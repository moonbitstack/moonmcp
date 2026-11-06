// What a client needs from a connection: one message in, one reply out, with
// the notifications that arrive in between handed somewhere, and a stream for
// the messages that never end.

///|
/// A connection that carries JSON-RPC messages. Implement it to reach a server
/// this library does not speak to itself; the three that ship here are
/// `Memory`, `Lines` and `Http`.
///
/// The trait is open: a transport only has to move messages and say which
/// reply belongs to which request, and answer the requests the server makes in
/// the middle of one of ours. Everything a client does with them — versioning,
/// capabilities, the shape of a call — stays in `Client`.
pub(open) trait Transport {
  /// Send one request and give back its reply. A notification that arrives
  /// before the reply is handed to `on_notification` rather than kept: it
  /// belongs to the request in flight.
  async fn ask(Self, message : Json, on_notification : async (Json) -> Unit) -> Json
  /// Send one message that gets no reply.
  async fn tell(Self, message : Json) -> Unit
  /// Open a subscription, handing every notification to `on_notification`
  /// until the server ends it or the connection goes.
  async fn listen(Self, message : Json, on_notification : async (Json) -> Unit) -> Unit
  /// Let go of the connection. It carries nothing afterwards.
  async fn close(Self) -> Unit
  /// Where a request the server makes while one of ours is in flight goes: the
  /// answer travels back the way the question came. A transport that cannot
  /// carry one leaves this alone, and such a request is handed on as a
  /// notification nobody answers.
  fn answer_with(Self, answer : async (Json) -> Json?) -> Unit
}

///|
/// A transport that reaches a server in the same program, with no wire
/// between them: what an editor, a test or an embedded agent uses.
pub struct Memory {
  server : @server.Server
  answer : Ref[(async (Json) -> Json?)?]
}

///|
/// Reach `server` directly. Its handlers see no headers and no client
/// identity, since nothing carried the message.
pub fn Memory::new(server : @server.Server) -> Memory {
  { server, answer: Ref(None), }
}

