///|
async test "the server writes what it served and what it refused" {
  let sink = @moonlog.Memory::new()
  let hub = @moonlog.Hub::new(
    clock=fn() { 0L },
    filter=@moonlog.Filter::at(@moonlog.debug),
  )
  ignore(
    hub.add(
      @moonlog.Slot::new(sink, name="test").layout(
        @moonlog.Pattern::parse("{level} {target}: {msg}"),
      ),
    ) catch {
      e => fail("the log hub refused the slot: " + e.to_text())
    },
  )
  let mcp = demo()
  mcp.log_to(logger=hub.logger("moonmcp"))
  ignore(mcp.handle(modern(1, "tools/list")).unwrap())
  ignore(mcp.handle(modern(2, "no/such/method")).unwrap())
  let lines = sink.lines()
  assert_eq(lines.length() >= 2, true)
  let served = lines
    .iter()
    .find_first(fn(line : String) { line.contains("served") })
  assert_eq(served is Some(_), true)
  let refused = lines
    .iter()
    .find_first(fn(line : String) { line.contains("refused") })
  assert_eq(refused is Some(_), true)
  assert_eq(refused.unwrap().contains("no/such/method"), true)
}
