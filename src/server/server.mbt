///|
/// Who may keep a cached list result: any intermediary, or only caches inside
/// the same authorisation context (the `cacheScope` of a cacheable result).
pub(all) enum Scope {
  Public
  Private
} derive(Eq, Debug)

///|
pub extend Scope with Eq::{equal, not_equal}

///|
pub extend Scope with Debug::{to_repr}

///|
/// An MCP server (← FastMCP's `FastMCP`): the tools, resources, resource
/// templates and prompts it offers, and who it says it is.
///
/// It speaks both eras of the protocol. A request carrying its protocol version
/// in `_meta` is served statelessly under the 2026-07-28 revision; an
/// `initialize` request opens the handshake of the revisions before it. The
/// same server is reached over Streamable HTTP with `to_asgi`, over stdio with
/// `run_stdio`, or by any transport of your own through `handle`.
///
/// `ttl_ms` and `scope` are the caching hints every list result carries under
/// the 2026-07-28 revision. The presets say "stale at once" and "this caller
/// only", the cautious end of both, since a server that changes what it lists
/// per caller would otherwise leak one caller's list to the next.
pub struct Server {
  info : @types.Implementation
  instructions : String?
  ttl_ms : Int32
  scope : Scope
  priv tools : Map[String, @tools.Tool]
  priv checks : Map[String, @moonschema.Schema]
  priv resources : Map[String, @resources.Resource]
  priv templates : Array[@resources.ResourceTemplate]
  priv prompts : Map[String, @prompts.Prompt]
}

///|
pub fn Server::new(
  name : String,
  version~ : String = "0.1.0",
  title? : String,
  instructions? : String,
  ttl_ms~ : Int32 = 0,
  scope~ : Scope = Private,
) -> Server {
  {
    info: { name, title, version, },
    instructions,
    ttl_ms,
    scope,
    tools: Map([]),
    checks: Map([]),
    resources: Map([]),
    templates: [],
    prompts: Map([]),
  }
}

///|
/// Offer `tool`. Its input schema is compiled here, so a call is checked
/// against it before the tool runs. A schema that does not compile is a
/// mistake in the program, not in a request, so it aborts now rather than
/// failing the first call. A second tool under the same name replaces the
/// first.
pub fn Server::add_tool(self : Server, tool : @tools.Tool) -> Unit {
  let name = tool.component.name
  let check = @moonschema.Schema::new(tool.parameters) catch {
    e => abort("tool '\{name}': input schema does not compile: \{e}")
  }
  self.tools[name] = tool
  self.checks[name] = check
}

///|
/// Offer a tool whose handler returns any JSON value (← `@mcp.tool`). An object
/// becomes structured content as well as text; anything else becomes text. An
/// error the handler raises becomes a result marked `isError`, which the model
/// reads and can correct itself from. A name the protocol does not allow aborts
/// at registration.
pub fn Server::tool(
  self : Server,
  name : String,
  run : async (Map[String, Json]) -> Json,
  input_schema~ : Json = { "type": "object" },
  title? : String,
  description? : String,
  output_schema? : Json,
  annotations? : @types.ToolAnnotations,
) -> Unit {
  let shape = @tools.Tool::new(
    name,
    parameters=input_schema,
    run_fn=_ => @tools.ToolResult::new(),
    title?,
    description?,
    output_schema?,
    annotations?,
  ) catch {
    e => abort("tool '\{name}': \{text_of(e)}")
  }
  self.add_tool({
    ..shape,
    run_fn: args => {
      let value = run(args) catch {
        @exceptions.Mcp(data) => raise @exceptions.Mcp(data)
        e => raise @exceptions.Tool(text_of(e))
      }
      shape.convert_result(value)
    },
  })
}

///|
/// Offer `resource` at its URI. A second resource at the same URI replaces the
/// first.
pub fn Server::add_resource(
  self : Server,
  resource : @resources.Resource,
) -> Unit {
  self.resources[resource.uri] = resource
}

///|
/// Offer a resource read as text (← `@mcp.resource(uri)`).
pub fn Server::resource(
  self : Server,
  uri : String,
  read : async () -> String,
  name? : String,
  title? : String,
  description? : String,
  mime_type~ : String = "text/plain",
) -> Unit {
  self.add_resource(
    @resources.Resource::from_function(
      uri,
      read_fn=() => {
        let text = read() catch {
          @exceptions.Mcp(data) => raise @exceptions.Mcp(data)
          @exceptions.NotFound(m) => raise @exceptions.NotFound(m)
          e => raise @exceptions.Resource(text_of(e))
        }
        Text(text)
      },
      name?,
      title?,
      description?,
      mime_type~,
    ),
  )
}

///|
/// Offer `template`; a URI no fixed resource answers is matched against the
/// templates in the order they were added.
pub fn Server::add_template(
  self : Server,
  template : @resources.ResourceTemplate,
) -> Unit {
  self.templates.push(template)
}

///|
/// Offer the resources an RFC 6570 template names, read as text with the
/// parameters the URI matched (← `@mcp.resource("users://{id}")`). A template
/// that does not parse aborts at registration.
pub fn Server::template(
  self : Server,
  uri_template : String,
  read : async (Map[String, Json]) -> String,
  name? : String,
  title? : String,
  description? : String,
  mime_type~ : String = "text/plain",
) -> Unit {
  let properties : Map[String, Json] = Map([])
  for param in @resources.parse_template_params(uri_template) {
    properties[param] = { "type": "string" }
  }
  let template = @resources.ResourceTemplate::new(
    uri_template,
    parameters={ "type": "object", "properties": Json(properties) },
    read_fn=params => {
      let text = read(params) catch {
        @exceptions.Mcp(data) => raise @exceptions.Mcp(data)
        @exceptions.NotFound(m) => raise @exceptions.NotFound(m)
        e => raise @exceptions.Resource(text_of(e))
      }
      Text(text)
    },
    name?,
    title?,
    description?,
    mime_type~,
  ) catch {
    e => abort("resource template '\{uri_template}': \{text_of(e)}")
  }
  self.add_template(template)
}

///|
/// Offer `prompt`. A second prompt under the same name replaces the first.
pub fn Server::add_prompt(self : Server, prompt : @prompts.Prompt) -> Unit {
  self.prompts[prompt.component.name] = prompt
}

///|
/// Offer a prompt rendered as one user message (← `@mcp.prompt`).
pub fn Server::prompt(
  self : Server,
  name : String,
  render : async (Map[String, Json]) -> String,
  title? : String,
  description? : String,
  arguments~ : Array[@types.PromptArgument] = [],
) -> Unit {
  self.add_prompt(
    @prompts.Prompt::new(
      name,
      render_fn=args => {
        let text = render(args) catch {
          @exceptions.Mcp(data) => raise @exceptions.Mcp(data)
          @exceptions.Validation(m) => raise @exceptions.Validation(m)
          e => raise @exceptions.Prompt(text_of(e))
        }
        Text(text)
      },
      title?,
      description?,
      arguments~,
    ),
  )
}
