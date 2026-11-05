/// Core protocol types shared across moonmcp, mirroring the MCP wire format.

///|
/// JSON-RPC error codes defined by the MCP specification.
pub let parse_error : Int32 = -32700

///|
/// The JSON-RPC code for a message that is not a request at all.
pub let invalid_request : Int32 = -32600

///|
/// The JSON-RPC code for a method this revision does not define.
pub let method_not_found : Int32 = -32601

///|
/// The JSON-RPC code for arguments the method cannot use.
pub let invalid_params : Int32 = -32602

///|
/// The JSON-RPC code for a failure the server did not plan for.
pub let internal_error : Int32 = -32603

///|
/// The protocol version this implementation speaks.
pub let latest_protocol_version : String = "2025-11-25"

///|
/// Protocol versions with modern semantics (used for capability gating).
pub fn modern_protocol_versions() -> Array[String] {
  ["2025-06-18", "2025-11-25"]
}

///|
/// The revisions a client may name in `initialize`, newest first. The
/// stateless revision is not among them: it has no handshake.
pub fn handshake_protocol_versions() -> Array[String] {
  ["2025-03-26", "2025-06-18", "2025-11-25"]
}

///|
/// The `_meta` keys a 2026-07-28 request and reply carry their session facts
/// under. The prefix is the one the specification reserves for itself, so a
/// request from another revision is told apart by the presence of one of these
/// alone.
pub let server_info_meta_key : String = "io.modelcontextprotocol/serverInfo"

///|
/// The `_meta` key a request says who is calling under.
pub let client_info_meta_key : String = "io.modelcontextprotocol/clientInfo"

///|
/// The `_meta` key a stateless request names its protocol revision under.
pub let protocol_version_meta_key : String = "io.modelcontextprotocol/protocolVersion"

///|
/// The `_meta` key a request says what the client can do under.
pub let client_capabilities_meta_key : String = "io.modelcontextprotocol/clientCapabilities"

///|
/// The scope of a cacheable result, the `cacheScope` a list or a read carries:
/// who may keep the reply. `Public` says it holds nothing tied to one caller;
/// `Private` says a cache must belong to the authorisation context it was
/// fetched in.
#derive(Debug, Eq)
pub(all) enum CacheScope {
  Public
  Private
}

///|
pub fn CacheScope::to_wire(self : CacheScope) -> String {
  match self {
    Public => "public"
    Private => "private"
  }
}

///|
/// The cache scope a wire string names, or `None` for one this revision does
/// not define.
pub fn cache_scope_of_wire(value : String) -> CacheScope? {
  match value {
    "public" => Some(Public)
    "private" => Some(Private)
    _ => None
  }
}

///|
/// Verbosity levels for `notifications/message`, ordered debug → emergency.
#derive(Debug, Eq)
pub(all) enum LoggingLevel {
  Debug
  Info
  Notice
  Warning
  Error
  Critical
  Alert
  Emergency
}

///|
/// How severe a level is, for comparing two: RFC 5424's order, least severe first.
pub fn LoggingLevel::rank(self : LoggingLevel) -> Int32 {
  match self {
    Debug => 0
    Info => 1
    Notice => 2
    Warning => 3
    Error => 4
    Critical => 5
    Alert => 6
    Emergency => 7
  }
}

///|
pub fn LoggingLevel::to_wire(self : LoggingLevel) -> String {
  match self {
    Debug => "debug"
    Info => "info"
    Notice => "notice"
    Warning => "warning"
    Error => "error"
    Critical => "critical"
    Alert => "alert"
    Emergency => "emergency"
  }
}

///|
/// The severity a `notifications/message` names, or `None` for a level the
/// specification does not define.
pub fn logging_level_from_wire(value : String) -> LoggingLevel? {
  match value {
    "debug" => Some(Debug)
    "info" => Some(Info)
    "notice" => Some(Notice)
    "warning" => Some(Warning)
    "error" => Some(Error)
    "critical" => Some(Critical)
    "alert" => Some(Alert)
    "emergency" => Some(Emergency)
    _ => None
  }
}

///|
/// Canonical JSON-RPC method and notification names.
pub let method_initialize : String = "initialize"

///|
/// The wire name of the `ping` request.
pub let method_ping : String = "ping"

///|
/// The wire name of the `tools/list` request.
pub let method_tools_list : String = "tools/list"

///|
/// The wire name of the `tools/call` request.
pub let method_tools_call : String = "tools/call"

///|
/// The wire name of the `resources/list` request.
pub let method_resources_list : String = "resources/list"

///|
/// The wire name of the `resources/read` request.
pub let method_resources_read : String = "resources/read"

///|
/// The wire name of the `resources/subscribe` request.
pub let method_resources_subscribe : String = "resources/subscribe"

///|
/// The wire name of the `resources/unsubscribe` request.
pub let method_resources_unsubscribe : String = "resources/unsubscribe"

///|
/// The wire name of the `prompts/list` request.
pub let method_prompts_list : String = "prompts/list"

///|
/// The wire name of the `prompts/get` request.
pub let method_prompts_get : String = "prompts/get"

///|
/// The wire name of the `completion/complete` request.
pub let method_completion_complete : String = "completion/complete"

