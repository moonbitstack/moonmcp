/// Request parameter models.

/// A prompt reference used for completion.
pub(all) enum Reference {
  PromptReference(name~ : String)
  ResourceTemplateReference(uri~ : String)
} derive(Debug, Eq)

pub impl ToJson for Reference with to_json(self : Reference) -> Json {
  let obj : Map[String, Json] = {}
  match self {
    PromptReference(name~) => {
      put_str(obj, "type", "ref/prompt")
      put_str(obj, "name", name)
    }
    ResourceTemplateReference(uri~) => {
      put_str(obj, "type", "ref/resource")
      put_str(obj, "uri", uri)
    }
  }
  obj.to_json()
}

pub impl FromJson for Reference with from_json(
  json : Json,
  path : @json.JsonPath,
) -> Reference raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "Reference")
  match req_str(obj, path, "Reference", "type") {
    "ref/prompt" =>
      PromptReference(name=req_str(obj, path, "Reference", "name"))
    "ref/resource" =>
      ResourceTemplateReference(uri=req_str(obj, path, "Reference", "uri"))
    ref_type => raise decode_error(path, "Reference: unknown type \{ref_type}")
  }
}

pub(all) struct CompletionArgument {
  name : String
  value : String
} derive(Debug, Eq)

pub impl ToJson for CompletionArgument with to_json(
  self : CompletionArgument,
) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "name", self.name)
  put_str(obj, "value", self.value)
  obj.to_json()
}

pub impl FromJson for CompletionArgument with from_json(
  json : Json,
  path : @json.JsonPath,
) -> CompletionArgument raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "CompletionArgument")
  {
    name: req_str(obj, path, "CompletionArgument", "name"),
    value: req_str(obj, path, "CompletionArgument", "value"),
  }
}

pub(all) struct CompletionContext {
  reference : Reference
  argument : CompletionArgument
} derive(Debug, Eq)

pub impl ToJson for CompletionContext with to_json(
  self : CompletionContext,
) -> Json {
  let obj : Map[String, Json] = {}
  put_opt_json(obj, "ref", Some(Reference::to_json(self.reference)))
  put_opt_json(obj, "argument", Some(self.argument.to_json()))
  obj.to_json()
}

pub impl FromJson for CompletionContext with from_json(
  json : Json,
  path : @json.JsonPath,
) -> CompletionContext raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "CompletionContext")
  {
    reference: @json.from_json(obj.get("ref").unwrap_or(Json::null())),
    argument: @json.from_json(obj.get("argument").unwrap_or(Json::null())),
  }
}

/// Parameters common to every request; `_meta.progressToken` drives progress.
pub(all) struct RequestParamsMeta {
  meta : Map[String, Json]?
} derive(Debug, Eq)

pub fn RequestParamsMeta::progress_token(
  self : RequestParamsMeta,
) -> String? {
  progress_token_of(self.meta)
}

pub impl ToJson for RequestParamsMeta with to_json(
  self : RequestParamsMeta,
) -> Json {
  let obj : Map[String, Json] = {}
  put_opt_map(obj, "_meta", self.meta)
  obj.to_json()
}

pub impl FromJson for RequestParamsMeta with from_json(
  json : Json,
  path : @json.JsonPath,
) -> RequestParamsMeta raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "RequestParamsMeta")
  { meta: opt_obj(obj, path, "_meta") }
}

/// `initialize` request parameters.
pub(all) struct InitializeRequestParams {
  protocol_version : String
  capabilities : ClientCapabilities
  client_info : Implementation
  meta : Map[String, Json]?
} derive(Debug, Eq)

pub impl ToJson for InitializeRequestParams with to_json(
  self : InitializeRequestParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "protocolVersion", self.protocol_version)
  put_opt_json(obj, "capabilities", Some(self.capabilities.to_json()))
  put_opt_json(obj, "clientInfo", Some(self.client_info.to_json()))
  put_opt_map(obj, "_meta", self.meta)
  obj.to_json()
}

pub impl FromJson for InitializeRequestParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> InitializeRequestParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "InitializeRequestParams")
  {
    protocol_version: req_str(obj, path, "InitializeRequestParams", "protocolVersion"),
    capabilities: @json.from_json(obj.get("capabilities").unwrap_or(Json::null())),
    client_info: @json.from_json(obj.get("clientInfo").unwrap_or(Json::null())),
    meta: opt_obj(obj, path, "_meta"),
  }
}

