///|
fn demo() -> @server.Server {
  let mcp = @server.Server::new("demo", version="1.0.0", instructions="try it")
  mcp.tool(
    "add",
    args => {
      guard args.get("a") is Some(Number(a, ..)) &&
        args.get("b") is Some(Number(b, ..)) else {
        raise @exceptions.Tool("numbers please")
      }
      { "sum": Json(a + b) }
    },
    input_schema={
      "type": "object",
      "properties": {
        "a": { "type": "number" },
        "b": { "type": "number" },
        "region": { "type": "string", "x-mcp-header": "Region" },
      },
      "required": ["a", "b"],
    },
  )
  mcp.tool("boom", _ => raise Failure("it broke"))
  mcp.resource("config://app", () => "dark")
  mcp.template("users://{id}", params => {
    guard params.get("id") is Some(String(id)) else { "" }
    "user " + id
  })
  mcp.prompt("review", args => {
    guard args.get("code") is Some(String(code)) else { "nothing" }
    "review " + code
  })
  mcp
}

///|
let modern_meta : Json = {
  "io.modelcontextprotocol/protocolVersion": "2026-07-28",
  "io.modelcontextprotocol/clientCapabilities": {},
}

///|
fn request(id : Int32, op : String, params : Map[String, Json]) -> Json {
  {
    "jsonrpc": "2.0",
    "id": Json(id),
    "method": Json(op),
    "params": Json(params),
  }
}

///|
fn modern(id : Int32, op : String, params? : Map[String, Json]) -> Json {
  let p = params.unwrap_or(Map([])).copy()
  p["_meta"] = modern_meta
  request(id, op, p)
}

///|
fn dig(j : Json, path : Array[String]) -> Json? {
  let mut at = j
  for key in path {
    guard at is Object(o) && o.get(key) is Some(next) else { return None }
    at = next
  }
  Some(at)
}

