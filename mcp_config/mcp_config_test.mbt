test "transport inference from url" {
  assert_eq(
    @mcp_config.infer_transport_type_from_url("https://example.com/sse"),
    Ok("sse"),
  )
  assert_eq(
    @mcp_config.infer_transport_type_from_url("https://example.com/sse?x=1"),
    Ok("sse"),
  )
  assert_eq(
    @mcp_config.infer_transport_type_from_url("https://example.com/mcp"),
    Ok("http"),
  )
  assert_eq(
    @mcp_config.infer_transport_type_from_url("https://example.com/sseserver"),
    Ok("http"),
  )
  assert_eq(
    @mcp_config.infer_transport_type_from_url("ftp://example.com"),
    Err("Invalid URL: ftp://example.com"),
  )
}

test "stdio server config round trips" {
  let config = @mcp_config.config_from_json(
    Json::object({
      "mcpServers": Json::object({
        "my-server": Json::object({
          "command": Json::string("npx"),
          "args": Json::array([
            Json::string("-y"),
            Json::string("@my/mcp-server"),
          ]),
          "env": Json::object({ "API_KEY": Json::string("secret") }),
          "timeout": Json::number(30000),
        }),
      }),
    }),
  )
  guard config.mcp_servers.get("my-server") is Some(entry) else {
    fail("expected server entry")
  }
  guard entry.kind is @mcp_config.Stdio(command~, args~, env~, ..) else {
    fail("expected stdio kind")
  }
  assert_eq(command, "npx")
  assert_eq(args, ["-y", "@my/mcp-server"])
  assert_eq(env.get("API_KEY"), Some(Json::string("secret")))
  assert_eq(entry.timeout, Some(30000))

  let json = @mcp_config.MCPConfig::to_json(config)
  let round_tripped = @mcp_config.config_from_json(json)
  assert_eq(round_tripped.mcp_servers.get("my-server"), Some(entry))
}

test "remote server config infers sse transport" {
  let config = @mcp_config.config_from_json(
    Json::object({
      "mcpServers": Json::object({
        "remote": Json::object({
          "url": Json::string("https://example.com/sse"),
          "headers": Json::object({ "X-Key": Json::string("v") }),
        }),
      }),
    }),
  )
  guard config.mcp_servers.get("remote") is Some(entry) else {
    fail("expected server entry")
  }
  guard entry.kind is @mcp_config.Remote(url~, transport~, headers~, ..) else {
    fail("expected remote kind")
  }
  assert_eq(url, "https://example.com/sse")
  assert_eq(transport, Some(@mcp_config.Sse))
  assert_eq(headers.get("X-Key"), Some("v"))
}

test "server configs at root wrap under mcpServers" {
  let config = @mcp_config.config_from_json(
    Json::object({
      "helper": Json::object({ "command": Json::string("uvx") }),
    }),
  )
  assert_eq(config.mcp_servers.size(), 1)
  assert_true(config.mcp_servers.contains("helper"))
}

test "transform fields decode into the server transform" {
  let config = @mcp_config.config_from_json(
    Json::object({
      "mcpServers": Json::object({
        "proxied": Json::object({
          "url": Json::string("https://example.com/mcp"),
          "includeTags": Json::array([Json::string("safe")]),
        }),
      }),
    }),
  )
  guard config.mcp_servers.get("proxied") is Some(entry) else {
    fail("expected server entry")
  }
  guard entry.transform is Some(transform) else { fail("expected transform") }
  assert_true(transform.include_tags.unwrap().contains("safe"))
  assert_true(transform.tools.is_empty())
}
