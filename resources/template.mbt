/// The resource template component mirroring fastmcp/resources/template.py.
///
/// Python's function-introspection machinery (`FunctionResourceTemplate`)
/// maps to a template carrying a read closure plus the JSON schema of its
/// parameters, supplied at registration time.

///|
/// A template for dynamically creating resources.
pub(all) struct ResourceTemplate {
  component : @component.ComponentBase
  uri_template : String
  mime_type : String
  /// JSON schema for the read function's parameters.
  parameters : Json
  annotations : @types.Annotations?
  security : ResourceSecuritySetting
  /// Non-exploded `{?name}` query parameters whose value is a list.
  list_query_params : @set.Set[String]
  segments : Array[TemplateSegment]
  read_fn : (Map[String, Json]) -> RawResourceValue raise @exceptions.FastMCPError
}

///|
pub impl @component.Component for ResourceTemplate with fn base(self) {
  self.component
}

///|
pub impl @component.Component for ResourceTemplate with fn identifier(self) {
  self.uri_template
}

///|
pub impl @component.Component for ResourceTemplate with fn key(self) {
  let base_key = @component.ComponentBase::make_key(
    self.component.key_prefix,
    self.uri_template,
  )
  "\{base_key}@\{self.component.version.unwrap_or("")}"
}

///|
pub impl @component.Component for ResourceTemplate with fn get_meta(self) {
  self.component.get_meta()
}

///|
/// Resolve the effective security policy for this template.
pub fn ResourceTemplate::resolve_security(
  self : ResourceTemplate,
  server_default : ResourceSecurity?,
) -> ResourceSecurity? {
  resolve_security(self.security, server_default)
}

///|
/// Register a resource template; `read_fn` receives the parameters matched
/// from the request URI.
pub fn ResourceTemplate::new(
  uri_template : String,
  parameters~ : Json,
  read_fn~ : (Map[String, Json]) -> RawResourceValue raise @exceptions.FastMCPError,
  name? : String,
  version? : String,
  title? : String,
  description? : String,
  icons? : Array[@types.Icon],
  mime_type~ : String = "text/plain",
  tags~ : @set.Set[String] = @set.Set::from_array([]),
  meta? : Map[String, Json],
  annotations? : @types.Annotations,
  security~ : ResourceSecuritySetting = Inherit,
  list_query_params~ : @set.Set[String] = @set.Set::from_array([]),
) -> ResourceTemplate raise @exceptions.FastMCPError {
  let all_params = parse_template_params(uri_template)
  if all_params.is_empty() {
    raise @exceptions.Validation(
      "URI template must contain at least one parameter",
    )
  }
  {
    component: @component.ComponentBase::new(
      "template",
      name.unwrap_or(uri_template),
      version?,
      title?,
      description?,
      icons?,
      tags~,
      meta?,
    ),
    uri_template,
    mime_type,
    parameters,
    annotations,
    security,
    list_query_params,
    segments: parse_template(uri_template),
    read_fn,
  }
}

///|
/// All parameter names a template declares, hyphens normalised to
/// underscores, path and query parameters combined.
pub fn parse_template_params(uri_template : String) -> @set.Set[String] {
  let names : Array[String] = []
  for name in extract_query_params(uri_template) {
    names.push(name.replace(old="-", new="_"))
  }
  for segment in parse_template(uri_template) {
    match segment {
      PathVar(name~, ..) => names.push(name.replace(old="-", new="_"))
      Literal(_) => ()
    }
  }
  @set.Set::from_array(names)
}

///|
/// Check if a URI matches this template and extract its parameters,
/// screening extracted values against the effective security policy.
pub fn ResourceTemplate::matches(
  self : ResourceTemplate,
  uri : String,
  security : ResourceSecurity?,
) -> Map[String, Json]? raise @exceptions.FastMCPError {
  let list_params : Array[String] = if uri.contains("?") {
    self.list_query_params.to_array()
  } else {
    []
  }
  guard match_uri_template(
      uri,
      self.uri_template,
      list_params~,
      segments=self.segments,
    )
    is Some(params) else {
    return None
  }
  match security {
    Some(policy) =>
      match policy.validate(params) {
        Some(_) =>
          // Surfaced as "not found" so a traversal attempt is
          // indistinguishable from a request for a missing resource.
          raise @exceptions.ResourceSecurity("Blocked by resource security")
        None => Some(params)
      }
    None => Some(params)
  }
}

///|
/// Read the resource content with the matched parameters.
pub fn ResourceTemplate::read(
  self : ResourceTemplate,
  arguments : Map[String, Json],
) -> RawResourceValue raise @exceptions.FastMCPError {
  (self.read_fn)(arguments)
}

///|
/// Convert a raw result to a `ResourceResult`, forwarding the template's
/// declared MIME type so reads match what it advertises in listings.
pub fn ResourceTemplate::convert_result(
  self : ResourceTemplate,
  raw_value : RawResourceValue,
) -> ResourceResult {
  convert_raw_to_resource_result(
    raw_value,
    mime_type=self.mime_type,
    meta?=self.component.meta,
  )
}

///|
/// Server entry point for template reads.
pub fn ResourceTemplate::read_result(
  self : ResourceTemplate,
  _uri : String,
  params : Map[String, Json],
) -> ResourceResult raise @exceptions.FastMCPError {
  self.convert_result(self.read(params))
}

///|
/// Create a concrete resource from the template for the given parameters.
pub fn ResourceTemplate::create_resource(
  self : ResourceTemplate,
  uri : String,
  params : Map[String, Json],
) -> Resource {
  let read_fn = self.read_fn
  let captured = params.copy()
  let name = self.component.name
  let description = self.component.description
  let mime_type = self.mime_type
  let tags = self.component.tags
  let meta = self.component.meta
  let title = self.component.title
  let icons = self.component.icons
  let annotations = self.annotations
  Resource::new(
    uri,
    read_fn=() => read_fn(captured),
    name~,
    description?,
    mime_type~,
    tags~,
    meta?,
    title?,
    icons?,
    annotations?,
  )
}

///|
/// Convert the template to its wire representation.
pub fn ResourceTemplate::to_mcp_template(
  self : ResourceTemplate,
) -> @types.ResourceTemplate {
  {
    uri_template: self.uri_template,
    name: self.component.name,
    title: self.component.title,
    description: self.component.description,
    mime_type: Some(self.mime_type),
    annotations: self.annotations,
    meta: Some(ResourceTemplate::get_meta(self)),
  }
}

///|
/// Create a template from a raw wire template, for remote servers whose
/// original function is lost.
pub fn ResourceTemplate::from_mcp_template(
  mcp_template : @types.ResourceTemplate,
) -> ResourceTemplate raise @exceptions.FastMCPError {
  ResourceTemplate::new(
    mcp_template.uri_template,
    parameters=Json::object({}),
    read_fn=_ => {
      raise @exceptions.Resource("Remote templates cannot be read locally")
    },
    name=mcp_template.name,
    description?=mcp_template.description,
    mime_type=mcp_template.mime_type.unwrap_or("text/plain"),
  )
}

///|
pub extend ResourceTemplate with @component.Component::{
  base,
  identifier,
  key,
  get_meta,
}
