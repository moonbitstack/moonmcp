<p align="center">
  <strong>moonmcp</strong><br>
  Model Context Protocol servers and clients for MoonBit.<br>
  Register tools, resources, resource templates and prompts, serve them over<br>
  Streamable HTTP or stdio in both protocol eras, and reach other people's<br>
  servers from the other end — with their authorization flow.
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
rule(name: "mcp", command: "moonx moonbitstack/moonmcp/cmd/mcp@0.1.10 -C \"$mod_dir\" \"$input\" -o \"$output\"")
```

and in the `moon.pkg` of the package holding the functions:

```
dev_build(rule: "mcp", input: "tools.mbt", output: "tools.g.mbt")
formatter(ignore: [ "tools.g.mbt" ])
```

`moon check`, `moon build` and `moon run` regenerate `tools.g.mbt` whenever
`tools.mbt` changes. It holds `register(mcp)`, which the program calls once
before serving.

## Without annotations

Annotations are one of three ways to say the same thing. The other two are one
registration per capability, and a type that holds a capability of its own.

### One call per capability

Annotations generate exactly these calls, and a capability decided at run time
is written the same way:

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

### A type per capability

A set of capabilities can also live in a type: the state in its fields, the
work in its methods, and one `impl Provider` saying which of them the server
offers. The server is handed the object and asks it again whenever the tools
are listed, so what it offers may change between two listings.

```moonbit
///|
struct Arithmetic {
  priv mut calls : Int
}

///|
fn Arithmetic::add(
  self : Arithmetic,
  a : Double,
  b : Double,
) -> @moonmcp.ToolResult raise @moonmcp.FastMCPError {
  self.calls = self.calls + 1
  @moonmcp.ToolResult::new(content=[@moonmcp.text_block("\{a + b}")])
}

