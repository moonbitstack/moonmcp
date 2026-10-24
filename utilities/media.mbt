///|
/// Media helper classes mirroring fastmcp/utilities/types.py.
///
/// Byte-backed helpers return image/audio/resource content blocks; path-based
/// loading requires native file IO, which is deferred until the transport
/// layer introduces it.
fn lower_ascii(value : String) -> String {
  let buf = StringBuilder::StringBuilder()
  for ch in value {
    buf.write_char(ch.to_ascii_lowercase())
  }
  buf.to_string()
}

///|
/// Base64-encode raw bytes for wire transport.
pub fn encode_base64(data : Bytes) -> String {
  @base64.encode(data)
}

///|
/// A helper for returning images from tools.
pub(all) struct Image {
  path : String?
  data : Bytes?
  format : String?
  mime_type : String
  annotations : @types.Annotations?
}

///|
fn image_mime_from_format(format : String) -> String {
  let fmt = lower_ascii(format)
  match fmt {
    "jpg" => "image/jpeg"
    "svg" => "image/svg+xml"
    "tif" => "image/tiff"
    _ => "image/\{fmt}"
  }
}

///|
fn image_mime_from_path(path : String) -> String {
  let dot = path.rev_find(".")
  match dot {
    Some(index) => {
      let ext = lower_ascii(path[index + 1:].to_owned())
      match ext {
        "png" => "image/png"
        "jpg" | "jpeg" => "image/jpeg"
        "gif" => "image/gif"
        "webp" => "image/webp"
        "svg" => "image/svg+xml"
        "tif" | "tiff" => "image/tiff"
        "bmp" => "image/bmp"
        _ => "application/octet-stream"
      }
    }
    None => "application/octet-stream"
  }
}

///|
/// Create an image from a file path or raw data, not both.
pub fn Image::new(
  path? : String,
  data? : Bytes,
  format? : String,
  annotations? : @types.Annotations,
) -> Image raise @exceptions.FastMCPError {
  if path is None && data is None {
    raise @exceptions.Validation("Either path or data must be provided")
  }
  if path is Some(_) && data is Some(_) {
    raise @exceptions.Validation("Only one of path or data can be provided")
  }
  let mime_type = match format {
    Some(fmt) => image_mime_from_format(fmt)
    None =>
      match path {
        Some(p) => image_mime_from_path(p)
        None => "image/png"
      }
  }
  { path, data, format, mime_type, annotations, }
}

///|
fn Image::encoded_data(self : Image) -> String raise @exceptions.FastMCPError {
  match self.data {
    Some(data) => encode_base64(data)
    None =>
      raise @exceptions.Validation(
        "No image data available: path-based loading requires native IO",
      )
  }
}

///|
/// Convert to an image content block.
pub fn Image::to_image_content(
  self : Image,
  mime_type? : String,
  annotations? : @types.Annotations,
) -> @types.ContentBlock raise @exceptions.FastMCPError {
  @types.Image(
    data=self.encoded_data(),
    mime_type=mime_type.unwrap_or(self.mime_type),
    annotations=pick_annotations(annotations, self.annotations),
    meta=None,
  )
}

///|
/// Render as a `data:` URI.
pub fn Image::to_data_uri(
  self : Image,
  mime_type? : String,
) -> String raise @exceptions.FastMCPError {
  "data:\{mime_type.unwrap_or(self.mime_type)};base64,\{self.encoded_data()}"
}

///|
/// A helper for returning audio from tools.
pub(all) struct Audio {
  path : String?
  data : Bytes?
  format : String?
  mime_type : String
  annotations : @types.Annotations?
}

///|
fn audio_mime_from_format(format : String) -> String {
  let fmt = lower_ascii(format)
  match fmt {
    "wav" => "audio/wav"
    "mp3" => "audio/mpeg"
    "ogg" => "audio/ogg"
    "m4a" => "audio/mp4"
    "flac" => "audio/flac"
    "opus" => "audio/ogg"
    "aac" => "audio/aac"
    "webm" => "audio/webm"
    "aiff" | "aif" => "audio/aiff"
    _ => "audio/\{fmt}"
  }
}

///|
fn audio_mime_from_path(path : String) -> String {
  let dot = path.rev_find(".")
  match dot {
    Some(index) => audio_mime_from_format(path[index + 1:].to_owned())
    None => "application/octet-stream"
  }
}

///|
/// Create an audio clip from a file path or raw data, not both.
pub fn Audio::new(
  path? : String,
  data? : Bytes,
  format? : String,
  annotations? : @types.Annotations,
) -> Audio raise @exceptions.FastMCPError {
  if path is None && data is None {
    raise @exceptions.Validation("Either path or data must be provided")
  }
  if path is Some(_) && data is Some(_) {
    raise @exceptions.Validation("Only one of path or data can be provided")
  }
  let mime_type = match format {
    Some(fmt) => audio_mime_from_format(fmt)
    None =>
      match path {
        Some(p) => audio_mime_from_path(p)
        None => "audio/wav"
      }
  }
  { path, data, format, mime_type, annotations, }
}

///|
fn Audio::encoded_data(self : Audio) -> String raise @exceptions.FastMCPError {
  match self.data {
    Some(data) => encode_base64(data)
    None =>
      raise @exceptions.Validation(
        "No audio data available: path-based loading requires native IO",
      )
  }
}

