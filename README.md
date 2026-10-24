# moonmcp

Model Context Protocol servers and clients for MoonBit, after
[FastMCP](https://github.com/jlowin/fastmcp). Python's machinery (pydantic
introspection, decorators, camelCase shims) becomes MoonBit's own: records with
`ToJson` and `FromJson`, closures in place of subclasses, one error enum.

> **Status:** the foundation layer is in: the wire model and the components.
> The server core, the transports and the client come next.

## Packages

| Package | What it holds |
|:--:|:--|
| `types` | The MCP wire model: protocol constants, the JSON-RPC envelope, content blocks, tools, prompts, resources, capabilities, request parameters, every result |
| `exceptions` | `FastMCPError`, one enum whose variants carry their payloads, and the mapping to MCP error codes |
| `component` | `ComponentBase`, the open `Component` trait, metadata and version handling |
| `tools` | `Tool` with `run` and `prepare_run`, `ToolResult`, structured-output wrapping |
| `prompts` | `Prompt`, `Message`, `PromptResult` |
| `resources` | `Resource`, `ResourceTemplate` with an RFC 6570 URI template engine, path screening |
| `tasks` | Task mode, configuration and metadata |
| `settings` | `Settings`, read from `FASTMCP_*` variables |
| `mcp_config` | The `mcp.json` client configuration: server kinds, transforms, transport inference |
| `utilities` | Image, audio and file helpers that become content blocks |

## How Python maps over

| FastMCP | moonmcp |
|:--|:--|
| Exception class hierarchy | `pub(all) suberror FastMCPError`, a variant per class |
| Pydantic models | `pub(all) struct`s with `ToJson` and `FromJson` written out, so wire names such as `mimeType` stay exact |
| `FunctionTool`, `FunctionPrompt`, `FunctionResource` subclasses | a struct with a closure field (`run_fn`, `render_fn`, `read_fn`); components implement the open `Component` trait |
| `TransformingMCPServer` mixin | a `transform` field on `MCPServerEntry` |

## Install

```bash
moon add moonbitstack/moonmcp
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
