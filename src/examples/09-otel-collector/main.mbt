// One traced call, sent to a real collector. The caller opens a client span,
// puts its W3C context in `params._meta` as a client over stdio would, and the
// server's tracing layer opens a server span as its child. Both leave over
// OTLP/HTTP, so the collector's own record is what says whether the two were
// joined and whether the span was named and tagged as the conventions ask.

///|
/// The clock the exporter batches and times its retries with, in milliseconds.
fn millis() -> Int64 {
  @async.now()
}

///|
/// The clock a span is timed by, in nanoseconds.
fn nanos() -> Int64 {
  @async.now() * 1_000_000L
}

///|
/// The same clock, but never standing still: a platform clock too coarse to
/// move between two reads would otherwise give a span no duration at all.
fn ticking_nanos() -> () -> Int64 {
  let last = Ref(0L)
  () => {
    let now = @async.now() * 1_000_000L
    last.val = if now > last.val { now } else { last.val + 1L }
    last.val
  }
}

///|
/// The ids a span is given, from the platform's entropy source.
fn entropy(width : Int32) -> Bytes {
  let rng = @auto.rng() catch { _ => abort("no entropy source") }
  let filled = FixedArray::make(width, (0).to_byte())
  rng.fill(filled)
  Bytes::from_array(Array::makei(width, index => filled[index]))
}

///|
async fn main {
  let arguments = @env.args()
  let endpoint = if arguments.length() > 1 {
    arguments[1]
  } else {
    "http://127.0.0.1:4318"
  }
  let traces = @export.traces(
    endpoint~,
    service="moonmcp-collector-check",
    now=millis,
    rand=entropy,
  )
  let tracer = @trace.Tracer::new(
    rand=entropy,
    sink=traces,
    sampler=@trace.always,
  )
  let caller = tracer.start(
    "caller calls tools/call add",
    kind=@trace.Client,
    at=nanos(),
  ) catch {
    _ => abort("the platform has no entropy for a caller span")
  }
  let request : Json = {
    "jsonrpc": "2.0",
    "id": Json(42),
    "method": "tools/call",
    "params": {
      "name": Json::string("add"),
      "arguments": (Map([]) : Map[String, Json]),
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": Json::string("2026-07-28"),
        "traceparent": Json::string(caller.context().to_traceparent()),
        "tracestate": Json::string("vendor=collector"),
      },
    },
  }
  let mcp = @moonmcp.Server::new("demo", version="1.0.0")
  mcp.tool("add", _args => { "sum": Json(2) })
  mcp.use_layer(@otel.Tracing::new(tracer~, now=ticking_nanos()).layer())
  // A request over stdio has no headers; the trace can only travel in `_meta`.
  let reply = mcp.handle(request)
  guard reply is Some(answer) else { abort("the server gave no answer") }
  if !answer.stringify().contains("\"result\"") {
    abort("the tool call was not answered: \{answer.stringify()}")
  }
  caller.finish(at=nanos() + 1_000_000L)
  let report = traces.flush()
  if report.delivered != 2 || report.rejected != 0 || report.dropped != 0 {
    abort(
      "a collector at \{endpoint} did not take both spans: delivered \{report.delivered}, " +
      "rejected \{report.rejected}, dropped \{report.dropped}",
    )
  }
  println("\{report.delivered} spans delivered to \{endpoint}")
}
