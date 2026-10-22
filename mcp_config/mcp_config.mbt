/// Canonical MCP configuration format, mirroring fastmcp/mcp_config.py.

fn cfg_err(
  path : @json.JsonPath,
  message : String,
) -> @json.JsonDecodeError {
  @json.JsonDecodeError((path, message))
}

fn expect_obj(
  json : Json,
  path : @json.JsonPath,
  context : String,
) -> Map[String, Json] raise @json.JsonDecodeError {
  guard json is Object(obj) else {
    raise cfg_err(path, "\{context}: expected object")
  }
  obj
}

fn opt_str(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(v)) => Some(v)
    _ => None
  }
}

fn req_str(
  obj : Map[String, Json],
  path : @json.JsonPath,
  context : String,
  key : String,
) -> String raise @json.JsonDecodeError {
  guard obj.get(key) is Some(String(v)) else {
    raise cfg_err(path, "\{context}: missing string field \{key}")
  }
  v
}

fn opt_int(obj : Map[String, Json], key : String) -> Int? {
  match obj.get(key) {
    Some(Number(v, ..)) => Some(v.to_int())
    _ => None
  }
}

fn opt_bool(obj : Map[String, Json], key : String) -> Bool? {
  match obj.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

fn opt_str_array(obj : Map[String, Json], key : String) -> Array[String]? {
  match obj.get(key) {
    Some(Array(values)) => Some(values.filter_map(fn(v) { v.as_string() }))
    _ => None
  }
}

fn opt_obj(obj : Map[String, Json], key : String) -> Map[String, Json]? {
  match obj.get(key) {
    Some(Object(v)) => Some(v)
    _ => None
  }
}

fn put_str(obj : Map[String, Json], key : String, value : String) -> Unit {
  obj[key] = Json::string(value)
}

fn put_opt_str(obj : Map[String, Json], key : String, value : String?) -> Unit {
  if value is Some(v) {
    obj[key] = Json::string(v)
  }
}

fn put_opt_int(obj : Map[String, Json], key : String, value : Int?) -> Unit {
  if value is Some(v) {
    obj[key] = Json::number(v.to_double())
  }
}

fn put_opt_bool(obj : Map[String, Json], key : String, value : Bool?) -> Unit {
  if value is Some(v) {
    obj[key] = Json::boolean(v)
  }
}

/// Infer `"sse"` or `"http"` from a remote server URL.
pub fn infer_transport_type_from_url(
  url : String,
) -> Result[String, String] {
  if not(url.has_prefix("http")) {
    return Err("Invalid URL: \{url}")
  }
  // Match /sse followed by /, ?, &, or end of string.
  let path_start = match url.find("://") {
    Some(authority_start) => {
      let rest = url[authority_start + 3:]
      match rest.find("/") {
        Some(index) => authority_start + 3 + index
        None => url.length()
      }
    }
    None => 0
  }
  let path = url[path_start:].to_string()
  match path.find("/sse") {
    Some(index) => {
      let after = path.get_char(index + 4)
      if after is None || after.unwrap() == '/' || after.unwrap() == '?' || after.unwrap() == '&' {
        Ok("sse")
      } else {
        Ok("http")
      }
    }
    None => Ok("http")
  }
}

/// FastMCP-specific tool transforms and tag filters for a proxied server.
pub(all) struct ServerTransform {
  /// Tool transform configs keyed by tool name.
  tools : Map[String, Json]
  include_tags : @set.Set[String]?
  exclude_tags : @set.Set[String]?
} derive(Debug, Eq)

pub(all) enum RemoteTransport {
  Http
  StreamableHttp
  Sse
} derive(Debug, Eq)

/// One server entry: either a stdio command or a remote URL.
pub(all) enum MCPServerKind {
  Stdio(
    command~ : String,
    args~ : Array[String],
    env~ : Map[String, Json],
    cwd~ : String?,
    keep_alive~ : Bool?,
  )
  Remote(
    url~ : String,
    transport~ : RemoteTransport?,
    headers~ : Map[String, String],
    /// Bearer token, or the literal "oauth".
    auth~ : String?,
    sse_read_timeout_ms~ : Int?,
  )
} derive(Debug, Eq)

pub(all) struct MCPServerEntry {
  kind : MCPServerKind
  /// Per-request timeout in milliseconds; zero disables it.
  timeout : Int?
  description : String?
  icon : String?
  authentication : Map[String, Json]?
  transform : ServerTransform?
} derive(Debug, Eq)

pub impl ToJson for MCPServerEntry with to_json(self : MCPServerEntry) -> Json {
  let obj : Map[String, Json] = {}
  match self.kind {
    Stdio(command~, args~, env~, cwd~, keep_alive~) => {
      put_str(obj, "command", command)
      obj["args"] = Json::array(args.map(Json::string))
      let env_obj : Map[String, Json] = {}
      for key, value in env {
        env_obj[key] = value
      }
      obj["env"] = env_obj.to_json()
      put_opt_str(obj, "cwd", cwd)
      put_opt_bool(obj, "keepAlive", keep_alive)
    }
    Remote(url~, transport~, headers~, auth~, sse_read_timeout_ms~) => {
      put_str(obj, "url", url)
      put_opt_str(
        obj,
        "transport",
        transport.map(RemoteTransport::to_wire),
      )
      let headers_obj : Map[String, Json] = {}
      for key, value in headers {
        headers_obj[key] = Json::string(value)
      }
      obj["headers"] = headers_obj.to_json()
      put_opt_str(obj, "auth", auth)
      put_opt_int(obj, "sseReadTimeout", sse_read_timeout_ms)
    }
  }
  put_opt_int(obj, "timeout", self.timeout)
  put_opt_str(obj, "description", self.description)
  put_opt_str(obj, "icon", self.icon)
  if self.authentication is Some(auth) {
    obj["authentication"] = auth.to_json()
  }
  if self.transform is Some(transform) {
    let tools_obj : Map[String, Json] = {}
    for key, value in transform.tools {
      tools_obj[key] = value
    }
    obj["tools"] = tools_obj.to_json()
    if transform.include_tags is Some(tags) {
      obj["includeTags"] = Json::array(tags.to_array().map(Json::string))
    }
    if transform.exclude_tags is Some(tags) {
      obj["excludeTags"] = Json::array(tags.to_array().map(Json::string))
    }
  }
  obj.to_json()
}

pub fn RemoteTransport::to_wire(self : RemoteTransport) -> String {
  match self {
    Http => "http"
    StreamableHttp => "streamable-http"
    Sse => "sse"
  }
}

pub impl FromJson for MCPServerEntry with from_json(
  json : Json,
  path : @json.JsonPath,
) -> MCPServerEntry raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "MCPServerEntry")
  let kind : MCPServerKind = match obj.get("command") {
    Some(String(command)) => {
      let args = opt_str_array(obj, "args").unwrap_or([])
      let env = opt_obj(obj, "env").unwrap_or({})
      Stdio(
        command~,
        args= args,
        env= env,
        cwd= opt_str(obj, "cwd"),
        keep_alive= opt_bool(obj, "keepAlive"),
      )
    }
    _ => {
      let url = req_str(obj, path, "MCPServerEntry", "url")
      let transport = match opt_str(obj, "transport") {
        Some("http") => Some(Http)
        Some("streamable-http") => Some(StreamableHttp)
        Some("sse") => Some(Sse)
        _ => match infer_transport_type_from_url(url) {
          Ok("sse") => Some(Sse)
          Ok("http") => Some(Http)
          Ok(other) => raise cfg_err(path, "MCPServerEntry: bad transport \{other}")
          Err(message) => raise cfg_err(path, message)
        }
      }
      let headers : Map[String, String] = {}
      if opt_obj(obj, "headers") is Some(headers_obj) {
        for key, value in headers_obj {
          if value is String(v) {
            headers[key] = v
          }
        }
      }
      Remote(
        url~,
        transport= transport,
        headers= headers,
        auth= opt_str(obj, "auth"),
        sse_read_timeout_ms= opt_int(obj, "sseReadTimeout"),
      )
    }
  }
  let tools : Map[String, Json] = {}
  if opt_obj(obj, "tools") is Some(tools_obj) {
    for key, value in tools_obj {
      tools[key] = value
    }
  }
  let include_tags : Array[String]? = opt_str_array(obj, "includeTags")
  let exclude_tags : Array[String]? = opt_str_array(obj, "excludeTags")
  let transform : ServerTransform? = if not(tools.is_empty()) || include_tags is Some(_) || exclude_tags is Some(_) {
    Some({
      tools,
      include_tags: include_tags.map(fn(tags) { @set.Set::from_array(tags) }),
      exclude_tags: exclude_tags.map(fn(tags) { @set.Set::from_array(tags) }),
    })
  } else {
    None
  }
  {
    kind,
    timeout: opt_int(obj, "timeout"),
    description: opt_str(obj, "description"),
    icon: opt_str(obj, "icon"),
    authentication: opt_obj(obj, "authentication"),
    transform,
  }
}

