// Streamable HTTP: one POST per message at one endpoint. A 2026-07-28 request
// mirrors its version, method and name into headers so that intermediaries can
// route without reading the body; the server checks that the two agree before
// it trusts either.

///|
/// The server as an ASGI application serving the MCP endpoint at `path`
/// (← FastMCP's `http_app`). Run it with mooncat, or mount it beside a moonapi
/// app.
///
/// Every message is its own POST, answered with one JSON object, or `202` for a
/// notification. Sessions, the `GET` stream and `DELETE` belong to the
/// revisions before 2026-07-28 and are optional there; this server keeps no
/// session, so `GET` and `DELETE` answer `405`.
///
/// A request whose `Origin` header names another site is refused with `403`, as
/// the transport requires against DNS rebinding. An origin passes when its host
/// is the request's own `Host`, a loopback address, or one listed in `origins`.
///
/// `debug_page` names a path the debug page is served at, beside the endpoint:
/// a browser opened on it lists what the server offers and calls it, in both
/// eras of the protocol. Nothing is served there unless you name the path, and
/// the path must differ from the endpoint's; the page is off by default and
/// never carries credentials of its own, so it is for development servers.
pub fn Server::to_asgi(
  self : Server,
  path~ : String = "/mcp",
  origins~ : Array[String] = [],
  debug_page? : String,
) -> @moonasgi.AsgiApp {
  (scope, receive, send) => {
    match scope {
      Http(hs) => {
        let body = read_body(receive)
        let (status, headers, payload) = match debug_page {
          Some(page) if page != path && at_page(hs.path, page) =>
            debug_reply(hs.http_method, debug_page_html(endpoint=path))
          _ => self.over_http(hs, body, path, origins)
        }
        send(HttpResponseStart(status~, headers~, trailers=false))
        send(HttpResponseBody(body=payload, more_body=false))
      }
      WebSocket(_) => send(WebSocketClose(code=1000, reason=""))
      Lifespan(_) =>
        while true {
          match receive() {
            LifespanStartup => send(LifespanStartupComplete)
            LifespanShutdown => {
              send(LifespanShutdownComplete)
              break
            }
            _ => break
          }
        }
    }
  }
}

///|
/// Whether `got` names `want`: the path as given, or with a trailing slash, as
/// a browser asks for a directory.
fn at_page(got : String, want : String) -> Bool {
  got == want || got == want + "/"
}

///|
/// The debug page for `GET`, its headers alone for `HEAD`, and `405` for
/// anything else. It goes out with `no-store`, so that a browser never shows a
/// listing from before the server's registrations changed.
fn debug_reply(
  http_method : String,
  page : String,
) -> (Int32, Array[(String, String)], Bytes) {
  let headers = [
    ("content-type", "text/html; charset=utf-8"),
    ("cache-control", "no-store"),
  ]
  match http_method {
    "GET" => (200, headers, @utf8.encode(page))
    "HEAD" => (200, headers, b"")
    _ =>
      (
        405,
        [("allow", "GET, HEAD"), ("content-type", "text/plain; charset=utf-8")],
        b"Method Not Allowed",
      )
  }
}

///|
async fn read_body(receive : @moonasgi.Receive) -> Bytes {
  let out = Buffer()
  while true {
    match receive() {
      HttpRequest(body~, more_body~) => {
        out.write_bytes(body)
        if !more_body {
          break
        }
      }
      _ => break
    }
  }
  out.to_bytes()
}

///|
async fn Server::over_http(
  self : Server,
  hs : @moonasgi.HttpScope,
  body : Bytes,
  path : String,
  origins : Array[String],
) -> (Int32, Array[(String, String)], Bytes) {
  let plain = [("content-type", "text/plain; charset=utf-8")]
  if hs.path != path && hs.path != path + "/" {
    return (404, plain, b"Not Found")
  }
  if header(hs.headers, "origin") is Some(origin) &&
    !allowed(origin, header(hs.headers, "host"), origins) {
    return (403, plain, b"Forbidden")
  }
  if hs.http_method != "POST" {
    return (405, [("allow", "POST"), ..plain], b"Method Not Allowed")
  }
  guard header(hs.headers, "content-type") is Some(kind) &&
    kind.to_lower().has_prefix("application/json") else {
    return (415, plain, b"Unsupported Media Type")
  }
  let message = @json.parse(@utf8.decode_lossy(body[:])) catch {
    _ =>
      return json_reply(
        400,
        refusal(Json::null(), fail(parse_error, "Parse error")).1,
      )
  }
  if message is Array(_) {
    return json_reply(
      400,
      refusal(Json::null(), fail(invalid_request, "Batches are not accepted")).1,
    )
  }
  let id = match message {
    Object(m) => m.get("id").unwrap_or(Json::null())
    _ => Json::null()
  }
  let modern = message is Object(m) &&
    m.get("params") is Some(Object(p)) &&
    era_of(p) is Modern(_)
  let refused = if modern {
    self.check_headers(hs.headers, message)
  } else {
    legacy_header(hs.headers, message)
  }
  if refused is Some(f) {
    return json_reply(400, refusal(id, f).1)
  }
  match self.answer(message) {
    None => (202, [], b"")
    Some((code, reply)) => {
      let status = match code {
        Some(c) if c == parse_error || c == invalid_request => 400
        Some(c) if modern && c >= unsupported_version && c <= header_mismatch =>
          400
        Some(c) if modern && c == method_not_found => 404
        _ => 200
      }
      json_reply(status, reply)
    }
  }
}

///|
fn json_reply(
  status : Int32,
  reply : Json,
) -> (Int32, Array[(String, String)], Bytes) {
  (
    status,
    [("content-type", "application/json")],
    @utf8.encode(reply.stringify()),
  )
}

