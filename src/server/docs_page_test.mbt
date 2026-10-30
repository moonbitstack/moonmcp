///|
/// The body the page sends for `op` in the era `era`: the same shape the page
/// builds in the browser, so a test can ask the endpoint what the page asks.
fn page_call(
  id : Int32,
  op : String,
  era : String,
) -> (Json, Array[(String, String)]) {
  let params : Map[String, Json] = if era == "2026-07-28" {
    {
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": Json(era),
        "io.modelcontextprotocol/clientCapabilities": Json::object(Map([])),
      },
    }
  } else {
    Map([])
  }
  let headers = [
    ("content-type", "application/json"),
    ("mcp-protocol-version", era),
  ]
  let headers = if era == "2026-07-28" {
    [..headers, ("mcp-method", op)]
  } else {
    headers
  }
  (request(id, op, params), headers)
}

///|
async test "the docs page is on at /docs, moves with docs=, and is off with None" {
  let client = @testing.Client::new(demo().to_asgi(docs=None))
  assert_eq(client.get("/docs").status, 404)
  let client = @testing.Client::new(demo().to_asgi(docs=Some("/debug")))
  assert_eq(client.get("/docs").status, 404)
  assert_eq(client.get("/debug").status, 200)
  assert_eq(client.get("/debug/").status, 200)
  assert_eq(client.get("/debugging").status, 404)
  let client = @testing.Client::new(demo().to_asgi())
  let got = client.get("/docs")
  assert_eq(got.status, 200)
  assert_eq(got.header("content-type"), Some("text/html; charset=utf-8"))
  assert_eq(got.header("cache-control"), Some("no-store"))
  assert_true(got.text().has_prefix("<!doctype html>"))
  // A docs path equal to the endpoint's is ignored, and the endpoint answers.
  let same = @testing.Client::new(demo().to_asgi(docs=Some("/mcp")))
  assert_eq(same.get("/mcp").status, 405)
}

///|
async test "the docs path takes GET and HEAD, and the endpoint keeps its own" {
  let client = @testing.Client::new(demo().to_asgi())
  let head = client.head("/docs")
  assert_eq(head.status, 200)
  assert_eq(head.body.length(), 0)
  assert_eq(head.header("content-type"), Some("text/html; charset=utf-8"))
  let posted = client.post("/docs", body=b"{}", headers=[
    ("content-type", "application/json"),
  ])
  assert_eq(posted.status, 405)
  assert_eq(posted.header("allow"), Some("GET, HEAD"))
  assert_eq(client.get("/mcp").status, 405)
  let listed = client.post(
    "/mcp",
    body=@utf8.encode(request(1, "tools/list", Map([])).stringify()),
    headers=[("content-type", "application/json")],
  )
  assert_eq(listed.status, 200)
}

///|
test "the page is told the endpoint to call, in JSON it cannot break out of" {
  assert_true(@docs.page().contains("{\"endpoint\":\"/mcp\"}"))
  assert_true(@docs.page(endpoint="/rpc").contains("{\"endpoint\":\"/rpc\"}"))
  assert_true(@docs.page(endpoint="a\"b").contains("{\"endpoint\":\"a\\\"b\"}"))
}

///|
test "the page carries both palettes and the headers the modern era asks for" {
  let page = @docs.page()
  let plain = @docs.page(theme=Plain)
  assert_true(page != plain)
  assert_true(plain.contains("prefers-color-scheme:dark"))
  assert_true(page.contains("prefers-color-scheme:dark"))
  assert_true(page.contains("[data-theme=dark]"))
  assert_true(page.contains("[data-theme=light]"))
  for header in ["mcp-protocol-version", "mcp-method", "mcp-name", "mcp-param-"] {
    assert_true(page.contains(header))
  }
  assert_false(page.contains("ENDPOINT_HERE"))
}

///|
async test "every listing the page asks for answers in both eras" {
  let client = @testing.Client::new(demo().to_asgi())
  for era in ["2026-07-28", "2025-11-25"] {
    for
      op in [
        "server/discover", "tools/list", "resources/list", "resources/templates/list",
        "prompts/list",
      ] {
      let (message, headers) = page_call(1, op, era)
      let got = client.post(
        "/mcp",
        body=@utf8.encode(message.stringify()),
        headers~,
      )
      assert_eq(got.status, 200)
      assert_true(got.text().contains("\"result\""))
    }
  }
}
