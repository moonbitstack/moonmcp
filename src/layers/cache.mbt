// A cache in front of the calls that are expensive and repeat: the same
// request, asked again inside the time a result stays good, is answered from
// the last one.

///|
/// One stored answer and the moment it was made.
struct Entry {
  value : Json
  started : @bench.Timestamp
}

///|
/// Answers a call from memory when the same call was made recently (← FastMCP's
/// `CachingMiddleware`).
///
/// The key is the operation, the name and the arguments, with object keys
/// sorted at every depth, so a client that sends the same arguments in another
/// order still gets the stored answer. Errors and asks for client input are
/// never stored: repeating them would hide the reason and replay a state the
/// client has already answered.
///
/// `ttl_ms` is how long an answer stays good — five minutes, the default of
/// FastMCP's cache. `capacity` is how many answers are kept before the oldest
/// goes; `shared` says whether one caller's answer may be handed to another,
/// which is only safe when the answer does not depend on who asked.
pub struct Caching {
  priv ttl_ms : Int32
  priv capacity : Int32
  priv operations : Array[Operation]
  priv shared : Bool
  priv entries : Map[String, Entry]
  priv mut order : Array[String]
  priv mut head : Int32
  priv mut hits : Int32
  priv mut misses : Int32
}

///|
/// A cache of every call and every listing, kept for five minutes.
pub fn Caching::new(
  ttl_ms~ : Int32 = 300_000,
  capacity~ : Int32 = 1000,
  operations~ : Array[Operation] = [
    ListTools,
    ListResources,
    ListTemplates,
    ListPrompts,
    CallTool,
    ReadResource,
    GetPrompt,
  ],
  shared~ : Bool = false,
) -> Caching {
  {
    ttl_ms,
    capacity,
    operations,
    shared,
    entries: Map([]),
    order: [],
    head: 0,
    hits: 0,
    misses: 0,
  }
}

///|
/// The layer this cache installs on a server.
pub fn Caching::layer(self : Caching) -> Layer {
  Layer::new(name="cache", run=async fn(
    call,
    next,
  ) -> Json raise @exceptions.FastMCPError {
    guard self.operations.contains(call.operation) else {
      return next.then(call)
    }
    let key = self.key(call)
    match self.take(key) {
      Some(value) => {
        self.hits = self.hits + 1
        return value
      }
      None => {
        self.misses = self.misses + 1
        let value = next.then(call)
        if worth_keeping(value) {
          self.put(key, value)
        }
        return value
      }
    }
  })
}

///|
/// How many calls were answered without asking the server.
pub fn Caching::hits(self : Caching) -> Int32 {
  self.hits
}

///|
/// How many went through.
pub fn Caching::misses(self : Caching) -> Int32 {
  self.misses
}

///|
/// How many answers are held right now.
pub fn Caching::size(self : Caching) -> Int32 {
  self.entries.length()
}

///|
/// Forget everything.
pub fn Caching::clear(self : Caching) -> Unit {
  self.entries.clear()
  self.order.clear()
  self.head = 0
}

///|
/// The key one call is stored under.
fn Caching::key(self : Caching, call : Call) -> String {
  if self.shared {
    call.fingerprint()
  } else {
    @moonjson.dumps(
      Json([Json::string(call.subject()), Json::string(call.fingerprint())]),
    )
  }
}

///|
/// The stored answer for `key`, if it is still good. A stale one is dropped
/// where it is found.
fn Caching::take(self : Caching, key : String) -> Json? {
  guard self.entries.get(key) is Some(entry) else { return None }
  let age_ms = @bench.monotonic_clock_end(entry.started) / 1000.0
  if age_ms > self.ttl_ms.to_double() {
    self.entries.remove(key)
    return None
  }
  Some(entry.value)
}

///|
/// Store `value` under `key`, dropping the oldest answer when the cache is
/// full.
fn Caching::put(self : Caching, key : String, value : Json) -> Unit {
  if self.entries.contains(key) {
    self.entries[key] = { value, started: @bench.monotonic_clock_start(), }
    return
  }
  while self.entries.length() >= self.capacity &&
        self.head < self.order.length() {
    let oldest = self.order[self.head]
    self.head = self.head + 1
    self.entries.remove(oldest)
  }
  // The queue only grows at the end, so the keys already dropped are cut off
  // once they are more than half of it.
  if self.head >= 32 && self.head * 2 >= self.order.length() {
    self.order = self.order[self.head:].to_owned()
    self.head = 0
  }
  self.entries[key] = { value, started: @bench.monotonic_clock_start(), }
  self.order.push(key)
}

///|
/// Whether an answer may be stored: a refusal is the server's answer to those
/// arguments, which the next call deserves to hear for itself, and an ask for
/// client input carries a state that belongs to one exchange.
fn worth_keeping(value : Json) -> Bool {
  guard value is Object(fields) else { return true }
  if fields.get("isError") == Some(Json::boolean(true)) {
    return false
  }
  if fields.get("resultType") == Some(Json::string("input_required")) {
    return false
  }
  !(fields.contains("inputRequests") || fields.contains("requestState"))
}
