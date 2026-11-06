// Which scope to ask for. There is one order, and it is the protocol's
// (SEP-835): what the server asked for in its challenge first, because that is
// the scope that satisfies the request at hand; then what the resource says it
// supports; then whatever the client was configured with.

///|
/// The scope for an authorization request. `None` when nothing names one, in
/// which case the request carries no `scope` parameter at all: sending an empty
/// one is not the same thing to every server.
pub fn scope_for(
  challenge : Challenge?,
  resource : Resource?,
  configured : String?,
) -> String? {
  if challenge is Some(challenge) {
    if challenge.scope is Some(scope) &&
      !scope.trim(chars=" ").to_owned().is_empty() {
      return Some(scope)
    }
  }
  if resource is Some(resource) {
    if resource.scopes_supported is Some(scopes) && !scopes.is_empty() {
      return Some(scopes.join(" "))
    }
  }
  configured
}

///|
/// Whether every scope `asked` names is one `granted` already carries. A
/// challenge that names no scope asks nothing new; one that names a scope this
/// client was never granted is a step up, and a refresh cannot answer it
/// (RFC 6749 §6 keeps a refresh inside the scope it was given).
pub fn scope_within(asked : String?, granted : String?) -> Bool {
  guard asked is Some(asked) else { return true }
  guard granted is Some(granted) else { return false }
  let held : Array[String] = []
  for piece in granted.split(" ") {
    let scope = piece.to_owned()
    if !scope.is_empty() && !held.contains(scope) {
      held.push(scope)
    }
  }
  for piece in asked.split(" ") {
    let scope = piece.to_owned()
    if !scope.is_empty() && !held.contains(scope) {
      return false
    }
  }
  true
}

///|
/// The scope to ask for when this client wants a refresh token. The
/// authorization server's own `offline_access` is what makes it hand one out,
/// and a server that does not list it must not be asked (SEP-2207). The
/// client-credentials grant gets no refresh token at all (RFC 6749 §4.4.3), so
/// nothing is added for it.
pub fn with_offline_access(
  scope : String?,
  server : Server,
  grant : Grant,
) -> String? {
  guard grant is AuthorizationCode else { return scope }
  match server.scopes_supported {
    Some(supported) =>
      if supported.contains("offline_access") {
        widen_scope(scope, Some("offline_access"))
      } else {
        scope
      }
    None => scope
  }
}

///|
/// The union of two scope strings, the current one first, without repeats.
pub fn widen_scope(current : String?, asked : String?) -> String? {
  guard asked is Some(asked) else { return current }
  let seen : Array[String] = []
  for at in 0..<2 {
    let text = if at == 0 { current.unwrap_or("") } else { asked }
    for piece in text.split(" ") {
      let scope = piece.to_owned()
      if !scope.is_empty() && !seen.contains(scope) {
        seen.push(scope)
      }
    }
  }
  if seen.is_empty() {
    None
  } else {
    Some(seen.join(" "))
  }
}
