///|
/// A set of arithmetic tools kept in one object: the work in its methods, the
/// state in its fields, the registration in one `impl`.
pub struct Arithmetic {
  priv mut calls : Int32
}

///|
fn Arithmetic::add(
  self : Arithmetic,
  a : Double,
  b : Double,
) -> @tools.ToolResult raise @exceptions.FastMCPError {
  self.calls = self.calls + 1
  @tools.ToolResult::new(content=[@types.text_block("\{a + b}")])
}

///|
impl @providers.Provider for Arithmetic with fn tools(self) {
  [
    @tools.Tool::new(
      "add",
      parameters={
        "type": "object",
        "properties": { "a": { "type": "number" }, "b": { "type": "number" } },
        "required": ["a", "b"],
      },
      run_fn=args => {
        let a = match args.get("a") {
          Some(Number(value, ..)) => value
          _ => 0.0
        }
        let b = match args.get("b") {
          Some(Number(value, ..)) => value
          _ => 0.0
        }
        self.add(a, b)
      },
    ) catch {
      e => abort("add: \{e}")
    },
  ]
}

///|
/// The server: the object's tools under a prefix, a cache in front of them, and
/// a ceiling of two calls a second for each caller.
pub fn server() -> @moonmcp.Server {
  let mcp = @moonmcp.Server::new("extensions", version="1.0.0")
  mcp.add_provider(Arithmetic::{ calls: 0, })
  mcp.add_transform(@transforms.Namespace::new("bench"))
  mcp.use_layer(@layers.RateLimiting::new(rate=2, burst=4).layer())
  mcp.use_layer(@layers.Caching::new(ttl_ms=5_000).layer())
  mcp
}

///|
async fn main {
  server().run_stdio()
}
