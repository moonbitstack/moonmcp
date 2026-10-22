test "content block round trips through the wire format" {
  let block : @types.ContentBlock = @types.ContentBlock::Image(
    data="aGk=",
    mime_type="image/png",
    annotations=None,
    meta=None,
  )
  let json = @types.ContentBlock::to_json(block)
  guard json is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("type"), Some(Json::string("image")))
  assert_eq(obj.get("mimeType"), Some(Json::string("image/png")))
  let decoded : @types.ContentBlock = @json.from_json(json)
  assert_eq(decoded, block)

  let link : @types.ContentBlock = @types.ContentBlock::ResourceLink(
    uri="file:///x.txt",
    name="x",
    title=Some("X"),
    description=None,
    mime_type=Some("text/plain"),
    size=Some(3),
    annotations=None,
    meta=None,
  )
  let round_tripped : @types.ContentBlock = @json.from_json(
    @types.ContentBlock::to_json(link),
  )
  assert_eq(round_tripped, link)
}

test "resource contents text and blob variants" {
  let text : @types.ResourceContents = @types.Text(
    uri="file:///a.txt",
    mime_type=Some("text/plain"),
    text="hello",
  )
  let blob : @types.ResourceContents = @types.Blob(
    uri="file:///a.bin",
    mime_type=None,
    blob="AA==",
  )
  let decoded_text : @types.ResourceContents = @json.from_json(
    @types.ResourceContents::to_json(text),
  )
  let decoded_blob : @types.ResourceContents = @json.from_json(
    @types.ResourceContents::to_json(blob),
  )
  assert_eq(decoded_text, text)
  assert_eq(decoded_blob, blob)
  assert_eq(@types.ResourceContents::uri(decoded_text), "file:///a.txt")
}

test "tool serialises with camelCase wire keys" {
  let tool : @types.Tool = {
    name: "add",
    title: Some("Add"),
    description: Some("Add two numbers"),
    input_schema: Json::object({
      "type": Json::string("object"),
      "properties": Json::object({}),
    }),
    output_schema: None,
    icons: None,
    annotations: None,
    execution: None,
    meta: Some({ "fastmcp": Json::object({ "tags": Json::array([]) }) }),
  }
  let json = @types.Tool::to_json(tool)
  guard json is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("inputSchema") is Some(_), true)
  assert_eq(obj.get("_meta") is Some(_), true)
  let decoded : @types.Tool = @json.from_json(json)
  assert_eq(decoded, tool)
}

test "initialize result round trips" {
  let result : @types.InitializeResult = {
    protocol_version: @types.latest_protocol_version,
    capabilities: {
      experimental: None,
      logging: Some(true),
      completions: None,
      prompts: Some({ list_changed: Some(true) }),
      resources: Some({ subscribe: None, list_changed: Some(true) }),
      tools: Some({ list_changed: Some(true) }),
      tasks: None,
    },
    server_info: { name: "moonmcp", title: None, version: "0.1.0" },
    instructions: Some("be useful"),
    meta: None,
  }
  let json = @types.InitializeResult::to_json(result)
  guard json is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("protocolVersion"), Some(Json::string("2025-11-25")))
  guard obj.get("capabilities") is Some(Object(caps)) else {
    fail("expected capabilities")
  }
  assert_eq(caps.get("logging") is Some(Object(_)), true)
  let decoded : @types.InitializeResult = @json.from_json(json)
  assert_eq(decoded, result)
}

test "call tool result error flag round trips" {
  let ok = @types.CallToolResult::new([@types.text_block("done")])
  assert_false(ok.is_error)
  let err = @types.CallToolResult::error("boom")
  assert_true(err.is_error)
  let decoded : @types.CallToolResult = @json.from_json(
    @types.CallToolResult::to_json(err),
  )
  assert_eq(decoded, err)
  guard decoded.content[0] is @types.Text(text~, ..) else {
    fail("expected text block")
  }
  assert_eq(text, "boom")
}

