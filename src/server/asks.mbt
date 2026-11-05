// Asking the client for something in the middle of a request, the way the revisions before
// 2026-07-28 do it: a JSON-RPC request travels out on the response stream, and its reply comes back
// as a message of its own, on another POST or the next line, to be matched up by id.

///|
/// How long a question put to the client waits for its reply: 60 seconds, the TypeScript SDK's
/// `DEFAULT_REQUEST_TIMEOUT_MSEC`.
pub let ask_timeout_ms : Int32 = 60000

///|
/// How many times one request may ask before it is taken to be stuck. A handler that asks again
/// because it got an answer it did not like is fine; one that never stops is not.
pub let ask_rounds : Int32 = 16

///|
/// Whether a message answers something this server asked, rather than asking something itself.
fn is_reply(message : Json) -> Bool {
  guard message is Object(m) else { return false }
  !m.contains("method") &&
  m.contains("id") &&
  (m.contains("result") || m.contains("error"))
}

///|
/// Hand a reply to whoever is waiting for it. One nobody is waiting for is dropped: it may have come
/// in after the wait gave up.
fn Server::settle(self : Server, message : Json) -> Unit {
  guard request_id_of(message) is Some(id) &&
    self.asked.get(id_key(id)) is Some(waiting) else {
    return
  }
  ignore(waiting.try_put(message) catch { _ => false })
}

///|
/// Wake everything still waiting for the client, which is not coming back.
fn Server::give_up_asks(self : Server) -> Unit {
  for _, waiting in self.asked {
    ignore(waiting.try_put(Json::null()) catch { _ => false })
  }
}

///|
/// Send the client `request` and wait for what it says. Its error comes back as an error here.
async fn Server::ask_client(
  self : Server,
  request : Json,
  channel : Channel,
) -> Json {
  guard request is Object(fields) else {
    raise fail(internal_error, "an input request has to be an object")
  }
  self.asks_made += 1
  let id = Json::string("ask-\{self.asks_made}")
  let key = id_key(id)
  let waiting : @aqueue.Queue[Json] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  self.asked[key] = waiting
  defer self.asked.remove(key)
  let out = fields.copy()
  out["jsonrpc"] = "2.0"
  out["id"] = id
  (channel.emit)(Json(out))
  let reply = @async.with_timeout_opt(self.ask_timeout_ms, () => waiting.get())
  match reply {
    Some(Object({ "result": result, .. })) => result
    Some(Object({ "error": Object({ "message": String(said), .. }), .. })) =>
      raise fail(internal_error, "the client refused: \{said}")
    _ => raise fail(internal_error, "the client did not answer")
  }
}

///|
/// The parameters of the next leg of a request: everything it had, with the answers to what the last
/// leg asked and the state it wanted back.
async fn Server::asked_again(
  self : Server,
  params : Map[String, Json],
  ask : Json,
  channel : Channel,
) -> Map[String, Json] {
  guard channel.asks else {
    raise fail(
      internal_error, "a handler asked the client for input, and this transport has no way to",
    )
  }
  let next = params.copy()
  let responses = match params.get("inputResponses") {
    Some(Object(responses)) => responses.copy()
    _ => Map([])
  }
  guard ask is Object(fields) else { return next }
  if fields.get("inputRequests") is Some(Array(requests)) {
    for one in requests {
      guard one is Object({ "id": String(name), "request": request, .. }) else {
        continue
      }
      responses[name] = self.ask_client(request, channel)
    }
  }
  next["inputResponses"] = Json(responses)
  match fields.get("requestState") {
    Some(state) => next["requestState"] = state
    None => next.remove("requestState")
  }
  next
}
