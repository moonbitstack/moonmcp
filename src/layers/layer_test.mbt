///|
fn layer(
  name : String,
  run : async (@layers.Call, @layers.Next) -> Json raise @exceptions.FastMCPError,
) -> @layers.Layer {
  @layers.Layer::new(name~, run~)
}

///|
fn quiet_call(operation : @layers.Operation, name : String) -> @layers.Call {
  @layers.Call::new(operation~, name~, context=@context.Context::quiet())
}

///|
/// The answer of a test server, or the error one named `boom` deserves.
#warnings("-unused_async")
async fn deliver(value : Json) -> Json raise @exceptions.FastMCPError {
  if value == Json::null() {
    raise @exceptions.Tool("nothing to say")
  }
  value
}

///|
/// The innermost step of a test chain: record what reached the server, then
/// answer.
async fn serve(
  seen : Array[String],
  value : Json,
  call : @layers.Call,
) -> Json raise @exceptions.FastMCPError {
  seen.push(call.name)
  deliver(value)
}

///|
/// A layer that turns every call away.
#warnings("-unused_async")
async fn refuse() -> Json raise @exceptions.FastMCPError {
  raise @exceptions.Mcp({
    code: @layers.refused_code,
    message: "no",
    data: None,
  })
}

///|
async test "a chain runs its layers outermost first and ends in the call" {
  let trace : Array[String] = []
  let layers = [
    layer("outer", async fn(call, next) -> Json raise @exceptions.FastMCPError {
      trace.push("outer in")
      let answer = next.then(call)
      trace.push("outer out")
      answer
    }),
    layer("inner", async fn(call, next) -> Json raise @exceptions.FastMCPError {
      trace.push("inner in")
      let answer = next.then(call)
      trace.push("inner out")
      answer
    }),
  ]
  let answer = @layers.chain(layers, quiet_call(@layers.CallTool, "add"), async fn(
    call,
  ) -> Json raise @exceptions.FastMCPError {
    trace.push("served")
    deliver(Json::string(call.name))
  })
  assert_eq(answer.stringify(), "\"add\"")
  assert_eq(trace.join(","), "outer in,inner in,served,inner out,outer out")
}

///|
async test "a layer may answer without passing the call on" {
  let reached : Array[String] = []
  let layers = [
    layer("short circuit", async fn(
      _call,
      _next,
    ) -> Json raise @exceptions.FastMCPError {
      deliver(Json::string("answered by the layer"))
    }),
  ]
  let answer = @layers.chain(layers, quiet_call(@layers.CallTool, "add"), async fn(
    call,
  ) -> Json raise @exceptions.FastMCPError {
    serve(reached, Json::string("served"), call)
  })
  assert_eq(answer.stringify(), "\"answered by the layer\"")
  assert_eq(reached.length(), 0)
}

///|
async test "an empty chain calls the server directly" {
  let answer = @layers.chain([], quiet_call(@layers.ListTools, ""), async fn(
    call,
  ) -> Json raise @exceptions.FastMCPError {
    deliver(Json::string(call.operation.code()))
  })
  assert_eq(answer.stringify(), "\"tools/list\"")
}

///|
async test "a layer that raises a protocol error stops the chain" {
  let reached : Array[String] = []
  let layers = [
    layer("refuse", async fn(
      _call,
      _next,
    ) -> Json raise @exceptions.FastMCPError {
      refuse()
    }),
  ]
  let mut code : Int32 = 0
  let answer = @layers.chain(layers, quiet_call(@layers.CallTool, "add"), async fn(
    call,
  ) -> Json raise @exceptions.FastMCPError {
    serve(reached, Json::string("served"), call)
  }) catch {
    @exceptions.Mcp(data) => {
      code = data.code
      Json::null()
    }
    _ => Json::null()
  }
  assert_eq(answer, Json::null())
  assert_eq(code, -32000)
  assert_eq(reached.length(), 0)
}

///|
test "the fingerprint of a call does not depend on the order arguments came in" {
  let first : Map[String, Json] = { "a": 1, "b": { "x": 1, "y": 2 } }
  let second : Map[String, Json] = { "b": { "y": 2, "x": 1 }, "a": 1 }
  let one = @layers.Call::new(
    operation=@layers.CallTool,
    name="add",
    arguments=first,
    context=@context.Context::quiet(),
  )
  let other = @layers.Call::new(
    operation=@layers.CallTool,
    name="add",
    arguments=second,
    context=@context.Context::quiet(),
  )
  assert_eq(one.fingerprint(), other.fingerprint())
}

///|
test "the fingerprint separates the operation, the name and the arguments" {
  let base = @layers.Call::new(
    operation=@layers.CallTool,
    name="add",
    arguments={ "a": 1 },
    context=@context.Context::quiet(),
  )
  let renamed = @layers.Call::new(
    operation=@layers.CallTool,
    name="sum",
    arguments={ "a": 1 },
    context=@context.Context::quiet(),
  )
  let listed = @layers.Call::new(
    operation=@layers.ListTools,
    name="add",
    arguments={ "a": 1 },
    context=@context.Context::quiet(),
  )
  let other_arguments = @layers.Call::new(
    operation=@layers.CallTool,
    name="add",
    arguments={ "a": 2 },
    context=@context.Context::quiet(),
  )
  assert_false(base.fingerprint() == renamed.fingerprint())
  assert_false(base.fingerprint() == listed.fingerprint())
  assert_false(base.fingerprint() == other_arguments.fingerprint())
}

///|
test "an operation names its method, and a listing says so" {
  assert_eq(@layers.CallTool.code(), "tools/call")
  assert_eq(@layers.ListPrompts.code(), "prompts/list")
  assert_false(@layers.CallTool.is_list())
  assert_true(@layers.ListPrompts.is_list())
}
