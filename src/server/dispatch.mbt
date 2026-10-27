// One JSON-RPC message in, at most one out. Which era a request belongs to is
// read off the request itself: the protocol version in `_meta` makes it a
// 2026-07-28 request, served on its own; `initialize` and everything without
// that `_meta` are served under the handshake revisions.

///|
let modern_versions : Array[String] = ["2026-07-28"]

///|
let legacy_versions : Array[String] = [
  "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05",
]

///|
let version_key = "io.modelcontextprotocol/protocolVersion"

///|
let server_info_key = "io.modelcontextprotocol/serverInfo"

///|
let parse_error = -32700

///|
let invalid_request = -32600

///|
let method_not_found = -32601

///|
let invalid_params = -32602

///|
let internal_error = -32603

///|
let header_mismatch = -32020

///|
let unsupported_version = -32022

///|
/// The 2025-11-25 code for a resource that is not there; 2026-07-28 moved it to
/// `invalid_params`.
let legacy_not_found = -32002

///|
/// A JSON-RPC error on its way to becoming a response.
priv suberror Fail {
  Fail(code~ : Int32, message~ : String, data~ : Json?)
}

///|
fn fail(code : Int32, message : String, data? : Json) -> Fail {
  Fail(code~, message~, data~)
}

///|
/// The era a request was sent in.
priv enum Era {
  Modern(String)
  Legacy
}

///|
/// Answer one JSON-RPC message, the way every transport does (← the
/// low-level server's message loop). `None` is the answer to a notification.
/// A message that is not JSON-RPC at all is answered with the error JSON-RPC
/// prescribes, under a `null` id.
pub async fn Server::handle(self : Server, message : Json) -> Json? {
  match self.answer(message) {
    Some((_, reply)) => Some(reply)
    None => None
  }
}

///|
/// The reply to `message` and the error code inside it, if it is an error;
/// a transport maps the code to its own status.
async fn Server::answer(self : Server, message : Json) -> (Int32?, Json)? {
  guard message is Object(m) &&
    m.get("jsonrpc") is Some(String("2.0")) &&
    m.get("method") is Some(String(op)) else {
    return Some(refusal(Json::null(), fail(invalid_request, "Invalid Request")))
  }
  let params = match m.get("params") {
    Some(Object(p)) => p
    None | Some(Null) => Map([])
    Some(_) =>
      return Some(
        refusal(
          m.get("id").unwrap_or(Json::null()),
          fail(invalid_params, "params must be an object"),
        ),
      )
  }
  guard m.get("id") is Some(id) else {
    // Notifications are acknowledged by silence; none of them changes what a
    // stateless server does next.
    return None
  }
  guard id is (String(_) | Number(_, ..)) else {
    return Some(
      refusal(
        Json::null(),
        fail(invalid_request, "id must be a string or a number"),
      ),
    )
  }
  let era = era_of(params)
  let result = self.dispatch(op, params, era) catch {
    Fail(_) as f => return Some(refusal(id, f))
    e => return Some(refusal(id, fail(internal_error, "\{e}")))
  }
  let result = match era {
    Modern(_) => self.stamp(result, op)
    Legacy => result
  }
  Some((None, { "jsonrpc": "2.0", "id": id, "result": result }))
}

///|
fn refusal(id : Json, f : Fail) -> (Int32?, Json) {
  let Fail(code~, message~, data~) = f
  let error : Map[String, Json] = {
    "code": Json(code),
    "message": Json(message),
  }
  if data is Some(d) {
    error["data"] = d
  }
  (Some(code), { "jsonrpc": "2.0", "id": id, "error": Json(error) })
}

///|
fn era_of(params : Map[String, Json]) -> Era {
  match params.get("_meta") {
    Some(Object(meta)) =>
      match meta.get(version_key) {
        Some(String(v)) => Modern(v)
        _ => Legacy
      }
    _ => Legacy
  }
}

