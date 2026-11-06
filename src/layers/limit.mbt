// A ceiling on how often one caller may ask, counted in a token bucket so a
// burst is allowed but the long-run rate is not exceeded.

///|
/// The JSON-RPC code a refusal carries: -32000, the first of the range JSON-RPC
/// leaves to the server for errors of its own.
pub let refused_code : Int32 = -32000

///|
/// A token bucket per caller (← FastMCP's `RateLimitingMiddleware`).
///
/// Each caller starts with a full bucket of `burst` tokens, spends one per
/// call, and gains `rate` tokens a second up to that ceiling. A caller with
/// none left is refused with `refused_code` and told how long to wait; the
/// bucket keeps no token for them, so a caller that keeps asking only waits
/// longer.
///
/// Ten a second, twenty at once, is FastMCP's default. The caller is the
/// subject the authorisation check named, and everyone unauthenticated shares
/// one bucket — give `key` to count by a header or a tool instead. `clock`
/// reads seconds from any fixed origin; the default is the monotonic clock.
pub struct RateLimiting {
  priv rate : Int32
  priv burst : Int32
  priv operations : Array[Operation]
  priv key : (Call) -> String
  priv clock : () -> Double
  priv buckets : Map[String, @moonward.Bucket]
  priv mut refused : Int32
}

///|
/// A limiter of ten calls a second per caller, twenty in a burst.
pub fn RateLimiting::new(
  rate~ : Int32 = 10,
  burst~ : Int32 = 20,
  operations~ : Array[Operation] = [CallTool, ReadResource, GetPrompt],
  key? : (Call) -> String,
  clock? : () -> Double,
) -> RateLimiting {
  let origin = @bench.monotonic_clock_start()
  {
    rate,
    burst,
    operations,
    key: key.unwrap_or(fn(call) { call.subject() }),
    clock: clock.unwrap_or(fn() {
      @bench.monotonic_clock_end(origin) / 1_000_000.0
    }),
    buckets: Map([]),
    refused: 0,
  }
}

///|
/// The layer this limiter installs on a server.
pub fn RateLimiting::layer(self : RateLimiting) -> Layer {
  Layer::new(name="rate limit", run=async fn(
    call,
    next,
  ) -> Json raise @exceptions.FastMCPError {
    guard self.operations.contains(call.operation) else {
      return next.then(call)
    }
    let key = (self.key)(call)
    // moonward counts in nanoseconds and takes the reading from its caller, so
    // the whole policy stays testable with a clock a test moves by hand.
    let now = ((self.clock)() * 1_000_000_000.0).to_int64()
    let bucket = match self.buckets.get(key) {
      Some(bucket) => bucket
      None => {
        let bucket = @moonward.Bucket::new(
          self.rate.to_double(),
          burst=self.burst.to_double(),
          now~,
        )
        self.buckets[key] = bucket
        bucket
      }
    }
    if !bucket.take(now) {
      self.refused = self.refused + 1
      let tokens = bucket.tokens(now)
      let wait_ms = ((1.0 - tokens) / self.rate.to_double() * 1000.0).to_int()
      raise @exceptions.Mcp({
        code: refused_code,
        message: "Rate limit exceeded: retry in \{wait_ms} ms",
        data: Some(Json({ "retryAfterMs": Json(wait_ms) })),
      })
    }
    next.then(call)
  })
}

///|
/// How many calls were refused.
pub fn RateLimiting::refused(self : RateLimiting) -> Int32 {
  self.refused
}

///|
/// How many callers are being counted.
pub fn RateLimiting::callers(self : RateLimiting) -> Int32 {
  self.buckets.length()
}

///|
/// Refill everyone to a full burst, as if no one had called yet.
pub fn RateLimiting::reset(self : RateLimiting) -> Unit {
  self.buckets.clear()
}