/// List requests with cursor-based pagination.
pub(all) struct PaginatedRequestParams {
  cursor : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

pub fn PaginatedRequestParams::progress_token(
  self : PaginatedRequestParams,
) -> String? {
  progress_token_of(self.meta)
}

pub impl ToJson for PaginatedRequestParams with to_json(
  self : PaginatedRequestParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_opt_str(obj, "cursor", self.cursor)
  put_opt_map(obj, "_meta", self.meta)
  obj.to_json()
}

pub impl FromJson for PaginatedRequestParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> PaginatedRequestParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "PaginatedRequestParams")
  {
    cursor: opt_str(obj, path, "cursor"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

/// `tools/call` request parameters.
pub(all) struct CallToolRequestParams {
  name : String
  arguments : Map[String, Json]?
  meta : Map[String, Json]?
} derive(Debug, Eq)

pub fn CallToolRequestParams::progress_token(
  self : CallToolRequestParams,
) -> String? {
  progress_token_of(self.meta)
}

pub impl ToJson for CallToolRequestParams with to_json(
  self : CallToolRequestParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "name", self.name)
  put_opt_map(obj, "arguments", self.arguments)
  put_opt_map(obj, "_meta", self.meta)
  obj.to_json()
}

pub impl FromJson for CallToolRequestParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> CallToolRequestParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "CallToolRequestParams")
  {
    name: req_str(obj, path, "CallToolRequestParams", "name"),
    arguments: opt_obj(obj, path, "arguments"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

/// `resources/read` request parameters.
pub(all) struct ReadResourceRequestParams {
  uri : String
  meta : Map[String, Json]?
} derive(Debug, Eq)

pub impl ToJson for ReadResourceRequestParams with to_json(
  self : ReadResourceRequestParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "uri", self.uri)
  put_opt_map(obj, "_meta", self.meta)
  obj.to_json()
}

pub impl FromJson for ReadResourceRequestParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> ReadResourceRequestParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ReadResourceRequestParams")
  {
    uri: req_str(obj, path, "ReadResourceRequestParams", "uri"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

/// `resources/subscribe` request parameters.
pub(all) struct SubscribeRequestParams {
  uri : String
  meta : Map[String, Json]?
} derive(Debug, Eq)

pub impl ToJson for SubscribeRequestParams with to_json(
  self : SubscribeRequestParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "uri", self.uri)
  put_opt_map(obj, "_meta", self.meta)
  obj.to_json()
}

pub impl FromJson for SubscribeRequestParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> SubscribeRequestParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "SubscribeRequestParams")
  {
    uri: req_str(obj, path, "SubscribeRequestParams", "uri"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

/// `prompts/get` request parameters.
pub(all) struct GetPromptRequestParams {
  name : String
  arguments : Map[String, Json]?
  meta : Map[String, Json]?
} derive(Debug, Eq)

pub impl ToJson for GetPromptRequestParams with to_json(
  self : GetPromptRequestParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "name", self.name)
  put_opt_map(obj, "arguments", self.arguments)
  put_opt_map(obj, "_meta", self.meta)
  obj.to_json()
}

pub impl FromJson for GetPromptRequestParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> GetPromptRequestParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "GetPromptRequestParams")
  {
    name: req_str(obj, path, "GetPromptRequestParams", "name"),
    arguments: opt_obj(obj, path, "arguments"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

/// `completion/complete` request parameters.
pub(all) struct CompleteRequestParams {
  context : CompletionContext
  meta : Map[String, Json]?
} derive(Debug, Eq)

pub impl ToJson for CompleteRequestParams with to_json(
  self : CompleteRequestParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_opt_json(obj, "context", Some(self.context.to_json()))
  put_opt_map(obj, "_meta", self.meta)
  obj.to_json()
}

pub impl FromJson for CompleteRequestParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> CompleteRequestParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "CompleteRequestParams")
  {
    context: @json.from_json(obj.get("context").unwrap_or(Json::null())),
    meta: opt_obj(obj, path, "_meta"),
  }
}

/// `logging/setLevel` request parameters.
pub(all) struct SetLevelRequestParams {
  level : LoggingLevel
  meta : Map[String, Json]?
} derive(Debug, Eq)

pub impl ToJson for SetLevelRequestParams with to_json(
  self : SetLevelRequestParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "level", self.level.to_wire())
  put_opt_map(obj, "_meta", self.meta)
  obj.to_json()
}

pub impl FromJson for SetLevelRequestParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> SetLevelRequestParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "SetLevelRequestParams")
  let level = match logging_level_from_wire(req_str(
    obj,
    path,
    "SetLevelRequestParams",
    "level",
  )) {
    Some(level) => level
    None => raise decode_error(path, "SetLevelRequestParams: invalid level")
  }
  { level, meta: opt_obj(obj, path, "_meta") }
}