///|
/// The fields every 2026-07-28 result carries: `resultType`, the server's
/// identity in `_meta`, and on the cacheable ones the caching hints.
fn Server::stamp(self : Server, result : Json, op : String) -> Json {
  guard result is Object(r) else { return result }
  let out = r.copy()
  out["resultType"] = "complete"
  let meta = match r.get("_meta") {
    Some(Object(m)) => m.copy()
    _ => Map([])
  }
  meta[server_info_key] = self.info.to_json()
  out["_meta"] = Json(meta)
  if op
    is ("server/discover"
    | "tools/list"
    | "resources/list"
    | "resources/templates/list"
    | "resources/read"
    | "prompts/list") {
    out["ttlMs"] = Json(self.ttl_ms)
    out["cacheScope"] = match self.scope {
      Public => "public"
      Private => "private"
    }
  }
  Json(out)
}

///|
async fn Server::dispatch(
  self : Server,
  op : String,
  params : Map[String, Json],
  era : Era,
) -> Json {
  if era is Modern(version) && !modern_versions.contains(version) {
    raise fail(unsupported_version, "Unsupported protocol version", data={
      "supported": Json(
        [..modern_versions, ..legacy_versions].map(Json::string),
      ),
      "requested": Json(version),
    })
  }
  match (op, era) {
    ("server/discover", _) => self.discover()
    ("initialize", _) => self.initialize(params)
    ("ping", Legacy) => Json::object(Map([]))
    ("tools/list", _) => {
      no_cursor(params)
      {
        "tools": Json(
          self.tools.values().map(t => t.to_mcp_tool().to_json()).collect(),
        ),
      }
    }
    ("tools/call", _) => self.call_tool(params)
    ("resources/list", _) => {
      no_cursor(params)
      {
        "resources": Json(
          self.resources
          .values()
          .map(r => r.to_mcp_resource().to_json())
          .collect(),
        ),
      }
    }
    ("resources/templates/list", _) => {
      no_cursor(params)
      {
        "resourceTemplates": Json(
          self.templates.map(t => t.to_mcp_template().to_json()),
        ),
      }
    }
    ("resources/read", _) => self.read_resource(params, era)
    ("prompts/list", _) => {
      no_cursor(params)
      {
        "prompts": Json(
          self.prompts.values().map(p => p.to_mcp_prompt().to_json()).collect(),
        ),
      }
    }
    ("prompts/get", _) => self.get_prompt(params)
    _ => raise fail(method_not_found, "Method not found: \{op}")
  }
}

///|
/// Every list comes back whole, so no cursor is ever issued and one sent
/// back is not one of ours.
fn no_cursor(params : Map[String, Json]) -> Unit raise {
  if params.get("cursor") is Some(String(_)) {
    raise fail(invalid_params, "Invalid cursor")
  }
}

///|
fn Server::discover(self : Server) -> Json {
  let out : Map[String, Json] = {
    "supportedVersions": Json(
      [..modern_versions, ..legacy_versions].map(Json::string),
    ),
    "capabilities": capabilities(),
  }
  if self.instructions is Some(text) {
    out["instructions"] = Json(text)
  }
  Json(out)
}

///|
/// The handshake of the revisions before 2026-07-28: the client's version when
/// the server speaks it, else the newest one the server does.
fn Server::initialize(self : Server, params : Map[String, Json]) -> Json raise {
  guard params.get("protocolVersion") is Some(String(asked)) else {
    raise fail(invalid_params, "initialize needs a protocolVersion")
  }
  let version = if legacy_versions.contains(asked) {
    asked
  } else {
    legacy_versions[0]
  }
  let out : Map[String, Json] = {
    "protocolVersion": Json(version),
    "capabilities": capabilities(),
    "serverInfo": self.info.to_json(),
  }
  if self.instructions is Some(text) {
    out["instructions"] = Json(text)
  }
  Json(out)
}

///|
fn capabilities() -> Json {
  {
    "tools": { "listChanged": false },
    "resources": { "subscribe": false, "listChanged": false },
    "prompts": { "listChanged": false },
  }
}

