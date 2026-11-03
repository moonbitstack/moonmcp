// One server's components under a name of their own, so two servers or two
// mounts of the same set can be told apart by the client.

///|
/// Put everything a server offers under `prefix`: a tool or prompt `add`
/// becomes `prefix_add`, and a resource or template `users://{id}` becomes
/// `prefix+users://{id}` (the prefix joins the scheme, so the URI keeps its
/// shape and a template keeps its parameters).
///
/// `prefix` should be spelled the way a tool name is — letters, digits,
/// underscores and hyphens — since that is what prefixed tool names become.
pub(all) struct Namespace {
  prefix : String
}

///|
/// A namespace under `prefix`.
pub fn Namespace::new(prefix : String) -> Namespace {
  { prefix, }
}

///|
/// The name `name` takes inside the namespace.
pub fn Namespace::rename(self : Namespace, name : String) -> String {
  self.prefix + "_" + name
}

///|
/// The URI `uri` takes inside the namespace.
pub fn Namespace::rename_uri(self : Namespace, uri : String) -> String {
  self.prefix + "+" + uri
}

///|
pub impl Transform for Namespace with fn tools(self, tools) {
  tools.map(fn(tool) {
    let name = self.rename(tool.component.name)
    { ..tool, component: { ..tool.component, name, }, }
  })
}

///|
pub impl Transform for Namespace with fn prompts(self, prompts) {
  prompts.map(fn(prompt) {
    let name = self.rename(prompt.component.name)
    { ..prompt, component: { ..prompt.component, name, }, }
  })
}

///|
pub impl Transform for Namespace with fn resources(self, resources) {
  resources.map(fn(resource) {
    let uri = self.rename_uri(resource.uri)
    { ..resource, uri, }
  })
}

///|
pub impl Transform for Namespace with fn templates(self, templates) {
  templates.map(fn(template) {
    let pattern = self.rename_uri(template.uri_template)
    let name = if template.component.name == template.uri_template {
      pattern
    } else {
      template.component.name
    }
    {
      ..template,
      uri_template: pattern,
      // The pattern is matched piece by piece, so the pieces are read again.
      segments: @resources.parse_template(pattern),
      component: { ..template.component, name, },
    }
  })
}

///|
pub extend Namespace with Transform::{tools, resources, templates, prompts}
