// The client the official MCP conformance suite drives: one program that reads
// the scenario from the environment, does what that scenario asks a client to
// do, and exits.
//
//     MCP_CONFORMANCE_SCENARIO=auth/metadata-default \
//       moon run src/examples/08-conformance-client --target native -- http://127.0.0.1:PORT/mcp
//
// `scripts/interop/check_client_conformance.sh` starts the suite, which starts
// this program once per scenario and reads the checks it made.

///|
/// The client's own identity on the wire.
let client_name : String = "moonmcp-conformance"

///|
/// The revision the suite's servers speak. Its scenarios are the revisions up
/// to 2025-11-25, so the handshake runs.
let protocol_version : String = "2025-11-25"

///|
/// Where a browser is sent back to. Nothing listens there: the conformance
/// flow reads the code off the redirect instead of waiting for a browser.
let redirect_uri : String = "http://127.0.0.1:53682/callback"

///|
/// The fixed client metadata document the suite expects a URL client
/// identifier to name.
let metadata_url : String = "https://conformance-test.local/client-metadata.json"

///|
async fn main {
  let arguments = @env.args()
  guard arguments.length() > 1 else {
    abort("usage: 08-conformance-client <server-url>")
  }
  let url = arguments[1]
  let scenario = @env.get_env_var("MCP_CONFORMANCE_SCENARIO").unwrap_or("")
  let context = context_of(@env.get_env_var("MCP_CONFORMANCE_CONTEXT"))
  guard !scenario.is_empty() else {
    abort("MCP_CONFORMANCE_SCENARIO is not set")
  }
  run(scenario, url, context) catch {
    e => {
      println("scenario \{scenario} failed: \{e}")
      @env.exit(1)
    }
  }
}

///|
/// The scenario's own data, empty when it has none.
fn context_of(raw : String?) -> Map[String, Json] {
  guard raw is Some(raw) else { return Map([]) }
  let parsed : Json? = try @json.parse(raw) catch {
    _ => None
  } noraise {
    json => Some(json)
  }
  match parsed {
    Some(Object(fields)) => fields
    _ => Map([])
  }
}

///|
/// Do what `scenario` asks of a client.
async fn run(
  scenario : String,
  url : String,
  context : Map[String, Json],
) -> Unit {
  match scenario {
    "initialize" => plain(url, call_tool=false)
    "tools_call" => plain(url, call_tool=true)
    "elicitation-sep1034-client-defaults" => elicit(url)
    "sse-retry" => sse_retry(url)
    "auth/client-credentials-jwt" => client_credentials_jwt(url, context)
    "auth/client-credentials-basic" => client_credentials_basic(url, context)
    "auth/cross-app-access-complete-flow" => cross_app(url, context)
    _ =>
      if scenario.has_prefix("auth/") {
        // Every other authorization scenario is the same well-behaved client:
        // it connects, lists the tools and calls the one tool the suite serves.
        authorized(url, oauth_for(scenario, url, context))
      } else {
        abort("unknown scenario: \{scenario}")
      }
  }
}

