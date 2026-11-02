///|
fn demo_server() -> @server.Server {
  let mcp = @server.Server::new("demo", version="1.0.0")
  mcp.tool("add", args => {
    let a = match args.get("a") {
      Some(Number(value, ..)) => value
      _ => 0.0
    }
    let b = match args.get("b") {
      Some(Number(value, ..)) => value
      _ => 0.0
    }
    { "sum": Json(a + b) }
  })
  mcp.tool_context("count", async fn(args, context) {
    context.info("counting") catch {
      _ => ()
    }
    context.report_progress(progress=1.0, total=1.0) catch {
      _ => ()
    }
    let n = match args.get("n") {
      Some(Number(value, ..)) => value
      _ => 0.0
    }
    @tools.ToolResult::new(content=[@types.text_block(n.to_string())])
  })
  mcp.resource("config://app", () => "dark")
  mcp
}

///|
async test "the http transport reaches a server over a socket" {
  let app = demo_server().to_asgi()
  let port = 12080
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    group.spawn_bg(
      async fn() { @mooncat.serve(app, port~) catch { _ => () } },
      no_wait=true,
    )
    for i in 0..<50 {
      let ready = try @net.Client::Client("http://127.0.0.1:\{port}") catch {
        _ => None
      } noraise {
        client => {
          client.close()
          Some(())
        }
      }
      if ready is Some(_) {
        break
      }
      @async.sleep(100)
      ignore(i)
    }
    let client = @client.Client::connect(
      @http.Http::new("http://127.0.0.1:\{port}/mcp"),
      protocol_version="2026-07-28",
    )
    let tools = client.list_tools()
    assert_eq(tools.length(), 2)
    let result = client.call_tool("add", arguments={ "a": 2, "b": 8 })
    assert_eq(result.structured_content.unwrap().get("sum"), Some(Json(10)))
    let seen = []
    let counted = client.call_tool(
      "count",
      arguments={ "n": 7 },
      progress_token=Json::string("p-1"),
      on_notification=fn(message) { seen.push(message) },
    )
    assert_eq(counted.content.length(), 1)
    assert_eq(seen.length(), 2)
    let resource = client.read_resource("config://app")
    assert_eq(resource.contents.length(), 1)
    client.close()
  })
}
