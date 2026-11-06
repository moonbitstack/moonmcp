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
///
/// A stream that closes before the reply arrives is asked for again with a
/// `GET` carrying `Last-Event-ID`, after waiting the number of milliseconds the
/// stream's `retry` field asked for (SEP-1699): that is how a server that keeps
/// a tool's answer for later hands it over.
///
/// `token` is read before each message and sent as the bearer when it gives
/// one; `renew` is called when the server answers `401` or `403`, with the
/// status and the `WWW-Authenticate` header, and the message is sent once more
/// when it says a new token was obtained.
pub struct Http {
  url : String
  version : String
  token : () -> String?
  renew : (async (Int32, String) -> Bool)?
  session : Ref[String?]
  priv beside : Ref[Beside?]
  last_event : Ref[String?]
  retry_ms : Ref[Int32]
  answer : Ref[(async (Json) -> Json?)?]
}

///|
/// Connect to `url`, an endpoint such as `http://127.0.0.1:12000/mcp`. A stream
/// that does not say how long to wait before coming back is waited on for a
/// second, the browser default for `EventSource`.
pub fn Http::new(
  url : String,
  version~ : String = "2026-07-28",
  token? : () -> String?,
  renew? : async (Int32, String) -> Bool,
) -> Http {
  {
    url,
    version,
    token: token.unwrap_or(fn() -> String? { None }),
    renew,
    session: Ref(None),
    beside: Ref(None),
    last_event: Ref(None),
    retry_ms: Ref(1000),
    answer: Ref(None),
  }
}

