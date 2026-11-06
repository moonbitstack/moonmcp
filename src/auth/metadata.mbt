// The two documents an OAuth client reads before it can ask for a token: the
// protected resource metadata of RFC 9728, which says who vouches for this
// resource, and the authorization server metadata of RFC 8414 (or OpenID
// Connect Discovery), which says where to register, to authorize and to get a
// token.
//
// Both are read leniently: a field the document leaves out is a capability the
// server does not advertise, and only the fields a flow cannot go on without
// are required.

///|
/// Why an OAuth client could not go on, in words a person reads.
pub(all) suberror Refused {
  Refused(message~ : String)
}

///|
/// What a protected resource says about itself (RFC 9728): the identifier
/// tokens for it must be minted for, and the authorization servers that mint
/// them.
#derive(Debug, Eq)
pub(all) struct Resource {
  resource : String
  authorization_servers : Array[String]
  scopes_supported : Array[String]?
}

///|
/// What an authorization server says it can do (RFC 8414 and OpenID Connect
/// Discovery). A field the document leaves out keeps the default the metadata
/// specification gives it, except where the default is "not offered".
#derive(Debug, Eq)
pub(all) struct Server {
  issuer : String
  authorization_endpoint : String?
  token_endpoint : String
  registration_endpoint : String?
  scopes_supported : Array[String]?
  response_types_supported : Array[String]
  grant_types_supported : Array[String]
  token_endpoint_auth_methods_supported : Array[String]
  token_endpoint_auth_signing_alg_values_supported : Array[String]
  code_challenge_methods_supported : Array[String]?
  client_id_metadata_document_supported : Bool
}

///|
/// The `Bearer` challenge of a `401` or `403`: where the resource metadata is,
/// which scope would satisfy it, and what went wrong.
#derive(Debug, Eq)
pub(all) struct Challenge {
  resource_metadata : String?
  scope : String?
  error : String?
  error_description : String?
}

///|
/// Read a JSON object, or refuse.
fn object_of(json : Json) -> Map[String, Json] raise Refused {
  match json {
    Object(fields) => fields
    _ => raise Refused(message="expected a JSON object")
  }
}

