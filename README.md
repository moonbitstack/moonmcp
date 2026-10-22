# moonmcp

A MoonBit transcription of [FastMCP](https://github.com/jlowin/fastmcp): a framework
for building Model Context Protocol (MCP) servers and clients.

This project transcribes the Python `fastmcp` library (reference source under
`.fastmcp-ref/`) into idiomatic MoonBit. It is not a line-by-line port —
Python-specific machinery (pydantic introspection, decorators, rich logging,
camelCase compatibility shims) is mapped to MoonBit-idiomatic equivalents — but
every capability of the original is preserved.

## Requirements

- MoonBit toolchain (`moon`) — built and verified with `0.1.20261016`
- Moon check with `moon check`, tests with `moon test`

## Status

| Package | Contents | Status |
|---|---|---|
| `types/` | Full MCP wire model: protocol constants, JSON-RPC envelope, content blocks, tools, prompts, resources, capabilities, request params (incl. SEP-2322 input mechanism), all result types | Done |
| `exceptions/` | Unified `FastMCPError` suberror enum with payload-carrying variants and `to_mcp_error` mapping | Done |
| `tasks/` | Task mode, task configuration, task metadata, `TASKS_EXTENSION_ID` | Done |
| `component/` | `ComponentBase`, open `Component` trait, `FastMCPMeta`, version coercion | Done |
| `settings/` | `Settings` struct with `from_env()` reading `FASTMCP_*` variables | Done |
| `mcp_config/` | Server kinds, transforms, `MCPConfig` with root-level auto-wrap, transport inference | Done |
| `utilities/` | Image / Audio / File helpers with `to_content_block`, percent-encoding | Done |
| `tools/` | `ToolResult`, `Tool` with `run` / `prepare_run`, structured-output wrapping | Done |
| `prompts/` | `Message`, `PromptResult`, `Prompt` | Done |
| `resources/` | `ResourceContent`, `ResourceResult`, `Resource`, `ResourceTemplate`, hand-written RFC 6570 URI template engine, path screening | Done |
| `server/` | Server core, middleware stack, stdio transport loop | In progress |
| `client/` | Client SDK and transports (stdio / http / sse / memory) | Pending |

All 90 current tests pass across every completed package.

Deferred (requires native I/O or is deferred until the server/client layers land):
MCPConfig file I/O, path-backed media helpers, and file / HTTP / directory
resource readers.

## Design decisions

- **Exception hierarchy** — Python's class hierarchy becomes a single
  `pub(all) suberror FastMCPError` enum; variants carry their payloads directly.
- **Pydantic models** — become `pub(all) struct`s with hand-written
  `ToJson` / `FromJson` implementations (the toolchain has no `@json.rename`),
  so wire names such as `mimeType` are preserved exactly. Validators become
  constructor functions raising `FastMCPError`.
- **Subclass dispatch** — Python's `FunctionTool` / `FunctionPrompt` /
  `FunctionResource` subclassing becomes a struct with a closure field
  (`run_fn` / `render_fn` / `read_fn`); components implement the open
  `Component` trait. Resources are keyed by URI, templates by `uri_template`.
- **TransformingMCPServer** — the Python mixin folds into `MCPServerEntry`
  as a `transform` field.
- **Spelling** — all documentation and identifiers follow Oxford / EN-ZA
  spelling (`authorisation`, `serialise`, `initialise`).

## Licence

Apache-2.0, matching the upstream FastMCP project.
