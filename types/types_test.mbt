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

test "error data round trip" {
  let data : @types.ErrorData = {
    code: @types.invalid_params,
    message: "nope",
    data: None,
  }
  let decoded : @types.ErrorData = @json.from_json(
    @json.ToJson::to_json(data),
  )
  assert_eq(decoded, data)
}
