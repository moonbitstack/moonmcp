// What a server can be extended with: components another object supplies, the
// way those components are shown, and the code every request passes through
// before it is served.

///|
/// Take components from `provider` as well as from the server's own registry.
/// The provider is asked again on every listing, so what it supplies may change
/// between two of them. A name this server already answers is not taken from a
/// provider.
pub fn Server::add_provider(
  self : Server,
  provider : &@providers.Provider,
) -> Unit {
  self.providers.push(provider)
}

///|
/// Apply `transform` to the components the server offers, in the order the
/// transforms were added: each one sees what the one before it produced.
pub fn Server::add_transform(
  self : Server,
  transform : &@transforms.Transform,
) -> Unit {
  self.transforms.push(transform)
}

///|
/// Put `layer` in front of every request: the first one added is the outermost,
/// so it sees a request before the ones after it and its answer last.
///
/// A layer that raises `@exceptions.Mcp` refuses the request with that code; a
/// layer that answers without calling on to the rest answers for the server.
pub fn Server::use_layer(self : Server, layer : @layers.Layer) -> Unit {
  self.layers.push(layer)
}

///|
/// The tools a client is offered: the registered ones, then whatever the
/// providers supply, as the transforms leave them.
pub fn Server::offered_tools(self : Server) -> Array[@tools.Tool] {
  self.view().0
}

///|
/// The resources a client is offered, after the transforms.
pub fn Server::offered_resources(self : Server) -> Array[@resources.Resource] {
  self.view().1
}

///|
/// The resource templates a client is offered, after the transforms.
pub fn Server::offered_templates(
  self : Server,
) -> Array[@resources.ResourceTemplate] {
  self.view().2
}

///|
/// The prompts a client is offered, after the transforms.
pub fn Server::offered_prompts(self : Server) -> Array[@prompts.Prompt] {
  self.view().3
}

///|
/// Everything the server offers, gathered from its registry and its providers
/// and then put through every transform. A name offered twice is taken from
/// whichever came first.
fn Server::view(
  self : Server,
) -> (
  Array[@tools.Tool],
  Array[@resources.Resource],
  Array[@resources.ResourceTemplate],
  Array[@prompts.Prompt],
) {
  let tools : Array[@tools.Tool] = []
  let resources : Array[@resources.Resource] = []
  let templates : Array[@resources.ResourceTemplate] = []
  let prompts : Array[@prompts.Prompt] = []
  let tool_names : Map[String, Unit] = Map([])
  let resource_uris : Map[String, Unit] = Map([])
  let template_patterns : Map[String, Unit] = Map([])
  let prompt_names : Map[String, Unit] = Map([])
  for tool in self.tools.values() {
    tool_names[tool.component.name] = ()
    tools.push(tool)
  }
  for resource in self.resources.values() {
    resource_uris[resource.uri] = ()
    resources.push(resource)
  }
  for template in self.templates {
    template_patterns[template.uri_template] = ()
    templates.push(template)
  }
  for prompt in self.prompts.values() {
    prompt_names[prompt.component.name] = ()
    prompts.push(prompt)
  }
  for provider in self.providers {
    for tool in provider.tools() {
      if !tool_names.contains(tool.component.name) {
        tool_names[tool.component.name] = ()
        tools.push(tool)
      }
    }
    for resource in provider.resources() {
      if !resource_uris.contains(resource.uri) {
        resource_uris[resource.uri] = ()
        resources.push(resource)
      }
    }
    for template in provider.templates() {
      if !template_patterns.contains(template.uri_template) {
        template_patterns[template.uri_template] = ()
        templates.push(template)
      }
    }
    for prompt in provider.prompts() {
      if !prompt_names.contains(prompt.component.name) {
        prompt_names[prompt.component.name] = ()
        prompts.push(prompt)
      }
    }
  }
  @transforms.apply(self.transforms, tools, resources, templates, prompts)
}

///|
/// The schema a tool's arguments are checked against. A tool that came from a
/// provider is compiled the first time it is called; one whose schema does not
/// compile is served without the check rather than failing the request.
fn Server::check_of(self : Server, tool : @tools.Tool) -> @moonschema.Schema? {
  let name = tool.component.name
  match self.checks.get(name) {
    Some(check) => Some(check)
    None => {
      let check = @moonschema.Schema::new(tool.parameters) catch {
        _ => return None
      }
      self.checks[name] = check
      Some(check)
    }
  }
}
