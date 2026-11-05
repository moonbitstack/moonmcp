// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// What a client of the revisions before 2026-07-28 expects of a server. The official suite runs the
// same ground from outside, in `scripts/interop/check_conformance.sh`; these name each behaviour and
// its other side.

///|
fn legacy_demo(ask_timeout_ms? : Int32, ask_rounds? : Int32) -> @server.Server {
  let mcp = @server.Server::new("legacy", ask_timeout_ms?, ask_rounds?)
  mcp.tool_context("noisy", async fn(_, context) {
    context.report_progress(progress=1.0, total=2.0)
    context.info("working")
    @tools.ToolResult::new(content=[@types.text_block("done")])
  })
  mcp.tool("quiet", _ => Json::string("done"))
  mcp.tool_context("ask", (_, context) => {
    match context.input_responses().get("name") {
      Some(Object({ "content": Object({ "name": String(name), .. }), .. })) => {
        let state = context.request_state().unwrap_or("none")
        @tools.ToolResult::new(content=[
          @types.text_block("hello \{name}, state \{state}"),
        ])
      }
      _ =>
        @tools.ToolResult::input_required({
          input_requests: [
            {
              id: "name",
              request: {
                "method": "elicitation/create",
                "params": { "message": "Your name?" },
              },
            },
          ],
          request_state: Some("kept"),
          meta: None,
        })
    }
  })
  mcp.tool_context("ask_forever", (_, _) => {
    @tools.ToolResult::input_required({
      input_requests: [
        {
          id: "again",
          request: { "method": "elicitation/create", "params": {} },
        },
      ],
      request_state: None,
      meta: None,
    })
  })
  mcp
}

///|
fn call(id : Int32, name : String, token? : String) -> Json {
  let params : Map[String, Json] = { "name": Json::string(name) }
  if token is Some(token) {
    params["_meta"] = { "progressToken": Json::string(token) }
  }
  { "jsonrpc": "2.0", "id": id, "method": "tools/call", "params": Json(params) }
}

///|
async fn post_legacy(
  client : @testing.Client,
  message : Json,
  accept~ : String = "application/json, text/event-stream",
) -> @client.TestResponse {
  client.post("/mcp", body=@utf8.encode(message.stringify()), headers=[
    ("content-type", "application/json"),
    ("accept", accept),
    ("mcp-protocol-version", "2025-11-25"),
  ])
}

///|
async fn plain(mcp : @server.Server, op : String, params : Json) -> Json {
  mcp
  .handle({ "jsonrpc": "2.0", "id": 1, "method": op, "params": params })
  .unwrap()
}

///|
async test "a handler's messages turn the reply into a stream, and only then" {
  let client = @testing.Client::new(legacy_demo().to_asgi())
  let noisy = post_legacy(client, call(1, "noisy", token="t"))
  assert_eq(noisy.status, 200)
  assert_eq(header_of(noisy.headers, "content-type"), Some("text/event-stream"))
  let messages = sse_messages(@utf8.decode_lossy(noisy.body[:]))
  assert_eq(messages.length(), 3)
  assert_eq(dig(messages[0], ["method"]), Some("notifications/progress"))
  assert_eq(dig(messages[1], ["method"]), Some("notifications/message"))
  assert_eq(dig(messages[2], ["id"]), Some(Json(1)))
  // Nothing to send but the reply: one JSON object, whatever the client would have taken.
  let quiet = post_legacy(client, call(2, "quiet"))
  assert_eq(header_of(quiet.headers, "content-type"), Some("application/json"))
}

///|
async test "a client that takes no stream gets the reply alone" {
  let client = @testing.Client::new(legacy_demo().to_asgi())
  let response = post_legacy(
    client,
    call(1, "noisy", token="t"),
    accept="application/json",
  )
  assert_eq(
    header_of(response.headers, "content-type"),
    Some("application/json"),
  )
  let reply = @json.parse(@utf8.decode_lossy(response.body[:]))
  assert_eq(dig(reply, ["id"]), Some(Json(1)))
}

