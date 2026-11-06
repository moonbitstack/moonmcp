// The client side of MCP's authorization section: find the resource's
// metadata, find its authorization server, register, send the user to
// authorize, and exchange what comes back for a token.
//
// The flow is written as one call — `Oauth::renew` — because that is how a
// transport uses it: a request comes back `401` or `403`, and the transport
// asks for a token and sends the request again. Everything a caller may want to
// see afterwards is a method on the same object.

///|
/// A client of one protected resource: what it is called, where the browser
/// comes back to, and how it presents the authorization URL to whoever is
/// sitting in front of it.
///
/// One object holds the flow's whole state — the documents it discovered, the
/// registration it obtained, the token it was given — so a second `renew` after
/// a `403` only asks for what the new challenge names.
pub struct Oauth {
  resource_url : String
  metadata : @auth.Metadata
  redirect_uri : String
  scope : String?
  pre_registered : @auth.Registration?
  metadata_url : String?
  grant : @auth.Grant
  assertion : Assertion?
  present : async (String) -> String
  clock : () -> Int64
  priv mut resource : @auth.Resource?
  priv mut server : @auth.Server?
  priv mut registration : @auth.Registration?
  priv mut tokens : @auth.Tokens?
  priv mut good_until : Int64?
  priv mut rounds : Int32
}

///|
/// A client for `resource_url`. `present` is handed the authorization URL and
/// answers with the URL the browser was sent back to, or the empty string when
/// the user gave up; opening a browser and listening on a loopback port for the
/// redirect is the caller's business, because only the caller knows whether
/// there is a person there at all.
///
/// `metadata_url` is the HTTPS document a URL client identifier points at; it
/// is used when the authorization server advertises
/// `client_id_metadata_document_supported`, and dynamic registration is used
/// otherwise. `pre_registered` is what a deployment hands out instead: when it
/// is set, nothing is registered.
pub fn Oauth::new(
  resource_url~ : String,
  client_name~ : String = "moonmcp",
  redirect_uri~ : String = "http://127.0.0.1:53682/callback",
  scope? : String,
  pre_registered? : @auth.Registration,
  metadata_url? : String,
  grant~ : @auth.Grant = AuthorizationCode,
  assertion? : Assertion,
  present~ : async (String) -> String,
  clock~ : () -> Int64 = fn() { @async.now() / 1_000L },
) -> Oauth {
  {
    resource_url,
    metadata: @auth.Metadata::new(
      client_name~,
      redirect_uris=[redirect_uri],
      scope?,
      token_endpoint_auth_method=if pre_registered is Some(_) {
        "client_secret_basic"
      } else {
        "none"
      },
    ),
    redirect_uri,
    scope,
    pre_registered,
    metadata_url,
    grant,
    assertion,
    present,
    clock,
    resource: None,
    server: None,
    registration: None,
    tokens: None,
    good_until: None,
    rounds: 0,
  }
}

///|
/// The token to send as a bearer, if one has been obtained.
pub fn Oauth::bearer(self : Oauth) -> String? {
  self.tokens.map(tokens => tokens.access_token)
}

///|
/// The registration in force: issued by the server, or the one configured.
pub fn Oauth::registration(self : Oauth) -> @auth.Registration? {
  self.registration
}

///|
/// The authorization server's metadata, once discovered.
pub fn Oauth::server(self : Oauth) -> @auth.Server? {
  self.server
}

///|
/// When the token stops being good, seconds since the epoch, if it said.
pub fn Oauth::good_until(self : Oauth) -> Int64? {
  self.good_until
}

///|
/// The scope the last authorization request asked for.
pub fn Oauth::scope(self : Oauth) -> String? {
  self.scope
}

///|
/// How many authorization requests this client has made: the number a retry
/// limit is set against.
pub fn Oauth::rounds(self : Oauth) -> Int32 {
  self.rounds
}

///|
/// Get a token for what `challenge` asks for, replacing any token held. False
/// when the flow did not finish — the caller then sends what it has, or gives
/// up, rather than looping.
///
/// Three rounds is the ceiling: a server that keeps refusing with a new scope
/// would otherwise be asked forever.
pub async fn Oauth::renew(self : Oauth, challenge? : @auth.Challenge) -> Bool {
  if self.rounds >= 3 {
    return false
  }
  self.authorize(challenge?) catch {
    _ => return false
  }
  true
}