///|
/// A call checked against the tool's input schema, then run. A wrong argument
/// or a failing tool is a result marked `isError`, which the model reads and
/// can correct itself from; only a tool that is not there is a protocol error.
async fn Server::call_tool(self : Server, params : Map[String, Json]) -> Json {
  guard params.get("name") is Some(String(name)) else {
    raise fail(invalid_params, "tools/call needs a name")
  }
  guard self.tools.get(name) is Some(tool) else {
    raise fail(invalid_params, "Unknown tool: \{name}")
  }
  let args = match params.get("arguments") {
    Some(Object(a)) => a
    None | Some(Null) => Map([])
    Some(_) => raise fail(invalid_params, "arguments must be an object")
  }
  if self.checks.get(name) is Some(check) {
    let faults = check.faults(Json(args))
    if !faults.is_empty() {
      let lines = faults.map(f => {
        let at = if f.at == "" { "/" } else { f.at }
        "\{at}: \{f.message}"
      })
      return tool_error(
        "Invalid arguments for tool '\{name}': " + lines.join("; "),
      )
    }
  }
  let result = tool.run(args) catch {
    @exceptions.Mcp(data) =>
      raise fail(data.code, data.message, data?=data.data)
    e => return tool_error(text_of(e))
  }
  result.to_mcp_result().to_json()
}

///|
fn tool_error(text : String) -> Json {
  { "content": [{ "type": "text", "text": Json(text) }], "isError": true }
}

///|
/// The text of an error, without the constructor around a framework one.
fn text_of(e : Error) -> String {
  match e {
    @exceptions.Mcp(data) => data.message
    @exceptions.Validation(m)
    | @exceptions.Resource(m)
    | @exceptions.Tool(m)
    | @exceptions.Prompt(m)
    | @exceptions.InvalidSignature(m)
    | @exceptions.Client(m)
    | @exceptions.NotFound(m)
    | @exceptions.Disabled(m)
    | @exceptions.ResourceSecurity(m)
    | @exceptions.Authorisation(m) => m
    @exceptions.InsufficientScope(message~, ..) => message
    _ => "\{e}"
  }
}

///|
/// An error a resource or a prompt raised, as the JSON-RPC error it stands for.
fn as_fail(e : Error) -> Fail {
  match e {
    @exceptions.Mcp(data) => fail(data.code, data.message, data?=data.data)
    @exceptions.NotFound(m) | @exceptions.Validation(m) =>
      fail(invalid_params, m)
    _ => fail(internal_error, text_of(e))
  }
}

///|
async fn Server::read_resource(
  self : Server,
  params : Map[String, Json],
  era : Era,
) -> Json {
  guard params.get("uri") is Some(String(uri)) else {
    raise fail(invalid_params, "resources/read needs a uri")
  }
  let result = if self.resources.get(uri) is Some(resource) {
    resource.read_result() catch {
      e => raise as_fail(e)
    }
  } else {
    let mut found = None
    for template in self.templates {
      let matched = template.matches(uri, None) catch {
        e => raise fail(invalid_params, text_of(e))
      }
      if matched is Some(args) {
        found = Some((template, args))
        break
      }
    }
    guard found is Some((template, args)) else {
      let code = match era {
        Modern(_) => invalid_params
        Legacy => legacy_not_found
      }
      raise fail(code, "Resource not found", data={ "uri": Json(uri) })
    }
    template.read_result(uri, args) catch {
      e => raise as_fail(e)
    }
  }
  result.to_mcp_result(uri).to_json()
}

///|
async fn Server::get_prompt(self : Server, params : Map[String, Json]) -> Json {
  guard params.get("name") is Some(String(name)) else {
    raise fail(invalid_params, "prompts/get needs a name")
  }
  guard self.prompts.get(name) is Some(prompt) else {
    raise fail(invalid_params, "Unknown prompt: \{name}")
  }
  let args = match params.get("arguments") {
    Some(Object(a)) => a
    None | Some(Null) => Map([])
    Some(_) => raise fail(invalid_params, "arguments must be an object")
  }
  let rendered = prompt.render_result(args) catch { e => raise as_fail(e) }
  rendered.to_mcp_prompt_result().to_json()
}
