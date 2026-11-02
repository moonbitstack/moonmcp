///|
fn signing_key(secret : String) -> @jwt.Keyed {
  @jwt.mac(fn() {
    @hmac.Hmac::new(@utf8.encode(secret)[:], fn() { @sha2.Hasher::new() })
  })
}

///|
fn token(secret : String, claims : Map[String, Json]) -> String {
  @jwt.sign(claims, @jwt.HS256, signing_key(secret))
}

///|
fn claims(subject : String, expires : Double) -> Map[String, Json] {
  { "sub": Json::string(subject), "exp": Json::number(expires) }
}

///|
test "a token signed with the shared secret names its subject" {
  let bearer = @auth.Bearer::hmac(secret="s3cret", clock=fn() { 1_000L })
  let outcome = bearer.check(
    "Bearer " + token("s3cret", claims("alice", 2_000.0)),
  )
  match outcome {
    Ok(principal) => {
      assert_eq(principal.subject, Some("alice"))
      assert_eq(principal.claims.get("sub"), Some(Json::string("alice")))
    }
    Err(reason) => fail(reason)
  }
}

///|
test "a token for another secret is refused" {
  let bearer = @auth.Bearer::hmac(secret="s3cret", clock=fn() { 1_000L })
  let outcome = bearer.check(
    "Bearer " + token("other", claims("alice", 2_000.0)),
  )
  match outcome {
    Ok(_) => fail("a token signed with another secret was accepted")
    Err(reason) => assert_eq(reason.contains("signature"), true)
  }
}

///|
test "an expired token is refused and says so" {
  let bearer = @auth.Bearer::hmac(secret="s3cret", clock=fn() { 3_000L })
  let outcome = bearer.check(
    "Bearer " + token("s3cret", claims("alice", 2_000.0)),
  )
  match outcome {
    Ok(_) => fail("an expired token was accepted")
    Err(reason) => assert_eq(reason.contains("expired"), true)
  }
}

///|
test "a token minted for another audience is refused" {
  let bearer = @auth.Bearer::hmac(secret="s3cret", clock=fn() { 1_000L }, audience=[
    "moonmcp",
  ])
  let minted : Map[String, Json] = {
    "sub": Json::string("alice"),
    "exp": Json::number(2_000.0),
    "aud": Json::string("something-else"),
  }
  match bearer.check("Bearer " + token("s3cret", minted)) {
    Ok(_) => fail("a token for another audience was accepted")
    Err(reason) => assert_eq(reason.contains("audience"), true)
  }
}

///|
test "a header that is not a bearer token is refused before any parsing" {
  let bearer = @auth.Bearer::hmac(secret="s3cret")
  match bearer.check("Basic dXNlcjpwYXNz") {
    Ok(_) => fail("a basic credential was accepted")
    Err(reason) => assert_eq(reason.contains("bearer"), true)
  }
  match bearer.check("Bearer") {
    Ok(_) => fail("an empty bearer was accepted")
    Err(reason) => assert_eq(reason.contains("no token"), true)
  }
}

///|
test "a check of the caller's own decides, and its reason travels" {
  let bearer = @auth.Bearer::own(check=fn(token) {
    if token == "let-me-in" {
      Ok({ subject: Some("bob"), claims: { "role": Json::string("admin") }, })
    } else {
      Err("no such token")
    }
  })
  match bearer.check("Bearer let-me-in") {
    Ok(principal) => assert_eq(principal.has_scope("admin"), false)
    Err(_) => fail("a token the check accepts was refused")
  }
  match bearer.check("Bearer nope") {
    Ok(_) => fail("a token the check refuses was accepted")
    Err(reason) => assert_eq(reason, "no such token")
  }
}

///|
test "scopes are read from either spelling" {
  let spaced : @auth.Principal = {
    subject: None,
    claims: { "scope": Json::string("read write") },
  }
  assert_eq(spaced.has_scope("write"), true)
  assert_eq(spaced.has_scope("admin"), false)
  let listed : @auth.Principal = {
    subject: None,
    claims: { "scp": Json::array([Json::string("read")]) },
  }
  assert_eq(listed.has_scope("read"), true)
}
