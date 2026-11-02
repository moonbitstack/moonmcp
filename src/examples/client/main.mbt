///|
/// A client and the server it talks to in the same program: the tools are
/// listed, one is called, and the progress a handler reports is printed as it
/// arrives.
///
///     moon run src/examples/client --target native
async fn main {
  let mcp = @moonmcp.Server::new("client demo", version="1.0.0")
  mcp.tool_context("count", async fn(
    args : Map[String, Json],
    context : @moonmcp.Context,
  ) {
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
    @moonmcp.ToolResult::new(content=[
      @moonmcp.text_block("counted to \{up_to}"),
    ])
  })
  let client = @moonmcp.Client::connect(
    @moonmcp.Memory::new(mcp),
    protocol_version="2026-07-28",
  )
  for tool in client.list_tools() {
    println("tool: \{tool.name}")
  }
  let reply = client.call_tool(
    "count",
    arguments={ "up_to": 2 },
    progress_token=Json::string("p-1"),
    on_notification=fn(message) { println("progress: \{message.stringify()}") },
  )
  println("result: \{reply.to_json().stringify()}")
  client.close()
}
