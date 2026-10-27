/// Content blocks exchanged over the wire.

///|
/// Audience and priority hints attached to content.
pub(all) struct Annotations {
  audience : Array[String]?
  priority : Double?
} derive(Debug, Eq)

///|
pub impl ToJson for Annotations with fn to_json(self : Annotations) -> Json {
  let obj : Map[String, Json] = Map([])
  put_opt_array(
    obj,
    "audience",
    self.audience.map(fn(a) { a.map(Json::string) }),
  )
  if self.priority is Some(p) {
    put_opt_double(obj, "priority", p)
  }
  Json(obj)
}

///|
pub impl FromJson for Annotations with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Annotations raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "Annotations")
  {
    audience: opt_str_array(obj, path, "audience"),
    priority: opt_double(obj, path, "priority"),
  }
}

///|
/// The contents of a resource, either inline text or base64-encoded bytes.
pub(all) enum ResourceContents {
  Text(uri~ : String, mime_type~ : String?, text~ : String)
  Blob(uri~ : String, mime_type~ : String?, blob~ : String)
} derive(Debug, Eq)

///|
pub fn ResourceContents::uri(self : ResourceContents) -> String {
  match self {
    Text(uri~, ..) => uri
    Blob(uri~, ..) => uri
  }
}

///|
pub impl ToJson for ResourceContents with fn to_json(self : ResourceContents) -> Json {
  let obj : Map[String, Json] = Map([])
  match self {
    Text(uri~, mime_type~, text~) => {
      put_str(obj, "uri", uri)
      put_opt_str(obj, "mimeType", mime_type)
      put_str(obj, "text", text)
    }
    Blob(uri~, mime_type~, blob~) => {
      put_str(obj, "uri", uri)
      put_opt_str(obj, "mimeType", mime_type)
      put_str(obj, "blob", blob)
    }
  }
  Json(obj)
}

///|
pub impl FromJson for ResourceContents with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ResourceContents raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ResourceContents")
  let uri = req_str(obj, path, "ResourceContents", "uri")
  let mime_type = opt_str(obj, path, "mimeType")
  if obj.get("text") is Some(String(text)) {
    return Text(uri~, mime_type~, text~)
  }
  if obj.get("blob") is Some(String(blob)) {
    return Blob(uri~, mime_type~, blob~)
  }
  raise decode_error(path, "ResourceContents: missing text or blob")
}

///|
/// A block of content in a tool result, sampling message or prompt message.
pub(all) enum ContentBlock {
  /// Plain text content.
  Text(text~ : String, annotations~ : Annotations?, meta~ : Map[String, Json]?)
  /// Base64-encoded image content.
  Image(
    data~ : String,
    mime_type~ : String,
    annotations~ : Annotations?,
    meta~ : Map[String, Json]?
  )
  /// Base64-encoded audio content.
  Audio(
    data~ : String,
    mime_type~ : String,
    annotations~ : Annotations?,
    meta~ : Map[String, Json]?
  )
  /// A link to a resource the client should read separately.
  ResourceLink(
    uri~ : String,
    name~ : String,
    title~ : String?,
    description~ : String?,
    mime_type~ : String?,
    size~ : Int32?,
    annotations~ : Annotations?,
    meta~ : Map[String, Json]?
  )
  /// A resource embedded directly in the content.
  EmbeddedResource(
    resource~ : ResourceContents,
    annotations~ : Annotations?,
    meta~ : Map[String, Json]?
  )
} derive(Debug, Eq)

///|
/// Shorthand for a plain text block without annotations.
pub fn text_block(text : String) -> ContentBlock {
  Text(text~, annotations=None, meta=None)
}

///|
pub impl ToJson for ContentBlock with fn to_json(self : ContentBlock) -> Json {
  let obj : Map[String, Json] = Map([])
  fn put_annotations(block_annotations : Annotations?) -> Unit {
    put_opt_json(
      obj,
      "annotations",
      block_annotations.map(Annotations::to_json),
    )
  }

  fn put_meta(block_meta : Map[String, Json]?) -> Unit {
    put_opt_map(obj, "_meta", block_meta)
  }

