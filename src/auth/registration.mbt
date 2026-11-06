// What the client registers and what the server answers, plus how the token
// endpoint is asked to authenticate the client (RFC 7591, RFC 6749 §2.3.1 and
// the URL-based client identifiers of MCP's client metadata documents).

///|
/// What a client says about itself: at registration, and in the document a
/// URL client identifier points at.
#derive(Debug, Eq)
pub(all) struct Metadata {
  client_name : String
  redirect_uris : Array[String]
  grant_types : Array[String]
  response_types : Array[String]
  token_endpoint_auth_method : String
  scope : String?
}

///|
/// A client's metadata. `refresh_token` is among the grants because a client
/// that can keep a session wants one; `none` is the authentication method of a
/// public client that a loopback redirect makes safe with PKCE.
pub fn Metadata::new(
  client_name~ : String,
  redirect_uris~ : Array[String],
  scope? : String,
  grant_types~ : Array[String] = ["authorization_code", "refresh_token"],
  response_types~ : Array[String] = ["code"],
  token_endpoint_auth_method~ : String = "none",
) -> Metadata {
  {
    client_name,
    redirect_uris,
    grant_types,
    response_types,
    token_endpoint_auth_method,
    scope,
  }
}

///|
/// The body of a registration request.
pub fn Metadata::body(self : Metadata) -> Map[String, Json] {
  let out : Map[String, Json] = {
    "client_name": Json::string(self.client_name),
    "redirect_uris": Json::array(self.redirect_uris.map(Json::string)),
    "grant_types": Json::array(self.grant_types.map(Json::string)),
    "response_types": Json::array(self.response_types.map(Json::string)),
    "token_endpoint_auth_method": Json::string(self.token_endpoint_auth_method),
  }
  if self.scope is Some(scope) {
    out["scope"] = Json::string(scope)
  }
  out
}

///|
/// What a client is known by: the identifier the server issued, or the one a
/// deployment was given, and the secret if it has one.
#derive(Debug, Eq)
pub(all) struct Registration {
  client_id : String
  client_secret : String?
  token_endpoint_auth_method : String?
}

///|
/// Read a registration response.
pub fn Registration::parse(json : Json) -> Registration raise Refused {
  let fields = object_of(json)
  {
    client_id: required_text(fields, "client_id", "registration response"),
    client_secret: text_field(fields, "client_secret"),
    token_endpoint_auth_method: text_field(fields, "token_endpoint_auth_method"),
  }
}

///|
/// How the token endpoint is asked to authenticate the client.
#derive(Debug, Eq)
pub(all) enum Credentials {
  Basic
  Post
  Public
}

///|
/// The method to use, given what the server says it supports and how the client
/// was registered. Priority is the one a client that holds a secret should
/// follow: what registration returned when the server lists it, else HTTP
/// Basic, else the secret in the body, else nothing.
pub fn Credentials::select(
  registration : Registration,
  supported : Array[String],
) -> Credentials {
  let registered = registration.token_endpoint_auth_method
  if registered is Some(choice) {
    let usable = supported.is_empty() || supported.contains(choice)
    if usable {
      match choice {
        "client_secret_basic" => return Basic
        "client_secret_post" => return Post
        "none" => return Public
        _ => ()
      }
    }
  }
  let has_secret = registration.client_secret is Some(_)
  if has_secret &&
    (supported.is_empty() || supported.contains("client_secret_basic")) {
    return Basic
  }
  if has_secret && supported.contains("client_secret_post") {
    return Post
  }
  if supported.contains("none") || !has_secret {
    return Public
  }
  Post
}

///|
/// The `Authorization` header value for this method, when it uses one. Basic
/// credentials are `client_id:client_secret` in base64, both percent-encoded
/// as RFC 6749 §2.3.1 requires.
pub fn Credentials::authorization(
  self : Credentials,
  registration : Registration,
) -> String? {
  match self {
    Basic =>
      match registration.client_secret {
        Some(secret) => {
          let pair = "\{percent_encode(registration.client_id)}:\{percent_encode(secret)}"
          Some(
            "Basic " +
            @base64.encode(@utf8.encode(pair)[:], kind=Std, padding=true),
          )
        }
        None => None
      }
    _ => None
  }
}

///|
/// The fields this method puts in the token request's body.
pub fn Credentials::form(
  self : Credentials,
  registration : Registration,
) -> Array[(String, String)] {
  match self {
    Basic => []
    Post =>
      [
        ("client_id", registration.client_id),
        ..match registration.client_secret {
          Some(secret) => [("client_secret", secret)]
          None => []
        },
      ]
    Public => [("client_id", registration.client_id)]
  }
}

///|
/// Percent-encode everything but the unreserved characters, which is what a
/// form body and an OAuth parameter take.
pub fn percent_encode(text : StringView) -> String {
  let out = StringBuilder::StringBuilder()
  for byte in @utf8.encode(text) {
    let code = byte.to_int()
    let unreserved = (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      (code >= 0x30 && code <= 0x39) ||
      code == 0x2D ||
      code == 0x2E ||
      code == 0x5F ||
      code == 0x7E
    if unreserved {
      out.write_char(code.unsafe_to_char())
    } else {
      out.write_char('%')
      out.write_char(hex_digit(code / 16))
      out.write_char(hex_digit(code % 16))
    }
  }
  out.to_string()
}

///|
/// One uppercase hexadecimal digit.
fn hex_digit(value : Int32) -> Char {
  if value < 10 {
    (0x30 + value).unsafe_to_char()
  } else {
    (0x41 + value - 10).unsafe_to_char()
  }
}

///|
/// `pairs` as an `application/x-www-form-urlencoded` body.
pub fn form_encode(pairs : Array[(String, String)]) -> String {
  pairs
  .map(pair => "\{percent_encode(pair.0)}=\{percent_encode(pair.1)}")
  .join("&")
}

///|
pub extend Metadata with Debug::{to_repr}

///|
pub extend Metadata with Eq::{not_equal, equal}

///|
pub extend Registration with Debug::{to_repr}

///|
pub extend Registration with Eq::{not_equal, equal}

///|
pub extend Credentials with Debug::{to_repr}

///|
pub extend Credentials with Eq::{not_equal, equal}
