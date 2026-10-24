/// Result payloads returned by requests.

///|
/// `initialize` result: capabilities and server description.
pub(all) struct InitializeResult {
  protocol_version : String
  capabilities : ServerCapabilities
  server_info : Implementation
  instructions : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for InitializeResult with fn to_json(self : InitializeResult) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "protocolVersion", self.protocol_version)
  put_opt_json(obj, "capabilities", Some(self.capabilities.to_json()))
  put_opt_json(obj, "serverInfo", Some(self.server_info.to_json()))
  put_opt_str(obj, "instructions", self.instructions)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for InitializeResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> InitializeResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "InitializeResult")
  {
    protocol_version: req_str(obj, path, "InitializeResult", "protocolVersion"),
    capabilities: @json.from_json(
      obj.get("capabilities").unwrap_or(Json::null()),
    ),
    server_info: @json.from_json(obj.get("serverInfo").unwrap_or(Json::null())),
    instructions: opt_str(obj, path, "instructions"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// The result of a `tools/list` call.
pub(all) struct ListToolsResult {
  tools : Array[Tool]
  next_cursor : String?
  cache_control : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for ListToolsResult with fn to_json(self : ListToolsResult) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_array(obj, "tools", Some(self.tools.map(Tool::to_json)))
  put_opt_str(obj, "nextCursor", self.next_cursor)
  put_opt_str(obj, "cacheControl", self.cache_control)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for ListToolsResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ListToolsResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ListToolsResult")
  {
    tools: req_array(obj, path, "ListToolsResult", "tools").map(value => {
      @json.from_json(value)
    }),
    next_cursor: opt_str(obj, path, "nextCursor"),
    cache_control: opt_str(obj, path, "cacheControl"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// The result of a `tools/call` call.
pub(all) struct CallToolResult {
  content : Array[ContentBlock]
  structured_content : Map[String, Json]?
  is_error : Bool
  cache_control : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub fn CallToolResult::new(content : Array[ContentBlock]) -> CallToolResult {
  {
    content,
    structured_content: None,
    is_error: false,
    cache_control: None,
    meta: None,
  }
}

///|
pub fn CallToolResult::error(message : String) -> CallToolResult {
  {
    content: [text_block(message)],
    structured_content: None,
    is_error: true,
    cache_control: None,
    meta: None,
  }
}

///|
pub impl ToJson for CallToolResult with fn to_json(self : CallToolResult) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_array(obj, "content", Some(self.content.map(ContentBlock::to_json)))
  put_opt_map(obj, "structuredContent", self.structured_content)
  put_opt_bool(obj, "isError", Some(self.is_error))
  put_opt_str(obj, "cacheControl", self.cache_control)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for CallToolResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> CallToolResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "CallToolResult")
  {
    content: opt_array(obj, path, "content")
    .unwrap_or([])
    .map(value => @json.from_json(value)),
    structured_content: opt_obj(obj, path, "structuredContent"),
    is_error: opt_bool(obj, path, "isError").unwrap_or(false),
    cache_control: opt_str(obj, path, "cacheControl"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// The result of a `prompts/list` call.
pub(all) struct ListPromptsResult {
  prompts : Array[Prompt]
  next_cursor : String?
  cache_control : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for ListPromptsResult with fn to_json(self : ListPromptsResult) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_array(obj, "prompts", Some(self.prompts.map(Prompt::to_json)))
  put_opt_str(obj, "nextCursor", self.next_cursor)
  put_opt_str(obj, "cacheControl", self.cache_control)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for ListPromptsResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ListPromptsResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ListPromptsResult")
  {
    prompts: req_array(obj, path, "ListPromptsResult", "prompts").map(value => {
      @json.from_json(value)
    }),
    next_cursor: opt_str(obj, path, "nextCursor"),
    cache_control: opt_str(obj, path, "cacheControl"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// One message in a rendered prompt.
pub(all) struct PromptMessage {
  role : Role
  content : ContentBlock
} derive(Debug, Eq)

///|
pub impl ToJson for PromptMessage with fn to_json(self : PromptMessage) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "role", self.role.to_wire())
  put_opt_json(obj, "content", Some(ContentBlock::to_json(self.content)))
  Json(obj)
}

///|
pub impl FromJson for PromptMessage with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> PromptMessage raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "PromptMessage")
  let role = match role_from_wire(req_str(obj, path, "PromptMessage", "role")) {
    Some(r) => r
    None => raise decode_error(path, "PromptMessage: invalid role")
  }
  {
    role,
    content: @json.from_json(obj.get("content").unwrap_or(Json::null())),
  }
}

///|
/// The result of a `prompts/get` call.
pub(all) struct GetPromptResult {
  description : String?
  messages : Array[PromptMessage]
  cache_control : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for GetPromptResult with fn to_json(self : GetPromptResult) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_str(obj, "description", self.description)
  put_opt_array(
    obj,
    "messages",
    Some(self.messages.map(PromptMessage::to_json)),
  )
  put_opt_str(obj, "cacheControl", self.cache_control)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for GetPromptResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> GetPromptResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "GetPromptResult")
  {
    description: opt_str(obj, path, "description"),
    messages: req_array(obj, path, "GetPromptResult", "messages").map(value => {
      @json.from_json(value)
    }),
    cache_control: opt_str(obj, path, "cacheControl"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// The result of a `resources/list` call.
pub(all) struct ListResourcesResult {
  resources : Array[Resource]
  next_cursor : String?
  cache_control : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for ListResourcesResult with fn to_json(
  self : ListResourcesResult,
) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_array(obj, "resources", Some(self.resources.map(Resource::to_json)))
  put_opt_str(obj, "nextCursor", self.next_cursor)
  put_opt_str(obj, "cacheControl", self.cache_control)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for ListResourcesResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ListResourcesResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ListResourcesResult")
  {
    resources: req_array(obj, path, "ListResourcesResult", "resources").map(value => {
      @json.from_json(value)
    }),
    next_cursor: opt_str(obj, path, "nextCursor"),
    cache_control: opt_str(obj, path, "cacheControl"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// The result of a `resources/read` call.
pub(all) struct ReadResourceResult {
  contents : Array[ResourceContents]
  cache_control : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for ReadResourceResult with fn to_json(
  self : ReadResourceResult,
) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_array(
    obj,
    "contents",
    Some(self.contents.map(ResourceContents::to_json)),
  )
  put_opt_str(obj, "cacheControl", self.cache_control)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for ReadResourceResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ReadResourceResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ReadResourceResult")
  {
    contents: req_array(obj, path, "ReadResourceResult", "contents").map(value => {
      @json.from_json(value)
    }),
    cache_control: opt_str(obj, path, "cacheControl"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// The result of a `resources/templates/list` call.
pub(all) struct ListResourceTemplatesResult {
  resource_templates : Array[ResourceTemplate]
  next_cursor : String?
  cache_control : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for ListResourceTemplatesResult with fn to_json(
  self : ListResourceTemplatesResult,
) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_array(
    obj,
    "resourceTemplates",
    Some(self.resource_templates.map(ResourceTemplate::to_json)),
  )
  put_opt_str(obj, "nextCursor", self.next_cursor)
  put_opt_str(obj, "cacheControl", self.cache_control)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for ListResourceTemplatesResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ListResourceTemplatesResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ListResourceTemplatesResult")
  {
    resource_templates: req_array(
      obj, path, "ListResourceTemplatesResult", "resourceTemplates",
    ).map(value => @json.from_json(value)),
    next_cursor: opt_str(obj, path, "nextCursor"),
    cache_control: opt_str(obj, path, "cacheControl"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// Completion values returned by `completion/complete`.
pub(all) struct Completion {
  values : Array[String]
  total : Int32?
  has_more : Bool?
} derive(Debug, Eq)

///|
pub impl ToJson for Completion with fn to_json(self : Completion) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_array(obj, "values", Some(self.values.map(Json::string)))
  put_opt_int(obj, "total", self.total)
  put_opt_bool(obj, "hasMore", self.has_more)
  Json(obj)
}

///|
pub impl FromJson for Completion with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Completion raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "Completion")
  {
    values: opt_str_array(obj, path, "values").unwrap_or([]),
    total: opt_int(obj, path, "total"),
    has_more: opt_bool(obj, path, "hasMore"),
  }
}

///|
/// The result of a `completion/complete` call.
pub(all) struct CompleteResult {
  completion : Completion
  cache_control : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for CompleteResult with fn to_json(self : CompleteResult) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_json(obj, "completion", Some(self.completion.to_json()))
  put_opt_str(obj, "cacheControl", self.cache_control)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for CompleteResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> CompleteResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "CompleteResult")
  {
    completion: @json.from_json(obj.get("completion").unwrap_or(Json::null())),
    cache_control: opt_str(obj, path, "cacheControl"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// A bare result with no payload.
pub(all) struct EmptyResult {
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for EmptyResult with fn to_json(self : EmptyResult) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for EmptyResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> EmptyResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "EmptyResult")
  { meta: opt_obj(obj, path, "_meta"), }
}

///|
/// The result of a `sampling/createMessage` call.
pub(all) struct CreateMessageResult {
  model : String
  stop_reason : String?
  role : Role
  content : ContentBlock
  cache_control : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for CreateMessageResult with fn to_json(
  self : CreateMessageResult,
) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "model", self.model)
  put_opt_str(obj, "stopReason", self.stop_reason)
  put_str(obj, "role", self.role.to_wire())
  put_opt_json(obj, "content", Some(ContentBlock::to_json(self.content)))
  put_opt_str(obj, "cacheControl", self.cache_control)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for CreateMessageResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> CreateMessageResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "CreateMessageResult")
  let role = match
    role_from_wire(req_str(obj, path, "CreateMessageResult", "role")) {
    Some(r) => r
    None => raise decode_error(path, "CreateMessageResult: invalid role")
  }
  {
    model: req_str(obj, path, "CreateMessageResult", "model"),
    stop_reason: opt_str(obj, path, "stopReason"),
    role,
    content: @json.from_json(obj.get("content").unwrap_or(Json::null())),
    cache_control: opt_str(obj, path, "cacheControl"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// The result of an elicitation round trip.
pub(all) struct ElicitResult {
  action : String
  content : Map[String, Json]?
  cache_control : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub fn ElicitResult::accept(content : Map[String, Json]) -> ElicitResult {
  { action: "accept", content: Some(content), cache_control: None, meta: None, }
}

///|
pub fn ElicitResult::decline() -> ElicitResult {
  { action: "decline", content: None, cache_control: None, meta: None, }
}

///|
pub fn ElicitResult::cancel() -> ElicitResult {
  { action: "cancel", content: None, cache_control: None, meta: None, }
}

///|
pub impl ToJson for ElicitResult with fn to_json(self : ElicitResult) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "action", self.action)
  put_opt_map(obj, "content", self.content)
  put_opt_str(obj, "cacheControl", self.cache_control)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for ElicitResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ElicitResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ElicitResult")
  {
    action: req_str(obj, path, "ElicitResult", "action"),
    content: opt_obj(obj, path, "content"),
    cache_control: opt_str(obj, path, "cacheControl"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// The result of a `roots/list` call.
pub(all) struct ListRootsResult {
  roots : Array[Root]
  cache_control : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for ListRootsResult with fn to_json(self : ListRootsResult) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_array(obj, "roots", Some(self.roots.map(Root::to_json)))
  put_opt_str(obj, "cacheControl", self.cache_control)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for ListRootsResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ListRootsResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ListRootsResult")
  {
    roots: req_array(obj, path, "ListRootsResult", "roots").map(value => {
      @json.from_json(value)
    }),
    cache_control: opt_str(obj, path, "cacheControl"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// One guard-channel request a client must answer (SEP-2322).
pub(all) struct InputRequest {
  id : String
  request : Json
} derive(Debug, Eq)

///|
pub impl ToJson for InputRequest with fn to_json(self : InputRequest) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "id", self.id)
  put_opt_json(obj, "request", Some(self.request))
  Json(obj)
}

///|
pub impl FromJson for InputRequest with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> InputRequest raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "InputRequest")
  {
    id: req_str(obj, path, "InputRequest", "id"),
    request: obj.get("request").unwrap_or(Json::null()),
  }
}

///|
/// Tells the client to answer the carried requests and re-issue the call.
pub(all) struct InputRequiredResult {
  input_requests : Array[InputRequest]
  request_state : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for InputRequiredResult with fn to_json(
  self : InputRequiredResult,
) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_array(
    obj,
    "inputRequests",
    Some(self.input_requests.map(InputRequest::to_json)),
  )
  put_opt_str(obj, "requestState", self.request_state)
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for InputRequiredResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> InputRequiredResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "InputRequiredResult")
  {
    input_requests: req_array(obj, path, "InputRequiredResult", "inputRequests").map(value => {
        @json.from_json(value)
      },
    ),
    request_state: opt_str(obj, path, "requestState"),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// A task handle minted for task-augmented execution (SEP-2663).
pub(all) struct CreateTaskResult {
  task : Json
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for CreateTaskResult with fn to_json(self : CreateTaskResult) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_json(obj, "task", Some(self.task))
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for CreateTaskResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> CreateTaskResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "CreateTaskResult")
  {
    task: obj.get("task").unwrap_or(Json::null()),
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// A discovery reply wrapping any core result, tagged with its type.
pub(all) struct DiscoverResult {
  result_type : String
  result : Json
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for DiscoverResult with fn to_json(self : DiscoverResult) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "resultType", self.result_type)
  match self.result {
    Object(result_obj) =>
      for key, value in result_obj {
        obj[key] = value
      }
    _ => put_opt_json(obj, "result", Some(self.result))
  }
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for DiscoverResult with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> DiscoverResult raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "DiscoverResult")
  let result_type = req_str(obj, path, "DiscoverResult", "resultType")
  let result : Map[String, Json] = Map([])
  for key, value in obj {
    if key != "resultType" && key != "_meta" {
      result[key] = value
    }
  }
  { result_type, result: Json(result), meta: opt_obj(obj, path, "_meta"), }
}

///|
pub extend CallToolResult with @json.FromJson::{from_json}

///|
pub extend CallToolResult with Debug::{to_repr}

///|
pub extend CallToolResult with Eq::{not_equal, equal}

///|
pub extend CallToolResult with ToJson::{to_json}

///|
pub extend CompleteResult with @json.FromJson::{from_json}

///|
pub extend CompleteResult with Debug::{to_repr}

///|
pub extend CompleteResult with Eq::{not_equal, equal}

///|
pub extend CompleteResult with ToJson::{to_json}

///|
pub extend Completion with @json.FromJson::{from_json}

///|
pub extend Completion with Debug::{to_repr}

///|
pub extend Completion with Eq::{not_equal, equal}

///|
pub extend Completion with ToJson::{to_json}

///|
pub extend CreateMessageResult with @json.FromJson::{from_json}

///|
pub extend CreateMessageResult with Debug::{to_repr}

///|
pub extend CreateMessageResult with Eq::{not_equal, equal}

///|
pub extend CreateMessageResult with ToJson::{to_json}

///|
pub extend CreateTaskResult with @json.FromJson::{from_json}

///|
pub extend CreateTaskResult with Debug::{to_repr}

///|
pub extend CreateTaskResult with Eq::{not_equal, equal}

///|
pub extend CreateTaskResult with ToJson::{to_json}

///|
pub extend DiscoverResult with @json.FromJson::{from_json}

///|
pub extend DiscoverResult with Debug::{to_repr}

///|
pub extend DiscoverResult with Eq::{not_equal, equal}

///|
pub extend DiscoverResult with ToJson::{to_json}

///|
pub extend ElicitResult with @json.FromJson::{from_json}

///|
pub extend ElicitResult with Debug::{to_repr}

///|
pub extend ElicitResult with Eq::{not_equal, equal}

///|
pub extend ElicitResult with ToJson::{to_json}

///|
pub extend EmptyResult with @json.FromJson::{from_json}

///|
pub extend EmptyResult with Debug::{to_repr}

///|
pub extend EmptyResult with Eq::{not_equal, equal}

///|
pub extend EmptyResult with ToJson::{to_json}

///|
pub extend GetPromptResult with @json.FromJson::{from_json}

///|
pub extend GetPromptResult with Debug::{to_repr}

///|
pub extend GetPromptResult with Eq::{not_equal, equal}

///|
pub extend GetPromptResult with ToJson::{to_json}

///|
pub extend InitializeResult with @json.FromJson::{from_json}

///|
pub extend InitializeResult with Debug::{to_repr}

///|
pub extend InitializeResult with Eq::{not_equal, equal}

///|
pub extend InitializeResult with ToJson::{to_json}

///|
pub extend InputRequest with @json.FromJson::{from_json}

///|
pub extend InputRequest with Debug::{to_repr}

///|
pub extend InputRequest with Eq::{not_equal, equal}

///|
pub extend InputRequest with ToJson::{to_json}

///|
pub extend InputRequiredResult with @json.FromJson::{from_json}

///|
pub extend InputRequiredResult with Debug::{to_repr}

///|
pub extend InputRequiredResult with Eq::{not_equal, equal}

///|
pub extend InputRequiredResult with ToJson::{to_json}

///|
pub extend ListPromptsResult with @json.FromJson::{from_json}

///|
pub extend ListPromptsResult with Debug::{to_repr}

///|
pub extend ListPromptsResult with Eq::{not_equal, equal}

///|
pub extend ListPromptsResult with ToJson::{to_json}

///|
pub extend ListResourceTemplatesResult with @json.FromJson::{from_json}

///|
pub extend ListResourceTemplatesResult with Debug::{to_repr}

///|
pub extend ListResourceTemplatesResult with Eq::{not_equal, equal}

///|
pub extend ListResourceTemplatesResult with ToJson::{to_json}

///|
pub extend ListResourcesResult with @json.FromJson::{from_json}

///|
pub extend ListResourcesResult with Debug::{to_repr}

///|
pub extend ListResourcesResult with Eq::{not_equal, equal}

///|
pub extend ListResourcesResult with ToJson::{to_json}

///|
pub extend ListRootsResult with @json.FromJson::{from_json}

///|
pub extend ListRootsResult with Debug::{to_repr}

///|
pub extend ListRootsResult with Eq::{not_equal, equal}

///|
pub extend ListRootsResult with ToJson::{to_json}

///|
pub extend ListToolsResult with @json.FromJson::{from_json}

///|
pub extend ListToolsResult with Debug::{to_repr}

///|
pub extend ListToolsResult with Eq::{not_equal, equal}

///|
pub extend ListToolsResult with ToJson::{to_json}

///|
pub extend PromptMessage with @json.FromJson::{from_json}

///|
pub extend PromptMessage with Debug::{to_repr}

///|
pub extend PromptMessage with Eq::{not_equal, equal}

///|
pub extend PromptMessage with ToJson::{to_json}

///|
pub extend ReadResourceResult with @json.FromJson::{from_json}

///|
pub extend ReadResourceResult with Debug::{to_repr}

///|
pub extend ReadResourceResult with Eq::{not_equal, equal}

///|
pub extend ReadResourceResult with ToJson::{to_json}
