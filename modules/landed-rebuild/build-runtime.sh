#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${FIRN_BUN:-$HOME/.local/lib/firn/cli/current/bin/bun}" build "$here/host.mjs" --target bun --minify --outfile "$here/runtime.mjs"
sed -i '1{/^\/\/ @bun$/d;}' "$here/runtime.mjs"
