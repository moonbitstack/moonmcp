<p align="center">
  <strong>moonmcp</strong><br>
  Model Context Protocol servers for MoonBit.<br>
  Register tools, resources, resource templates and prompts; serve them over<br>
  Streamable HTTP or stdio, in both protocol eras.
</p>

<p align="center">
  <a href="docs/index.html"><strong>Home</strong></a> &nbsp;·&nbsp;
  <a href="docs/guide.html"><strong>Guide</strong></a> &nbsp;·&nbsp;
  <a href="docs/api.html"><strong>API</strong></a> &nbsp;·&nbsp;
  <a href="https://mooncakes.io/docs/moonbitstack/moonmcp"><strong>mooncakes</strong></a>
</p>

One server answers both eras of the protocol. A request that carries its
protocol version in `_meta` is served statelessly under revision 2026-07-28; an
`initialize` handshake selects the revisions before it (2025-11-25 back to
2024-11-05). Clients of either era connect without configuration.

## Quick start

Write the tools on the functions themselves:

```moonbit nocheck
#mcp.tool(description="Add two numbers")
fn add(a : Double, b : Double) -> Double {
  a + b
}

#mcp.resource("config://app", mime_type="application/json")
fn config() -> String {
  "{\"theme\":\"dark\"}"
}

async fn main {
  let mcp = @moonmcp.Server::new("demo", version="1.0.0")
  register(mcp)
  @mooncat.serve(mcp.to_asgi(), port=12000) catch {
    e => println("stopped: \{e}")
  }
}
```

The server is now at `http://127.0.0.1:12000/mcp`. For a client that starts the
server as a subprocess, call `mcp.run_stdio()` instead of serving HTTP.

`moon.mod` needs `moonbitstack/moonmcp`, `moonbitstack/mooncat` and
`moonbitlang/async`, and the package with `main` imports the same three.

## Annotations

Each kind of thing a server offers has its annotation:

```moonbit nocheck
#mcp.tool(description="Add two numbers")
fn add(a : Double, b : Double) -> Double {
  a + b
}

#mcp.tool(name="word_count")
fn count(text : String, unique~ : Bool = false) -> Int {
  ...
}

#mcp.resource("users://{id}/profile")
fn profile(id : Int) -> String {
  "profile of user \{id}"
}

#mcp.prompt(description="Ask for a code review")
fn review(code : String, focus? : String) -> String {
  ...
}
```

Each parameter becomes a property of the tool's input schema, typed from its
MoonBit type; optional parameters and those with a default are left out of
`required`. A URI with `{name}` makes a resource template whose matched values
are read into the function's parameters. A tool's or resource's result goes back
as JSON unless it is a `String`.

Wire the generator into the build once. In `moon.mod`:

```
rule(name: "mcp", command: "moonx moonbitstack/moonmcp/cmd/mcp@0.1.6 -C \"$mod_dir\" \"$input\" -o \"$output\"")
```

and in the `moon.pkg` of the package holding the functions:

```
dev_build(rule: "mcp", input: "tools.mbt", output: "tools.g.mbt")
formatter(ignore: [ "tools.g.mbt" ])
```

`moon check`, `moon build` and `moon run` regenerate `tools.g.mbt` whenever
`tools.mbt` changes. It holds `register(mcp)`, which the program calls once
before serving.

## Registering by hand

Annotations generate these calls, and a tool built at run time is written the same way:

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo", version="1.0.0")
  mcp.tool(
    "add",
    args => {
      guard args.get("a") is Some(Number(a, ..)) &&
        args.get("b") is Some(Number(b, ..)) else {
        fail("a and b must be numbers")
      }
      { "sum": Json(a + b) }
    },
    description="Add two numbers",
    input_schema={
      "type": "object",
      "properties": { "a": { "type": "number" }, "b": { "type": "number" } },
      "required": ["a", "b"],
    },
  )
  mcp.resource("config://app", () => "{\"theme\":\"dark\"}", mime_type="application/json")
  @mooncat.serve(mcp.to_asgi(), port=12000) catch {
    e => println("stopped: \{e}")
  }
}
```


| Call | Offers |
|:--|:--|
| `tool(name, handler, input_schema=, output_schema=, description=, annotations=)` | A tool. The handler returns any JSON value: an object becomes structured content as well as text. |
| `resource(uri, read, mime_type=)` | A resource read as text. |
| `template(uri_template, read)` | Every resource an RFC 6570 template names; `read` gets the matched parameters. |
| `prompt(name, render, arguments=)` | A prompt rendered as one user message. |
| `add_tool`, `add_resource`, `add_template`, `add_prompt` | A component built in full with `Tool::new`, `Resource::new`, `ResourceTemplate::new` or `Prompt::new`. |
| `tool_context`, `resource_context`, `template_context`, `prompt_context` | The same, with the request handed to the handler as a `Context`. |

Arguments are checked against the tool's input schema (JSON Schema 2020-12)
before the handler runs. A wrong argument or an error the handler raises comes
back as a result marked `isError`, which the model reads and can correct itself
from; only a tool that does not exist is a protocol error.

## Request context

A handler that needs to know who is calling, or to report while it works, is
registered with the context-taking call. The `Context` carries the request's
headers, the client's identity and capabilities, its progress token, the
answers it sent back on a retry, and whether it has withdrawn the request.

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo")
  mcp.tool_context(
    "summarise",
    async fn(args : Map[String, Json], context : @context.Context) {
      let tenant = context.header("x-tenant").unwrap_or("public")
      context.report_progress(progress=0.0, total=1.0, message="reading") catch {
        _ => ()
      }
      let text = match args.get("text") {
        Some(String(text)) => text
        _ => ""
      }
      context.report_progress(progress=1.0, total=1.0) catch { _ => () }
      @moonmcp.ToolResult::new(
        content=[@moonmcp.text_block("\{tenant}: \{text.length()} characters")],
      )
    },
  )
}
```

