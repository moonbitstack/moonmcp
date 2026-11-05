// Streamable HTTP: one POST per message at one endpoint. A 2026-07-28 request
// mirrors its version, method and name into headers so that intermediaries can
// route without reading the body; the server checks that the two agree before
// it trusts either.
//
// A request that has something to say before its answer — progress reports, a
// log line, or a subscription that stays open — is answered with an SSE stream
// instead of one JSON object. Which of the two a client gets is decided before
// the message is served, from what the request asks for and what it accepts.

///|
/// The server as an ASGI application serving the MCP endpoint at `path`
/// (← FastMCP's `http_app`). Run it with mooncat, or mount it beside a moonapi
/// app.
///
/// Every message is its own POST, answered with one JSON object, or `202` for a
/// notification. This server keeps no session, so `DELETE` answers `405`.
///
/// A 2026-07-28 request that offers a progress token, or that opens a
/// subscription, is answered with `text/event-stream` when the client accepts
/// it: the notifications the handler sends arrive on that stream, and the
/// reply ends it.
///
/// Under the revisions before, a request becomes a stream the moment its handler
/// has something to send, and stays one JSON object when it has nothing. A `GET`
/// that accepts `text/event-stream` opens the stream those revisions hear list
/// changes and subscribed resources on; with no session to tie it to, every such
/// stream hears the updates to anything a client has subscribed to.
///
/// A request whose `Origin` header names another site is refused with `403`, as
/// the transport requires against DNS rebinding. An origin passes when its host
/// is the request's own `Host`, a loopback address, or one listed in `origins`.
///
/// `Host` is checked as well, since a rebound name reaches a local server with a
/// `Host` that is not its own. `hosts` lists the names this server answers to; left
/// out, a server listening on a loopback address answers to loopback names only,
/// and one listening anywhere else takes any. A reverse proxy in front of a
/// loopback listener has to name the public host here.
///
/// `docs` names the path the documentation page is served at, beside the
/// endpoint: a browser opened on it lists what the server offers and calls it,
/// in both eras of the protocol. It is on at `/docs` unless told otherwise, as
/// an API framework's interactive docs are; `docs=None` leaves it off, and a
/// path equal to the endpoint's is ignored. `theme` picks its look, the moonmcp
/// website's by default. The page carries no credentials of its own.
pub fn Server::to_asgi(
  self : Server,
  path~ : String = "/mcp",
  origins~ : Array[String] = [],
  hosts? : Array[String],
  docs~ : String? = Some("/docs"),
  theme~ : @docs.Theme = @docs.theme,
  auth? : @auth.Bearer,
) -> @moonasgi.AsgiApp {
  (scope, receive, send) => {
    match scope {
      Http(hs) => {
        let body = read_body(receive)
        let page = match docs {
          Some(page) if page != path && at_page(hs.path, page) => Some(page)
          _ => None
        }
        match page {
          Some(_) => {
            let (status, headers, payload) = page_reply(
              hs.http_method,
              @docs.page(endpoint=path, theme~),
            )
            send(HttpResponseStart(status~, headers~, trailers=false))
            send(HttpResponseBody(body=payload, more_body=false))
          }
          None =>
            self.over_http(hs, body, path, origins, hosts, send, receive, auth)
        }
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
/// The documentation page for `GET`, its headers alone for `HEAD`, and `405`
/// for anything else. It goes out with `no-store`, so that a browser never shows a
/// listing from before the server's registrations changed.
fn page_reply(
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
  hosts : Array[String]?,
  send : @moonasgi.Send,
  receive : @moonasgi.Receive,
  auth : @auth.Bearer?,
) -> Unit {
  let plain = [("content-type", "text/plain; charset=utf-8")]
  if hs.path != path && hs.path != path + "/" {
    return reply_json(send, 404, plain, b"Not Found")
  }
  if header(hs.headers, "origin") is Some(origin) &&
    !allowed(origin, header(hs.headers, "host"), origins) {
    return reply_json(send, 403, plain, b"Forbidden")
  }
  if !host_allowed(header(hs.headers, "host"), hosts, hs.server) {
    return reply_json(send, 403, plain, b"Forbidden")
  }
  let listening = hs.http_method == "GET" &&
    accepts_event_stream(hs.headers) &&
    !(header(hs.headers, "mcp-protocol-version") is Some(version) &&
    modern_versions.contains(version))
  if hs.http_method != "POST" && !listening {
    return reply_json(
      send,
      405,
      [("allow", "GET, POST"), ..plain],
      b"Method Not Allowed",
    )
  }
  if !listening {
    guard header(hs.headers, "content-type") is Some(kind) &&
      kind.to_lower().has_prefix("application/json") else {
      return reply_json(send, 415, plain, b"Unsupported Media Type")
    }
  }
  // The token is checked before the body is read: a caller who is not allowed
  // in learns nothing about the request, not even whether it parses.
  let principal = match auth {
    Some(bearer) =>
      match header(hs.headers, "authorization") {
        Some(value) =>
          match bearer.check(value) {
            Ok(principal) => Some(principal)
            Err(reason) => return challenge(send, reason)
          }
        None => return challenge(send, "a bearer token is required")
      }
    None => None
  }
  if listening {
    return self.listen_http(send, receive)
  }
  let message = @json.parse(@utf8.decode_lossy(body[:])) catch {
    _ =>
      return json_reply(
        send,
        400,
        refusal(Json::null(), fail(parse_error, "Parse error")).1,
      )
  }
  if message is Array(_) {
    return json_reply(
      send,
      400,
      refusal(Json::null(), fail(invalid_request, "Batches are not accepted")).1,
    )
  }
  let id = match message {
    Object(m) => m.get("id").unwrap_or(Json::null())
    _ => Json::null()
  }
  let modern = match message {
    Object(m) => m.get("params") is Some(Object(p)) && era_of(p) is Modern(_)
    _ => false
  }
  let refused = if modern {
    self.check_headers(hs.headers, message)
  } else {
    legacy_header(hs.headers, message)
  }
  if refused is Some(f) {
    return json_reply(send, 400, refusal(id, f).1)
  }
  self.serve_http(hs, message, send, principal, modern)
}

///|
/// The status of a reply that goes out as one JSON object.
fn status_of(code : Int32?, modern : Bool) -> Int32 {
  match code {
    Some(c) if c == parse_error || c == invalid_request => 400
    Some(c) if modern && c >= unsupported_version && c <= header_mismatch => 400
    Some(c) if modern && c == method_not_found => 404
    _ => 200
  }
}

///|
/// Whether the request has anything to send beside its answer, which is what
/// makes the answer a stream: a progress token, or a subscription that stays
/// open until the client lets go.
fn streams(message : Json) -> Bool {
  match method_of(message) {
    Some(op) if op == @types.method_subscriptions_listen => true
    _ =>
      params_of(message).get("_meta") is Some(Object(meta)) &&
      meta.get("progressToken") is Some(_)
  }
}

///|
/// Whether the client will take an SSE stream: the transport has it list both
/// content types, and this server honours the listing rather than ignoring it.
fn accepts_event_stream(headers : Array[(String, String)]) -> Bool {
  match header(headers, "accept") {
    Some(accept) => accept.contains("text/event-stream")
    None => false
  }
}

///|
let sse_headers : Array[(String, String)] = [
  ("content-type", "text/event-stream"),
  ("cache-control", "no-store"),
  ("x-accel-buffering", "no"),
]

///|
/// Serve one request and send its reply: as one JSON object, or as an SSE stream of the messages its
/// handler sends and then the reply.
///
/// A 2026-07-28 request says in advance which it wants. A request of the revisions before does not,
/// so its stream starts at the first thing there is to send, and one with nothing to send stays a
/// plain reply with a proper status.
///
/// A write that fails means the client has gone; the handler sees that through the context's own
/// notice, which is what closes the connection in this revision, rather than any cancellation message.
async fn Server::serve_http(
  self : Server,
  hs : @moonasgi.HttpScope,
  message : Json,
  send : @moonasgi.Send,
  principal : @auth.Principal?,
  modern : Bool,
) -> Unit {
  let accepts = accepts_event_stream(hs.headers)
  let eager = modern && accepts && streams(message)
  let can_stream = eager || (accepts && !modern)
  let mut started = false
  let mut alive = true
  let begin = async fn() {
    if !started {
      started = true
      send(HttpResponseStart(status=200, headers=sse_headers, trailers=false))
    }
  }
  if eager {
    begin()
  }
  let frame = async fn(out : Json) {
    if !can_stream || !alive {
      return
    }
    begin() catch {
      _ => {
        alive = false
        return
      }
    }
    send(HttpResponseBody(body=@utf8.encode(sse_frame(out)), more_body=true)) catch {
      _ => alive = false
    }
  }
  let channel = Channel::new(
    emit=frame,
    headers=header_map(hs.headers),
    gone=fn() { !alive },
    subject?=principal.bind(principal => principal.subject),
    claims=principal.map(principal => principal.claims).unwrap_or(Map([])),
    asks=can_stream && !modern,
  )
  let answer : (Int32?, Json)? = match method_of(message) {
    Some(op) if eager && op == @types.method_subscriptions_listen =>
      match request_id_of(message) {
        Some(id) => {
          self.serve_subscription(id, params_of(message), channel) catch {
            _ => ()
          }
          let closed : Json = {
            "jsonrpc": "2.0",
            "id": id,
            "result": subscription_closed_result(id),
          }
          Some((None, closed))
        }
        None => None
      }
    _ => self.answer(message, channel~)
  }
  if started {
    if answer is Some((_, reply)) {
      frame(reply) catch {
        _ => ()
      }
    }
    send(HttpResponseBody(body=b"", more_body=false)) catch {
      _ => ()
    }
  } else {
    match answer {
      None => reply_json(send, 202, [], b"")
      Some((code, reply)) => json_reply(send, status_of(code, modern), reply)
    }
  }
}

///|
/// The `GET` stream of the revisions before 2026-07-28: every list change, and updates to subscribed
/// resources, until the client goes away. Only that going away ends it, so a task sits waiting for
/// the transport to say so.
async fn Server::listen_http(
  self : Server,
  send : @moonasgi.Send,
  receive : @moonasgi.Receive,
) -> Unit {
  send(HttpResponseStart(status=200, headers=sse_headers, trailers=false))
  self.asks_made += 1
  let key = "listen-\{self.asks_made}"
  let queue = self.watch_legacy(key)
  defer self.unwatch(key)
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    group.spawn_bg(no_wait=true, allow_failure=true, async fn() {
      while !(receive() is HttpDisconnect) {

      }
      ignore(queue.try_put(Json::null()) catch { _ => false })
    })
    while queue.get() is (Object(_) as out) {
      send(HttpResponseBody(body=@utf8.encode(sse_frame(out)), more_body=true)) catch {
        _ => break
      }
    }
  })
  send(HttpResponseBody(body=b"", more_body=false)) catch {
    _ => ()
  }
}

///|
/// The answer to a request whose token is missing or does not verify: `401`
/// with the challenge RFC 6750 asks for, and nothing of the request in it.
async fn challenge(send : @moonasgi.Send, reason : String) -> Unit {
  let header = "Bearer realm=\"mcp\", error=\"invalid_token\", " +
    "error_description=\"" +
    reason +
    "\""
  reply_json(
    send,
    401,
    [
      ("www-authenticate", header),
      ("content-type", "text/plain; charset=utf-8"),
    ],
    b"",
  )
}

///|
/// One server-sent event carrying `message`. The stream serves JSON-RPC
/// messages only, so the event name is fixed and no id is set: streams are not
/// resumed.
fn sse_frame(message : Json) -> String {
  "event: message\ndata: " + message.stringify() + "\n\n"
}

///|
/// Every header a request carried, keyed in lower case, as a handler reads
/// them from its context.
fn header_map(headers : Array[(String, String)]) -> Map[String, String] {
  let map : Map[String, String] = Map([])
  for pair in headers {
    map[pair.0] = pair.1
  }
  map
}

///|
async fn reply_json(
  send : @moonasgi.Send,
  status : Int32,
  headers : Array[(String, String)],
  body : Bytes,
) -> Unit {
  send(HttpResponseStart(status~, headers~, trailers=false))
  send(HttpResponseBody(body~, more_body=false))
}

///|
/// A JSON body with its status.
async fn json_reply(
  send : @moonasgi.Send,
  status : Int32,
  reply : Json,
) -> Unit {
  reply_json(
    send,
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
    Some(k) => origin.exact_view(start=k + 3).to_owned()
    None => return false
  }
  if host is Some(h) && rest == h {
    return true
  }
  let name = match rest.rev_find(":") {
    Some(k) if !rest.has_suffix("]") => rest.exact_view(end=k).to_owned()
    _ => rest
  }
  name is ("localhost" | "127.0.0.1" | "[::1]")
}

///|
/// A `Host` value without its port.
fn host_name(host : String) -> String {
  if host.has_prefix("[") {
    return match host.find("]") {
      Some(k) => host.exact_view(end=k + 1).to_owned()
      None => host
    }
  }
  match host.rev_find(":") {
    Some(k) => host.exact_view(end=k).to_owned()
    None => host
  }
}

///|
fn is_loopback(name : String) -> Bool {
  name is ("localhost" | "127.0.0.1" | "[::1]" | "::1")
}

///|
/// Whether a request's `Host` is one this server answers to: one of `hosts`, or with none named, any
/// loopback name when it listens on a loopback address and anything when it does not.
fn host_allowed(
  host : String?,
  hosts : Array[String]?,
  bound : (String, Int32?)?,
) -> Bool {
  guard host is Some(host) else { return true }
  let name = host_name(host)
  match hosts {
    Some(hosts) => hosts.contains(name) || hosts.contains(host)
    None =>
      match bound {
        Some((address, _)) if is_loopback(address) => is_loopback(name)
        _ => true
      }
  }
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
  let inner = value.exact_view(start=9, end=value.length() - 2)
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
