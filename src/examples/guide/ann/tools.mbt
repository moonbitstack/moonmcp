// The capabilities of the guide's server, written as annotations. The
// generator turns them into the `register` call in `tools.g.mbt`.

// guide:first

///|
/// Add two numbers.
#mcp.tool(description="Add two numbers")
fn add(a : Double, b : Double) -> Double {
  a + b
}

///|
/// Greet someone, in Chinese when asked. An optional parameter is left out of
/// the schema's `required`, and a missing one arrives as `None`.
#mcp.tool(description="Greet someone, in Chinese when asked")
fn greet(name : String, language? : String) -> String {
  match language {
    Some("zh") => "你好，" + name
    _ => "hello, " + name
  }
}
// end

// guide:resources

///|
/// The application's settings. A resource that answers something other than
/// text is sent as JSON.
#mcp.resource("config://app", description="The application settings")
fn config() -> Json {
  { "theme": "dark", "language": "en" }
}

///|
/// A profile per user: `{id}` makes a template, and the value it matched is
/// read as an `Int`.
#mcp.resource("users://{id}/profile")
fn profile(id : Int32) -> String {
  "profile of user \{id}"
}
// end

// guide:prompts

///|
/// Ask for a code review. The parameters become the prompt's arguments.
#mcp.prompt(description="Ask for a code review")
fn review(code : String, focus? : String) -> String {
  let what = match focus {
    Some(focus) => " Focus on \{focus}."
    None => ""
  }
  "Review this code.\{what}\n\n\{code}"
}
// end
