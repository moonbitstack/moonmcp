// The checks, run over whichever transport reached the server: list, call,
// read, render, and the two ways of being refused.

///|
let failures : Array[String] = []

///|
/// One check, printed as it is made.
fn check(label : String, holds : Bool) -> Unit {
  if holds {
    println("ok   " + label)
  } else {
    failures.push(label)
    println("FAIL " + label)
  }
}

///|
/// The text of the first content block of a call.
fn call_text(result : @types.CallToolResult) -> String {
  guard result.content.length() > 0 else { return "" }
  match result.content[0] {
    @types.Text(text~, ..) => text
    _ => ""
  }
}

///|
/// Whether a body read back carries `wanted`.
fn reading_holds(read : @types.ReadResourceResult, wanted : String) -> Bool {
  guard read.contents.length() > 0 else { return false }
  match read.contents[0] {
    @types.Text(text~, ..) => text.contains(wanted)
    _ => false
  }
}

///|
/// The code a call to a tool that is not there is refused with, or zero when it
/// was answered instead.
async fn unknown_tool_code(client : @moonmcp.Client) -> Int32 {
  let answered = client.call_tool("nope", arguments=Map([])) catch {
    @client.Refused(code~, ..) => return code
    _ => return -1
  }
  let _ = answered
  0
}

///|
/// The checks every transport runs.
async fn checks(client : @moonmcp.Client) -> Unit {
  let tools = client.list_tools()
  let names = tools.map(tool => tool.name).join(",")
  check("tools/list has echo", names.contains("echo"))
  check("tools/list has sum", names.contains("sum"))

  let echoed = client.call_tool("echo", arguments={ "message": "hi" })
  check("tools/call echo says hi", call_text(echoed) == "hi")
  let added = client.call_tool("sum", arguments={ "a": 2, "b": 3 })
  check("tools/call sum is 5", call_text(added) == "5")

  let resources = client.list_resources()
  check(
    "resources/list has mem://greeting",
    resources.map(resource => resource.uri).join(",").contains("mem://greeting"),
  )
  let read = client.read_resource("mem://greeting")
  check("resources/read answers hello", reading_holds(read, "hello"))

  let prompts = client.list_prompts()
  check(
    "prompts/list has shout",
    prompts.map(prompt => prompt.name).join(",").contains("shout"),
  )
  let rendered = client.get_prompt("shout", arguments={ "text": "hi" })
  let first = match rendered.messages.length() {
    0 => ""
    _ =>
      match rendered.messages[0].content {
        @types.Text(text~, ..) => text
        _ => ""
      }
  }
  check("prompts/get shout renders HI", first == "HI")

  check("an unknown tool is refused", unknown_tool_code(client) != 0)
}

///|
async fn main {
  let arguments = @env.args()
  guard arguments.length() > 1 else {
    println("usage: 06-interop http <url> | stdio <command> [args...]")
    return
  }
  let mode = arguments[1]
  if mode == "http" {
    let url = arguments[2]
    let transport = @http.Http::new(url, version="2025-11-25")
    let client = @client.Client::connect(
      transport,
      protocol_version="2025-11-25",
    )
    checks(client)
    client.close()
  } else if mode == "stdio" {
    let (output, sink) = @process.read_from_process()
    let (source, feed) = @process.write_to_process()
    ignore(
      @process.spawn_orphan(
        arguments[2],
        arguments[3:],
        stdin=source,
        stdout=sink,
      ),
    )
    let transport = @client.Lines::new(
      read=async fn() { output.read_until("\n") },
      write=async fn(line) { feed.write(line) },
    )
    let client = @client.Client::connect(
      transport,
      protocol_version="2025-11-25",
    )
    checks(client)
    feed.close()
    output.close()
  } else {
    println("usage: 06-interop http <url> | stdio <command> [args...]")
    return
  }
  if failures.is_empty() {
    println("\{mode}: all checks passed")
  } else {
    println("\{mode}: \{failures.length()} check(s) failed")
  }
}
