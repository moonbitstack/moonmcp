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
