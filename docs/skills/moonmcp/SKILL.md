---
name: moonmcp
description: Model Context Protocol servers and clients for MoonBit. Use it to expose tools, resources and prompts to an MCP client over stdio or Streamable HTTP, or to call another server from MoonBit, including servers that ask for an OAuth token.
---

# moonmcp

Servers register what they offer and hand the result to a transport; clients
speak the same protocol from the other end. Both eras of the specification are
served by one object: a request carrying its protocol version in `_meta` is
answered statelessly under 2026-07-28, and an `initialize` handshake selects the
revisions before it.

## Install

```bash
moon add moonbitstack/moonmcp
```

Import `moonbitstack/moonmcp` for the names a server is written with. Serving
over HTTP takes a server of its own — `moonbitstack/mooncat` — which is not a
dependency of this library:

```bash
moon add moonbitstack/mooncat
```

## A server of tools and resources

Register each capability on the server. A handler that returns a `Json` has its
result sent as `structuredContent`; one that returns a string sends it as text.

```moonbit native
async fn main {
  let mcp = @moonmcp.Server::new("demo", version="1.0.0")
  mcp.tool("add", args => {
    let a = match args.get("a") {
      Some(Number(value, ..)) => value
      _ => 0.0
    }
    let b = match args.get("b") {
      Some(Number(value, ..)) => value
      _ => 0.0
    }
    { "sum": Json(a + b) }
  }, description="Add two numbers")
  mcp.resource("config://app", () => "{\"theme\":\"dark\"}")
  mcp.run_stdio()
}
```

`moon run . --target native` is then a server any MCP client can start as a
child process.

Over HTTP, hand the same object to a server. The documentation page is served
at `/docs` unless told otherwise:

```moonbit native
async fn main {
  let mcp = @moonmcp.Server::new("demo", version="1.0.0")
  mcp.tool("ping", _ => { "pong": Json::string("pong") })
  @mooncat.serve(mcp.to_asgi(), port=12000) catch {
    e => println("stopped: \{e}")
  }
}
```

The endpoint is `http://127.0.0.1:12000/mcp`.

## Reach a server from MoonBit

`Client::connect` takes a transport. `Memory` reaches a server in the same
program, `Lines` a pair of line streams (a child's stdio), and `Http` an
endpoint:

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo")
  mcp.tool("add", args => { "ok": Json(true) })
  let client = @moonmcp.Client::connect(
    @moonmcp.Memory::new(mcp),
    protocol_version="2026-07-28",
  )
  let tools = client.list_tools()
  println("\{tools.length()} tools")
  let result = client.call_tool("add", arguments={ "a": 2 })
  println(result.is_error.to_string())
  client.close()
}
```

A server may ask the client for a completion, a form or the roots it may read.
Say what to do about each when connecting; anything left out is refused:

```moonbit
async fn main {
  let mcp = @moonmcp.Server::new("demo")
  let client = @moonmcp.Client::connect(
    @moonmcp.Memory::new(mcp),
    handlers=@client.Handlers::new(
      elicitation=_request => @moonmcp.ElicitResult::accept(Map([])),
    ),
  )
  client.close()
}
```

## A server behind OAuth

`Oauth` reads the metadata the server's `401` points at, registers, sends the
user to authorize, and exchanges the code. The HTTP transport calls it whenever
the server asks for a token the client does not have.

`renew` is what the transport calls, and it spends a refresh token before it
opens a browser: the authorization server has to list `offline_access` for one
to be issued at all, and a challenge that asks for a scope this token was never
granted still goes through the person, because a refresh may not widen one.

```moonbit native
async fn main {
  let oauth = @oauth.Oauth::new(
    resource_url="https://example.com/mcp",
    client_name="my-agent",
    redirect_uri="http://127.0.0.1:53682/callback",
    // Open a browser here and listen on the redirect port; answer with the URL
    // the browser was sent to, or "" when the person gave up.
    present=_url => "",
  )
  let transport = @http.Http::new(
    "https://example.com/mcp",
    token=fn() { oauth.bearer() },
    renew=async fn(_status, challenge) {
      oauth.renew(challenge?=@moonmcp.Challenge::parse(challenge))
    },
  )
  let client = @moonmcp.Client::connect(transport)
  println("\{client.list_tools().length()} tools")
  client.close()
}
```

## Tracing

`@otel.Tracing::new(tracer~, now~).layer()` opens one server span per request,
named `tools/call add` and tagged as the OpenTelemetry conventions for MCP ask.
The parent comes from `params._meta` — `traceparent` and `tracestate` — before
the request headers are read, so a call over stdio joins its caller's trace too;
a broken context starts a new trace instead of refusing the request. A handler
reads the whole object with `Context::meta()`. It is a package of its own,
imported by nothing in the root package, so a program that does not trace
carries no tracing library. `@otel/export` posts the spans over OTLP/HTTP and
is native and wasm only; the tracer takes any sink instead.

## Rules that catch people out

- Register before serving, not while a request runs. A registration that cannot
  work aborts: an invalid tool name, a schema that does not compile, a template
  that does not parse.
- A failing tool is a result with `isError`, which the model reads and can
  correct; only an unknown tool is a protocol error. To stop a call outright,
  raise `@exceptions.Mcp` with the code you want.
- Tool arguments are validated against the schema before the handler runs; a
  mismatch comes back as `isError` with the path of the field.
- A `traceparent` in `params._meta` wins over the `traceparent` header. The two
  sources are never mixed: when `_meta` supplies the parent, a `tracestate` in
  the headers is ignored. Over stdio there are no headers at all.
- `for { }` is not an infinite loop in MoonBit; write `while true`.
- `method`, `local` and `move` are reserved words, so a parameter of your own
  cannot be called `method`.
- The annotations (`#mcp.tool`, `#mcp.resource`, `#mcp.prompt`) need the
  generator wired in once: a `rule` in `moon.mod` and a `dev_build` line in the
  package's `moon.pkg`. Without them the functions compile and nothing is
  registered.
