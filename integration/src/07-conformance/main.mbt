// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
let image : String = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

///|
let audio : String = "UklGRiYAAABXQVZFZm10IBAAAAABAAEAQB8AAAB9AAACABAAZGF0YQIAAAA="

///|
fn text(value : String) -> @types.ContentBlock {
  @types.text_block(value)
}

///|
fn picture() -> @types.ContentBlock {
  Image(data=image, mime_type="image/png", annotations=None, meta=None)
}

///|
fn embedded(
  uri : String,
  mime_type : String,
  value : String,
) -> @types.ContentBlock {
  EmbeddedResource(
    resource=Text(uri~, mime_type=Some(mime_type), text=value),
    annotations=None,
    meta=None,
  )
}

///|
fn answer(content : Array[@types.ContentBlock]) -> @tools.ToolResult raise {
  @tools.ToolResult::new(content~)
}

///|
/// A tool whose one job is to return `content`.
fn fixed(
  mcp : @server.Server,
  name : String,
  description : String,
  content : Array[@types.ContentBlock],
) -> Unit {
  mcp.tool_context(name, (_, _) => answer(content), description~)
}

///|
/// Ask the client once, then answer with what `reply` makes of its response.
fn ask(
  context : @context.Context,
  op : String,
  params : Json,
  reply : (Json) -> String,
) -> @tools.ToolResult raise {
  match context.input_responses().get("reply") {
    Some(response) => answer([text(reply(response))])
    None =>
      @tools.ToolResult::input_required({
        input_requests: [
          {
            id: "reply",
            request: { "method": Json::string(op), "params": params },
          },
        ],
        request_state: None,
        meta: None,
      })
  }
}

///|
fn elicited(prefix : String) -> (Json) -> String {
  response => {
    let (action, content) = match response {
      Object(fields) =>
        (
          fields.get("action").unwrap_or(Json::string("")),
          fields.get("content").unwrap_or(Json::object(Map([]))),
        )
      _ => (Json::string(""), Json::object(Map([])))
    }
    let word = match action {
      String(word) => word
      other => other.stringify()
    }
    "\{prefix}: action=\{word}, content=\{content.stringify()}"
  }
}

