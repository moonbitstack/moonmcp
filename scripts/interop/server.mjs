// A server written with the official TypeScript SDK, for moonmcp's client to
// talk to. The same capabilities over stdio and over Streamable HTTP, so both
// transports can be checked against the same answers.
//
//   node server.mjs stdio
//   node server.mjs http <port>

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import {
  CallToolRequestSchema,
  GetPromptRequestSchema,
  ListPromptsRequestSchema,
  ListResourcesRequestSchema,
  ListToolsRequestSchema,
  ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { createServer } from "node:http";

const text = (value) => ({ content: [{ type: "text", text: String(value) }] });

function build() {
  const server = new Server(
    { name: "typescript-sdk", version: "1.0.0" },
    { capabilities: { tools: {}, resources: {}, prompts: {} } },
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
      {
        name: "echo",
        description: "Say what it was given",
        inputSchema: {
          type: "object",
          properties: { message: { type: "string" } },
          required: ["message"],
        },
      },
      {
        name: "sum",
        description: "Add two numbers",
        inputSchema: {
          type: "object",
          properties: { a: { type: "number" }, b: { type: "number" } },
          required: ["a", "b"],
        },
      },
    ],
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args = {} } = request.params;
    if (name === "echo") {
      return text(args.message ?? "");
    }
    if (name === "sum") {
      return text(Number(args.a ?? 0) + Number(args.b ?? 0));
    }
    throw new Error(`Unknown tool: ${name}`);
  });

  server.setRequestHandler(ListResourcesRequestSchema, async () => ({
    resources: [
      {
        uri: "mem://greeting",
        name: "greeting",
        mimeType: "text/plain",
      },
    ],
  }));

  server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
    if (request.params.uri !== "mem://greeting") {
      throw new Error(`Unknown resource: ${request.params.uri}`);
    }
    return {
      contents: [
        { uri: "mem://greeting", mimeType: "text/plain", text: "hello" },
      ],
    };
  });

  server.setRequestHandler(ListPromptsRequestSchema, async () => ({
    prompts: [
      {
        name: "shout",
        description: "Repeat a text in capitals",
        arguments: [{ name: "text", required: true }],
      },
    ],
  }));

  server.setRequestHandler(GetPromptRequestSchema, async (request) => {
    if (request.params.name !== "shout") {
      throw new Error(`Unknown prompt: ${request.params.name}`);
    }
    const said = request.params.arguments?.text ?? "";
    return {
      description: "Repeat a text in capitals",
      messages: [
        { role: "user", content: { type: "text", text: said.toUpperCase() } },
      ],
    };
  });

  return server;
}

async function stdio() {
  await build().connect(new StdioServerTransport());
}

// One server and one transport per request: the stateless shape, which a client
// that sends no session id expects.
async function http(port) {
  const listener = createServer(async (req, res) => {
    if (req.method !== "POST") {
      res.writeHead(405).end();
      return;
    }
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    const server = build();
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
    });
    res.on("close", () => {
      transport.close();
      server.close();
    });
    await server.connect(transport);
    await transport.handleRequest(req, res, body);
  });
  listener.listen(port, "127.0.0.1", () => {
    process.stderr.write(`typescript-sdk server on http://127.0.0.1:${port}/mcp\n`);
  });
}

const [mode, argument] = process.argv.slice(2);
if (mode === "stdio") {
  await stdio();
} else if (mode === "http") {
  await http(Number(argument ?? 9410));
} else {
  console.error("usage: node server.mjs stdio | http <port>");
  process.exit(2);
}
