/// JSON-RPC envelope and typed request/notification dispatch.

/// A JSON-RPC request id: either a number or a string.
pub(all) enum RequestId {
  Number(id~ : Int)
  Text(id~ : String)
} derive(Debug, Eq)

pub impl ToJson for RequestId with to_json(self : RequestId) -> Json {
  match self {
    Number(id~) => Json::number(id.to_double())
    Text(id~) => Json::string(id)
  }
}

pub impl FromJson for RequestId with from_json(
  json : Json,
  path : @json.JsonPath,
) -> RequestId raise @json.JsonDecodeError {
  match json {
    Number(id, ..) => {
      let id : Int = id.to_int()
      Number(id~)
    }
    String(id) => Text(id~)
    _ => raise decode_error(path, "RequestId: expected number or string")
  }
}

/// Any message frame on the wire.
pub(all) enum JSONRPCMessage {
  Request(id~ : RequestId, method~ : String, params~ : Json?)
  Notification(method~ : String, params~ : Json?)
  Response(id~ : RequestId, result~ : Json)
  Error(id~ : RequestId, error~ : ErrorData)
} derive(Debug, Eq)

pub impl ToJson for JSONRPCMessage with to_json(self : JSONRPCMessage) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "jsonrpc", "2.0")
  match self {
    Request(id~, method~, params~) => {
      put_opt_json(obj, "id", Some(RequestId::to_json(id)))
      put_str(obj, "method", method)
      put_opt_json(obj, "params", params)
    }
    Notification(method~, params~) => {
      put_str(obj, "method", method)
      put_opt_json(obj, "params", params)
    }
    Response(id~, result~) => {
      put_opt_json(obj, "id", Some(RequestId::to_json(id)))
      put_opt_json(obj, "result", Some(result))
    }
    Error(id~, error~) => {
      put_opt_json(obj, "id", Some(RequestId::to_json(id)))
      put_opt_json(obj, "error", Some(ErrorData::to_json(error)))
    }
  }
  obj.to_json()
}

pub impl FromJson for JSONRPCMessage with from_json(
  json : Json,
  path : @json.JsonPath,
) -> JSONRPCMessage raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "JSONRPCMessage")
  let id = match obj.get("id") {
    Some(value) => Some(@json.from_json(value))
    None => None
  }
  if obj.get("method") is Some(String(method)) {
    let params = obj.get("params")
    match id {
      Some(id) => Request(id~, method~, params= params)
      None => Notification(method~, params= params)
    }
  } else if obj.get("result") is Some(result) {
    Response(id= id.unwrap_or(Number(id= 0)), result= result)
  } else if obj.get("error") is Some(error) {
    Error(
      id= id.unwrap_or(Number(id= 0)),
      error= @json.from_json(error),
    )
  } else {
    raise decode_error(
      path,
      "JSONRPCMessage: missing method, result or error",
    )
  }
}

/// Parse one wire frame.
pub fn parse_message(json : Json) -> JSONRPCMessage raise @json.JsonDecodeError {
  @json.from_json(json)
}

/// Progress reported for an in-flight request.
pub(all) struct ProgressNotificationParams {
  progress_token : String
  progress : Double
  message : String?
  total : Double?
} derive(Debug, Eq)

pub impl ToJson for ProgressNotificationParams with to_json(
  self : ProgressNotificationParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "progressToken", self.progress_token)
  put_opt_double(obj, "progress", self.progress)
  put_opt_str(obj, "message", self.message)
  if self.total is Some(t) {
    put_opt_double(obj, "total", t)
  }
  obj.to_json()
}

pub impl FromJson for ProgressNotificationParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> ProgressNotificationParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ProgressNotificationParams")
  {
    progress_token: req_str(obj, path, "ProgressNotificationParams", "progressToken"),
    progress: opt_double(obj, path, "progress").unwrap_or(0),
    message: opt_str(obj, path, "message"),
    total: opt_double(obj, path, "total"),
  }
}

/// A cancelled request, sent by the side that issued it.
pub(all) struct CancelledNotificationParams {
  request_id : RequestId
  reason : String?
} derive(Debug, Eq)

pub impl ToJson for CancelledNotificationParams with to_json(
  self : CancelledNotificationParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_opt_json(obj, "requestId", Some(RequestId::to_json(self.request_id)))
  put_opt_str(obj, "reason", self.reason)
  obj.to_json()
}

pub impl FromJson for CancelledNotificationParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> CancelledNotificationParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "CancelledNotificationParams")
  {
    request_id: @json.from_json(obj.get("requestId").unwrap_or(Json::null())),
    reason: opt_str(obj, path, "reason"),
  }
}

