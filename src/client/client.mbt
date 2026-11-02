// The client: the protocol from the caller's side. It owns the request ids,
// says which revision it speaks, carries its identity on every modern request,
// and turns replies into the types of the library.

///|
/// A server said no. The code and data are the JSON-RPC error as it arrived.
pub suberror Refused {
  Refused(code~ : Int32, message~ : String, data~ : Json?)
}

///|
/// A connection to a server, with the handshake behind it (← FastMCP's
/// `Client`).
///
/// On the 2026-07-28 revision there is no handshake: every request carries the
/// version, the client's identity and its capabilities in `_meta`, and the
/// server answers on its own. On the revisions before it, `connect` runs
/// `initialize` and `notifications/initialized` once.
pub struct Client {
  priv transport : &Transport
  priv mut next_id : Int32
  priv mut server_info : @types.Implementation?
  priv mut server_capabilities : @types.ServerCapabilities?
  priv mut protocol_version : String
  info : @types.Implementation
  capabilities : @types.ClientCapabilities
  priv modern : Bool
}

///|
/// Connect over `transport`. `protocol_version` picks the dialect: `2026-07-28`
/// speaks the stateless revision, anything the server lists as older runs the
/// handshake. The default follows the server's own `latest_protocol_version`.
pub async fn Client::connect(
  transport : &Transport,
  name~ : String = "moonmcp",
  version~ : String = "0.1.0",
  protocol_version~ : String = @types.latest_protocol_version,
  capabilities~ : @types.ClientCapabilities = @types.ClientCapabilities::new(),
) -> Client {
  let client : Client = {
    transport,
    next_id: 1,
    server_info: None,
    server_capabilities: None,
    protocol_version,
    info: { name, title: None, version, },
    capabilities,
    modern: modern_revision(protocol_version),
  }
  if !client.modern {
    client.handshake()
  }
  client
}

///|
/// Whether `version` is one this library serves without a handshake.
fn modern_revision(version : String) -> Bool {
  version == "2026-07-28"
}

///|
/// The handshake of the revisions before 2026-07-28, run once at connect:
/// `initialize`, then `notifications/initialized`, with the server's identity
/// and capabilities kept for the caller.
async fn Client::handshake(self : Client) -> Unit {
  let reply = self.transport.ask(
    self.frame(
      "initialize",
      {
        "protocolVersion": Json::string(self.protocol_version),
        "capabilities": self.capabilities.to_json(),
        "clientInfo": self.info.to_json(),
      },
      modern=false,
    ),
    fn(_) { () },
  )
  let result = result_of(reply)
  match result.get("protocolVersion") {
    Some(String(version)) => self.protocol_version = version
    _ => ()
  }
  self.server_info = decode_or_none(result, "serverInfo")
  self.server_capabilities = decode_or_none(result, "capabilities")
  self.transport.tell(notification(@types.notification_initialized, Map([]))) catch {
    _ => ()
  }
}

///|
/// Field `key` of `result`, read as `T`; `None` when it is absent or does not
/// read. A server that omits part of the handshake is served as best it can
/// be rather than refused.
fn[T : @json.FromJson] decode_or_none(
  result : Map[String, Json],
  key : String,
) -> T? {
  match result.get(key) {
    Some(value) =>
      try @json.from_json(value) catch {
        _ => None
      } noraise {
        decoded => Some(decoded)
      }
    None => None
  }
}

///|
/// Who the server says it is, once it has said.
pub fn Client::server_info(self : Client) -> @types.Implementation? {
  self.server_info
}

///|
/// What the server says it can do.
pub fn Client::server_capabilities(self : Client) -> @types.ServerCapabilities? {
  self.server_capabilities
}

///|
/// The revision in force on this connection.
pub fn Client::protocol_version(self : Client) -> String {
  self.protocol_version
}

///|
/// The next request id, taken.
fn Client::take_id(self : Client) -> Int32 {
  let id = self.next_id
  self.next_id = id + 1
  id
}

///|
/// One request message, with the metadata a stateless revision wants on every
/// request.
fn Client::frame(
  self : Client,
  operation : String,
  params : Map[String, Json],
  modern~ : Bool,
) -> Json {
  let out = params.copy()
  if modern {
    let meta : Map[String, Json] = match params.get("_meta") {
      Some(Object(meta)) => meta.copy()
      _ => Map([])
    }
    meta[@types.protocol_version_meta_key] = Json::string(self.protocol_version)
    meta[@types.client_info_meta_key] = self.info.to_json()
    meta[@types.client_capabilities_meta_key] = self.capabilities.to_json()
    out["_meta"] = Json(meta)
  }
  {
    "jsonrpc": "2.0",
    "id": Json::number(self.take_id().to_double()),
    "method": Json::string(operation),
    "params": Json(out),
  }
}

///|
/// Ask `operation` with `params` and hand back the result, raising `Refused`
/// when the server answers with an error.
pub async fn Client::request(
  self : Client,
  operation : String,
  params~ : Map[String, Json] = Map([]),
) -> Map[String, Json] {
  self.exchange(operation, params~, on_notification=fn(_) { () })
}