///|
impl @moonmcp.Provider for Arithmetic with fn tools(self) {
  [
    @moonmcp.Tool::new(
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
  ]
}

///|
async fn main {
  let mcp = @moonmcp.Server::new("demo", version="1.0.0")
  mcp.add_provider(Arithmetic::{ calls: 0 })
  @mooncat.serve(mcp.to_asgi(), port=12000) catch {
    e => println("stopped: \{e}")
  }
}
```

## Extending the server

Three things can sit between the program and the client. A **provider** supplies
capabilities from somewhere other than the registry — a file, another server, a
type of your own. A **transform** rewrites what the client is shown. A **layer**
sees every request before it is served, and may answer it, refuse it, or let it
go on.

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo", version="1.0.0")
  mcp.tool("add", args => Json("added"), description="Add two numbers")
  mcp.add_transform(@moonmcp.Namespace::new("bench"))
  mcp.use_layer(@moonmcp.RateLimiting::new(rate=10, burst=20).layer())
  mcp.use_layer(@moonmcp.Caching::new(ttl_ms=5_000).layer())
  @mooncat.serve(mcp.to_asgi(), port=12000) catch {
    e => println("stopped: \{e}")
  }
}
```

The tool is now listed as `bench_add`, ten calls a second are allowed per caller
with twenty in a burst, and a repeated call is answered from memory for five
seconds.

| Call | Does |
|:--|:--|
| `add_provider(provider)` | Takes capabilities from an object implementing `Provider`, asked again on every listing. A name the server already answers is not taken over. |
| `add_transform(transform)` | Rewrites the offered set: `Namespace(prefix)`, `Hidden(names)`, `Tagged(any_of)`, or a type implementing `Transform`. They run in the order they were added. |
| `use_layer(layer)` | Puts a `Layer` in front of every request: `Caching`, `RateLimiting`, `Telemetry`, or `Layer::new(run=)`. The first one added is outermost. |

A cached answer is keyed on the operation, the name, the caller and the
arguments, with object keys sorted, so the same call with its arguments in
another order hits the same entry. Errors and asks for client input are never
cached, and one caller's answer is not handed to another unless the cache was
built with `shared=true`.

## Extending the server

Three things can sit between the program and the client. A **provider** supplies
capabilities from somewhere other than the registry — a file, another server, a
type of your own. A **transform** rewrites what the client is shown. A **layer**
sees every request before it is served, and may answer it, refuse it, or let it
go on.

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo", version="1.0.0")
  mcp.tool("add", args => Json("added"), description="Add two numbers")
  mcp.add_transform(@moonmcp.Namespace::new("bench"))
  mcp.use_layer(@moonmcp.RateLimiting::new(rate=10, burst=20).layer())
  mcp.use_layer(@moonmcp.Caching::new(ttl_ms=5_000).layer())
  @mooncat.serve(mcp.to_asgi(), port=12000) catch {
    e => println("stopped: \{e}")
  }
}
```

The tool is now listed as `bench_add`, ten calls a second are allowed per caller
with twenty in a burst, and a repeated call is answered from memory for five
seconds.

| Call | Does |
|:--|:--|
| `add_provider(provider)` | Takes capabilities from an object implementing `Provider`, asked again on every listing. A name the server already answers is not taken over. |
| `add_transform(transform)` | Rewrites the offered set: `Namespace(prefix)`, `Hidden(names)`, `Tagged(any_of)`, or a type implementing `Transform`. They run in the order they were added. |
| `use_layer(layer)` | Puts a `Layer` in front of every request: `Caching`, `RateLimiting`, `Telemetry`, or `Layer::new(run=)`. The first one added is outermost. |

A cached answer is keyed on the operation, the name, the caller and the
arguments, with object keys sorted, so the same call with its arguments in
another order hits the same entry. Errors and asks for client input are never
cached, and one caller's answer is not handed to another unless the cache was
built with `shared=true`.

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

A client of the revisions before 2026-07-28 knows nothing of this, so the server
asks in its place: the request goes out on the response stream, the reply comes
back as a POST or a line of its own, and the handler runs again with the answer.
The handler is written the same way for both. `Server::new` takes `ask_timeout_ms`
and `ask_rounds`, which bound the wait and the number of times one call may ask.

On stdio a client withdraws a request with `notifications/cancelled`; on
Streamable HTTP it closes the response stream, which the server notices the
next time it writes. Either way `Context::is_cancelled` answers.

## Completion

`Server::completion` answers `completion/complete`, and registering it is what
declares the capability.

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo")
  mcp.completion((request, _) => {
    {
      values: ["en", "fr"].filter(lang => lang.has_prefix(request.argument.value)),
      total: None,
      has_more: None,
    }
  })
}
```

## Conformance

