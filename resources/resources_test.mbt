///|
test "path traversal detection rejects dot segments only" {
  assert_true(@resources.contains_path_traversal("../etc/passwd"))
  assert_true(@resources.contains_path_traversal("a/../../b"))
  assert_true(@resources.contains_path_traversal("..\\windows"))
  assert_false(@resources.contains_path_traversal("HEAD~3..HEAD"))
  assert_false(@resources.contains_path_traversal("v1..v2"))
  assert_false(@resources.contains_path_traversal("file.tar.gz"))
}

///|
test "absolute path detection" {
  assert_true(@resources.is_absolute_path("/etc/passwd"))
  assert_true(@resources.is_absolute_path("\\\\server\\share"))
  assert_true(@resources.is_absolute_path("C:\\\\Users"))
  assert_true(@resources.is_absolute_path("D:/data"))
  assert_false(@resources.is_absolute_path("relative/path"))
  assert_false(@resources.is_absolute_path("./here"))
}

///|
test "resource security screens extracted params" {
  let policy = @resources.ResourceSecurity::default()
  assert_eq(
    policy.validate({ "path": Json::string("../../etc/passwd") }),
    Some("path"),
  )
  assert_eq(policy.validate({ "path": Json::string("safe/path.txt") }), None)
  assert_eq(policy.validate({ "n": Json::string("a\u{0}b") }), Some("n"))
  // Non-string values are ignored.
  assert_eq(policy.validate({ "n": Json::number(3) }), None)
}

///|
test "resource security honours exempt params" {
  let policy : @resources.ResourceSecurity = {
    reject_path_traversal: true,
    reject_absolute_paths: true,
    reject_null_bytes: true,
    exempt_params: @set.Set::from_array(["git-ref"]),
  }
  assert_eq(policy.validate({ "git_ref": Json::string("HEAD~3..HEAD") }), None)
  assert_eq(
    policy.validate({ "other": Json::string("../etc/passwd") }),
    Some("other"),
  )
}

///|
test "resolve security follows the component setting" {
  let server_default = @resources.ResourceSecurity::default()
  assert_true(
    @resources.resolve_security(@resources.Inherit, Some(server_default))
    is Some(_),
  )
  assert_true(@resources.resolve_security(@resources.Inherit, None) is None)
  assert_true(
    @resources.resolve_security(@resources.Disabled, Some(server_default))
    is None,
  )
}

///|
test "query parameter extraction handles explode modifiers" {
  let template = "weather://{city}/current{?units,tags*}"
  assert_eq(@resources.extract_query_params(template), ["units", "tags"])
  assert_eq(@resources.extract_exploded_query_params(template), ["tags"])
  assert_eq(@resources.parse_template_params(template).length() >= 2, true)
}

///|
test "encode literal keeps reserved chars and triplets" {
  assert_eq(@resources.encode_literal("a b"), "a%20b")
  assert_eq(@resources.encode_literal("a/b"), "a/b")
  assert_eq(@resources.encode_literal("a%20b"), "a%20b")
  assert_eq(@resources.encode_literal("caf\u00e9"), "caf%C3%A9")
}

///|
test "pct encode respects the safe set" {
  assert_eq(@resources.pct_encode("a/b"), "a%2Fb")
  assert_eq(@resources.pct_encode("a/b", safe="/"), "a/b")
}

///|
test "match uri template extracts path params" {
  let params = @resources.match_uri_template(
    "weather://london/current", "weather://{city}/current",
  )
  guard params is Some(params) else { fail("expected match") }
  assert_eq(params.get("city"), Some(Json::string("london")))
}

///|
test "match uri template rejects wrong shape" {
  assert_true(
    @resources.match_uri_template(
      "weather://london/forecast", "weather://{city}/current",
    )
    is None,
  )
  assert_true(
    @resources.match_uri_template(
      "weather://london/current/extra", "weather://{city}/current",
    )
    is None,
  )
}

