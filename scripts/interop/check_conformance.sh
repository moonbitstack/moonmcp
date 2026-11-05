#!/bin/sh
# The official MCP conformance suite against `src/examples/07-conformance`, every server scenario
# including the ones still pending upstream. Pinned, so a new scenario upstream turns nothing red
# until someone looks at it. Needs Node.
#
#     sh scripts/interop/check_conformance.sh
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname "$(dirname "$here")")
cd "$root"

moon build src/examples/07-conformance --target native
server=$(find _build/native/debug/build -type f \( -name 07-conformance -o -name 07-conformance.exe \) | head -1)

"$server" > /dev/null 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
sleep 1

npx --yes @modelcontextprotocol/conformance@0.1.16 server --url http://127.0.0.1:12000/mcp --suite all
