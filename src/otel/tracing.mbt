// The span one request gets: what the MCP semantic conventions say it is
// called, which attributes it carries, and how a failure is recorded.

///|
/// A tracer bound to a clock, ready to hang a span on every request a server
/// serves.
///
/// The trace a request arrived with is read from its headers, so a server
/// behind an instrumented caller joins the caller's trace instead of starting a
/// second one. A request that carries no context, or one that carries a broken
/// one, starts a trace of its own: refusing a request over a header would lose
/// more than it protects.
///
/// This library never reads a clock of its own; `now` is the caller's, in
/// nanoseconds from any fixed origin, so a replay can drive a request through a
/// timeline it chose.
pub struct Tracing {
  priv tracer : @trace.Tracer
  priv now : () -> Int64
}

///|
/// A tracer over `tracer`, timed by `now`.
pub fn Tracing::new(tracer~ : @trace.Tracer, now~ : () -> Int64) -> Tracing {
  { tracer, now, }
}

///|
/// The layer that opens a server span for every request passing through it.
///
/// A span is opened whether the request is answered or raises, and it ends when
/// the answer is ready. A request that raises is marked an error, carries
/// `error.type` and the JSON-RPC code the client was answered with, and keeps
/// the failure as an exception event, which is what a backend shows beside the
/// trace.
pub fn Tracing::layer(self : Tracing) -> @layers.Layer {
  @layers.Layer::new(name="otel", run=async fn(
    call,
    next,
  ) -> Json raise @exceptions.FastMCPError {
    let started = (self.now)()
    let span = self.start(call, started)
    let answer : Result[Json, @exceptions.FastMCPError] = Ok(next.then(call)) catch {
      error => Err(error)
    }
    let ended = (self.now)()
    match answer {
      Ok(value) => {
        match span {
          Some(span) => {
            span.set_status(@trace.Ok)
            span.finish(at=ended)
          }
          None => ()
        }
        value
      }
      Err(error) => {
        match span {
          Some(span) => {
            let code = @exceptions.to_mcp_error(error).code
            span.set_attribute("error.type", @trace.Str(error_type(error)))
            span.set_attribute(
              "rpc.response.status_code",
              @trace.Int(code.to_int64()),
            )
            span.record_exception(message=error.message(), at=ended)
            span.set_status(@trace.Error(error.message()))
            span.finish(at=ended)
          }
          None => ()
        }
        raise error
      }
    }
  })
}

///|
/// The span for `call`, joined to the trace it arrived with. `None` when the
/// tracer's source of randomness cannot make an id: the request is served
/// untraced rather than refused.
fn Tracing::start(
  self : Tracing,
  call : @layers.Call,
  at : Int64,
) -> @trace.Span? {
  let begun : Result[@trace.Span, @trace.Refused] = Ok(
    self.tracer.start(
      name_of(call),
      parent?=parent_of(call),
      kind=@trace.Server,
      at~,
      attributes=attributes_of(call),
    ),
  ) catch {
    error => Err(error)
  }
  match begun {
    Ok(span) => Some(span)
    Err(_) => None
  }
}

///|
/// What the conventions call the span: the method, and the component name when
/// the request names one. A resource URI stays out of the name, since a server
/// that reads a thousand URIs would otherwise have a thousand span names.
fn name_of(call : @layers.Call) -> String {
  let operation = call.operation.code()
  match call.operation {
    @layers.CallTool | @layers.GetPrompt =>
      if call.name.is_empty() {
        operation
      } else {
        operation + " " + call.name
      }
    _ => operation
  }
}

///|
/// The trace the request carried, as a parent for its span.
fn parent_of(call : @layers.Call) -> @trace.TraceContext? {
  let headers = call.context.headers()
  guard headers.get("traceparent") is Some(traceparent) else { return None }
  let tracestate = headers.get("tracestate").map(state => state[:])
  let parsed : Result[@trace.TraceContext, @trace.Refused] = Ok(
    @propagate.parse(traceparent, tracestate?),
  ) catch {
    // A context that does not parse is the caller's bug; serving the request
    // untraced keeps the failure from becoming an outage.
    error => Err(error)
  }
  match parsed {
    Ok(context) => Some(context)
    Err(_) => None
  }
}

///|
/// The attributes the conventions put on a server span, plus the ones that say
/// which request this was.
fn attributes_of(call : @layers.Call) -> Array[(String, @trace.Value)] {
  let attributes : Array[(String, @trace.Value)] = [
    ("mcp.method.name", @trace.Str(call.operation.code())),
    ("mcp.protocol.version", @trace.Str(call.context.protocol_version())),
  ]
  if !call.name.is_empty() {
    match call.operation {
      @layers.CallTool => {
        attributes.push(("gen_ai.tool.name", @trace.Str(call.name)))
        attributes.push(("gen_ai.operation.name", @trace.Str("execute_tool")))
      }
      @layers.GetPrompt =>
        attributes.push(("gen_ai.prompt.name", @trace.Str(call.name)))
      @layers.ReadResource =>
        attributes.push(("mcp.resource.uri", @trace.Str(call.name)))
      _ => ()
    }
  }
  match request_id_of(call) {
    Some(id) => attributes.push(("jsonrpc.request.id", id))
    None => ()
  }
  attributes
}

///|
/// The JSON-RPC id as an attribute: a number stays a number, an id written as a
/// string stays a string, and `null` is left off.
fn request_id_of(call : @layers.Call) -> @trace.Value? {
  match call.context.request_id() {
    String(id) => Some(@trace.Str(id))
    Number(value, ..) =>
      if value == value.round() {
        Some(@trace.Int(value.to_int64()))
      } else {
        Some(@trace.Double(value))
      }
    _ => None
  }
}

///|
/// The class of failure, as a backend groups them: one name per kind of refusal
/// rather than one per message.
fn error_type(error : @exceptions.FastMCPError) -> String {
  match error {
    @exceptions.Mcp(_) => "protocol_error"
    @exceptions.Validation(_) => "validation_error"
    @exceptions.Resource(_) => "resource_error"
    @exceptions.Tool(_) => "tool_error"
    @exceptions.Prompt(_) => "prompt_error"
    @exceptions.InvalidSignature(_) => "invalid_signature"
    @exceptions.Client(_) => "client_error"
    @exceptions.NotFound(_) | @exceptions.Disabled(_) => "not_found"
    @exceptions.ResourceSecurity(_) => "resource_denied"
    @exceptions.Authorisation(_) | @exceptions.InsufficientScope(..) =>
      "authorization_error"
  }
}