The official [MCP conformance suite](https://github.com/modelcontextprotocol/conformance),
pinned at 0.1.16, runs in CI in both directions.

`scripts/interop/check_conformance.sh` drives the server in
`integration/src/07-conformance`: 42 server scenarios, the pending ones
included, every check passing.

`scripts/interop/check_client_conformance.sh` drives
`src/examples/08-conformance-client` through the 27 client scenarios: the
foundation ones, the fifteen of the authorization suite, the two older-revision
ones, the three drafts and the three extensions. 287 checks, every one passing.

| Client scenario | Checks |
|:--|--:|
| initialize, tools_call | 2 |
| elicitation-sep1034-client-defaults | 5 |
| sse-retry | 3 |
| auth/metadata-default, -var1, -var2, -var3 | 52 |
| auth/basic-cimd | 13 |
| auth/scope-from-www-authenticate, -scopes-supported, -omitted-when-undefined | 42 |
| auth/scope-step-up, auth/scope-retry-limit | 30 |
| auth/token-endpoint-auth-basic, -post, -none | 54 |
| auth/pre-registration | 13 |
| auth/2025-03-26-oauth-metadata-backcompat, -endpoint-fallback | 19 |
| auth/resource-mismatch, -offline-access-scope, -offline-access-not-supported | 29 |
| auth/client-credentials-jwt, -basic, auth/cross-app-access-complete-flow | 25 |

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

A transport is anything implementing `Transport`: `ask`, `tell`, `listen`,
`close`, and `answer_with`, which is where the requests the server makes of the
client go. `Memory`, `Lines` and `Http` ship here; a fourth is a hundred lines,
and the client above it does not change.

The server may ask the client for something while a call is in flight: a
completion (sampling), a form for the person in front of it (elicitation), the
roots it may read. `Client::connect(handlers=)` says what this client does about
each, and a request it does not serve is refused with the error JSON-RPC names.

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo")
  let client = @moonmcp.Client::connect(
    @moonmcp.Memory::new(mcp),
    handlers=@client.Handlers::new(
      elicitation=request => {
        // A real client shows `request.requested_schema` and returns what was filled in.
        println(request.message)
        @moonmcp.ElicitResult::accept(Map([]))
      },
    ),
  )
  client.close()
}
```

### Authorization

A server that answers `401` names where its metadata is; the client reads it,
registers, sends the user to authorize and exchanges the code for a token.
`Oauth` does that whole flow, and the HTTP transport calls it whenever the
server asks for a token it does not have.

```moonbit
async fn main {
  let oauth = @oauth.Oauth::new(
    resource_url="https://example.com/mcp",
    client_name="my-agent",
    redirect_uri="http://127.0.0.1:53682/callback",
    // Open a browser on this URL and listen on the redirect port for the
    // callback; give back the URL the browser was sent to, or "" if the person
    // gave up.
    present=url => {
      println("authorize: \{url}")
      ""
    },
  )
  let transport = @http.Http::new(
    "https://example.com/mcp",
    token=fn() { oauth.bearer() },
    renew=async fn(_status, challenge) {
      oauth.renew(challenge?=@moonmcp.Challenge::parse(challenge))
    },
  )
  let client = @moonmcp.Client::connect(transport)
  let tools = client.list_tools()
  println("\{tools.length()} tools")
  client.close()
}
```

What the flow does, in the order the specifications put it:

| Step | What is read or sent |
|:--|:--|
| Discovery | the protected resource metadata of RFC 9728, at the location the challenge named or under the endpoint's own path, then the authorization server metadata of RFC 8414, then OpenID Connect Discovery, then the endpoints of a server that publishes neither |
| Registration | dynamic registration (RFC 7591), a URL client identifier when the server advertises client metadata documents, or the credentials a deployment was given |
| Authorization | `response_type=code`, PKCE with S256, the scope the challenge named or the resource's own, and the resource indicator of RFC 8707 |
| Token | the code and its verifier, with the client authenticating by HTTP Basic, in the body, or not at all |
| Renewal | a second round when the server answers `403` with a scope this token does not carry, at most three times |

A resource whose metadata names another origin is refused before anything is
sent: the token would be minted for a server that is not this one. `Oauth`
also holds the client-credentials grant, and a signed JWT assertion for servers
that take `private_key_jwt`.

## Authorization

An endpoint that should not be open takes a bearer token: the header is checked
before the body is read, and a request without a good one is answered `401` with
the `WWW-Authenticate` challenge the specification asks for.

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo")
  let bearer = @moonmcp.Bearer::hmac(secret="s3cret")
  @mooncat.serve(mcp.to_asgi(auth=bearer), port=12000) catch {
    _ => ()
  }
}
```

`Bearer::hmac` verifies a token signed with a shared secret — the signature, the
expiry, and the issuer and audience when they are given. `Bearer::own` takes a
check of your own for everything else: an RSA or ECDSA key, a key set fetched
from the issuer, an opaque token looked up in a table.

