// The spans leaving the process: OTLP over HTTP, wired once, with the resource
// and the instrumentation scope a moonmcp server should be found under.
//
// A package of its own because it takes an HTTP stack, which a program that
// only turns spans on for a test does not need.

///|
/// The address a collector listens on when it is started with its defaults.
pub let default_endpoint : String = "http://localhost:4318"

///|
/// A trace exporter that posts to `endpoint`, a collector's base address; the
/// `/v1/traces` path is added. Hand it to `@trace.Tracer::new(sink=...)` and
/// the span of every request the server serves leaves the process on its own,
/// batched and retried as the protocol asks.
///
/// The spans are marked as coming from `moonbitstack/moonmcp` and resource-tagged
/// with `service`, so a backend groups them by the program that served them.
///
/// `headers` ride on every request, for a collector that wants a token.
/// `encoding` is moontel's: the JSON mapping when it is not given,
/// `@binary.protobuf` from `moontel/otlp/binary` for the binary one.
/// `transport` is for a program that already owns a client — one behind a proxy,
/// or one that records what it was asked to send instead of sending it. `now`
/// counts milliseconds and is what batching and the retry budget are measured
/// with; `rand` makes the jitter of a retry.
pub fn traces(
  endpoint~ : String = default_endpoint,
  service~ : String = "moonmcp",
  headers~ : Array[(String, String)] = [],
  encoding? : &@otlp.Encoding,
  transport? : &@otlp.Transport,
  now~ : () -> Int64,
  rand~ : (Int32) -> Bytes,
) -> @otlp.TraceExporter {
  let carrier : &@otlp.Transport = match transport {
    Some(carrier) => carrier
    None => @collector.HttpTransport::new()
  }
  @otlp.TraceExporter::new(
    transport=carrier,
    endpoint~,
    headers~,
    resource=@otlp.Resource::of_service(service),
    scope=@otlp.Scope::new(name="moonbitstack/moonmcp"),
    encoding?,
    now~,
    rand~,
  )
}
