///|
/// The innermost step of a recorded chain.
#warnings("-unused_async")
async fn serve_watched(
  call : @layers.Call,
) -> Json raise @exceptions.FastMCPError {
  if call.name == "boom" {
    raise @exceptions.Tool("the call the test server refuses")
  }
  Json::string(call.name)
}

///|
fn watched_call(operation : @layers.Operation, name : String) -> @layers.Call {
  @layers.Call::new(operation~, name~, context=@context.Context::quiet())
}

///|
async test "every request leaves a span and a count" {
  let telemetry = @layers.Telemetry::new()
  let layers = [telemetry.layer()]
  ignore(
    @layers.chain(layers, watched_call(@layers.CallTool, "add"), async fn(
      call,
    ) -> Json raise @exceptions.FastMCPError {
      serve_watched(call)
    }),
  )
  ignore(
    @layers.chain(layers, watched_call(@layers.ListTools, ""), async fn(
      call,
    ) -> Json raise @exceptions.FastMCPError {
      serve_watched(call)
    }),
  )
  assert_eq(telemetry.total(), 2)
  assert_eq(telemetry.count(@layers.CallTool), 1)
  assert_eq(telemetry.count(@layers.ListTools), 1)
  assert_eq(telemetry.count(@layers.ReadResource), 0)
  let spans = telemetry.spans()
  assert_eq(spans.length(), 2)
  assert_eq(spans[0].name, "add")
  assert_eq(spans[0].operation, @layers.CallTool)
  assert_false(spans[0].failed)
  assert_true(spans[0].duration_us >= 0.0)
}

///|
async test "a request that raises is counted as a failure and still raises" {
  let telemetry = @layers.Telemetry::new()
  let layers = [telemetry.layer()]
  let answered = @layers.chain(layers, watched_call(@layers.CallTool, "boom"), async fn(
    call,
  ) -> Json raise @exceptions.FastMCPError {
    serve_watched(call)
  }) catch {
    @exceptions.Tool(_) => Json::null()
    _ => Json::string("something else")
  }
  assert_eq(answered, Json::null())
  assert_eq(telemetry.failures(), 1)
  assert_eq(telemetry.total(), 1)
  let spans = telemetry.spans()
  assert_eq(spans.length(), 1)
  assert_true(spans[0].failed)
}

///|
async test "the recorder keeps the last spans it was given room for" {
  let telemetry = @layers.Telemetry::new(capacity=2)
  let layers = [telemetry.layer()]
  for name in ["one", "two", "three"] {
    ignore(
      @layers.chain(layers, watched_call(@layers.CallTool, name), async fn(
        call,
      ) -> Json raise @exceptions.FastMCPError {
        serve_watched(call)
      }),
    )
  }
  let names = telemetry.spans().map(span => span.name)
  assert_eq(names.join(","), "two,three")
  assert_eq(telemetry.total(), 3)
}

///|
async test "every span is handed to the sink" {
  let seen : Array[String] = []
  let telemetry = @layers.Telemetry::new(sink=fn(span) {
    seen.push(span.operation.code())
  })
  let layers = [telemetry.layer()]
  ignore(
    @layers.chain(layers, watched_call(@layers.CallTool, "add"), async fn(
      call,
    ) -> Json raise @exceptions.FastMCPError {
      serve_watched(call)
    }),
  )
  assert_eq(seen.join(","), "tools/call")
}

///|
async test "clearing forgets the record" {
  let telemetry = @layers.Telemetry::new()
  let layers = [telemetry.layer()]
  ignore(
    @layers.chain(layers, watched_call(@layers.CallTool, "add"), async fn(
      call,
    ) -> Json raise @exceptions.FastMCPError {
      serve_watched(call)
    }),
  )
  telemetry.clear()
  assert_eq(telemetry.total(), 0)
  assert_eq(telemetry.spans().length(), 0)
}
