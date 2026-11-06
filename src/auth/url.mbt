// The parts of a URL an OAuth client has to take apart: RFC 9728 and RFC 8414
// both hang a document off the authority or off the path, and the endpoints
// they name are then called with a query this builds.

///|
/// Everything in `url` before its path: scheme, authority, and nothing else.
pub fn origin_of(url : String) -> String {
  match url.find("://") {
    Some(colon) =>
      match url.exact_view(start=colon + 3).to_owned().find("/") {
        Some(slash) => url.exact_view(end=colon + 3 + slash).to_owned()
        None => url
      }
    None => url
  }
}

///|
/// The path of `url`, from the slash after the authority up to the query or
/// fragment. `/` when it has none, which is what the well-known lookups expect.
pub fn path_of(url : String) -> String {
  let rest = match url.find("://") {
    Some(colon) => url.exact_view(start=colon + 3).to_owned()
    None => url
  }
  let from_authority = match rest.find("/") {
    Some(slash) => rest.exact_view(start=slash).to_owned()
    None => return "/"
  }
  let path = match from_authority.find("?") {
    Some(at) => from_authority.exact_view(end=at).to_owned()
    None => from_authority
  }
  if path.is_empty() {
    "/"
  } else {
    path
  }
}

///|
/// The path of `url` without its trailing slash, which is the form the
/// well-known prefixes are built from.
pub fn trimmed_path_of(url : String) -> String {
  let path = path_of(url)
  if path == "/" {
    ""
  } else if path.has_suffix("/") {
    path.exact_view(end=path.length() - 1).to_owned()
  } else {
    path
  }
}

///|
/// `url` with `query` as its query, replacing one it had.
pub fn with_query(url : String, query : Array[(String, String)]) -> String {
  let base = match url.find("?") {
    Some(at) => url.exact_view(end=at).to_owned()
    None => url
  }
  if query.is_empty() {
    return base
  }
  let pairs = query.map(pair => {
    let (name, value) = pair
    "\{@moonurl.escape_text(name, kind=@moonurl.Query)}=\{@moonurl.escape_text(value, kind=@moonurl.Query)}"
  })
  base + "?" + pairs.join("&")
}

///|
/// The whole of `url` as a request line carries it: path and query.
pub fn target_of(url : String) -> String {
  let origin = origin_of(url)
  if origin.length() >= url.length() {
    "/"
  } else {
    url.exact_view(start=origin.length()).to_owned()
  }
}

///|
/// The value of `name` in a query string, with `+` read as a space as
/// `application/x-www-form-urlencoded` says and the escapes decoded.
pub fn query_value(query : String, name : String) -> String? {
  for pair in query.split("&") {
    let (key, value) = match pair.find("=") {
      Some(at) =>
        (
          pair.exact_view(end=at).to_owned(),
          pair.exact_view(start=at + 1).to_owned(),
        )
      None => (pair.to_owned(), "")
    }
    if key == name {
      let spaced = value.replace_all(old="+", new=" ")
      return Some(@moonurl.unescape_text(spaced))
    }
  }
  None
}

///|
/// The query of `url`, without the `?`.
pub fn query_of(url : String) -> String {
  match url.find("?") {
    Some(at) => url.exact_view(start=at + 1).to_owned()
    None => ""
  }
}

///|
/// Whether `url` names the same resource as `expected`: the scheme and host
/// compared without regard to case, the rest exactly. RFC 8707 lets a client
/// refuse a protected resource that names another origin.
pub fn same_origin(url : String, expected : String) -> Bool {
  origin_of(url).to_lower() == origin_of(expected).to_lower()
}
