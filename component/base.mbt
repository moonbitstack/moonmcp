/// Common state shared by all moonmcp components.
pub(all) struct ComponentBase {
  /// Type prefix used in lookup keys, e.g. `"tool"` or `"resource"`.
  key_prefix : String
  name : String
  version : String?
  title : String?
  description : String?
  icons : Array[@types.Icon]?
  tags : @set.Set[String]
  meta : Map[String, Json]?
  task_config : @tasks.TaskConfig
}

pub fn ComponentBase::new(
  key_prefix : String,
  name : String,
  version? : String,
  title? : String,
  description? : String,
  icons? : Array[@types.Icon],
  tags? : @set.Set[String] = @set.Set::from_array([]),
  meta? : Map[String, Json],
  task_config? : @tasks.TaskConfig = @tasks.TaskConfig::new(mode=@tasks.Forbidden),
) -> ComponentBase {
  {
    key_prefix,
    name,
    version,
    title,
    description,
    icons,
    tags,
    meta,
    task_config,
  }
}

/// Construct the lookup key for a component type, e.g. `"tool:name"`.
pub fn ComponentBase::make_key(prefix : String, identifier : String) -> String {
  if prefix.is_empty() {
    identifier
  } else {
    "\{prefix}:\{identifier}"
  }
}

/// The globally unique lookup key for a component.
///
/// Format: `"{key_prefix}:{identifier}@{version}"`; the `@` delimiter is
/// always present so keys parse unambiguously even when the identifier
/// itself contains `@`.
pub fn ComponentBase::key(self : ComponentBase, identifier : String) -> String {
  let base_key = ComponentBase::make_key(self.key_prefix, identifier)
  "\{base_key}@\{self.version.unwrap_or("")}"
}

/// The public meta information about the component.
///
/// Always includes a `fastmcp` key containing the sorted `tags` list and the
/// `version` (when set); internal keys (prefixed with `_`) are stripped from
/// the fastmcp namespace.
pub fn ComponentBase::get_meta(self : ComponentBase) -> Map[String, Json] {
  let meta = self.meta.map_or({}, fn(m) { m.copy() })
  // The core `Compare` for `String` orders by length first; tags follow
  // fastmcp's lexicographic `sorted()` instead.
  let sorted_tags = self.tags.to_array()
  sorted_tags.sort_by(String::lexical_compare)
  let fastmcp_meta : Map[String, Json] = {
    "tags": sorted_tags.to_json(),
  }
  if self.version is Some(version) {
    fastmcp_meta["version"] = version.to_json()
  }
  if meta.get("fastmcp") is Some(Object(upstream)) {
    for key, value in upstream {
      if not(key.has_prefix("_")) {
        fastmcp_meta[key] = value
      }
    }
  }
  meta["fastmcp"] = fastmcp_meta.to_json()
  meta
}

/// A moonmcp component: tool, prompt, resource or resource template.
pub(open) trait Component {
  base(Self) -> ComponentBase

  /// The raw identifier: the name for tools and prompts, the URI for
  /// resources and resource templates.
  identifier(Self) -> String = _
  key(Self) -> String = _
  get_meta(Self) -> Map[String, Json] = _
}

impl Component with identifier(self) {
  self.base().name
}

impl Component with key(self) {
  self.base().key(self.identifier())
}

impl Component with get_meta(self) {
  self.base().get_meta()
}
