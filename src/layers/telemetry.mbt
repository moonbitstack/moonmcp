// A record of what the server did: one span per request, with how long it took
// and whether it ended in an error, and the counters an operator watches.

///|
/// One served request, as the telemetry layer saw it.
#derive(Debug)
pub(all) struct Span {
  operation : Operation
  /// The tool or prompt name, the resource URI, or the empty string for a
  /// listing.
  name : String
  /// How long the request took, in microseconds.
  duration_us : Double
  /// Whether the request ended in an error rather than an answer.
  failed : Bool
}

///|
/// Timing and counting for every request that passes through (← FastMCP's
/// timing and logging middleware, kept as one record a caller can read or
/// forward).
///
/// The last `capacity` spans are kept in memory and every one is handed to
/// `sink`, so a program can print them, write them to its logger, or forward
/// them to a tracing system of its own. A span is recorded whether the request
/// was answered or raised, so a failure is counted where it happened rather
/// than where the client noticed.
pub struct Telemetry {
  priv capacity : Int32
  priv sink : ((Span) -> Unit)?
  priv mut spans : Array[Span]
  priv counts : Map[String, Int32]
  priv mut failures : Int32
  priv mut total : Int32
}

///|
/// A recorder of the last 128 spans, keeping nothing else.
pub fn Telemetry::new(
  capacity~ : Int32 = 128,
  sink? : (Span) -> Unit,
) -> Telemetry {
  { capacity, sink, spans: [], counts: Map([]), failures: 0, total: 0, }
}

///|
/// The layer this recorder installs on a server.
pub fn Telemetry::layer(self : Telemetry) -> Layer {
  Layer::new(name="telemetry", run=async fn(
    call,
    next,
  ) -> Json raise @exceptions.FastMCPError {
    let started = @bench.monotonic_clock_start()
    let answer = {
      errdefer self.record(
        call,
        @bench.monotonic_clock_end(started),
        failed=true,
      )
      next.then(call)
    }
    self.record(call, @bench.monotonic_clock_end(started), failed=false)
    answer
  })
}

///|
/// Keep one span and count it.
fn Telemetry::record(
  self : Telemetry,
  call : Call,
  duration_us : Double,
  failed~ : Bool,
) -> Unit {
  let span = {
    operation: call.operation,
    name: call.name,
    duration_us,
    failed,
  }
  self.total = self.total + 1
  if failed {
    self.failures = self.failures + 1
  }
  let op = call.operation.code()
  self.counts[op] = self.counts.get(op).unwrap_or(0) + 1
  while self.spans.length() >= self.capacity {
    self.spans = self.spans[1:].to_owned()
  }
  self.spans.push(span)
  match self.sink {
    Some(sink) => sink(span)
    None => ()
  }
}

///|
/// The spans kept so far, oldest first.
pub fn Telemetry::spans(self : Telemetry) -> Array[Span] {
  self.spans.copy()
}

///|
/// How many requests of `operation` were served.
pub fn Telemetry::count(self : Telemetry, operation : Operation) -> Int32 {
  self.counts.get(operation.code()).unwrap_or(0)
}

///|
/// How many requests were served, all operations together.
pub fn Telemetry::total(self : Telemetry) -> Int32 {
  self.total
}

///|
/// How many of them ended in an error.
pub fn Telemetry::failures(self : Telemetry) -> Int32 {
  self.failures
}

///|
/// Forget every span and counter recorded so far.
pub fn Telemetry::clear(self : Telemetry) -> Unit {
  self.spans.clear()
  self.counts.clear()
  self.failures = 0
  self.total = 0
}

///|
pub extend Span with Debug::{to_repr}