///|
test "match uri template wildcards span segments" {
  let params = @resources.match_uri_template(
    "files://docs/a/b/c.txt", "files://docs/{path*}",
  )
  guard params is Some(params) else { fail("expected match") }
  assert_eq(params.get("path"), Some(Json::string("a/b/c.txt")))
}

///|
test "match uri template accepts percent-encoded literals" {
  let params = @resources.match_uri_template(
    "files://my%20docs/readme.txt", "files://my docs/{name}",
  )
  guard params is Some(params) else { fail("expected match") }
  assert_eq(params.get("name"), Some(Json::string("readme.txt")))
}

///|
test "match uri template decodes captured values" {
  let params = @resources.match_uri_template(
    "files://docs/hello%20world.txt", "files://docs/{name}",
  )
  guard params is Some(params) else { fail("expected match") }
  assert_eq(params.get("name"), Some(Json::string("hello world.txt")))
}

///|
test "match uri template extracts scalar query params" {
  let params = @resources.match_uri_template(
    "weather://london/current?units=metric", "weather://{city}/current{?units}",
  )
  guard params is Some(params) else { fail("expected match") }
  assert_eq(params.get("city"), Some(Json::string("london")))
  assert_eq(params.get("units"), Some(Json::string("metric")))
}

///|
test "match uri template collects exploded query params" {
  let params = @resources.match_uri_template(
    "weather://london/current?tags=a&tags=b", "weather://{city}/current{?tags*}",
  )
  guard params is Some(params) else { fail("expected match") }
  assert_eq(
    params.get("tags"),
    Some(Json::array([Json::string("a"), Json::string("b")])),
  )
}

///|
test "match uri template splits list query params on commas" {
  let params = @resources.match_uri_template(
    "weather://london/current?tags=a%2Cb,b",
    "weather://{city}/current{?tags}",
    list_params=["tags"],
  )
  guard params is Some(params) else { fail("expected match") }
  assert_eq(
    params.get("tags"),
    Some(Json::array([Json::string("a,b"), Json::string("b")])),
  )
}

///|
test "match uri template keeps blank query values" {
  let params = @resources.match_uri_template(
    "weather://london/current?units=", "weather://{city}/current{?units}",
  )
  guard params is Some(params) else { fail("expected match") }
  assert_eq(params.get("units"), Some(Json::string("")))
}

///|
test "match uri template strips fragments" {
  let params = @resources.match_uri_template(
    "files://docs/a.txt#section", "files://docs/{name}",
  )
  guard params is Some(params) else { fail("expected match") }
  assert_eq(params.get("name"), Some(Json::string("a.txt")))
}

///|
test "expand uri template substitutes and encodes" {
  let expanded = @resources.expand_uri_template("weather://{city}/current", {
    "city": Json::string("new york"),
  })
  assert_eq(expanded, "weather://new%20york/current")
}

///|
test "expand uri template keeps slashes in wildcard params" {
  let expanded = @resources.expand_uri_template("files://docs/{path*}", {
    "path": Json::string("a/b/c.txt"),
  })
  assert_eq(expanded, "files://docs/a/b/c.txt")
}

///|
test "expand uri template expands query blocks" {
  let expanded = @resources.expand_uri_template(
    "weather://{city}/current{?units,tags*}",
    {
      "city": Json::string("london"),
      "units": Json::string("metric"),
      "tags": Json::array([Json::string("a"), Json::string("b")]),
    },
  )
  assert_eq(expanded, "weather://london/current?units=metric&tags=a&tags=b")
}

///|
test "expand accepts hyphenated template spellings" {
  let expanded = @resources.expand_uri_template("weather://{user-id}", {
    "user_id": Json::string("42"),
  })
  assert_eq(expanded, "weather://42")
}

///|
test "expand and match round trip" {
  let template = "weather://{city}/current{?units}"
  let params : Map[String, Json] = {
    "city": Json::string("cape town"),
    "units": Json::string("imperial"),
  }
  let expanded = @resources.expand_uri_template(template, params)
  let matched = @resources.match_uri_template(expanded, template)
  guard matched is Some(matched) else { fail("expected round trip") }
  assert_eq(matched.get("city"), Some(Json::string("cape town")))
  assert_eq(matched.get("units"), Some(Json::string("imperial")))
}

