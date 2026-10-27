/// The resource component mirroring fastmcp/resources/base.py and
/// fastmcp/resources/types.py.
///
/// Python's concrete subclasses (TextResource, BinaryResource, FileResource,
/// HttpResource, DirectoryResource) map to factory functions supplying a
/// read closure. File-, HTTP- and directory-backed resources need native
/// IO and are deferred to the transport layer.

///|
/// A registered resource.
pub(all) struct Resource {
  component : @component.ComponentBase
  uri : String
  mime_type : String
  annotations : @types.Annotations?
  read_fn : async () -> RawResourceValue raise @exceptions.FastMCPError
}

///|
pub impl @component.Component for Resource with fn base(self) {
  self.component
}

///|
pub impl @component.Component for Resource with fn identifier(self) {
  self.uri
}

///|
pub impl @component.Component for Resource with fn key(self) {
  let base_key = @component.ComponentBase::make_key(
    self.component.key_prefix,
    self.uri,
  )
  "\{base_key}@\{self.component.version.unwrap_or("")}"
}

///|
pub impl @component.Component for Resource with fn get_meta(self) {
  self.component.get_meta()
}

///|
/// Register a resource at `uri`. The name defaults to the URI when absent.
pub fn Resource::new(
  uri : String,
  read_fn~ : async () -> RawResourceValue raise @exceptions.FastMCPError,
  name? : String,
  version? : String,
  title? : String,
  description? : String,
  icons? : Array[@types.Icon],
  mime_type~ : String = "text/plain",
  tags~ : @set.Set[String] = @set.Set::from_array([]),
  meta? : Map[String, Json],
  annotations? : @types.Annotations,
) -> Resource {
  {
    component: @component.ComponentBase::new(
      "resource",
      name.unwrap_or(uri),
      version?,
      title?,
      description?,
      icons?,
      tags~,
      meta?,
    ),
    uri,
    mime_type,
    annotations,
    read_fn,
  }
}

///|
/// A resource backed by inline text.
pub fn Resource::text(
  uri : String,
  text~ : String,
  name? : String,
  version? : String,
  title? : String,
  description? : String,
  icons? : Array[@types.Icon],
  mime_type~ : String = "text/plain",
  tags~ : @set.Set[String] = @set.Set::from_array([]),
  meta? : Map[String, Json],
  annotations? : @types.Annotations,
) -> Resource {
  Resource::new(
    uri,
    read_fn=() => Text(text),
    name?,
    version?,
    title?,
    description?,
    icons?,
    mime_type~,
    tags~,
    meta?,
    annotations?,
  )
}

///|
/// A resource backed by inline bytes.
pub fn Resource::binary(
  uri : String,
  data~ : Bytes,
  name? : String,
  version? : String,
  title? : String,
  description? : String,
  icons? : Array[@types.Icon],
  mime_type~ : String = "application/octet-stream",
  tags~ : @set.Set[String] = @set.Set::from_array([]),
  meta? : Map[String, Json],
  annotations? : @types.Annotations,
) -> Resource {
  Resource::new(
    uri,
    read_fn=() => Blob(data),
    name?,
    version?,
    title?,
    description?,
    icons?,
    mime_type~,
    tags~,
    meta?,
    annotations?,
  )
}

///|
/// A resource backed by a closure computing its value on read.
pub fn Resource::from_function(
  uri : String,
  read_fn~ : async () -> RawResourceValue raise @exceptions.FastMCPError,
  name? : String,
  version? : String,
  title? : String,
  description? : String,
  icons? : Array[@types.Icon],
  mime_type~ : String = "text/plain",
  tags~ : @set.Set[String] = @set.Set::from_array([]),
  meta? : Map[String, Json],
  annotations? : @types.Annotations,
) -> Resource {
  Resource::new(
    uri,
    read_fn~,
    name?,
    version?,
    title?,
    description?,
    icons?,
    mime_type~,
    tags~,
    meta?,
    annotations?,
  )
}

///|
/// Read the resource content.
pub async fn Resource::read(
  self : Resource,
) -> RawResourceValue raise @exceptions.FastMCPError {
  (self.read_fn)()
}

///|
/// Convert a raw result to a `ResourceResult`, forwarding this resource's
/// declared MIME type and component metadata to each content item.
pub fn Resource::convert_result(
  self : Resource,
  raw_value : RawResourceValue,
) -> ResourceResult {
  convert_raw_to_resource_result(
    raw_value,
    mime_type=self.mime_type,
    meta?=self.component.meta,
  )
}

///|
/// Server entry point for resource reads.
pub async fn Resource::read_result(
  self : Resource,
) -> ResourceResult raise @exceptions.FastMCPError {
  self.convert_result(self.read())
}

///|
/// Convert the resource to its wire representation.
pub fn Resource::to_mcp_resource(self : Resource) -> @types.Resource {
  {
    uri: self.uri,
    name: self.component.name,
    title: self.component.title,
    description: self.component.description,
    mime_type: Some(self.mime_type),
    size: None,
    annotations: self.annotations,
    meta: Some(Resource::get_meta(self)),
  }
}

///|
pub extend Resource with @component.Component::{base, identifier, key, get_meta}
