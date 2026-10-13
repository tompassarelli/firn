#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
beagle="${BEAGLE_PATH:-$HOME/code/beagle/main}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-landed-runtime.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT
"$beagle/bin/beagle-build-all" "$beagle/native-core/src/native/json.bjs" \
  "$repo/native/impact.bjs" "$repo/native/rebuild.bjs" "$repo/native/rebuild_native.bjs" \
  "$repo/native/firn_rebuild_family.bjs" --out "$scratch/generated"
mkdir -p "$scratch/node_modules/beagle"
cp "$beagle/beagle-lib/lib/beagle/core.js" "$beagle/beagle-lib/lib/beagle/host.js" "$scratch/node_modules/beagle/"
printf '%s\n' '{"type":"module"}' > "$scratch/node_modules/beagle/package.json"
cp "$here/host.mjs" "$scratch/host.mjs"
"${FIRN_BUN:-$HOME/.local/lib/firn/cli/current/bin/bun}" build "$scratch/host.mjs" --target bun --minify --outfile "$here/runtime.mjs"
sed -i '1{/^\/\/ @bun$/d;}' "$here/runtime.mjs"
