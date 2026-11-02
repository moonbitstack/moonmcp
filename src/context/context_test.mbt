///|
async test "a report carries the token, the count and the message" {
  let sent = []
  let ctx = @context.Context::new(
    facts=@context.Facts::new(progress_token=Json::string("t-1")),
    emit=fn(message) { sent.push(message) },
  )
  ctx.report_progress(progress=1.0, total=2.0, message="half") catch {
    _ => fail("reporting progress raised")
  }
  assert_eq(sent.length(), 1)
  let message = sent[0]
  guard message is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("method"), Some(Json::string("notifications/progress")))
  guard obj.get("params") is Some(Object(params)) else {
    fail("expected params")
  }
  assert_eq(params.get("progressToken"), Some(Json::string("t-1")))
  assert_eq(params.get("progress"), Some(Json::number(1.0)))
  assert_eq(params.get("total"), Some(Json::number(2.0)))
  assert_eq(params.get("message"), Some(Json::string("half")))
}

///|
async test "a report without a token goes nowhere" {
  let sent = []
  let ctx = @context.Context::new(facts=@context.Facts::new(), emit=fn(
    message,
  ) {
    sent.push(message)
  })
  ctx.report_progress(progress=1.0) catch {
    _ => fail("raised")
  }
  assert_eq(sent.length(), 0)
}

///|
async test "a log message names its level and its text" {
  let sent = []
  let ctx = @context.Context::new(facts=@context.Facts::new(), emit=fn(
    message,
  ) {
    sent.push(message)
  })
  ctx.log(level=@types.Warning, message="careful", logger="db") catch {
    _ => fail("logging raised")
  }
  guard sent[0] is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("method"), Some(Json::string("notifications/message")))
  guard obj.get("params") is Some(Object(params)) else {
    fail("expected params")
  }
  assert_eq(params.get("level"), Some(Json::string("warning")))
  assert_eq(params.get("data"), Some(Json::string("careful")))
  assert_eq(params.get("logger"), Some(Json::string("db")))
}

///|
async test "the facts of a request reach its handler" {
  let mut gone = false
  let ctx = @context.Context::new(
    facts=@context.Facts::new(
      operation="tools/call",
      request_id=Json::number(7.0),
      headers={ "x-tenant": "acme" },
      input_responses={ "0": Json::string("yes") },
      request_state="state-1",
    ),
    gone=fn() { gone },
  )
  assert_eq(ctx.operation(), "tools/call")
  assert_eq(ctx.request_id(), Json::number(7.0))
  assert_eq(ctx.header("x-tenant"), Some("acme"))
  assert_eq(ctx.input_responses().get("0"), Some(Json::string("yes")))
  assert_eq(ctx.request_state(), Some("state-1"))
  assert_false(ctx.is_cancelled())
  gone = true
  assert_true(ctx.is_cancelled())
}

///|
async test "a quiet context answers and reports nothing" {
  let ctx = @context.Context::quiet()
  assert_false(ctx.is_cancelled())
  assert_eq(ctx.operation(), "")
  ctx.info("nothing to see") catch {
    _ => fail("raised")
  }
}
