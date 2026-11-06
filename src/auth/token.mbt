// An access token as the token endpoint hands it out, and the two requests that
// ask for one: the authorization-code exchange, which every interactive client
// makes, and the client-credentials grant, for a client acting as itself.

///|
/// What the token endpoint answered.
#derive(Debug, Eq)
pub(all) struct Tokens {
  access_token : String
  token_type : String
  expires_in : Int64?
  refresh_token : String?
  scope : String?
}

///|
/// Read a token response. `access_token` is the only field a client cannot do
/// without; a server that omits `token_type` is taken at its word that the token
/// goes in the `Authorization` header.
pub fn Tokens::parse(json : Json) -> Tokens raise Refused {
  let fields = object_of(json)
  if fields.get("error") is Some(String(_)) {
    raise Refused(message=refused_text(fields, "the token endpoint refused"))
  }
  {
    access_token: required_text(fields, "access_token", "token response"),
    token_type: text_field(fields, "token_type").unwrap_or("Bearer"),
    expires_in: match fields.get("expires_in") {
      Some(Number(value, ..)) => Some(value.to_int64())
      _ => None
    },
    refresh_token: text_field(fields, "refresh_token"),
    scope: text_field(fields, "scope"),
  }
}

///|
/// When the token stops being good, in seconds since the epoch, measured from
/// `issued`; `None` when it names no lifetime, which a client reads as "until
/// the server says otherwise".
pub fn Tokens::good_until(self : Tokens, issued : Int64) -> Int64? {
  match self.expires_in {
    Some(lifetime) => Some(issued + lifetime)
    None => None
  }
}

///|
/// The token a refresh left this client with. A server may rotate the refresh
/// token, so a response that carries one replaces the old; one that carries
/// none leaves the old in place rather than throwing the only key away. The
/// same holds for the scope: what a response does not name is what was asked
/// for, which is what this client already had.
pub fn Tokens::renewed(self : Tokens, fresh : Tokens) -> Tokens {
  {
    access_token: fresh.access_token,
    token_type: fresh.token_type,
    expires_in: fresh.expires_in,
    refresh_token: match fresh.refresh_token {
      Some(token) => Some(token)
      None => self.refresh_token
    },
    scope: match fresh.scope {
      Some(scope) => Some(scope)
      None => self.scope
    },
  }
}

///|
/// The body of an authorization-code exchange (RFC 6749 §4.1.3) with the PKCE
/// verifier and the RFC 8707 resource indicator.
pub fn authorization_code_form(
  code~ : String,
  redirect_uri~ : String,
  verifier~ : String,
  resource? : String,
  scope? : String,
) -> Array[(String, String)] {
  let form = [
    ("grant_type", "authorization_code"),
    ("code", code),
    ("redirect_uri", redirect_uri),
    ("code_verifier", verifier),
  ]
  with_optional(with_optional(form, "resource", resource), "scope", scope)
}

///|
/// The body of a client-credentials request (RFC 6749 §4.4).
pub fn client_credentials_form(
  resource? : String,
  scope? : String,
) -> Array[(String, String)] {
  let form = [("grant_type", "client_credentials")]
  with_optional(with_optional(form, "resource", resource), "scope", scope)
}

///|
/// The body of a refresh (RFC 6749 §6).
pub fn refresh_form(
  refresh_token~ : String,
  resource? : String,
  scope? : String,
) -> Array[(String, String)] {
  let form = [("grant_type", "refresh_token"), ("refresh_token", refresh_token)]
  with_optional(with_optional(form, "resource", resource), "scope", scope)
}

///|
/// `pairs` with one more, or as they were when there is nothing to add.
fn with_optional(
  pairs : Array[(String, String)],
  name : String,
  value : String?,
) -> Array[(String, String)] {
  match value {
    Some(value) => [..pairs, (name, value)]
    None => pairs
  }
}

///|
pub extend Tokens with Debug::{to_repr}

///|
pub extend Tokens with Eq::{not_equal, equal}

///|
/// Which grant a client is set up to use: the interactive one, or the one a
/// client makes on its own behalf.
#derive(Debug, Eq)
pub(all) enum Grant {
  AuthorizationCode
  ClientCredentials
}

///|
pub extend Grant with Debug::{to_repr}

///|
pub extend Grant with Eq::{not_equal, equal}
