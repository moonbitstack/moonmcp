// The HTTP transport: one POST per message, an ordinary JSON body or an SSE
// stream in answer, as the 2026-07-28 transport allows.

///|
/// A client over Streamable HTTP (← the transport of the same name).
///
/// Every message is a POST to `url` with the request metadata headers the
/// revision asks for. The reply is read as `application/json`, or as
/// `text/event-stream` when the server chose to stream: the notifications on
/// that stream are handed to the caller and the message that ends it is the
/// reply.
pub struct Http {
  client : @net.Client
  url : String
  version : String
}

///|
/// Connect to `url`, an endpoint such as `http://127.0.0.1:12000/mcp`.
pub async fn Http::new(url : String, version~ : String = "2026-07-28") -> Http {
  // The HTTP client takes the origin; the path travels with each request.
  let client = @net.Client::Client(origin_of(url))
  { client, url, version, }
}

///|
/// The scheme and authority of `url`, without its path: what a connection is
/// opened to.
fn origin_of(url : String) -> String {
  match url.find("://") {
    Some(k) =>
      match url.exact_view(start=k + 3).to_owned().find("/") {
        Some(slash) => url.exact_view(end=k + 3 + slash).to_owned()
        None => url
      }
    None => url
  }
}

///|
pub impl @client.Transport for Http with fn ask(
  self : Http,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Json {
  let operation = @server.method_of(message).unwrap_or("")
  let path = path_of(self.url)
  let headers : @net.Headers = {
    "content-type": "application/json",
    "accept": "application/json, text/event-stream",
    "mcp-protocol-version": self.version,
    "mcp-method": operation,
  }
  match operation {
    "tools/call" | "prompts/get" =>
      match @server.params_of(message).get("name") {
        Some(String(name)) => headers["mcp-name"] = name
        _ => ()
      }
    "resources/read" =>
      match @server.params_of(message).get("uri") {
        Some(String(uri)) => headers["mcp-name"] = uri
        _ => ()
      }
    _ => ()
  }
  let response = self.client.post(
    path,
    @utf8.encode(message.stringify()),
    extra_headers=headers,
  )
  if response.code >= 400 && response.code != 200 {
    // A refused request still carries a JSON-RPC error body when the server
    // had one to give, and a bare status when it did not.
    let body = read_body(self.client)
    let parsed : Json? = try @json.parse(@utf8.decode_lossy(body[:])) catch {
      _ => None
    } noraise {
      json => Some(json)
    }
    match parsed {
      Some(reply) => return reply
      None =>
        return {
          "jsonrpc": "2.0",
          "id": Json::null(),
          "error": {
            "code": Json::number(-32603.0),
            "message": Json::string("HTTP \{response.code}: \{response.reason}"),
          },
        }
    }
  }
  let streamed = match response.headers.get("content-type") {
    Some(kind) => kind.contains("text/event-stream")
    None => false
  }
  if !streamed {
    let body = read_body(self.client)
    let parsed : Json? = try @json.parse(@utf8.decode_lossy(body[:])) catch {
      _ => None
    } noraise {
      json => Some(json)
    }
    return match parsed {
      Some(reply) => reply
      None =>
        {
          "jsonrpc": "2.0",
          "id": Json::null(),
          "error": {
            "code": Json::number(-32700.0),
            "message": Json::string("The reply is not JSON"),
          },
        }
    }
  }
  let mut reply : Json? = None
  while reply is None {
    let frame = read_frame(self.client) catch { _ => None }
    guard frame is Some(message) else { break }
    if is_reply(message) {
      reply = Some(message)
    } else {
      on_notification(message)
    }
  }
  match reply {
    Some(reply) => reply
    None =>
      {
        "jsonrpc": "2.0",
        "id": Json::null(),
        "error": {
          "code": Json::number(-32603.0),
          "message": Json::string("The stream ended without a reply"),
        },
      }
  }
}

///|
pub impl @client.Transport for Http with fn tell(self : Http, message : Json) -> Unit {
  let operation = @server.method_of(message).unwrap_or("")
  let headers : @net.Headers = {
    "content-type": "application/json",
    "mcp-protocol-version": self.version,
    "mcp-method": operation,
  }
  let response = self.client.post(
    path_of(self.url),
    @utf8.encode(message.stringify()),
    extra_headers=headers,
  )
  ignore(response)
  ignore(read_body(self.client))
}

///|
pub impl @client.Transport for Http with fn listen(
  self : Http,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Unit {
  let response = self.client.post(
    path_of(self.url),
    @utf8.encode(message.stringify()),
    extra_headers={
      "content-type": "application/json",
      "accept": "text/event-stream",
      "mcp-protocol-version": self.version,
      "mcp-method": @types.method_subscriptions_listen,
    },
  )
  ignore(response)
  while true {
    let frame = read_frame(self.client) catch { _ => None }
    guard frame is Some(message) else { break }
    if is_reply(message) {
      return
    }
    on_notification(message)
  }
}

///|
pub impl @client.Transport for Http with fn close(self : Http) -> Unit {
  self.client.close()
}

///|
/// The whole body of a reply, however it is chunked.
async fn read_body(client : @net.Client) -> Bytes {
  let out = Buffer()
  while true {
    let chunk = client.read_some() catch { _ => None }
    guard chunk is Some(chunk) else { break }
    out.write_bytes(chunk)
  }
  out.to_bytes()
}

///|
/// The path part of a URL, which is what the request line carries.
fn path_of(url : String) -> String {
  match url.find("://") {
    Some(k) =>
      match url.exact_view(start=k + 3).to_owned().find("/") {
        Some(slash) => url.exact_view(start=k + 3 + slash).to_owned()
        None => "/"
      }
    None => url
  }
}

///|
/// Whether a stream message answers the request rather than reporting on it.
fn is_reply(message : Json) -> Bool {
  match message {
    Object(obj) => obj.contains("result") || obj.contains("error")
    _ => false
  }
}

///|
/// The next message on an SSE stream: the `data:` lines of one event, joined,
/// read as JSON. `None` at the end of the stream.
async fn read_frame(client : @net.Client) -> Json? {
  let data = StringBuilder::StringBuilder()
  let mut seen = false
  while true {
    let line = client.read_until("\n") catch { _ => return None }
    guard line is Some(line) else { return None }
    let line = line.trim(chars=" \t\r\n").to_owned()
    if line.is_empty() {
      if seen {
        let parsed : Json? = try @json.parse(data.to_string()) catch {
          _ => None
        } noraise {
          json => Some(json)
        }
        return parsed
      }
      continue
    }
    if line.has_prefix("data:") {
      seen = true
      let payload = line.exact_view(start=5).to_owned()
      data.write_string(payload.trim(chars=" ").to_owned())
    }
  }
  None
}

///|
pub extend Http with @client.Transport::{ask, tell, listen, close}