///|
/// One message in, one reply out, with the authorization retry around it.
pub impl @client.Transport for Http with fn ask(
  self : Http,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Json {
  let mut sent = self.exchange(message, on_notification)
  if (sent.status == 401 || sent.status == 403) && self.renew is Some(_) {
    let challenge = sent.challenge.unwrap_or("")
    let renewed = self.renew.unwrap()(sent.status, challenge) catch {
      _ => false
    }
    if renewed {
      sent = self.exchange(message, on_notification)
    }
  }
  sent.reply
}

///|
/// A notification is one POST, with nothing read back beyond the status.
pub impl @client.Transport for Http with fn tell(self : Http, message : Json) -> Unit {
  let client = @net.Client::Client(origin_of(self.url)) catch { _ => return }
  defer client.close()
  let response = client.post(
    path_of(self.url),
    @utf8.encode(message.stringify()),
    extra_headers=self.headers_for(message),
  ) catch {
    _ => return
  }
  self.remember_session(response.headers)
  ignore(read_body(client) catch { _ => b"" })
}

///|
/// Open a subscription and hand every message on it to `on_notification` until
/// the server ends the stream.
pub impl @client.Transport for Http with fn listen(
  self : Http,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Unit {
  let client = @net.Client::Client(origin_of(self.url)) catch { _ => return }
  defer client.close()
  let headers = self.headers_for(message)
  headers["accept"] = "text/event-stream"
  let response = client.post(
    path_of(self.url),
    @utf8.encode(message.stringify()),
    extra_headers=headers,
  ) catch {
    _ => return
  }
  self.remember_session(response.headers)
  if response.code >= 400 {
    return
  }
  while true {
    let frame = read_frame(client) catch { _ => None }
    guard frame is Some(frame) else { return }
    guard frame.data is Some(text) else { continue }
    let parsed : Json? = try @json.parse(text) catch {
      _ => None
    } noraise {
      json => Some(json)
    }
    guard parsed is Some(message) else { continue }
    if is_reply(message) {
      return
    }
    self.dispatch(message, on_notification)
  }
}

///|
/// There is nothing kept open between messages: each one opens and closes its
/// own connection.
pub impl @client.Transport for Http with fn close(self : Http) -> Unit {
  match self.beside.val {
    Some(Offered(client)) => client.close()
    _ => ()
  }
  self.beside.val = None
}

///|
/// Where a request the server makes goes.
pub impl @client.Transport for Http with fn answer_with(
  self : Http,
  answer : async (Json) -> Json?,
) -> Unit {
  self.answer.val = Some(answer)
}

///|
/// What one exchange came back with: the status, the challenge if the server
/// sent one, and the reply — a JSON-RPC error object when the status was bad.
priv struct Sent {
  status : Int32
  challenge : String?
  reply : Json
}

///|
/// Post `message` and read what comes back, following an SSE stream to its
/// reply and reopening it once when it closes early.
async fn Http::exchange(
  self : Http,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Sent {
  // A stateful server sends the questions it has for this client on the one
  // stream it keeps beside the session — the `GET` one. It is opened before the
  // message goes out, because a question asked while no stream is there has
  // nowhere to go.
  let beside = self.beside_stream(message)
  let client = @net.Client::Client(origin_of(self.url)) catch {
    e => return bad_reply(-32603, "\{e}")
  }
  defer client.close()
  let headers = self.headers_for(message)
  let response = client.post(
    path_of(self.url),
    @utf8.encode(message.stringify()),
    extra_headers=headers,
  ) catch {
    e => return bad_reply(-32603, "\{e}")
  }
  let status = response.code
  self.remember_session(response.headers)
  let challenge = header_of(response.headers, "www-authenticate")
  if status >= 400 && status != 200 {
    // A refused request still carries a JSON-RPC error body when the server
    // had one to give, and a bare status when it did not.
    let body = read_body(client) catch { _ => b"" }
    let parsed : Json? = try @json.parse(@utf8.decode_lossy(body[:])) catch {
      _ => None
    } noraise {
      json => Some(json)
    }
    let reply = match parsed {
      Some(reply) if is_reply(reply) => reply
      _ =>
        {
          "jsonrpc": "2.0",
          "id": Json::null(),
          "error": {
            "code": Json::number(-32603.0),
            "message": Json::string("HTTP \{status}: \{response.reason}"),
          },
        }
    }
    return { status, challenge, reply, }
  }
  let streamed = match header_of(response.headers, "content-type") {
    Some(kind) => kind.contains("text/event-stream")
    None => false
  }
  if !streamed {
    let body = read_body(client) catch { _ => b"" }
    let parsed : Json? = try @json.parse(@utf8.decode_lossy(body[:])) catch {
      _ => None
    } noraise {
      json => Some(json)
    }
    let reply = match parsed {
      Some(reply) => reply
      None => bad_reply(-32700, "The reply is not JSON").reply
    }
    return { status, challenge, reply, }
  }
  let reply = match beside {
    Some(_) => self.follow_beside(client, beside, on_notification)
    None => self.follow(client, on_notification)
  }
  match reply {
    Some(reply) => { status, challenge, reply, }
    None => self.reopen(on_notification)
  }
}

///|
/// The stream a stateful server keeps beside the session. There is one per
/// session and it stays open — a server refuses a second one — so it is opened
/// the first time it is needed and read a little on each exchange.
async fn Http::beside_stream(self : Http, message : Json) -> @net.Client? {
  guard !is_initialize(message) && self.session.val is Some(_) else {
    return None
  }
  match self.beside.val {
    Some(Offered(client)) => Some(client)
    Some(Absent) => None
    None => {
      let opened = self.open_beside(message)
      match opened {
        Some(client) => self.beside.val = Some(Offered(client))
        None => self.beside.val = Some(Absent)
      }
      opened
    }
  }
}

///|
/// Whether a `GET` was offered for this session: kept, refused, or not asked
/// yet.
priv enum Beside {
  Offered(@net.Client)
  Absent
}

///|
/// Open the stream a stateful server keeps beside the session. The body is left
/// unread: the caller reads it beside the answer.
async fn Http::open_beside(self : Http, message : Json) -> @net.Client? {
  ignore(message)
  let client = @net.Client::Client(origin_of(self.url)) catch {
    _ => return None
  }
  let headers : @net.Headers = {
    "accept": "text/event-stream",
    "mcp-protocol-version": self.version,
  }
  match self.session.val {
    Some(session) => headers["mcp-session-id"] = session
    None => ()
  }
  match (self.token)() {
    Some(token) => headers["authorization"] = "Bearer " + token
    None => ()
  }
  let response = client.get(path_of(self.url), extra_headers=headers) catch {
    _ => {
      client.close()
      return None
    }
  }
  let streamed = match header_of(response.headers, "content-type") {
    Some(kind) => kind.contains("text/event-stream")
    None => false
  }
  if response.code != 200 || !streamed {
    client.close()
    return None
  }
  Some(client)
}

///|
/// Read the answer on the message's own stream while a task reads the stream
/// beside the session: a question from the server arrives on the latter, and
/// the answer to it has to go back before the former can finish.
async fn Http::follow_beside(
  self : Http,
  client : @net.Client,
  beside : @net.Client?,
  on_notification : async (Json) -> Unit,
) -> Json? {
  guard beside is Some(beside) else {
    return self.follow(client, on_notification)
  }
  let answer : Ref[Json?] = Ref(None)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      self.read_beside(beside, on_notification)
    })
    answer.val = self.follow(client, on_notification)
  })
  answer.val
}