/// A log entry streamed by the server.
pub(all) struct LoggingMessageNotificationParams {
  level : LoggingLevel
  logger : String?
  data : Json
} derive(Debug, Eq)

pub impl ToJson for LoggingMessageNotificationParams with to_json(
  self : LoggingMessageNotificationParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "level", self.level.to_wire())
  put_opt_str(obj, "logger", self.logger)
  put_opt_json(obj, "data", Some(self.data))
  obj.to_json()
}

pub impl FromJson for LoggingMessageNotificationParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> LoggingMessageNotificationParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "LoggingMessageNotificationParams")
  let level = match logging_level_from_wire(req_str(
    obj,
    path,
    "LoggingMessageNotificationParams",
    "level",
  )) {
    Some(level) => level
    None =>
      raise decode_error(path, "LoggingMessageNotificationParams: invalid level")
  }
  {
    level,
    logger: opt_str(obj, path, "logger"),
    data: obj.get("data").unwrap_or(Json::null()),
  }
}

/// A notification frame the server can send to a client.
pub(all) enum ServerNotification {
  Cancelled(CancelledNotificationParams)
  Progress(ProgressNotificationParams)
  Message(LoggingMessageNotificationParams)
  ResourceUpdated(uri~ : String)
  ResourceListChanged
  ToolListChanged
  PromptListChanged
  Initialized
  RootsListChanged
} derive(Debug, Eq)

