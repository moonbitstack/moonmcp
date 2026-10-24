/// Component and capability models advertised over the wire.

///|
/// The name and version of an MCP implementation.
pub(all) struct Implementation {
  name : String
  title : String?
  version : String
} derive(Debug, Eq)

///|
pub impl ToJson for Implementation with fn to_json(self : Implementation) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "name", self.name)
  put_opt_str(obj, "title", self.title)
  put_str(obj, "version", self.version)
  Json(obj)
}

///|
pub impl FromJson for Implementation with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Implementation raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "Implementation")
  {
    name: req_str(obj, path, "Implementation", "name"),
    title: opt_str(obj, path, "title"),
    version: req_str(obj, path, "Implementation", "version"),
  }
}

///|
/// Tool listings only need list-change notifications.
pub(all) struct ToolCapabilities {
  list_changed : Bool?
} derive(Debug, Eq)

///|
/// Resource capability flags.
pub(all) struct ResourcesCapabilities {
  subscribe : Bool?
  list_changed : Bool?
} derive(Debug, Eq)

///|
/// Prompt listings only need list-change notifications.
pub(all) struct PromptsCapabilities {
  list_changed : Bool?
} derive(Debug, Eq)

///|
/// What a server supports; absent groups mean the feature is off.
pub(all) struct ServerCapabilities {
  experimental : Map[String, Json]?
  logging : Bool?
  completions : Bool?
  prompts : PromptsCapabilities?
  resources : ResourcesCapabilities?
  tools : ToolCapabilities?
  tasks : Bool?
} derive(Debug, Eq)

///|
pub fn ServerCapabilities::new() -> ServerCapabilities {
  {
    experimental: None,
    logging: None,
    completions: None,
    prompts: None,
    resources: None,
    tools: None,
    tasks: None,
  }
}

///|
pub impl ToJson for ServerCapabilities with fn to_json(
  self : ServerCapabilities,
) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_map(obj, "experimental", self.experimental)
  if self.logging is Some(true) {
    put_opt_map(obj, "logging", Some({}))
  }
  if self.completions is Some(true) {
    put_opt_map(obj, "completions", Some({}))
  }
  if self.tasks is Some(true) {
    put_opt_map(obj, "tasks", Some({}))
  }
  if self.prompts is Some(prompts) {
    let prompts_obj : Map[String, Json] = Map([])
    put_opt_bool(prompts_obj, "listChanged", prompts.list_changed)
    put_opt_map(obj, "prompts", Some(prompts_obj))
  }
  if self.resources is Some(resources) {
    let resources_obj : Map[String, Json] = Map([])
    put_opt_bool(resources_obj, "subscribe", resources.subscribe)
    put_opt_bool(resources_obj, "listChanged", resources.list_changed)
    put_opt_map(obj, "resources", Some(resources_obj))
  }
  if self.tools is Some(tools) {
    let tools_obj : Map[String, Json] = Map([])
    put_opt_bool(tools_obj, "listChanged", tools.list_changed)
    put_opt_map(obj, "tools", Some(tools_obj))
  }
  Json(obj)
}

///|
pub impl FromJson for ServerCapabilities with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ServerCapabilities raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ServerCapabilities")
  fn prompts_caps() -> PromptsCapabilities? raise @json.JsonDecodeError {
    match opt_obj(obj, path, "prompts") {
      Some(p) => Some({ list_changed: opt_bool(p, path, "listChanged"), })
      None => None
    }
  }

  fn resources_caps() -> ResourcesCapabilities? raise @json.JsonDecodeError {
    match opt_obj(obj, path, "resources") {
      Some(r) =>
        Some({
          subscribe: opt_bool(r, path, "subscribe"),
          list_changed: opt_bool(r, path, "listChanged"),
        })
      None => None
    }
  }

  fn tools_caps() -> ToolCapabilities? raise @json.JsonDecodeError {
    match opt_obj(obj, path, "tools") {
      Some(t) => Some({ list_changed: opt_bool(t, path, "listChanged"), })
      None => None
    }
  }

  {
    experimental: opt_obj(obj, path, "experimental"),
    logging: opt_obj(obj, path, "logging").map_or(None, fn(_) { Some(true) }),
    completions: opt_obj(obj, path, "completions").map_or(None, fn(_) {
      Some(true)
    }),
    tasks: opt_obj(obj, path, "tasks").map_or(None, fn(_) { Some(true) }),
    prompts: prompts_caps(),
    resources: resources_caps(),
    tools: tools_caps(),
  }
}