///|
/// Read the stream beside the session until it closes or this task is
/// cancelled, answering whatever the server asks on it.
async fn Http::read_beside(
  self : Http,
  client : @net.Client,
  on_notification : async (Json) -> Unit,
) -> Unit {
  while true {
    let frame = read_frame(client) catch { _ => break }
    guard frame is Some(frame) else { break }
    self.remember_frame(frame)
    guard frame.data is Some(text) else { continue }
    let parsed : Json? = try @json.parse(text) catch {
      _ => None
    } noraise {
      json => Some(json)
    }
    guard parsed is Some(message) else { continue }
    if is_reply(message) {
      // An answer to a question this side asked; its caller is elsewhere.
      continue
    }
    self.dispatch(message, on_notification)
  }
  // The stream is over: the next exchange opens another one.
  self.beside.val = None
}

///|
/// Whether `message` is the handshake, which is what brings a session into
/// being: there is no stream beside one yet.
fn is_initialize(message : Json) -> Bool {
  match @server.method_of(message) {
    Some("initialize") => true
    _ => false
  }
}

///|
/// Read an SSE stream until the reply arrives; `None` when the stream ends
/// first, which is the server saying to come back.
async fn Http::follow(
  self : Http,
  client : @net.Client,
  on_notification : async (Json) -> Unit,
) -> Json? {
  while true {
    let frame = read_frame(client) catch { _ => None }
    guard frame is Some(frame) else { return None }
    self.remember_frame(frame)
    guard frame.data is Some(text) else { continue }
    let parsed : Json? = try @json.parse(text) catch {
      _ => None
    } noraise {
      json => Some(json)
    }
    guard parsed is Some(message) else { continue }
    if is_reply(message) {
      return Some(message)
    }
    self.dispatch(message, on_notification)
  }
  None
}

///|
/// Come back for the reply the stream did not carry: wait what the stream asked
/// for, `GET` the endpoint with `Last-Event-ID`, and read on.
async fn Http::reopen(
  self : Http,
  on_notification : async (Json) -> Unit,
) -> Sent {
  @async.sleep(self.retry_ms.val)
  let client = @net.Client::Client(origin_of(self.url)) catch {
    e => return bad_reply(-32603, "\{e}")
  }
  defer client.close()
  let headers : @net.Headers = {
    "accept": "text/event-stream",
    "mcp-protocol-version": self.version,
  }
  match (self.token)() {
    Some(token) => headers["authorization"] = "Bearer " + token
    None => ()
  }
  match self.last_event.val {
    Some(id) => headers["last-event-id"] = id
    None => ()
  }
  match self.session.val {
    Some(session) => headers["mcp-session-id"] = session
    None => ()
  }
  let response = client.get(path_of(self.url), extra_headers=headers) catch {
    e => return bad_reply(-32603, "\{e}")
  }
  self.remember_session(response.headers)
  let mut reply : Json? = None
  while reply is None {
    let frame = read_frame(client) catch { _ => None }
    guard frame is Some(frame) else { break }
    self.remember_frame(frame)
    guard frame.data is Some(text) else { continue }
    let parsed : Json? = try @json.parse(text) catch {
      _ => None
    } noraise {
      json => Some(json)
    }
    guard parsed is Some(message) else { continue }
    if is_reply(message) {
      reply = Some(message)
    } else {
      self.dispatch(message, on_notification)
    }
  }
  match reply {
    Some(reply) => { status: 200, challenge: None, reply, }
    None => bad_reply(-32603, "The stream ended without a reply")
  }
}

///|
/// Keep what a reconnection needs to know: the last event's id, and how long
/// the server asked to be left alone.
fn Http::remember_frame(self : Http, frame : Frame) -> Unit {
  match frame.id {
    Some(id) => self.last_event.val = Some(id)
    None => ()
  }
  match frame.retry {
    Some(ms) => self.retry_ms.val = ms
    None => ()
  }
}

