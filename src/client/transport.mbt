// What a client needs from a connection: one message in, one reply out, with
// the notifications that arrive in between handed somewhere, and a stream for
// the messages that never end.

///|
/// A connection that carries JSON-RPC messages. Implement it to reach a server
/// this library does not speak to itself; the three that ship here are
/// `Memory`, `Lines` and `Http`.
///
/// The trait is open: a transport only has to move messages and say which
/// reply belongs to which request. Everything a client does with them —
/// versioning, capabilities, the shape of a call — stays in `Client`.
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
}

///|
/// A transport that reaches a server in the same program, with no wire
/// between them: what an editor, a test or an embedded agent uses.
pub struct Memory {
  server : @server.Server
}

///|
/// Reach `server` directly. Its handlers see no headers and no client
/// identity, since nothing carried the message.
pub fn Memory::new(server : @server.Server) -> Memory {
  { server, }
}

///|
pub impl Transport for Memory with fn ask(
  self : Memory,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Json {
  let channel = @server.Channel::new(emit=on_notification, headers=Map([]), gone=fn() {
    false
  })
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
pub impl Transport for Memory with fn tell(self : Memory, message : Json) -> Unit {
  let channel = @server.Channel::new(emit=fn(_) { () }, headers=Map([]), gone=fn() {
    false
  })
  ignore(self.server.handle_with(message, channel~) catch { _ => None })
}

///|
pub impl Transport for Memory with fn listen(
  self : Memory,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Unit {
  let id = @server.request_id_of(message).unwrap_or(Json::null())
  let channel = @server.Channel::new(emit=on_notification, headers=Map([]), gone=fn() {
    false
  })
  self.server.serve_subscription(id, @server.params_of(message), channel) catch {
    _ => ()
  }
}

///|
pub impl Transport for Memory with fn close(_self : Memory) -> Unit {
  ()
}

///|
/// A transport over a pair of line streams: standard input and output of a
/// child process, a socket, a pipe. The same reader and writer a server is
/// served on, seen from the other end.
///
/// One question is in flight at a time: a reply carries only an id, so a
/// second question would have to read past the first one's answer. The lock
/// holds the whole exchange for that reason.
pub struct Lines {
  read : async () -> String?
  write : async (String) -> Unit
  lock : @async.Mutex
}

///|
/// Speak newline-delimited JSON-RPC over `read` and `write`.
pub fn Lines::new(
  read~ : async () -> String?,
  write~ : async (String) -> Unit,
) -> Lines {
  { read, write, lock: @async.Mutex::Mutex(), }
}

///|
pub impl Transport for Lines with fn ask(
  self : Lines,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Json {
  let id = @server.request_id_of(message).unwrap_or(Json::null())
  self.lock.acquire()
  defer self.lock.release()
  (self.write)(message.stringify() + "\n")
  let mut reply : Json? = None
  while true {
    guard (self.read)() is Some(line) else { break }
    let line = line.trim(chars=" \t\r\n").to_owned()
    if line.is_empty() {
      continue
    }
    let parsed : Json? = try @json.parse(line) catch {
      _ => None
    } noraise {
      json => Some(json)
    }
    guard parsed is Some(parsed) else { continue }
    if same_request(parsed, id) {
      reply = Some(parsed)
      break
    }
    on_notification(parsed)
  }
  match reply {
    Some(reply) => reply
    None => error_reply(id, -32603, "The connection closed before the reply")
  }
}

///|

///|
pub impl Transport for Lines with fn tell(self : Lines, message : Json) -> Unit {
  self.lock.acquire()
  defer self.lock.release()
  (self.write)(message.stringify() + "\n")
}

///|
pub impl Transport for Lines with fn listen(
  self : Lines,
  message : Json,
  on_notification : async (Json) -> Unit,
) -> Unit {
  let id = @server.request_id_of(message).unwrap_or(Json::null())
  (self.write)(message.stringify() + "\n")
  while true {
    guard (self.read)() is Some(line) else { return }
    let line = line.trim(chars=" \t\r\n").to_owned()
    if line.is_empty() {
      continue
    }
    let parsed : Json? = try @json.parse(line) catch {
      _ => None
    } noraise {
      json => Some(json)
    }
    guard parsed is Some(reply) else { continue }
    if same_request(reply, id) {
      // The reply to a `subscriptions/listen` request closes the stream.
      return
    }
    on_notification(reply)
  }
}

///|
pub impl Transport for Lines with fn close(_self : Lines) -> Unit {
  ()
}

///|
/// Whether `message` is the reply to request `id`.
fn same_request(message : Json, id : Json) -> Bool {
  guard message is Object(obj) && obj.get("id") is Some(got) else {
    return false
  }
  got.stringify() == id.stringify()
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
pub extend Memory with Transport::{ask, tell, listen, close}

///|
pub extend Lines with Transport::{ask, tell, listen, close}
