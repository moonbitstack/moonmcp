// The official TypeScript SDK as a client of a moonmcp server.
//
//   node client.mjs stdio <command> [args...]
//   node client.mjs http <url>
//
// Every check prints one line; the program exits non-zero if any of them fails.

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

const [mode, ...rest] = process.argv.slice(2);
let transport;
if (mode === "stdio") {
  transport = new StdioClientTransport({ command: rest[0], args: rest.slice(1) });
} else if (mode === "http") {
  transport = new StreamableHTTPClientTransport(new URL(rest[0]));
} else {
  console.error("usage: node client.mjs stdio <command> [args...] | http <url>");
  process.exit(2);
}

const failures = [];
function check(label, condition, seen) {
  if (condition) {
    console.log(`ok   ${label}`);
  } else {
    failures.push(label);
    console.log(`FAIL ${label}: ${JSON.stringify(seen)}`);
  }
}

const client = new Client({ name: "typescript-client", version: "1.0.0" });
await client.connect(transport);

const tools = await client.listTools();
const names = tools.tools.map((tool) => tool.name);
check("tools/list has add", names.includes("add"), names);
check("tools/list has greet", names.includes("greet"), names);
check("tools/list has count", names.includes("count"), names);

const added = await client.callTool({ name: "add", arguments: { a: 2, b: 3 } });
const addedText = added.content?.[0]?.text;
check("tools/call add is 5", added.isError !== true && /5/.test(String(addedText)), added);

const greeted = await client.callTool({
  name: "greet",
  arguments: { name: "leo", language: "zh" },
});
check(
  "tools/call greet names the caller",
  String(greeted.content?.[0]?.text ?? "").includes("leo"),
  greeted,
);

const resources = await client.listResources();
const uris = resources.resources.map((resource) => resource.uri);
check("resources/list has config://app", uris.includes("config://app"), uris);

const templates = await client.listResourceTemplates();
const patterns = templates.resourceTemplates.map((template) => template.uriTemplate);
check(
  "resources/templates/list has users://{id}/profile",
  patterns.includes("users://{id}/profile"),
  patterns,
);

const read = await client.readResource({ uri: "config://app" });
check(
  "resources/read config://app answers",
  String(read.contents?.[0]?.text ?? "").includes("dark"),
  read,
);

const templated = await client.readResource({ uri: "users://7/profile" });
check(
  "resources/read a template URI answers",
  String(templated.contents?.[0]?.text ?? "").includes("7"),
  templated,
);

const prompts = await client.listPrompts();
const promptNames = prompts.prompts.map((prompt) => prompt.name);
check("prompts/list has review", promptNames.includes("review"), promptNames);

const rendered = await client.getPrompt({
  name: "review",
  arguments: { code: "fn f() { 1 }" },
});
check(
  "prompts/get review renders",
  String(rendered.messages?.[0]?.content?.text ?? "").includes("fn f() { 1 }"),
  rendered,
);

// A tool that is not there is a protocol error, not a result.
let refused = null;
try {
  await client.callTool({ name: "nope", arguments: {} });
} catch (error) {
  refused = error;
}
check("an unknown tool is refused", refused !== null, refused?.message);

// A call the schema rejects is a result marked isError, which a model reads.
let failed = null;
try {
  failed = await client.callTool({ name: "add", arguments: { a: "two", b: 3 } });
} catch (error) {
  failed = { thrown: String(error) };
}
check("a bad argument answers with isError", failed?.isError === true, failed);

await client.close();
if (failures.length) {
  console.error(`${failures.length} check(s) failed`);
  process.exit(1);
}
console.log(`${mode}: all checks passed`);
