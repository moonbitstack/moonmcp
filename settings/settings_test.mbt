///|
test "settings defaults mirror fastmcp" {
  let settings = @settings.Settings::new()
  assert_eq(settings.log_enabled, true)
  assert_eq(settings.log_level, @settings.Info)
  assert_eq(settings.transport, @settings.Stdio)
  assert_eq(settings.host, "127.0.0.1")
  assert_eq(settings.port, 8000)
  assert_eq(settings.sse_path, "/sse")
  assert_eq(settings.streamable_http_path, "/mcp")
  assert_eq(settings.client_disconnect_timeout, 5)
  assert_eq(settings.telemetry_mode, @settings.Native)
  assert_eq(settings.http_session_idle_timeout, @settings.Auto)
  assert_eq(settings.show_server_banner, true)
  assert_eq(settings.check_for_updates, @settings.Stable)
}

///|
test "settings apply environment overrides" {
  @env.set_env_var("FASTMCP_PORT", "9000")
  @env.set_env_var("FASTMCP_LOG_ENABLED", "false")
  @env.set_env_var("FASTMCP_LOG_LEVEL", "warning")
  @env.set_env_var("FASTMCP_HTTP_ALLOWED_HOSTS", "a.example,b.example")
  @env.set_env_var("FASTMCP_HTTP_SESSION_IDLE_TIMEOUT", "none")
  let settings = @settings.Settings::from_env()
  @env.unset_env_var("FASTMCP_PORT")
  @env.unset_env_var("FASTMCP_LOG_ENABLED")
  @env.unset_env_var("FASTMCP_LOG_LEVEL")
  @env.unset_env_var("FASTMCP_HTTP_ALLOWED_HOSTS")
  @env.unset_env_var("FASTMCP_HTTP_SESSION_IDLE_TIMEOUT")
  assert_eq(settings.port, 9000)
  assert_false(settings.log_enabled)
  assert_eq(settings.log_level, @settings.Warning)
  assert_eq(settings.http_allowed_hosts, Some(["a.example", "b.example"]))
  assert_eq(settings.http_session_idle_timeout, @settings.Never)
}

///|
test "log level wire conversion is case-insensitive" {
  assert_eq(@settings.log_level_from_wire("debug"), Some(@settings.Debug))
  assert_eq(@settings.log_level_from_wire("Info"), Some(@settings.Info))
  assert_eq(@settings.log_level_from_wire("bogus"), None)
  assert_eq(
    @settings.telemetry_mode_from_wire("propagation_only"),
    Some(@settings.PropagationOnly),
  )
}
