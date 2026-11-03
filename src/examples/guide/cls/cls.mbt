// The same server again, with every capability held by a type of its own: the
// state lives in the struct, the work in its methods, and one `impl Provider`
// says which of them the server offers.

///|
/// One object for each kind of capability.
pub fn server() -> @moonmcp.Server {
  let mcp = @moonmcp.Server::new("guide", version="1.0.0")
  mcp.add_provider(Arithmetic::new())
  mcp.add_provider(Catalog::{ })
  mcp.add_provider(Reviewer::{ })
  mcp
}

///|
/// The server with the counting tool on it.
pub fn with_counter() -> @moonmcp.Server {
  with_counter_on(server())
}

///|
/// The server with a capability held back and a cache in front of it.
pub fn extended() -> @moonmcp.Server {
  with_extensions(server())
}

// guide:first

///|
/// The arithmetic tools, and how many times they were used.
pub struct Arithmetic {
  priv mut calls : Int32
}

///|
/// A set of arithmetic tools that has not been used yet.
pub fn Arithmetic::new() -> Arithmetic {
  { calls: 0, }
}

///|
/// How many calls the tools have answered.
pub fn Arithmetic::calls(self : Arithmetic) -> Int32 {
  self.calls
}

///|
fn Arithmetic::add(
  self : Arithmetic,
  a : Double,
  b : Double,
) -> @tools.ToolResult raise @exceptions.FastMCPError {
  self.calls = self.calls + 1
  @tools.ToolResult::new(content=[@types.text_block("\{a + b}")])
}

///|
fn Arithmetic::greet(
  self : Arithmetic,
  name : String,
  language : String,
) -> @tools.ToolResult raise @exceptions.FastMCPError {
  self.calls = self.calls + 1
  let greeting = if language == "zh" {
    "你好，" + name
  } else {
    "hello, " + name
  }
  @tools.ToolResult::new(content=[@types.text_block(greeting)])
}

///|
impl @providers.Provider for Arithmetic with fn tools(self) {
  [
    @tools.Tool::new(
      "add",
      parameters={
        "type": "object",
        "properties": { "a": { "type": "number" }, "b": { "type": "number" } },
        "required": ["a", "b"],
      },
      run_fn=args => {
        let a = match args.get("a") {
          Some(Number(value, ..)) => value
          _ => 0.0
        }
        let b = match args.get("b") {
          Some(Number(value, ..)) => value
          _ => 0.0
        }
        self.add(a, b)
      },
    ) catch {
      e => abort("add: \{e}")
    },
    @tools.Tool::new(
      "greet",
      parameters={
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "language": { "type": "string" },
        },
        "required": ["name"],
      },
      run_fn=args => {
        let name = match args.get("name") {
          Some(String(name)) => name
          _ => "stranger"
        }
        let language = match args.get("language") {
          Some(String(language)) => language
          _ => ""
        }
        self.greet(name, language)
      },
    ) catch {
      e => abort("greet: \{e}")
    },
  ]
}
// end

// guide:resources

///|
/// The application's settings, and one resource per user.
pub struct Catalog {}

///|
fn Catalog::settings(self : Catalog) -> String {
  let _ = self
  "{\"theme\":\"dark\",\"language\":\"en\"}"
}

///|
fn Catalog::profile(self : Catalog, id : String) -> String {
  let _ = self
  "profile of user " + id
}

///|
impl @providers.Provider for Catalog with fn resources(self) {
  [
    @resources.Resource::new(
      "config://app",
      read_fn=() => Text(self.settings()),
      description="The application settings",
      mime_type="application/json",
    ),
  ]
}

///|
impl @providers.Provider for Catalog with fn templates(self) {
  [
    @resources.ResourceTemplate::new(
      "users://{id}/profile",
      parameters={
        "type": "object",
        "properties": { "id": { "type": "string" } },
      },
      read_fn=params => {
        let id = match params.get("id") {
          Some(String(id)) => id
          _ => "?"
        }
        Text(self.profile(id))
      },
    ) catch {
      e => abort("users://{id}/profile: \{e}")
    },
  ]
}
// end

// guide:prompts

///|
/// The reviewer: one method, one prompt.
pub struct Reviewer {}

///|
fn Reviewer::review(self : Reviewer, code : String, focus : String) -> String {
  let _ = self
  let what = if focus.is_empty() { "" } else { " Focus on " + focus + "." }
  "Review this code." + what + "\n\n" + code
}

///|
impl @providers.Provider for Reviewer with fn prompts(self) {
  [
    @prompts.Prompt::new(
      "review",
      render_fn=args => {
        let code = match args.get("code") {
          Some(String(code)) => code
          _ => ""
        }
        let focus = match args.get("focus") {
          Some(String(focus)) => focus
          _ => ""
        }
        Text(self.review(code, focus))
      },
      description="Ask for a code review",
      arguments=[
        { name: "code", title: None, description: None, required: Some(true), },
        {
          name: "focus",
          title: None,
          description: None,
          required: Some(false),
        },
      ],
    ),
  ]
}
// end

// guide:context

///|
/// A counter that reports how far it has got, through the request it serves.
pub struct Counter {}

///|
impl @providers.Provider for Counter with fn tools(self) {
  [
    @tools.Tool::new(
      "count",
      parameters={
        "type": "object",
        "properties": { "up_to": { "type": "number" } },
      },
      run_fn=_ => {
        let _ = self
        abort("count is served with its request, through context_run_fn")
      },
      description="Count to a number, reporting progress as it goes",
      context_run_fn=async fn(
        args,
        context,
      ) -> @tools.ToolResult raise @exceptions.FastMCPError {
        let up_to = match args.get("up_to") {
          Some(Number(value, ..)) => value.to_int()
          _ => 3
        }
        if up_to < 0 {
          raise @exceptions.Tool("up_to must not be negative")
        }
        for step in 0..<up_to {
          context.report_progress(
            progress=(step + 1).to_double(),
            total=up_to.to_double(),
            message="step \{step + 1}",
          ) catch {
            _ => ()
          }
        }
        @tools.ToolResult::new(content=[
          @types.text_block("counted to \{up_to}"),
        ])
      },
    ) catch {
      e => abort("count: \{e}")
    },
  ]
}
// end

///|
/// The counting tool on an existing server.
pub fn with_counter_on(mcp : @moonmcp.Server) -> @moonmcp.Server {
  mcp.add_provider(Counter::{ })
  mcp
}

// guide:extend

///|
/// A filter is a contract, so holding the greeting back is a type of its own.
pub struct Quiet {}

///|
impl @transforms.Transform for Quiet with fn tools(self, tools) {
  let _ = self
  tools.filter(tool => tool.component.name != "greet")
}

///|
/// Hold a capability back from the listing, and put a cache in front of every
/// request.
pub fn with_extensions(mcp : @moonmcp.Server) -> @moonmcp.Server {
  mcp.add_transform(Quiet::{ })
  mcp.use_layer(@layers.Caching::new(ttl_ms=1_000).layer())
  mcp
}
// end