///|
/// Hand a message from a stream to the client when it asks something, and to
/// `on_notification` otherwise.
async fn Http::dispatch(
  self : Http,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Unit {
  guard @server.request_id_of(message) is Some(_) &&
    @server.method_of(message) is Some(_) else {
    on_notification(message)
    return
  }
  match self.answer.val {
    Some(answer) => {
      let reply = answer(message) catch { _ => None }
      match reply {
        Some(reply) => self.reply_with(reply)
        None => on_notification(message)
      }
    }
    None => on_notification(message)
  }
}

///|
/// Send a reply the server asked for on the same endpoint.
async fn Http::reply_with(self : Http, reply : Json) -> Unit {
  let client = @net.Client::Client(origin_of(self.url)) catch { _ => return }
  defer client.close()
  let headers : @net.Headers = {
    "content-type": "application/json",
    "accept": "application/json, text/event-stream",
    "mcp-protocol-version": self.version,
  }
  match self.session.val {
    Some(session) => headers["mcp-session-id"] = session
    None => ()
  }
  let response = client.post(
    path_of(self.url),
    @utf8.encode(reply.stringify()),
    extra_headers=headers,
  ) catch {
    _ => return
  }
  ignore(response)
}

///|
/// The headers every message of this connection carries.
fn Http::headers_for(self : Http, message : Json) -> @net.Headers {
  let operation = @server.method_of(message).unwrap_or("")
  let headers : @net.Headers = {
    "content-type": "application/json",
    "accept": "application/json, text/event-stream",
    "mcp-protocol-version": self.version,
    "mcp-method": operation,
  }
  match @server.params_of(message).get("name") {
    Some(String(name)) if operation == "tools/call" ||
      operation == "prompts/get" => headers["mcp-name"] = name
    _ => ()
  }
  match @server.params_of(message).get("uri") {
    Some(String(uri)) if operation == "resources/read" =>
      headers["mcp-name"] = uri
    _ => ()
  }
  match (self.token)() {
    Some(token) => headers["authorization"] = "Bearer " + token
    None => ()
  }
  match self.session.val {
    Some(session) => headers["mcp-session-id"] = session
    None => ()
  }
  headers
}

///|
/// Keep the session the server named, so that later messages join it.
fn Http::remember_session(self : Http, headers : @net.Headers) -> Unit {
  match header_of(headers, "mcp-session-id") {
    Some(session) => self.session.val = Some(session)
    None => ()
  }
}

///|
/// One field of a header map, whatever its case.
fn header_of(headers : @net.Headers, name : String) -> String? {
  for pair in headers {
    if pair.0.to_string().to_lower() == name.to_lower() {
      return Some(pair.1)
    }
  }
  None
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
/// Whether a stream message answers the request rather than reporting on it.
fn is_reply(message : Json) -> Bool {
  match message {
    Object(obj) => obj.contains("result") || obj.contains("error")
    _ => false
  }
}

///|
/// One event of an SSE stream: the `data:` lines joined, and the `id` and
/// `retry` fields that came with it.
priv struct Frame {
  data : String?
  id : String?
  retry : Int32?
}

///|
/// The next event on an SSE stream. `None` at the end of the stream.
///
/// An event that carries only `id` and `retry` — the priming event a stream
/// opens with — comes back with `data` unset and is still an event: it is what
/// a reconnection has to remember.
async fn read_frame(client : @net.Client) -> Frame? {
  let data = StringBuilder::StringBuilder()
  let mut started = false
  let mut id : String? = None
  let mut retry : Int32? = None
  let mut seen = false
  while true {
    let line = client.read_until("\n") catch { _ => return None }
    guard line is Some(line) else { return None }
    let line = line.trim(chars="\r\n").to_owned()
    if line.is_empty() {
      if seen {
        return Some({
          data: if started {
            Some(data.to_string())
          } else {
            None
          },
          id,
          retry,
        })
      }
      continue
    }
    if line.has_prefix("data:") {
      seen = true
      if started {
        data.write_char('\n')
      }
      started = true
      data.write_string(line.exact_view(start=5).to_owned())
    } else if line.has_prefix("id:") {
      seen = true
      id = Some(line.exact_view(start=3).to_owned().trim(chars=" ").to_owned())
    } else if line.has_prefix("retry:") {
      seen = true
      let text = line.exact_view(start=6).to_owned().trim(chars=" ").to_owned()
      match digits_of(text) {
        Some(ms) if ms > 0 => retry = Some(ms)
        _ => ()
      }
    }
  }
  None
}

///|
/// The number `text` is, when it is one.
fn digits_of(text : String) -> Int32? {
  let parsed : Json? = try @json.parse(text) catch {
    _ => None
  } noraise {
    json => Some(json)
  }
  match parsed {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
/// A reply for a failure this client made up, so that a caller sees the same
/// shape as a refusal from the server.
fn bad_reply(code : Int32, message : String) -> Sent {
  {
    status: 200,
    challenge: None,
    reply: {
      "jsonrpc": "2.0",
      "id": Json::null(),
      "error": {
        "code": Json::number(code.to_double()),
        "message": Json::string(message),
      },
    },
  }
}

///|
pub extend Http with @client.Transport::{ask, tell, listen, close, answer_with}
