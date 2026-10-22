/// Core protocol types shared across moonmcp, mirroring the MCP wire format.

/// JSON-RPC error codes defined by the MCP specification.
pub let parse_error : Int = -32700

pub let invalid_request : Int = -32600

pub let method_not_found : Int = -32601

pub let invalid_params : Int = -32602

pub let internal_error : Int = -32603

/// The protocol version this implementation speaks.
pub let latest_protocol_version : String = "2025-11-25"

/// Protocol versions with modern semantics (used for capability gating).
pub fn modern_protocol_versions() -> Array[String] {
  ["2025-06-18", "2025-11-25"]
}

pub fn handshake_protocol_versions() -> Array[String] {
  ["2025-03-26", "2025-06-18", "2025-11-25"]
}

/// Request `_meta` keys used to propagate session facts.
pub let server_info_meta_key : String = "serverInfo"

pub let client_info_meta_key : String = "clientInfo"

pub let protocol_version_meta_key : String = "protocolVersion"

pub let client_capabilities_meta_key : String = "clientCapabilities"

/// Verbosity levels for `notifications/message`, ordered debug → emergency.
pub(all) enum LoggingLevel {
  Debug
  Info
  Notice
  Warning
  Error
  Critical
  Alert
  Emergency
} derive(Debug, Eq)

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

/// Canonical JSON-RPC method and notification names.
pub let method_initialize : String = "initialize"

pub let method_ping : String = "ping"

pub let method_tools_list : String = "tools/list"

pub let method_tools_call : String = "tools/call"

pub let method_resources_list : String = "resources/list"

pub let method_resources_read : String = "resources/read"

pub let method_resources_subscribe : String = "resources/subscribe"

pub let method_resources_unsubscribe : String = "resources/unsubscribe"

pub let method_prompts_list : String = "prompts/list"

pub let method_prompts_get : String = "prompts/get"

pub let method_completion_complete : String = "completion/complete"

pub let method_logging_set_level : String = "logging/setLevel"

pub let method_roots_list : String = "roots/list"

pub let method_sampling_create_message : String = "sampling/createMessage"

pub let method_elicitation_create : String = "elicitation/create"

pub let method_elicitation_create_form : String = "elicitation/createForm"

pub let method_server_discover : String = "server/discover"

pub let method_input_response : String = "input/response"

pub let notification_initialized : String = "notifications/initialized"

pub let notification_cancelled : String = "notifications/cancelled"

pub let notification_progress : String = "notifications/progress"

pub let notification_message : String = "notifications/message"

pub let notification_roots_list_changed : String = "notifications/roots/list_changed"

pub let notification_resource_updated : String = "notifications/resources/updated"

pub let notification_resource_list_changed : String = "notifications/resources/list_changed"

pub let notification_tool_list_changed : String = "notifications/tools/list_changed"

pub let notification_prompt_list_changed : String = "notifications/prompts/list_changed"

/// Result type names that may appear as the `resultType` of a discover reply.
pub fn core_result_types() -> Array[String] {
  [
    "InitializeResult",
    "ListToolsResult",
    "CallToolResult",
    "ListPromptsResult",
    "GetPromptResult",
    "ListResourcesResult",
    "ReadResourceResult",
    "ListResourceTemplatesResult",
    "CompleteResult",
    "CreateMessageResult",
    "EmptyResult",
  ]
}

/// Wire-format error payload carried by JSON-RPC error responses.
pub(all) struct ErrorData {
  code : Int
  message : String
  data : Json?
} derive(ToJson, FromJson, Debug, Eq)

/// An icon for display in user interfaces.
pub(all) struct Icon {
  src : String
  mime_type : String?
  sizes : Array[String]?
} derive(Debug, Eq)

pub impl ToJson for Icon with to_json(self : Icon) -> Json {
  let obj : Map[String, Json] = { "src": self.src.to_json() }
  if self.mime_type is Some(mime_type) {
    obj["mimeType"] = mime_type.to_json()
  }
  if self.sizes is Some(sizes) {
    obj["sizes"] = sizes.to_json()
  }
  obj.to_json()
}

pub impl FromJson for Icon with from_json(
  json : Json,
  path : @json.JsonPath,
) -> Icon raise @json.JsonDecodeError {
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
  { src, mime_type, sizes }
}
