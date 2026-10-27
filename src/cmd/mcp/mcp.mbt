///|
/// `#mcp.tool`, `#mcp.resource(uri)` and `#mcp.prompt` on free functions,
/// turned into `register(mcp)`.
priv struct Mcp {}

///|
impl @gen.Generator for Mcp with fn name(_) {
  "moonmcp"
}

///|
/// Where `attr` is written, as `file:line:column`.
fn at(attr : @attribute.Attribute, file : String) -> String {
  "\{file}:\{attr.loc.start.lnum}:\{attr.loc.start.column()}"
}

///|
/// The arguments each annotation takes.
fn spec(name : String, kind : String) -> @attr.Spec {
  let base = @attr.Spec::new(name)
  let base = if kind == "resource" {
    base.positional("uri", Str).optional("mime_type", Str)
  } else {
    base
  }
  base.optional("name", Str).optional("title", Str).optional("description", Str)
}

///|
fn quoted(text : String) -> String {
  @quote.string(text).to_string()
}

///|
/// The JSON Schema a parameter type describes, as MoonBit source. A type this
/// does not know (a struct of the program's own) accepts any value and is left
/// to its `FromJson`.
fn schema_of(ty : String) -> String {
  let ty = ty.trim(chars=" ").to_owned()
  if ty.has_suffix("?") {
    let inner = ty.view(end_offset=ty.length() - 1).to_owned()
    return "{ \"anyOf\": [\{schema_of(inner)}, { \"type\": \"null\" }] }"
  }
  match generic(ty) {
    Some(("Option", [inner])) =>
      "{ \"anyOf\": [\{schema_of(inner)}, { \"type\": \"null\" }] }"
    Some(("Array" | "FixedArray" | "ReadOnlyArray", [inner])) =>
      "{ \"type\": \"array\", \"items\": \{schema_of(inner)} }"
    Some(("Map", [_, inner])) =>
      "{ \"type\": \"object\", \"additionalProperties\": \{schema_of(inner)} }"
    _ =>
      match ty {
        "String" => "{ \"type\": \"string\" }"
        "Int"
        | "Int16"
        | "Int32"
        | "Int64"
        | "UInt"
        | "UInt16"
        | "UInt32"
        | "UInt64"
        | "Byte"
        | "BigInt" => "{ \"type\": \"integer\" }"
        "Double" | "Float" => "{ \"type\": \"number\" }"
        "Bool" => "{ \"type\": \"boolean\" }"
        "Unit" => "{ \"type\": \"null\" }"
        _ => "{}"
      }
  }
}

///|
/// `Name[A, B]` as its name and arguments; commas inside nested brackets stay
/// with their argument.
fn generic(ty : String) -> (String, Array[String])? {
  guard ty.find("[") is Some(open) && ty.has_suffix("]") else { return None }
  let name = ty.view(end_offset=open).to_owned()
  let inside = ty.view(start_offset=open + 1, end_offset=ty.length() - 1)
  let args = []
  let mut depth = 0
  let mut from = 0
  for i, c in inside {
    match c {
      '[' => depth += 1
      ']' => depth -= 1
      ',' if depth == 0 => {
        args.push(
          inside
          .view(start_offset=from, end_offset=i)
          .trim(chars=" ")
          .to_owned(),
        )
        from = i + 1
      }
      _ => ()
    }
  }
  args.push(inside.view(start_offset=from).trim(chars=" ").to_owned())
  Some((name, args))
}

///|
fn optional_type(ty : String) -> Bool {
  ty.has_suffix("?") || ty.has_prefix("Option[")
}

///|
/// The parameters as the call that reads each from `args`, the schema of the
/// whole argument object, and the prompt arguments they make.
fn params_of(
  params : Array[@gen.Param],
  where_ : String,
  source : String,
) -> (String, String, String) raise {
  let call = []
  let props = []
  let required = []
  let arguments = []
  for param in params {
    guard param.name is Some(name) && param.ty is Some(ty) else {
      fail("\{where_}: every parameter needs a name and a type")
    }
    let maybe = "@moonmcp.decode_option(\{source}, \{quoted(name)})"
    let read = if optional_type(ty) {
      maybe
    } else {
      "@moonmcp.decode(\{source}, \{quoted(name)})"
    }
    let needed = match param.pass {
      Positional => {
        call.push(read)
        !optional_type(ty)
      }
      Labelled => {
        call.push("\{name}=\{read}")
        !optional_type(ty)
      }
      Optional | Defaulted => {
        call.push("\{name}?=\{maybe}")
        false
      }
    }
    props.push("\{quoted(name)}: \{schema_of(ty)}")
    if needed {
      required.push(quoted(name))
    }
    arguments.push(
      "{ name: \{quoted(name)}, title: None, description: None, required: Some(\{needed}) }",
    )
  }
  let schema = "{ \"type\": \"object\", \"properties\": { \{props.join(", ")} }, \"required\": [\{required.join(", ")}] }"
  (call.join(", "), schema, "[\{arguments.join(", ")}]")
}

