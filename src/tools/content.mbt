///|
/// Result-to-content conversion helpers mirroring the private functions of
/// fastmcp/tools/base.py.
fn is_content_block(value : Json) -> Bool {
  guard value is Object(obj) else { return false }
  guard obj.get("type") is Some(String(kind)) else { return false }
  match kind {
    "text" | "image" | "audio" | "resource_link" | "resource" => true
    _ => false
  }
}

///|
fn parse_block(value : Json) -> @types.ContentBlock raise @json.JsonDecodeError {
  @json.from_json(value)
}

///|
fn serialize_json(value : Json) -> String {
  value.stringify()
}

///|
/// Whether a raw JSON value is content-block shaped: one block, or a list
/// where any element is a block.
fn is_content_result(value : Json) -> Bool {
  match value {
    Object(_) => is_content_block(value)
    Array(items) => {
      let mut found = false
      for item in items {
        if is_content_block(item) {
          found = true
          break
        }
      }
      found
    }
    _ => false
  }
}

///|
/// Convert one item to a content block: blocks pass through, strings become
/// text, everything else serialises to JSON text.
fn convert_to_single_content_block(
  item : Json,
) -> @types.ContentBlock raise @json.JsonDecodeError {
  if is_content_block(item) {
    return parse_block(item)
  }
  match item {
    String(text) => @types.text_block(text)
    _ => @types.text_block(serialize_json(item))
  }
}

///|
/// Convert a raw result to a sequence of content blocks.
pub fn convert_to_content(
  result : Json,
) -> Array[@types.ContentBlock] raise @json.JsonDecodeError {
  match result {
    Null => []
    Array(items) => {
      let mut all_blocks = true
      for item in items {
        if !is_content_block(item) {
          all_blocks = false
          break
        }
      }
      if all_blocks {
        items.map(convert_to_single_content_block)
      } else {
        let mut any_block = false
        for item in items {
          if is_content_block(item) {
            any_block = true
            break
          }
        }
        if any_block {
          items.map(convert_to_single_content_block)
        } else {
          [@types.text_block(serialize_json(result))]
        }
      }
    }
    _ => [convert_to_single_content_block(result)]
  }
}
