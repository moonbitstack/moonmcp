// The spans a server serves, checked against what the semantic conventions say
// a server span is: its name, its attributes, its kind, and the trace it hangs
// from.

///|
/// A clock that moves a hundred nanoseconds every time it is read, so a span in
/// a test has a timeline the test wrote.
fn step_clock() -> () -> Int64 {
  let at = Ref(1_700_000_000_000_000_000L)
  () => {
    at.val = at.val + 100L
    at.val
  }
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
/// One attribute of a recorded span, by the name it was written under.
fn attribute(span : @trace.SpanData, name : String) -> @trace.Value? {
  for pair in span.attributes {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// A server with one tool and one prompt, and the tracing layer in front of
/// every request.
fn traced(tracing : @otel.Tracing) -> @server.Server {
  let mcp = @server.Server::new("demo", version="1.0.0")
  mcp.tool("add", _args => { "sum": Json(1) })
  mcp.resource("config://app", () => "{\"theme\":\"dark\"}")
  mcp.prompt("review", _args => "look at this")
  mcp.use_layer(tracing.layer())
  mcp
}

///|
/// The `traceparent` a caller in another process sent: trace 4bf9…, span 00f0….
let caller_traceparent : String = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

///|
/// A request as a 2026-07-28 client sends it.
fn call_request(operation : String, name : String, id : Int32) -> Json {
  {
    "jsonrpc": "2.0",
    "id": Json(id),
    "method": Json::string(operation),
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
/// A `resources/read` as a client sends it.
fn read_request(uri : String) -> Json {
  {
    "jsonrpc": "2.0",
    "id": Json(9),
    "method": "resources/read",
    "params": {
      "uri": Json::string(uri),
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": Json::string("2026-07-28"),
      },
    },
  }
}

///|
/// The headers a request arrived with, as a transport hands them on.
fn carried(traceparent : String) -> @server.Channel {
  @server.Channel::new(
    emit=fn(_) { () },
    headers={ "traceparent": traceparent },
    gone=fn() { false },
  )
}

///|
async test "a tool call is one server span named after the method and the tool" {
  let recorder = @trace.Recorder::new()
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=recorder,
    sampler=@trace.always,
  )
  let mcp = traced(@otel.Tracing::new(tracer~, now=step_clock()))
  ignore(
    mcp.handle_with(
      call_request("tools/call", "add", 7),
      channel=carried(caller_traceparent),
    ),
  )
  let spans = recorder.spans()
  assert_eq(spans.length(), 1)
  let span = spans[0]
  assert_eq(span.name, "tools/call add")
  assert_eq(span.kind, @trace.Server)
  assert_eq(span.status, @trace.Ok)
  assert_eq(attribute(span, "mcp.method.name"), Some(@trace.Str("tools/call")))
  assert_eq(attribute(span, "gen_ai.tool.name"), Some(@trace.Str("add")))
  assert_eq(
    attribute(span, "gen_ai.operation.name"),
    Some(@trace.Str("execute_tool")),
  )
  assert_eq(
    attribute(span, "mcp.protocol.version"),
    Some(@trace.Str("2026-07-28")),
  )
  assert_eq(attribute(span, "jsonrpc.request.id"), Some(@trace.Int(7L)))
  assert_eq(attribute(span, "error.type"), None)
  assert_true(span.duration() > 0L)
}

///|
async test "the span is a child of the trace the request carried" {
  let recorder = @trace.Recorder::new()
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=recorder,
    sampler=@trace.always,
  )
  let mcp = traced(@otel.Tracing::new(tracer~, now=step_clock()))
  ignore(
    mcp.handle_with(
      call_request("tools/call", "add", 1),
      channel=carried(caller_traceparent),
    ),
  )
  let caller = @propagate.parse(caller_traceparent) catch {
    _ => abort("the test's own traceparent is invalid")
  }
  let span = recorder.spans()[0]
  assert_eq(span.parent, Some(caller.span_id))
  assert_eq(span.context.trace_id, caller.trace_id)
  assert_true(span.context.span_id != caller.span_id)
  assert_true(span.sampled())
}

///|
async test "a request that carries no trace starts one" {
  let recorder = @trace.Recorder::new()
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=recorder,
    sampler=@trace.always,
  )
  let mcp = traced(@otel.Tracing::new(tracer~, now=step_clock()))
  ignore(mcp.handle(call_request("tools/call", "add", 1)))
  let span = recorder.spans()[0]
  assert_eq(span.parent, None)
  assert_eq(span.context.trace_id.length(), 16)
}

///|
async test "a refused request is an error span and is still refused" {
  let recorder = @trace.Recorder::new()
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=recorder,
    sampler=@trace.always,
  )
  let mcp = traced(@otel.Tracing::new(tracer~, now=step_clock()))
  let reply = mcp.handle_with(
    call_request("tools/call", "nope", 2),
    channel=carried(caller_traceparent),
  )
  let span = recorder.spans()[0]
  match span.status {
    @trace.Error(message) => assert_true(message.contains("nope"))
    _ => abort("a refused request is an error span")
  }
  assert_eq(attribute(span, "error.type"), Some(@trace.Str("protocol_error")))
  assert_eq(
    attribute(span, "rpc.response.status_code"),
    Some(@trace.Int(-32602L)),
  )
  assert_eq(span.events.length(), 1)
  assert_eq(span.events[0].name, "exception")
  assert_true(Json(reply.unwrap()).stringify().contains("\"code\":-32602"))
}

