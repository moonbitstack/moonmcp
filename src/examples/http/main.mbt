///|
/// The demo server over Streamable HTTP at `http://127.0.0.1:12000/mcp`, with
/// the documentation page beside it at `http://127.0.0.1:12000/docs`.
///
///     moon run src/examples/http --target native
async fn main {
  let mcp = @demo.server()
  @mooncat.serve(mcp.to_asgi(), port=12000) catch {
    e => println("stopped: \{e}")
  }
}
