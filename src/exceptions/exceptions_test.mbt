///|
test "not found and disabled map to invalid params" {
  let not_found = @exceptions.to_mcp_error(@exceptions.NotFound("missing"))
  assert_eq(not_found.code, @types.invalid_params)
  assert_eq(not_found.message, "missing")
  let disabled = @exceptions.to_mcp_error(@exceptions.Disabled("off"))
  assert_eq(disabled.code, @types.invalid_params)
}

///|
test "validation maps to invalid params" {
  let err = @exceptions.to_mcp_error(@exceptions.Validation("bad args"))
  assert_eq(err.code, @types.invalid_params)
}

///|
test "resource security hides as invalid params" {
  let err = @exceptions.to_mcp_error(@exceptions.ResourceSecurity("traversal"))
  assert_eq(err.code, @types.invalid_params)
}

///|
test "existing protocol error survives translation" {
  let payload : @types.ErrorData = {
    code: @types.method_not_found,
    message: "explicit",
    data: None,
  }
  let err = @exceptions.to_mcp_error(@exceptions.Mcp(payload))
  assert_eq(err.code, @types.method_not_found)
}

///|
test "other errors fall back to the default code" {
  let err = @exceptions.to_mcp_error(@exceptions.Tool("boom"))
  assert_eq(err.code, @types.internal_error)
  assert_eq(err.message, "boom")
  let custom = @exceptions.to_mcp_error(
    @exceptions.Client("nope"),
    default_code=-32000,
  )
  assert_eq(custom.code, -32000)
}

///|
test "insufficient scope names the unmet scopes" {
  let err = @exceptions.insufficient_scope(["read", "write"])
  assert_eq(err.message(), "Insufficient scope. Required: read, write")
  guard err is @exceptions.InsufficientScope(required_scopes~, ..) else {
    fail("expected InsufficientScope")
  }
  assert_eq(required_scopes, ["read", "write"])
}