///|
async test "logging/setLevel holds back what is below it, and only from the client" {
  let mcp = legacy_demo()
  let initialized = plain(mcp, "initialize", {
    "protocolVersion": "2025-11-25",
    "capabilities": {},
    "clientInfo": { "name": "c", "version": "1" },
  })
  assert_true(
    dig(initialized, ["result", "capabilities", "logging"]) is Some(_),
  )
  let client = @testing.Client::new(mcp.to_asgi())
  let bad = plain(mcp, "logging/setLevel", { "level": "loud" })
  assert_eq(dig(bad, ["error", "code"]), Some(Json(-32602)))
  assert_true(
    dig(plain(mcp, "logging/setLevel", { "level": "warning" }), ["result"])
    is Some(_),
  )
  let held = sse_messages(
    @utf8.decode_lossy(post_legacy(client, call(1, "noisy", token="t")).body[:]),
  )
  assert_eq(held.length(), 2)
  assert_eq(dig(held[0], ["method"]), Some("notifications/progress"))
  assert_eq(dig(held[1], ["id"]), Some(Json(1)))
  ignore(plain(mcp, "logging/setLevel", { "level": "info" }))
  let told = sse_messages(
    @utf8.decode_lossy(post_legacy(client, call(2, "noisy", token="t")).body[:]),
  )
  assert_eq(told.length(), 3)
}

///|
async test "completion/complete is there when a handler is, and declared when it is" {
  let mcp = legacy_demo()
  let asked : Json = {
    "ref": { "type": "ref/prompt", "name": "greet" },
    "argument": { "name": "who", "value": "le" },
    "context": { "arguments": { "lang": "en" } },
  }
  let missing = plain(mcp, "completion/complete", asked)
  assert_eq(dig(missing, ["error", "code"]), Some(Json(-32601)))
  let handshake : Json = {
    "protocolVersion": "2025-11-25",
    "capabilities": {},
    "clientInfo": { "name": "c", "version": "1" },
  }
  assert_true(
    dig(plain(mcp, "initialize", handshake), [
      "result", "capabilities", "completions",
    ])
    is None,
  )
  mcp.completion((request, _) => {
    let lang = request.arguments.bind(args => args.get("lang")).unwrap_or("?")
    {
      values: [
        request.argument.name + ":" + request.argument.value + ":" + lang,
      ],
      total: Some(1),
      has_more: Some(false),
    }
  })
  assert_true(
    dig(plain(mcp, "initialize", handshake), [
      "result", "capabilities", "completions",
    ])
    is Some(_),
  )
  let answered = plain(mcp, "completion/complete", asked)
  assert_eq(
    dig(answered, ["result", "completion", "values"]),
    Some(["who:le:en"]),
  )
  assert_eq(dig(answered, ["result", "completion", "total"]), Some(Json(1)))
}

///|
test "completion parameters read and write as the specification has them" {
  let wire : Json = {
    "ref": { "type": "ref/prompt", "name": "greet" },
    "argument": { "name": "who", "value": "le" },
    "context": { "arguments": { "lang": "en" } },
  }
  let params : @types.CompleteRequestParams = @json.from_json(wire)
  assert_eq(params.argument.value, "le")
  assert_eq(params.arguments.unwrap().get("lang"), Some("en"))
  assert_eq(params.to_json(), wire)
  // `context` is optional, and absent is not empty.
  let bare : @types.CompleteRequestParams = @json.from_json({
    "ref": { "type": "ref/prompt", "name": "greet" },
    "argument": { "name": "who", "value": "" },
  })
  assert_eq(bare.arguments, None)
}

///|
/// A `GET` stream driven by hand, since it has no end of its own for a test client to wait for.
async fn listening(
  mcp : @server.Server,
  during : async () -> Unit,
) -> Array[Json] {
  let app = mcp.to_asgi()
  let gone : @aqueue.Queue[Unit] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  let body = StringBuilder()
  let mut read = false
  let scope = @moonasgi.HttpScope::new(http_method="GET", path="/mcp", headers=[
    ("accept", "text/event-stream"),
  ])
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    group.spawn_bg(async fn() {
      app(
        Http(scope),
        async fn() {
          if !read {
            read = true
            return @moonasgi.Event::HttpRequest(body=b"", more_body=false)
          }
          gone.get()
          @moonasgi.Event::HttpDisconnect
        },
        event => {
          if event is HttpResponseBody(body=chunk, ..) {
            body.write_string(@utf8.decode_lossy(chunk[:]))
          }
        },
      )
    })
    @async.sleep(10)
    during()
    @async.sleep(10)
    gone.put(())
  })
  sse_messages(body.to_string())
}