/// A configuration object for MCP servers.
pub(all) struct MCPConfig {
  mcp_servers : Map[String, MCPServerEntry]
} derive(Debug, Eq)

pub fn MCPConfig::new() -> MCPConfig {
  { mcp_servers: {} }
}

/// Add or update a server in the configuration.
pub fn MCPConfig::add_server(
  self : MCPConfig,
  name : String,
  server : MCPServerEntry,
) -> Unit {
  self.mcp_servers[name] = server
}

pub impl FromJson for MCPConfig with from_json(
  json : Json,
  path : @json.JsonPath,
) -> MCPConfig raise @json.JsonDecodeError {
  let root = expect_obj(json, path, "MCPConfig")
  let servers : Map[String, Json] = match root.get("mcpServers") {
    Some(Object(servers)) => servers
    _ => {
      // Server configs at root wrap under mcpServers.
      let has_servers = {
        let mut found = false
        for _, value in root {
          if value is Object(entry) && (entry.get("command") is Some(_) || entry.get("url") is Some(_)) {
            found = true
            break
          }
        }
        found
      }
      if has_servers {
        root
      } else {
        raise cfg_err(path, "MCPConfig: no mcpServers key")
      }
    }
  }
  let config = MCPConfig::new()
  for name, value in servers {
    config.mcp_servers[name] = @json.from_json(value)
  }
  config
}

/// Parse MCP configuration from a JSON document.
pub fn config_from_json(
  json : Json,
) -> MCPConfig raise @json.JsonDecodeError {
  @json.from_json(json)
}

/// Convert the configuration to a JSON document, omitting empty fields.
pub fn MCPConfig::to_json(self : MCPConfig) -> Json {
  let servers : Map[String, Json] = {}
  for name, entry in self.mcp_servers {
    servers[name] = MCPServerEntry::to_json(entry)
  }
  Json::object({ "mcpServers": servers.to_json() })
}