A handler reads who called from its context; the claims are there too, as the
issuer wrote them:

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo")
  mcp.tool_context(
    "whoami",
    async fn(_args : Map[String, Json], context : @moonmcp.Context) {
      let subject = context.subject().unwrap_or("nobody")
      let role = match context.claims().get("role") {
        Some(String(role)) => role
        _ => "no role"
      }
      @moonmcp.ToolResult::new(content=[
        @moonmcp.text_block("\{subject} (\{role})"),
      ])
    },
  )
}
```

## Logging

A client's `logging/setLevel` holds back what is sent to it. It has no effect on
the server's own log, which keeps everything.

The server keeps no log of its own unless it is handed one. Given a structured
logger, it writes every request it served, every one it refused, and the lines a
handler asks for — `Context::log` writes there as well as sending
`notifications/message`, so a client that went away does not take the record
with it.

```moonbit
async fn main {
  let sink = @moonlog.Lines::new(fn(line) { println(line) })
  let hub = @moonlog.Hub::new()
  let slot = @moonlog.Slot::new(sink, name="console").layout(
    @moonlog.Pattern::parse("{level} {target}: {msg}"),
  )
  ignore(hub.add(slot) catch {
    e => abort("the log hub refused the slot: " + e.to_text())
  })
  let mcp = @moonmcp.Server::new("demo")
  mcp.log_to(logger=hub.logger("moonmcp"))
}
```

`Context::logger` hands a handler the same logger, scoped to its request, for
lines of its own.

## The documentation page

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
| [`demo`](src/examples/demo/) | One server with three tools, a resource, a resource template and a prompt; one tool reports progress |
| [`01-annotations`](src/examples/01-annotations/) | Tools, resources, a template and a prompt written as `#mcp.*` annotations, served over stdio |
| [`02-http`](integration/src/02-http/) | That server over Streamable HTTP, with the documentation page at `/docs`: `cd integration && moon run src/02-http --target native` |
| [`03-stdio`](src/examples/03-stdio/) | That server over stdio: `moon run src/examples/03-stdio --target native` |
| [`04-client`](src/examples/04-client/) | A client and a server in one program: list the tools, call one, print the progress it reports: `moon run src/examples/04-client --target native` |
| [`05-extensions`](src/examples/05-extensions/) | A provider, a namespace, a cache and a rate limiter on one server: `moon run src/examples/05-extensions --target native` |
| [`06-interop`](src/examples/06-interop/) | The client against a server written with the official TypeScript SDK, over Streamable HTTP and over a child's stdio: `moon run src/examples/06-interop --target native -- http <url>` |
| [`guide/ann`](src/examples/guide/ann/), [`guide/fns`](src/examples/guide/fns/), [`guide/cls`](src/examples/guide/cls/) | The same server written three ways; `guide/check` sends each request to all three and fails if one of them answers differently |
| [`08-conformance-client`](src/examples/08-conformance-client/) | The client the official conformance suite drives, one scenario per run |
| [`integration/`](integration/) | The examples that need a server to run them, and the server the conformance suite tests; a module of its own, so the library carries neither |
| [`08-conformance-client`](src/examples/08-conformance-client/) | The client the official conformance suite drives, one scenario per run |
| [`integration/`](integration/) | The examples that need a server to run them, and the server the conformance suite tests; a module of its own, so the library carries neither |

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
| `auth` | `Bearer` and `Principal`: the token an HTTP endpoint checks, verified through `mooncred`; and the metadata, PKCE, registration and scope rules a client follows to get one |
| `auth/oauth` | `Oauth`: the authorization-code flow over HTTP, the client-credentials grant and the JWT assertion; native only |
| `providers` | `Provider`: where capabilities come from when they are not registered one at a time, and `Listing` |
| `transforms` | `Transform`: what the client is shown, with `Namespace`, `Hidden` and `Tagged` |
| `layers` | `Layer`: the code every request passes through, with `Caching`, `RateLimiting` and `Telemetry` |
| `component`, `tasks`, `settings`, `config`, `utilities` | Component metadata, task configuration, settings, the `mcp.json` client configuration, media helpers |

## Install

```bash
moon add moonbitstack/moonmcp
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
