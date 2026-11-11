// A trace context that arrives in `params._meta`, which is the only place a
// caller over stdio can put one. The headers remain the fallback for a caller
// over HTTP that still sends its context there.

///|
/// A second caller, so precedence between `_meta` and the headers is visible.
let other_traceparent : String = "00-11111111111111111111111111111111-2222222222222222-01"

///|
/// A `tools/call` whose `_meta` carries a W3C trace context.
fn meta_request(traceparent? : Json, tracestate? : Json) -> Json {
  let meta : Map[String, Json] = {
    "io.modelcontextprotocol/protocolVersion": Json::string("2026-07-28"),
  }
  if traceparent is Some(parent) {
    meta["traceparent"] = parent
  }
  if tracestate is Some(state) {
    meta["tracestate"] = state
  }
  {
    "jsonrpc": "2.0",
    "id": Json(11),
    "method": "tools/call",
    "params": {
      "name": Json::string("add"),
      "arguments": (Map([]) : Map[String, Json]),
      "_meta": Json(meta),
    },
  }
}

///|
/// The same request under a revision where `_meta` has no protocol version.
fn legacy_meta_request(traceparent : String) -> Json {
  {
    "jsonrpc": "2.0",
    "id": Json(14),
    "method": "tools/call",
    "params": {
      "name": Json::string("add"),
      "_meta": { "traceparent": Json::string(traceparent) },
    },
  }
}

///|
/// A traced server whose spans land in `recorder`.
fn traced_with(recorder : @trace.Recorder) -> @server.Server {
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=recorder,
    sampler=@trace.always,
  )
  traced(@otel.Tracing::new(tracer~, now=step_clock()))
}

///|
/// An HTTP channel carrying a caller's context in its headers.
fn http_carried(traceparent : String, tracestate? : String) -> @server.Channel {
  let headers : Map[String, String] = { "traceparent": traceparent }
  if tracestate is Some(state) {
    headers["tracestate"] = state
  }
  @server.Channel::new(emit=fn(_) { () }, headers~, gone=fn() { false })
}

///|
async test "a caller's trace in _meta joins the server span over stdio" {
  let recorder = @trace.Recorder::new()
  let mcp = traced_with(recorder)
  let caller = @propagate.parse(caller_traceparent) catch {
    _ => abort("the test's own traceparent is invalid")
  }
  // A stdio request has no headers at all; the quiet channel is what that
  // transport hands the server.
  ignore(
    mcp.handle_with(
      meta_request(
        traceparent=Json::string(caller_traceparent),
        tracestate=Json::string("vendor=one"),
      ),
      channel=@server.Channel::quiet(),
    ),
  )
  let span = recorder.spans()[0]
  assert_eq(span.parent, Some(caller.span_id))
  assert_eq(span.context.trace_id, caller.trace_id)
  assert_eq(span.context.state.get("vendor"), Some("one"))
  assert_true(span.context.span_id != caller.span_id)
  assert_eq(span.name, "tools/call add")
}

///|
async test "a caller's trace in the headers still joins the server span over HTTP" {
  let recorder = @trace.Recorder::new()
  let mcp = traced_with(recorder)
  let caller = @propagate.parse(caller_traceparent) catch {
    _ => abort("the test's own traceparent is invalid")
  }
  ignore(
    mcp.handle_with(
      call_request("tools/call", "add", 12),
      channel=http_carried(caller_traceparent, tracestate="vendor=two"),
    ),
  )
  let span = recorder.spans()[0]
  assert_eq(span.parent, Some(caller.span_id))
  assert_eq(span.context.trace_id, caller.trace_id)
  assert_eq(span.context.state.get("vendor"), Some("two"))
}