///|
/// Run the flow once. `challenge` is what the server said when it refused, when
/// it said anything.
pub async fn Oauth::authorize(
  self : Oauth,
  challenge? : @auth.Challenge,
) -> Unit raise @auth.Refused {
  self.rounds += 1
  let (resource, server) = self.discover(
    match challenge {
      Some(challenge) => challenge.resource_metadata
      None => None
    },
  )
  match resource {
    Some(resource) =>
      // RFC 8707: a resource that names another origin is not this resource,
      // and a token minted for it would be handed to the wrong server.
      if !@auth.same_origin(resource.resource, self.resource_url) {
        raise @auth.Refused(
          message="the protected resource metadata names \{resource.resource}, not \{self.resource_url}",
        )
      }
    None => ()
  }
  let scope = @auth.scope_for(challenge, resource, self.scope)
  let registration = self.establish(server)
  let tokens = match self.grant {
    ClientCredentials =>
      tokens_of(
        server,
        registration,
        @auth.client_credentials_form(
          resource?=self.resource_indicator(resource),
          scope?,
        ),
        self.assertion,
        (self.clock)(),
      )
    AuthorizationCode => {
      let pkce = @auth.Pkce::new()
      let state = @auth.new_state()
      let url = @auth.authorize_url(
        server,
        registration,
        self.redirect_uri,
        state,
        pkce,
        scope?,
        resource?=self.resource_indicator(resource),
      )
      let redirected = (self.present)(url) catch { _ => "" }
      if redirected.is_empty() {
        raise @auth.Refused(message="the authorization was not completed")
      }
      let redirect = @auth.Redirect::parse(redirected)
      match redirect.state {
        Some(got) =>
          if got != state {
            raise @auth.Refused(
              message="the redirect carried state \{got}, not the \{state} that was sent",
            )
          }
        None => ()
      }
      tokens_of(
        server,
        registration,
        @auth.authorization_code_form(
          code=redirect.code,
          redirect_uri=self.redirect_uri,
          verifier=pkce.verifier,
          resource?=self.resource_indicator(resource),
          scope?,
        ),
        self.assertion,
        (self.clock)(),
      )
    }
  }
  self.tokens = Some(tokens)
  self.good_until = tokens.good_until((self.clock)())
}

///|
/// The resource indicator to send: what the metadata calls the resource, which
/// is the identifier the server will check the token against.
fn Oauth::resource_indicator(
  self : Oauth,
  resource : @auth.Resource?,
) -> String? {
  ignore(self)
  match resource {
    Some(resource) => Some(resource.resource)
    None => None
  }
}

///|
/// Find the resource's metadata and the authorization server's. The resource's
/// may be absent — a 2025-03-26 server has none — and then the server's own
/// origin is the authorization server.
async fn Oauth::discover(
  self : Oauth,
  hinted : String?,
) -> (@auth.Resource?, @auth.Server) raise @auth.Refused {
  let resource = match self.resource {
    Some(resource) => Some(resource)
    None => {
      let found = discover_resource(self.resource_url, hinted)
      self.resource = found
      found
    }
  }
  let authorization_server = match resource {
    Some(resource) if !resource.authorization_servers.is_empty() =>
      resource.authorization_servers[0]
    _ => @auth.origin_of(self.resource_url)
  }
  match self.server {
    Some(server) => (resource, server)
    None => {
      let server = match discover_server(authorization_server) {
        Some(server) => server
        None =>
          if resource is None {
            // Nothing published anywhere: the endpoints MCP named before it
            // pointed at RFC 8414.
            @auth.Server::at_root(authorization_server)
          } else {
            raise @auth.Refused(
              message="\{authorization_server} publishes no authorization server metadata",
            )
          }
      }
      self.server = Some(server)
      (resource, server)
    }
  }
}