///|
/// What a client supports.
pub(all) struct ClientCapabilities {
  experimental : Map[String, Json]?
  roots_list_changed : Bool?
  sampling : Bool?
  elicitation : Bool?
  tasks : Bool?
} derive(Debug, Eq)

///|
pub impl ToJson for ClientCapabilities with fn to_json(
  self : ClientCapabilities,
) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_map(obj, "experimental", self.experimental)
  if self.roots_list_changed is Some(true) {
    put_opt_map(obj, "roots", Some({ "listChanged": Json::boolean(true) }))
  }
  if self.sampling is Some(true) {
    put_opt_map(obj, "sampling", Some({}))
  }
  if self.elicitation is Some(true) {
    put_opt_map(obj, "elicitation", Some({}))
  }
  if self.tasks is Some(true) {
    put_opt_map(obj, "tasks", Some({}))
  }
  Json(obj)
}

///|
pub impl FromJson for ClientCapabilities with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ClientCapabilities raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ClientCapabilities")
  {
    experimental: opt_obj(obj, path, "experimental"),
    roots_list_changed: match opt_obj(obj, path, "roots") {
      Some(roots) => opt_bool(roots, path, "listChanged")
      None => None
    },
    sampling: opt_obj(obj, path, "sampling").map_or(None, fn(_) { Some(true) }),
    elicitation: opt_obj(obj, path, "elicitation").map_or(None, fn(_) {
      Some(true)
    }),
    tasks: opt_obj(obj, path, "tasks").map_or(None, fn(_) { Some(true) }),
  }
}

///|
/// UI hints for a tool.
pub(all) struct ToolAnnotations {
  title : String?
  read_only_hint : Bool?
  destructive_hint : Bool?
  idempotent_hint : Bool?
  open_world_hint : Bool?
} derive(Debug, Eq)

///|
pub impl ToJson for ToolAnnotations with fn to_json(self : ToolAnnotations) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_str(obj, "title", self.title)
  put_opt_bool(obj, "readOnlyHint", self.read_only_hint)
  put_opt_bool(obj, "destructiveHint", self.destructive_hint)
  put_opt_bool(obj, "idempotentHint", self.idempotent_hint)
  put_opt_bool(obj, "openWorldHint", self.open_world_hint)
  Json(obj)
}

///|
pub impl FromJson for ToolAnnotations with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ToolAnnotations raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ToolAnnotations")
  {
    title: opt_str(obj, path, "title"),
    read_only_hint: opt_bool(obj, path, "readOnlyHint"),
    destructive_hint: opt_bool(obj, path, "destructiveHint"),
    idempotent_hint: opt_bool(obj, path, "idempotentHint"),
    open_world_hint: opt_bool(obj, path, "openWorldHint"),
  }
}

///|
/// Task execution configuration advertised on a tool (SEP-1686).
pub(all) struct ToolExecution {
  task_support : @tasks.TaskMode
} derive(Debug, Eq)

///|
pub impl ToJson for ToolExecution with fn to_json(self : ToolExecution) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "taskSupport", self.task_support.to_wire())
  Json(obj)
}

///|
pub impl FromJson for ToolExecution with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ToolExecution raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ToolExecution")
  let mode = match
    @tasks.task_mode_from_wire(
      req_str(obj, path, "ToolExecution", "taskSupport"),
    ) {
    Some(mode) => mode
    None => raise decode_error(path, "ToolExecution: invalid taskSupport value")
  }
  { task_support: mode, }
}

