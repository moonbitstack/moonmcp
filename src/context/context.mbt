// The request a handler is serving, handed to it beside its arguments: who
// asked, for what, and the way back out to the client while the answer is
// still being worked out.

///|
/// What one request says about itself: the revision it was sent under, the
/// client's identity and capabilities, the progress token it offered, the
/// headers that carried it, the `_meta` object it came with, and the answers it
/// brings back to an earlier leg.
#derive(Debug, Eq)
pub(all) struct Facts {
  protocol_version : String
  operation : String
  request_id : Json
  client_info : @types.Implementation?
  client_capabilities : @types.ClientCapabilities?
  progress_token : Json?
  headers : Map[String, String]
  /// `params._meta` as the client sent it; empty when the request had none.
  meta : Map[String, Json]
  input_responses : Map[String, Json]
  request_state : String?
  /// The subject the transport's token vouched for, when it checked one.
  subject : String?
  /// Every claim that token carried; empty when there was no token.
  claims : Map[String, Json]
}

///|
/// The facts of a request that carries nothing but its own name, which is what
/// a handler called straight from a program sees.
pub fn Facts::new(
  operation~ : String = "",
  request_id~ : Json = Json::null(),
  protocol_version~ : String = @types.latest_protocol_version,
  client_info? : @types.Implementation,
  client_capabilities? : @types.ClientCapabilities,
  progress_token? : Json,
  headers~ : Map[String, String] = Map([]),
  meta~ : Map[String, Json] = Map([]),
  input_responses~ : Map[String, Json] = Map([]),
  request_state? : String,
  subject? : String,
  claims~ : Map[String, Json] = Map([]),
) -> Facts {
  {
    protocol_version,
    operation,
    request_id,
    client_info,
    client_capabilities,
    progress_token,
    headers,
    meta,
    input_responses,
    request_state,
    subject,
    claims,
  }
}

///|
/// The request a tool, a resource or a prompt is serving: the facts above, and
/// the two things a handler can do with the connection while it runs, report
/// progress and ask whether the caller has gone away.
///
/// A `Context` is passed by the framework with every request; a handler called
/// straight from a program gets `Context::quiet`, whose reports go nowhere.
pub struct Context {
  priv facts : Facts
  priv emit : async (Json) -> Unit
  priv gone : () -> Bool
  priv logger : @moonlog.Logger?
  priv level : () -> @types.LoggingLevel?
}

///|
/// Whether a message leaving a handler goes out at all, and whether the caller
/// is still there. Both are supplied by the transport that carries the
/// request; the defaults do nothing.
pub fn Context::new(
  facts~ : Facts,
  emit~ : async (Json) -> Unit = fn(_) { () },
  gone~ : () -> Bool = fn() { false },
  logger? : @moonlog.Logger,
  level~ : () -> @types.LoggingLevel? = fn() { None },
) -> Context {
  { facts, emit, gone, logger, level, }
}

///|
/// A context for a call made without a connection: reports are dropped and the
/// caller is always there.
pub fn Context::quiet() -> Context {
  Context::new(facts=Facts::new())
}

///|
/// The facts this request was served with.
pub fn Context::facts(self : Context) -> Facts {
  self.facts
}

///|
/// The protocol revision the request was sent under.
pub fn Context::protocol_version(self : Context) -> String {
  self.facts.protocol_version
}

///|
/// The method that reached this handler, for example `tools/call`.
pub fn Context::operation(self : Context) -> String {
  self.facts.operation
}

///|
/// The JSON-RPC id of the request, which a progress notification or a
/// subscription echoes back.
pub fn Context::request_id(self : Context) -> Json {
  self.facts.request_id
}

///|
/// Who the client says it is. Self-reported and unverified, of use for display
/// and for logging, never for a permission decision.
pub fn Context::client_info(self : Context) -> @types.Implementation? {
  self.facts.client_info
}

///|
/// What the client says it can do on this request. A request carries its own
/// capabilities, so this is never inherited from an earlier one.
pub fn Context::client_capabilities(
  self : Context,
) -> @types.ClientCapabilities? {
  self.facts.client_capabilities
}

///|
/// The token the client gave for progress reports, if it asked for any. A
/// handler that reports progress without one is not answered, and the reports
/// go nowhere.
pub fn Context::progress_token(self : Context) -> Json? {
  self.facts.progress_token
}

///|
/// The value of the request header `name`, in lower case as ASGI carries it.
/// Over stdio there are none.
pub fn Context::header(self : Context, name : String) -> String? {
  self.facts.headers.get(name)
}

///|
/// Every header the request carried, keyed in lower case.
pub fn Context::headers(self : Context) -> Map[String, String] {
  self.facts.headers
}

