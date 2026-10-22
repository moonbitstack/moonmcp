/// Path-safety policy for templated resource parameters,
/// mirroring fastmcp/resources/security.py.

/// Whether `value` contains `..` as a path component, considering both
/// separators. Dots inside a single segment are not traversal.
pub fn contains_path_traversal(value : String) -> Bool {
  for segment in value.split("/") {
    for piece in segment.to_string().split("\\") {
      if piece.to_string() == ".." {
        return true
      }
    }
  }
  false
}

/// Whether `value` looks like an absolute filesystem path: rooted at `/`
/// or `\\`, UNC-prefixed, or a Windows drive letter path.
pub fn is_absolute_path(value : String) -> Bool {
  if value.has_prefix("/") || value.has_prefix("\\\\") {
    return true
  }
  if value.has_prefix("\\") {
    return true
  }
  // Drive letter form: `C:\` or `C:/`.
  let chars = value.to_array()
  if chars.length() >= 3 {
    let drive = chars[0]
    let is_letter = (drive >= 'a' && drive <= 'z') ||
      (drive >= 'A' && drive <= 'Z')
    if is_letter && chars[1] == ':' && (chars[2] == '/' || chars[2] == '\\') {
      return true
    }
  }
  false
}

/// Security policy applied to extracted resource template parameters.
///
/// The checks run after a URI has matched a template and its parameter
/// values have been extracted and percent-decoded; they catch
/// path-traversal and absolute-path injection regardless of how the value
/// was encoded in the URI.
pub(all) struct ResourceSecurity {
  /// Reject values containing `..` as a path component.
  reject_path_traversal : Bool
  /// Reject values that look like absolute filesystem paths.
  reject_absolute_paths : Bool
  /// Reject values containing NUL.
  reject_null_bytes : Bool
  /// Parameter names to skip all checks for. Hyphenated URI-template
  /// spellings are accepted.
  exempt_params : @set.Set[String]
} derive(Debug, Eq)

/// Secure-by-default policy: traversal, absolute paths and null bytes
/// all rejected.
pub fn ResourceSecurity::default() -> ResourceSecurity {
  {
    reject_path_traversal: true,
    reject_absolute_paths: true,
    reject_null_bytes: true,
    exempt_params: @set.Set::from_array([]),
  }
}

fn ResourceSecurity::is_exempt(self : ResourceSecurity, name : String) -> Bool {
  if self.exempt_params.contains(name) {
    return true
  }
  let mut found = false
  for exempt in self.exempt_params.iter() {
    if exempt.replace(old="-", new="_") == name {
      found = true
      break
    }
  }
  found
}

/// Check all parameter values against the policy. String values (and lists
/// of strings, from wildcard parameters) are screened; non-string values are
/// ignored. Returns the name of the first failing parameter, if any.
pub fn ResourceSecurity::validate(
  self : ResourceSecurity,
  params : Map[String, Json],
) -> String? {
  for name, value in params {
    if self.is_exempt(name) {
      continue
    }
    let candidates : Array[String] = match value {
      String(text) => [text]
      Array(items) =>
        items.filter_map(fn(item) { item.as_string() })
      _ => []
    }
    for candidate in candidates {
      if self.reject_null_bytes && candidate.contains("\u{0}") {
        return Some(name)
      }
      if self.reject_path_traversal && contains_path_traversal(candidate) {
        return Some(name)
      }
      if self.reject_absolute_paths && is_absolute_path(candidate) {
        return Some(name)
      }
    }
  }
  None
}

/// Per-component security setting: inherit the server-wide default,
/// apply an explicit policy, or disable screening.
pub(all) enum ResourceSecuritySetting {
  Inherit
  Explicit(ResourceSecurity)
  Disabled
} derive(Debug, Eq)

/// Resolve the effective policy for a component.
pub fn resolve_security(
  setting : ResourceSecuritySetting,
  server_default : ResourceSecurity?,
) -> ResourceSecurity? {
  match setting {
    Inherit => server_default
    Explicit(policy) => Some(policy)
    Disabled => None
  }
}
