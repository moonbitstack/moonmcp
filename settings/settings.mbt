/// moonmcp settings, mirroring fastmcp/settings.py.

fn to_upper_ascii(value : String) -> String {
  let buf = StringBuilder::StringBuilder()
  for ch in value {
    buf.write_char(ch.to_ascii_uppercase())
  }
  buf.to_string()
}

fn to_lower_ascii(value : String) -> String {
  let buf = StringBuilder::StringBuilder()
  for ch in value {
    buf.write_char(ch.to_ascii_lowercase())
  }
  buf.to_string()
}

pub let ten_mb_in_bytes : Int = 1024 * 1024 * 10

pub(all) enum LogLevel {
  Debug
  Info
  Warning
  Error
  Critical
} derive(Debug, Eq)

pub fn LogLevel::to_wire(self : LogLevel) -> String {
  match self {
    Debug => "DEBUG"
    Info => "INFO"
    Warning => "WARNING"
    Error => "ERROR"
    Critical => "CRITICAL"
  }
}

pub fn log_level_from_wire(value : String) -> LogLevel? {
  match to_upper_ascii(value) {
    "DEBUG" => Some(Debug)
    "INFO" => Some(Info)
    "WARNING" => Some(Warning)
    "ERROR" => Some(Error)
    "CRITICAL" => Some(Critical)
    _ => None
  }
}

/// How moonmcp's native telemetry behaves.
pub(all) enum TelemetryMode {
  Native
  PropagationOnly
  Off
} derive(Debug, Eq)

pub fn TelemetryMode::to_wire(self : TelemetryMode) -> String {
  match self {
    Native => "native"
    PropagationOnly => "propagation_only"
    Off => "off"
  }
}

pub fn telemetry_mode_from_wire(value : String) -> TelemetryMode? {
  match value {
    "native" => Some(Native)
    "propagation_only" => Some(PropagationOnly)
    "off" => Some(Off)
    _ => None
  }
}

pub(all) enum TransportKind {
  Stdio
  Http
  Sse
  StreamableHttp
} derive(Debug, Eq)

pub fn TransportKind::to_wire(self : TransportKind) -> String {
  match self {
    Stdio => "stdio"
    Http => "http"
    Sse => "sse"
    StreamableHttp => "streamable-http"
  }
}

pub fn transport_kind_from_wire(value : String) -> TransportKind? {
  match value {
    "stdio" => Some(Stdio)
    "http" => Some(Http)
    "sse" => Some(Sse)
    "streamable-http" => Some(StreamableHttp)
    _ => None
  }
}

pub(all) enum CheckForUpdates {
  Stable
  Prerelease
  Off
} derive(Debug, Eq)

pub(all) enum SessionIdleTimeout {
  Auto
  Never
  Seconds(Double)
} derive(Debug, Eq)

/// The `http_session_idle_timeout` wire forms: `"auto"`, `"none"`, or a number.
pub fn SessionIdleTimeout::to_wire(self : SessionIdleTimeout) -> String {
  match self {
    Auto => "auto"
    Never => "none"
    Seconds(s) => s.to_string()
  }
}

pub fn session_idle_timeout_from_wire(
  value : String,
) -> SessionIdleTimeout? {
  match to_lower_ascii(value) {
    "auto" => Some(Auto)
    "none" => Some(Never)
    _ => {
      let parsed = try Ok(@string.parse_double(value)) catch { _ => Err(()) }
      if parsed is Ok(seconds) {
        Some(Seconds(seconds))
      } else {
        None
      }
    }
  }
}

/// Everything the framework reads from `FASTMCP_*` environment variables.
pub(all) struct Settings {
  home : String
  oauth_encryption_key : String?
  test_mode : Bool
  log_enabled : Bool
  log_level : LogLevel
  enable_rich_logging : Bool
  enable_rich_tracebacks : Bool
  deprecation_warnings : Bool
  telemetry_mode : TelemetryMode
  client_init_timeout : Double?
  client_disconnect_timeout : Double
  transport : TransportKind
  host : String
  port : Int
  sse_path : String
  message_path : String
  streamable_http_path : String
  debug : Bool
  mask_error_details : Bool
  client_log_level : @types.LoggingLevel?
  strict_input_validation : Bool
  ssrf_trust_proxy : Bool
  server_dependencies : Array[String]
  json_response : Bool
  stateless_http : Bool
  http_host_origin_protection : Bool
  http_allowed_hosts : Array[String]?
  http_allowed_origins : Array[String]?
  http_session_idle_timeout : SessionIdleTimeout
  mounted_components_raise_on_load_error : Bool
  show_server_banner : Bool
  check_for_updates : CheckForUpdates
} derive(Debug, Eq)

pub fn Settings::new() -> Settings {
  {
    home: ".moonmcp",
    oauth_encryption_key: None,
    test_mode: false,
    log_enabled: true,
    log_level: Info,
    enable_rich_logging: true,
    enable_rich_tracebacks: true,
    deprecation_warnings: true,
    telemetry_mode: Native,
    client_init_timeout: None,
    client_disconnect_timeout: 5,
    transport: Stdio,
    host: "127.0.0.1",
    port: 8000,
    sse_path: "/sse",
    message_path: "/messages/",
    streamable_http_path: "/mcp",
    debug: false,
    mask_error_details: false,
    client_log_level: None,
    strict_input_validation: false,
    ssrf_trust_proxy: false,
    server_dependencies: [],
    json_response: false,
    stateless_http: false,
    http_host_origin_protection: false,
    http_allowed_hosts: None,
    http_allowed_origins: None,
    http_session_idle_timeout: Auto,
    mounted_components_raise_on_load_error: false,
    show_server_banner: true,
    check_for_updates: Stable,
  }
}

