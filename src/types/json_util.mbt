///|
/// Helpers for hand-rolled JSON codecs; the wire format uses camelCase keys
/// that differ from MoonBit field names.
fn put_str(obj : Map[String, Json], key : String, value : String) -> Unit {
  obj[key] = Json::string(value)
}

///|
fn put_opt_str(obj : Map[String, Json], key : String, value : String?) -> Unit {
  if value is Some(v) {
    obj[key] = Json::string(v)
  }
}

///|
fn put_opt_bool(obj : Map[String, Json], key : String, value : Bool?) -> Unit {
  if value is Some(v) {
    obj[key] = Json::boolean(v)
  }
}

///|
fn put_opt_int(obj : Map[String, Json], key : String, value : Int32?) -> Unit {
  if value is Some(v) {
    obj[key] = Json::number(v.to_double())
  }
}

///|
fn put_opt_double(
  obj : Map[String, Json],
  key : String,
  value : Double,
) -> Unit {
  obj[key] = Json::number(value)
}

///|
fn put_opt_json(obj : Map[String, Json], key : String, value : Json?) -> Unit {
  if value is Some(v) {
    obj[key] = v
  }
}

///|
fn put_opt_array(
  obj : Map[String, Json],
  key : String,
  value : Array[Json]?,
) -> Unit {
  if value is Some(v) {
    obj[key] = Json::array(v)
  }
}

///|
fn put_opt_map(
  obj : Map[String, Json],
  key : String,
  value : Map[String, Json]?,
) -> Unit {
  if value is Some(v) {
    obj[key] = Json(v)
  }
}

///|
fn decode_error(
  path : @json.JsonPath,
  message : String,
) -> @json.JsonDecodeError {
  @json.JsonDecodeError((path, message))
}

///|
fn expect_obj(
  json : Json,
  path : @json.JsonPath,
  context : String,
) -> Map[String, Json] raise @json.JsonDecodeError {
  guard json is Object(obj) else {
    raise decode_error(path, "\{context}: expected object")
  }
  obj
}

///|
fn req_str(
  obj : Map[String, Json],
  path : @json.JsonPath,
  context : String,
  key : String,
) -> String raise @json.JsonDecodeError {
  guard obj.get(key) is Some(String(v)) else {
    raise decode_error(path, "\{context}: missing string field \{key}")
  }
  v
}

///|
fn opt_str(
  obj : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> String? raise @json.JsonDecodeError {
  match obj.get(key) {
    Some(String(v)) => Some(v)
    Some(Null) | None => None
    Some(_) => raise decode_error(path, "field \{key}: expected string")
  }
}

///|
fn opt_bool(
  obj : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> Bool? raise @json.JsonDecodeError {
  match obj.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    Some(_) => raise decode_error(path, "field \{key}: expected bool")
  }
}

///|
fn opt_int(
  obj : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> Int32? raise @json.JsonDecodeError {
  match obj.get(key) {
    Some(Number(v, ..)) => Some(v.to_int())
    Some(Null) | None => None
    Some(_) => raise decode_error(path, "field \{key}: expected number")
  }
}

///|
fn opt_double(
  obj : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> Double? raise @json.JsonDecodeError {
  match obj.get(key) {
    Some(Number(v, ..)) => Some(v)
    Some(Null) | None => None
    Some(_) => raise decode_error(path, "field \{key}: expected number")
  }
}

///|
fn opt_obj(
  obj : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> Map[String, Json]? raise @json.JsonDecodeError {
  match obj.get(key) {
    Some(Object(v)) => Some(v)
    Some(Null) | None => None
    Some(_) => raise decode_error(path, "field \{key}: expected object")
  }
}

///|
fn opt_array(
  obj : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> Array[Json]? raise @json.JsonDecodeError {
  match obj.get(key) {
    Some(Array(v)) => Some(v)
    Some(Null) | None => None
    Some(_) => raise decode_error(path, "field \{key}: expected array")
  }
}

///|
fn req_array(
  obj : Map[String, Json],
  path : @json.JsonPath,
  context : String,
  key : String,
) -> Array[Json] raise @json.JsonDecodeError {
  guard opt_array(obj, path, key) is Some(v) else {
    raise decode_error(path, "\{context}: missing array field \{key}")
  }
  v
}

///|
fn opt_str_array(
  obj : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> Array[String]? raise @json.JsonDecodeError {
  match opt_array(obj, path, key) {
    Some(values) =>
      Some(
        values.filter_map(fn(v) { if v is String(s) { Some(s) } else { None } }),
      )
    None => None
  }
}

///|
fn progress_token_of(meta : Map[String, Json]?) -> String? {
  guard meta is Some(meta) else { return None }
  match meta.get("progressToken") {
    Some(String(token)) => Some(token)
    _ => None
  }
}

///|
fn put_opt_str_array(
  obj : Map[String, Json],
  key : String,
  value : Array[String]?,
) -> Unit {
  if value is Some(v) {
    obj[key] = Json::array(v.map(Json::string))
  }
}
