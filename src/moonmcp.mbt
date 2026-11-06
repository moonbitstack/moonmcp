// The names a server is written with, under one package: `@moonmcp.Server`,
// `@moonmcp.Tool` and the rest. Each lives in its own package, which a program
// may import instead.

///|
pub using @server {
  type Server,
  type Scope,
  type Channel,
  type Cancellations,
  decode,
  decode_option,
}

///|
pub using @tools {type Tool, type ToolResult}

///|
pub using @resources {type Resource, type ResourceTemplate}

///|
pub using @prompts {type Prompt, type Message}

///|
pub using @context {type Context, type Facts}

///|
pub using @client {type Client, type Memory, type Lines, type Refused}

///|
pub using @auth {type Bearer, type Principal, type Challenge}

///|
pub using @types {type CacheScope, type ElicitResult, text_block}

///|
pub using @exceptions {type FastMCPError}

///|
pub using @providers {trait Provider, type Listing}

///|
pub using @transforms {
  trait Transform,
  type Namespace,
  type Hidden,
  type Tagged,
}

///|
pub using @layers {
  type Layer,
  type Next,
  type Call,
  type Operation,
  type Caching,
  type RateLimiting,
  type Telemetry,
  type Span,
}
