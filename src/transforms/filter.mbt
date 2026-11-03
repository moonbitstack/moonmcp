// Parts of a set held back from the client: a name that only some callers
// should see, or everything that does not carry the tag this deployment is
// for.

///|
/// Keep a component out of the listing, and out of reach: a call to a hidden
/// name is answered as an unknown one.
pub(all) struct Hidden {
  names : @set.Set[String]
}

///|
/// Hide the components named here — a tool or prompt name, a resource URI or
/// a template pattern.
pub fn Hidden::new(names~ : Array[String]) -> Hidden {
  { names: @set.Set::from_array(names), }
}

///|
/// Whether `name` is hidden.
pub fn Hidden::hides(self : Hidden, name : String) -> Bool {
  self.names.contains(name)
}

///|
pub impl Transform for Hidden with fn tools(self, tools) {
  tools.filter(fn(tool) { !self.hides(tool.component.name) })
}

///|
pub impl Transform for Hidden with fn prompts(self, prompts) {
  prompts.filter(fn(prompt) { !self.hides(prompt.component.name) })
}

///|
pub impl Transform for Hidden with fn resources(self, resources) {
  resources.filter(fn(resource) { !self.hides(resource.uri) })
}

///|
pub impl Transform for Hidden with fn templates(self, templates) {
  templates.filter(fn(template) { !self.hides(template.uri_template) })
}

///|
/// Offer only the components that carry one of these tags. A component without
/// tags is held back, since a set chosen by tag is a set of tagged things.
pub(all) struct Tagged {
  any_of : @set.Set[String]
}

///|
/// Keep the components tagged with any of `any_of`.
pub fn Tagged::new(any_of~ : Array[String]) -> Tagged {
  { any_of: @set.Set::from_array(any_of), }
}

///|
/// Whether a component carrying `tags` passes.
pub fn Tagged::keeps(self : Tagged, tags : @set.Set[String]) -> Bool {
  for tag in tags {
    if self.any_of.contains(tag) {
      return true
    }
  }
  false
}

///|
pub impl Transform for Tagged with fn tools(self, tools) {
  tools.filter(fn(tool) { self.keeps(tool.component.tags) })
}

///|
pub impl Transform for Tagged with fn prompts(self, prompts) {
  prompts.filter(fn(prompt) { self.keeps(prompt.component.tags) })
}

///|
pub impl Transform for Tagged with fn resources(self, resources) {
  resources.filter(fn(resource) { self.keeps(resource.component.tags) })
}

///|
pub impl Transform for Tagged with fn templates(self, templates) {
  templates.filter(fn(template) { self.keeps(template.component.tags) })
}

///|
pub extend Hidden with Transform::{tools, resources, templates, prompts}

///|
pub extend Tagged with Transform::{tools, resources, templates, prompts}
