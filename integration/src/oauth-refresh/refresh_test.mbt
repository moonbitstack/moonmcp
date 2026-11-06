// The OAuth flow against an authorization server in this process, on a port:
// what a refresh token is worth on the wire, and when the client decides to
// send somebody through the browser instead.

///|
/// What the mock authorization server was asked, for the test to look at
/// afterwards.
struct Seen {
  grants : Array[String]
  refreshes : Array[String]
  gives_refresh : Bool
  rotates : Bool
}

///|
/// An authorization server and the resource it protects, on one port.
struct Mock {
  port : Int32
  seen : Seen
}

///|
fn Mock::base(self : Mock) -> String {
  "http://127.0.0.1:\{self.port}"
}

///|
/// The access token handed out for an authorization code, and the one handed
/// out for a refresh: distinct so a test can tell them apart.
let first_token : String = "access-1"

///|
let refreshed_token : String = "access-2"

///|
/// One request of the mock.
fn answer(mock : Mock, request : @asgi.Request) -> @asgi.Response {
  let base = mock.base()
  match (request.http_method, request.path) {
    ("GET", "/.well-known/oauth-protected-resource/mcp") =>
      @asgi.Response::json(
        ({
          "resource": "\{base}/mcp",
          "authorization_servers": [base],
          "scopes_supported": ["mcp:basic"],
        } : Json),
      )
    ("GET", "/.well-known/oauth-authorization-server") =>
      @asgi.Response::json(
        ({
          "issuer": base,
          "authorization_endpoint": "\{base}/authorize",
          "token_endpoint": "\{base}/token",
          "registration_endpoint": "\{base}/register",
          "response_types_supported": ["code"],
          "code_challenge_methods_supported": ["S256"],
          "token_endpoint_auth_methods_supported": ["none"],
          // What a client that wants a refresh token is told: the scope that
          // buys one is on offer here (SEP-2207).
          "scopes_supported": ["mcp:basic", "offline_access"],
        } : Json),
      )
    ("POST", "/register") =>
      @asgi.Response::json(
        status=201,
        ({
          "client_id": "client-1",
          "token_endpoint_auth_method": "none",
        } : Json),
      )
    ("POST", "/token") => {
      let form = @utf8.decode_lossy(request.body[:])
      let grant = @auth.query_value(form, "grant_type").unwrap_or("")
      mock.seen.grants.push(grant)
      match grant {
        "authorization_code" =>
          if mock.seen.gives_refresh {
            @asgi.Response::json(
              ({
                "access_token": first_token,
                "token_type": "Bearer",
                "expires_in": Json::number(3600.0),
                "refresh_token": "refresh-1",
                "scope": "mcp:basic",
              } : Json),
            )
          } else {
            @asgi.Response::json(
              ({
                "access_token": first_token,
                "token_type": "Bearer",
                "expires_in": Json::number(3600.0),
                "scope": "mcp:basic",
              } : Json),
            )
          }
        "refresh_token" => {
          mock.seen.refreshes.push(
            @auth.query_value(form, "refresh_token").unwrap_or(""),
          )
          if mock.seen.rotates {
            @asgi.Response::json(
              ({
                "access_token": refreshed_token,
                "token_type": "Bearer",
                "expires_in": Json::number(3600.0),
                "refresh_token": "refresh-2",
              } : Json),
            )
          } else {
            // A server that hands out the same refresh token again, or names
            // none: the client must not lose the one it has.
            @asgi.Response::json(
              ({
                "access_token": refreshed_token,
                "token_type": "Bearer",
                "expires_in": Json::number(3600.0),
              } : Json),
            )
          }
        }
        _ =>
          @asgi.Response::json(
            status=400,
            ({ "error": "unsupported_grant_type" } : Json),
          )
      }
    }
    _ => @asgi.Response::new(404, [], b"")
  }
}

///|
/// Run `body` with the mock listening on `port`. The server lives exactly as
/// long as the body does.
async fn with_mock(
  port : Int32,
  gives_refresh : Bool,
  rotates : Bool,
  body : async (Mock) -> Unit,
) -> Unit {
  let mock : Mock = {
    port,
    seen: { grants: [], refreshes: [], gives_refresh, rotates },
  }
  let app = @asgi.to_asgi(request => answer(mock, request))
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    group.spawn_bg(
      async fn() { @mooncat.serve(app, port~) catch { _ => () } },
      no_wait=true,
    )
    for _ in 0..<50 {
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
    }
    body(mock)
  })
}

