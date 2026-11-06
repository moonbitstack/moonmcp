// The three requests an OAuth client makes over HTTP: fetch a document, post a
// form, post JSON. One connection each — a flow makes a handful of them, and
// nothing here is on a hot path.

///|
/// What an exchange came back with.
pub struct Reply {
  code : Int32
  headers : @net.Headers
  body : String
}

///|
/// Whether the exchange was answered with success.
pub fn Reply::ok(self : Reply) -> Bool {
  self.code >= 200 && self.code < 300
}

///|
/// The first header named `name`, whatever its case.
pub fn Reply::header(self : Reply, name : String) -> String? {
  for pair in self.headers {
    if pair.0.to_string().to_lower() == name.to_lower() {
      return Some(pair.1)
    }
  }
  None
}

///|
/// Fetch `url`.
pub async fn get(url : String) -> Reply raise @auth.Refused {
  let client = connect(url)
  defer client.close()
  let response = client.get(@auth.target_of(url)) catch {
    e => raise @auth.Refused(message="\{url}: \{e}")
  }
  let body = read_body(client)
  { code: response.code, headers: response.headers, body, }
}

///|
/// Post `body` to `url` as `kind`, with `authorization` when the token endpoint
/// wants one.
pub async fn post(
  url : String,
  body : String,
  kind~ : String = "application/x-www-form-urlencoded",
  authorization? : String,
) -> Reply raise @auth.Refused {
  let headers : @net.Headers = {
    "content-type": kind,
    "accept": "application/json",
  }
  match authorization {
    Some(value) => headers["authorization"] = value
    None => ()
  }
  let client = connect(url)
  defer client.close()
  let response = client.post(
    @auth.target_of(url),
    @utf8.encode(body),
    extra_headers=headers,
  ) catch {
    e => raise @auth.Refused(message="\{url}: \{e}")
  }
  let body = read_body(client)
  { code: response.code, headers: response.headers, body, }
}

///|
/// A connection to the origin of `url`: the path travels with each request.
async fn connect(url : String) -> @net.Client raise @auth.Refused {
  @net.Client::Client(@auth.origin_of(url)) catch {
    e => raise @auth.Refused(message="\{url}: \{e}")
  }
}

///|
/// The whole body, however it is chunked.
async fn read_body(client : @net.Client) -> String raise @auth.Refused {
  let out = Buffer()
  while true {
    let chunk = client.read_some() catch {
      e => raise @auth.Refused(message="the reply stopped early: \{e}")
    }
    guard chunk is Some(chunk) else { break }
    out.write_bytes(chunk)
  }
  @utf8.decode_lossy(out.to_bytes()[:])
}

///|
/// `reply` read as JSON.
pub fn json_of(reply : Reply) -> Json raise @auth.Refused {
  try @json.parse(reply.body) catch {
    _ => raise @auth.Refused(message="the reply is not JSON: \{reply.body}")
  } noraise {
    json => json
  }
}