| On a `Context` | Gives |
|:--|:--|
| `header(name)`, `headers()` | The request's headers, in lower case. Empty over stdio. |
| `client_info()`, `client_capabilities()` | What the client says it is and can do, from `_meta`. Self-reported, never a permission. |
| `protocol_version()`, `operation()`, `request_id()` | Which request this is and which revision it came in. |
| `progress_token()` | The token the client offered, if any. |
| `report_progress(progress=, total=, message=)` | A `notifications/progress` on the request's own stream. Silent when no token was given. |
| `log(level=, message=)`, `debug`, `info`, `warning`, `error` | A `notifications/message`. |
| `is_cancelled()` | Whether the client withdrew the request. A long handler should stop. |
| `input_responses()`, `request_state()` | What came back with a retried request. |

## Transports

| Transport | Call | Notes |
|:--|:--|:--|
| Streamable HTTP | `to_asgi(path="/mcp", origins=[])` | An ASGI application. One POST per message, answered with one JSON object, one SSE stream, or `202`. Version, method and name headers are checked against the body; a foreign `Origin` is refused with `403`. `docs=` names the path the documentation page is served at. |
| stdio | `run_stdio()` | One message per line on standard input and output, answered as they arrive. Native. |
| Any line stream | `serve_lines(read, write)` | The stdio loop over streams of your own. |
| In process | `handle(message)` | One JSON-RPC message in, the reply out; `None` for a notification. `handle_with(message, channel=)` carries headers and somewhere to put notifications. |

Under revision 2026-07-28 every result carries `resultType` and the server's
identity; list results also carry `ttlMs` and `cacheScope`, set with
`Server::new(ttl_ms=, scope=)`. A result that asks for input carries
`resultType: "input_required"` instead.

## Progress and subscriptions

A 2026-07-28 request that offers a progress token, or that opens a
subscription, is answered with `text/event-stream` when the client accepts one:
what the handler reports arrives on that stream, and the reply ends it.

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo")
  mcp.tool_context("count", async fn(_args : Map[String, Json], context : @context.Context) {
    context.report_progress(progress=1.0, total=2.0, message="half way") catch {
      _ => ()
    }
    @moonmcp.ToolResult::new(content=[@moonmcp.text_block("done")])
  })
  @mooncat.serve(mcp.to_asgi(), port=12000) catch { _ => () }
}
```

A subscription keeps one stream open for the changes a client opted in to. The
server advertises what changed; every subscription whose filter asked for it
hears about it, and nothing else.

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo")
  // ... register the tools ...
  mcp.notify_tools_changed()
  mcp.notify_resource_updated("config://app")
}
```

Registering a tool, a resource or a prompt sends the matching list-changed
notification by itself; `notify_tools_changed`, `notify_resources_changed`,
`notify_prompts_changed` and `notify_resource_updated` are for the times a
server changes what it offers for reasons of its own.

## Asking the client for input

A handler that cannot finish without something from the client says so instead
of answering. The client answers, then sends the same call again with the
answers and the state it was handed.

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo")
  mcp.tool_context("greet", async fn(_args : Map[String, Json], context : @context.Context) {
    match context.input_responses().get("name") {
      Some(String(name)) =>
        @moonmcp.ToolResult::new(content=[@moonmcp.text_block("hello " + name)])
      _ =>
        @moonmcp.ToolResult::input_required({
          input_requests: [
            {
              id: "name",
              request: {
                "method": Json::string("elicitation/create"),
                "params": {
                  "message": Json::string("Your name?"),
                  "requestedSchema": { "type": "object" },
                },
              },
            },
          ],
          request_state: Some("greeting"),
          meta: None,
        })
    }
  })
}
```

On stdio a client withdraws a request with `notifications/cancelled`; on
Streamable HTTP it closes the response stream, which the server notices the
next time it writes. Either way `Context::is_cancelled` answers.

## Client

The client speaks the same protocol from the other end, over an in-memory
server, a pair of line streams, or HTTP.

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo")
  mcp.tool("add", args => {
    let a = match args.get("a") {
      Some(Number(value, ..)) => value
      _ => 0.0
    }
    { "sum": Json(a) }
  })
  let client = @moonmcp.Client::connect(
    @moonmcp.Memory::new(mcp),
    protocol_version="2026-07-28",
  )
  let tools = client.list_tools()
  println("\{tools.length()} tools")
  let result = client.call_tool("add", arguments={ "a": 2, "b": 3 })
  println(Json(result.structured_content.unwrap()).stringify())
  client.close()
}
```

