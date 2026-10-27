///|
fn generate(source : String) -> String raise {
  @gen.render(Mcp::{ }, [("tools.mbt", source)])
}

///|
test "types become schemas" {
  assert_eq(schema_of("String"), "{ \"type\": \"string\" }")
  assert_eq(schema_of("Int64"), "{ \"type\": \"integer\" }")
  assert_eq(schema_of("Double"), "{ \"type\": \"number\" }")
  assert_eq(schema_of("Bool"), "{ \"type\": \"boolean\" }")
  assert_eq(
    schema_of("Array[Int]"),
    "{ \"type\": \"array\", \"items\": { \"type\": \"integer\" } }",
  )
  assert_eq(
    schema_of("Map[String, Array[Bool]]"),
    "{ \"type\": \"object\", \"additionalProperties\": { \"type\": \"array\", \"items\": { \"type\": \"boolean\" } } }",
  )
  assert_eq(
    schema_of("String?"),
    "{ \"anyOf\": [{ \"type\": \"string\" }, { \"type\": \"null\" }] }",
  )
  assert_eq(schema_of("Option[Int]"), schema_of("Int?"))
  assert_eq(schema_of("@mine.Profile"), "{}")
}

///|
test "generic splits arguments at the top level only" {
  assert_eq(
    generic("Map[String, Map[String, Int]]"),
    Some(("Map", ["String", "Map[String, Int]"])),
  )
  assert_eq(generic("Int"), None)
}

///|
test "a tool reads each parameter as its pass mode asks" {
  let code = generate(
    (
      #|#mcp.tool(description="Count")
      #|fn count(text : String, unique~ : Bool = false, limit? : Int, hint : String?) -> Int {
      #|  ignore((text, unique, limit, hint))
      #|  0
      #|}
    ),
  )
  assert_true(code.contains("pub fn register(mcp : @moonmcp.Server) -> Unit {"))
  assert_true(code.contains("@moonmcp.decode(args, \"text\")"))
  assert_true(code.contains("unique?=@moonmcp.decode_option(args, \"unique\")"))
  assert_true(code.contains("limit?=@moonmcp.decode_option(args, \"limit\")"))
  assert_true(code.contains("@moonmcp.decode_option(args, \"hint\")"))
  assert_true(code.contains("\"required\": [\"text\"]"))
  assert_true(code.contains("description=\"Count\""))
}

///|
test "resources: fixed, templated, and JSON for anything not text" {
  let code = generate(
    (
      #|#mcp.resource("config://app")
      #|fn config() -> Json {
      #|  {}
      #|}
      #|
      #|#mcp.resource("users://{id}", mime_type="text/markdown")
      #|fn user(id : Int) -> String {
      #|  ignore(id)
      #|  ""
      #|}
    ),
  )
  assert_true(code.contains("mcp.resource("))
  assert_true(code.contains("ToJson::to_json(config()).stringify()"))
  assert_true(code.contains("mime_type=\"application/json\""))
  assert_true(code.contains("mcp.template("))
  assert_true(code.contains("@moonmcp.decode(params, \"id\")"))
  assert_true(code.contains("mime_type=\"text/markdown\""))
}

///|
test "a prompt names its arguments and which are required" {
  let code = generate(
    (
      #|#mcp.prompt(name="code_review")
      #|fn review(code : String, focus? : String) -> String {
      #|  ignore((code, focus))
      #|  ""
      #|}
    ),
  )
  assert_true(code.contains("\"code_review\""))
  assert_true(code.contains("required: Some(true)"))
  assert_true(code.contains("required: Some(false)"))
}

///|
test "mistakes are reported where they are written" {
  let refused = (source : String) => {
    try {
      ignore(generate(source))
      ""
    } catch {
      e => "\{e}"
    }
  }
  assert_true(
    refused(
      (
        #|#mcp.tool
        #|struct S {}
      ),
    ).contains("goes on a free function"),
  )
  assert_true(
    refused(
      (
        #|#mcp.resource("config://app")
        #|fn c(x : Int) -> String { ignore(x); "" }
      ),
    ).contains("takes no parameters"),
  )
  assert_true(
    refused(
      (
        #|#mcp.prompt
        #|fn p() -> Int { 0 }
      ),
    ).contains("returns the text it renders"),
  )
  assert_true(
    refused(
      (
        #|#mcp.toolz
        #|fn t() -> Int { 0 }
      ),
    ).contains("not a moonmcp annotation"),
  )
}
