///|
/// A small server with one of everything: two tools, a resource, a resource
/// template and a prompt. The HTTP and stdio examples serve this same server.
pub fn server() -> @server.Server {
  let mcp = @server.Server::new(
    "demo",
    version="1.0.0",
    instructions="Arithmetic and greetings, for trying a client out.",
  )
  mcp.tool(
    "add",
    args => {
      guard args.get("a") is Some(Number(a, ..)) &&
        args.get("b") is Some(Number(b, ..)) else {
        raise @exceptions.Tool("a and b must be numbers")
      }
      { "sum": Json(a + b) }
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
      guard args.get("name") is Some(String(name)) else {
        raise @exceptions.Tool("name must be a string")
      }
      Json("hello, " + name)
    },
    description="Greet someone by name",
    input_schema={
      "type": "object",
      "properties": { "name": { "type": "string" } },
      "required": ["name"],
    },
  )
  mcp.tool_context(
    "count",
    async fn(args : Map[String, Json], context : @context.Context) {
      let up_to = match args.get("up_to") {
        Some(Number(value, ..)) => value.to_int()
        _ => 3
      }
      for i in 0..<up_to {
        let step = i + 1
        context.report_progress(
          progress=step.to_double(),
          total=(up_to + 1).to_double(),
          message="step \{step}",
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
  mcp.resource(
    "config://app",
    () => "{\"theme\":\"dark\"}",
    name="app config",
    mime_type="application/json",
  )
  mcp.template("users://{id}/profile", params => {
    guard params.get("id") is Some(String(id)) else { "unknown" }
    "profile of user " + id
  })
  mcp.prompt(
    "review",
    args => {
      guard args.get("code") is Some(String(code)) else { "Review this code." }
      "Review this code:\n" + code
    },
    description="Ask for a code review",
    arguments=[
      { name: "code", title: None, description: None, required: Some(true), },
    ],
  )
  mcp
}
