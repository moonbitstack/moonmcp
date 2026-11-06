#!/bin/sh
# The official MCP conformance suite against `src/examples/08-conformance-client`, every client
# scenario: the four core ones, the fifteen of the authorization suite, the two older-revision ones,
# the three drafts and the three extensions. Pinned, so a new scenario upstream turns nothing red
# until someone looks at it. Needs Node.
#
#     sh scripts/interop/check_client_conformance.sh
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname "$(dirname "$here")")
cd "$root"

moon build src/examples/08-conformance-client --target native
client=$(find _build/native/debug/build -type f \
  \( -name 08-conformance-client -o -name 08-conformance-client.exe \) | head -1)

# The suite splits the command on spaces and runs it through a shell, so the
# path has to be absolute in the form that shell understands: Windows paths for
# a Windows shell, and the Unix path everywhere else.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) client=$(cygpath -w "$client") ;;
  *) client="$(cd "$(dirname "$client")" && pwd)/$(basename "$client")" ;;
esac

npx --yes @modelcontextprotocol/conformance@0.1.16 client --command "$client" --suite all