test "jsonrpc request frame parses and serialises" {
  let frame : Map[String, Json] = {
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(1),
    "method": Json::string("tools/call"),
    "params": Json::object({
      "name": Json::string("add"),
      "arguments": Json::object({ "a": Json::number(1) }),
    }),
  }
  let message = @types.parse_message(frame.to_json())
  guard message is @types.Request(id~, method~, params~) else {
    fail("expected request")
  }
  assert_eq(id, @types.Number(id=1))
  assert_eq(method, "tools/call")
  let re_encoded = @types.JSONRPCMessage::to_json(message)
  guard re_encoded is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("jsonrpc"), Some(Json::string("2.0")))
}

test "client request parses from a frame" {
  let request = @types.parse_client_request(
    Json::object({
      "method": Json::string("prompts/get"),
      "params": Json::object({
        "name": Json::string("welcome"),
        "arguments": Json::object({ "user": Json::string("heke") }),
      }),
    }),
  )
  guard request is @types.GetPrompt(params) else { fail("expected get prompt") }
  assert_eq(params.name, "welcome")
  guard params.arguments is Some(arguments) else { fail("expected arguments") }
  assert_eq(arguments.get("user"), Some(Json::string("heke")))
}

test "server request frame builder" {
  let frame = @types.server_request_frame(
    @types.Text(id="2"),
    @types.ListRoots(meta=None),
  )
  guard frame is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("id"), Some(Json::string("2")))
  assert_eq(obj.get("method"), Some(Json::string("roots/list")))
  let parsed = @types.parse_server_request(frame)
  assert_eq(parsed, @types.ListRoots(meta=None))
}

test "server notification frames" {
  let list_changed = @types.ToolListChanged
  let json = @types.ServerNotification::to_json(list_changed)
  guard json is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("method"), Some(Json::string("notifications/tools/list_changed")))
  assert_eq(obj.get("jsonrpc"), Some(Json::string("2.0")))

  let progress = @types.Progress(
    {
      progress_token: "t1",
      progress: 0.5,
      message: Some("halfway"),
      total: None,
    },
  )
  let progress_json = @types.ServerNotification::to_json(progress)
  guard progress_json is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("method"), Some(Json::string("notifications/progress")))
}

test "discover result flattens the wrapped payload" {
  let result : @types.DiscoverResult = {
    result_type: "CallToolResult",
    result: Json::object({
      "content": Json::array([]),
      "isError": Json::boolean(false),
    }),
    meta: None,
  }
  let json = @types.DiscoverResult::to_json(result)
  guard json is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("resultType"), Some(Json::string("CallToolResult")))
  assert_eq(obj.get("content") is Some(Array(_)), true)
  let decoded : @types.DiscoverResult = @json.from_json(json)
  assert_eq(decoded.result_type, "CallToolResult")
}

test "elicit result actions" {
  let accepted = @types.ElicitResult::accept({ "value": Json::string("yes") })
  assert_eq(accepted.action, "accept")
  let declined = @types.ElicitResult::decline()
  let decoded : @types.ElicitResult = @json.from_json(
    @types.ElicitResult::to_json(declined),
  )
  assert_eq(decoded, declined)
}

test "error response frame" {
  let error_data : @types.ErrorData = {
    code: @types.invalid_params,
    message: "missing",
    data: None,
  }
  let message : @types.JSONRPCMessage = @types.JSONRPCMessage::Error(id=@types.Number(id=7), error=error_data)
  let json = @types.JSONRPCMessage::to_json(message)
  guard json is Object(obj) else { fail("expected object") }
  guard obj.get("error") is Some(Object(err)) else { fail("expected error") }
  assert_eq(err.get("code"), Some(Json::number(-32602)))
  let parsed = @types.parse_message(json)
  assert_eq(parsed, message)
}