///|
/// A tool exposed to the client.
pub(all) struct Tool {
  name : String
  title : String?
  description : String?
  input_schema : Json
  output_schema : Json?
  icons : Array[Icon]?
  annotations : ToolAnnotations?
  execution : ToolExecution?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for Tool with fn to_json(self : Tool) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "name", self.name)
  put_opt_str(obj, "title", self.title)
  put_opt_str(obj, "description", self.description)
  put_opt_json(obj, "inputSchema", Some(self.input_schema))
  put_opt_json(obj, "outputSchema", self.output_schema)
  put_opt_array(
    obj,
    "icons",
    self.icons.map(fn(icons) { icons.map(Icon::to_json) }),
  )
  put_opt_json(
    obj,
    "annotations",
    self.annotations.map(ToolAnnotations::to_json),
  )
  put_opt_json(obj, "execution", self.execution.map(ToolExecution::to_json))
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for Tool with fn from_json(json : Json, path : @json.JsonPath) -> Tool raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "Tool")
  {
    name: req_str(obj, path, "Tool", "name"),
    title: opt_str(obj, path, "title"),
    description: opt_str(obj, path, "description"),
    input_schema: obj.get("inputSchema").unwrap_or(Json::null()),
    output_schema: obj.get("outputSchema"),
    icons: match opt_array(obj, path, "icons") {
      Some(values) => Some(values.map(value => @json.from_json(value)))
      None => None
    },
    annotations: match obj.get("annotations") {
      Some(value) => Some(@json.from_json(value))
      None => None
    },
    execution: match obj.get("execution") {
      Some(value) => Some(@json.from_json(value))
      None => None
    },
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// One argument of a prompt template.
pub(all) struct PromptArgument {
  name : String
  title : String?
  description : String?
  required : Bool?
} derive(Debug, Eq)

///|
pub impl ToJson for PromptArgument with fn to_json(self : PromptArgument) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "name", self.name)
  put_opt_str(obj, "title", self.title)
  put_opt_str(obj, "description", self.description)
  put_opt_bool(obj, "required", self.required)
  Json(obj)
}

///|
pub impl FromJson for PromptArgument with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> PromptArgument raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "PromptArgument")
  {
    name: req_str(obj, path, "PromptArgument", "name"),
    title: opt_str(obj, path, "title"),
    description: opt_str(obj, path, "description"),
    required: opt_bool(obj, path, "required"),
  }
}

///|
/// A prompt template exposed to the client.
pub(all) struct Prompt {
  name : String
  title : String?
  description : String?
  arguments : Array[PromptArgument]?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for Prompt with fn to_json(self : Prompt) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "name", self.name)
  put_opt_str(obj, "title", self.title)
  put_opt_str(obj, "description", self.description)
  put_opt_array(
    obj,
    "arguments",
    self.arguments.map(fn(args) { args.map(PromptArgument::to_json) }),
  )
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for Prompt with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Prompt raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "Prompt")
  {
    name: req_str(obj, path, "Prompt", "name"),
    title: opt_str(obj, path, "title"),
    description: opt_str(obj, path, "description"),
    arguments: match opt_array(obj, path, "arguments") {
      Some(values) => Some(values.map(value => @json.from_json(value)))
      None => None
    },
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// A resource exposed for reading.
pub(all) struct Resource {
  uri : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  size : Int32?
  annotations : Annotations?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for Resource with fn to_json(self : Resource) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "uri", self.uri)
  put_str(obj, "name", self.name)
  put_opt_str(obj, "title", self.title)
  put_opt_str(obj, "description", self.description)
  put_opt_str(obj, "mimeType", self.mime_type)
  put_opt_int(obj, "size", self.size)
  put_opt_json(obj, "annotations", self.annotations.map(Annotations::to_json))
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for Resource with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Resource raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "Resource")
  {
    uri: req_str(obj, path, "Resource", "uri"),
    name: req_str(obj, path, "Resource", "name"),
    title: opt_str(obj, path, "title"),
    description: opt_str(obj, path, "description"),
    mime_type: opt_str(obj, path, "mimeType"),
    size: opt_int(obj, path, "size"),
    annotations: match obj.get("annotations") {
      Some(value) => Some(@json.from_json(value))
      None => None
    },
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// A parameterised resource address pattern.
pub(all) struct ResourceTemplate {
  uri_template : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  annotations : Annotations?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
pub impl ToJson for ResourceTemplate with fn to_json(self : ResourceTemplate) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "uriTemplate", self.uri_template)
  put_str(obj, "name", self.name)
  put_opt_str(obj, "title", self.title)
  put_opt_str(obj, "description", self.description)
  put_opt_str(obj, "mimeType", self.mime_type)
  put_opt_json(obj, "annotations", self.annotations.map(Annotations::to_json))
  put_opt_map(obj, "_meta", self.meta)
  Json(obj)
}

