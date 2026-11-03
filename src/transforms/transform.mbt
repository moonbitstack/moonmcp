// What a client is shown need not be what the program registered: a transform
// rewrites the components on their way out, so a server can present one set
// under a namespace, hide part of it, or hold a set back behind a tag.

///|
/// A rewrite of the components a server offers (← FastMCP's transforms).
///
/// The server applies every transform it was given to the whole set, in the
/// order they were added, each time the set is listed and before a call is
/// looked up. A transform therefore sees its predecessor's output: the order
/// is the meaning.
///
/// Every method has a default that leaves the set alone, so a transform
/// implements only the kinds it touches.
pub(open) trait Transform {
  fn tools(Self, Array[@tools.Tool]) -> Array[@tools.Tool] = _
  fn resources(Self, Array[@resources.Resource]) -> Array[@resources.Resource] = _
  fn templates(Self, Array[@resources.ResourceTemplate]) -> Array[
    @resources.ResourceTemplate,
  ] = _
  fn prompts(Self, Array[@prompts.Prompt]) -> Array[@prompts.Prompt] = _
}

///|
impl Transform with fn tools(_self, tools) {
  tools
}

///|
impl Transform with fn resources(_self, resources) {
  resources
}

///|
impl Transform with fn templates(_self, templates) {
  templates
}

///|
impl Transform with fn prompts(_self, prompts) {
  prompts
}

///|
/// Serve one set of components through every transform, in order.
pub fn apply(
  transforms : Array[&Transform],
  tools : Array[@tools.Tool],
  resources : Array[@resources.Resource],
  templates : Array[@resources.ResourceTemplate],
  prompts : Array[@prompts.Prompt],
) -> (
  Array[@tools.Tool],
  Array[@resources.Resource],
  Array[@resources.ResourceTemplate],
  Array[@prompts.Prompt],
) {
  let mut tools = tools
  let mut resources = resources
  let mut templates = templates
  let mut prompts = prompts
  for transform in transforms {
    tools = transform.tools(tools)
    resources = transform.resources(resources)
    templates = transform.templates(templates)
    prompts = transform.prompts(prompts)
  }
  (tools, resources, templates, prompts)
}
