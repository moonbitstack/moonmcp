///|
/// The argument `name` of a call, read as `T`; the code `#mcp.tool` generates
/// calls this for each required parameter. A string read where something else
/// is wanted is read again as JSON, which is how the `{id}` of a resource
/// template, always text, reaches an `Int` parameter.
pub fn[T : @json.FromJson] decode(
  args : Map[String, Json],
  name : String,
) -> T raise @json.JsonDecodeError {
  let value = args.get(name).unwrap_or(Json::null())
  @json.from_json(value) catch {
    e =>
      match value {
        String(text) => {
          let parsed = @json.parse(text) catch { _ => raise e }
          @json.from_json(parsed)
        }
        _ => raise e
      }
  }
}

///|
/// The argument `name` of a call when it may be left out: `None` when it is
/// missing or `null`, else the value read as `decode` reads it. The code
/// `#mcp.tool` generates calls this for optional parameters.
pub fn[T : @json.FromJson] decode_option(
  args : Map[String, Json],
  name : String,
) -> T? raise @json.JsonDecodeError {
  match args.get(name) {
    None | Some(Null) => None
    Some(_) => Some(decode(args, name))
  }
}
