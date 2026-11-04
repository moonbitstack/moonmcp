/// Task configuration primitives for moonmcp components,
/// mirroring fastmcp/utilities/tasks.py.

///|
/// Reverse-DNS identifier of the SEP-2663 tasks extension.
pub let tasks_extension_id : String = "io.modelcontextprotocol/tasks"

///|
/// How often a task is polled when the caller says nothing: five seconds.
pub let default_poll_interval_ms : Int32 = 5000

///|
/// How long a task's result is kept when the caller says nothing: one minute.
pub let default_ttl_ms : Int32 = 60000

///|
/// How a component handles task-augmented execution requests.
#derive(Debug, Eq)
pub(all) enum TaskMode {
  Forbidden
  Optional
  Required
}

///|
pub fn TaskMode::to_wire(self : TaskMode) -> String {
  match self {
    Forbidden => "forbidden"
    Optional => "optional"
    Required => "required"
  }
}

///|
/// The task mode a wire string names, or `None` for one this library does
/// not offer.
pub fn task_mode_from_wire(value : String) -> TaskMode? {
  match value {
    "forbidden" => Some(Forbidden)
    "optional" => Some(Optional)
    "required" => Some(Required)
    _ => None
  }
}

///|
/// Metadata for task-augmented execution requests.
#derive(Debug, Eq)
pub(all) struct TaskMeta {
  /// Client-requested TTL in milliseconds; `None` uses the server default.
  ttl : Int32?
  /// Routing key; derived from the component name when `None`.
  fn_key : String?
}

///|
/// Configuration for MCP background task execution.
#derive(Debug, Eq)
pub(all) struct TaskConfig {
  mode : TaskMode
  poll_interval_ms : Int32
}

///|
pub fn TaskConfig::new(
  mode~ : TaskMode = Forbidden,
  poll_interval_ms~ : Int32 = default_poll_interval_ms,
) -> TaskConfig {
  { mode, poll_interval_ms, }
}

///|
/// Convert a boolean task flag to a `TaskConfig`.
pub fn TaskConfig::from_bool(value : Bool) -> TaskConfig {
  {
    mode: if value {
      Optional
    } else {
      Forbidden
    },
    poll_interval_ms: default_poll_interval_ms,
  }
}

///|
/// Whether this component supports task execution.
pub fn TaskConfig::supports_tasks(self : TaskConfig) -> Bool {
  self.mode != Forbidden
}

///|
pub extend TaskConfig with Debug::{to_repr}

///|
pub extend TaskConfig with Eq::{not_equal, equal}

///|
pub extend TaskMeta with Debug::{to_repr}

///|
pub extend TaskMeta with Eq::{not_equal, equal}

///|
pub extend TaskMode with Debug::{to_repr}

///|
pub extend TaskMode with Eq::{not_equal, equal}