///|
async test "discover names every version and stamps the modern fields" {
  let reply = demo().handle(modern(1, "server/discover")).unwrap()
  let result = dig(reply, ["result"]).unwrap()
  assert_eq(
    dig(result, ["supportedVersions"]),
    Some(["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]),
  )
  assert_eq(dig(result, ["resultType"]), Some("complete"))
  assert_eq(dig(result, ["ttlMs"]), Some(Json(0)))
  assert_eq(dig(result, ["cacheScope"]), Some("private"))
  assert_eq(
    dig(result, ["_meta", "io.modelcontextprotocol/serverInfo", "name"]),
    Some("demo"),
  )
  assert_eq(dig(result, ["instructions"]), Some("try it"))
}

///|
async test "initialize negotiates a legacy version and stamps nothing" {
  let mcp = demo()
  let asked = request(1, "initialize", {
    "protocolVersion": "2025-06-18",
    "capabilities": {},
    "clientInfo": { "name": "c", "version": "1" },
  })
  let result = dig(mcp.handle(asked).unwrap(), ["result"]).unwrap()
  assert_eq(dig(result, ["protocolVersion"]), Some("2025-06-18"))
  assert_eq(dig(result, ["serverInfo", "version"]), Some("1.0.0"))
  assert_eq(dig(result, ["resultType"]), None)
  let unknown = request(2, "initialize", { "protocolVersion": "2099-01-01" })
  assert_eq(
    dig(mcp.handle(unknown).unwrap(), ["result", "protocolVersion"]),
    Some("2025-11-25"),
  )
}

///|
async test "an unsupported modern version is refused with the supported list" {
  let asked : Json = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list",
    "params": {
      "_meta": { "io.modelcontextprotocol/protocolVersion": "1900-01-01" },
    },
  }
  let reply = demo().handle(asked).unwrap()
  assert_eq(dig(reply, ["error", "code"]), Some(Json(-32022)))
  assert_eq(dig(reply, ["error", "data", "requested"]), Some("1900-01-01"))
}

///|
async test "tools: list in order, call, schema errors and failures are tool errors" {
  let mcp = demo()
  let list = mcp.handle(modern(1, "tools/list")).unwrap()
  guard! dig(list, ["result", "tools"]) is Some(Array(tools))
  assert_eq(tools.map(t => dig(t, ["name"]).unwrap()), ["add", "boom"])
  let sum = mcp.handle(
    modern(2, "tools/call", params={
      "name": "add",
      "arguments": { "a": 2, "b": 3 },
    }),
  )
  assert_eq(
    dig(sum.unwrap(), ["result", "structuredContent", "sum"]),
    Some(Json(5)),
  )
  let wrong = mcp.handle(
    modern(3, "tools/call", params={ "name": "add", "arguments": { "a": "x" } }),
  )
  assert_eq(dig(wrong.unwrap(), ["result", "isError"]), Some(true))
  let broke = mcp.handle(modern(4, "tools/call", params={ "name": "boom" }))
  assert_eq(dig(broke.unwrap(), ["result", "isError"]), Some(true))
  let gone = mcp.handle(modern(5, "tools/call", params={ "name": "nope" }))
  assert_eq(dig(gone.unwrap(), ["error", "code"]), Some(Json(-32602)))
}

///|
async test "resources: fixed, templated, and the missing code per era" {
  let mcp = demo()
  let fixed = mcp.handle(
    modern(1, "resources/read", params={ "uri": "config://app" }),
  )
  guard! dig(fixed.unwrap(), ["result", "contents"]) is Some(Array(contents))
  assert_eq(dig(contents[0], ["text"]), Some("dark"))
  let templated = mcp.handle(
    modern(2, "resources/read", params={ "uri": "users://7" }),
  )
  guard! dig(templated.unwrap(), ["result", "contents"])
    is Some(Array(contents))
  assert_eq(dig(contents[0], ["text"]), Some("user 7"))
  let missing_modern = mcp.handle(
    modern(3, "resources/read", params={ "uri": "x://y" }),
  )
  assert_eq(dig(missing_modern.unwrap(), ["error", "code"]), Some(Json(-32602)))
  let missing_legacy = mcp.handle(
    request(4, "resources/read", { "uri": "x://y" }),
  )
  assert_eq(dig(missing_legacy.unwrap(), ["error", "code"]), Some(Json(-32002)))
}

///|
async test "prompts render, and ping is legacy only" {
  let mcp = demo()
  let got = mcp.handle(
    modern(1, "prompts/get", params={
      "name": "review",
      "arguments": { "code": "x" },
    }),
  )
  guard! dig(got.unwrap(), ["result", "messages"]) is Some(Array(messages))
  assert_eq(dig(messages[0], ["content", "text"]), Some("review x"))
  assert_eq(
    dig(mcp.handle(request(2, "ping", Map([]))).unwrap(), ["result"]),
    Some(Json::object(Map([]))),
  )
  assert_eq(
    dig(mcp.handle(modern(3, "ping")).unwrap(), ["error", "code"]),
    Some(Json(-32601)),
  )
}

///|
async test "notifications get no reply, and malformed messages a JSON-RPC error" {
  let mcp = demo()
  let note : Json = { "jsonrpc": "2.0", "method": "notifications/initialized" }
  assert_eq(mcp.handle(note), None)
  let bad = mcp.handle({ "id": 1 }).unwrap()
  assert_eq(dig(bad, ["error", "code"]), Some(Json(-32600)))
  let cursor = mcp.handle(modern(2, "tools/list", params={ "cursor": "c" }))
  assert_eq(dig(cursor.unwrap(), ["error", "code"]), Some(Json(-32602)))
}

///|
test "panic a schema that does not compile" {
  @server.Server::new("x").tool("t", _ => Json::null(), input_schema={
    "$schema": "https://example.com/no-such-metaschema",
  })
}

///|
async test "serve_lines answers line by line and skips notifications" {
  let mcp = demo()
  let input = [
    modern(1, "tools/list").stringify(),
    "",
    "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
    "not json",
  ]
  let output : Array[String] = []
  let mut i = 0
  mcp.serve_lines(
    () => {
      guard i < input.length() else { return None }
      i += 1
      Some(input[i - 1])
    },
    line => output.push(line),
  )
  assert_eq(output.length(), 2)
  assert_true(output[0].contains("\"tools\""))
  assert_true(output[1].contains("-32700"))
}

///|
async test "http: modern headers must agree with the body" {
  let app = demo().to_asgi()
  let client = @testing.Client::new(app)
  let call = modern(1, "tools/call", params={
    "name": "add",
    "arguments": { "a": 1, "b": 2, "region": "eu" },
  })
  let body = @utf8.encode(call.stringify())
  let base = [
    ("content-type", "application/json"),
    ("mcp-protocol-version", "2026-07-28"),
    ("mcp-method", "tools/call"),
    ("mcp-name", "add"),
  ]
  let ok = client.post(
    "/mcp",
    body~,
    headers=[..base, ("mcp-param-region", "eu")],
  )
  assert_eq(ok.status, 200)
  let no_param = client.post("/mcp", body~, headers=base)
  assert_eq(no_param.status, 400)
  assert_true(no_param.text().contains("-32020"))
  let encoded = client.post(
    "/mcp",
    body~,
    headers=[..base, ("mcp-param-region", "=?base64?ZXU=?=")],
  )
  assert_eq(encoded.status, 200)
  let wrong_name = client.post("/mcp", body~, headers=[
    ("content-type", "application/json"),
    ("mcp-protocol-version", "2026-07-28"),
    ("mcp-method", "tools/call"),
    ("mcp-name", "boom"),
    ("mcp-param-region", "eu"),
  ])
  assert_eq(wrong_name.status, 400)
}

///|
async test "http: statuses for methods, origins, notifications and bad bodies" {
  let client = @testing.Client::new(demo().to_asgi())
  assert_eq(client.get("/mcp").status, 405)
  assert_eq(client.get("/elsewhere").status, 404)
  let json = [("content-type", "application/json")]
  let note = @utf8.encode(
    "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
  )
  assert_eq(client.post("/mcp", body=note, headers=json).status, 202)
  assert_eq(client.post("/mcp", body=b"{nope", headers=json).status, 400)
  assert_eq(
    client.post("/mcp", body=note, headers=[("content-type", "text/plain")]).status,
    415,
  )
  let evil = client.post(
    "/mcp",
    body=note,
    headers=[..json, ("origin", "http://evil.example")],
  )
  assert_eq(evil.status, 403)
  let loopback = client.post(
    "/mcp",
    body=note,
    headers=[..json, ("origin", "http://localhost:3000")],
  )
  assert_eq(loopback.status, 202)
  let legacy = request(1, "tools/list", Map([]))
  let listed = client.post(
    "/mcp",
    body=@utf8.encode(legacy.stringify()),
    headers=[..json, ("mcp-protocol-version", "2025-06-18")],
  )
  assert_eq(listed.status, 200)
  let unknown_legacy = client.post(
    "/mcp",
    body=@utf8.encode(legacy.stringify()),
    headers=[..json, ("mcp-protocol-version", "1999-01-01")],
  )
  assert_eq(unknown_legacy.status, 400)
}
