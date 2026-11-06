// The documents an OAuth client reads and the requests it builds, against the
// examples the specifications give.

///|
test "the RFC 7636 example pair comes out exactly" {
  let pkce = @auth.Pkce::of("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
  assert_eq(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
}

///|
test "protected resource metadata keeps what it was given and drops the rest" {
  let document : Json = {
    "resource": "http://127.0.0.1:12000/mcp",
    "authorization_servers": ["http://127.0.0.1:12001"],
    "scopes_supported": ["mcp:basic", "mcp:write"],
  }
  let resource = @auth.Resource::parse(document) catch {
    @auth.Refused(message~) => fail(message)
  }
  assert_eq(resource.resource, "http://127.0.0.1:12000/mcp")
  assert_eq(resource.authorization_servers.length(), 1)
  assert_eq(resource.scopes_supported, Some(["mcp:basic", "mcp:write"]))
  let bare = @auth.Resource::parse({ "resource": "https://example.com" }) catch {
    @auth.Refused(message~) => fail(message)
  }
  assert_eq(bare.scopes_supported, None)
  assert_eq(bare.authorization_servers.length(), 0)
}

///|
test "authorization server metadata fills in the RFC 8414 defaults" {
  let document : Json = {
    "issuer": "https://as.example.com",
    "authorization_endpoint": "https://as.example.com/authorize",
    "token_endpoint": "https://as.example.com/token",
  }
  let server = @auth.Server::parse(document) catch {
    @auth.Refused(message~) => fail(message)
  }
  assert_eq(server.registration_endpoint, None)
  assert_eq(server.response_types_supported, ["code"])
  assert_eq(server.token_endpoint_auth_methods_supported, [
    "client_secret_basic",
  ])
  assert_eq(server.client_id_metadata_document_supported, false)
  assert_eq(server.serves_authorization_code(), true)
}

///|
test "a server that names no code challenge method still serves the flow" {
  let document : Json = {
    "issuer": "https://as.example.com",
    "token_endpoint": "https://as.example.com/token",
    "code_challenge_methods_supported": ["plain"],
  }
  let server = @auth.Server::parse(document) catch {
    @auth.Refused(message~) => fail(message)
  }
  assert_eq(server.serves_authorization_code(), false)
}

///|
test "the protected resource is looked up under its path first" {
  assert_eq(@auth.Resource::probes("https://example.com/mcp"), [
    "https://example.com/.well-known/oauth-protected-resource/mcp", "https://example.com/.well-known/oauth-protected-resource",
  ])
  assert_eq(@auth.Resource::probes("https://example.com"), [
    "https://example.com/.well-known/oauth-protected-resource",
  ])
  assert_eq(
    @auth.Resource::probes(
      "https://example.com/mcp",
      hinted="https://example.com/custom.json",
    ),
    ["https://example.com/custom.json"],
  )
}

///|
test "authorization server metadata is looked up the three ways RFC 8414 and OpenID allow" {
  assert_eq(@auth.Server::probes("https://as.example.com/tenant1"), [
    "https://as.example.com/.well-known/oauth-authorization-server/tenant1", "https://as.example.com/.well-known/openid-configuration/tenant1",
    "https://as.example.com/tenant1/.well-known/openid-configuration",
  ])
  assert_eq(@auth.Server::probes("https://as.example.com"), [
    "https://as.example.com/.well-known/oauth-authorization-server", "https://as.example.com/.well-known/openid-configuration",
  ])
}

///|
/// The challenge `text` carries, or a failed test.
fn challenge_of(text : String) -> @auth.Challenge {
  match @auth.Challenge::parse(text) {
    Some(challenge) => challenge
    None => abort("no challenge in " + text)
  }
}

///|
test "a challenge is read whether its parameters are quoted or not" {
  let quoted = challenge_of(
    "Bearer scope=\"mcp:basic mcp:write\", resource_metadata=\"https://example.com/prm\"",
  )
  assert_eq(quoted.scope, Some("mcp:basic mcp:write"))
  assert_eq(quoted.resource_metadata, Some("https://example.com/prm"))
  let bare = challenge_of(
    "bearer error=insufficient_scope, scope=mcp:admin, resource_metadata=https://example.com/prm",
  )
  assert_eq(bare.error, Some("insufficient_scope"))
  assert_eq(bare.scope, Some("mcp:admin"))
  assert_eq(@auth.Challenge::parse("Basic realm=x"), None)
}

///|
test "the scope comes from the challenge, then the resource, then the client" {
  let challenge = Some(challenge_of("Bearer scope=\"a b\""))
  let resource = @auth.Resource::parse({
    "resource": "https://example.com/mcp",
    "scopes_supported": ["c", "d"],
  }) catch {
    @auth.Refused(message~) => fail(message)
  }
  assert_eq(@auth.scope_for(challenge, Some(resource), Some("e")), Some("a b"))
  assert_eq(@auth.scope_for(None, Some(resource), Some("e")), Some("c d"))
  assert_eq(@auth.scope_for(None, None, Some("e")), Some("e"))
  assert_eq(@auth.scope_for(None, None, None), None)
  let empty = Some(challenge_of("Bearer scope=\"\""))
  assert_eq(@auth.scope_for(empty, None, None), None)
}

///|
test "a widened scope keeps the order and drops repeats" {
  assert_eq(@auth.widen_scope(Some("a b"), Some("b c")), Some("a b c"))
  assert_eq(@auth.widen_scope(None, Some("c")), Some("c"))
  assert_eq(@auth.widen_scope(Some("a"), None), Some("a"))
}

///|
test "the token endpoint method follows what registration returned, then the server's list" {
  let public = @auth.Registration::parse({
    "client_id": "abc",
    "token_endpoint_auth_method": "none",
  }) catch {
    @auth.Refused(message~) => fail(message)
  }
  assert_eq(
    @auth.Credentials::select(public, ["none"]),
    @auth.Credentials::Public,
  )
  let secret : @auth.Registration = {
    client_id: "abc",
    client_secret: Some("s3cret"),
    token_endpoint_auth_method: None,
  }
  assert_eq(
    @auth.Credentials::select(secret, [
      "client_secret_basic", "client_secret_post",
    ]),
    @auth.Credentials::Basic,
  )
  assert_eq(
    @auth.Credentials::select(secret, ["client_secret_post"]),
    @auth.Credentials::Post,
  )
  assert_eq(@auth.Credentials::select(secret, []), @auth.Credentials::Basic)
}

///|
test "basic credentials are the pair, percent-encoded, in base64" {
  let secret : @auth.Registration = {
    client_id: "s6BhdRkqt3",
    client_secret: Some("7Fjfp0ZBr1KtDRbnfVdmIw"),
    token_endpoint_auth_method: None,
  }
  let header = @auth.Credentials::authorization(
    @auth.Credentials::Basic,
    secret,
  )
  assert_eq(header, Some("Basic czZCaGRSa3F0Mzo3RmpmcDBaQnIxS3REUmJuZlZkbUl3"))
  assert_eq(@auth.Credentials::form(@auth.Credentials::Post, secret), [
    ("client_id", "s6BhdRkqt3"),
    ("client_secret", "7Fjfp0ZBr1KtDRbnfVdmIw"),
  ])
}

///|
test "form encoding keeps only the unreserved characters" {
  assert_eq(@auth.percent_encode("a-b._~"), "a-b._~")
  assert_eq(@auth.percent_encode("a b&c"), "a%20b%26c")
  assert_eq(
    @auth.form_encode([("grant_type", "authorization_code"), ("code", "a+b")]),
    "grant_type=authorization_code&code=a%2Bb",
  )
}

///|
test "a token response is read, and an error response is refused" {
  let tokens = @auth.Tokens::parse({
    "access_token": "test-token-1",
    "token_type": "Bearer",
    "expires_in": 3600.0,
    "scope": "mcp:basic",
  }) catch {
    @auth.Refused(message~) => fail(message)
  }
  assert_eq(tokens.access_token, "test-token-1")
  assert_eq(tokens.expires_in, Some(3600L))
  assert_eq(tokens.good_until(1_000L), Some(4_600L))
  let refused = try {
    ignore(
      @auth.Tokens::parse({
        "error": "invalid_client",
        "error_description": "no such client",
      }),
    )
    fail("an error response was read as a token")
  } catch {
    @auth.Refused(message~) => message
    _ => "another error"
  }
  assert_eq(refused.contains("invalid_client"), true)
  assert_eq(refused.contains("no such client"), true)
}

///|
test "the authorization request carries the code flow, the challenge and the resource" {
  let server = @auth.Server::parse({
    "issuer": "https://as.example.com",
    "authorization_endpoint": "https://as.example.com/authorize",
    "token_endpoint": "https://as.example.com/token",
    "code_challenge_methods_supported": ["S256"],
  }) catch {
    @auth.Refused(message~) => fail(message)
  }
  let registration : @auth.Registration = {
    client_id: "abc",
    client_secret: None,
    token_endpoint_auth_method: Some("none"),
  }
  let url = @auth.authorize_url(
    server,
    registration,
    "http://127.0.0.1:53682/callback",
    "state-1",
    @auth.Pkce::of("verifier"),
    scope="mcp:basic mcp:write",
    resource="https://example.com/mcp",
  ) catch {
    @auth.Refused(message~) => fail(message)
  }
  let query = @auth.query_of(url)
  assert_eq(@auth.query_value(query, "response_type"), Some("code"))
  assert_eq(@auth.query_value(query, "client_id"), Some("abc"))
  assert_eq(@auth.query_value(query, "state"), Some("state-1"))
  assert_eq(@auth.query_value(query, "code_challenge_method"), Some("S256"))
  assert_eq(@auth.query_value(query, "scope"), Some("mcp:basic mcp:write"))
  assert_eq(
    @auth.query_value(query, "resource"),
    Some("https://example.com/mcp"),
  )
  assert_eq(
    @auth.query_value(query, "redirect_uri"),
    Some("http://127.0.0.1:53682/callback"),
  )
}

///|
test "a redirect gives back its code, and an error redirect is refused" {
  let redirect = @auth.Redirect::parse(
    "http://127.0.0.1:53682/callback?code=test-auth-code&state=state-1",
  ) catch {
    @auth.Refused(message~) => fail(message)
  }
  assert_eq(redirect.code, "test-auth-code")
  assert_eq(redirect.state, Some("state-1"))
  let refused = try {
    ignore(
      @auth.Redirect::parse(
        "http://127.0.0.1:53682/callback?error=access_denied",
      ),
    )
    "no error"
  } catch {
    @auth.Refused(message~) => message
  }
  assert_eq(refused.contains("access_denied"), true)
}

///|
test "an origin is compared without its case and nothing else" {
  assert_eq(
    @auth.same_origin("HTTPS://Example.COM/a", "https://example.com/b"),
    true,
  )
  assert_eq(
    @auth.same_origin("https://evil.example.com/mcp", "https://example.com/mcp"),
    false,
  )
  assert_eq(
    @auth.origin_of("https://example.com:8443/a/b?c=1"),
    "https://example.com:8443",
  )
  assert_eq(@auth.path_of("https://example.com/a/b?c=1"), "/a/b")
  assert_eq(@auth.path_of("https://example.com"), "/")
  assert_eq(@auth.target_of("https://example.com/a?b=1"), "/a?b=1")
}