///|
/// A string field, or `None` when it is absent or another type.
fn text_field(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
/// A string field a document cannot do without.
fn required_text(
  fields : Map[String, Json],
  key : String,
  of : String,
) -> String raise Refused {
  match text_field(fields, key) {
    Some(value) => value
    None => raise Refused(message="\{of} has no \{key}")
  }
}

///|
/// A field that is a list of strings: absent and not-a-list both read as empty.
fn text_list(fields : Map[String, Json], key : String) -> Array[String] {
  match fields.get(key) {
    Some(Array(items)) =>
      items.filter_map(item => {
        match item {
          String(text) => Some(text)
          _ => None
        }
      })
    _ => []
  }
}

///|
/// Read protected resource metadata.
pub fn Resource::parse(json : Json) -> Resource raise Refused {
  let fields = object_of(json)
  {
    resource: required_text(fields, "resource", "protected resource metadata"),
    authorization_servers: text_list(fields, "authorization_servers"),
    scopes_supported: match fields.get("scopes_supported") {
      Some(Array(_)) => Some(text_list(fields, "scopes_supported"))
      _ => None
    },
  }
}

///|
/// Read authorization server metadata. `issuer` and `token_endpoint` are the
/// two a client cannot work without.
pub fn Server::parse(json : Json) -> Server raise Refused {
  let fields = object_of(json)
  let authorization_endpoint = text_field(fields, "authorization_endpoint")
  let response_types = text_list(fields, "response_types_supported")
  let code_challenges = match fields.get("code_challenge_methods_supported") {
    Some(Array(_)) =>
      Some(text_list(fields, "code_challenge_methods_supported"))
    _ => None
  }
  {
    issuer: required_text(fields, "issuer", "authorization server metadata"),
    authorization_endpoint,
    token_endpoint: required_text(
      fields, "token_endpoint", "authorization server metadata",
    ),
    registration_endpoint: text_field(fields, "registration_endpoint"),
    scopes_supported: match fields.get("scopes_supported") {
      Some(Array(_)) => Some(text_list(fields, "scopes_supported"))
      _ => None
    },
    response_types_supported: if response_types.is_empty() {
      ["code"]
    } else {
      response_types
    },
    grant_types_supported: match fields.get("grant_types_supported") {
      Some(Array(_)) => text_list(fields, "grant_types_supported")
      _ => ["authorization_code", "implicit"]
    },
    token_endpoint_auth_methods_supported: match
      fields.get("token_endpoint_auth_methods_supported") {
      Some(Array(_)) =>
        text_list(fields, "token_endpoint_auth_methods_supported")
      // RFC 8414 §2: the default is client_secret_basic.
      _ => ["client_secret_basic"]
    },
    token_endpoint_auth_signing_alg_values_supported: text_list(
      fields, "token_endpoint_auth_signing_alg_values_supported",
    ),
    code_challenge_methods_supported: code_challenges,
    client_id_metadata_document_supported: match
      fields.get("client_id_metadata_document_supported") {
      Some(True) => true
      _ => false
    },
  }
}

///|
/// The documents to try for protected resource metadata, in the order the
/// specification asks for: the one a challenge pointed at, else the path-aware
/// location, else the root. A server that publishes the path-aware location is
/// not asked for the root one — a client that asks both is told apart by that.
pub fn Resource::probes(
  resource_url : String,
  hinted? : String,
) -> Array[String] {
  match hinted {
    Some(url) => [url]
    None => {
      let origin = origin_of(resource_url)
      let path = trimmed_path_of(resource_url)
      let pathbased = "\{origin}/.well-known/oauth-protected-resource\{path}"
      if path.is_empty() {
        [origin + "/.well-known/oauth-protected-resource"]
      } else {
        [pathbased, origin + "/.well-known/oauth-protected-resource"]
      }
    }
  }
}

///|
/// The documents to try for authorization server metadata, in the order RFC
/// 8414 and OpenID Connect Discovery put them: the path inserted after the
/// well-known prefix, then the two OpenID spellings.
pub fn Server::probes(authorization_server : String) -> Array[String] {
  let origin = origin_of(authorization_server)
  let path = trimmed_path_of(authorization_server)
  if path.is_empty() {
    [
      "\{origin}/.well-known/oauth-authorization-server",
      "\{origin}/.well-known/openid-configuration",
    ]
  } else {
    [
      "\{origin}/.well-known/oauth-authorization-server\{path}",
      "\{origin}/.well-known/openid-configuration\{path}",
      "\{origin}\{path}/.well-known/openid-configuration",
    ]
  }
}

///|
/// The endpoints a 2025-03-26 server has when it publishes no metadata at all:
/// the three OAuth paths at the server's own root (MCP's authorization section
/// before it named RFC 8414).
pub fn Server::at_root(base : String) -> Server {
  let origin = origin_of(base)
  {
    issuer: origin,
    authorization_endpoint: Some(origin + "/authorize"),
    token_endpoint: origin + "/token",
    registration_endpoint: Some(origin + "/register"),
    scopes_supported: None,
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    token_endpoint_auth_methods_supported: ["client_secret_basic"],
    token_endpoint_auth_signing_alg_values_supported: [],
    code_challenge_methods_supported: Some(["S256"]),
    client_id_metadata_document_supported: false,
  }
}

///|
/// Whether this server can run an authorization-code flow with PKCE.
pub fn Server::serves_authorization_code(self : Server) -> Bool {
  if !self.response_types_supported.contains("code") {
    return false
  }
  match self.code_challenge_methods_supported {
    Some(methods) => methods.contains("S256")
    None => true
  }
}

///|
/// Whether this server offers the `grant`.
pub fn Server::offers(self : Server, grant : String) -> Bool {
  self.grant_types_supported.contains(grant)
}

///|
/// Read the `Bearer` challenge out of a `WWW-Authenticate` header. Parameters
/// are `name=value` with the value optionally quoted; a name repeated keeps the
/// first, which is what a client needs.
pub fn Challenge::parse(header : String) -> Challenge? {
  let rest = match header.to_lower().find("bearer") {
    Some(at) => header.exact_view(start=at + 6).to_owned()
    None => return None
  }
  let fields : Map[String, String] = Map([])
  let mut at = 0
  let text = rest
  while at < text.length() {
    // Skip what separates parameters: spaces and commas.
    while at < text.length() &&
          (text[at] == ' ' || text[at] == ',' || text[at] == '\t') {
      at += 1
    }
    guard at < text.length() else { break }
    let name_start = at
    while at < text.length() && text[at] != '=' && text[at] != ',' {
      at += 1
    }
    guard at < text.length() && text[at] == '=' else { break }
    let name = text
      .exact_view(start=name_start, end=at)
      .to_owned()
      .trim(chars=" \t")
      .to_owned()
      .to_lower()
    at += 1
    let value = if at < text.length() && text[at] == '"' {
      at += 1
      let start = at
      while at < text.length() && text[at] != '"' {
        at += 1
      }
      let value = text.exact_view(start~, end=at).to_owned()
      if at < text.length() {
        at += 1
      }
      value
    } else {
      let start = at
      while at < text.length() && text[at] != ',' && text[at] != ' ' {
        at += 1
      }
      text.exact_view(start~, end=at).to_owned()
    }
    if !fields.contains(name) {
      fields[name] = value
    }
  }
  Some({
    resource_metadata: fields.get("resource_metadata"),
    scope: fields.get("scope"),
    error: fields.get("error"),
    error_description: fields.get("error_description"),
  })
}

///|
/// The `error` and `error_description` of an OAuth error body, in one line.
fn refused_text(fields : Map[String, Json], what : String) -> String {
  let error = text_field(fields, "error").unwrap_or("error")
  match text_field(fields, "error_description") {
    Some(why) => "\{what}: \{error}: \{why}"
    None => "\{what}: \{error}"
  }
}

///|
pub extend Resource with Debug::{to_repr}

///|
pub extend Resource with Eq::{not_equal, equal}

///|
pub extend Server with Debug::{to_repr}

///|
pub extend Server with Eq::{not_equal, equal}

///|
pub extend Challenge with Debug::{to_repr}

///|
pub extend Challenge with Eq::{not_equal, equal}