///|
async test "the GET stream hears list changes, and updates to what was subscribed to" {
  let mcp = legacy_demo()
  let heard = listening(mcp, async fn() {
    mcp.notify_resource_updated("test://a")
    assert_true(
      dig(plain(mcp, "resources/subscribe", { "uri": "test://a" }), ["result"])
      is Some(_),
    )
    mcp.notify_resource_updated("test://a")
    mcp.notify_resource_updated("test://b")
    mcp.notify_tools_changed()
    ignore(plain(mcp, "resources/unsubscribe", { "uri": "test://a" }))
    mcp.notify_resource_updated("test://a")
  })
  assert_eq(heard.length(), 2)
  assert_eq(dig(heard[0], ["method"]), Some("notifications/resources/updated"))
  assert_eq(dig(heard[0], ["params", "uri"]), Some("test://a"))
  assert_eq(dig(heard[1], ["method"]), Some("notifications/tools/list_changed"))
}

///|
async test "a subscription names a uri" {
  let mcp = legacy_demo()
  let bad = plain(mcp, "resources/subscribe", {})
  assert_eq(dig(bad, ["error", "code"]), Some(Json(-32602)))
}

///|
async test "a GET that takes no stream is refused, and so is one of the stateless revision" {
  let client = @testing.Client::new(legacy_demo().to_asgi())
  assert_eq(client.get("/mcp").status, 405)
  let modern = client.get("/mcp", headers=[
    ("accept", "text/event-stream"),
    ("mcp-protocol-version", "2026-07-28"),
  ])
  assert_eq(modern.status, 405)
}

///|
/// Call `name` and answer what it asks once with `reply`, the way a client on another connection
/// would, and give back everything the stream carried.
async fn asked(
  mcp : @server.Server,
  name : String,
  reply : (Json) -> Json,
) -> Array[Json] {
  let client = @testing.Client::new(mcp.to_asgi())
  let mut out = []
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    group.spawn_bg(async fn() {
      let response = post_legacy(client, call(1, name))
      out = sse_messages(@utf8.decode_lossy(response.body[:]))
    })
    @async.sleep(10)
    let answer = post_legacy(client, reply(Json::string("ask-1")))
    assert_eq(answer.status, 202)
  })
  out
}

///|
async test "what a handler asks goes out on the stream, and its answer starts the next leg" {
  let messages = asked(legacy_demo(), "ask", id => {
    "jsonrpc": "2.0",
    "id": id,
    "result": { "action": "accept", "content": { "name": "leo" } },
  })
  assert_eq(messages.length(), 2)
  assert_eq(dig(messages[0], ["method"]), Some("elicitation/create"))
  assert_eq(dig(messages[0], ["id"]), Some("ask-1"))
  assert_eq(dig(messages[0], ["params", "message"]), Some("Your name?"))
  assert_eq(dig(messages[1], ["id"]), Some(Json(1)))
  assert_eq(
    dig(messages[1], ["result", "content"]),
    Some([{ "type": Json::string("text"), "text": "hello leo, state kept" }]),
  )
}

///|
async test "a client's refusal to answer ends the call with its reason" {
  let messages = asked(legacy_demo(), "ask", id => {
    "jsonrpc": "2.0",
    "id": id,
    "error": { "code": -32601, "message": "not here" },
  })
  let last = messages[messages.length() - 1]
  assert_eq(
    dig(last, ["error", "message"]),
    Some("the client refused: not here"),
  )
}

///|
async test "a client that never answers runs the question out of time" {
  let client = @testing.Client::new(legacy_demo(ask_timeout_ms=20).to_asgi())
  let response = post_legacy(client, call(1, "ask"))
  let messages = sse_messages(@utf8.decode_lossy(response.body[:]))
  let last = messages[messages.length() - 1]
  assert_eq(dig(last, ["error", "message"]), Some("the client did not answer"))
}

