// The two things a transport lends a request while it is being served: a way
// to send notifications out of band, and notice that the caller has gone.

///|
/// What a transport lends one request: the headers that carried it, the way to
/// send a notification before the reply, and whether the caller is still
/// there.
///
/// A transport that can carry nothing beside the reply passes
/// `Channel::quiet`, which is what `Server::handle` uses.
pub(all) struct Channel {
  emit : async (Json) -> Unit
  headers : Map[String, String]
  gone : () -> Bool
  /// The subject the transport's token vouched for, if it checked one.
  subject : String?
  /// Every claim that token carried.
  claims : Map[String, Json]
  /// Whether a request sent through `emit` can reach the client and its reply come back. A
  /// response stream or a pair of lines can; a single JSON reply cannot.
  asks : Bool
}

///|
/// A channel over the transport that carries this request.
pub fn Channel::new(
  emit~ : async (Json) -> Unit,
  headers~ : Map[String, String],
  gone~ : () -> Bool,
  subject? : String,
  claims~ : Map[String, Json] = Map([]),
  asks~ : Bool = false,
) -> Channel {
  { emit, headers, gone, subject, claims, asks, }
}

///|
/// A channel with nowhere to send and no caller to lose.
pub fn Channel::quiet() -> Channel {
  {
    emit: fn(_) { () },
    headers: Map([]),
    gone: fn() { false },
    subject: None,
    claims: Map([]),
    asks: false,
  }
}

///|
/// Which requests a client has withdrawn by `notifications/cancelled`.
///
/// The notification names a request the client already sent, so a transport
/// keeps this beside its read loop: the loop records, the running requests
/// ask.
pub struct Cancellations {
  priv ids : Map[String, Unit]
  priv hooks : Map[String, () -> Unit]
}

///|
/// Nothing withdrawn yet.
pub fn Cancellations::new() -> Cancellations {
  { ids: Map([]), hooks: Map([]), }
}

///|
/// Ask to be told when request `id` is withdrawn. A stream that waits for
/// something other than its own answer, a subscription above all, has no other
/// way to hear about it.
pub fn Cancellations::watch(
  self : Cancellations,
  id : Json,
  hook : () -> Unit,
) -> Unit {
  self.hooks[id_key(id)] = hook
}

///|
/// Stop waiting to be told: the request is over.
pub fn Cancellations::unwatch(self : Cancellations, id : Json) -> Unit {
  self.hooks.remove(id_key(id))
}

///|
/// Record that the client no longer wants the answer to request `id`.
pub fn Cancellations::add(self : Cancellations, id : Json) -> Unit {
  let key = id_key(id)
  self.ids[key] = ()
  match self.hooks.get(key) {
    Some(hook) => hook()
    None => ()
  }
}

///|
/// Whether the client has withdrawn request `id`.
pub fn Cancellations::has(self : Cancellations, id : Json) -> Bool {
  self.ids.contains(id_key(id))
}

///|
/// A request id as a map key: a string as itself, a number by its digits, and
/// anything else by its JSON text, so the two sides of a cancellation agree
/// without knowing which kind the client chose.
fn id_key(id : Json) -> String {
  match id {
    String(text) => "s:" + text
    Number(_, repr=Some(text)) => "n:" + text
    Number(value, ..) => "n:" + Json::number(value).stringify()
    _ => "j:" + id.stringify()
  }
}

///|
/// The method a message names, if it is a JSON-RPC one at all.
pub fn method_of(message : Json) -> String? {
  match message {
    Object(obj) =>
      match obj.get("method") {
        Some(String(op)) => Some(op)
        _ => None
      }
    _ => None
  }
}

///|
/// The id a request carries; `None` on a notification.
pub fn request_id_of(message : Json) -> Json? {
  match message {
    Object(obj) =>
      match obj.get("id") {
        Some(id) if id is (String(_) | Number(_, ..)) => Some(id)
        _ => None
      }
    _ => None
  }
}

///|
/// The parameters a message carries, empty when it carries none.
pub fn params_of(message : Json) -> Map[String, Json] {
  match message {
    Object(obj) =>
      match obj.get("params") {
        Some(Object(params)) => params
        _ => Map([])
      }
    _ => Map([])
  }
}
