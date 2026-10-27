///|
/// The demo server over stdio, for a client that starts it as a subprocess.
///
///     moon run src/examples/stdio --target native
async fn main {
  let mcp = @demo.server()
  mcp.run_stdio()
}
