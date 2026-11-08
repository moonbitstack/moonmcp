// The same span, as it leaves the process: the OTLP/JSON record a collector
// reads, under the field names the protocol gives them.

///|
/// One field of a JSON object, or `null` when it is not there.
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
/// The first span record of an OTLP/JSON trace body, where every assertion
/// about one span starts.
fn first_span(document : Json) -> Json {
  let resources : Json = field(document, "resourceSpans")
  let scopes : Json = match resources {
    Array(items) if items.length() > 0 => field(items[0], "scopeSpans")
    _ => Json::null()
  }
  let spans : Json = match scopes {
    Array(items) if items.length() > 0 => field(items[0], "spans")
    _ => Json::null()
  }
  match spans {
    Array(items) if items.length() > 0 => items[0]
    _ => abort("the body carries no span record")
  }
}

///|
/// The value written under an attribute's key, whichever of the protocol's value
/// kinds it used.
fn otlp_attribute(span : Json, key : String) -> Json {
  match field(span, "attributes") {
    Array(attributes) => {
      for attribute in attributes {
        if field(attribute, "key") == Json::string(key) {
          let value = field(attribute, "value")
          match field(value, "stringValue") {
            String(text) => return Json::string(text)
            _ => ()
          }
          match field(value, "intValue") {
            String(number) => return Json::string(number)
            _ => ()
          }
          return value
        }
      }
      Json::null()
    }
    _ => Json::null()
  }
}

///|
/// The trace `recorded` holds, as a collector receives it.
fn encoded(recorded : @trace.Recorder) -> Json {
  let body = @otlp.encode_traces(
    recorded.spans(),
    resource=@otlp.Resource::of_service("demo"),
  )
  @json.parse(body) catch {
    _ => abort("the encoder wrote something that is not JSON")
  }
}

///|
async test "an encoded trace names the method, the tool and the caller's span" {
  let recorded = @trace.Recorder::new()
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=recorded,
    sampler=@trace.always,
  )
  let mcp = traced(@otel.Tracing::new(tracer~, now=step_clock()))
  ignore(
    mcp.handle_with(
      call_request("tools/call", "add", 7),
      channel=carried(caller_traceparent),
    ),
  )
  let span = first_span(encoded(recorded))
  assert_eq(field(span, "name"), Json::string("tools/call add"))
  assert_eq(field(span, "kind"), Json::number(2.0))
  assert_eq(otlp_attribute(span, "mcp.method.name"), Json::string("tools/call"))
  assert_eq(otlp_attribute(span, "gen_ai.tool.name"), Json::string("add"))
  assert_eq(
    otlp_attribute(span, "mcp.protocol.version"),
    Json::string("2026-07-28"),
  )
  assert_eq(otlp_attribute(span, "jsonrpc.request.id"), Json::string("7"))
  let caller = @propagate.parse(caller_traceparent) catch {
    _ => abort("the test's own traceparent is invalid")
  }
  assert_eq(
    field(span, "parentSpanId"),
    Json::string(@base16.encode(caller.span_id)),
  )
  assert_eq(
    field(span, "traceId"),
    Json::string(@base16.encode(caller.trace_id)),
  )
  assert_true(
    field(span, "spanId") != Json::string(@base16.encode(caller.span_id)),
  )
}

///|
async test "an encoded trace of a refused request says that it failed" {
  let recorded = @trace.Recorder::new()
  let tracer = @trace.Tracer::new(
    rand=counting_rand(),
    sink=recorded,
    sampler=@trace.always,
  )
  let mcp = traced(@otel.Tracing::new(tracer~, now=step_clock()))
  ignore(
    mcp.handle_with(
      call_request("tools/call", "nope", 8),
      channel=carried(caller_traceparent),
    ),
  )
  let span = first_span(encoded(recorded))
  assert_eq(field(span, "name"), Json::string("tools/call nope"))
  assert_eq(field(field(span, "status"), "code"), Json::number(2.0))
  assert_eq(otlp_attribute(span, "error.type"), Json::string("protocol_error"))
  assert_eq(
    otlp_attribute(span, "rpc.response.status_code"),
    Json::string("-32602"),
  )
}
