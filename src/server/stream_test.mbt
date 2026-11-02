///|
fn streaming_demo() -> @server.Server {
  let mcp = @server.Server::new("streams", version="1.0.0")
  mcp.tool_context("count", async fn(args, context) {
    context.report_progress(progress=1.0, total=2.0, message="starting") catch {
      _ => ()
    }
    context.info("half done") catch {
      _ => ()
    }
    context.report_progress(progress=2.0, total=2.0) catch {
      _ => ()
    }
    let n = match args.get("n") {
      Some(Number(value, ..)) => value
      _ => 0.0
    }
    @tools.ToolResult::new(content=[@types.text_block(n.to_string())])
  })
  mcp
}

///|
/// The first of `headers` named `name`.
fn header_of(headers : Array[(String, String)], name : String) -> String? {
  headers.iter().find_first(h => h.0 == name).map(h => h.1)
}

///|
async fn post_stream(
  client : @testing.Client,
  message : Json,
  accept~ : String = "application/json, text/event-stream",
) -> @client.TestResponse {
  client.post("/mcp", body=@utf8.encode(message.stringify()), headers=[
    ("content-type", "application/json"),
    ("accept", accept),
    ("mcp-protocol-version", "2026-07-28"),
    (
      "mcp-method",
      match message {
        Object(obj) =>
          match obj.get("method") {
            Some(String(op)) => op
            _ => ""
          }
        _ => ""
      },
    ),
    ("mcp-name", "count"),
  ])
}

///|
/// The `data:` payloads of an SSE body, in order.
fn sse_messages(body : String) -> Array[Json] {
  let out = []
  for chunk in body.split("\n\n") {
    let mut payload = ""
    for line in chunk.split("\n") {
      if line.has_prefix("data: ") {
        payload = payload + line.exact_view(start=6).to_owned()
      }
    }
    if !payload.is_empty() {
      let parsed : Json? = try @json.parse(payload) catch {
        _ => None
      } noraise {
        json => Some(json)
      }
      if parsed is Some(json) {
        out.push(json)
      }
    }
  }
  out
}

///|
async test "progress and log messages arrive on the response stream" {
  let app = streaming_demo().to_asgi()
  let client = @testing.Client::new(app)
  let response = post_stream(
    client,
    request(1, "tools/call", {
      "name": Json::string("count"),
      "arguments": { "n": 3 },
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "progressToken": "p-1",
      },
    }),
  )
  assert_eq(response.status, 200)
  assert_eq(
    header_of(response.headers, "content-type"),
    Some("text/event-stream"),
  )
  assert_eq(header_of(response.headers, "x-accel-buffering"), Some("no"))
  let messages = sse_messages(@utf8.decode_lossy(response.body[:]))
  assert_eq(messages.length(), 4)
  assert_eq(dig(messages[0], ["method"]), Some("notifications/progress"))
  assert_eq(dig(messages[0], ["params", "progressToken"]), Some("p-1"))
  assert_eq(dig(messages[1], ["method"]), Some("notifications/message"))
  assert_eq(dig(messages[1], ["params", "level"]), Some("info"))
  assert_eq(dig(messages[2], ["method"]), Some("notifications/progress"))
  assert_eq(dig(messages[3], ["id"]), Some(Json(1)))
  assert_eq(dig(messages[3], ["result", "resultType"]), Some("complete"))
  assert_eq(
    dig(messages[3], ["result", "content"]),
    Some([{ "type": Json::string("text"), "text": Json::string("3") }]),
  )
}

///|
async test "the same call without a progress token is one JSON object" {
  let app = streaming_demo().to_asgi()
  let client = @testing.Client::new(app)
  let response = post_stream(
    client,
    request(2, "tools/call", {
      "name": Json::string("count"),
      "arguments": { "n": 4 },
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
      },
    }),
  )
  assert_eq(response.status, 200)
  assert_eq(
    header_of(response.headers, "content-type"),
    Some("application/json"),
  )
  let reply : Json = @json.parse(@utf8.decode_lossy(response.body[:])) catch {
    _ => fail("the reply is not JSON")
  }
  assert_eq(dig(reply, ["result", "resultType"]), Some("complete"))
}

///|
async test "a client that accepts no stream gets one JSON object" {
  let app = streaming_demo().to_asgi()
  let client = @testing.Client::new(app)
  let response = post_stream(
    client,
    request(3, "tools/call", {
      "name": Json::string("count"),
      "arguments": { "n": 5 },
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "progressToken": "p-2",
      },
    }),
    accept="application/json",
  )
  assert_eq(
    header_of(response.headers, "content-type"),
    Some("application/json"),
  )
  assert_eq(response.status, 200)
}

