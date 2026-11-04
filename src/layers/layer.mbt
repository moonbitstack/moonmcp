// What a layer sees, and the chain that puts one in front of another. A layer
// is a function that is handed a call and the rest of the chain, so it decides
// for itself whether the call goes on, is answered on the spot, or is refused.

///|
/// The request kinds a layer is asked about: the three that run a component,
/// and the four that list them.
#derive(Eq, Debug)
pub(all) enum Operation {
  ListTools
  ListResources
  ListTemplates
  ListPrompts
  CallTool
  ReadResource
  GetPrompt
}

///|
/// The JSON-RPC method an operation answers.
pub fn Operation::code(self : Operation) -> String {
  match self {
    ListTools => "tools/list"
    ListResources => "resources/list"
    ListTemplates => "resources/templates/list"
    ListPrompts => "prompts/list"
    CallTool => "tools/call"
    ReadResource => "resources/read"
    GetPrompt => "prompts/get"
  }
}

///|
/// Whether the operation lists components rather than running one.
pub fn Operation::is_list(self : Operation) -> Bool {
  match self {
    ListTools | ListResources | ListTemplates | ListPrompts => true
    _ => false
  }
}

///|
/// One request on its way through the chain: what it is, what it names, the
/// arguments it carries, and the request context it will be served in.
pub(all) struct Call {
  operation : Operation
  /// The tool or prompt name, the resource URI, or the empty string for a
  /// listing.
  name : String
  arguments : Map[String, Json]
  context : @context.Context
}

///|
/// The call a request makes.
pub fn Call::new(
  operation~ : Operation,
  name~ : String,
  arguments~ : Map[String, Json] = Map([]),
  context~ : @context.Context,
) -> Call {
  { operation, name, arguments, context, }
}

///|
/// Who is calling, as the authorisation check named them; empty when the
/// request carried no identity.
pub fn Call::subject(self : Call) -> String {
  self.context.subject().unwrap_or("")
}

///|
/// The arguments as one string: keys sorted at every depth, so two calls that
/// mean the same thing also spell the same thing. A cache keys on it, and a
/// rate limiter that counts by argument does too.
pub fn Call::fingerprint(self : Call) -> String {
  Json([
    Json::string(self.operation.code()),
    Json::string(self.name),
    Json::string(canonical(Json(self.arguments))),
  ]).stringify()
}

///|
/// One JSON value written with its object keys in lexicographic order.
fn canonical(value : Json) -> String {
  match value {
    Object(fields) => {
      let keys : Array[String] = fields.keys().collect()
      keys.sort_by(String::lexical_compare)
      let written = keys.map(key => {
        Json::string(key).stringify() + ":" + canonical(fields[key])
      })
      "{" + written.join(",") + "}"
    }
    Array(items) => "[" + items.map(canonical).join(",") + "]"
    _ => value.stringify()
  }
}

///|
/// The rest of the chain, as a layer is handed it.
pub(all) struct Next {
  priv run : async (Call) -> Json raise @exceptions.FastMCPError
}

///|
/// Serve the call with everything behind this point in the chain.
pub async fn Next::then(
  self : Next,
  call : Call,
) -> Json raise @exceptions.FastMCPError {
  (self.run)(call)
}

///|
/// One step of a chain (← FastMCP's middleware): a name for the logs and
/// spans, and the function that sees every call passing through it.
///
/// A layer may answer without going on, pass the call along with
/// `next.then(call)`, look at what came back, or refuse it by raising
/// `@exceptions.Mcp` with the code it wants sent.
pub(all) struct Layer {
  /// What the layer calls itself, for a log line or a span.
  name : String
  priv run : async (Call, Next) -> Json raise @exceptions.FastMCPError
}

///|
/// A layer made of a function.
pub fn Layer::new(
  name~ : String = "layer",
  run~ : async (Call, Next) -> Json raise @exceptions.FastMCPError,
) -> Layer {
  { name, run, }
}

///|
/// Serve the call through this layer alone, with `next` behind it.
pub async fn Layer::serve(
  self : Layer,
  call : Call,
  next : Next,
) -> Json raise @exceptions.FastMCPError {
  (self.run)(call, next)
}

///|
/// Serve `call` through `layers` in the order they were added, the first one
/// outermost, and `end` in the middle. An empty list calls `end` directly.
pub async fn chain(
  layers : Array[Layer],
  call : Call,
  end : async (Call) -> Json raise @exceptions.FastMCPError,
) -> Json raise @exceptions.FastMCPError {
  step(layers, 0, call, end)
}

///|
async fn step(
  layers : Array[Layer],
  index : Int32,
  call : Call,
  end : async (Call) -> Json raise @exceptions.FastMCPError,
) -> Json raise @exceptions.FastMCPError {
  if index >= layers.length() {
    return end(call)
  }
  let my = layers[index]
  let next : Next = {
    run: async fn(reached) -> Json raise @exceptions.FastMCPError {
      step(layers, index + 1, reached, end)
    },
  }
  my.serve(call, next)
}

///|
pub extend Operation with Eq::{equal, not_equal}

///|
pub extend Operation with Debug::{to_repr}
