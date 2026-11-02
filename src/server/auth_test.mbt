///|
fn auth_demo() -> @server.Server {
  let mcp = @server.Server::new("auth demo", version="1.0.0")
  mcp.tool_context("whoami", async fn(
    _args : Map[String, Json],
    context : @context.Context,
  ) {
    @async.pause()
    let subject = context.subject().unwrap_or("nobody")
    let role = match context.claims().get("role") {
      Some(String(role)) => role
      _ => "no role"
    }
    @tools.ToolResult::new(content=[@types.text_block("\{subject} (\{role})")])
  })
  mcp
}

///|
fn auth_bearer(clock : () -> Int64) -> @auth.Bearer {
  @auth.Bearer::hmac(secret="s3cret", clock~)
}

///|
fn mint(claims : Map[String, Json]) -> String {
  let key = @jwt.mac(fn() {
    @hmac.Hmac::new(@utf8.encode("s3cret")[:], fn() { @sha2.Hasher::new() })
  })
  @jwt.sign(claims, @jwt.HS256, key)
}

///|
fn whoami_request() -> Json {
  {
    "jsonrpc": "2.0",
    "id": Json::number(1.0),
    "method": Json::string("tools/call"),
    "params": {
      "name": Json::string("whoami"),
      "arguments": Json::object(Map([])),
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
      },
    },
  }
}

///|
async fn post_whoami(
  client : @testing.Client,
  authorization : String?,
) -> @client.TestResponse {
  let headers : Array[(String, String)] = [
    ("content-type", "application/json"),
    ("mcp-protocol-version", "2026-07-28"),
    ("mcp-method", "tools/call"),
    ("mcp-name", "whoami"),
  ]
  if authorization is Some(value) {
    headers.push(("authorization", value))
  }
  client.post("/mcp", body=@utf8.encode(whoami_request().stringify()), headers~)
}

///|
async test "http: a request without a token is challenged" {
  let app = auth_demo().to_asgi(auth=Some(auth_bearer(fn() { 1_000L })))
  let client = @testing.Client::new(app)
  let response = post_whoami(client, None) catch {
    _ => fail("the request raised")
  }
  assert_eq(response.status, 401)
  let challenge = header_of(response.headers, "www-authenticate").unwrap_or("")
  assert_eq(challenge.has_prefix("Bearer "), true)
  assert_eq(challenge.contains("error=\"invalid_token\""), true)
}

///|
async test "http: a token that does not verify is challenged" {
  let app = auth_demo().to_asgi(auth=Some(auth_bearer(fn() { 1_000L })))
  let client = @testing.Client::new(app)
  let expired = mint({ "sub": Json::string("alice"), "exp": Json::number(10.0) })
  let response = post_whoami(client, Some("Bearer " + expired)) catch {
    _ => fail("the request raised")
  }
  assert_eq(response.status, 401)
  assert_eq(
    header_of(response.headers, "www-authenticate")
    .unwrap_or("")
    .contains("expired"),
    true,
  )
}

///|
async test "http: a valid token names the caller its handler sees" {
  let app = auth_demo().to_asgi(auth=Some(auth_bearer(fn() { 1_000L })))
  let client = @testing.Client::new(app)
  let token = mint({
    "sub": Json::string("alice"),
    "role": Json::string("admin"),
    "exp": Json::number(2_000.0),
  })
  let response = post_whoami(client, Some("Bearer " + token)) catch {
    _ => fail("the request raised")
  }
  assert_eq(response.status, 200)
  let reply : Json = @json.parse(@utf8.decode_lossy(response.body[:])) catch {
    _ => fail("the reply is not JSON")
  }
  assert_eq(
    dig(reply, ["result", "content"]),
    Some([
      { "type": Json::string("text"), "text": Json::string("alice (admin)") },
    ]),
  )
}

///|
async test "http: an open endpoint asks for no token" {
  let app = auth_demo().to_asgi()
  let client = @testing.Client::new(app)
  let response = post_whoami(client, None) catch {
    _ => fail("the request raised")
  }
  assert_eq(response.status, 200)
  let reply : Json = @json.parse(@utf8.decode_lossy(response.body[:])) catch {
    _ => fail("the reply is not JSON")
  }
  assert_eq(
    dig(reply, ["result", "content"]),
    Some([
      { "type": Json::string("text"), "text": Json::string("nobody (no role)") },
    ]),
  )
}
