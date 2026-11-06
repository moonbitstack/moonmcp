// The authorization request the browser (or a headless stand-in) is sent to,
// and the redirect that comes back with a code.

///|
/// The state parameter of an authorization request: a value the client makes up
/// and checks on the way back, so a redirect it did not cause is not taken.
pub fn new_state() -> String raise Refused {
  let bytes = FixedArray::make(16, b'\x00')
  let rng = @auto.rng() catch {
    _ => raise Refused(message="no entropy to draw a state from")
  }
  rng.fill(bytes)
  @base64.encode(Bytes::from_array(bytes)[:], kind=Url, padding=false)
}

///|
/// The URL to send the user to: `response_type=code`, the client, the redirect,
/// the state, the S256 challenge, and the resource indicator RFC 8707 asks for.
pub fn authorize_url(
  server : Server,
  registration : Registration,
  redirect_uri : String,
  state : String,
  pkce : Pkce,
  scope? : String,
  resource? : String,
) -> String raise Refused {
  guard server.serves_authorization_code() else {
    raise Refused(
      message="the authorization server does not offer the code flow with S256",
    )
  }
  guard server.authorization_endpoint is Some(endpoint) else {
    raise Refused(
      message="the authorization server names no authorization endpoint",
    )
  }
  with_query(
    endpoint,
    [
      ("response_type", "code"),
      ("client_id", registration.client_id),
      ("redirect_uri", redirect_uri),
      ("state", state),
      ("code_challenge", pkce.challenge),
      ("code_challenge_method", "S256"),
      ..match scope {
        Some(scope) => [("scope", scope)]
        None => []
      },
      ..match resource {
        Some(resource) => [("resource", resource)]
        None => []
      },
    ],
  )
}

///|
/// The code and state a redirect carried, or why there is none.
#derive(Debug, Eq)
pub(all) struct Redirect {
  code : String
  state : String?
}

///|
/// Read a redirect back: the `code`, the `state` to compare with the one sent,
/// and an `error` if the server refused instead.
pub fn Redirect::parse(url : String) -> Redirect raise Refused {
  let query = query_of(url)
  match query_value(query, "error") {
    Some(error) => {
      let why = match query_value(query, "error_description") {
        Some(why) => ": " + why
        None => ""
      }
      raise Refused(message="the authorization server refused: \{error}\{why}")
    }
    None => ()
  }
  match query_value(query, "code") {
    Some(code) => { code, state: query_value(query, "state"), }
    None => raise Refused(message="the redirect carried no code")
  }
}

///|
pub extend Redirect with Debug::{to_repr}

///|
pub extend Redirect with Eq::{not_equal, equal}
