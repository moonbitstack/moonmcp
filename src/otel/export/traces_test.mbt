// What leaves the process for one tool call: an OTLP/HTTP request carrying the
// span, read back from the transport instead of a collector.

///|
/// A transport that keeps every request and answers `200`.
struct Postbox {
  requests : Array[@otlp.Request]
}

///|
impl @otlp.Transport for Postbox with fn send(self, request) {
  self.requests.push(request)
  { status: 200, headers: [], body: b"", }
}

///|
/// Entropy that never repeats, so ids are valid and every run produces the same
/// bytes.
fn counting_rand() -> (Int32) -> Bytes {
  let calls = Ref(0)
  width => {
    calls.val = calls.val + 1
    Bytes::from_array(
      Array::makei(width, index => {
        ((calls.val * 37 + index + 1) % 251 + 1).to_byte()
      }),
    )
  }
}

///|
/// A clock that moves a hundred nanoseconds every time it is read.
fn step_clock() -> () -> Int64 {
  let at = Ref(1_700_000_000_000_000_000L)
  () => {
    at.val = at.val + 100L
    at.val
  }
}

///|
/// A `tools/call` as a 2026-07-28 client sends it.
fn call_request(name : String) -> Json {
  {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": Json::string(name),
      "arguments": (Map([]) : Map[String, Json]),
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": Json::string("2026-07-28"),
      },
    },
  }
}

///|
/// One request header, by name.
fn header_of(headers : Array[(String, String)], name : String) -> String? {
  for pair in headers {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// A body as text, for the assertions that read what was posted.
fn text_of(body : Bytes) -> String {
  @utf8.decode(body) catch {
    _ => ""
  }
}

///|
async test "a tool call is posted to the collector as one span" {
  let postbox = { requests: [], }
  let exporter = @export.traces(
    transport=postbox,
    service="demo",
    now=fn() { 1_700_000_000_000L },
    rand=counting_rand(),
  )
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=exporter,
    sampler=@trace.always,
  )
  let mcp = @server.Server::new("demo", version="1.0.0")
  mcp.tool("add", _args => { "sum": Json(2) })
  mcp.use_layer(@otel.Tracing::new(tracer~, now=step_clock()).layer())
  ignore(mcp.handle(call_request("add")))
  let report = exporter.flush()
  assert_eq(report.delivered, 1)
  assert_eq(postbox.requests.length(), 1)
  let request = postbox.requests[0]
  assert_eq(request.url, "http://localhost:4318/v1/traces")
  let body = text_of(request.body)
  assert_true(body.contains("\"resourceSpans\""))
  assert_true(body.contains("\"scope\""))
  assert_true(body.contains("\"name\":\"tools/call add\""))
  assert_true(body.contains("\"moonbitstack/moonmcp\""))
  assert_true(body.contains("\"demo\""))
  assert_eq(exporter.stats().delivered, 1L)
}

///|
async test "an exporter names the service and the address it was given" {
  let postbox = { requests: [], }
  let exporter = @export.traces(
    endpoint="http://collector.internal:4318",
    service="orders",
    headers=[("authorization", "Bearer token")],
    transport=postbox,
    now=fn() { 1_700_000_000_000L },
    rand=counting_rand(),
  )
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=exporter,
    sampler=@trace.always,
  )
  let mcp = @server.Server::new("demo", version="1.0.0")
  mcp.tool("add", _args => { "sum": Json(2) })
  mcp.use_layer(@otel.Tracing::new(tracer~, now=step_clock()).layer())
  ignore(mcp.handle(call_request("add")))
  ignore(exporter.flush())
  let request = postbox.requests[0]
  assert_eq(request.url, "http://collector.internal:4318/v1/traces")
  assert_eq(header_of(request.headers, "authorization"), Some("Bearer token"))
  assert_true(text_of(request.body).contains("\"orders\""))
}
