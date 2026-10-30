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

The server is now at `http://127.0.0.1:12000/mcp`. For a client that starts the
server as a subprocess, call `mcp.run_stdio()` instead of serving HTTP.

`moon.mod` needs `moonbitstack/moonmcp`, `moonbitstack/mooncat` and
`moonbitlang/async`, and the package with `main` imports the same three.

## Registering

| Call | Offers |
|:--|:--|
| `tool(name, handler, input_schema=, output_schema=, description=, annotations=)` | A tool. The handler returns any JSON value: an object becomes structured content as well as text. |
| `resource(uri, read, mime_type=)` | A resource read as text. |
| `template(uri_template, read)` | Every resource an RFC 6570 template names; `read` gets the matched parameters. |
| `prompt(name, render, arguments=)` | A prompt rendered as one user message. |
| `add_tool`, `add_resource`, `add_template`, `add_prompt` | A component built in full with `Tool::new`, `Resource::new`, `ResourceTemplate::new` or `Prompt::new`. |

Arguments are checked against the tool's input schema (JSON Schema 2020-12)
before the handler runs. A wrong argument or an error the handler raises comes
back as a result marked `isError`, which the model reads and can correct itself
from; only a tool that does not exist is a protocol error.

## Annotations

The same registrations, written on the functions themselves:

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
rule(name: "mcp", command: "moonx moonbitstack/moonmcp/cmd/mcp@0.1.2 -C \"$mod_dir\" \"$input\" -o \"$output\"")
```

and in the `moon.pkg` of the package holding the functions:

```
dev_build(rule: "mcp", input: "tools.mbt", output: "tools.g.mbt")
formatter(ignore: [ "tools.g.mbt" ])
```

`moon check`, `moon build` and `moon run` regenerate `tools.g.mbt` whenever
`tools.mbt` changes. It holds `register(mcp)`, which the program calls once
before serving.

## Transports

| Transport | Call | Notes |
|:--|:--|:--|
| Streamable HTTP | `to_asgi(path="/mcp", origins=[])` | An ASGI application. One POST per message, answered with one JSON object or `202`. Version, method and name headers are checked against the body; a foreign `Origin` is refused with `403`. `debug_page?` names a path the debug page is served at. |
| stdio | `run_stdio()` | One message per line on standard input and output. Native. |
| Any line stream | `serve_lines(read, write)` | The stdio loop over streams of your own. |
| In process | `handle(message)` | One JSON-RPC message in, the reply out; `None` for a notification. |

Under revision 2026-07-28 every result carries `resultType` and the server's
identity; list results also carry `ttlMs` and `cacheScope`, set with
`Server::new(ttl_ms=, scope=)`.

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

## Packages

| Package | What it holds |
|:--|:--|
| `moonmcp` | The names a server is written with: `Server`, `Tool`, `Resource`, `Prompt` and the rest |
| `server` | `Server`: registration, dispatch for both protocol eras, Streamable HTTP, stdio, serving the documentation page; `decode`, which reads an argument as a parameter's type |
| `cmd/mcp` | The generator behind `#mcp.tool`, `#mcp.resource` and `#mcp.prompt` |
| `types` | The wire model: content blocks, tools, prompts, resources, capabilities, results |
| `tools`, `resources`, `prompts` | The components a server offers |
| `exceptions` | `FastMCPError` and the MCP error codes it maps to |
| `component`, `tasks`, `settings`, `config`, `utilities` | Component metadata, task configuration, settings, the `mcp.json` client configuration, media helpers |

## Install

```bash
moon add moonbitstack/moonmcp
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