///|
pub impl FromJson for ResourceTemplate with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ResourceTemplate raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ResourceTemplate")
  {
    uri_template: req_str(obj, path, "ResourceTemplate", "uriTemplate"),
    name: req_str(obj, path, "ResourceTemplate", "name"),
    title: opt_str(obj, path, "title"),
    description: opt_str(obj, path, "description"),
    mime_type: opt_str(obj, path, "mimeType"),
    annotations: match obj.get("annotations") {
      Some(value) => Some(@json.from_json(value))
      None => None
    },
    meta: opt_obj(obj, path, "_meta"),
  }
}

///|
/// A filesystem root the client exposes to the server.
pub(all) struct Root {
  uri : String
  name : String?
} derive(Debug, Eq)

///|
pub impl ToJson for Root with fn to_json(self : Root) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "uri", self.uri)
  put_opt_str(obj, "name", self.name)
  Json(obj)
}

///|
pub impl FromJson for Root with fn from_json(json : Json, path : @json.JsonPath) -> Root raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "Root")
  { uri: req_str(obj, path, "Root", "uri"), name: opt_str(obj, path, "name"), }
}

///|
/// One message in a sampling round trip.
pub(all) enum Role {
  User
  Assistant
} derive(Debug, Eq)

///|
pub fn Role::to_wire(self : Role) -> String {
  match self {
    User => "user"
    Assistant => "assistant"
  }
}

///|
pub fn role_from_wire(value : String) -> Role? {
  match value {
    "user" => Some(User)
    "assistant" => Some(Assistant)
    _ => None
  }
}

///|
pub(all) struct SamplingMessage {
  role : Role
  content : ContentBlock
} derive(Debug, Eq)

///|
pub impl ToJson for SamplingMessage with fn to_json(self : SamplingMessage) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "role", self.role.to_wire())
  put_opt_json(obj, "content", Some(ContentBlock::to_json(self.content)))
  Json(obj)
}

///|
pub impl FromJson for SamplingMessage with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> SamplingMessage raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "SamplingMessage")
  let role = match
    role_from_wire(req_str(obj, path, "SamplingMessage", "role")) {
    Some(r) => r
    None => raise decode_error(path, "SamplingMessage: invalid role")
  }
  {
    role,
    content: @json.from_json(obj.get("content").unwrap_or(Json::null())),
  }
}

///|
/// Client hints steering server-side model selection.
pub(all) struct ModelHint {
  name : String
} derive(Debug, Eq)

///|
pub(all) struct ModelPreferences {
  hints : Array[ModelHint]?
  cost_priority : Double?
  speed_priority : Double?
  intelligence_priority : Double?
} derive(Debug, Eq)

///|
pub impl ToJson for ModelPreferences with fn to_json(self : ModelPreferences) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_array(
    obj,
    "hints",
    self.hints.map(fn(hints) { hints.map(fn(h) { h.to_json() }) }),
  )
  if self.cost_priority is Some(p) {
    put_opt_double(obj, "costPriority", p)
  }
  if self.speed_priority is Some(p) {
    put_opt_double(obj, "speedPriority", p)
  }
  if self.intelligence_priority is Some(p) {
    put_opt_double(obj, "intelligencePriority", p)
  }
  Json(obj)
}

///|
pub impl FromJson for ModelPreferences with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ModelPreferences raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ModelPreferences")
  {
    hints: match opt_array(obj, path, "hints") {
      Some(values) => Some(values.map(value => @json.from_json(value)))
      None => None
    },
    cost_priority: opt_double(obj, path, "costPriority"),
    speed_priority: opt_double(obj, path, "speedPriority"),
    intelligence_priority: opt_double(obj, path, "intelligencePriority"),
  }
}

///|
pub impl ToJson for ModelHint with fn to_json(self : ModelHint) -> Json {
  let obj : Map[String, Json] = Map([])
  put_str(obj, "name", self.name)
  Json(obj)
}

///|
pub impl FromJson for ModelHint with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ModelHint raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ModelHint")
  { name: req_str(obj, path, "ModelHint", "name"), }
}

