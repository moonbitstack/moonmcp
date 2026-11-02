///|
test "icon serialises with wire field names" {
  let icon : @types.Icon = {
    src: "https://example.com/icon.png",
    mime_type: Some("image/png"),
    sizes: Some(["48x48"]),
  }
  let json = @json.ToJson::to_json(icon)
  guard json is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("mimeType"), Some(Json::string("image/png")))
  assert_eq(obj.get("sizes"), Some(Json::array([Json::string("48x48")])))
  let round_tripped : @types.Icon = @json.from_json(json)
  assert_eq(round_tripped, icon)
}

///|
test "icon omits absent optional fields" {
  let icon : @types.Icon = {
    src: "https://example.com/icon.svg",
    mime_type: None,
    sizes: None,
  }
  let json = @json.ToJson::to_json(icon)
  guard json is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("mimeType"), None)
  assert_eq(obj.get("sizes"), None)
}

///|
test "error data round trip" {
  let data : @types.ErrorData = {
    code: @types.invalid_params,
    message: "nope",
    data: None,
  }
  let decoded : @types.ErrorData = @json.from_json(@json.ToJson::to_json(data))
  assert_eq(decoded, data)
}

///|
test "a cacheable list result round trips its time-to-live and scope" {
  let result : @types.ListToolsResult = {
    tools: [],
    next_cursor: None,
    ttl_ms: Some(30_000),
    cache_scope: Some(@types.Public),
    meta: None,
  }
  let json = @types.ListToolsResult::to_json(result)
  guard json is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("ttlMs"), Some(Json::number(30_000.0)))
  assert_eq(obj.get("cacheScope"), Some(Json::string("public")))
  let round_tripped : @types.ListToolsResult = @json.from_json(json)
  assert_eq(round_tripped, result)
}

///|
test "a cacheable result without hints writes neither field" {
  let result : @types.ReadResourceResult = {
    contents: [],
    ttl_ms: None,
    cache_scope: None,
    meta: None,
  }
  let json = @types.ReadResourceResult::to_json(result)
  guard json is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("ttlMs"), None)
  assert_eq(obj.get("cacheScope"), None)
}
