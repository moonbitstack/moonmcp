///|
test "default title capitalises words" {
  assert_eq(@tools.default_title("add_numbers"), "Add Numbers")
  assert_eq(@tools.default_title("fetch-user-data"), "Fetch User Data")
  assert_eq(@tools.default_title("x"), "X")
}

///|
test "tool name validation follows SEP-986" {
  assert_true(@tools.is_valid_tool_name("add"))
  assert_true(@tools.is_valid_tool_name("add_numbers-2"))
  assert_true(@tools.is_valid_tool_name("a"))
  assert_false(@tools.is_valid_tool_name(""))
  assert_false(@tools.is_valid_tool_name("add numbers"))
  assert_false(@tools.is_valid_tool_name("add!"))
  let long_name = "a".repeat(65)
  assert_false(@tools.is_valid_tool_name(long_name))
}

///|
test "tool result requires content or structured content" {
  let empty : Result[@tools.ToolResult, @exceptions.FastMCPError] = Ok(
    @tools.ToolResult::new(),
  ) catch {
    e => Err(e)
  }
  assert_true(empty is Err(_))
  let text = @tools.ToolResult::new(content=[@types.text_block("hello")])
  assert_false(text.is_error)
  assert_eq(text.content.length(), 1)
}

///|
test "tool result round trips through the wire result" {
  let result = @tools.ToolResult::from_mcp_result(
    @types.CallToolResult::error("boom"),
  )
  let wire = result.to_mcp_result()
  assert_true(wire.is_error)
  assert_eq(wire.content[0], @types.text_block("boom"))
}

///|
test "input required tool result keeps empty content" {
  let request : @types.InputRequest = {
    id: "q1",
    request: Json::object({ "message": Json::string("How many?") }),
  }
  let ask : @types.InputRequiredResult = {
    input_requests: [request],
    request_state: None,
    meta: None,
  }
  let result = @tools.ToolResult::input_required(ask)
  assert_true(result.is_input_required())
  assert_eq(result.content.length(), 0)
}

///|
async test "tool registers and converts to wire form" {
  let tool = @tools.Tool::new(
    "add",
    parameters=Json::object({ "type": Json::string("object") }),
    run_fn=_ => @tools.ToolResult::new(content=[@types.text_block("3")]),
    description="Add two numbers",
    task_config=@tasks.TaskConfig::new(mode=@tasks.Optional),
  )
  assert_eq(tool.component.name, "add")
  assert_eq(@component.Component::key(tool), "tool:add@")
  let wire = tool.to_mcp_tool()
  assert_eq(wire.name, "add")
  assert_eq(wire.title, Some("Add"))
  assert_eq(wire.execution is Some(_), true)
  let run = tool.run({})
  assert_eq(run.content[0], @types.text_block("3"))
}

///|
test "explicit annotation title wins over derived title" {
  let tool = @tools.Tool::new(
    "add",
    parameters=Json::object({}),
    run_fn=_ => @tools.ToolResult::new(content=[]),
    annotations={
      title: Some("Calculator"),
      read_only_hint: None,
      destructive_hint: None,
      idempotent_hint: None,
      open_world_hint: None,
    },
  )
  assert_eq(tool.to_mcp_tool().title, Some("Calculator"))
}

///|
test "convert result wraps structured output on schema request" {
  let schema = Json::object({
    "type": Json::string("object"),
    "x-fastmcp-wrap-result": Json::boolean(true),
  })
  let tool = @tools.Tool::new(
    "query",
    parameters=Json::object({}),
    run_fn=_ => @tools.ToolResult::new(content=[]),
    output_schema=schema,
  )
  let raw = Json::object({ "rows": Json::number(2) })
  let result = tool.convert_result(raw)
  guard result.structured_content is Some(structured) else {
    fail("expected structured content")
  }
  assert_eq(structured.get("result") is Some(_), true)
  guard result.meta is Some(meta) else { fail("expected meta") }
  assert_eq(meta.get("fastmcp") is Some(_), true)
}

///|
test "convert result keeps plain object structured output" {
  let tool = @tools.Tool::new("query", parameters=Json::object({}), run_fn=_ => {
    @tools.ToolResult::new(content=[])
  })
  let raw = Json::object({ "rows": Json::number(2) })
  let result = tool.convert_result(raw)
  guard result.structured_content is Some(structured) else {
    fail("expected structured content")
  }
  assert_eq(structured.get("rows") is Some(_), true)
  assert_eq(result.content[0], @types.text_block(raw.stringify()))
}

///|
test "convert result keeps content blocks as content" {
  let tool = @tools.Tool::new("echo", parameters=Json::object({}), run_fn=_ => {
    @tools.ToolResult::new(content=[])
  })
  let block = Json::object({
    "type": Json::string("text"),
    "text": Json::string("hi"),
  })
  let result = tool.convert_result(block)
  assert_eq(result.content.length(), 1)
  assert_eq(result.structured_content is None, true)
}
