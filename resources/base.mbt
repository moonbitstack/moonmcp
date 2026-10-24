/// Resource content and result wrappers mirroring fastmcp/resources/base.py.

///|
/// The payload of a resource content item: inline text or raw bytes.
pub(all) enum ContentPayload {
  Text(String)
  Blob(Bytes)
} derive(Debug, Eq)

///|
/// A single resource content item with optional MIME type and metadata.
pub(all) struct ResourceContent {
  content : ContentPayload
  mime_type : String?
  meta : Map[String, Json]?
} derive(Debug, Eq)

///|
/// Create a resource content item, defaulting the MIME type by payload:
/// `text/plain` for text, `application/octet-stream` for bytes.
pub fn ResourceContent::new(
  content : ContentPayload,
  mime_type? : String,
  meta? : Map[String, Json],
) -> ResourceContent {
  let mime_type = match content {
    Text(_) => Some(mime_type.unwrap_or("text/plain"))
    Blob(_) => Some(mime_type.unwrap_or("application/octet-stream"))
  }
  { content, mime_type, meta, }
}

///|
/// Convert to the wire resource contents type; bytes are base64-encoded.
pub fn ResourceContent::to_mcp_resource_contents(
  self : ResourceContent,
  uri : String,
) -> @types.ResourceContents {
  match self.content {
    Text(text) => @types.Text(uri~, mime_type=self.mime_type, text~)
    Blob(data) =>
      @types.Blob(uri~, mime_type=self.mime_type, blob=@base64.encode(data))
  }
}

///|
/// The canonical result of a resource read.
pub(all) struct ResourceResult {
  contents : Array[ResourceContent]
  meta : Map[String, Json]?
  /// The client-input request when this read resolved to an input ask
  /// (SEP-2322); `contents` is always empty in that case.
  input_required : @types.InputRequiredResult?
} derive(Debug, Eq)

///|
/// Create a resource result from content items.
pub fn ResourceResult::new(
  contents : Array[ResourceContent],
  meta? : Map[String, Json],
) -> ResourceResult {
  { contents, meta, input_required: None, }
}

///|
/// Wrap a client-input ask (SEP-2322) as an ordinary resource result.
pub fn ResourceResult::input_required(
  input_required : @types.InputRequiredResult,
) -> ResourceResult {
  { contents: [], meta: None, input_required: Some(input_required), }
}

///|
/// Whether this result carries a client-input ask (SEP-2322).
pub fn ResourceResult::is_input_required(self : ResourceResult) -> Bool {
  self.input_required is Some(_)
}

///|
/// Convert to the wire read-resource result.
pub fn ResourceResult::to_mcp_result(
  self : ResourceResult,
  uri : String,
) -> @types.ReadResourceResult {
  {
    contents: self.contents.map(fn(item) { item.to_mcp_resource_contents(uri) }),
    cache_control: None,
    meta: self.meta,
  }
}

///|
/// What a resource read function may return: text, bytes or a full result.
pub(all) enum RawResourceValue {
  Text(String)
  Blob(Bytes)
  Ready(ResourceResult)
}

///|
/// Wrap a resource function's return value in a `ResourceResult`.
///
/// Shared by `Resource` and `ResourceTemplate` so both honour the MIME type
/// the component declares in listings: a component that advertises
/// `text/csv` must not serve `text/plain` on read.
pub fn convert_raw_to_resource_result(
  raw_value : RawResourceValue,
  mime_type? : String,
  meta? : Map[String, Json],
) -> ResourceResult {
  let public_meta = @component.public_result_meta(meta)
  match raw_value {
    Ready(result) => result
    Text(text) =>
      ResourceResult::new([
        ResourceContent::new(Text(text), mime_type?, meta?=public_meta),
      ])
    Blob(data) =>
      ResourceResult::new([
        ResourceContent::new(Blob(data), mime_type?, meta?=public_meta),
      ])
  }
}

///|
pub extend ContentPayload with Debug::{to_repr}

///|
pub extend ContentPayload with Eq::{not_equal, equal}

///|
pub extend ResourceContent with Debug::{to_repr}

///|
pub extend ResourceContent with Eq::{not_equal, equal}

///|
pub extend ResourceResult with Debug::{to_repr}

///|
pub extend ResourceResult with Eq::{not_equal, equal}