pub impl ToJson for ServerNotification with to_json(
  self : ServerNotification,
) -> Json {
  let obj : Map[String, Json] = {}
  match self {
    Cancelled(params) => {
      put_str(obj, "method", notification_cancelled)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    Progress(params) => {
      put_str(obj, "method", notification_progress)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    Message(params) => {
      put_str(obj, "method", notification_message)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    ResourceUpdated(uri~) => {
      put_str(obj, "method", notification_resource_updated)
      put_opt_map(obj, "params", Some({ "uri": Json::string(uri) }))
    }
    ResourceListChanged => put_str(obj, "method", notification_resource_list_changed)
    ToolListChanged => put_str(obj, "method", notification_tool_list_changed)
    PromptListChanged => put_str(obj, "method", notification_prompt_list_changed)
    Initialized => put_str(obj, "method", notification_initialized)
    RootsListChanged =>
      put_str(obj, "method", notification_roots_list_changed)
  }
  put_str(obj, "jsonrpc", "2.0")
  obj.to_json()
}

/// A typed request a client can send to a server.
pub(all) enum ClientRequest {
  Initialize(InitializeRequestParams)
  Ping(meta~ : Map[String, Json]?)
  ListTools(PaginatedRequestParams)
  CallTool(CallToolRequestParams)
  ListResources(PaginatedRequestParams)
  ReadResource(ReadResourceRequestParams)
  Subscribe(SubscribeRequestParams)
  Unsubscribe(SubscribeRequestParams)
  ListPrompts(PaginatedRequestParams)
  GetPrompt(GetPromptRequestParams)
  Complete(CompleteRequestParams)
  SetLevel(SetLevelRequestParams)
  InputResponse(InputResponseRequestParams)
} derive(Debug, Eq)

/// A typed request a server can send to a client.
pub(all) enum ServerRequest {
  Ping(meta~ : Map[String, Json]?)
  CreateMessage(CreateMessageRequestParams)
  Elicit(ElicitRequestParams)
  ListRoots(meta~ : Map[String, Json]?)
} derive(Debug, Eq)

/// Wrap a client request into a wire frame.
pub fn client_request_frame(id : RequestId, request : ClientRequest) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "jsonrpc", "2.0")
  put_opt_json(obj, "id", Some(RequestId::to_json(id)))
  match request {
    Initialize(params) => {
      put_str(obj, "method", method_initialize)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    Ping(meta~) => {
      put_str(obj, "method", method_ping)
      if meta is Some(m) {
        put_opt_map(obj, "params", Some({ "_meta": m.to_json() }))
      }
    }
    ListTools(params) => {
      put_str(obj, "method", method_tools_list)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    CallTool(params) => {
      put_str(obj, "method", method_tools_call)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    ListResources(params) => {
      put_str(obj, "method", method_resources_list)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    ReadResource(params) => {
      put_str(obj, "method", method_resources_read)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    Subscribe(params) => {
      put_str(obj, "method", method_resources_subscribe)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    Unsubscribe(params) => {
      put_str(obj, "method", method_resources_unsubscribe)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    ListPrompts(params) => {
      put_str(obj, "method", method_prompts_list)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    GetPrompt(params) => {
      put_str(obj, "method", method_prompts_get)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    Complete(params) => {
      put_str(obj, "method", method_completion_complete)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    SetLevel(params) => {
      put_str(obj, "method", method_logging_set_level)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    InputResponse(params) => {
      put_str(obj, "method", method_input_response)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
  }
  obj.to_json()
}

/// Wrap a server request into a wire frame.
pub fn server_request_frame(id : RequestId, request : ServerRequest) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "jsonrpc", "2.0")
  put_opt_json(obj, "id", Some(RequestId::to_json(id)))
  match request {
    Ping(meta~) => {
      put_str(obj, "method", method_ping)
      if meta is Some(m) {
        put_opt_map(obj, "params", Some({ "_meta": m.to_json() }))
      }
    }
    CreateMessage(params) => {
      put_str(obj, "method", method_sampling_create_message)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    Elicit(params) => {
      put_str(obj, "method", method_elicitation_create)
      put_opt_json(obj, "params", Some(params.to_json()))
    }
    ListRoots(meta~) => {
      put_str(obj, "method", method_roots_list)
      if meta is Some(m) {
        put_opt_map(obj, "params", Some({ "_meta": m.to_json() }))
      }
    }
  }
  obj.to_json()
}

pub impl FromJson for ClientRequest with from_json(
  json : Json,
  path : @json.JsonPath,
) -> ClientRequest raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ClientRequest frame")
  let method = req_str(obj, path, "ClientRequest", "method")
  let params = obj.get("params")
  fn p() -> Json {
    params.unwrap_or(Json::null())
  }

  fn pmeta() -> Map[String, Json]? {
    match obj.get("params") {
      Some(Object(params_obj)) =>
        match params_obj.get("_meta") {
          Some(Object(meta)) => Some(meta)
          _ => None
        }
      _ => None
    }
  }

  match method {
    "initialize" => Initialize(@json.from_json(p()))
    "ping" => Ping(meta= pmeta())
    "tools/list" => ListTools(@json.from_json(p()))
    "tools/call" => CallTool(@json.from_json(p()))
    "resources/list" => ListResources(@json.from_json(p()))
    "resources/read" => ReadResource(@json.from_json(p()))
    "resources/subscribe" => Subscribe(@json.from_json(p()))
    "resources/unsubscribe" => Unsubscribe(@json.from_json(p()))
    "prompts/list" => ListPrompts(@json.from_json(p()))
    "prompts/get" => GetPrompt(@json.from_json(p()))
    "completion/complete" => Complete(@json.from_json(p()))
    "logging/setLevel" => SetLevel(@json.from_json(p()))
    "input/response" => InputResponse(@json.from_json(p()))
    other => raise decode_error(path, "ClientRequest: unknown method \{other}")
  }
}

/// Decode a request frame into a typed `ClientRequest`.
pub fn parse_client_request(
  frame : Json,
) -> ClientRequest raise @json.JsonDecodeError {
  @json.from_json(frame)
}

pub impl FromJson for ServerRequest with from_json(
  json : Json,
  path : @json.JsonPath,
) -> ServerRequest raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ServerRequest frame")
  let method = req_str(obj, path, "ServerRequest", "method")
  let params = obj.get("params")
  fn p() -> Json {
    params.unwrap_or(Json::null())
  }

  fn pmeta() -> Map[String, Json]? {
    match obj.get("params") {
      Some(Object(params_obj)) =>
        match params_obj.get("_meta") {
          Some(Object(meta)) => Some(meta)
          _ => None
        }
      _ => None
    }
  }

  match method {
    "ping" => Ping(meta= pmeta())
    "sampling/createMessage" => CreateMessage(@json.from_json(p()))
    "elicitation/create" => Elicit(@json.from_json(p()))
    "elicitation/createForm" => Elicit(@json.from_json(p()))
    "roots/list" => ListRoots(meta= pmeta())
    other => raise decode_error(path, "ServerRequest: unknown method \{other}")
  }
}

/// Decode a request frame into a typed `ServerRequest`.
pub fn parse_server_request(
  frame : Json,
) -> ServerRequest raise @json.JsonDecodeError {
  @json.from_json(frame)
}

/// The method name a typed request will be sent under.
pub fn ClientRequest::method(self : ClientRequest) -> String {
  match self {
    Initialize(_) => method_initialize
    Ping(_) => method_ping
    ListTools(_) => method_tools_list
    CallTool(_) => method_tools_call
    ListResources(_) => method_resources_list
    ReadResource(_) => method_resources_read
    Subscribe(_) => method_resources_subscribe
    Unsubscribe(_) => method_resources_unsubscribe
    ListPrompts(_) => method_prompts_list
    GetPrompt(_) => method_prompts_get
    Complete(_) => method_completion_complete
    SetLevel(_) => method_logging_set_level
    InputResponse(_) => method_input_response
  }
}
