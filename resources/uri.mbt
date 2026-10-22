/// RFC 6570 URI template machinery mirroring fastmcp/resources/template.py.
///
/// Supports the same subset as fastmcp: `{var}` simple path parameters,
/// `{var*}` wildcard path parameters and `{?a,b}` / `{?list*}` query blocks.

/// RFC 3986 reserved characters, which stay as written in a template literal.
let reserved : String = ":/?#[]@!$&'()*+,;="

fn is_unreserved_char(ch : Char) -> Bool {
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= 'a' && ch <= 'z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '-' || ch == '.' || ch == '_' || ch == '~'
}

fn hex_digit_value(ch : Char) -> Int? {
  if ch >= '0' && ch <= '9' {
    Some(ch.to_int() - '0'.to_int())
  } else if ch >= 'a' && ch <= 'f' {
    Some(ch.to_int() - 'a'.to_int() + 10)
  } else if ch >= 'A' && ch <= 'F' {
    Some(ch.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

fn is_hex_digit(ch : Char) -> Bool {
  hex_digit_value(ch) is Some(_)
}

fn write_hex_byte(buf : StringBuilder, byte : Byte) -> Unit {
  let digits = "0123456789ABCDEF"
  buf.write_char('%')
  buf.write_char(digits.get_char((byte / 16).to_int()).unwrap())
  buf.write_char(digits.get_char((byte % 16).to_int()).unwrap())
}

/// Percent-encode `text`, keeping unreserved characters plus `safe`.
pub fn pct_encode(text : String, safe~ : String = "") -> String {
  let buf = StringBuilder::StringBuilder()
  for ch in text {
    if is_unreserved_char(ch) || (safe.length() > 0 && safe.contains(ch.to_string())) {
      buf.write_char(ch)
    } else {
      for byte in @utf8.encode(ch.to_string()) {
        write_hex_byte(buf, byte)
      }
    }
  }
  buf.to_string()
}

/// Percent-encode literal template text per RFC 6570 section 3.1.
///
/// Existing `%XX` triplets pass through so an already-encoded literal is not
/// encoded twice; everything else keeps reserved and unreserved characters
/// and encodes the rest.
pub fn encode_literal(text : String) -> String {
  let chars = text.to_array()
  let buf = StringBuilder::StringBuilder()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '%' &&
      i + 2 < chars.length() &&
      is_hex_digit(chars[i + 1]) &&
      is_hex_digit(chars[i + 2]) {
      buf.write_char(chars[i])
      buf.write_char(chars[i + 1])
      buf.write_char(chars[i + 2])
      i += 3
    } else {
      let ch = chars[i]
      if is_unreserved_char(ch) || reserved.contains(ch.to_string()) {
        buf.write_char(ch)
      } else {
        for byte in @utf8.encode(ch.to_string()) {
          write_hex_byte(buf, byte)
        }
      }
      i += 1
    }
  }
  buf.to_string()
}

fn unquote(value : String) -> String {
  @percent.decode_lossy(value)
}

fn unquote_plus(value : String) -> String {
  @percent.decode_lossy(value.replace(old="+", new="%20"))
}

/// One parsed chunk of a template's path portion.
pub(all) enum TemplateSegment {
  Literal(Array[Char])
  PathVar(name~ : String, wildcard~ : Bool)
}

fn strip_query_blocks(uri_template : String) -> String {
  let buf = StringBuilder::StringBuilder()
  let chars = uri_template.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '{' && i + 1 < chars.length() && chars[i + 1] == '?' {
      let mut j = i + 2
      while j < chars.length() && chars[j] != '}' {
        j += 1
      }
      if j < chars.length() {
        i = j + 1
      } else {
        buf.write_char(chars[i])
        i += 1
      }
    } else {
      buf.write_char(chars[i])
      i += 1
    }
  }
  buf.to_string()
}

/// Parse the path portion of a URI template into literal and variable
/// segments; query blocks are dropped for path matching.
pub fn parse_template(uri_template : String) -> Array[TemplateSegment] {
  let stripped = strip_query_blocks(uri_template)
  let segments : Array[TemplateSegment] = []
  let chars = stripped.to_array()
  let buf : Array[Char] = []
  fn flush(segments : Array[TemplateSegment], buf : Array[Char]) -> Unit {
    if buf.length() > 0 {
      segments.push(Literal(buf.copy()))
      buf.clear()
    }
  }
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '{' {
      let mut j = i + 1
      while j < chars.length() && chars[j] != '}' {
        j += 1
      }
      if j < chars.length() {
        flush(segments, buf)
        let name_buf = StringBuilder::StringBuilder()
        let mut k = i + 1
        while k < j {
          name_buf.write_char(chars[k])
          k += 1
        }
        let mut name = name_buf.to_string()
        let mut wildcard = false
        if name.has_suffix("*") {
          wildcard = true
          name = name[:name.length() - 1].to_string()
        }
        segments.push(PathVar(name~, wildcard~))
        i = j + 1
        continue
      }
    }
    buf.push(chars[i])
    i += 1
  }
  flush(segments, buf)
  segments
}