///|
async test "a subscription acknowledges, then reports a new tool" {
  let mcp = streaming_demo()
  let seen : Array[Json] = []
  let channel = @server.Channel::new(
    emit=fn(message) { seen.push(message) },
    headers=Map([]),
    gone=fn() { seen.length() >= 2 },
  )
  let id = Json::number(9.0)
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    group.spawn_bg(async fn() {
      mcp.serve_subscription(
        id,
        { "notifications": { "toolsListChanged": true } },
        channel,
      ) catch {
        _ => ()
      }
    })
    // Wait for the acknowledgement before changing anything, so the
    // subscription is in place when the change is made.
    for i in 0..<100 {
      if seen.length() > 0 {
        break
      }
      @async.pause()
      ignore(i)
    }
    mcp.notify_tools_changed()
    for i in 0..<100 {
      if seen.length() >= 2 {
        break
      }
      @async.pause()
      ignore(i)
    }
  })
  assert_eq(seen.length(), 2)
  assert_eq(
    dig(seen[0], ["method"]),
    Some("notifications/subscriptions/acknowledged"),
  )
  assert_eq(
    dig(seen[0], ["params", "notifications", "toolsListChanged"]),
    Some(true),
  )
  assert_eq(
    dig(seen[0], ["params", "_meta", "io.modelcontextprotocol/subscriptionId"]),
    Some(Json::number(9.0)),
  )
  assert_eq(dig(seen[1], ["method"]), Some("notifications/tools/list_changed"))
  assert_eq(
    dig(seen[1], ["_meta", "io.modelcontextprotocol/subscriptionId"]),
    Some(Json::number(9.0)),
  )
}

///|
async test "a subscription hears only what it asked for" {
  let mcp = streaming_demo()
  let seen : Array[Json] = []
  let channel = @server.Channel::new(
    emit=fn(message) { seen.push(message) },
    headers=Map([]),
    gone=fn() { seen.length() >= 2 },
  )
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    group.spawn_bg(async fn() {
      mcp.serve_subscription(
        Json::number(10.0),
        { "notifications": { "promptsListChanged": true } },
        channel,
      ) catch {
        _ => ()
      }
    })
    for i in 0..<100 {
      if seen.length() > 0 {
        break
      }
      @async.pause()
      ignore(i)
    }
    mcp.notify_tools_changed()
    mcp.notify_prompts_changed()
    for i in 0..<200 {
      if seen.length() >= 2 {
        break
      }
      @async.pause()
      ignore(i)
    }
    mcp.notify_prompts_changed()
    @async.pause()
  })
  assert_eq(seen.length(), 2)
  assert_eq(
    dig(seen[1], ["method"]),
    Some("notifications/prompts/list_changed"),
  )
}

///|
async test "a resource update reaches only the subscriber that named it" {
  let mcp = streaming_demo()
  let seen : Array[Json] = []
  let channel = @server.Channel::new(
    emit=fn(message) { seen.push(message) },
    headers=Map([]),
    gone=fn() { seen.length() >= 2 },
  )
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    group.spawn_bg(async fn() {
      mcp.serve_subscription(
        Json::number(11.0),
        { "notifications": { "resourceSubscriptions": ["config://app"] } },
        channel,
      ) catch {
        _ => ()
      }
    })
    for i in 0..<100 {
      if seen.length() > 0 {
        break
      }
      @async.pause()
      ignore(i)
    }
    mcp.notify_resource_updated("config://other")
    mcp.notify_resource_updated("config://app")
    for i in 0..<100 {
      if seen.length() >= 2 {
        break
      }
      @async.pause()
      ignore(i)
    }
  })
  assert_eq(seen.length(), 2)
  assert_eq(dig(seen[1], ["method"]), Some("notifications/resources/updated"))
  assert_eq(dig(seen[1], ["params", "uri"]), Some("config://app"))
}

///|
async test "closing the input closes an open subscription with it" {
  let mcp = streaming_demo()
  let to_server : @aqueue.Queue[String?] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  let lines : Array[String] = []
  let listen : Json = {
    "jsonrpc": "2.0",
    "id": Json::number(1.0),
    "method": Json::string("subscriptions/listen"),
    "params": {
      "notifications": { "toolsListChanged": true },
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
      },
    },
  }
  to_server.put(Some(listen.stringify()))
  to_server.put(None)
  // Returning at all is the assertion: a stream left waiting on a queue nobody
  // feeds holds the process open, which is what this test is here to catch.
  mcp.serve_lines(() => to_server.get(), line => lines.push(line))
  assert_eq(lines.length() >= 1, true)
  assert_eq(lines[0].contains("acknowledged"), true)
}
