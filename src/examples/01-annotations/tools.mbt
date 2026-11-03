///|
/// Each parameter becomes a property of the tool's input schema, typed from its
/// MoonBit type; the result is sent back as JSON.
#mcp.tool(description="Add two numbers")
fn add(a : Double, b : Double) -> Double {
  a + b
}

///|
/// An optional parameter is left out of `required`, and a missing argument
/// arrives as `None`.
#mcp.tool(description="Greet someone, in Chinese when asked")
fn greet(name : String, language? : String) -> String {
  match language {
    Some("zh") => "你好，" + name
    _ => "hello, " + name
  }
}

///|
/// The tool's name may differ from the function's, and a labelled parameter
/// with a default is optional too.
#mcp.tool(name="word_count", description="Count the words of a text")
fn count(text : String, unique~ : Bool = false) -> Int32 {
  let words = text
    .split(" ")
    .filter(w => !w.is_empty())
    .map(w => w.to_owned())
    .collect()
  if unique {
    let seen : Map[String, Bool] = Map([])
    for w in words {
      seen[w] = true
    }
    seen.length()
  } else {
    words.length()
  }
}

///|
/// A resource that returns something other than text is sent as JSON.
#mcp.resource("config://app", description="The app configuration")
fn config() -> Json {
  { "theme": "dark", "language": "en" }
}

///|
/// A URI with `{id}` makes a template: every `users://<id>/profile` is read
/// through this function, and the `{id}` it matched is read as an `Int`.
#mcp.resource("users://{id}/profile")
fn profile(id : Int32) -> String {
  "profile of user \{id}"
}

///|
/// A prompt renders the text the client hands to its model; its parameters
/// become the prompt's arguments.
#mcp.prompt(description="Ask for a code review")
fn review(code : String, focus? : String) -> String {
  let what = match focus {
    Some(f) => " Focus on \{f}."
    None => ""
  }
  "Review this code.\{what}\n\n\{code}"
}
