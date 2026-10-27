///|
test "message wraps text and content blocks" {
  let text = @prompts.Message::text("hello")
  assert_eq(text.role, @types.User)
  assert_eq(text.content, @types.text_block("hello"))
  let assistant = @prompts.Message::text("hi", role=@types.Assistant)
  assert_eq(assistant.role, @types.Assistant)
  let wire = assistant.to_mcp_prompt_message()
  assert_eq(wire.role, @types.Assistant)
}

///|
test "prompt result renders to wire messages" {
  let result = @prompts.PromptResult::new(
    [
      @prompts.Message::text("What's the weather?"),
      @prompts.Message::text("It's sunny.", role=@types.Assistant),
    ],
    description="A chat",
  )
  let wire = result.to_mcp_prompt_result()
  assert_eq(wire.description, Some("A chat"))
  assert_eq(wire.messages.length(), 2)
  assert_eq(wire.messages[1].role, @types.Assistant)
}

///|
async test "prompt renders text and message lists" {
  let prompt = @prompts.Prompt::new(
    "greet",
    render_fn=fn(args) {
      match args.get("user") {
        Some(Json::String(name)) =>
          @prompts.RenderedPrompt::Text("hello \{name}")
        _ => @prompts.RenderedPrompt::Messages([])
      }
    },
    description="Greet a user",
  )
  let result = prompt.render_result({ "user": Json::string("heke") })
  assert_eq(result.messages.length(), 1)
  assert_eq(result.messages[0].content, @types.text_block("hello heke"))
  assert_eq(result.description, Some("Greet a user"))
}

///|
test "prompt wire form carries arguments and meta" {
  let prompt = @prompts.Prompt::new(
    "review",
    render_fn=fn(_) { @prompts.RenderedPrompt::Text("ok") },
    arguments=[
      {
        name: "language",
        title: None,
        description: Some("Target language"),
        required: Some(true),
      },
    ],
  )
  let wire = prompt.to_mcp_prompt()
  assert_eq(wire.name, "review")
  assert_eq(wire.arguments.unwrap()[0].name, "language")
  assert_eq(wire.meta is Some(_), true)
  assert_eq(@component.Component::key(prompt), "prompt:review@")
}

///|
test "input required prompt result keeps empty messages" {
  let request : @types.InputRequest = { id: "q1", request: Json::object({}), }
  let ask : @types.InputRequiredResult = {
    input_requests: [request],
    request_state: None,
    meta: None,
  }
  let result = @prompts.PromptResult::input_required(ask)
  assert_true(result.is_input_required())
  assert_eq(result.messages.length(), 0)
}
