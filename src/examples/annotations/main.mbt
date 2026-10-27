///|
/// The annotated functions in `tools.mbt`, registered by the generated
/// `register` and served over stdio.
///
///     moon run src/examples/annotations --target native
async fn main {
  let mcp = @moonmcp.Server::new("annotated", version="1.0.0")
  register(mcp)
  mcp.run_stdio()
}
