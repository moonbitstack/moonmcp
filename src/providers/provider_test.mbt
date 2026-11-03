///|
/// The answer a test tool gives, or the error it raises when it has no name.
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
fn tool(name : String) -> @tools.Tool {
  @tools.Tool::new(name, parameters={ "type": "object" }, run_fn=async fn(
    _arguments,
  ) -> @tools.ToolResult raise @exceptions.FastMCPError {
    answer(name)
  }) catch {
    _ => abort("the test tool does not build")
  }
}

///|
struct OnlyTools {
  tool : @tools.Tool
}

///|
pub impl @providers.Provider for OnlyTools with fn tools(self) {
  [self.tool]
}

///|
test "a listing hands over the components it was given" {
  let listing = @providers.Listing::new(tools=[tool("add"), tool("sum")])
  let provider : &@providers.Provider = listing
  assert_eq(provider.tools().length(), 2)
  assert_eq(provider.tools()[0].component.name, "add")
  assert_eq(provider.resources().length(), 0)
  assert_eq(provider.templates().length(), 0)
  assert_eq(provider.prompts().length(), 0)
}

///|
test "a provider implements only the kinds it has" {
  let provider : &@providers.Provider = OnlyTools::{ tool: tool("add"), }
  assert_eq(provider.tools().length(), 1)
  assert_eq(provider.prompts().length(), 0)
}
