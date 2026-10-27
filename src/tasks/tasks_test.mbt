///|
test "task config from bool" {
  assert_eq(@tasks.TaskConfig::from_bool(true).mode, @tasks.Optional)
  assert_eq(@tasks.TaskConfig::from_bool(false).mode, @tasks.Forbidden)
}

///|
test "supports tasks excludes forbidden" {
  assert_true(@tasks.TaskConfig::new(mode=Optional).supports_tasks())
  assert_true(@tasks.TaskConfig::new(mode=Required).supports_tasks())
  assert_false(@tasks.TaskConfig::new(mode=Forbidden).supports_tasks())
}

///|
test "defaults mirror fastmcp" {
  assert_eq(@tasks.default_poll_interval_ms, 5000)
  assert_eq(@tasks.default_ttl_ms, 60000)
  assert_eq(@tasks.tasks_extension_id, "io.modelcontextprotocol/tasks")
}
