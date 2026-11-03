///|
/// The server, with the registered capabilities of `tools.mbt` on it.
pub fn server() -> @moonmcp.Server {
  let mcp = @moonmcp.Server::new("guide", version="1.0.0")
  register(mcp)
  mcp
}