///|
/// The same, with somewhere to put the notifications the server sends while
/// the answer is being worked out: progress, log messages.
pub async fn Client::exchange(
  self : Client,
  operation : String,
  params~ : Map[String, Json] = Map([]),
  on_notification~ : async (Json) -> Unit = fn(_) { () },
  progress_token? : Json,
) -> Map[String, Json] {
  let mut adjusted = params
  if progress_token is Some(token) {
    let with_meta = adjusted.copy()
    let meta : Map[String, Json] = match params.get("_meta") {
      Some(Object(meta)) => meta.copy()
      _ => Map([])
    }
    meta["progressToken"] = token
    with_meta["_meta"] = Json(meta)
    adjusted = with_meta
  }
  let reply = self.transport.ask(
    self.frame(operation, adjusted, modern=self.modern),
    on_notification,
  )
  result_of(reply)
}

///|
/// Send a message that gets no reply.
pub async fn Client::notify(
  self : Client,
  operation : String,
  params~ : Map[String, Json] = Map([]),
) -> Unit {
  self.transport.tell(notification(operation, params))
}

///|
/// Open a subscription and hand every notification on it to `on_notification`
/// until the server ends it.
pub async fn Client::listen(
  self : Client,
  filter~ : @types.SubscriptionFilter,
  on_notification~ : async (Json) -> Unit,
) -> Unit {
  let message = self.frame(
    @types.method_subscriptions_listen,
    { "notifications": filter.to_json() },
    modern=self.modern,
  )
  self.transport.listen(message, on_notification)
}

///|
/// Stop asking for anything on this connection.
pub async fn Client::close(self : Client) -> Unit {
  self.transport.close()
}

///|
/// A bare result with no payload.
pub async fn Client::ping(self : Client) -> Unit {
  ignore(self.request(@types.method_ping))
}

///|
/// What the server supports and which revisions it speaks.
pub async fn Client::discover(self : Client) -> Map[String, Json] {
  self.request(@types.method_server_discover)
}

///|
/// The tools the server offers.
pub async fn Client::list_tools(self : Client) -> Array[@types.Tool] {
  let result = self.request(@types.method_tools_list)
  match result.get("tools") {
    Some(Array(tools)) => tools.map(tool => @json.from_json(tool))
    _ =>
      raise Refused(
        code=@types.invalid_params,
        message="tools/list carried no tools",
        data=None,
      )
  }
}

///|
/// Call `name` with `arguments`; notifications sent before the answer go to
/// `on_notification`.
pub async fn Client::call_tool(
  self : Client,
  name : String,
  arguments~ : Map[String, Json] = Map([]),
  on_notification~ : async (Json) -> Unit = fn(_) { () },
  progress_token? : Json,
) -> @types.CallToolResult {
  let result = self.exchange(
    @types.method_tools_call,
    params={ "name": Json::string(name), "arguments": Json(arguments) },
    on_notification~,
    progress_token?,
  )
  @json.from_json(Json(result))
}

///|
/// The resources the server offers.
pub async fn Client::list_resources(self : Client) -> Array[@types.Resource] {
  let result = self.request(@types.method_resources_list)
  match result.get("resources") {
    Some(Array(resources)) =>
      resources.map(resource => @json.from_json(resource))
    _ =>
      raise Refused(
        code=@types.invalid_params,
        message="resources/list carried no resources",
        data=None,
      )
  }
}

///|
/// Read the resource at `uri`.
pub async fn Client::read_resource(
  self : Client,
  uri : String,
) -> @types.ReadResourceResult {
  let result = self.request(@types.method_resources_read, params={
    "uri": Json::string(uri),
  })
  @json.from_json(Json(result))
}

///|
/// The prompts the server offers.
pub async fn Client::list_prompts(self : Client) -> Array[@types.Prompt] {
  let result = self.request(@types.method_prompts_list)
  match result.get("prompts") {
    Some(Array(prompts)) => prompts.map(prompt => @json.from_json(prompt))
    _ =>
      raise Refused(
        code=@types.invalid_params,
        message="prompts/list carried no prompts",
        data=None,
      )
  }
}

///|
/// Render the prompt `name` with `arguments`.
pub async fn Client::get_prompt(
  self : Client,
  name : String,
  arguments~ : Map[String, Json] = Map([]),
) -> @types.GetPromptResult {
  let result = self.request(@types.method_prompts_get, params={
    "name": Json::string(name),
    "arguments": Json(arguments),
  })
  @json.from_json(Json(result))
}

///|
/// The result of a reply, or the error it carries as `Refused`.
fn result_of(reply : Json) -> Map[String, Json] raise {
  guard reply is Object(obj) else {
    raise Refused(
      code=@types.internal_error,
      message="Reply is not an object",
      data=None,
    )
  }
  match obj.get("error") {
    Some(Object(error)) =>
      raise Refused(
        code=match error.get("code") {
          Some(Number(value, ..)) => value.to_int()
          _ => @types.internal_error
        },
        message=match error.get("message") {
          Some(String(text)) => text
          _ => "The server refused"
        },
        data=error.get("data"),
      )
    _ => ()
  }
  match obj.get("result") {
    Some(Object(result)) => result
    Some(_) =>
      raise Refused(
        code=@types.internal_error,
        message="Reply carries no result object",
        data=None,
      )
    None =>
      raise Refused(
        code=@types.internal_error,
        message="Reply carries no result",
        data=None,
      )
  }
}

///|
/// One notification message.
fn notification(operation : String, params : Map[String, Json]) -> Json {
  {
    "jsonrpc": "2.0",
    "method": Json::string(operation),
    "params": Json(params),
  }
}
