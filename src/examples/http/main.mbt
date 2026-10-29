///|
/// The demo server over Streamable HTTP at `http://127.0.0.1:12000/mcp`, with
/// the debug page beside it at `http://127.0.0.1:12000/debug`.
///
///     moon run src/examples/http --target native
async fn main {
  let mcp = @demo.server()
  @mooncat.serve(mcp.to_asgi(debug_page="/debug"), port=12000) catch {
    e => println("stopped: \{e}")
  }
}