/// Extract query parameter names from RFC 6570 `{?param1,param2}` syntax.
///
/// The explode modifier is stripped, so `{?tags*}` yields `tags`.
pub fn extract_query_params(uri_template : String) -> Array[String] {
  let names : Array[String] = []
  let block = query_block(uri_template)
  guard block is Some(inner) else { return names }
  for raw in inner.split(",") {
    let name = raw.to_string().trim()
    if name.has_suffix("*") {
      names.push(name[:name.length() - 1].to_string())
    } else {
      names.push(name.to_string())
    }
  }
  names
}

/// Extract query parameter names declared with the explode modifier:
/// `{?tags*}` marks `tags` as repeatable.
pub fn extract_exploded_query_params(
  uri_template : String,
) -> Array[String] {
  let names : Array[String] = []
  let block = query_block(uri_template)
  guard block is Some(inner) else { return names }
  for raw in inner.split(",") {
    let name = raw.to_string().trim()
    if name.has_suffix("*") {
      names.push(name[:name.length() - 1].to_string())
    }
  }
  names
}

fn query_block(uri_template : String) -> String? {
  let chars = uri_template.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '{' && i + 1 < chars.length() && chars[i + 1] == '?' {
      let mut j = i + 2
      while j < chars.length() && chars[j] != '}' {
        j += 1
      }
      if j < chars.length() {
        let buf = StringBuilder::StringBuilder()
        let mut k = i + 2
        while k < j {
          buf.write_char(chars[k])
          k += 1
        }
        return Some(buf.to_string())
      }
      return None
    }
    i += 1
  }
  None
}

fn chars_to_string(u : Array[Char], start : Int, end_ : Int) -> String {
  let buf = StringBuilder::StringBuilder()
  for i in start..<end_ {
    buf.write_char(u[i])
  }
  buf.to_string()
}

/// Match consecutive `%XX` triplets at `pos` against the UTF-8 bytes of
/// `want`; hex digits may be either case. Returns the position after the
/// matched triplets.
fn match_percent_encoded(
  u : Array[Char],
  pos : Int,
  want : Bytes,
) -> Int? {
  let count = want.length()
  guard pos + 3 * count <= u.length() else { return None }
  for i in 0..<count {
    let at = pos + 3 * i
    guard u[at] == '%' &&
      is_hex_digit(u[at + 1]) &&
      is_hex_digit(u[at + 2]) else { return None }
    let hi = hex_digit_value(u[at + 1]).unwrap()
    let lo = hex_digit_value(u[at + 2]).unwrap()
    if hi * 16 + lo != want[i].to_int() {
      return None
    }
  }
  Some(pos + 3 * count)
}

fn match_literal(
  segs : Array[TemplateSegment],
  seg_idx : Int,
  lit : Array[Char],
  k : Int,
  u : Array[Char],
  pos : Int,
  params : Map[String, String],
) -> Map[String, String]? {
  if k == lit.length() {
    return match_segments(segs, seg_idx + 1, u, pos, params)
  }
  let want = @utf8.encode(lit[k].to_string())
  // Option 1: the character as written.
  if pos < u.length() && u[pos] == lit[k] {
    let matched = match_literal(segs, seg_idx, lit, k + 1, u, pos + 1, params)
    if matched is Some(_) {
      return matched
    }
  }
  // Option 2: the character percent-encoded, hex digits in either case.
  match match_percent_encoded(u, pos, want) {
    Some(next) =>
      match_literal(segs, seg_idx, lit, k + 1, u, next, params)
    None => None
  }
}