Reaching a server over HTTP takes the transport from `moonbitstack/moonmcp/client/http`,
which needs a socket and so is native only:

```moonbit nocheck
let client = @client.Client::connect(@http.Http::new("http://127.0.0.1:12000/mcp"))
```

`Lines` carries the same messages over any pair of line streams, which is what a
server started as a child process speaks.

| Call | Does |
|:--|:--|
| `Client::connect(transport, protocol_version=)` | Connects; on the revisions before 2026-07-28 it runs the handshake once and keeps the server's identity and capabilities. |
| `list_tools`, `list_resources`, `list_prompts` | The three listings, as the library's own types. |
| `call_tool(name, arguments=, progress_token=, on_notification=)` | A call, with the notifications it causes handed to the callback. |
| `read_resource`, `get_prompt` | One read, one render. |
| `listen(filter=, on_notification=)` | A subscription, until the server ends it. |
| `request`, `exchange`, `notify` | Any method, with `_meta` filled in for you. |
| `close()` | Lets the connection go. |

A transport is anything implementing `Transport`: `ask`, `tell`, `listen` and
`close`. `Memory`, `Lines` and `Http` ship here; a fourth is a hundred lines,
and the client above it does not change.

## Debug page

`to_asgi` serves a documentation page beside the endpoint, the way an API
framework serves its interactive docs:

```moonbit nocheck
@mooncat.serve(mcp.to_asgi(), port=12000)
```

Open `http://127.0.0.1:12000/docs`. The page asks the endpoint for the tools,
resources, resource templates and prompts, fills an argument form in from each
tool's input schema, and shows the JSON-RPC request it built beside the reply
it got back, in either era of the protocol. `docs=Some("/other")` moves it,
`docs=None` leaves it off, and `theme=Plain` swaps the website's look for a
neutral one. `@docs.page(endpoint=...)` from `moonbitstack/moonmcp/docs` gives
the same page to a router of your own.

## Connect a client

A client that starts the server as a subprocess is given the command:

<!-- nocheck -->
```json
{
  "mcpServers": {
    "demo": {
      "command": "moon",
      "args": ["run", "src/examples/stdio", "--target", "native"]
    }
  }
}
```

One that reaches the server over HTTP is given the URL, with `streamable-http`
as the transport:

<!-- nocheck -->
```json
{
  "mcpServers": {
    "demo": {
      "url": "http://127.0.0.1:12000/mcp",
      "transport": "streamable-http"
    }
  }
}
```

Clients of both eras connect without configuration: the handshake revisions
open with `initialize`, and a client that speaks 2026-07-28 names its version in
`_meta` and needs no handshake at all. `moonbitstack/moonmcp/config` reads and
writes the configuration above.

## Examples

| Example | Shows |
|:--|:--|
| [`demo`](src/examples/demo/) | One server with two tools, a resource, a resource template and a prompt |
| [`http`](src/examples/http/) | That server over Streamable HTTP, with the documentation page at `/docs`: `moon run src/examples/http --target native` |
| [`stdio`](src/examples/stdio/) | That server over stdio: `moon run src/examples/stdio --target native` |
| [`annotations`](src/examples/annotations/) | Tools, resources, a template and a prompt written as `#mcp.*` annotations, served over stdio |
| [`client`](src/examples/client/) | A client and a server in one program: list the tools, call one, print the progress it reports: `moon run src/examples/client --target native` |

## Packages

| Package | What it holds |
|:--|:--|
| `moonmcp` | The names a server is written with: `Server`, `Tool`, `Resource`, `Prompt` and the rest |
| `server` | `Server`: registration, dispatch for both protocol eras, Streamable HTTP, stdio, serving the documentation page; `decode`, which reads an argument as a parameter's type |
| `cmd/mcp` | The generator behind `#mcp.tool`, `#mcp.resource` and `#mcp.prompt` |
| `types` | The wire model: content blocks, tools, prompts, resources, capabilities, results |
| `tools`, `resources`, `prompts` | The components a server offers |
| `exceptions` | `FastMCPError` and the MCP error codes it maps to |
| `context` | `Context` and `Facts`: what a handler is told about the request it serves |
| `client` | `Client` and the `Transport` contract, with the in-memory and line transports |
| `client/http` | The HTTP transport |
| `component`, `tasks`, `settings`, `config`, `utilities` | Component metadata, task configuration, settings, the `mcp.json` client configuration, media helpers |

## Install

```bash
moon add moonbitstack/moonmcp
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
