///|
/// A JSON number in the arguments is read straight, with no second parse.
test "a JSON number in the arguments decodes as the number" {
  let args : Map[String, Json] = { "n": 3 }
  assert_eq(@server.decode(args, "n"), 3)
}

///|
/// A string that is JSON is read again as JSON: this is the path that goes
/// through @moonjson.loads, and it is what lets a text parameter — a resource
/// template `{id}`, a query value, a header — still reach an Int argument.
test "a string that is a JSON number decodes as the number" {
  let args : Map[String, Json] = { "n": Json::string("123") }
  assert_eq(@server.decode(args, "n"), 123)
}

///|
/// The re-parse covers objects too: a string that is a JSON object becomes the
/// object, not the string it arrived in.
test "a string that is a JSON object decodes as the object" {
  let args : Map[String, Json] = { "v": Json::string("{\"x\":1}") }
  let value : Map[String, Json] = @server.decode(args, "v")
  assert_eq(value.length(), 1)
  assert_true(value.contains("x"))
}

///|
/// A string that is not JSON for the wanted type surfaces the original decode
/// error, not the failure of the second parse.
test "a string that is not JSON for the type raises" {
  let args : Map[String, Json] = { "n": Json::string("not-a-number") }
  let raised : Bool = try {
    let _ : Int32 = @server.decode(args, "n")
    false
  } catch {
    @json.JsonDecodeError(_) => true
  }
  assert_true(raised)
}

///|
test "decode_option is None for a missing argument" {
  let args : Map[String, Json] = Map([])
  let got : Int32? = @server.decode_option(args, "n")
  assert_eq(got, None)
}

///|
test "decode_option is None for a null argument" {
  let args : Map[String, Json] = { "n": Json::null() }
  let got : Int32? = @server.decode_option(args, "n")
  assert_eq(got, None)
}

///|
test "decode_option is Some for a present argument, read from a string" {
  let args : Map[String, Json] = { "n": Json::string("7") }
  let got : Int32? = @server.decode_option(args, "n")
  assert_eq(got, Some(7))
}