///|
/// Convert to an audio content block.
pub fn Audio::to_audio_content(
  self : Audio,
  mime_type? : String,
  annotations? : @types.Annotations,
) -> @types.ContentBlock raise @exceptions.FastMCPError {
  @types.Audio(
    data=self.encoded_data(),
    mime_type=mime_type.unwrap_or(self.mime_type),
    annotations=pick_annotations(annotations, self.annotations),
    meta=None,
  )
}

///|
/// A helper for returning file data from tools.
pub(all) struct File {
  path : String?
  data : Bytes?
  format : String?
  name : String?
  mime_type : String
  annotations : @types.Annotations?
}

///|
fn file_mime_from_format(format : String) -> String {
  let fmt = lower_ascii(format)
  match fmt {
    "plain" | "txt" | "text" => "text/plain"
    "csv" => "text/csv"
    "html" | "htm" => "text/html"
    "md" | "markdown" => "text/markdown"
    _ => "application/\{fmt}"
  }
}

///|
fn file_mime_from_path(path : String) -> String {
  let dot = path.rev_find(".")
  match dot {
    Some(index) => {
      let ext = lower_ascii(path[index + 1:].to_owned())
      match ext {
        "txt" => "text/plain"
        "csv" => "text/csv"
        "html" | "htm" => "text/html"
        "md" | "markdown" => "text/markdown"
        "json" => "application/json"
        "xml" => "application/xml"
        "pdf" => "application/pdf"
        "zip" => "application/zip"
        "gz" => "application/gzip"
        "tar" => "application/x-tar"
        "png" | "jpg" | "jpeg" | "gif" | "webp" | "svg" | "bmp" =>
          "image/\{ext}"
        "wav" | "mp3" | "ogg" | "flac" | "aac" => "audio/\{ext}"
        _ => "application/octet-stream"
      }
    }
    None => "application/octet-stream"
  }
}

///|
/// Create a file payload from a path or raw data, not both.
pub fn File::new(
  path? : String,
  data? : Bytes,
  format? : String,
  name? : String,
  annotations? : @types.Annotations,
) -> File raise @exceptions.FastMCPError {
  if path is None && data is None {
    raise @exceptions.Validation("Either path or data must be provided")
  }
  if path is Some(_) && data is Some(_) {
    raise @exceptions.Validation("Only one of path or data can be provided")
  }
  let mime_type = match format {
    Some(fmt) => file_mime_from_format(fmt)
    None =>
      match path {
        Some(p) => file_mime_from_path(p)
        None => "application/octet-stream"
      }
  }
  { path, data, format, name, mime_type, annotations, }
}

///|
fn is_unreserved(ch : Char) -> Bool {
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= 'a' && ch <= 'z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '-' ||
  ch == '.' ||
  ch == '_' ||
  ch == '~'
}

///|
fn write_hex_byte(buf : StringBuilder, byte : Byte) -> Unit {
  let digits = "0123456789ABCDEF"
  buf.write_char('%')
  buf.write_char(digits.get_char((byte / 16).to_int()).unwrap())
  buf.write_char(digits.get_char((byte % 16).to_int()).unwrap())
}

///|
/// Percent-encode every non-unreserved character, UTF-8 for non-ASCII.
fn pct_encode_component(text : String) -> String {
  let buf = StringBuilder::StringBuilder()
  for ch in text {
    if is_unreserved(ch) {
      buf.write_char(ch)
    } else {
      for byte in @utf8.encode(ch.to_string()) {
        write_hex_byte(buf, byte)
      }
    }
  }
  buf.to_string()
}

///|
fn pick_annotations(
  chosen : @types.Annotations?,
  fallback : @types.Annotations?,
) -> @types.Annotations? {
  if chosen is Some(_) {
    chosen
  } else {
    fallback
  }
}

///|
fn File::embedded_uri(self : File) -> String raise @exceptions.FastMCPError {
  match self.path {
    Some(path) => "file:///\{pct_encode_component(path)}"
    None => {
      guard self.data is Some(_) else {
        raise @exceptions.Validation("No resource data available")
      }
      let extension = match self.format {
        Some(fmt) => ".\{lower_ascii(fmt)}"
        None => {
          let slash = self.mime_type.find("/")
          match slash {
            Some(index) => ".\{self.mime_type[index + 1:].to_owned()}"
            None => ""
          }
        }
      }
      match self.name {
        Some(name) =>
          if name.contains(".") {
            "file:///\{pct_encode_component(name)}"
          } else {
            let with_ext = "\{name}\{extension}"
            "file:///\{pct_encode_component(with_ext)}"
          }
        None => "file:///resource\{extension}"
      }
    }
  }
}

///|
/// Convert to an embedded resource content block.
pub fn File::to_resource_content(
  self : File,
  mime_type? : String,
  annotations? : @types.Annotations,
) -> @types.ContentBlock raise @exceptions.FastMCPError {
  guard self.data is Some(raw_data) else {
    raise @exceptions.Validation(
      "No resource data available: path-based loading requires native IO",
    )
  }
  let mime = mime_type.unwrap_or(self.mime_type)
  let uri = self.embedded_uri()
  let resource : @types.ResourceContents = if mime.has_prefix("text/") {
    Text(uri~, mime_type=Some(mime), text=@utf8.decode_lossy(raw_data))
  } else {
    Blob(uri~, mime_type=Some(mime), blob=encode_base64(raw_data))
  }
  @types.EmbeddedResource(
    resource~,
    annotations=pick_annotations(annotations, self.annotations),
    meta=None,
  )
}