///|
/// The request's `params._meta` object as the client sent it. Over stdio this
/// is the only place a caller can put a trace context or its own metadata;
/// a handler reads it here, and the tracing layer reads `traceparent` and
/// `tracestate` from it before falling back to the headers. Empty when the
/// request had no `_meta` or made one that was not an object.
pub fn Context::meta(self : Context) -> Map[String, Json] {
  self.facts.meta
}

///|
/// The answers a client sent back with a retried request, keyed by the id the
/// server gave each input request.
pub fn Context::input_responses(self : Context) -> Map[String, Json] {
  self.facts.input_responses
}

///|
/// The subject a bearer token vouched for, when the transport checked one.
/// `None` over stdio, and over HTTP when the endpoint is open.
pub fn Context::subject(self : Context) -> String? {
  self.facts.subject
}

///|
/// Every claim the token carried, as the issuer wrote them. Empty when no
/// token was checked.
pub fn Context::claims(self : Context) -> Map[String, Json] {
  self.facts.claims
}

///|
/// The server's log, scoped to this request: its id and operation are already
/// bound, so a line says which request it came from. `None` when the server
/// was given no logger, which is the default.
pub fn Context::logger(self : Context) -> @moonlog.Logger? {
  self.logger
}

///|
/// The opaque state the server asked the client to hand back on the retry, or
/// `None` on the first leg.
pub fn Context::request_state(self : Context) -> String? {
  self.facts.request_state
}

///|
/// Whether the caller said it no longer wants this answer. A long handler
/// should stop; the framework drops whatever it returns.
pub fn Context::is_cancelled(self : Context) -> Bool {
  (self.gone)()
}

///|
/// Report how far along the work is. Silent when the client gave no progress
/// token, as the specification has it: a report the caller did not ask for is
/// not sent.
///
/// `progress` grows towards `total`; a report without `total` says how much is
/// done but not how much is left.
pub async fn Context::report_progress(
  self : Context,
  progress~ : Double,
  total? : Double,
  message? : String,
) -> Unit {
  guard self.facts.progress_token is Some(token) else { return }
  let params : Map[String, Json] = {
    "progressToken": token,
    "progress": Json::number(progress),
  }
  if total is Some(value) {
    params["total"] = Json::number(value)
  }
  if message is Some(text) {
    params["message"] = Json::string(text)
  }
  (self.emit)(notification(@types.notification_progress, params))
}

///|
/// Report a log message to the client, at `level`, as `notifications/message`.
/// It travels the same way progress does: on the stream of the request that
/// caused it, and nowhere when the transport has no stream.
pub async fn Context::log(
  self : Context,
  level~ : @types.LoggingLevel,
  message~ : String,
  logger? : String,
  data? : Json,
) -> Unit {
  // The server's own log first: a client that went away should not take the
  // record of what happened with it.
  if self.logger is Some(log) {
    let fields : Array[(String, @moonlog.Value)] = []
    if logger is Some(name) {
      fields.push(("logger", @moonlog.Value::of_str(name)))
    }
    if data is Some(value) {
      fields.push(("data", @moonlog.Value::of_str(@moonjson.dumps(value))))
    }
    log.log(severity(level), message, fields~)
  }
  // What the client asked for with `logging/setLevel` governs what it is sent, not what is kept.
  if (self.level)() is Some(least) && level.rank() < least.rank() {
    return
  }
  let params : Map[String, Json] = {
    "level": Json::string(level.to_wire()),
    "data": Json::string(message),
  }
  if logger is Some(name) {
    params["logger"] = Json::string(name)
  }
  if data is Some(value) {
    params["data"] = value
  }
  (self.emit)(notification(@types.notification_message, params))
}

///|
/// A log message at `debug`.
pub async fn Context::debug(self : Context, message : String) -> Unit {
  self.log(level=@types.Debug, message~)
}

///|
/// A log message at `info`.
pub async fn Context::info(self : Context, message : String) -> Unit {
  self.log(level=@types.Info, message~)
}

///|
/// A log message at `warning`.
pub async fn Context::warning(self : Context, message : String) -> Unit {
  self.log(level=@types.Warning, message~)
}

///|
/// A log message at `error`.
pub async fn Context::error(self : Context, message : String) -> Unit {
  self.log(level=@types.Error, message~)
}

///|
/// One notification message, framed as the wire carries it.
pub fn notification(operation : String, params : Map[String, Json]) -> Json {
  {
    "jsonrpc": "2.0",
    "method": Json::string(operation),
    "params": Json(params),
  }
}

///|
pub extend Facts with Debug::{to_repr}

///|
pub extend Facts with Eq::{not_equal, equal}

///|
/// The same severity in the server's own log, which has six levels where the
/// protocol has eight.
fn severity(level : @types.LoggingLevel) -> @moonlog.Level {
  match level {
    @types.Debug => @moonlog.debug
    @types.Info | @types.Notice => @moonlog.info
    @types.Warning => @moonlog.warn
    @types.Error => @moonlog.error
    @types.Critical | @types.Alert | @types.Emergency => @moonlog.fatal
  }
}