///|
async test "a handler that never stops asking is stopped" {
  let mcp = legacy_demo(ask_rounds=1)
  let client = @testing.Client::new(mcp.to_asgi())
  let mut out = []
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    group.spawn_bg(async fn() {
      let response = post_legacy(client, call(1, "ask_forever"))
      out = sse_messages(@utf8.decode_lossy(response.body[:]))
    })
    @async.sleep(10)
    let done : Json = {
      "jsonrpc": "2.0",
      "id": "ask-1",
      "result": { "action": "decline" },
    }
    ignore(post_legacy(client, done))
  })
  let last = out[out.length() - 1]
  assert_eq(
    dig(last, ["error", "message"]),
    Some("a handler asked the client for input 1 times"),
  )
}

///|
async test "a client that takes no stream cannot be asked, and hears why" {
  let client = @testing.Client::new(legacy_demo().to_asgi())
  let response = post_legacy(client, call(1, "ask"), accept="application/json")
  let reply = @json.parse(@utf8.decode_lossy(response.body[:]))
  assert_eq(
    dig(reply, ["error", "message"]),
    Some(
      "a handler asked the client for input, and this transport has no way to",
    ),
  )
}

///|
async test "a stateless client gets the ask itself, and answers it on its own" {
  let mcp = legacy_demo()
  let reply = mcp
    .handle(modern(1, "tools/call", params={ "name": "ask" }))
    .unwrap()
  assert_eq(dig(reply, ["result", "resultType"]), Some("input_required"))
}

///|
/// A line stream driven by hand: every line written is kept, and `then` can send the next line once
/// the server has said something.
async fn over_lines(
  mcp : @server.Server,
  first : Array[Json],
  then : async (Array[String], async (Json) -> Unit) -> Unit,
) -> Array[String] {
  let input : @aqueue.Queue[String?] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  let written : Array[String] = []
  for line in first {
    input.put(Some(line.stringify()))
  }
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    group.spawn_bg(async fn() {
      mcp.serve_lines(() => input.get(), line => written.push(line))
    })
    @async.sleep(10)
    then(written, async fn(line) {
      input.put(Some(line.stringify()))
      @async.sleep(10)
    })
    input.put(None)
  })
  written
}

///|
async test "over lines a question goes out at once, and its answer costs no later reply a turn" {
  let written = over_lines(legacy_demo(), [call(1, "ask")], async fn(
    lines,
    say,
  ) {
    assert_eq(lines.length(), 1)
    let question = @json.parse(lines[0])
    assert_eq(dig(question, ["method"]), Some("elicitation/create"))
    say({
      "jsonrpc": "2.0",
      "id": "ask-1",
      "result": { "action": "accept", "content": { "name": "leo" } },
    })
    say(call(2, "quiet"))
  })
  assert_eq(written.length(), 3)
  let first = @json.parse(written[1])
  assert_eq(dig(first, ["id"]), Some(Json(1)))
  assert_eq(
    dig(first, ["result", "content"]),
    Some([{ "type": Json::string("text"), "text": "hello leo, state kept" }]),
  )
  assert_eq(dig(@json.parse(written[2]), ["id"]), Some(Json(2)))
}

///|
async test "a question still open when the client goes away ends at once" {
  // Well inside the minute a question otherwise waits.
  let written = @async.with_timeout(5000, () => {
    over_lines(legacy_demo(), [call(1, "ask")], (_, _) => ())
  })
  let last = @json.parse(written[written.length() - 1])
  assert_eq(dig(last, ["error", "message"]), Some("the client did not answer"))
}

///|
async test "a client that said initialize hears changes on its own connection" {
  let mcp = legacy_demo()
  let handshake : Json = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-11-25",
      "capabilities": {},
      "clientInfo": { "name": "c", "version": "1" },
    },
  }
  let written = over_lines(mcp, [handshake], async fn(_, _) {
    mcp.notify_tools_changed()
    @async.sleep(10)
  })
  let methods = written.map(line => {
    let message = @json.parse(line) catch { _ => Json::null() }
    dig(message, ["method"])
  })
  assert_true(methods.contains(Some("notifications/tools/list_changed")))
}

///|
async test "a client that did not hears nothing it did not ask for" {
  let mcp = legacy_demo()
  let written = over_lines(mcp, [call(1, "quiet")], async fn(_, _) {
    mcp.notify_tools_changed()
    @async.sleep(10)
  })
  assert_eq(written.length(), 1)
}
