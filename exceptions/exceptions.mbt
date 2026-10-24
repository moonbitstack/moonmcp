///|
/// Custom errors for moonmcp, mirroring fastmcp/exceptions.py.
pub(all) suberror FastMCPError {
  /// A wire-format protocol error, already carrying a JSON-RPC code.
  Mcp(@types.ErrorData)
  /// Error in validating parameters or return values.
  Validation(String)
  /// Error in resource operations.
  Resource(String)
  /// Error in tool operations.
  Tool(String)
  /// Error in prompt operations.
  Prompt(String)
  /// Invalid signature for use with moonmcp.
  InvalidSignature(String)
  /// Error in client operations.
  Client(String)
  /// Object not found.
  NotFound(String)
  /// Object is disabled.
  Disabled(String)
  /// A templated resource parameter failed path-security screening.
  ///
  /// Surfaced to the client as an ordinary "not found" so a traversal
  /// attempt is indistinguishable from a request for a missing resource.
  ResourceSecurity(String)
  /// Error when an authorisation check fails.
  Authorisation(String)
  /// Authorisation failed because the token is missing required scopes.
  InsufficientScope(required_scopes~ : Array[String], message~ : String)
} derive(Debug, Eq)

///|
/// Construct an `InsufficientScope` error with the standard message.
pub fn insufficient_scope(required_scopes : Array[String]) -> FastMCPError {
  let named = if required_scopes.is_empty() {
    "(unknown)"
  } else {
    required_scopes.join(", ")
  }
  InsufficientScope(
    required_scopes~,
    message="Insufficient scope. Required: \{named}",
  )
}

///|
/// Translate a moonmcp error into a wire-format error payload.
///
/// `NotFound`, `Disabled` and `Validation` map to `invalid_params` (-32602);
/// an existing `Mcp` payload is returned unchanged so an explicit code chosen
/// upstream survives translation; everything else falls back to
/// `default_code` (`internal_error` by default).
pub fn to_mcp_error(
  exc : FastMCPError,
  default_code~ : Int32 = @types.internal_error,
) -> @types.ErrorData {
  match exc {
    Mcp(data) => data
    NotFound(message) | Disabled(message) | Validation(message) =>
      { code: @types.invalid_params, message, data: None, }
    ResourceSecurity(message) =>
      { code: @types.invalid_params, message, data: None, }
    _ => { code: default_code, message: exc.message(), data: None, }
  }
}

///|
/// Render the human-readable message carried by the error.
pub fn FastMCPError::message(self : FastMCPError) -> String {
  match self {
    Mcp(data) => data.message
    Validation(message)
    | Resource(message)
    | Tool(message)
    | Prompt(message)
    | InvalidSignature(message)
    | Client(message)
    | NotFound(message)
    | Disabled(message)
    | ResourceSecurity(message)
    | Authorisation(message) => message
    InsufficientScope(message~, ..) => message
  }
}

///|
pub extend FastMCPError with Debug::{to_repr}

///|
pub extend FastMCPError with Eq::{not_equal, equal}
