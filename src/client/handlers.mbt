// What the client does when the server asks it something: a completion the
// model writes (sampling), a question put to the person in front of it
// (elicitation), or the roots it is allowed to read.

///|
/// A client's answers to the requests a server may make of it. Any of the three
/// may be left out, and a server that asks for one the client does not do is
/// told so with the error JSON-RPC prescribes.
///
/// `apply_defaults` is SEP-1034: an accepted elicitation leaves out a field the
/// person did not touch, and the default from the requested schema is filled in
/// before the answer goes back, so the server sees a complete form.
pub(all) struct Handlers {
  sampling : (async (@types.CreateMessageRequestParams) -> @types.CreateMessageResult)?
  elicitation : (async (@types.ElicitRequestParams) -> @types.ElicitResult)?
  roots : (async () -> @types.ListRootsResult)?
  apply_defaults : Bool
}

///|
/// The answers a client gives. Everything left out is a request the client
/// declines to serve.
pub fn Handlers::new(
  sampling? : async (@types.CreateMessageRequestParams) -> @types.CreateMessageResult,
  elicitation? : async (@types.ElicitRequestParams) -> @types.ElicitResult,
  roots? : async () -> @types.ListRootsResult,
  apply_defaults~ : Bool = true,
) -> Handlers {
  { sampling, elicitation, roots, apply_defaults, }
}

///|
/// A client that answers nothing.
pub fn Handlers::none() -> Handlers {
  { sampling: None, elicitation: None, roots: None, apply_defaults: true, }
}

///|
/// What to send back for a message the server sent: a reply when it was a
/// request, nothing when it was a notification.
pub async fn Handlers::answer(self : Handlers, message : Json) -> Json? {
  guard @server.request_id_of(message) is Some(id) else { return None }
  let operation = @server.method_of(message).unwrap_or("")
  let params = @server.params_of(message)
  match operation {
    "sampling/createMessage" =>
      match self.sampling {
        Some(run) => {
          let request : @types.CreateMessageRequestParams? = try
            @json.from_json(Json(params))
          catch {
            _ => None
          } noraise {
            request => Some(request)
          }
          guard request is Some(request) else {
            return refusal(
              id, @types.invalid_params, "sampling/createMessage: bad params",
            )
          }
          let result = run(request) catch {
            e => return refusal(id, @types.internal_error, "\{e}")
          }
          Some({ "jsonrpc": "2.0", "id": id, "result": result.to_json() })
        }
        None =>
          refusal(id, @types.method_not_found, "This client does not sample")
      }
    "elicitation/create" | "elicitation/createForm" =>
      match self.elicitation {
        Some(run) => {
          let request : @types.ElicitRequestParams? = try
            @json.from_json(Json(params))
          catch {
            _ => None
          } noraise {
            request => Some(request)
          }
          guard request is Some(request) else {
            return refusal(
              id, @types.invalid_params, "elicitation/create: bad params",
            )
          }
          let result = run(request) catch {
            e => return refusal(id, @types.internal_error, "\{e}")
          }
          let result = if self.apply_defaults && result.action == "accept" {
            (
              {
                action: result.action,
                content: Some(
                  fill_defaults(
                    request.requested_schema,
                    result.content.unwrap_or(Map([])),
                  ),
                ),
                meta: result.meta,
              } : @types.ElicitResult)
          } else {
            result
          }
          Some({ "jsonrpc": "2.0", "id": id, "result": result.to_json() })
        }
        None =>
          refusal(id, @types.method_not_found, "This client does not elicit")
      }
    "roots/list" =>
      match self.roots {
        Some(run) => {
          let result = run() catch {
            e => return refusal(id, @types.internal_error, "\{e}")
          }
          Some({ "jsonrpc": "2.0", "id": id, "result": result.to_json() })
        }
        None => refusal(id, @types.method_not_found, "This client has no roots")
      }
    _ => refusal(id, @types.method_not_found, "Method not found: \{operation}")
  }
}

///|
/// An error reply to a request this client will not serve.
fn refusal(id : Json, code : Int32, message : String) -> Json? {
  Some({
    "jsonrpc": "2.0",
    "id": id,
    "error": {
      "code": Json::number(code.to_double()),
      "message": Json::string(message),
    },
  })
}

///|
/// `content` with the default of every property of `schema` it leaves out, one
/// level deep: a form's fields are properties of the requested schema, and a
/// nested object carries its own form. A property without a default stays out —
/// the person left it empty, which the server may treat as an error.
pub fn fill_defaults(
  schema : Map[String, Json]?,
  content : Map[String, Json],
) -> Map[String, Json] {
  guard schema is Some(schema) &&
    schema.get("properties") is Some(Object(properties)) else {
    return content
  }
  let out = content.copy()
  for property in properties {
    let (name, definition) = property
    guard !out.contains(name) && definition is Object(definition) else {
      continue
    }
    match definition.get("default") {
      Some(value) => out[name] = value
      None => ()
    }
  }
  out
}