fn match_segments(
  segs : Array[TemplateSegment],
  seg_idx : Int,
  u : Array[Char],
  pos : Int,
  params : Map[String, String],
) -> Map[String, String]? {
  if seg_idx == segs.length() {
    return if pos == u.length() {
      Some(params)
    } else {
      None
    }
  }
  match segs[seg_idx] {
    Literal(lit) => match_literal(segs, seg_idx, lit, 0, u, pos, params)
    PathVar(name~, wildcard~) => {
      let mut result : Map[String, String]? = None
      if wildcard {
        // `.+` captures across segments; longest candidate first.
        let mut end_ = u.length()
        while end_ >= pos + 1 && result is None {
          let next_params = params.copy()
          next_params[name] = chars_to_string(u, pos, end_)
          let matched = match_segments(segs, seg_idx + 1, u, end_, next_params)
          if matched is Some(_) {
            result = matched
          }
          end_ -= 1
        }
      } else {
        // `[^/]+` captures within one segment.
        let mut end_ = pos + 1
        while end_ <= u.length() && result is None {
          if u[end_ - 1] == '/' {
            break
          }
          let next_params = params.copy()
          next_params[name] = chars_to_string(u, pos, end_)
          let matched = match_segments(segs, seg_idx + 1, u, end_, next_params)
          if matched is Some(_) {
            result = matched
          }
          end_ += 1
        }
      }
      result
    }
  }
}

fn json_of_param(value : String) -> Json {
  Json::string(value)
}

/// Match a URI against a template and extract both path and query
/// parameters, percent-decoded.
///
/// `list_params` names non-exploded query parameters that hold lists; their
/// first value is comma-split per RFC 6570 section 3.2.8. Pass pre-parsed
/// `segments` when the caller already holds them.
pub fn match_uri_template(
  uri : String,
  uri_template : String,
  list_params? : Array[String] = [],
  segments? : Array[TemplateSegment],
) -> Map[String, Json]? {
  // A fragment is not part of the resource identity; drop it before
  // splitting off the query unless the template spells out a literal `#`.
  let uri = if uri_template.contains("#") {
    uri
  } else {
    match uri.find("#") {
      Some(index) => uri[:index].to_string()
      None => uri
    }
  }
  let mut path_part = uri
  let mut query_part = ""
  match uri.find("?") {
    Some(index) => {
      path_part = uri[:index].to_string()
      query_part = uri[index + 1:].to_string()
    }
    None => ()
  }
  let segs = match segments {
    Some(segs) => segs
    None => parse_template(uri_template)
  }
  let u = path_part.to_array()
  guard match_segments(segs, 0, u, 0, {}) is Some(raw_params) else {
    return None
  }
  // Percent-decode captured path values.
  let params : Map[String, Json] = {}
  for name, value in raw_params {
    params[name] = json_of_param(unquote(value))
  }
  if query_part.length() > 0 {
    // Repeated keys collect; blank values are preserved so callers can
    // distinguish "explicitly empty" from "missing".
    let parsed_query : Map[String, Array[String]] = {}
    let raw_query : Map[String, String] = {}
    for pair in query_part.split("&") {
      let pair_str = pair.to_string()
      if pair_str.is_empty() {
        continue
      }
      let mut name = ""
      let mut value = ""
      match pair_str.find("=") {
        Some(index) => {
          name = unquote_plus(pair_str[:index].to_string())
          value = pair_str[index + 1:].to_string()
        }
        None => {
          name = unquote_plus(pair_str)
          value = ""
        }
      }
      let decoded = unquote_plus(value)
      match parsed_query.get(name) {
        Some(existing) => existing.push(decoded)
        None => parsed_query[name] = [decoded]
      }
      if raw_query.get(name) is None {
        raw_query[name] = value
      }
    }
    let exploded = extract_exploded_query_params(uri_template)
    let query_names = extract_query_params(uri_template)
    for name in query_names {
      guard parsed_query.get(name) is Some(values) else { continue }
      // Hyphens normalise to underscores; path params win.
      let key = name.replace(old="-", new="_")
      if params.get(key) is Some(_) {
        continue
      }
      let is_exploded = {
        let mut found = false
        for candidate in exploded {
          if candidate == name {
            found = true
            break
          }
        }
        found
      }
      let is_list = {
        let mut found = false
        for candidate in list_params {
          if candidate == name {
            found = true
            break
          }
        }
        found
      }
      if is_exploded {
        params[key] = Json::array(values.map(Json::string))
      } else if is_list {
        let raw = raw_query.get(name).unwrap_or("")
        if raw.is_empty() {
          params[key] = Json::array([])
        } else {
          let items : Array[Json] = []
          for item in raw.split(",") {
            items.push(Json::string(unquote_plus(item.to_string())))
          }
          params[key] = Json::array(items)
        }
      } else {
        params[key] = Json::string(values[0])
      }
    }
  }
  Some(params)
}

