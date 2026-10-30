// The names a server is written with, under one package: `@moonmcp.Server`,
// `@moonmcp.Tool` and the rest. Each lives in its own package, which a program
// may import instead.

///|
pub using @server {type Server, type Scope, decode, decode_option}

///|
pub using @tools {type Tool, type ToolResult}

///|
pub using @resources {type Resource, type ResourceTemplate}

///|
pub using @prompts {type Prompt, type Message}

///|
pub using @exceptions {type FastMCPError}
