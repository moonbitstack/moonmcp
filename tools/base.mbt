/// Tool base classes mirroring fastmcp/tools/base.py.
///
/// Python's subclass-based dispatch (FunctionTool, TransformedTool, provider
/// tools overriding `run`) maps to a struct carrying a run closure: every
/// concrete tool in fastmcp is ultimately function-backed.

///|
/// Derive a display title from a tool name.
///
/// The MCP spec says clients should fall back to `name` for display when
/// `title` is absent, but some clients instead drop the tool entirely. Always
/// emitting a title avoids depending on that fallback.
pub fn default_title(name : String) -> String {
  let buf = StringBuilder::StringBuilder()
  let mut cap_next = true
  for ch in name {
    if ch == '_' || ch == '-' {
      buf.write_char(' ')
      cap_next = true
    } else if cap_next {
      buf.write_char(ch.to_ascii_uppercase())
      cap_next = false
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
/// Whether a tool name is valid per the MCP specification (SEP-986):
/// 1-64 characters of letters, digits, underscores and hyphens.
pub fn is_valid_tool_name(name : String) -> Bool {
  if name.is_empty() || name.length() > 64 {
    return false
  }
  for ch in name {
    let valid = (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' ||
      ch == '-'
    if !valid {
      return false
    }
  }
  true
}

///|
/// The canonical result of running a tool.
pub(all) struct ToolResult {
  content : Array[@types.ContentBlock]
  structured_content : Map[String, Json]?
  meta : Map[String, Json]?
  is_error : Bool
  /// Preserved wire representation when this result wraps a protocol result.
  raw_mcp_result : @types.CallToolResult?
  /// The client-input request when this leg resolved to an input ask
  /// (SEP-2322); `content` is always empty in that case.
  input_required : @types.InputRequiredResult?
} derive(Debug, Eq)

///|
/// Create a tool result from explicit parts; content or structured content
/// must be provided.
pub fn ToolResult::new(
  content? : Array[@types.ContentBlock],
  structured_content? : Map[String, Json],
  meta? : Map[String, Json],
  is_error~ : Bool = false,
) -> ToolResult raise @exceptions.FastMCPError {
  let content = match content {
    Some(blocks) => blocks
    None =>
      match structured_content {
        Some(_) => []
        None =>
          raise @exceptions.Validation(
            "Either content or structured_content must be provided",
          )
      }
  }
  {
    content,
    structured_content,
    meta,
    is_error,
    raw_mcp_result: None,
    input_required: None,
  }
}

///|
/// Wrap a protocol result while preserving its exact wire representation.
pub fn ToolResult::from_mcp_result(
  result : @types.CallToolResult,
) -> ToolResult {
  {
    content: result.content,
    structured_content: result.structured_content,
    meta: result.meta,
    is_error: result.is_error,
    raw_mcp_result: Some(result),
    input_required: None,
  }
}

///|
/// Wrap a client-input ask (SEP-2322) as an ordinary tool result.
pub fn ToolResult::input_required(
  input_required : @types.InputRequiredResult,
) -> ToolResult {
  {
    content: [],
    structured_content: None,
    meta: None,
    is_error: false,
    raw_mcp_result: None,
    input_required: Some(input_required),
  }
}

///|
/// Whether this result carries a client-input ask (SEP-2322).
pub fn ToolResult::is_input_required(self : ToolResult) -> Bool {
  self.input_required is Some(_)
}

///|
/// Convert to the protocol result, keeping the original wire representation
/// when one was preserved.
pub fn ToolResult::to_mcp_result(self : ToolResult) -> @types.CallToolResult {
  match self.raw_mcp_result {
    Some(raw) => raw
    None =>
      {
        content: self.content,
        structured_content: self.structured_content,
        is_error: self.is_error,
        cache_control: None,
        meta: self.meta,
      }
  }
}

///|
/// A registered tool.
pub(all) struct Tool {
  component : @component.ComponentBase
  /// JSON schema for the tool's input parameters.
  parameters : Json
  /// JSON schema for the tool's structured output.
  output_schema : Json?
  annotations : @types.ToolAnnotations?
  /// Task execution configuration (SEP-1686).
  execution : @types.ToolExecution?
  /// Execution timeout in seconds; `None` applies no timeout.
  timeout : Double?
  run_fn : (Map[String, Json]) -> ToolResult raise @exceptions.FastMCPError
}

///|
pub impl @component.Component for Tool with fn base(self) {
  self.component
}

///|
pub impl @component.Component for Tool with fn identifier(self) {
  self.component.name
}

///|
pub impl @component.Component for Tool with fn key(self) {
  self.component.key(self.component.name)
}

///|
pub impl @component.Component for Tool with fn get_meta(self) {
  self.component.get_meta()
}

///|
/// Register a tool. `parameters` is the JSON schema of its arguments and
/// `run_fn` executes it.
pub fn Tool::new(
  name : String,
  parameters~ : Json,
  run_fn~ : (Map[String, Json]) -> ToolResult raise @exceptions.FastMCPError,
  version? : String,
  title? : String,
  description? : String,
  icons? : Array[@types.Icon],
  tags~ : @set.Set[String] = @set.Set::from_array([]),
  meta? : Map[String, Json],
  annotations? : @types.ToolAnnotations,
  output_schema? : Json,
  execution? : @types.ToolExecution,
  timeout? : Double,
  task_config~ : @tasks.TaskConfig = @tasks.TaskConfig::new(
    mode=@tasks.Forbidden,
  ),
) -> Tool raise @exceptions.FastMCPError {
  if !is_valid_tool_name(name) {
    raise @exceptions.Validation(
      "Invalid tool name '\{name}': must be 1-64 characters of letters, digits, underscores and hyphens",
    )
  }
  {
    component: @component.ComponentBase::new(
      "tool",
      name,
      version?,
      title?,
      description?,
      icons?,
      tags~,
      meta?,
      task_config~,
    ),
    parameters,
    output_schema,
    annotations,
    execution,
    timeout,
    run_fn,
  }
}

///|
/// Run the tool with arguments.
pub fn Tool::run(
  self : Tool,
  arguments : Map[String, Json],
) -> ToolResult raise @exceptions.FastMCPError {
  (self.run_fn)(arguments)
}

///|
/// Server entry point for tool execution; subclasses customise dispatch by
/// supplying a different `run_fn` at construction.
pub fn Tool::dispatch(
  self : Tool,
  arguments : Map[String, Json],
) -> ToolResult raise @exceptions.FastMCPError {
  self.run(arguments)
}

///|
/// Convert the tool to its wire representation.
///
/// Title precedence: explicit title, then annotation title, then a title
/// derived from the name.
pub fn Tool::to_mcp_tool(self : Tool) -> @types.Tool {
  let title = match self.component.title {
    Some(title) => Some(title)
    None =>
      match self.annotations {
        Some(annotations) => annotations.title
        None => None
      }
  }
  let title = Some(title.unwrap_or(default_title(self.component.name)))
  let mut execution = self.execution
  if self.component.task_config.supports_tasks() && execution is None {
    execution = Some({ task_support: self.component.task_config.mode, })
  }
  {
    name: self.component.name,
    title,
    description: self.component.description,
    input_schema: self.parameters,
    output_schema: self.output_schema,
    icons: self.component.icons,
    annotations: self.annotations,
    execution,
    meta: Some(Tool::get_meta(self)),
  }
}

///|
/// Convert a raw return value to a `ToolResult`, honouring the declared
/// output schema.
pub fn Tool::convert_result(
  self : Tool,
  raw_value : Json,
) -> ToolResult raise @exceptions.FastMCPError {
  let content : Array[@types.ContentBlock] = convert_to_content(raw_value) catch {
    _ => raise @exceptions.Tool("Could not convert tool result")
  }
  let is_content = is_content_result(raw_value)
  // Content-block results skip structured content unless an output schema
  // obliges it.
  if self.output_schema is None && is_content {
    return ToolResult::new(content~)
  }
  guard raw_value is Object(structured) else {
    // A non-object value cannot back structured content.
    if self.output_schema is Some(_) {
      raise @exceptions.Tool(
        "Could not serialise the return value of tool '\{self.component.name}' for its output schema",
      )
    }
    return ToolResult::new(content~)
  }
  if self.output_schema is None {
    // No schema: structured content only for objects.
    return ToolResult::new(content~, structured_content=structured)
  }
  // Has output schema: wrap when x-fastmcp-wrap-result is set.
  let wrap_result = match self.output_schema {
    Some(Object(schema)) =>
      schema.get("x-fastmcp-wrap-result") == Some(Json::boolean(true))
    _ => false
  }
  if wrap_result {
    let wrapped : Map[String, Json] = { "result": Json(structured) }
    let fastmcp : Map[String, Json] = { "wrap_result": Json::boolean(true) }
    let meta : Map[String, Json] = { "fastmcp": Json(fastmcp) }
    ToolResult::new(content~, structured_content=wrapped, meta~)
  } else {
    ToolResult::new(content~, structured_content=structured)
  }
}

///|
pub extend Tool with @component.Component::{base, identifier, key, get_meta}

///|
pub extend ToolResult with Debug::{to_repr}

///|
pub extend ToolResult with Eq::{not_equal, equal}