///|
fn tools(mcp : @server.Server) -> Unit {
  fixed(mcp, "test_simple_text", "Tests simple text content response", [
    text("This is a simple text response for testing."),
  ])
  fixed(mcp, "test_image_content", "Tests image content response", [picture()])
  fixed(mcp, "test_audio_content", "Tests audio content response", [
    Audio(data=audio, mime_type="audio/wav", annotations=None, meta=None),
  ])
  fixed(
    mcp,
    "test_embedded_resource",
    "Tests embedded resource content response",
    [
      embedded(
        "test://embedded-resource", "text/plain", "This is an embedded resource content.",
      ),
    ],
  )
  fixed(
    mcp,
    "test_multiple_content_types",
    "Tests response with multiple content types (text, image, resource)",
    [
      text("Multiple content types test:"),
      picture(),
      embedded(
        "test://mixed-content-resource", "application/json", "{\"test\":\"data\",\"value\":123}",
      ),
    ],
  )
  mcp.tool_context(
    "test_tool_with_logging",
    async fn(_, context) {
      context.info("Tool execution started")
      @async.sleep(50)
      context.info("Tool processing data")
      @async.sleep(50)
      context.info("Tool execution completed")
      answer([text("Tool with logging executed successfully")])
    },
    description="Tests tool that emits log messages during execution",
  )
  mcp.tool_context(
    "test_tool_with_progress",
    async fn(_, context) {
      for step in [0, 50, 100] {
        context.report_progress(
          progress=step.to_double(),
          total=100.0,
          message="Completed step \{step} of 100",
        )
        @async.sleep(50)
      }
      let token = context.progress_token().unwrap_or(Json::number(0.0))
      answer([text(token.stringify())])
    },
    description="Tests tool that reports progress notifications",
  )
  mcp.tool_context(
    "test_error_handling",
    (_, _) => {
      raise @exceptions.Tool(
        "This tool intentionally returns an error for testing",
      )
    },
    description="Tests error response handling",
  )
  mcp.tool_context(
    "test_sampling",
    (args, context) => {
      let prompt = args.get("prompt").unwrap_or(Json::string(""))
      ask(
        context,
        "sampling/createMessage",
        {
          "messages": [
            { "role": "user", "content": { "type": "text", "text": prompt } },
          ],
          "maxTokens": 100,
        },
        response => {
          let said = match response {
            Object({ "content": Object({ "text": String(said), .. }), .. }) =>
              said
            _ => "No response"
          }
          "LLM response: \{said}"
        },
      )
    },
    description="Tests server-initiated sampling (LLM completion request)",
    input_schema={
      "type": "object",
      "properties": {
        "prompt": {
          "type": "string",
          "description": "The prompt to send to the LLM",
        },
      },
      "required": ["prompt"],
    },
  )
  mcp.tool_context(
    "test_elicitation",
    (args, context) => {
      ask(
        context,
        "elicitation/create",
        {
          "message": args.get("message").unwrap_or(Json::string("")),
          "requestedSchema": {
            "type": "object",
            "properties": {
              "response": { "type": "string", "description": "User's response" },
            },
            "required": ["response"],
          },
        },
        elicited("User response"),
      )
    },
    description="Tests server-initiated elicitation (user input request)",
    input_schema={
      "type": "object",
      "properties": {
        "message": {
          "type": "string",
          "description": "The message to show the user",
        },
      },
      "required": ["message"],
    },
  )
  mcp.tool_context(
    "test_elicitation_sep1034_defaults",
    (_, context) => {
      ask(
        context,
        "elicitation/create",
        {
          "message": "Please review and update the form fields with defaults",
          "requestedSchema": {
            "type": "object",
            "properties": {
              "name": {
                "type": "string",
                "description": "User name",
                "default": "John Doe",
              },
              "age": {
                "type": "integer",
                "description": "User age",
                "default": 30,
              },
              "score": {
                "type": "number",
                "description": "User score",
                "default": 95.5,
              },
              "status": {
                "type": "string",
                "description": "User status",
                "enum": ["active", "inactive", "pending"],
                "default": "active",
              },
              "verified": {
                "type": "boolean",
                "description": "Verification status",
                "default": true,
              },
            },
            "required": [],
          },
        },
        elicited("Elicitation completed"),
      )
    },
    description="Tests elicitation with default values per SEP-1034",
  )
  mcp.tool_context(
    "test_elicitation_sep1330_enums",
    (_, context) => {
      ask(
        context,
        "elicitation/create",
        {
          "message": "Please select options from the enum fields",
          "requestedSchema": {
            "type": "object",
            "properties": {
              "untitledSingle": {
                "type": "string",
                "description": "Select one option",
                "enum": ["option1", "option2", "option3"],
              },
              "titledSingle": {
                "type": "string",
                "description": "Select one option with titles",
                "oneOf": [
                  { "const": "value1", "title": "First Option" },
                  { "const": "value2", "title": "Second Option" },
                  { "const": "value3", "title": "Third Option" },
                ],
              },
              "legacyEnum": {
                "type": "string",
                "description": "Select one option (legacy)",
                "enum": ["opt1", "opt2", "opt3"],
                "enumNames": ["Option One", "Option Two", "Option Three"],
              },
              "untitledMulti": {
                "type": "array",
                "description": "Select multiple options",
                "minItems": 1,
                "maxItems": 3,
                "items": {
                  "type": "string",
                  "enum": ["option1", "option2", "option3"],
                },
              },
              "titledMulti": {
                "type": "array",
                "description": "Select multiple options with titles",
                "minItems": 1,
                "maxItems": 3,
                "items": {
                  "anyOf": [
                    { "const": "value1", "title": "First Choice" },
                    { "const": "value2", "title": "Second Choice" },
                    { "const": "value3", "title": "Third Choice" },
                  ],
                },
              },
            },
            "required": [],
          },
        },
        elicited("Elicitation completed"),
      )
    },
    description="Tests elicitation with enum schema improvements per SEP-1330",
  )
  mcp.tool_context(
    "json_schema_2020_12_tool",
    (args, _) => {
      answer([
        text("JSON Schema 2020-12 tool called with: " + Json(args).stringify()),
      ])
    },
    description="Tool with JSON Schema 2020-12 features for conformance testing (SEP-1613)",
    input_schema={
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "$defs": {
        "address": {
          "$anchor": "addressDef",
          "type": "object",
          "properties": {
            "street": { "type": "string" },
            "city": { "type": "string" },
          },
        },
      },
      "properties": {
        "name": { "type": "string" },
        "address": { "$ref": "#/$defs/address" },
        "contactMethod": { "type": "string", "enum": ["phone", "email"] },
        "phone": { "type": "string" },
        "email": { "type": "string" },
      },
      "allOf": [
        { "anyOf": [{ "required": ["phone"] }, { "required": ["email"] }] },
      ],
      "if": {
        "properties": { "contactMethod": { "const": "phone" } },
        "required": ["contactMethod"],
      },
      "then": { "required": ["phone"] },
      "else": { "required": ["email"] },
      "additionalProperties": false,
    },
  )
}