///|
async test "_meta wins over a different trace in the headers" {
  let recorder = @trace.Recorder::new()
  let mcp = traced_with(recorder)
  let caller = @propagate.parse(caller_traceparent) catch {
    _ => abort("the test's own traceparent is invalid")
  }
  let other = @propagate.parse(other_traceparent) catch {
    _ => abort("the test's own traceparent is invalid")
  }
  ignore(
    mcp.handle_with(
      meta_request(
        traceparent=Json::string(caller_traceparent),
        tracestate=Json::string("vendor=one"),
      ),
      channel=http_carried(other_traceparent, tracestate="vendor=two"),
    ),
  )
  let span = recorder.spans()[0]
  assert_eq(span.parent, Some(caller.span_id))
  assert_eq(span.context.trace_id, caller.trace_id)
  assert_true(span.context.trace_id != other.trace_id)
  assert_eq(span.context.state.get("vendor"), Some("one"))
}

///|
async test "a broken traceparent in _meta starts a trace of its own" {
  let recorder = @trace.Recorder::new()
  let mcp = traced_with(recorder)
  let other = @propagate.parse(other_traceparent) catch {
    _ => abort("the test's own traceparent is invalid")
  }
  ignore(
    mcp.handle_with(
      meta_request(traceparent=Json::string("not-a-traceparent")),
      channel=http_carried(other_traceparent),
    ),
  )
  let span = recorder.spans()[0]
  assert_eq(span.parent, None)
  assert_true(span.context.trace_id != other.trace_id)
}

///|
async test "a traceparent in _meta that is not a string falls back to the headers" {
  let recorder = @trace.Recorder::new()
  let mcp = traced_with(recorder)
  let caller = @propagate.parse(caller_traceparent) catch {
    _ => abort("the test's own traceparent is invalid")
  }
  ignore(
    mcp.handle_with(
      meta_request(traceparent=Json::number(7.0)),
      channel=http_carried(caller_traceparent),
    ),
  )
  assert_eq(recorder.spans()[0].parent, Some(caller.span_id))
}

///|
async test "a legacy request whose _meta carries a traceparent joins the caller" {
  let recorder = @trace.Recorder::new()
  let mcp = traced_with(recorder)
  let caller = @propagate.parse(caller_traceparent) catch {
    _ => abort("the test's own traceparent is invalid")
  }
  ignore(mcp.handle(legacy_meta_request(caller_traceparent)))
  let span = recorder.spans()[0]
  assert_eq(span.parent, Some(caller.span_id))
  assert_eq(span.context.trace_id, caller.trace_id)
}

///|
async test "a layer reads the whole _meta object from the call's context" {
  let seen : Ref[Map[String, Json]] = Ref(Map([]))
  let mcp = @server.Server::new("demo", version="1.0.0")
  mcp.tool("add", _args => { "sum": Json(1) })
  mcp.use_layer(
    @layers.Layer::new(name="meta", run=async fn(
      call,
      next,
    ) -> Json raise @exceptions.FastMCPError {
      seen.val = call.context.meta()
      next.then(call)
    }),
  )
  ignore(mcp.handle(meta_request(traceparent=Json::string(caller_traceparent))))
  assert_eq(seen.val.get("traceparent"), Some(Json::string(caller_traceparent)))
  assert_eq(
    seen.val.get("io.modelcontextprotocol/protocolVersion"),
    Some(Json::string("2026-07-28")),
  )
  assert_eq(seen.val.get("name"), None)
}

///|
async test "the OTLP record of a stdio call names the parent span from _meta" {
  let recorded = @trace.Recorder::new()
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=recorded,
    sampler=@trace.always,
  )
  let mcp = traced(@otel.Tracing::new(tracer~, now=step_clock()))
  let caller = @propagate.parse(caller_traceparent) catch {
    _ => abort("the test's own traceparent is invalid")
  }
  ignore(mcp.handle(meta_request(traceparent=Json::string(caller_traceparent))))
  let span = first_span(encoded(recorded))
  assert_eq(field(span, "name"), Json::string("tools/call add"))
  assert_eq(
    field(span, "parentSpanId"),
    Json::string(@base16.encode(caller.span_id)),
  )
  assert_eq(
    field(span, "traceId"),
    Json::string(@base16.encode(caller.trace_id)),
  )
  assert_eq(otlp_attribute(span, "mcp.method.name"), Json::string("tools/call"))
}