/// `sampling/createMessage` request parameters.
pub(all) struct CreateMessageRequestParams {
  messages : Array[SamplingMessage]
  system_message : String?
  include_context : String?
  max_tokens : Int
  temperature : Double?
  stop_sequences : Array[String]?
  model_preferences : ModelPreferences?
  meta : Map[String, Json]?
} derive(Debug, Eq)

pub impl ToJson for CreateMessageRequestParams with to_json(
  self : CreateMessageRequestParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_opt_array(
    obj,
    "messages",
    Some(self.messages.map(SamplingMessage::to_json)),
  )
  put_opt_str(obj, "systemMessage", self.system_message)
  put_opt_str(obj, "includeContext", self.include_context)
  put_opt_int(obj, "maxTokens", Some(self.max_tokens))
  if self.temperature is Some(t) {
    put_opt_double(obj, "temperature", t)
  }
  put_opt_str_array(obj, "stopSequences", self.stop_sequences)
  put_opt_json(
    obj,
    "modelPreferences",
    self.model_preferences.map(ModelPreferences::to_json),
  )
  put_opt_map(obj, "_meta", self.meta)
  obj.to_json()
}

pub impl FromJson for CreateMessageRequestParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> CreateMessageRequestParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "CreateMessageRequestParams")
  {
    messages: req_array(obj, path, "CreateMessageRequestParams", "messages")
      .map(fn(value) { @json.from_json(value) }),
    system_message: opt_str(obj, path, "systemMessage"),
    include_context: opt_str(obj, path, "includeContext"),
    max_tokens: opt_int(obj, path, "maxTokens").unwrap_or(0),
    temperature: opt_double(obj, path, "temperature"),
    stop_sequences: opt_str_array(obj, path, "stopSequences"),
    model_preferences: match obj.get("modelPreferences") {
      Some(value) => Some(@json.from_json(value))
      None => None
    },
    meta: opt_obj(obj, path, "_meta"),
  }
}

/// `elicitation/create` request parameters, covering both the form- and
/// URL-based variants.
pub(all) struct ElicitRequestParams {
  message : String
  requested_schema : Map[String, Json]?
  url : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

pub impl ToJson for ElicitRequestParams with to_json(
  self : ElicitRequestParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "message", self.message)
  put_opt_map(obj, "requestedSchema", self.requested_schema)
  put_opt_str(obj, "url", self.url)
  put_opt_map(obj, "_meta", self.meta)
  obj.to_json()
}

pub impl FromJson for ElicitRequestParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> ElicitRequestParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ElicitRequestParams")
  {
    message: req_str(obj, path, "ElicitRequestParams", "message"),
    requested_schema: opt_obj(obj, path, "requestedSchema"),
    url: opt_str(obj, path, "url"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

/// A client answer to a guard-channel input request (SEP-2322).
pub(all) struct InputResponse {
  request_id : String
  action : String
  content : Map[String, Json]?
} derive(Debug, Eq)

pub impl ToJson for InputResponse with to_json(self : InputResponse) -> Json {
  let obj : Map[String, Json] = {}
  put_str(obj, "requestId", self.request_id)
  put_str(obj, "action", self.action)
  put_opt_map(obj, "content", self.content)
  obj.to_json()
}

pub impl FromJson for InputResponse with from_json(
  json : Json,
  path : @json.JsonPath,
) -> InputResponse raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "InputResponse")
  {
    request_id: req_str(obj, path, "InputResponse", "requestId"),
    action: req_str(obj, path, "InputResponse", "action"),
    content: opt_obj(obj, path, "content"),
  }
}

/// `input/response` request parameters: answers keyed by request id.
pub(all) struct InputResponseRequestParams {
  input_responses : Map[String, Json]
  request_state : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

pub impl ToJson for InputResponseRequestParams with to_json(
  self : InputResponseRequestParams,
) -> Json {
  let obj : Map[String, Json] = {}
  put_opt_map(obj, "inputResponses", Some(self.input_responses))
  put_opt_str(obj, "requestState", self.request_state)
  put_opt_map(obj, "_meta", self.meta)
  obj.to_json()
}

pub impl FromJson for InputResponseRequestParams with from_json(
  json : Json,
  path : @json.JsonPath,
) -> InputResponseRequestParams raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "InputResponseRequestParams")
  {
    input_responses: opt_obj(obj, path, "inputResponses").unwrap_or({}),
    request_state: opt_str(obj, path, "requestState"),
    meta: opt_obj(obj, path, "_meta"),
  }
}
