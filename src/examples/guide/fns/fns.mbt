// The same server as `ann`, written by registering each capability on it: the
// form the annotations generate, and the one to reach for when a capability is
// decided at run time.

///|
/// The server the guide's sections build between them.
pub fn server() -> @moonmcp.Server {
  let mcp = @moonmcp.Server::new("guide", version="1.0.0")
  add_tools(mcp)
  add_resources(mcp)
  add_review(mcp)
  mcp
}

///|
/// The server with the counting tool on it.
pub fn with_counter() -> @moonmcp.Server {
  let mcp = server()
  add_counter(mcp)
  mcp
}

///|
/// The server with a capability held back and a cache in front of it.
pub fn extended() -> @moonmcp.Server {
  with_extensions(server())
}

// guide:first

///|
/// Two tools, each one call on the server.
pub fn add_tools(mcp : @moonmcp.Server) -> Unit {
  mcp.tool(
    "add",
    args => {
      guard args.get("a") is Some(Number(a, ..)) &&
        args.get("b") is Some(Number(b, ..)) else {
        raise @exceptions.Tool("a and b must be numbers")
      }
      Json(a + b)
    },
    description="Add two numbers",
    input_schema={
      "type": "object",
      "properties": { "a": { "type": "number" }, "b": { "type": "number" } },
      "required": ["a", "b"],
    },
  )
  mcp.tool(
    "greet",
    args => {
      let name = match args.get("name") {
        Some(String(name)) => name
        _ => "stranger"
      }
      let language = match args.get("language") {
        Some(String(language)) => language
        _ => ""
      }
      if language == "zh" {
        Json("你好，" + name)
      } else {
        Json("hello, " + name)
      }
    },
    description="Greet someone, in Chinese when asked",
    input_schema={
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "language": { "type": "string" },
      },
      "required": ["name"],
    },
  )
}
// end

// guide:resources

///|
/// A resource at a fixed URI, and a template for the ones with an id in them.
pub fn add_resources(mcp : @moonmcp.Server) -> Unit {
  mcp.resource(
    "config://app",
    () => "{\"theme\":\"dark\",\"language\":\"en\"}",
    description="The application settings",
    mime_type="application/json",
  )
  mcp.template("users://{id}/profile", params => {
    let id = match params.get("id") {
      Some(String(id)) => id
      _ => "?"
    }
    "profile of user " + id
  })
}
// end

// guide:prompts

///|
/// A prompt whose arguments a client fills in.
pub fn add_review(mcp : @moonmcp.Server) -> Unit {
  mcp.prompt(
    "review",
    args => {
      let code = match args.get("code") {
        Some(String(code)) => code
        _ => ""
      }
      let what = match args.get("focus") {
        Some(String(focus)) => " Focus on " + focus + "."
        _ => ""
      }
      "Review this code." + what + "\n\n" + code
    },
    description="Ask for a code review",
    arguments=[
      { name: "code", title: None, description: None, required: Some(true), },
      { name: "focus", title: None, description: None, required: Some(false), },
    ],
  )
}
// end

// guide:context

///|
/// A tool that sees the request it serves, and reports on it while it works.
pub fn add_counter(mcp : @moonmcp.Server) -> Unit {
  mcp.tool_context(
    "count",
    async fn(args : Map[String, Json], context : @context.Context) {
      let up_to = match args.get("up_to") {
        Some(Number(value, ..)) => value.to_int()
        _ => 3
      }
      if up_to < 0 {
        raise @exceptions.Tool("up_to must not be negative")
      }
      for step in 0..<up_to {
        context.report_progress(
          progress=(step + 1).to_double(),
          total=up_to.to_double(),
          message="step \{step + 1}",
        ) catch {
          _ => ()
        }
      }
      @tools.ToolResult::new(content=[@types.text_block("counted to \{up_to}")])
    },
    description="Count to a number, reporting progress as it goes",
    input_schema={
      "type": "object",
      "properties": { "up_to": { "type": "number" } },
    },
  )
}
// end

// guide:extend

///|
/// Hold a capability back from the listing, and put a cache in front of every
/// request.
pub fn with_extensions(mcp : @moonmcp.Server) -> @moonmcp.Server {
  mcp.add_transform(@transforms.Hidden::new(names=["greet"]))
  mcp.use_layer(@layers.Caching::new(ttl_ms=1_000).layer())
  mcp
}
// end