///|
fn labelled(args : @attr.Args, keys : Array[String]) -> Array[String] {
  let out = []
  for key in keys {
    if args.str(key) is Some(v) {
      out.push("\{key}=\{quoted(v)}")
    }
  }
  out
}

///|
/// The statement registering the function `handler` under `attr`.
fn statement(
  attr : @attribute.Attribute,
  handler : String,
  params : Array[@gen.Param],
  returns : String?,
  file : String,
) -> String raise {
  let where_ = at(attr, file)
  guard @attr.name_of(attr) is Some(full) else { fail("\{where_}: unnamed") }
  let kind = full["mcp.".length():].to_owned()
  guard kind is ("tool" | "resource" | "prompt") else {
    fail("\{where_}: `#\{full}` is not a moonmcp annotation")
  }
  let args = spec(full, kind).bind(attr)
  let text = returns is Some("String")
  match kind {
    "tool" => {
      let (call, schema, _) = params_of(params, where_, "args")
      let name = args.str("name").unwrap_or(handler)
      let parts = [
        quoted(name),
        "args => ToJson::to_json(\{handler}(\{call}))",
        "input_schema=\{schema}",
        ..labelled(args, ["title", "description"]),
      ]
      "mcp.tool(\{parts.join(", ")})"
    }
    "resource" => {
      guard args.str("uri") is Some(uri) else {
        fail("\{where_}: `#mcp.resource` needs a URI")
      }
      let templated = uri.contains("{")
      let (call, _, _) = params_of(params, where_, "params")
      if !templated && !params.is_empty() {
        fail(
          "\{where_}: a resource without a template takes no parameters; put them in the URI as `{name}`",
        )
      }
      let body = if text {
        "\{handler}(\{call})"
      } else {
        "ToJson::to_json(\{handler}(\{call})).stringify()"
      }
      let mime = match args.str("mime_type") {
        Some(m) => ["mime_type=\{quoted(m)}"]
        None => if text { [] } else { ["mime_type=\"application/json\""] }
      }
      let parts = [
        quoted(uri),
        if templated {
          "params => \{body}"
        } else {
          "() => \{body}"
        },
        ..labelled(args, ["name", "title", "description"]),
        ..mime,
      ]
      let call_name = if templated { "template" } else { "resource" }
      "mcp.\{call_name}(\{parts.join(", ")})"
    }
    _ => {
      let (call, _, arguments) = params_of(params, where_, "args")
      if !text {
        fail("\{where_}: a prompt returns the text it renders, a `String`")
      }
      let name = args.str("name").unwrap_or(handler)
      let parts = [
        quoted(name),
        "args => \{handler}(\{call})",
        ..labelled(args, ["title", "description"]),
        "arguments=\{arguments}",
      ]
      "mcp.prompt(\{parts.join(", ")})"
    }
  }
}

///|
impl @gen.Generator for Mcp with fn generate(_, decls) {
  let lines = []
  for decl in decls {
    let found = @attr.under(decl.attrs(), "mcp")
    guard found is [first, ..] else { continue }
    guard decl is Func(owner=None, name~, params~, returns~, file~, ..) else {
      let file = match decl {
        Struct(file~, ..)
        | Enum(file~, ..)
        | Func(file~, ..)
        | Other(file~, ..) => file
      }
      fail("\{at(first, file)}: `#mcp.*` goes on a free function")
    }
    for attr in found {
      lines.push(statement(attr, name, params, returns, file))
    }
  }
  let source =
    #|pub fn register(mcp : @moonmcp.Server) -> Unit {
    #|  $lines*
    #|}
  @quote.items(source)
  .splice("lines", lines.map(l => @quote.expr(l).render()))
  .render()
}