///|
/// The wire name of the `logging/setLevel` request.
pub let method_logging_set_level : String = "logging/setLevel"

///|
/// The wire name of the `roots/list` request.
pub let method_roots_list : String = "roots/list"

///|
/// The wire name of the `sampling/createMessage` request.
pub let method_sampling_create_message : String = "sampling/createMessage"

///|
/// The wire name of the `elicitation/create` request.
pub let method_elicitation_create : String = "elicitation/create"

///|
/// The wire name of the `elicitation/createForm` request.
pub let method_elicitation_create_form : String = "elicitation/createForm"

///|
/// The wire name of the `server/discover` request.
pub let method_server_discover : String = "server/discover"

///|
/// The wire name of the `subscriptions/listen` request.
pub let method_subscriptions_listen : String = "subscriptions/listen"

///|
/// The wire name of the `notifications/subscriptions/acknowledged` notification.
pub let notification_subscriptions_acknowledged : String = "notifications/subscriptions/acknowledged"

///|
/// The `_meta` key a subscription's messages carry the id of the stream that opened it under.
pub let subscription_id_meta_key : String = "io.modelcontextprotocol/subscriptionId"

///|
/// The wire name of the `input/response` request.
pub let method_input_response : String = "input/response"

///|
/// The wire name of the `notifications/initialized` notification.
pub let notification_initialized : String = "notifications/initialized"

///|
/// The wire name of the `notifications/cancelled` notification.
pub let notification_cancelled : String = "notifications/cancelled"

///|
/// The wire name of the `notifications/progress` notification.
pub let notification_progress : String = "notifications/progress"

///|
/// The wire name of the `notifications/message` notification.
pub let notification_message : String = "notifications/message"

///|
/// The wire name of the `notifications/roots/list_changed` notification.
pub let notification_roots_list_changed : String = "notifications/roots/list_changed"

///|
/// The wire name of the `notifications/resources/updated` notification.
pub let notification_resource_updated : String = "notifications/resources/updated"

///|
/// The wire name of the `notifications/resources/list_changed` notification.
pub let notification_resource_list_changed : String = "notifications/resources/list_changed"

///|
/// The wire name of the `notifications/tools/list_changed` notification.
pub let notification_tool_list_changed : String = "notifications/tools/list_changed"

///|
/// The wire name of the `notifications/prompts/list_changed` notification.
pub let notification_prompt_list_changed : String = "notifications/prompts/list_changed"

///|
/// Result type names that may appear as the `resultType` of a discover reply.
pub fn core_result_types() -> Array[String] {
  [
    "InitializeResult", "ListToolsResult", "CallToolResult", "ListPromptsResult",
    "GetPromptResult", "ListResourcesResult", "ReadResourceResult", "ListResourceTemplatesResult",
    "CompleteResult", "CreateMessageResult", "EmptyResult",
  ]
}

///|
/// Wire-format error payload carried by JSON-RPC error responses.
#derive(ToJson, FromJson, Debug, Eq)
pub(all) struct ErrorData {
  code : Int32
  message : String
  data : Json?
}

///|
/// An icon for display in user interfaces.
#derive(Debug, Eq)
pub(all) struct Icon {
  src : String
  mime_type : String?
  sizes : Array[String]?
}

///|
pub impl ToJson for Icon with fn to_json(self : Icon) -> Json {
  let obj : Map[String, Json] = { "src": Json(self.src) }
  if self.mime_type is Some(mime_type) {
    obj["mimeType"] = Json(mime_type)
  }
  if self.sizes is Some(sizes) {
    obj["sizes"] = Json(sizes)
  }
  Json(obj)
}

///|
pub impl FromJson for Icon with fn from_json(json : Json, path : @json.JsonPath) -> Icon raise @json.JsonDecodeError {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError((path, "Icon: expected object"))
  }
  let src : String = match obj.get("src") {
    Some(value) => @json.from_json(value, path=path.add_key("src"))
    None => raise @json.JsonDecodeError((path, "Icon: missing field src"))
  }
  let mime_type : String? = match obj.get("mimeType") {
    Some(value) => Some(@json.from_json(value, path=path.add_key("mimeType")))
    None => None
  }
  let sizes : Array[String]? = match obj.get("sizes") {
    Some(value) => Some(@json.from_json(value, path=path.add_key("sizes")))
    None => None
  }
  { src, mime_type, sizes, }
}

///|
pub extend ErrorData with @json.FromJson::{from_json}

///|
pub extend ErrorData with Debug::{to_repr}

///|
pub extend ErrorData with Eq::{not_equal, equal}

///|
pub extend ErrorData with ToJson::{to_json}

///|
pub extend Icon with @json.FromJson::{from_json}

///|
pub extend Icon with Debug::{to_repr}

///|
pub extend Icon with Eq::{not_equal, equal}

///|
pub extend Icon with ToJson::{to_json}

///|
pub extend LoggingLevel with Debug::{to_repr}

///|
pub extend LoggingLevel with Eq::{not_equal, equal}

///|
pub extend CacheScope with Debug::{to_repr}

///|
pub extend CacheScope with Eq::{not_equal, equal}