///|
pub extend ClientCapabilities with @json.FromJson::{from_json}

///|
pub extend ClientCapabilities with Debug::{to_repr}

///|
pub extend ClientCapabilities with Eq::{not_equal, equal}

///|
pub extend ClientCapabilities with ToJson::{to_json}

///|
pub extend Implementation with @json.FromJson::{from_json}

///|
pub extend Implementation with Debug::{to_repr}

///|
pub extend Implementation with Eq::{not_equal, equal}

///|
pub extend Implementation with ToJson::{to_json}

///|
pub extend ModelHint with @json.FromJson::{from_json}

///|
pub extend ModelHint with Debug::{to_repr}

///|
pub extend ModelHint with Eq::{not_equal, equal}

///|
pub extend ModelHint with ToJson::{to_json}

///|
pub extend ModelPreferences with @json.FromJson::{from_json}

///|
pub extend ModelPreferences with Debug::{to_repr}

///|
pub extend ModelPreferences with Eq::{not_equal, equal}

///|
pub extend ModelPreferences with ToJson::{to_json}

///|
pub extend Prompt with @json.FromJson::{from_json}

///|
pub extend Prompt with Debug::{to_repr}

///|
pub extend Prompt with Eq::{not_equal, equal}

///|
pub extend Prompt with ToJson::{to_json}

///|
pub extend PromptArgument with @json.FromJson::{from_json}

///|
pub extend PromptArgument with Debug::{to_repr}

///|
pub extend PromptArgument with Eq::{not_equal, equal}

///|
pub extend PromptArgument with ToJson::{to_json}

///|
pub extend PromptsCapabilities with Debug::{to_repr}

///|
pub extend PromptsCapabilities with Eq::{not_equal, equal}

///|
pub extend Resource with @json.FromJson::{from_json}

///|
pub extend Resource with Debug::{to_repr}

///|
pub extend Resource with Eq::{not_equal, equal}

///|
pub extend Resource with ToJson::{to_json}

///|
pub extend ResourceTemplate with @json.FromJson::{from_json}

///|
pub extend ResourceTemplate with Debug::{to_repr}

///|
pub extend ResourceTemplate with Eq::{not_equal, equal}

///|
pub extend ResourceTemplate with ToJson::{to_json}

///|
pub extend ResourcesCapabilities with Debug::{to_repr}

///|
pub extend ResourcesCapabilities with Eq::{not_equal, equal}

///|
pub extend Role with Debug::{to_repr}

///|
pub extend Role with Eq::{not_equal, equal}

///|
pub extend Root with @json.FromJson::{from_json}

///|
pub extend Root with Debug::{to_repr}

///|
pub extend Root with Eq::{not_equal, equal}

///|
pub extend Root with ToJson::{to_json}

///|
pub extend SamplingMessage with @json.FromJson::{from_json}

///|
pub extend SamplingMessage with Debug::{to_repr}

///|
pub extend SamplingMessage with Eq::{not_equal, equal}

///|
pub extend SamplingMessage with ToJson::{to_json}

///|
pub extend ServerCapabilities with @json.FromJson::{from_json}

///|
pub extend ServerCapabilities with Debug::{to_repr}

///|
pub extend ServerCapabilities with Eq::{not_equal, equal}

///|
pub extend ServerCapabilities with ToJson::{to_json}

///|
pub extend Tool with @json.FromJson::{from_json}

///|
pub extend Tool with Debug::{to_repr}

///|
pub extend Tool with Eq::{not_equal, equal}

///|
pub extend Tool with ToJson::{to_json}

///|
pub extend ToolAnnotations with @json.FromJson::{from_json}

///|
pub extend ToolAnnotations with Debug::{to_repr}

///|
pub extend ToolAnnotations with Eq::{not_equal, equal}

///|
pub extend ToolAnnotations with ToJson::{to_json}

///|
pub extend ToolCapabilities with Debug::{to_repr}

///|
pub extend ToolCapabilities with Eq::{not_equal, equal}

///|
pub extend ToolExecution with @json.FromJson::{from_json}

///|
pub extend ToolExecution with Debug::{to_repr}

///|
pub extend ToolExecution with Eq::{not_equal, equal}

///|
pub extend ToolExecution with ToJson::{to_json}