///|
async test "a listing has no target in its name" {
  let recorder = @trace.Recorder::new()
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=recorder,
    sampler=@trace.always,
  )
  let mcp = traced(@otel.Tracing::new(tracer~, now=step_clock()))
  ignore(
    mcp.handle_with(
      call_request("tools/list", "", 3),
      channel=carried(caller_traceparent),
    ),
  )
  let span = recorder.spans()[0]
  assert_eq(span.name, "tools/list")
  assert_eq(attribute(span, "mcp.method.name"), Some(@trace.Str("tools/list")))
  assert_eq(attribute(span, "gen_ai.tool.name"), None)
}

///|
async test "a prompt names its span after the prompt and the method" {
  let recorder = @trace.Recorder::new()
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=recorder,
    sampler=@trace.always,
  )
  let mcp = traced(@otel.Tracing::new(tracer~, now=step_clock()))
  ignore(
    mcp.handle_with(
      call_request("prompts/get", "review", 4),
      channel=carried(caller_traceparent),
    ),
  )
  let span = recorder.spans()[0]
  assert_eq(span.name, "prompts/get review")
  assert_eq(attribute(span, "gen_ai.prompt.name"), Some(@trace.Str("review")))
}

///|
async test "a sampler that keeps nothing still answers, and records no span" {
  let recorder = @trace.Recorder::new()
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=recorder,
    sampler=@trace.never,
  )
  let mcp = traced(@otel.Tracing::new(tracer~, now=step_clock()))
  let reply = mcp.handle(call_request("tools/call", "add", 5))
  assert_true(Json(reply.unwrap()).stringify().contains("\"result\""))
  assert_eq(recorder.spans().length(), 0)
}

///|
async test "a resource read keeps the uri an attribute and out of the name" {
  let recorder = @trace.Recorder::new()
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=recorder,
    sampler=@trace.always,
  )
  let mcp = traced(@otel.Tracing::new(tracer~, now=step_clock()))
  ignore(
    mcp.handle_with(
      read_request("config://app"),
      channel=carried(caller_traceparent),
    ),
  )
  let span = recorder.spans()[0]
  assert_eq(span.name, "resources/read")
  assert_eq(
    attribute(span, "mcp.resource.uri"),
    Some(@trace.Str("config://app")),
  )
  assert_eq(attribute(span, "gen_ai.tool.name"), None)
  assert_eq(span.status, @trace.Ok)
}
