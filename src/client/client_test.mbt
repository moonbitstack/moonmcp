// The client against the server: in the same program, over a pair of line
// streams, and over HTTP.

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
  mcp.resource("config://app", () => "dark")
  mcp.prompt("review", _ => "review this")
  mcp
}

///|
async test "a client reaches a server in the same program" {
  let client = @client.Client::connect(
    @client.Memory::new(demo_server()),
    protocol_version="2026-07-28",
  )
  let tools = client.list_tools()
  assert_eq(tools.length(), 1)
  assert_eq(tools[0].name, "add")
  let result = client.call_tool("add", arguments={ "a": 2, "b": 3 })
  assert_eq(result.is_error, false)
  assert_eq(result.content.length(), 1)
  assert_eq(result.structured_content.unwrap().get("sum"), Some(Json(5)))
  let resource = client.read_resource("config://app")
  assert_eq(resource.contents.length(), 1)
  let prompt = client.get_prompt("review")
  let rendered = match prompt.messages[0].content {
    @types.Text(text~, ..) => text
    _ => ""
  }
  assert_eq(rendered, "review this")
  client.close()
}

///|
async test "a refused call raises the error the server gave" {
  let client = @client.Client::connect(
    @client.Memory::new(demo_server()),
    protocol_version="2026-07-28",
  )
  let outcome = try client.call_tool("no_such_tool") catch {
    @client.Refused(code~, message~, ..) => (code, message)
    _ => (-1, "not refused")
  } noraise {
    _ => (-1, "answered")
  }
  assert_eq(outcome.0, @types.invalid_params)
  assert_eq(outcome.1.contains("no_such_tool"), true)
}

///|
async test "a client reports what a handler sends while it works" {
  let mcp = demo_server()
  mcp.tool_context("slow", async fn(_args, context) {
    context.report_progress(progress=1.0, total=2.0) catch {
      _ => ()
    }
    context.report_progress(progress=2.0, total=2.0) catch {
      _ => ()
    }
    @tools.ToolResult::new(content=[@types.text_block("done")])
  })
  let client = @client.Client::connect(
    @client.Memory::new(mcp),
    protocol_version="2026-07-28",
  )
  let seen = []
  let result = client.call_tool("slow", progress_token=Json::string("p-1"), on_notification=fn(
    message,
  ) {
    seen.push(message)
  })
  assert_eq(result.content.length(), 1)
  assert_eq(seen.length(), 2)
  guard seen[0] is Object(obj) else { fail("expected object") }
  assert_eq(obj.get("method"), Some(Json::string("notifications/progress")))
}

///|
async test "a client over a legacy revision runs the handshake" {
  let client = @client.Client::connect(
    @client.Memory::new(demo_server()),
    protocol_version="2025-11-25",
  )
  assert_eq(client.protocol_version(), "2025-11-25")
  assert_eq(client.server_info().unwrap().name, "demo")
  let tools = client.list_tools()
  assert_eq(tools.length(), 1)
}

///|
async test "a client asks, is asked back, and answers on the retry" {
  let mcp = demo_server()
  mcp.tool_context("greet", async fn(_args, context) {
    @async.pause()
    match context.input_responses().get("0") {
      Some(String(name)) =>
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
          request_state: Some("state-1"),
          meta: None,
        })
    }
  })
  let client = @client.Client::connect(
    @client.Memory::new(mcp),
    protocol_version="2026-07-28",
  )
  let first = client.request(@types.method_tools_call, params={
    "name": Json::string("greet"),
    "arguments": Json::object(Map([])),
  })
  println("first: \{Json(first).stringify()}")
  assert_eq(first.get("resultType"), Some(Json::string("input_required")))
  assert_eq(first.get("requestState"), Some(Json::string("state-1")))
  let second = client.request(@types.method_tools_call, params={
    "name": Json::string("greet"),
    "arguments": Json::object(Map([])),
    "inputResponses": { "0": Json::string("Ada") },
    "requestState": Json::string("state-1"),
  })
  assert_eq(second.get("resultType"), Some(Json::string("complete")))
  assert_eq(dig(Json(second), ["structuredContent"]), None)
  assert_eq(
    dig(Json(second), ["content"]),
    Some([{ "type": Json::string("text"), "text": Json::string("hello Ada") }]),
  )
}

///|
/// The first of `headers` named `name`.
fn dig(json : Json, path : Array[String]) -> Json? {
  let mut at = json
  for key in path {
    guard at is Object(obj) && obj.get(key) is Some(next) else { return None }
    at = next
  }
  Some(at)
}

///|
async test "a client and a server over one pair of line streams" {
  let mcp = demo_server()
  let to_server : @aqueue.Queue[String?] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  let to_client : @aqueue.Queue[String?] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    group.spawn_bg(async fn() {
      mcp.serve_lines(() => to_server.get(), line => to_client.put(Some(line))) catch {
        _ => ()
      }
    })
    let client = @client.Client::connect(
      @client.Lines::new(read=() => to_client.get(), write=line => {
        to_server.put(Some(line))
      }),
      protocol_version="2026-07-28",
    )
    let tools = client.list_tools()
    assert_eq(tools.length(), 1)
    let result = client.call_tool("add", arguments={ "a": 1, "b": 4 })
    assert_eq(result.structured_content.unwrap().get("sum"), Some(Json(5)))
    to_server.put(None)
  })
}

///|
async test "a withdrawn request tells its handler to stop" {
  let mcp = @server.Server::new("slow")
  mcp.tool_context("wait", async fn(_args, context) {
    let mut rounds = 0
    while !context.is_cancelled() {
      @async.pause()
      rounds += 1
      if rounds > 200 {
        raise @exceptions.Tool("never withdrawn")
      }
    }
    raise @exceptions.Tool("withdrawn after \{rounds} rounds")
  })
  let to_server : @aqueue.Queue[String?] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  let to_client : @aqueue.Queue[String?] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    group.spawn_bg(async fn() {
      mcp.serve_lines(() => to_server.get(), line => to_client.put(Some(line))) catch {
        _ => ()
      }
    })
    let call : Json = {
      "jsonrpc": "2.0",
      "id": Json::number(1.0),
      "method": Json::string("tools/call"),
      "params": {
        "name": Json::string("wait"),
        "arguments": Json::object(Map([])),
        "_meta": {
          "io.modelcontextprotocol/protocolVersion": "2026-07-28",
          "io.modelcontextprotocol/clientCapabilities": {},
        },
      },
    }
    to_server.put(Some(call.stringify()))
    let cancel : Json = {
      "jsonrpc": "2.0",
      "method": Json::string("notifications/cancelled"),
      "params": {
        "requestId": Json::number(1.0),
        "reason": Json::string("changed my mind"),
      },
    }
    to_server.put(Some(cancel.stringify()))
    let mut reply = ""
    while reply.is_empty() {
      match to_client.get() {
        Some(line) => reply = line
        None => break
      }
    }
    assert_eq(reply.contains("withdrawn after"), true)
    to_server.put(None)
  })
}
