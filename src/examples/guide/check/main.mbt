// The guide's three servers answer the same requests. This program prints the
// answers the page records, and fails when one of the three differs.

///|
let meta : Json = {
  "io.modelcontextprotocol/protocolVersion": "2026-07-28",
  "io.modelcontextprotocol/clientCapabilities": {},
}

///|
fn message(id : Int32, op : String, params : Map[String, Json]) -> Json {
  let params = params.copy()
  params["_meta"] = meta
  {
    "jsonrpc": "2.0",
    "id": Json(id),
    "method": Json(op),
    "params": Json(params),
  }
}

///|
/// The names under `key` of a listing, in order.
fn names(result : Map[String, Json], key : String, field : String) -> String {
  guard result.get(key) is Some(Array(items)) else { return "" }
  items
  .filter_map(fn(item) {
    if item is Object(fields) && fields.get(field) is Some(String(name)) {
      Some(name)
    } else {
      None
    }
  })
  .join(",")
}

///|
/// The text of the first block of `key`, which holds a list of things with a
/// `text` field.
fn first_text(result : Map[String, Json], key : String) -> String {
  guard result.get(key) is Some(Array(items)) &&
    items.length() > 0 &&
    items[0] is Object(item) &&
    item.get("text") is Some(String(text)) else {
    return ""
  }
  text
}

///|
/// A body on one line, with its line breaks written as `\n`.
fn one_line(text : String) -> String {
  text.split("\n").join("\\n")
}

///|
/// A reply, in the one line the page shows.
fn describe(reply : Json) -> String {
  guard reply is Object(o) else { return "no reply" }
  if o.get("error") is Some(Object(error)) {
    return match error.get("code") {
      Some(Number(code, ..)) => "error \{code.to_int()}"
      _ => "error"
    }
  }
  guard o.get("result") is Some(Object(result)) else { return "no result" }
  if result.get("tools") is Some(_) {
    return names(result, "tools", "name")
  }
  if result.get("prompts") is Some(_) {
    return names(result, "prompts", "name")
  }
  if result.get("resources") is Some(_) {
    return names(result, "resources", "uri")
  }
  if result.get("resourceTemplates") is Some(_) {
    return names(result, "resourceTemplates", "uriTemplate")
  }
  if result.get("contents") is Some(_) {
    return one_line(first_text(result, "contents"))
  }
  if result.get("messages") is Some(_) {
    guard result.get("messages") is Some(Array(messages)) &&
      messages.length() > 0 &&
      messages[0] is Object(message) &&
      message.get("content") is Some(Object(content)) &&
      content.get("text") is Some(String(text)) else {
      return ""
    }
    return one_line(text)
  }
  one_line(first_text(result, "content"))
}

///|
/// One request of the guide: what the page calls it, the method, the params.
fn cases() -> Array[(String, String, Map[String, Json])] {
  let empty : Map[String, Json] = Map([])
  [
    ("tools/list", "tools/list", empty),
    (
      "tools/call add {\"a\":2,\"b\":3}",
      "tools/call",
      { "name": "add", "arguments": { "a": 2, "b": 3 } },
    ),
    (
      "tools/call greet {\"name\":\"leo\",\"language\":\"zh\"}",
      "tools/call",
      { "name": "greet", "arguments": { "name": "leo", "language": "zh" } },
    ),
    ("prompts/list", "prompts/list", empty),
    (
      "prompts/get review {\"code\":\"fn f() { 1 }\"}",
      "prompts/get",
      { "name": "review", "arguments": { "code": "fn f() { 1 }" } },
    ),
    ("resources/list", "resources/list", empty),
    ("resources/templates/list", "resources/templates/list", empty),
    (
      "resources/read {\"uri\":\"config://app\"}",
      "resources/read",
      { "uri": "config://app" },
    ),
    (
      "resources/read {\"uri\":\"users://7/profile\"}",
      "resources/read",
      { "uri": "users://7/profile" },
    ),
    (
      "tools/call count {\"up_to\":2}",
      "tools/call",
      { "name": "count", "arguments": { "up_to": 2 } },
    ),
    (
      "tools/call unknown {\"name\":\"nope\"}",
      "tools/call",
      { "name": "nope", "arguments": empty },
    ),
  ]
}

///|
fn common_cases() -> Array[(String, String, Map[String, Json])] {
  cases().filter(fn(entry) { !entry.0.has_prefix("tools/call count") })
}

///|
fn context_cases() -> Array[(String, String, Map[String, Json])] {
  cases().filter(fn(entry) { entry.0.has_prefix("tools/call count") })
}

///|
/// The answers of one server to `requests`, one line per request.
async fn answers(
  mcp : @moonmcp.Server,
  requests : Array[(String, String, Map[String, Json])],
) -> Array[String] {
  let lines : Array[String] = []
  let mut id = 0
  for entry in requests {
    let (label, op, params) = entry
    id = id + 1
    let reply = mcp.handle(message(id, op, params)) catch { _ => None }
    lines.push(label + " -> " + describe_or(reply))
  }
  lines
}

///|
fn describe_or(reply : Json?) -> String {
  match reply {
    Some(reply) => describe(reply)
    None => "no reply"
  }
}

///|
/// The answers of the extended servers, which hold the greeting back.
async fn extended_answers(mcp : @moonmcp.Server) -> Array[String] {
  let lines : Array[String] = []
  let listed = mcp.handle(message(1, "tools/list", Map([]))) catch { _ => None }
  lines.push("tools/list -> " + describe_or(listed))
  let called = mcp.handle(
    message(2, "tools/call", { "name": "add", "arguments": { "a": 2, "b": 3 } }),
  ) catch {
    _ => None
  }
  lines.push("tools/call add -> " + describe_or(called))
  lines
}

///|
/// Print `lines`, and the differences `other` has from them.
fn report(name : String, lines : Array[String], other : Array[String]) -> Bool {
  let same = lines == other
  if !same {
    println("DIFFERS: " + name)
    for i, line in other {
      if i >= lines.length() || line != lines[i] {
        println("  " + line)
      }
    }
  }
  same
}

///|
async fn main {
  let common = common_cases()
  let base = answers(@ann.server(), common)
  println("[common]")
  for line in base {
    println(line)
  }
  let mut same = report("functions", base, answers(@fns.server(), common))
  same = report("classes", base, answers(@cls.server(), common)) && same
  let context = context_cases()
  let context_base = answers(@fns.with_counter(), context)
  println("[context]")
  for line in context_base {
    println(line)
  }
  same = report("classes", context_base, answers(@cls.with_counter(), context)) &&
    same
  let extended = extended_answers(@fns.extended())
  println("[extended]")
  for line in extended {
    println(line)
  }
  same = report("extended classes", extended, extended_answers(@cls.extended())) &&
    same
  println("[same] \{same}")
}