///|
/// The first header named `name`; ASGI carries names in lower case.
fn header(headers : Array[(String, String)], name : String) -> String? {
  headers.iter().find_first(h => h.0 == name).map(h => h.1)
}

///|
/// Whether `origin` may call: the same host the request was sent to, a
/// loopback address, or one of `origins`.
fn allowed(origin : String, host : String?, origins : Array[String]) -> Bool {
  if origins.contains(origin) {
    return true
  }
  let rest = match origin.find("://") {
    Some(k) => origin.view(start_offset=k + 3).to_owned()
    None => return false
  }
  if host is Some(h) && rest == h {
    return true
  }
  let name = match rest.rev_find(":") {
    Some(k) if !rest.has_suffix("]") => rest.view(end_offset=k).to_owned()
    _ => rest
  }
  name is ("localhost" | "127.0.0.1" | "[::1]")
}

///|
/// The revisions before 2026-07-28 name their version in `MCP-Protocol-Version`
/// from 2025-06-18 on; one the server does not speak is refused. `initialize`
/// carries its version in the body instead.
fn legacy_header(headers : Array[(String, String)], message : Json) -> Fail? {
  if message is Object(m) && m.get("method") is Some(String("initialize")) {
    return None
  }
  match header(headers, "mcp-protocol-version") {
    Some(v) if !legacy_versions.contains(v) && !modern_versions.contains(v) =>
      Some(fail(invalid_request, "Unsupported protocol version: \{v}"))
    _ => None
  }
}

///|
/// The checks the 2026-07-28 transport makes before it trusts a request: the
/// version, method and name headers are there and say what the body says, and
/// so does every `Mcp-Param-*` header a tool's schema asks for.
fn Server::check_headers(
  self : Server,
  headers : Array[(String, String)],
  message : Json,
) -> Fail? {
  guard message is Object(m) &&
    m.get("method") is Some(String(op)) &&
    m.get("params") is Some(Object(params)) &&
    era_of(params) is Modern(version) else {
    return None
  }
  let mismatch = (what : String) => {
    Some(fail(header_mismatch, "Header mismatch: \{what}"))
  }
  match header(headers, "mcp-protocol-version") {
    Some(v) if v == version => ()
    Some(v) =>
      return mismatch(
        "MCP-Protocol-Version header value '\{v}' does not match body value '\{version}'",
      )
    None => return mismatch("MCP-Protocol-Version header is missing")
  }
  match header(headers, "mcp-method") {
    Some(v) if v == op => ()
    Some(v) =>
      return mismatch(
        "Mcp-Method header value '\{v}' does not match body value '\{op}'",
      )
    None => return mismatch("Mcp-Method header is missing")
  }
  let named = match op {
    "tools/call" | "prompts/get" => Some("name")
    "resources/read" => Some("uri")
    _ => None
  }
  if named is Some(field) {
    guard params.get(field) is Some(String(want)) else { return None }
    match header(headers, "mcp-name").map(decoded) {
      Some(Some(got)) if got == want => ()
      Some(_) =>
        return mismatch("Mcp-Name header does not match body value '\{want}'")
      None => return mismatch("Mcp-Name header is missing")
    }
  }
  if op == "tools/call" &&
    params.get("name") is Some(String(name)) &&
    self.tools.get(name) is Some(tool) {
    let args = match params.get("arguments") {
      Some(Object(a)) => Json(a)
      _ => Json::object(Map([]))
    }
    for mirrored in mirrored_params(tool.parameters, []) {
      let (label, route) = mirrored
      guard value_at(args, route) is Some(value) && !(value is Null) else {
        continue
      }
      let got = header(headers, "mcp-param-" + label.to_lower()).map(decoded)
      guard got is Some(Some(text)) && same_value(text, value) else {
        return mismatch(
          "Mcp-Param-\{label} header does not match the arguments",
        )
      }
    }
  }
  None
}

///|
/// A header value with the `=?base64?…?=` sentinel decoded; `None` when the
/// sentinel holds no valid Base64 or UTF-8.
fn decoded(value : String) -> String? {
  guard value.has_prefix("=?base64?") && value.has_suffix("?=") else {
    return Some(value)
  }
  let inner = value.view(start_offset=9, end_offset=value.length() - 2)
  let bytes = @base64.decode(inner) catch { _ => return None }
  try @utf8.decode(bytes[:]) catch {
    _ => None
  } noraise {
    text => Some(text)
  }
}

///|
/// Every `x-mcp-header` in `schema`, with the chain of `properties` keys that
/// leads to it; the annotation is only defined where that chain is all there
/// is.
fn mirrored_params(
  schema : Json,
  route : Array[String],
) -> Array[(String, Array[String])] {
  let out = []
  guard schema is Object(s) && s.get("properties") is Some(Object(props)) else {
    return out
  }
  for key, sub in props {
    let here = [..route, key]
    if sub is Object(o) && o.get("x-mcp-header") is Some(String(label)) {
      out.push((label, here))
    }
    for found in mirrored_params(sub, here) {
      out.push(found)
    }
  }
  out
}

///|
fn value_at(json : Json, route : Array[String]) -> Json? {
  let mut at = json
  for key in route {
    guard at is Object(o) && o.get(key) is Some(next) else { return None }
    at = next
  }
  Some(at)
}

///|
/// Whether a header value stands for `value`: a string as written, a boolean
/// as `true` or `false`, and a number compared as a number, so `42` and `42.0`
/// agree.
fn same_value(text : String, value : Json) -> Bool {
  match value {
    String(s) => text == s
    True => text == "true"
    False => text == "false"
    Number(n, ..) =>
      (@string.parse_double(text) catch { _ => return false }) == n
    _ => false
  }
}
