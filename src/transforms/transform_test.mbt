///|
/// The answer a test tool gives.
#warnings("-unused_async")
async fn answer(
  name : String,
) -> @tools.ToolResult raise @exceptions.FastMCPError {
  if name.is_empty() {
    raise @exceptions.Tool("a tool with no name")
  }
  @tools.ToolResult::new(content=[@types.text_block(name)])
}

///|
/// The body a test resource serves.
#warnings("-unused_async")
async fn body(
  text : String,
) -> @resources.RawResourceValue raise @exceptions.FastMCPError {
  if text.is_empty() {
    raise @exceptions.Resource("an empty body")
  }
  Text(text)
}

///|
fn tool(name : String, tags~ : Array[String] = []) -> @tools.Tool {
  @tools.Tool::new(
    name,
    parameters={ "type": "object" },
    run_fn=async fn(
      _arguments,
    ) -> @tools.ToolResult raise @exceptions.FastMCPError {
      answer(name)
    },
    tags=@set.Set::from_array(tags),
  ) catch {
    _ => abort("the test tool does not build")
  }
}

///|
fn resource(uri : String, tags~ : Array[String] = []) -> @resources.Resource {
  @resources.Resource::new(
    uri,
    read_fn=async fn() -> @resources.RawResourceValue raise @exceptions.FastMCPError {
      body("body")
    },
    tags=@set.Set::from_array(tags),
  )
}

///|
fn template(pattern : String) -> @resources.ResourceTemplate {
  @resources.ResourceTemplate::new(pattern, parameters={ "type": "object" }, read_fn=async fn(
    _arguments,
  ) -> @resources.RawResourceValue raise @exceptions.FastMCPError {
    body("body")
  }) catch {
    _ => abort("the test template does not build")
  }
}

///|
test "a namespace prefixes tool names, and puts itself in the scheme" {
  let mount = @transforms.Namespace::new("bench")
  let tools = mount.tools([tool("add")])
  assert_eq(tools[0].component.name, "bench_add")
  let resources_ = mount.resources([resource("config://app")])
  assert_eq(resources_[0].uri, "bench+config://app")
}

///|
test "a namespaced template keeps its parameters and still matches" {
  let mount = @transforms.Namespace::new("bench")
  let templates = mount.templates([template("users://{id}/profile")])
  let rewritten = templates[0]
  assert_eq(rewritten.uri_template, "bench+users://{id}/profile")
  assert_eq(rewritten.component.name, "bench+users://{id}/profile")
  let matched = rewritten.matches("bench+users://42/profile", None) catch {
    _ => None
  }
  guard matched is Some(arguments) else {
    abort("the namespaced template does not match its own URI")
  }
  assert_eq(arguments.get("id"), Some(Json::string("42")))
}

///|
test "a hidden name is dropped from every kind" {
  let hidden = @transforms.Hidden::new(names=["add", "config://app"])
  let kept = hidden.tools([tool("add"), tool("sum")])
  assert_eq(kept.length(), 1)
  assert_eq(kept[0].component.name, "sum")
  assert_eq(
    hidden
    .resources([resource("config://app"), resource("config://other")])
    .length(),
    1,
  )
}

///|
test "a tagged set keeps only what carries one of its tags" {
  let tagged = @transforms.Tagged::new(any_of=["public"])
  let kept = tagged.tools([
    tool("add", tags=["public"]),
    tool("secret", tags=["internal"]),
    tool("bare"),
  ])
  assert_eq(kept.length(), 1)
  assert_eq(kept[0].component.name, "add")
}

///|
test "the order of two transforms is the meaning" {
  let tools = [tool("add")]
  let mount = @transforms.Namespace::new("bench")
  let hidden = @transforms.Hidden::new(names=["add"])
  let namespace_then_hide = @transforms.apply([mount, hidden], tools, [], [], [])
  // Hidden looks for `add`, which the namespace has already renamed.
  assert_eq(namespace_then_hide.0.length(), 1)
  assert_eq(namespace_then_hide.0[0].component.name, "bench_add")
  let hide_then_namespace = @transforms.apply([hidden, mount], tools, [], [], [])
  assert_eq(hide_then_namespace.0.length(), 0)
}

///|
test "no transform at all leaves the set alone" {
  let tools = [tool("add")]
  let kept = @transforms.apply([], tools, [], [], [])
  assert_eq(kept.0.length(), 1)
  assert_eq(kept.0[0].component.name, "add")
}
