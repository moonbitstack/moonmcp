// Newline-delimited JSON-RPC over any pair of streams: the stdio transport,
// written once so a socket, a pipe or a test can carry the same messages.

///|
/// Serve newline-delimited JSON-RPC: read a line with `read` until it gives
/// `None`, answer it, and `write` the reply as one line (← the stdio
/// transport, over any pair of streams). A line that is not JSON is answered
/// with a parse error; a blank one is skipped.
///
/// Requests are worked on as they arrive, each in a task of its own, so a slow
/// tool does not hold up the next call. Replies still leave in the order their
/// requests came in, which is what a client that counts lines expects; a
/// subscription's notifications are the exception, since they are not replies
/// to anything.
///
/// `notifications/cancelled` withdraws the request it names, which the running
/// task sees through its context.
pub async fn Server::serve_lines(
  self : Server,
  read : async () -> String?,
  write : async (String) -> Unit,
) -> Unit {
  let lock = @async.Mutex::Mutex()
  let send = async fn(text : String) {
    lock.acquire()
    defer lock.release()
    write(text)
  }
  let outbox : @aqueue.Queue[(Int32, String)] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  let withdrawn = Cancellations::new()
  let headers : Map[String, String] = Map([])
  @async.with_task_group(async fn(group : @async.TaskGroup[Unit]) {
    ignore(group.spawn(async fn() { drain(outbox, send) }))
    let tasks : Array[@async.Task[Unit]] = []
    // Turns are counted over the messages that get an answer, so a
    // notification in the middle does not hold the next reply back.
    let mut seq = 0
    while read() is Some(line) {
      let line = line.trim(chars=" \t\r\n").to_owned()
      if line.is_empty() {
        continue
      }
      let message : Json? = try @json.parse(line) catch {
        _ => None
      } noraise {
        json => Some(json)
      }
      match message {
        None => {
          let text = refusal(Json::null(), fail(parse_error, "Parse error")).1.stringify()
          outbox.put((seq, text)) catch {
            _ => ()
          }
          seq += 1
        }
        Some(message) =>
          match method_of(message) {
            Some("notifications/cancelled") =>
              // Not an answer to give: the request it names stops instead.
              match params_of(message).get("requestId") {
                Some(id) => withdrawn.add(id)
                None => ()
              }
            Some(operation) if operation == @types.method_subscriptions_listen =>
              group.spawn_bg(
                async fn() { serve_one_listen(self, message, send, withdrawn) },
                allow_failure=true,
              )
            _ => {
              let answered = request_id_of(message) is Some(_)
              let turn = seq
              if answered {
                seq += 1
              }
              tasks.push(
                group.spawn(
                  async fn() {
                    let text = serve_one(
                      self, message, send, headers, withdrawn,
                    )
                    match text {
                      Some(text) if answered =>
                        outbox.put((turn, text)) catch {
                          _ => ()
                        }
                      _ => ()
                    }
                  },
                  allow_failure=true,
                ),
              )
            }
          }
      }
    }
    // Every answer still being worked out is settled before the stream closes,
    // and the sentinel goes last, so the writer drains in order.
    for task in tasks {
      task.wait()
    }
    outbox.put((-1, "")) catch {
      _ => ()
    }
  })
}

///|
/// Write the answers out in the order they were asked, waiting for one that is
/// still being worked out. `-1` ends the stream.
async fn drain(
  outbox : @aqueue.Queue[(Int32, String)],
  write : async (String) -> Unit,
) -> Unit {
  let waiting : Map[Int32, String] = Map([])
  let mut next = 0
  while true {
    let (turn, text) = outbox.get()
    if turn < 0 {
      break
    }
    waiting[turn] = text
    while waiting.get(next) is Some(text) {
      waiting.remove(next)
      write(text)
      next += 1
    }
  }
}

///|
/// Answer one message; the reply as it goes on the wire, or `None` when the
/// message wants no answer.
async fn serve_one(
  server : Server,
  message : Json,
  send : async (String) -> Unit,
  headers : Map[String, String],
  withdrawn : Cancellations,
) -> String? {
  let id = request_id_of(message)
  let channel = Channel::new(
    emit=async fn(out : Json) { send(out.stringify()) },
    headers~,
    gone=fn() {
      match id {
        Some(id) => withdrawn.has(id)
        None => false
      }
    },
  )
  let reply = server.answer(message, channel~) catch { _ => None }
  match reply {
    Some((_, reply)) => Some(reply.stringify())
    None => None
  }
}

///|
/// Serve one `subscriptions/listen` request until it is withdrawn or the
/// stream closes, then close it with the reply that says so.
async fn serve_one_listen(
  server : Server,
  message : Json,
  send : async (String) -> Unit,
  withdrawn : Cancellations,
) -> Unit {
  let id = match request_id_of(message) {
    Some(id) => id
    None => return
  }
  let params = params_of(message)
  let channel = Channel::new(
    emit=async fn(out : Json) { send(out.stringify()) },
    headers=Map([]),
    gone=fn() { withdrawn.has(id) },
  )
  server.serve_subscription(id, params, channel, cancellations=withdrawn) catch {
    _ => ()
  }
  let reply : Json = {
    "jsonrpc": "2.0",
    "id": id,
    "result": subscription_closed_result(id),
  }
  send(reply.stringify()) catch {
    _ => ()
  }
}