fn env_str(key : String) -> String? {
  @env.get_env_var("FASTMCP_\{to_upper_ascii(key)}")
}

fn env_bool(key : String) -> Bool? {
  match env_str(key) {
    Some(value) =>
      match to_lower_ascii(value) {
        "true" | "1" | "yes" | "on" => Some(true)
        "false" | "0" | "no" | "off" => Some(false)
        _ => None
      }
    None => None
  }
}

fn env_int(key : String) -> Int? {
  match env_str(key) {
    Some(value) => {
      let parsed = try Ok(@string.parse_int(value)) catch { _ => Err(()) }
      if parsed is Ok(v) {
        Some(v)
      } else {
        None
      }
    }
    None => None
  }
}

fn env_double(key : String) -> Double? {
  match env_str(key) {
    Some(value) => {
      let parsed = try Ok(@string.parse_double(value)) catch { _ => Err(()) }
      if parsed is Ok(v) {
        Some(v)
      } else {
        None
      }
    }
    None => None
  }
}

fn env_str_array(key : String) -> Array[String]? {
  match env_str(key) {
    Some(value) => Some(value.split(",").map(fn(part) { part.to_string() }).collect())
    None => None
  }
}

/// Load settings, applying `FASTMCP_*` environment overrides.
pub fn Settings::from_env() -> Settings {
  let settings = Settings::new()
  {
    home: env_str("HOME").unwrap_or(settings.home),
    oauth_encryption_key: env_str("OAUTH_ENCRYPTION_KEY"),
    test_mode: env_bool("TEST_MODE").unwrap_or(false),
    log_enabled: env_bool("LOG_ENABLED").unwrap_or(true),
    log_level: match env_str("LOG_LEVEL").map(log_level_from_wire) {
      Some(Some(level)) => level
      _ => Info
    },
    enable_rich_logging: env_bool("ENABLE_RICH_LOGGING").unwrap_or(true),
    enable_rich_tracebacks: env_bool("ENABLE_RICH_TRACEBACKS").unwrap_or(true),
    deprecation_warnings: env_bool("DEPRECATION_WARNINGS").unwrap_or(true),
    telemetry_mode: match env_str("TELEMETRY_MODE").map(telemetry_mode_from_wire) {
      Some(Some(mode)) => mode
      _ => Native
    },
    client_init_timeout: match env_double("CLIENT_INIT_TIMEOUT") {
      Some(0) => None
      timeout => timeout
    },
    client_disconnect_timeout: env_double("CLIENT_DISCONNECT_TIMEOUT")
      .unwrap_or(5),
    transport: match env_str("TRANSPORT").map(transport_kind_from_wire) {
      Some(Some(kind)) => kind
      _ => Stdio
    },
    host: env_str("HOST").unwrap_or("127.0.0.1"),
    port: env_int("PORT").unwrap_or(8000),
    sse_path: env_str("SSE_PATH").unwrap_or("/sse"),
    message_path: env_str("MESSAGE_PATH").unwrap_or("/messages/"),
    streamable_http_path: env_str("STREAMABLE_HTTP_PATH").unwrap_or("/mcp"),
    debug: env_bool("DEBUG").unwrap_or(false),
    mask_error_details: env_bool("MASK_ERROR_DETAILS").unwrap_or(false),
    client_log_level: match env_str("CLIENT_LOG_LEVEL")
      .map(@types.logging_level_from_wire) {
      Some(Some(level)) => Some(level)
      _ => None
    },
    strict_input_validation: env_bool("STRICT_INPUT_VALIDATION").unwrap_or(false),
    ssrf_trust_proxy: env_bool("SSRF_TRUST_PROXY").unwrap_or(false),
    server_dependencies: env_str_array("SERVER_DEPENDENCIES").unwrap_or([]),
    json_response: env_bool("JSON_RESPONSE").unwrap_or(false),
    stateless_http: env_bool("STATELESS_HTTP").unwrap_or(false),
    http_host_origin_protection: env_bool("HTTP_HOST_ORIGIN_PROTECTION")
      .unwrap_or(false),
    http_allowed_hosts: env_str_array("HTTP_ALLOWED_HOSTS"),
    http_allowed_origins: env_str_array("HTTP_ALLOWED_ORIGINS"),
    http_session_idle_timeout: match env_str("HTTP_SESSION_IDLE_TIMEOUT")
      .map(session_idle_timeout_from_wire) {
      Some(Some(timeout)) => timeout
      _ => Auto
    },
    mounted_components_raise_on_load_error: env_bool(
      "MOUNTED_COMPONENTS_RAISE_ON_LOAD_ERROR",
    ).unwrap_or(false),
    show_server_banner: env_bool("SHOW_SERVER_BANNER").unwrap_or(true),
    check_for_updates: match env_str("CHECK_FOR_UPDATES") {
      Some("prerelease") => Prerelease
      Some("off") => Off
      _ => Stable
    },
  }
}