///|
fn resources(mcp : @server.Server) -> Unit {
  mcp.resource(
    "test://static-text",
    () => "This is the content of the static text resource.",
    name="static-text",
    title="Static Text Resource",
    description="A static text resource for testing",
    mime_type="text/plain",
  )
  mcp.resource_context(
    "test://static-binary",
    _ => Blob(@base64.decode(image)),
    name="static-binary",
    title="Static Binary Resource",
    description="A static binary resource (image) for testing",
    mime_type="image/png",
  )
  mcp.template(
    "test://template/{id}/data",
    params => {
      let id = match params.get("id") {
        Some(String(id)) => id
        _ => ""
      }
      let body : Json = {
        "id": id,
        "templateTest": true,
        "data": "Data for ID: \{id}",
      }
      body.stringify()
    },
    name="template",
    title="Resource Template",
    description="A resource template with parameter substitution",
    mime_type="application/json",
  )
  mcp.resource(
    "test://watched-resource",
    () => "Watched resource content",
    name="watched-resource",
    title="Watched Resource",
    description="A resource a client can subscribe to",
    mime_type="text/plain",
  )
}

///|
fn prompts(mcp : @server.Server) -> Unit {
  mcp.prompt(
    "test_simple_prompt",
    _ => "This is a simple prompt for testing.",
    title="Simple Test Prompt",
    description="A simple prompt without arguments",
  )
  mcp.prompt(
    "test_prompt_with_arguments",
    args => {
      let word = (name : String) => {
        match args.get(name) {
          Some(String(value)) => value
          _ => ""
        }
      }
      "Prompt with arguments: arg1='\{word("arg1")}', arg2='\{word("arg2")}'"
    },
    title="Prompt With Arguments",
    description="A prompt with required arguments",
    arguments=[
      {
        name: "arg1",
        title: None,
        description: Some("First test argument"),
        required: Some(true),
      },
      {
        name: "arg2",
        title: None,
        description: Some("Second test argument"),
        required: Some(true),
      },
    ],
  )
  mcp.prompt_context(
    "test_prompt_with_embedded_resource",
    (args, _) => {
      let uri = match args.get("resourceUri") {
        Some(String(uri)) => uri
        _ => ""
      }
      Messages([
        @prompts.Message::of_content(
          embedded(uri, "text/plain", "Embedded resource content for testing."),
        ),
        @prompts.Message::text("Please process the embedded resource above."),
      ])
    },
    title="Prompt With Embedded Resource",
    description="A prompt that includes an embedded resource",
    arguments=[
      {
        name: "resourceUri",
        title: None,
        description: Some("URI of the resource to embed"),
        required: Some(true),
      },
    ],
  )
  mcp.prompt_context(
    "test_prompt_with_image",
    (_, _) => {
      Messages([
        @prompts.Message::of_content(picture()),
        @prompts.Message::text("Please analyze the image above."),
      ])
    },
    title="Prompt With Image",
    description="A prompt that includes image content",
  )
}

///|
/// The server the MCP conformance suite tests against, with the tools, resources and prompts its
/// scenarios call by name. `scripts/interop/check_conformance.sh` runs the suite on it.
#coverage.skip
async fn main {
  let mcp = @server.Server::new("moonmcp-conformance", version="1.0.0")
  tools(mcp)
  resources(mcp)
  prompts(mcp)
  mcp.completion((_, _) => {
    values: [],
    total: Some(0),
    has_more: Some(false),
  })
  @mooncat.serve(mcp.to_asgi(), port=12000) catch {
    e => println("stopped: \{e}")
  }
}
