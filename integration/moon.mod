name = "moonbitstack/moonmcp-ecosystem"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonmcp"

license = "Apache-2.0"

keywords = [
  "mcp",
  "model-context-protocol",
  "example",
  "conformance",
  "moonbit",
]

description = "The servers and clients that need a program to run them: mooncat serving moonmcp, and the executables the interoperability suites drive."

source = "src"

import {
  "moonbitlang/async@0.22.5",
  "moonbitstack/moonasgi@0.11.2",
  "moonbitstack/mooncat@0.20.0",
  "moonbitstack/moonmcp@0.1.12",
  "moonbitstack/moonbase@0.5.0",
}
