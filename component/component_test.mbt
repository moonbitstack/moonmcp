///|
test "make key prefixes the identifier" {
  assert_eq(@component.ComponentBase::make_key("tool", "add"), "tool:add")
  assert_eq(@component.ComponentBase::make_key("", "add"), "add")
}

///|
test "component key always carries the version delimiter" {
  let base = @component.ComponentBase::new("tool", "add", version="v2")
  assert_eq(base.key("add"), "tool:add@v2")
  let unversioned = @component.ComponentBase::new("resource", "x")
  assert_eq(unversioned.key("file://x.txt"), "resource:file://x.txt@")
}

///|
test "get meta merges sorted tags and version" {
  let base = @component.ComponentBase::new(
    "tool",
    "add",
    version="v2",
    tags=@set.Set::from_array(["beta", "alpha"]),
  )
  let meta = base.get_meta()
  guard meta.get("fastmcp") is Some(Object(fastmcp)) else {
    fail("expected fastmcp namespace")
  }
  assert_eq(
    fastmcp.get("tags"),
    Some(Json::array([Json::string("alpha"), Json::string("beta")])),
  )
  assert_eq(fastmcp.get("version"), Some(Json::string("v2")))
}

///|
test "get meta strips internal keys from the fastmcp namespace" {
  let base = @component.ComponentBase::new("tool", "add", meta={
    "fastmcp": Json::object(
      Map::from_array([
        ("_internal", Json::object({ "visibility": Json::string("private") })),
        ("custom", Json::string("kept")),
      ]),
    ),
  })
  let meta = base.get_meta()
  guard meta.get("fastmcp") is Some(Object(fastmcp)) else {
    fail("expected fastmcp namespace")
  }
  assert_eq(fastmcp.get("_internal"), None)
  assert_eq(fastmcp.get("custom"), Some(Json::string("kept")))
}

///|
test "public result meta strips bookkeeping and empty shells" {
  assert_eq(@component.public_result_meta(None), None)
  let stripped = @component.public_result_meta(
    Some({ "fastmcp": Json::object({ "_internal": Json::null() }) }),
  )
  assert_eq(stripped, None)
  let kept = @component.public_result_meta(
    Some({
      "fastmcp": Json::object({ "tags": Json::array([]) }),
      "other": Json::number(1),
    }),
  )
  guard kept is Some(obj) else { fail("expected public meta") }
  assert_eq(obj.get("other"), Some(Json::number(1)))
}

///|
test "fastmcp metadata falls back to the legacy namespace" {
  let meta : Map[String, Json] = {
    "_fastmcp": Json::object({
      "tags": Json::array([Json::string("a")]),
      "version": Json::string("v1"),
    }),
  }
  let metadata = @component.get_fastmcp_metadata(Some(meta))
  assert_eq(metadata.tags, ["a"])
  assert_eq(metadata.version, Some("v1"))
  assert_eq(@component.get_fastmcp_metadata(None).tags, [])
}

///|
test "coerce version accepts scalars and rejects the rest" {
  fn attempt(value : Json?) -> Result[String?, @exceptions.FastMCPError] {
    Ok(@component.coerce_version(value)) catch {
      e => Err(e)
    }
  }

  assert_eq(attempt(Some(Json::string("1.2"))), Ok(Some("1.2")))
  assert_eq(attempt(Some(Json::number(2))), Ok(Some("2")))
  assert_eq(attempt(None), Ok(None))
  assert_true(attempt(Some(Json::boolean(true))) is Err(_))
  assert_true(attempt(Some(Json::string("a@b"))) is Err(_))
}
