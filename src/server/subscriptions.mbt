// `subscriptions/listen`: the one stream a client keeps open beside its
// requests, and the change notifications that flow on it.
//
// The stream is a queue per subscription: a change pushes into every queue
// whose filter asked for it, and the task serving the stream takes them out
// and writes them. Nothing is pushed into a queue nobody is reading, so a
// server whose lists never change costs one empty map.

///|
/// One open subscription: what it asked for, and where its notifications wait.
priv struct Watcher {
  filter : @types.SubscriptionFilter
  queue : @aqueue.Queue[Json]
  /// A stream of the revisions before 2026-07-28: it asked for nothing in particular, and hears
  /// every list change and the updates to whatever `resources/subscribe` named.
  legacy : Bool
}

///|
/// The notification that a server's tools, prompts or resources changed.
pub fn list_changed_notification(operation : String) -> Json {
  @context.notification(operation, Map([]))
}

///|
/// The notification that one resource was rewritten.
pub fn resource_updated_notification(uri : String) -> Json {
  @context.notification(@types.notification_resource_updated, {
    "uri": Json::string(uri),
  })
}

///|
/// Whether `message` is one of the notifications a subscription can ask for.
fn is_change_notification(message : Json) -> Bool {
  guard message is Object(obj) && obj.get("method") is Some(String(op)) else {
    return false
  }
  match op {
    "notifications/tools/list_changed"
    | "notifications/prompts/list_changed"
    | "notifications/resources/list_changed"
    | "notifications/resources/updated" => true
    _ => false
  }
}

///|
/// Take out a subscription under `key` and get the queue its notifications
/// arrive on. The stream serving it must call `unwatch` when it ends.
fn Server::watch(
  self : Server,
  key : String,
  filter : @types.SubscriptionFilter,
) -> @aqueue.Queue[Json] {
  let queue = @aqueue.Queue::Queue(kind=@aqueue.Kind::Unbounded)
  self.watchers[key] = { filter, queue, legacy: false, }
  queue
}

///|
/// Take out a stream of the revisions before 2026-07-28 under `key`.
fn Server::watch_legacy(self : Server, key : String) -> @aqueue.Queue[Json] {
  let queue = @aqueue.Queue::Queue(kind=@aqueue.Kind::Unbounded)
  self.watchers[key] = {
    filter: @types.SubscriptionFilter::new(),
    queue,
    legacy: true,
  }
  queue
}

///|
/// Drop the subscription taken out under `key`.
fn Server::unwatch(self : Server, key : String) -> Unit {
  self.watchers.remove(key)
}

///|
/// Hand `message` to every subscription whose filter asked for it. A
/// subscription that has stopped reading its queue is dropped rather than
/// allowed to hold the change.
pub fn Server::notify(self : Server, message : Json) -> Unit {
  guard is_change_notification(message) else { return }
  guard message is Object(obj) && obj.get("method") is Some(String(op)) else {
    return
  }
  let uri = match obj.get("params") {
    Some(Object({ "uri": String(uri), .. })) => Some(uri)
    _ => None
  }
  for _, watcher in self.watchers {
    if watcher.legacy {
      if op == "notifications/resources/updated" &&
        !(uri is Some(uri) && self.subscribed.contains(uri)) {
        continue
      }
      ignore(watcher.queue.try_put(message) catch { _ => false })
      continue
    }
    guard watcher.filter.wants(op) else { continue }
    if op == "notifications/resources/updated" &&
      watcher.filter.resource_subscriptions is Some(uris) &&
      obj.get("params") is Some(Object(params)) &&
      params.get("uri") is Some(String(uri)) &&
      !uris.contains(uri) {
      continue
    }
    ignore(watcher.queue.try_put(message) catch { _ => false })
  }
}

///|
/// Tell every subscription that the tools changed. Registering a tool does
/// this by itself; a server whose tools come and go for reasons of its own
/// calls it when it knows.
pub fn Server::notify_tools_changed(self : Server) -> Unit {
  self.notify(list_changed_notification(@types.notification_tool_list_changed))
}

///|
/// Tell every subscription that the prompts changed.
pub fn Server::notify_prompts_changed(self : Server) -> Unit {
  self.notify(
    list_changed_notification(@types.notification_prompt_list_changed),
  )
}

///|
/// Tell every subscription that the resources changed.
pub fn Server::notify_resources_changed(self : Server) -> Unit {
  self.notify(
    list_changed_notification(@types.notification_resource_list_changed),
  )
}

///|
/// Tell the subscriptions that asked for `uri` that it was rewritten.
pub fn Server::notify_resource_updated(self : Server, uri : String) -> Unit {
  self.notify(resource_updated_notification(uri))
}

///|
/// The filter a `subscriptions/listen` request asks for; a request that names
/// none asks for nothing, which is honoured by sending nothing.
fn filter_of(params : Map[String, Json]) -> @types.SubscriptionFilter raise {
  match params.get("notifications") {
    Some(Object(filter)) => @json.from_json(Json(filter))
    Some(_) => raise fail(invalid_params, "notifications must be an object")
    _ => @types.SubscriptionFilter::new()
  }
}

///|
/// Serve one `subscriptions/listen` request until the transport lets go: the
/// acknowledgement first, then every notification the filter asked for, each
/// tagged with the id of the request that opened the stream.
///
/// The reply to the request itself is sent by the caller when this returns,
/// and only when it returns of its own accord: a stream cut by the transport
/// has no reply, as the specification has it.
pub async fn Server::serve_subscription(
  self : Server,
  id : Json,
  params : Map[String, Json],
  channel : Channel,
  cancellations? : Cancellations,
  queue? : @aqueue.Queue[Json],
) -> Unit {
  let filter = filter_of(params)
  let key = id_key(id)
  let queue = match queue {
    Some(queue) => {
      self.watchers[key] = { filter, queue, legacy: false, }
      queue
    }
    None => self.watch(key, filter)
  }
  defer {
    self.unwatch(key)
    if cancellations is Some(withdrawn) {
      withdrawn.unwatch(id)
    }
  }
  // A withdrawal arrives on the read loop, not here: it wakes this stream by
  // putting a `null` in its queue, which is not a notification.
  if cancellations is Some(withdrawn) {
    withdrawn.watch(id, fn() {
      ignore(queue.try_put(Json::null()) catch { _ => false })
    })
  }
  let tag = { "io.modelcontextprotocol/subscriptionId": id }
  (channel.emit)(
    @context.notification(@types.notification_subscriptions_acknowledged, {
      "notifications": filter.to_json(),
      "_meta": Json(tag),
    }),
  )
  while true {
    if (channel.gone)() {
      break
    }
    let message = queue.get()
    // `null` is not a message: it is the caller saying the stream is over,
    // which is how the read loop shuts a subscription down before it leaves.
    guard message is Object(obj) else { break }
    let out = obj.copy()
    let meta : Map[String, Json] = match obj.get("_meta") {
      Some(Object(existing)) => existing.copy()
      _ => Map([])
    }
    for key, value in tag {
      meta[key] = value
    }
    out["_meta"] = Json(meta)
    (channel.emit)(Json(out))
  }
}

///|
/// The reply that closes a subscription the server ended on purpose, carrying
/// the id of the stream so a client can pair it with the request.
pub fn subscription_closed_result(id : Json) -> Json {
  let meta : Map[String, Json] = {
    "io.modelcontextprotocol/subscriptionId": id,
  }
  { "resultType": "complete", "_meta": Json(meta) }
}
