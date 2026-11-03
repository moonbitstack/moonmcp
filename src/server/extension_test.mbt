///|
/// The answer of a counting tool.
#warnings("-unused_async")
async fn counted_answer(
  calls : Array[String],
  name : String,
  arguments : Map[String, Json],
) -> @tools.ToolResult raise @exceptions.FastMCPError {
  calls.push(name)
  let n = match arguments.get("n") {
    Some(Number(value, ..)) => value.to_int()
    _ => 0
  }
  @tools.ToolResult::new(content=[@types.text_block("\{name} \{n}")])
}

///|
/// A tool that counts how often it ran.
fn counted_tool(calls : Array[String], name : String) -> @tools.Tool {
  @tools.Tool::new(
    name,
    parameters={ "type": "object", "properties": { "n": { "type": "number" } } },
    run_fn=async fn(
      arguments,
    ) -> @tools.ToolResult raise @exceptions.FastMCPError {
      counted_answer(calls, name, arguments)
    },
  ) catch {
    _ => abort("the test tool does not build")
  }
}

///|
/// The names in the listing a reply carries under `key`.
fn listed_names(reply : Json, key : String) -> Array[String] {
  guard reply is Object(o) &&
    o.get("result") is Some(Object(result)) &&
    result.get(key) is Some(Array(items)) else {
    return []
  }
  items.filter_map(fn(item) {
    if item is Object(fields) && fields.get("name") is Some(String(name)) {
      Some(name)
    } else {
      None
    }
  })
}

///|
/// The text of the first content block of a call result.
fn answer_text(reply : Json) -> String {
  guard reply is Object(o) &&
    o.get("result") is Some(Object(result)) &&
    result.get("content") is Some(Array(blocks)) &&
    blocks.length() > 0 &&
    blocks[0] is Object(block) &&
    block.get("text") is Some(String(text)) else {
    return ""
  }
  text
}

///|
/// The text of the first content item of a read.
fn read_text(reply : Json) -> String {
  guard reply is Object(o) &&
    o.get("result") is Some(Object(result)) &&
    result.get("contents") is Some(Array(contents)) &&
    contents.length() > 0 &&
    contents[0] is Object(item) &&
    item.get("text") is Some(String(text)) else {
    return ""
  }
  text
}

///|
/// The error code a reply carries, or zero when it carries a result.
fn error_code(reply : Json) -> Int32 {
  match dig(reply, ["error", "code"]) {
    Some(Number(value, ..)) => value.to_int()
    _ => 0
  }
}

///|
async test "a provider's tool is listed and called" {
  let calls : Array[String] = []
  let mcp = @server.Server::new("extended", version="1.0.0")
  mcp.add_provider(
    @providers.Listing::new(tools=[counted_tool(calls, "counted")]),
  )
  let listed = mcp.handle(modern(1, "tools/list")) catch { _ => None }
  assert_eq(listed_names(listed.unwrap(), "tools").join(","), "counted")
  let called = mcp.handle(
    modern(2, "tools/call", params={
      "name": "counted",
      "arguments": { "n": 3 },
    }),
  ) catch {
    _ => None
  }
  assert_eq(answer_text(called.unwrap()), "counted 3")
  assert_eq(calls.length(), 1)
}

///|
async test "the server's own tool wins over a provider's of the same name" {
  let mcp = @server.Server::new("extended", version="1.0.0")
  mcp.add_provider(@providers.Listing::new(tools=[counted_tool([], "counted")]))
  mcp.tool("counted", _args => Json("mine"), description="mine")
  let called = mcp.handle(
    modern(1, "tools/call", params={ "name": "counted", "arguments": {} }),
  ) catch {
    _ => None
  }
  assert_eq(answer_text(called.unwrap()), "mine")
}

///|
async test "a namespace renames what is listed and what is called" {
  let calls : Array[String] = []
  let mcp = @server.Server::new("extended", version="1.0.0")
  mcp.add_provider(
    @providers.Listing::new(tools=[counted_tool(calls, "counted")]),
  )
  mcp.add_transform(@transforms.Namespace::new("bench"))
  let listed = mcp.handle(modern(1, "tools/list")) catch { _ => None }
  assert_eq(listed_names(listed.unwrap(), "tools").join(","), "bench_counted")
  let called = mcp.handle(
    modern(2, "tools/call", params={ "name": "bench_counted", "arguments": {} }),
  ) catch {
    _ => None
  }
  assert_eq(answer_text(called.unwrap()), "counted 0")
  let unknown = mcp.handle(
    modern(3, "tools/call", params={ "name": "counted", "arguments": {} }),
  ) catch {
    _ => None
  }
  assert_eq(error_code(unknown.unwrap()), -32602)
  assert_eq(calls.length(), 1)
}

