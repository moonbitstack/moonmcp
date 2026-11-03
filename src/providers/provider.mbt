// A server's components need not be registered one call at a time: a provider
// hands over a set of them whenever it is asked, so what a server offers can
// come from a file, a directory, another server or a program's own state.

///|
/// Something that supplies components (← FastMCP's tool, resource and prompt
/// providers, under one contract).
///
/// A provider is asked for its components every time the server lists them, so
/// a set that changes between two listings is served as it stands at each
/// moment. The components it returns are served by name like registered ones;
/// a name two providers both use is answered by the one added first.
///
/// Every method has a default that supplies nothing, so a provider implements
/// only the kinds it has.
pub(open) trait Provider {
  fn tools(Self) -> Array[@tools.Tool] = _
  fn resources(Self) -> Array[@resources.Resource] = _
  fn templates(Self) -> Array[@resources.ResourceTemplate] = _
  fn prompts(Self) -> Array[@prompts.Prompt] = _
}

///|
impl Provider with fn tools(_self) {
  []
}

///|
impl Provider with fn resources(_self) {
  []
}

///|
impl Provider with fn templates(_self) {
  []
}

///|
impl Provider with fn prompts(_self) {
  []
}

///|
/// A fixed set of components, built once and handed over as it stands.
pub(all) struct Listing {
  tools : Array[@tools.Tool]
  resources : Array[@resources.Resource]
  templates : Array[@resources.ResourceTemplate]
  prompts : Array[@prompts.Prompt]
}

///|
/// A listing of whatever is given; the arrays are kept, not copied.
pub fn Listing::new(
  tools~ : Array[@tools.Tool] = [],
  resources~ : Array[@resources.Resource] = [],
  templates~ : Array[@resources.ResourceTemplate] = [],
  prompts~ : Array[@prompts.Prompt] = [],
) -> Listing {
  { tools, resources, templates, prompts, }
}

///|
pub impl Provider for Listing with fn tools(self) {
  self.tools
}

///|
pub impl Provider for Listing with fn resources(self) {
  self.resources
}

///|
pub impl Provider for Listing with fn templates(self) {
  self.templates
}

///|
pub impl Provider for Listing with fn prompts(self) {
  self.prompts
}

///|
pub extend Listing with Provider::{tools, resources, templates, prompts}