///|
/// Ask the server in this program. Nothing carried the message, so its
/// handlers see no headers and no client identity.
///
/// A question the server puts to the client inside a handler travels out
/// through the same channel and comes back the same way, which is what makes
/// sampling and elicitation work with no wire at all.
pub impl Transport for Memory with fn ask(
  self : Memory,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Json {
  let channel = channel_of(self, on_notification)
  match self.server.handle_with(message, channel~) {
    Some(reply) => reply
    None =>
      // A request always has an answer; a notification reaching here was
      // asked for one by a caller that should have used `tell`.
      {
        "jsonrpc": "2.0",
        "id": Json::null(),
        "error": {
          "code": Json::number(-32600.0),
          "message": Json::string("Notifications get no reply"),
        },
      }
  }
}

///|
/// Hand a notification to the server; nothing comes back.
pub impl Transport for Memory with fn tell(self : Memory, message : Json) -> Unit {
  let channel = channel_of(self, fn(_) { () })
  ignore(self.server.handle_with(message, channel~) catch { _ => None })
}

///|
/// Open a subscription on the server and hand its notifications on until
/// the stream ends.
pub impl Transport for Memory with fn listen(
  self : Memory,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Unit {
  let id = @server.request_id_of(message).unwrap_or(Json::null())
  let channel = channel_of(self, on_notification)
  self.server.serve_subscription(id, @server.params_of(message), channel) catch {
    _ => ()
  }
}

///|
/// Nothing to let go: the server is in this process.
pub impl Transport for Memory with fn close(_self : Memory) -> Unit {
  ()
}

///|
/// Keep `answer` as the place the server's questions go.
pub impl Transport for Memory with fn answer_with(
  self : Memory,
  answer : async (Json) -> Json?,
) -> Unit {
  self.answer.val = Some(answer)
}

///|
/// A channel over the server in this program: what a handler sends goes to
/// `on_notification`, except that a request goes to the client's answerer and
/// its answer goes back into the server, which is waiting for it.
fn channel_of(
  memory : Memory,
  on_notification : async (Json) -> Unit,
) -> @server.Channel {
  @server.Channel::new(
    emit=async fn(out) {
      if @server.request_id_of(out) is Some(_) &&
        @server.method_of(out) is Some(_) {
        match memory.answer.val {
          Some(answer) => {
            let reply = answer(out) catch { _ => None }
            match reply {
              Some(reply) =>
                ignore(
                  memory.server.handle_with(
                    reply,
                    channel=@server.Channel::quiet(),
                  ) catch {
                    _ => None
                  },
                )
              None => on_notification(out)
            }
          }
          None => on_notification(out)
        }
      } else {
        on_notification(out)
      }
    },
    headers=Map([]),
    // The answer comes back through this very channel, so a handler may ask
    // the client something and wait for it.
    asks=true,
    gone=fn() { false },
  )
}

///|
/// A transport over a pair of line streams: standard input and output of a
/// child process, a socket, a pipe. The same reader and writer a server is
/// served on, seen from the other end.
///
/// One message is one line. The framing and the pairing of a reply with its
/// request are `moonjrpc`'s: a `Peer` over these streams assigns the request
/// identifiers, wakes the caller whose reply arrived, answers whatever the
/// server asks, and ends when the stream does.
pub struct Lines {
  priv frames : Couple
  lock : @async.Mutex
  answer : Ref[(async (Json) -> Json?)?]
}

///|
/// Speak newline-delimited JSON-RPC over `read` and `write`.
pub fn Lines::new(
  read~ : async () -> String?,
  write~ : async (String) -> Unit,
) -> Lines {
  { frames: { read, write, }, lock: @async.Mutex::Mutex(), answer: Ref(None), }
}

///|
/// The pair of closures a line stream is, as the frames `moonjrpc` carries: one
/// message to a line.
priv struct Couple {
  read : async () -> String?
  write : async (String) -> Unit
}

///|
impl @peer.Frames for Couple with fn read(self : Couple) -> String? {
  (self.read)()
}

///|
impl @peer.Frames for Couple with fn write(self : Couple, text : String) -> Unit {
  (self.write)(text + "\n")
}

///|
/// The methods a server may call on this client, by the names the protocol
/// gives them.
let request_names : Array[String] = [
  "sampling/createMessage", "elicitation/create", "elicitation/createForm", "roots/list",
  "ping",
]

///|
/// The notifications a client hears on the connection, by the names the
/// protocol gives them.
let notice_names : Array[String] = [
  "notifications/progress", "notifications/message", "notifications/resources/updated",
  "notifications/resources/list_changed", "notifications/tools/list_changed", "notifications/prompts/list_changed",
  "notifications/cancelled",
]

///|
/// The table a `Peer` answers with: a request goes to the client's answerer,
/// and a notification to the caller waiting for the reply.
fn Lines::methods(
  self : Lines,
  on_notification : async (Json) -> Unit,
) -> @moonjrpc.Methods {
  let methods = @moonjrpc.Methods::new()
  for name in request_names {
    let run : async (Json?) -> Json = params => self.serve(name, params)
    methods.call(name, run)
  }
  for name in notice_names {
    let run : async (Json?) -> Unit = params => {
      let message : Map[String, Json] = {
        "jsonrpc": Json::string("2.0"),
        "method": Json::string(name),
      }
      if params is Some(value) {
        message["params"] = value
      }
      on_notification(Json(message))
    }
    methods.notice(name, run)
  }
  methods
}

///|
/// Answer one request the server made, by the same rules the rest of the client
/// uses: the reply is a result, or the error object it carries.
async fn Lines::serve(self : Lines, name : String, params : Json?) -> Json {
  let request : Map[String, Json] = {
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(0.0),
    "method": Json::string(name),
  }
  if params is Some(value) {
    request["params"] = value
  }
  let reply = match self.answer.val {
    Some(answer) => answer(Json(request)) catch { _ => None }
    None => None
  }
  guard reply is Some(reply) else {
    raise @moonjrpc.fail(-32601, "This client does not serve \{name}")
  }
  match reply {
    Object(fields) =>
      match fields.get("result") {
        Some(result) => result
        None =>
          match fields.get("error") {
            Some(Object(error)) => {
              let code = match error.get("code") {
                Some(Number(value, ..)) => value.to_int()
                _ => -32603
              }
              let message = match error.get("message") {
                Some(String(text)) => text
                _ => "the client refused"
              }
              raise @moonjrpc.fail(code, message)
            }
            _ => raise @moonjrpc.fail(-32603, "the client answered nothing")
          }
      }
    _ => raise @moonjrpc.fail(-32603, "the client answered nothing")
  }
}

///|
/// Write the request and wait for its reply, with whatever the server asks in
/// between answered on the same stream.
pub impl Transport for Lines with fn ask(
  self : Lines,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Json {
  let name = @server.method_of(message).unwrap_or("")
  let params = match @server.params_of(message).is_empty() {
    true => None
    false => Some(Json(@server.params_of(message)))
  }
  self.lock.acquire()
  defer self.lock.release()
  self.exchange(name, params, on_notification)
}

///|
/// One call through a peer of its own: the peer lives as long as the call, and
/// its identifiers are this connection's to give.
async fn Lines::exchange(
  self : Lines,
  name : String,
  params : Json?,
  on_notification : async (Json) -> Unit,
) -> Json {
  let peer = @peer.Peer::new(
    self.frames,
    methods=self.methods(on_notification),
    timeout_ms=Some(@server.ask_timeout_ms),
  )
  let out : Ref[Json?] = Ref(None)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(no_wait=true, allow_failure=true, () => peer.run())
    let result = peer.call(name, params?) catch {
      @moonjrpc.Failed(failure) => {
        out.val = Some(failure_reply(failure))
        Json::null()
      }
      @moonjrpc.TimedOut(..) => {
        out.val = Some(
          error_reply(Json::null(), -32603, "The server did not answer in time"),
        )
        Json::null()
      }
      _ => {
        out.val = Some(
          error_reply(
            Json::null(),
            -32603,
            "The connection closed before the reply",
          ),
        )
        Json::null()
      }
    }
    if out.val is None {
      out.val = Some({
        "jsonrpc": "2.0",
        "id": Json::number(0.0),
        "result": result,
      })
    }
  })
  match out.val {
    Some(reply) => reply
    None => error_reply(Json::null(), -32603, "The call did not finish")
  }
}

///|
/// An error reply made where no server answered, so that a caller sees the
/// same shape either way.
fn error_reply(id : Json, code : Int32, message : String) -> Json {
  {
    "jsonrpc": "2.0",
    "id": id,
    "error": {
      "code": Json::number(code.to_double()),
      "message": Json::string(message),
    },
  }
}

///|
/// An error object from the other side, as a reply this client's caller reads.
fn failure_reply(failure : @moonjrpc.Failure) -> Json {
  let error : Map[String, Json] = {
    "code": Json::number(failure.code.to_double()),
    "message": Json::string(failure.message),
  }
  if failure.data is Some(data) {
    error["data"] = data
  }
  { "jsonrpc": "2.0", "id": Json::null(), "error": Json(error) }
}

///|
/// Write one notification; nothing is read back.
pub impl Transport for Lines with fn tell(self : Lines, message : Json) -> Unit {
  let name = @server.method_of(message).unwrap_or("")
  let params = match @server.params_of(message).is_empty() {
    true => None
    false => Some(Json(@server.params_of(message)))
  }
  self.lock.acquire()
  defer self.lock.release()
  let peer = @peer.Peer::new(self.frames)
  peer.notify(name, params?) catch {
    _ => ()
  }
}

///|
/// Open a subscription and hand every notification to `on_notification` until
/// the server answers the request that opened it.
pub impl Transport for Lines with fn listen(
  self : Lines,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Unit {
  let params = @server.params_of(message)
  let peer = @peer.Peer::new(
    self.frames,
    methods=self.methods(on_notification),
    timeout_ms=None,
  )
  @async.with_task_group(async fn(group) {
    group.spawn_bg(no_wait=true, allow_failure=true, () => peer.run())
    ignore(
      peer.call("subscriptions/listen", params=Json(params)) catch {
        _ => Json::null()
      },
    )
  })
}

///|
/// Nothing to let go: the streams belong to whoever made them.
pub impl Transport for Lines with fn close(_self : Lines) -> Unit {
  ()
}

///|
/// Keep `answer` as the place the server's questions go.
pub impl Transport for Lines with fn answer_with(
  self : Lines,
  answer : async (Json) -> Json?,
) -> Unit {
  self.answer.val = Some(answer)
}

///|
pub extend Memory with Transport::{ask, tell, listen, close, answer_with}

///|
pub extend Lines with Transport::{ask, tell, listen, close, answer_with}
