/// Prompt base classes mirroring fastmcp/prompts/base.py.

/// A wrapper for a prompt message with a role.
pub(all) struct Message {
  role : @types.Role
  content : @types.ContentBlock
} derive(Debug, Eq)

/// Create a message from plain text, user role by default.
pub fn Message::text(
  text : String,
  role? : @types.Role = @types.User,
) -> Message {
  { role, content: @types.text_block(text) }
}

/// Create a message from an existing content block, user role by default.
pub fn Message::of_content(
  content : @types.ContentBlock,
  role? : @types.Role = @types.User,
) -> Message {
  { role, content }
}

/// Convert to the wire prompt message.
pub fn Message::to_mcp_prompt_message(self : Message) -> @types.PromptMessage {
  { role: self.role, content: self.content }
}

/// The canonical result of rendering a prompt.
pub(all) struct PromptResult {
  messages : Array[Message]
  description : String?
  meta : Map[String, Json]?
  /// The client-input request when this leg resolved to an input ask
  /// (SEP-2322); `messages` is always empty in that case.
  input_required : @types.InputRequiredResult?
} derive(Debug, Eq)

/// Create a prompt result from a list of messages.
pub fn PromptResult::new(
  messages : Array[Message],
  description? : String,
  meta? : Map[String, Json],
) -> PromptResult {
  {
    messages,
    description,
    meta,
    input_required: None,
  }
}

/// Wrap a client-input ask (SEP-2322) as an ordinary prompt result.
pub fn PromptResult::input_required(
  input_required : @types.InputRequiredResult,
) -> PromptResult {
  {
    messages: [],
    description: None,
    meta: None,
    input_required: Some(input_required),
  }
}

/// Whether this result carries a client-input ask (SEP-2322).
pub fn PromptResult::is_input_required(self : PromptResult) -> Bool {
  self.input_required is Some(_)
}

/// Convert to the wire get-prompt result.
pub fn PromptResult::to_mcp_prompt_result(
  self : PromptResult,
) -> @types.GetPromptResult {
  {
    description: self.description,
    messages: self.messages.map(Message::to_mcp_prompt_message),
    cache_control: None,
    meta: self.meta,
  }
}

/// What a prompt's render function may return: plain text, a message list,
/// or an already-assembled result.
pub(all) enum RenderedPrompt {
  Text(String)
  Messages(Array[Message])
  Ready(PromptResult)
}

/// A prompt template that can be rendered with arguments.
pub(all) struct Prompt {
  component : @component.ComponentBase
  /// Arguments that can be passed to the prompt.
  arguments : Array[@types.PromptArgument]?
  render_fn : (Map[String, Json]) -> RenderedPrompt raise @exceptions.FastMCPError
}

pub impl @component.Component for Prompt with base(self) {
  self.component
}

pub impl @component.Component for Prompt with identifier(self) {
  self.component.name
}

pub impl @component.Component for Prompt with key(self) {
  self.component.key(self.component.name)
}

pub impl @component.Component for Prompt with get_meta(self) {
  self.component.get_meta()
}

/// Register a prompt; `render_fn` renders it with the given arguments.
pub fn Prompt::new(
  name : String,
  render_fn~ : (Map[String, Json]) -> RenderedPrompt raise @exceptions.FastMCPError,
  version? : String,
  title? : String,
  description? : String,
  icons? : Array[@types.Icon],
  tags? : @set.Set[String] = @set.Set::from_array([]),
  meta? : Map[String, Json],
  arguments? : Array[@types.PromptArgument],
) -> Prompt {
  {
    component: @component.ComponentBase::new(
      "prompt",
      name,
      version?=version,
      title?=title,
      description?=description,
      icons?=icons,
      tags=tags,
      meta?=meta,
    ),
    arguments,
    render_fn,
  }
}

/// Render the prompt with arguments.
pub fn Prompt::render(
  self : Prompt,
  arguments : Map[String, Json],
) -> RenderedPrompt raise @exceptions.FastMCPError {
  (self.render_fn)(arguments)
}

/// Convert a rendered value to a canonical result.
pub fn Prompt::convert_result(
  self : Prompt,
  raw_value : RenderedPrompt,
) -> PromptResult raise @exceptions.FastMCPError {
  match raw_value {
    Ready(result) => result
    Text(text) =>
      PromptResult::new(
        [Message::text(text)],
        description?=self.component.description,
        meta?=@component.public_result_meta(self.component.meta),
      )
    Messages(messages) =>
      PromptResult::new(
        messages,
        description?=self.component.description,
        meta?=@component.public_result_meta(self.component.meta),
      )
  }
}

/// Server entry point for prompt rendering.
pub fn Prompt::render_result(
  self : Prompt,
  arguments : Map[String, Json],
) -> PromptResult raise @exceptions.FastMCPError {
  self.convert_result(self.render(arguments))
}

/// Convert the prompt to its wire representation.
pub fn Prompt::to_mcp_prompt(self : Prompt) -> @types.Prompt {
  {
    name: self.component.name,
    title: self.component.title,
    description: self.component.description,
    arguments: self.arguments,
    meta: Some(Prompt::get_meta(self)),
  }
}