///|
/// The `state` an authorization URL carries, echoed back the way a browser
/// would.
fn callback_for(url : String) -> String {
  let state = @auth.query_value(@auth.query_of(url), "state").unwrap_or("")
  "http://127.0.0.1:53682/callback?code=code-1&state=\{state}"
}

///|
/// A client of the mock, counting how often it went to the browser.
fn client_for(mock : Mock, visits : Ref[Int]) -> @oauth.Oauth {
  @oauth.Oauth::new(
    resource_url=mock.base() + "/mcp",
    client_name="test",
    redirect_uri="http://127.0.0.1:53682/callback",
    present=url => {
      visits.val = visits.val + 1
      callback_for(url)
    },
  )
}

///|
async test "a refresh token buys an access token without a browser" {
  with_mock(12081, true, true, async fn(mock) {
    let visits : Ref[Int] = Ref(0)
    let oauth = client_for(mock, visits)
    oauth.authorize() catch {
      @auth.Refused(message~) => abort(message)
    }
    assert_eq(oauth.bearer(), Some(first_token))
    assert_eq(visits.val, 1)
    // A server that lists offline_access is asked for it, and the grant that
    // needs a refresh token is in the registration.
    assert_eq(oauth.rounds(), 1)
    assert_eq(oauth.refresh(), true)
    assert_eq(oauth.bearer(), Some(refreshed_token))
    // No browser: a refresh is one request, and not an authorization round.
    assert_eq(visits.val, 1)
    assert_eq(oauth.rounds(), 1)
    // The refresh request carried the token the server gave, and the rotated
    // one replaced it, so the next refresh sends the new one.
    assert_eq(mock.seen.refreshes, ["refresh-1"])
    assert_eq(oauth.refresh(), true)
    assert_eq(mock.seen.refreshes, ["refresh-1", "refresh-2"])
    assert_eq(mock.seen.grants, ["authorization_code", "refresh_token", "refresh_token"])
  })
}

///|
async test "a refresh the server does not rotate keeps the token it had" {
  with_mock(12082, true, false, async fn(mock) {
    let visits : Ref[Int] = Ref(0)
    let oauth = client_for(mock, visits)
    oauth.authorize() catch {
      @auth.Refused(message~) => abort(message)
    }
    assert_eq(oauth.refresh(), true)
    assert_eq(oauth.refresh(), true)
    // The response named no refresh token, and the old one is still the only
    // key this client has: it is kept, not dropped.
    assert_eq(mock.seen.refreshes, ["refresh-1", "refresh-1"])
  })
}

///|
async test "a token with no refresh token sends the client to authorize" {
  with_mock(12083, false, false, async fn(mock) {
    let visits : Ref[Int] = Ref(0)
    let oauth = client_for(mock, visits)
    oauth.authorize() catch {
      @auth.Refused(message~) => abort(message)
    }
    assert_eq(oauth.refresh(), false)
    assert_eq(mock.seen.refreshes, [])
    // `renew` is what a transport calls: it falls back to the full flow, which
    // is a second visit to the browser.
    assert_eq(oauth.renew(), true)
    assert_eq(visits.val, 2)
    assert_eq(mock.seen.refreshes, [])
  })
}

///|
async test "a challenge that asks for a wider scope authorizes, not refreshes" {
  with_mock(12084, true, true, async fn(mock) {
    let visits : Ref[Int] = Ref(0)
    let oauth = client_for(mock, visits)
    oauth.authorize() catch {
      @auth.Refused(message~) => abort(message)
    }
    // A refresh may not widen a scope (RFC 6749 §6), so this cannot be answered
    // by one: the client has to ask the person.
    let challenge = match @auth.Challenge::parse("Bearer scope=\"mcp:write\"") {
      Some(challenge) => challenge
      None => abort("no challenge")
    }
    assert_eq(oauth.renew(challenge~), true)
    assert_eq(mock.seen.refreshes, [])
    assert_eq(visits.val, 2)
  })
}