///|
test "forward uri carries the query byte for byte" {
  let forwarded = @resources.forward_uri(
    "weather://{city}/current{?units}",
    { "city": Json::string("london") },
    "weather://london/current?units=metric&tags=a%2Cb,b",
  )
  assert_eq(forwarded, "weather://london/current?units=metric&tags=a%2Cb,b")
}

///|
test "resource reads text content with declared mime" {
  let resource = @resources.Resource::text(
    "data://greeting",
    text="hello world",
    mime_type="text/csv",
  )
  assert_eq(resource.uri, "data://greeting")
  assert_eq(@component.Component::key(resource), "resource:data://greeting@")
  let result = resource.read_result()
  assert_eq(result.contents.length(), 1)
  assert_eq(result.contents[0].mime_type, Some("text/csv"))
  let wire = result.to_mcp_result("data://greeting")
  guard wire.contents[0] is @types.Text(text~, ..) else {
    fail("expected text contents")
  }
  assert_eq(text, "hello world")
}

///|
test "resource binary content round trips base64" {
  let payload = Bytes::from_array([0, 1, 2])
  let resource = @resources.Resource::binary("data://blob", data=payload)
  let result = resource.read_result()
  guard result.contents[0].content is @resources.Blob(_) else {
    fail("expected blob")
  }
  let wire = result.to_mcp_result("data://blob")
  guard wire.contents[0] is @types.Blob(blob~, ..) else {
    fail("expected blob contents")
  }
  assert_eq(blob, "AAEC")
}

///|
test "resource from function reads dynamically" {
  let resource = @resources.Resource::from_function("data://dynamic", read_fn=fn() {
    @resources.RawResourceValue::Text("computed")
  })
  let result = resource.read_result()
  assert_eq(result.contents[0].mime_type, Some("text/plain"))
  assert_eq(resource.to_mcp_resource().name, "data://dynamic")
}

///|
test "template matches and blocks traversal" {
  let template = @resources.ResourceTemplate::new(
    "files://docs/{path}",
    parameters=Json::object({}),
    read_fn=_ => @resources.RawResourceValue::Text("content"),
  )
  guard template.matches("files://docs/readme.txt", None) is Some(_) else {
    fail("expected match")
  }
  // A literal traversal payload does not even match the `[^/]+` pattern.
  assert_true(template.matches("files://docs/../../etc/passwd", None) is None)
  // An encoded traversal matches and is then blocked by screening.
  let blocked : Result[Map[String, Json]?, @exceptions.FastMCPError] = Ok(
    template.matches(
      "files://docs/%2E%2E%2Fetc%2Fpasswd",
      Some(@resources.ResourceSecurity::default()),
    ),
  ) catch {
    e => Err(e)
  }
  assert_true(blocked is Err(_))
  assert_eq(
    template.read_result("files://docs/readme.txt", {
      "path": Json::string("readme.txt"),
    }).contents[0].mime_type,
    Some("text/plain"),
  )
}

///|
test "template creates concrete resources" {
  let template = @resources.ResourceTemplate::new(
    "weather://{city}/current{?units}",
    parameters=Json::object({}),
    read_fn=_ => @resources.RawResourceValue::Text("sunny"),
  )
  let resource = template.create_resource("weather://london/current", {
    "city": Json::string("london"),
  })
  assert_eq(resource.uri, "weather://london/current")
  let result = resource.read_result()
  assert_eq(result.contents[0].mime_type, Some("text/plain"))
  let wire = template.to_mcp_template()
  assert_eq(wire.uri_template, "weather://{city}/current{?units}")
}

///|
test "template requires at least one parameter" {
  let built : Result[@resources.ResourceTemplate, @exceptions.FastMCPError] = Ok(
    @resources.ResourceTemplate::new(
      "weather://static",
      parameters=Json::object({}),
      read_fn=fn(_) { @resources.RawResourceValue::Text("x") },
    ),
  ) catch {
    e => Err(e)
  }
  assert_true(built is Err(_))
}
