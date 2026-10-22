/// Base component machinery shared by tools, prompts, resources and
/// resource templates, mirroring fastmcp/utilities/components.py.

/// FastMCP-namespaced metadata carried in a component's `_meta`.
pub(all) struct FastMCPMeta {
  tags : Array[String]
  version : String?
  versions : Array[String]
} derive(Debug, Eq)

pub fn FastMCPMeta::empty() -> FastMCPMeta {
  { tags: [], version: None, versions: [] }
}

/// Extract moonmcp metadata from a component's meta object.
///
/// Handles both the current `fastmcp` namespace and the legacy `_fastmcp`
/// namespace for compatibility with older servers.
pub fn get_fastmcp_metadata(meta : Map[String, Json]?) -> FastMCPMeta {
  guard meta is Some(meta) else { return FastMCPMeta::empty() }
  for key in ["fastmcp", "_fastmcp"] {
    if meta.get(key) is Some(Object(metadata)) {
      let tags : Array[String] = match metadata.get("tags") {
        Some(Array(values)) =>
          values.filter_map(fn(v) { v.as_string() })
        _ => []
      }
      let version : String? = match metadata.get("version") {
        Some(String(v)) => Some(v)
        _ => None
      }
      let versions : Array[String] = match metadata.get("versions") {
        Some(Array(values)) =>
          values.filter_map(fn(v) { v.as_string() })
        _ => []
      }
      return { tags, version, versions }
    }
  }
  FastMCPMeta::empty()
}

/// Strip moonmcp's internal bookkeeping out of component meta.
///
/// Returns `None` when nothing public remains, so components without user
/// metadata keep an absent `_meta` rather than an empty object.
pub fn public_result_meta(meta : Map[String, Json]?) -> Map[String, Json]? {
  guard meta is Some(meta) else { return None }
  let public = meta.copy()
  if public.get("fastmcp") is Some(Object(fastmcp_meta)) {
    let public_fastmcp : Map[String, Json] = {}
    for key, value in fastmcp_meta {
      if not(key.has_prefix("_")) {
        public_fastmcp[key] = value
      }
    }
    if public_fastmcp.is_empty() {
      public.remove("fastmcp")
    } else {
      public["fastmcp"] = public_fastmcp.to_json()
    }
  }
  if public.is_empty() {
    None
  } else {
    Some(public)
  }
}

/// Coerce a JSON scalar to a version string.
///
/// Raises `Validation` for non-scalar values or versions containing `@`
/// (used as the key delimiter).
pub fn coerce_version(
  value : Json?,
) -> String? raise @exceptions.FastMCPError {
  match value {
    None | Some(Null) => None
    Some(String(v)) => check_version(v)
    Some(Number(n, ..)) => {
      let repr = n.to_string()
      let version = if repr.has_suffix(".0") {
        repr[:repr.length() - 2].to_string()
      } else {
        repr
      }
      check_version(version)
    }
    Some(True) | Some(False) =>
      raise @exceptions.Validation(
        "Version must be a string or number, got bool",
      )
    Some(_) =>
      raise @exceptions.Validation("Version must be a string or number")
  }
}

fn check_version(version : String) -> String? raise @exceptions.FastMCPError {
  if version.contains("@") {
    raise @exceptions.Validation(
      "Version string cannot contain '@' (used as key delimiter): \{version}",
    )
  }
  Some(version)
}
