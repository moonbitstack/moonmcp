// The interoperability pass: the official TypeScript SDK and Inspector as
// clients of a moonmcp server, and moonmcp's client against a server written
// with the TypeScript SDK, over stdio and over Streamable HTTP.
//
//   node run.mjs --stdio <binary> --http <binary> --client <binary>
//
// The three binaries are the native builds of src/examples/03-stdio,
// src/examples/02-http and src/examples/06-interop. Every check prints a line;
// the program exits non-zero when one of them fails.

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const failures = [];
const children = [];

function argument(name) {
  const at = process.argv.indexOf(`--${name}`);
  if (at < 0 || at + 1 >= process.argv.length) {
    console.error(`usage: node run.mjs --stdio <binary> --http <binary> --client <binary>`);
    process.exit(2);
  }
  return process.argv[at + 1];
}

// `moon build` writes the artifact as `name.exe` on every platform. A relative
// path is resolved here: a bare name would be looked for on PATH instead.
function binary(given) {
  for (const candidate of [given, given + ".exe"].map((one) => path.resolve(one))) {
    if (existsSync(candidate)) return candidate;
  }
  console.error(`no such binary: ${path.resolve(given)} (build it with moon build --target native)`);
  process.exit(2);
}

const stdioServer = binary(argument("stdio"));
const httpServer = binary(argument("http"));
const moonClient = binary(argument("client"));

// The environment a CI runner has, minus any proxy: a proxy variable would
// send a loopback request somewhere else entirely.
const env = { ...process.env };
for (const name of ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "ALL_PROXY", "all_proxy"]) {
  delete env[name];
}
env.NO_PROXY = "127.0.0.1,localhost";

function note(ok, label, detail) {
  if (ok) {
    console.log(`ok   ${label}`);
  } else {
    failures.push(label);
    console.log(`FAIL ${label}${detail ? ": " + detail : ""}`);
  }
}

function run(command, args, options = {}) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { env, ...options });
    let out = "";
    child.stdout.on("data", (chunk) => (out += chunk));
    child.stderr.on("data", (chunk) => (out += chunk));
    child.on("close", (code) => resolve({ code, out }));
  });
}

async function waitFor(url, ms = 30000) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    try {
      const response = await fetch(url);
      if (response.status < 500) return true;
    } catch {
      // not listening yet
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  return false;
}

function startServer(binary) {
  const child = spawn(binary, [], { env, stdio: ["ignore", "pipe", "pipe"] });
  child.stdout.resume();
  child.stderr.resume();
  children.push(child);
  return child;
}

// 1. The TypeScript SDK's client against our server, over stdio.
{
  const { code, out } = await run(process.execPath, [path.join(here, "client.mjs"), "stdio", stdioServer]);
  note(code === 0, "typescript sdk client, stdio", out.trim().split("\n").slice(-3).join(" | "));
}

// 2. The TypeScript SDK's client against our server, over Streamable HTTP.
{
  startServer(httpServer);
  const up = await waitFor("http://127.0.0.1:12000/docs");
  note(up, "our server answers on 12000");
  if (up) {
    const { code, out } = await run(process.execPath, [path.join(here, "client.mjs"), "http", "http://127.0.0.1:12000/mcp"]);
    note(code === 0, "typescript sdk client, http", out.trim().split("\n").slice(-3).join(" | "));
  }
}

// 3. The Inspector against our server, over stdio and over Streamable HTTP.
{
  // Through the package's own entry point, so no shell is needed on Windows.
  const inspector = path.join(
    here, "node_modules", "@modelcontextprotocol", "inspector", "clients", "launcher", "build", "index.js",
  );
  const listed = await run(process.execPath, [inspector, "--cli", stdioServer, "--method", "tools/list", "--transport", "stdio"]);
  note(listed.code === 0 && listed.out.includes('"add"'), "inspector, stdio", listed.out.trim().split("\n").slice(-2).join(" | "));

  const called = await run(process.execPath, [inspector, 
    "--cli", "--server-url", "http://127.0.0.1:12000/mcp", "--transport", "http",
    "--method", "tools/call", "--tool-name", "add", "--tool-arg", "a=2", "--tool-arg", "b=3",
  ]);
  note(called.code === 0 && called.out.includes("5"), "inspector, http", called.out.trim().split("\n").slice(-2).join(" | "));
}

// 4. Our client against the TypeScript SDK's server, over Streamable HTTP.
{
  const child = spawn(process.execPath, [path.join(here, "server.mjs"), "http", "9410"], { env, stdio: ["ignore", "pipe", "pipe"] });
  child.stdout.resume();
  child.stderr.resume();
  children.push(child);
  const up = await waitFor("http://127.0.0.1:9410/mcp");
  note(up, "the typescript sdk server answers on 9410");
  if (up) {
    const { code, out } = await run(moonClient, ["http", "http://127.0.0.1:9410/mcp"]);
    note(code === 0 && out.includes("http: all checks passed"), "our client, http", out.trim().split("\n").slice(-2).join(" | "));
  }
}

// 5. Our client against the TypeScript SDK's server, over stdio.
{
  const { code, out } = await run(moonClient, ["stdio", process.execPath, path.join(here, "server.mjs"), "stdio"]);
  note(code === 0 && out.includes("stdio: all checks passed"), "our client, stdio", out.trim().split("\n").slice(-2).join(" | "));
}

for (const child of children) child.kill();
if (failures.length) {
  console.error(`\n${failures.length} check(s) failed`);
  process.exit(1);
}
console.log("\ninteroperability: every check passed");