///|
/// One field of a JSON body, or nothing when it is not an object or the field
/// is not a string.
fn field_of(body : Json, key : String) -> String? {
  match body {
    Object(fields) =>
      match fields.get(key) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
/// The handlers a conformance client offers: it accepts every elicitation with
/// an empty form, which the library fills from the schema's defaults.
fn handlers() -> @client.Handlers {
  @client.Handlers::new(
    elicitation=_request => @types.ElicitResult::accept(Map([])),
    roots=() => ({ roots: [], meta: None, } : @types.ListRootsResult),
    sampling=_request => {
      (
        {
          model: "conformance",
          stop_reason: Some("endTurn"),
          role: Assistant,
          content: @types.text_block("conformance"),
          meta: None,
        } : @types.CreateMessageResult)
    },
  )
}

///|
/// Connect, list the tools, and call one when the scenario expects it.
async fn plain(url : String, call_tool~ : Bool) -> Unit {
  let client = @client.Client::connect(
    @http.Http::new(url, version=protocol_version),
    name=client_name,
    version="1.0.0",
    protocol_version~,
    handlers=handlers(),
  )
  ignore(client.list_tools())
  if call_tool {
    ignore(
      client.call_tool("add_numbers", arguments={
        "a": Json::number(2.0),
        "b": Json::number(3.0),
      }),
    )
  }
  client.close()
}

///|
/// The elicitation scenario: the one tool asks a question, and the answer the
/// client sends back carries every default the schema named.
async fn elicit(url : String) -> Unit {
  let client = @client.Client::connect(
    @http.Http::new(url, version=protocol_version),
    name=client_name,
    version="1.0.0",
    protocol_version~,
    handlers=handlers(),
  )
  let tools = client.list_tools()
  let mut found = false
  for tool in tools {
    if tool.name == "test_client_elicitation_defaults" {
      found = true
    }
  }
  if found {
    ignore(
      client.call_tool("test_client_elicitation_defaults", arguments=Map([])),
    )
  }
  client.close()
}

///|
/// The streamable-HTTP scenario: a tool whose answer arrives after the first
/// stream closes, on the reopened one.
async fn sse_retry(url : String) -> Unit {
  let client = @client.Client::connect(
    @http.Http::new(url, version=protocol_version),
    name=client_name,
    version="1.0.0",
    protocol_version~,
    handlers=handlers(),
  )
  ignore(client.list_tools())
  ignore(client.call_tool("test_reconnection", arguments=Map([])))
  client.close()
}

///|
/// The OAuth client every authorization scenario drives, configured for that
/// scenario.
fn oauth_for(
  scenario : String,
  url : String,
  context : Map[String, Json],
) -> @oauth.Oauth {
  let pre_registered = match scenario {
    "auth/pre-registration" => Some(registration_of(context))
    _ => None
  }
  @oauth.Oauth::new(
    resource_url=url,
    client_name~,
    redirect_uri~,
    metadata_url~,
    pre_registered?,
    present=authorize_and_take_code,
  )
}

///|
/// The credentials a scenario hands to the client through the environment.
fn registration_of(context : Map[String, Json]) -> @auth.Registration {
  {
    client_id: text_in(context, "client_id"),
    client_secret: match context.get("client_secret") {
      Some(String(secret)) => Some(secret)
      _ => None
    },
    token_endpoint_auth_method: None,
  }
}

///|
/// A field of the conformance context.
fn text_in(context : Map[String, Json], key : String) -> String {
  match context.get(key) {
    Some(String(value)) => value
    _ => abort("the scenario's context has no \{key}")
  }
}

///|
/// Fetch the authorization URL without following it, and give back where it
/// points: the redirect that carries the code. A browser does this by hand; a
/// conformance run has nobody to ask.
async fn authorize_and_take_code(url : String) -> String {
  let client = @net.Client::Client(@auth.origin_of(url)) catch {
    _ => return ""
  }
  defer client.close()
  let response = client.get(@auth.target_of(url), extra_headers={
    "accept": "text/html",
  }) catch {
    _ => return ""
  }
  match header_of(response.headers, "location") {
    Some(location) => location
    None => ""
  }
}

///|
/// One header of a reply, whatever its case.
fn header_of(headers : @net.Headers, name : String) -> String? {
  for pair in headers {
    if pair.0.to_string().to_lower() == name.to_lower() {
      return Some(pair.1)
    }
  }
  None
}

///|
/// Connect as a client that holds credentials, listing the tools and calling
/// the suite's tool; the transport asks for a token whenever the server says
/// it needs one.
async fn authorized(url : String, oauth : @oauth.Oauth) -> Unit {
  let client = @client.Client::connect(
    @http.Http::new(
      url,
      version=protocol_version,
      token=fn() { oauth.bearer() },
      renew=async fn(status, header) {
        ignore(status)
        oauth.renew(challenge?=@auth.Challenge::parse(header))
      },
    ),
    name=client_name,
    version="1.0.0",
    protocol_version~,
    handlers=handlers(),
  )
  ignore(client.list_tools())
  ignore(client.call_tool("test-tool", arguments=Map([])))
  client.close()
}

///|
/// The client-credentials scenario, authenticating with a signed assertion.
async fn client_credentials_jwt(
  url : String,
  context : Map[String, Json],
) -> Unit {
  let assertion = @oauth.Assertion::es256(
    client_id=text_in(context, "client_id"),
    private_key=text_in(context, "private_key_pem"),
  ) catch {
    @auth.Refused(message~) => abort(message)
  }
  let oauth = @oauth.Oauth::new(
    resource_url=url,
    client_name~,
    redirect_uri~,
    grant=ClientCredentials,
    assertion~,
    pre_registered={
      client_id: text_in(context, "client_id"),
      client_secret: None,
      token_endpoint_auth_method: Some("private_key_jwt"),
    },
    present=authorize_and_take_code,
  )
  ignore(oauth.authorize())
  with_token(url, oauth)
}

///|
/// The client-credentials scenario, authenticating with a shared secret.
async fn client_credentials_basic(
  url : String,
  context : Map[String, Json],
) -> Unit {
  let oauth = @oauth.Oauth::new(
    resource_url=url,
    client_name~,
    redirect_uri~,
    grant=ClientCredentials,
    pre_registered={
      client_id: text_in(context, "client_id"),
      client_secret: Some(text_in(context, "client_secret")),
      token_endpoint_auth_method: Some("client_secret_basic"),
    },
    present=authorize_and_take_code,
  )
  ignore(oauth.authorize())
  with_token(url, oauth)
}

///|
/// Connect with the token a non-interactive flow already obtained.
async fn with_token(url : String, oauth : @oauth.Oauth) -> Unit {
  let client = @client.Client::connect(
    @http.Http::new(url, version=protocol_version, token=fn() { oauth.bearer() }),
    name=client_name,
    version="1.0.0",
    protocol_version~,
    handlers=handlers(),
  )
  ignore(client.list_tools())
  ignore(client.call_tool("test-tool", arguments=Map([])))
  client.close()
}

///|
/// SEP-990: an identity provider's ID token becomes an authorization grant at
/// the authorization server, and that grant becomes the access token the MCP
/// server takes.
async fn cross_app(url : String, context : Map[String, Json]) -> Unit {
  // The resource and the authorization server, from the protected resource
  // metadata both sides agree on.
  let prm_url = @auth.origin_of(url) +
    "/.well-known/oauth-protected-resource/mcp"
  let prm = @auth.Resource::parse(@oauth.json_of(@oauth.get(prm_url)))
  let authorization_server = prm.authorization_servers[0]
  let server = @auth.Server::parse(
    @oauth.json_of(
      @oauth.get(
        authorization_server + "/.well-known/oauth-authorization-server",
      ),
    ),
  )
  // The ID token is exchanged at the identity provider for an ID-JAG, and the
  // ID-JAG for an access token at the authorization server.
  let exchange = @oauth.post(
    text_in(context, "idp_token_endpoint"),
    @auth.form_encode([
      ("grant_type", "urn:ietf:params:oauth:grant-type:token-exchange"),
      ("requested_token_type", "urn:ietf:params:oauth:token-type:id-jag"),
      // The grant is for the authorization server, which is what the identity
      // provider addresses it to.
      ("audience", server.issuer),
      ("resource", prm.resource),
      ("subject_token", text_in(context, "idp_id_token")),
      ("subject_token_type", "urn:ietf:params:oauth:token-type:id_token"),
      ("client_id", text_in(context, "idp_client_id")),
    ]),
  )
  let exchange_body = @oauth.json_of(exchange)
  let id_jag = match field_of(exchange_body, "access_token") {
    Some(token) => token
    _ => abort("the identity provider returned no ID-JAG: \{exchange.body}")
  }
  let client_id = text_in(context, "client_id")
  let client_secret = text_in(context, "client_secret")
  let pair = "\{@auth.percent_encode(client_id)}:\{@auth.percent_encode(client_secret)}"
  let access = @oauth.post(
    authorization_server + "/token",
    @auth.form_encode([
      ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
      ("assertion", id_jag),
    ]),
    authorization="Basic " +
      @base64.encode(@utf8.encode(pair)[:], kind=Std, padding=true),
  )
  let access_body = @oauth.json_of(access)
  let token = match field_of(access_body, "access_token") {
    Some(token) => token
    _ => abort("the authorization server returned no token: \{access.body}")
  }
  let client = @client.Client::connect(
    @http.Http::new(url, version=protocol_version, token=fn() { Some(token) }),
    name=client_name,
    version="1.0.0",
    protocol_version~,
    handlers=handlers(),
  )
  ignore(client.list_tools())
  ignore(client.call_tool("test-tool", arguments=Map([])))
  client.close()
}
