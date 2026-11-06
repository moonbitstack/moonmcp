// A server asking its client something, with no wire between them: the same
// path sampling, elicitation and roots take over any transport.

///|
test "every default the requested schema names is filled in" {
  let schema : Map[String, Json] = {
    "type": Json::string("object"),
    "properties": {
      "name": { "type": "string", "default": "John Doe" },
      "age": { "type": "integer", "default": Json::number(30.0) },
      "verified": { "type": "boolean", "default": Json::boolean(true) },
      "empty": { "type": "string" },
    },
  }
  let filled = @client.fill_defaults(Some(schema), Map([]))
  assert_eq(filled.get("name"), Some(Json::string("John Doe")))
  assert_eq(filled.get("age"), Some(Json::number(30.0)))
  assert_eq(filled.get("verified"), Some(Json::boolean(true)))
  assert_eq(filled.get("empty"), None)
  // What the person did fill in stays as it is.
  let given : Map[String, Json] = { "name": Json::string("Ada") }
  assert_eq(
    @client.fill_defaults(Some(schema), given).get("name"),
    Some(Json::string("Ada")),
  )
}

///|
test "a schema with nothing to default leaves the answer alone" {
  let content : Map[String, Json] = { "a": Json::string("1") }
  assert_eq(@client.fill_defaults(None, content).length(), 1)
}

///|
async test "a client answers an elicitation the server asks for" {
  let asked : Ref[String?] = Ref(None)
  let handlers = @client.Handlers::new(elicitation=request => {
    asked.val = Some(request.message)
    @types.ElicitResult::accept(Map([]))
  })
  let request : Json = {
    "jsonrpc": "2.0",
    "id": Json::number(7.0),
    "method": Json::string("elicitation/create"),
    "params": {
      "message": Json::string("your name"),
      "requestedSchema": {
        "type": Json::string("object"),
        "properties": { "name": { "type": "string", "default": "Ada" } },
      },
    },
  }
  let reply = handlers.answer(request).unwrap()
  assert_eq(asked.val, Some("your name"))
  assert_eq(dig(reply, ["id"]), Some(Json::number(7.0)))
  assert_eq(dig(reply, ["result", "action"]), Some(Json::string("accept")))
  assert_eq(
    dig(reply, ["result", "content", "name"]),
    Some(Json::string("Ada")),
  )
}

///|
async test "a request the client does not serve is refused, not dropped" {
  let handlers = @client.Handlers::none()
  let request : Json = {
    "jsonrpc": "2.0",
    "id": Json::string("r-1"),
    "method": Json::string("sampling/createMessage"),
    "params": { "messages": Json::array([]), "maxTokens": Json::number(16.0) },
  }
  let reply = handlers.answer(request).unwrap()
  assert_eq(dig(reply, ["error", "code"]), Some(Json::number(-32601.0)))
}

///|
async test "a notification is not answered" {
  let handlers = @client.Handlers::new(roots=() => { roots: [], meta: None, })
  let note : Json = {
    "jsonrpc": "2.0",
    "method": Json::string("notifications/progress"),
    "params": { "progressToken": "p", "progress": 1.0 },
  }
  assert_eq(handlers.answer(note), None)
}

///|
async test "the client answers over an in-memory transport" {
  let mcp = @server.Server::new("asker", version="1.0.0")
  mcp.tool_context("greet", (_args, context) => {
    let answered = match context.input_responses().get("0") {
      Some(Object(reply)) =>
        match reply.get("content") {
          Some(Object(content)) =>
            match content.get("name") {
              Some(String(name)) => Some(name)
              _ => None
            }
          _ => None
        }
      _ => None
    }
    match answered {
      Some(name) =>
        @tools.ToolResult::new(content=[@types.text_block("hello " + name)])
      _ =>
        @tools.ToolResult::input_required({
          input_requests: [
            {
              id: "0",
              request: {
                "method": Json::string("elicitation/create"),
                "params": {
                  "message": Json::string("your name"),
                  "requestedSchema": { "type": "object" },
                },
              },
            },
          ],
          request_state: None,
          meta: None,
        })
    }
  })
  let client = @client.Client::connect(
    @client.Memory::new(mcp),
    protocol_version="2025-11-25",
    handlers=@client.Handlers::new(elicitation=_request => {
      @types.ElicitResult::accept({ "name": Json::string("Ada") })
    }),
  )
  let result = client.call_tool("greet", arguments=Map([]))
  match result.content[0] {
    @types.Text(text~, ..) => assert_eq(text, "hello Ada")
    _ => fail("expected text")
  }
}