///|
/// The protected resource metadata, if the resource publishes one: the first
/// document that answers with success.
#warnings("-unused_error_type")
async fn discover_resource(
  resource_url : String,
  hinted : String?,
) -> @auth.Resource? raise @auth.Refused {
  for probe in @auth.Resource::probes(resource_url, hinted?) {
    let json = fetch_json(probe)
    guard json is Some(json) else { continue }
    let resource : @auth.Resource? = try @auth.Resource::parse(json) catch {
      _ => None
    } noraise {
      resource => Some(resource)
    }
    guard resource is Some(resource) else { continue }
    return Some(resource)
  }
  None
}

///|
/// The authorization server metadata, if it publishes one: RFC 8414 first, then
/// the two OpenID Connect spellings.
#warnings("-unused_error_type")
async fn discover_server(
  authorization_server : String,
) -> @auth.Server? raise @auth.Refused {
  for probe in @auth.Server::probes(authorization_server) {
    let json = fetch_json(probe)
    guard json is Some(json) else { continue }
    let server : @auth.Server? = try @auth.Server::parse(json) catch {
      _ => None
    } noraise {
      server => Some(server)
    }
    guard server is Some(server) else { continue }
    return Some(server)
  }
  None
}

///|
/// The JSON `url` answers with, or nothing: a document that does not load is
/// one to skip, not one to stop for.
#warnings("-unused_error_type")
async fn fetch_json(url : String) -> Json? raise @auth.Refused {
  let reply : Reply? = try get(url) catch {
    _ => None
  } noraise {
    reply => Some(reply)
  }
  guard reply is Some(reply) && reply.ok() else { return None }
  try json_of(reply) catch {
    _ => None
  } noraise {
    json => Some(json)
  }
}

///|
/// The registration to use: the configured one, a URL client identifier when
/// the server offers them, else a registration made now.
async fn Oauth::establish(
  self : Oauth,
  server : @auth.Server,
) -> @auth.Registration raise @auth.Refused {
  match self.registration {
    Some(registration) => registration
    None => {
      let registration = match self.pre_registered {
        Some(registration) => registration
        None =>
          match
            (server.client_id_metadata_document_supported, self.metadata_url) {
            (true, Some(url)) =>
              // SEP-991: the identifier is the document itself, and the server
              // reads what it needs from it.
              (
                {
                  client_id: url,
                  client_secret: None,
                  token_endpoint_auth_method: Some("none"),
                } : @auth.Registration)
            _ => self.register(server)
          }
      }
      self.registration = Some(registration)
      registration
    }
  }
}

///|
/// Register with `server`, asking for `scope` so that the registration covers
/// it.
async fn Oauth::register(
  self : Oauth,
  server : @auth.Server,
) -> @auth.Registration raise @auth.Refused {
  guard server.registration_endpoint is Some(endpoint) else {
    raise @auth.Refused(
      message="the authorization server offers no registration endpoint, and no credentials were configured",
    )
  }
  let body = Json(self.metadata.body()).stringify()
  let reply = post(endpoint, body, kind="application/json")
  if !reply.ok() {
    raise @auth.Refused(
      message="registration failed: HTTP \{reply.code}: \{reply.body}",
    )
  }
  @auth.Registration::parse(json_of(reply))
}

///|
/// Ask the token endpoint for a token, authenticating the client the way the
/// server and the registration agree on.
async fn tokens_of(
  server : @auth.Server,
  registration : @auth.Registration,
  form : Array[(String, String)],
  assertion : Assertion?,
  now : Int64,
) -> @auth.Tokens raise @auth.Refused {
  // A client that holds a signing key says so with an assertion; one that holds
  // a secret says so with HTTP Basic, a body field, or nothing at all.
  let credentials = @auth.Credentials::select(
    registration,
    server.token_endpoint_auth_methods_supported,
  )
  let pairs = match assertion {
    Some(assertion) => [..form, ..assertion.form(audience=server.issuer, now~)]
    None => [..form, ..@auth.Credentials::form(credentials, registration)]
  }
  let authorization = match assertion {
    Some(_) => None
    None => @auth.Credentials::authorization(credentials, registration)
  }
  let reply = post(
    server.token_endpoint,
    @auth.form_encode(pairs),
    authorization?,
  )
  if !reply.ok() {
    raise @auth.Refused(
      message="the token endpoint answered HTTP \{reply.code}: \{reply.body}",
    )
  }
  @auth.Tokens::parse(json_of(reply))
}