///|
async test "a namespaced template is read under its new URI" {
  let mcp = @server.Server::new("extended", version="1.0.0")
  mcp.template("users://{id}/profile", params => {
    match params.get("id") {
      Some(String(id)) => "profile of " + id
      _ => "nobody"
    }
  })
  mcp.add_transform(@transforms.Namespace::new("bench"))
  let read = mcp.handle(
    modern(1, "resources/read", params={ "uri": "bench+users://42/profile" }),
  ) catch {
    _ => None
  }
  assert_eq(read_text(read.unwrap()), "profile of 42")
  let old = mcp.handle(
    modern(2, "resources/read", params={ "uri": "users://42/profile" }),
  ) catch {
    _ => None
  }
  assert_eq(error_code(old.unwrap()), -32602)
}

///|
async test "a hidden component cannot be listed or called" {
  let mcp = @server.Server::new("extended", version="1.0.0")
  mcp.tool("open", _args => Json("open"))
  mcp.tool("closed", _args => Json("closed"))
  mcp.add_transform(@transforms.Hidden::new(names=["closed"]))
  let listed = mcp.handle(modern(1, "tools/list")) catch { _ => None }
  assert_eq(listed_names(listed.unwrap(), "tools").join(","), "open")
}

///|
async test "a cache layer answers the second identical call without running the tool" {
  let calls : Array[String] = []
  let cache = @layers.Caching::new()
  let mcp = @server.Server::new("extended", version="1.0.0")
  mcp.tool("counted", _args => Json("counted"))
  let counted = counted_tool(calls, "counted_too")
  mcp.add_provider(@providers.Listing::new(tools=[counted]))
  mcp.use_layer(cache.layer())
  for id in [1, 2] {
    let called = mcp.handle(
      modern(id, "tools/call", params={ "name": "counted_too", "arguments": {} }),
    ) catch {
      _ => None
    }
    assert_eq(answer_text(called.unwrap()), "counted_too 0")
  }
  assert_eq(calls.length(), 1)
  assert_eq(cache.hits(), 1)
}

///|
async test "a rate limit layer refuses over the wire with its own code" {
  let mcp = @server.Server::new("extended", version="1.0.0")
  mcp.tool("counted", _args => Json("counted"))
  mcp.use_layer(@layers.RateLimiting::new(rate=1, burst=1).layer())
  let first = mcp.handle(
    modern(1, "tools/call", params={ "name": "counted", "arguments": {} }),
  ) catch {
    _ => None
  }
  assert_eq(answer_text(first.unwrap()), "counted")
  let second = mcp.handle(
    modern(2, "tools/call", params={ "name": "counted", "arguments": {} }),
  ) catch {
    _ => None
  }
  assert_eq(error_code(second.unwrap()), -32000)
  // A token is a second away, less whatever has already run off the clock.
  let retry_ms = match dig(second.unwrap(), ["error", "data", "retryAfterMs"]) {
    Some(Number(value, ..)) => value.to_int()
    _ => 0
  }
  assert_true(retry_ms >= 900 && retry_ms <= 1000)
}

///|
async test "a layer answers with the code it was given for a failing tool" {
  let mcp = @server.Server::new("extended", version="1.0.0")
  mcp.tool("broken", _args => raise @exceptions.Tool("no"))
  let telemetry = @layers.Telemetry::new()
  mcp.use_layer(telemetry.layer())
  let called = mcp.handle(
    modern(1, "tools/call", params={ "name": "broken", "arguments": {} }),
  ) catch {
    _ => None
  }
  assert_eq(dig(called.unwrap(), ["result", "isError"]), Some(Json(true)))
  assert_eq(telemetry.total(), 1)
  assert_false(telemetry.spans()[0].failed)
}

///|
async test "layers run in the order they were added" {
  let calls : Array[String] = []
  let inner_cache = @layers.Caching::new()
  let inner_telemetry = @layers.Telemetry::new()
  let outer_cache = @layers.Caching::new()
  let outer_telemetry = @layers.Telemetry::new()

  let cached_first = @server.Server::new("cached first", version="1.0.0")
  cached_first.add_provider(
    @providers.Listing::new(tools=[counted_tool(calls, "counted")]),
  )
  cached_first.use_layer(inner_cache.layer())
  cached_first.use_layer(inner_telemetry.layer())

  let counted_first = @server.Server::new("counted first", version="1.0.0")
  counted_first.add_provider(
    @providers.Listing::new(tools=[counted_tool(calls, "counted")]),
  )
  counted_first.use_layer(outer_telemetry.layer())
  counted_first.use_layer(outer_cache.layer())

  for mcp in [cached_first, counted_first] {
    for id in [1, 2] {
      ignore(
        mcp.handle(
          modern(id, "tools/call", params={ "name": "counted", "arguments": {} }),
        ) catch {
          _ => None
        },
      )
    }
  }
  // The cache outside the recorder answers the second call before it is seen.
  assert_eq(inner_telemetry.total(), 1)
  // The recorder outside the cache sees both.
  assert_eq(outer_telemetry.total(), 2)
  assert_eq(calls.length(), 2)
}
