///|
fn limited_call(name : String) -> @layers.Call {
  @layers.Call::new(
    operation=@layers.CallTool,
    name~,
    context=@context.Context::quiet(),
  )
}

///|
/// The innermost step of a limited chain.
#warnings("-unused_async")
async fn serve_limited(
  call : @layers.Call,
) -> Json raise @exceptions.FastMCPError {
  if call.name == "boom" {
    raise @exceptions.Tool("the call the test server refuses")
  }
  Json::string(call.name)
}

///|
/// Serve one call through `layers` and hand back the code it was refused with,
/// or zero when it went through.
async fn outcome(layers : Array[@layers.Layer], call : @layers.Call) -> Int32 {
  let mut code : Int32 = 0
  let answer = @layers.chain(layers, call, async fn(
    call,
  ) -> Json raise @exceptions.FastMCPError {
    serve_limited(call)
  }) catch {
    @exceptions.Mcp(data) => {
      code = data.code
      Json::null()
    }
    _ => Json::null()
  }
  ignore(answer)
  code
}

///|
async test "a burst is served, and the call after it is refused" {
  let limiter = @layers.RateLimiting::new(rate=1, burst=2)
  let layers = [limiter.layer()]
  assert_eq(outcome(layers, limited_call("add")), 0)
  assert_eq(outcome(layers, limited_call("add")), 0)
  assert_eq(outcome(layers, limited_call("add")), @layers.refused_code)
  assert_eq(limiter.refused(), 1)
}

///|
async test "a refused caller is served again once the bucket has filled" {
  let mut now = 0.0
  let limiter = @layers.RateLimiting::new(rate=1, burst=1, clock=fn() { now })
  let layers = [limiter.layer()]
  assert_eq(outcome(layers, limited_call("add")), 0)
  assert_eq(outcome(layers, limited_call("add")), @layers.refused_code)
  now = 1.0
  assert_eq(outcome(layers, limited_call("add")), 0)
  assert_eq(outcome(layers, limited_call("add")), @layers.refused_code)
}

///|
async test "a long wait fills the bucket to the burst, no further" {
  let mut now = 0.0
  let limiter = @layers.RateLimiting::new(rate=1, burst=2, clock=fn() { now })
  let layers = [limiter.layer()]
  for _ in 0..<2 {
    assert_eq(outcome(layers, limited_call("add")), 0)
  }
  now = 100.0
  assert_eq(outcome(layers, limited_call("add")), 0)
  assert_eq(outcome(layers, limited_call("add")), 0)
  assert_eq(outcome(layers, limited_call("add")), @layers.refused_code)
}

///|
async test "each caller has a bucket of its own" {
  let limiter = @layers.RateLimiting::new(rate=1, burst=1)
  let layers = [limiter.layer()]
  let alice = @layers.Call::new(
    operation=@layers.CallTool,
    name="add",
    context=@context.Context::new(facts=@context.Facts::new(subject="alice")),
  )
  let bob = @layers.Call::new(
    operation=@layers.CallTool,
    name="add",
    context=@context.Context::new(facts=@context.Facts::new(subject="bob")),
  )
  assert_eq(outcome(layers, alice), 0)
  assert_eq(outcome(layers, alice), @layers.refused_code)
  assert_eq(outcome(layers, bob), 0)
  assert_eq(limiter.callers(), 2)
}

///|
async test "a listing is not counted against the caller" {
  let limiter = @layers.RateLimiting::new(rate=1, burst=1)
  let layers = [limiter.layer()]
  let listing = @layers.Call::new(
    operation=@layers.ListTools,
    name="",
    context=@context.Context::quiet(),
  )
  for _ in 0..<3 {
    assert_eq(outcome(layers, listing), 0)
  }
  assert_eq(limiter.callers(), 0)
  assert_eq(limiter.refused(), 0)
}

///|
async test "resetting forgets every bucket" {
  let limiter = @layers.RateLimiting::new(rate=1, burst=1)
  let layers = [limiter.layer()]
  assert_eq(outcome(layers, limited_call("add")), 0)
  assert_eq(outcome(layers, limited_call("add")), @layers.refused_code)
  limiter.reset()
  assert_eq(outcome(layers, limited_call("add")), 0)
  assert_eq(limiter.callers(), 1)
}