  match self {
    Text(text~, annotations~, meta~) => {
      put_str(obj, "type", "text")
      put_str(obj, "text", text)
      put_annotations(annotations)
      put_meta(meta)
    }
    Image(data~, mime_type~, annotations~, meta~) => {
      put_str(obj, "type", "image")
      put_str(obj, "data", data)
      put_str(obj, "mimeType", mime_type)
      put_annotations(annotations)
      put_meta(meta)
    }
    Audio(data~, mime_type~, annotations~, meta~) => {
      put_str(obj, "type", "audio")
      put_str(obj, "data", data)
      put_str(obj, "mimeType", mime_type)
      put_annotations(annotations)
      put_meta(meta)
    }
    ResourceLink(
      uri~,
      name~,
      title~,
      description~,
      mime_type~,
      size~,
      annotations~,
      meta~
    ) => {
      put_str(obj, "type", "resource_link")
      put_str(obj, "uri", uri)
      put_str(obj, "name", name)
      put_opt_str(obj, "title", title)
      put_opt_str(obj, "description", description)
      put_opt_str(obj, "mimeType", mime_type)
      put_opt_int(obj, "size", size)
      put_annotations(annotations)
      put_meta(meta)
    }
    EmbeddedResource(resource~, annotations~, meta~) => {
      put_str(obj, "type", "resource")
      put_opt_json(obj, "resource", Some(ResourceContents::to_json(resource)))
      put_annotations(annotations)
      put_meta(meta)
    }
  }
  Json(obj)
}

///|
pub impl FromJson for ContentBlock with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> ContentBlock raise @json.JsonDecodeError {
  let obj = expect_obj(json, path, "ContentBlock")
  fn annotations() -> Annotations? raise @json.JsonDecodeError {
    match obj.get("annotations") {
      Some(value) => Some(@json.from_json(value))
      None => None
    }
  }

  let block_type = req_str(obj, path, "ContentBlock", "type")
  match block_type {
    "text" =>
      Text(
        text=req_str(obj, path, "ContentBlock", "text"),
        annotations=annotations(),
        meta=opt_obj(obj, path, "_meta"),
      )
    "image" =>
      Image(
        data=req_str(obj, path, "ContentBlock", "data"),
        mime_type=req_str(obj, path, "ContentBlock", "mimeType"),
        annotations=annotations(),
        meta=opt_obj(obj, path, "_meta"),
      )
    "audio" =>
      Audio(
        data=req_str(obj, path, "ContentBlock", "data"),
        mime_type=req_str(obj, path, "ContentBlock", "mimeType"),
        annotations=annotations(),
        meta=opt_obj(obj, path, "_meta"),
      )
    "resource_link" =>
      ResourceLink(
        uri=req_str(obj, path, "ContentBlock", "uri"),
        name=req_str(obj, path, "ContentBlock", "name"),
        title=opt_str(obj, path, "title"),
        description=opt_str(obj, path, "description"),
        mime_type=opt_str(obj, path, "mimeType"),
        size=opt_int(obj, path, "size"),
        annotations=annotations(),
        meta=opt_obj(obj, path, "_meta"),
      )
    "resource" =>
      EmbeddedResource(
        resource=@json.from_json(obj.get("resource").unwrap_or(Json::null())),
        annotations=annotations(),
        meta=opt_obj(obj, path, "_meta"),
      )
    _ => raise decode_error(path, "ContentBlock: unknown type \{block_type}")
  }
}

///|
pub extend Annotations with @json.FromJson::{from_json}

///|
pub extend Annotations with Debug::{to_repr}

///|
pub extend Annotations with Eq::{not_equal, equal}

///|
pub extend Annotations with ToJson::{to_json}

///|
pub extend ContentBlock with @json.FromJson::{from_json}

///|
pub extend ContentBlock with Debug::{to_repr}

///|
pub extend ContentBlock with Eq::{not_equal, equal}

///|
pub extend ContentBlock with ToJson::{to_json}

///|
pub extend ResourceContents with @json.FromJson::{from_json}

///|
pub extend ResourceContents with Debug::{to_repr}

///|
pub extend ResourceContents with Eq::{not_equal, equal}

///|
pub extend ResourceContents with ToJson::{to_json}