fn json_param_to_string(value : Json) -> String {
  match value {
    String(text) => text
    _ => value.stringify()
  }
}

/// Expand a URI template with parameters — the inverse of
/// `match_uri_template`. Params use underscored keys but templates may use
/// hyphens, so both spellings are tried.
pub fn expand_uri_template(
  uri_template : String,
  params : Map[String, Json],
) -> String {
  let chars = uri_template.to_array()
  let buf = StringBuilder::StringBuilder()
  let lit = StringBuilder::StringBuilder()

  fn flush_literal(buf : StringBuilder, lit : StringBuilder) -> Unit {
    buf.write_string(encode_literal(lit.to_string()))
    lit.reset()
  }

  fn expand_query(inner : String) -> Unit {
    let parts : Array[String] = []
    for raw in inner.split(",") {
      let mut name = raw.to_string().trim().to_string()
      let exploded = name.has_suffix("*")
      if exploded {
        name = name[:name.length() - 1].to_string()
      }
      let underscored = name.replace(old="-", new="_")
      let value = match params.get(name) {
        Some(value) => Some(value)
        None => params.get(underscored)
      }
      guard value is Some(value) else { continue }
      let encoded_name = pct_encode(name)
      match value {
        Array(values) =>
          if exploded {
            for v in values {
              parts.push(
                "\{encoded_name}=\{pct_encode(json_param_to_string(v))}",
              )
            }
          } else if values.length() > 0 {
            let joined = values
              .map(fn(v) { pct_encode(json_param_to_string(v)) })
              .join(",")
            parts.push("\{encoded_name}=\{joined}")
          }
        value => {
          let text = json_param_to_string(value)
          parts.push("\{encoded_name}=\{pct_encode(text)}")
        }
      }
    }
    if parts.length() > 0 {
      let query = parts.join("&")
      buf.write_string("?\{query}")
    }
  }

  let mut i = 0
  while i < chars.length() {
    if chars[i] == '{' {
      // Find the closing brace.
      let mut j = i + 1
      while j < chars.length() && chars[j] != '}' {
        j += 1
      }
      if j < chars.length() {
        let inner_buf = StringBuilder::StringBuilder()
        let mut k = i + 1
        while k < j {
          inner_buf.write_char(chars[k])
          k += 1
        }
        let inner = inner_buf.to_string()
        if inner.has_prefix("?") {
          flush_literal(buf, lit)
          expand_query(inner[1:].to_string())
          i = j + 1
          continue
        }
        flush_literal(buf, lit)
        let mut name = inner
        let mut wildcard = false
        if name.has_suffix("*") {
          wildcard = true
          name = name[:name.length() - 1].to_string()
        }
        let underscored = name.replace(old="-", new="_")
        let hyphenated = name.replace(old="_", new="-")
        let forms : Array[String] = [name]
        if underscored != name {
          forms.push(underscored)
        }
        if hyphenated != name {
          forms.push(hyphenated)
        }
        let mut substituted = false
        for form in forms {
          if substituted {
            break
          }
          match params.get(form) {
            Some(value) => {
              let text = json_param_to_string(value)
              buf.write_string(
                if wildcard {
                  pct_encode(text, safe="/")
                } else {
                  pct_encode(text)
                },
              )
              substituted = true
            }
            None => ()
          }
        }
        if not(substituted) {
          buf.write_char('{')
          buf.write_string(name)
          if wildcard {
            buf.write_char('*')
          }
          buf.write_char('}')
        }
        i = j + 1
        continue
      }
    }
    lit.write_char(chars[i])
    i += 1
  }
  flush_literal(buf, lit)
  buf.to_string()
}

/// Build the URI a forwarding layer (mount or proxy) sends to the server
/// behind it: the path is expanded from the template, but the query string
/// is carried over from the incoming URI byte for byte.
pub fn forward_uri(
  uri_template : String,
  params : Map[String, Json],
  uri : String,
) -> String {
  let path_template = strip_query_blocks(uri_template)
  let forwarded = expand_uri_template(path_template, params)
  match uri.find("?") {
    Some(index) => {
      let query = uri[index + 1:].to_string()
      let result = "\{forwarded}?\{query}"
      result
    }
    None => forwarded
  }
}
