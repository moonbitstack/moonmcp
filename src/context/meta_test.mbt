// The `_meta` object a request carried, kept whole on its facts and readable
// from the context a handler is given.

///|
test "a context made without a request has no _meta" {
  assert_eq(@context.Context::quiet().meta().keys().collect().length(), 0)
  assert_eq(@context.Facts::new().meta.keys().collect().length(), 0)
}

///|
test "meta() answers the object the request carried" {
  let meta : Map[String, Json] = {
    "io.modelcontextprotocol/protocolVersion": Json::string("2026-07-28"),
    "traceparent": Json::string(
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    ),
    "nested": { "flag": true },
  }
  let context = @context.Context::new(facts=@context.Facts::new(meta~))
  assert_eq(context.meta().keys().collect().length(), 3)
  assert_eq(context.meta().get("traceparent"), meta.get("traceparent"))
  assert_eq(
    context.meta().get("nested").unwrap().stringify(),
    "{\"flag\":true}",
  )
  assert_eq(
    context.facts().meta.get("io.modelcontextprotocol/protocolVersion"),
    Some(Json::string("2026-07-28")),
  )
}

///|
test "the headers and _meta of a request stay separate" {
  let context = @context.Context::new(
    facts=@context.Facts::new(headers={ "traceparent": "00-from-a-header" }, meta={
      "traceparent": Json::string("00-from-meta"),
    }),
  )
  assert_eq(context.header("traceparent"), Some("00-from-a-header"))
  assert_eq(
    context.meta().get("traceparent"),
    Some(Json::string("00-from-meta")),
  )
}
