#!/usr/bin/env bash
# build/ stays untracked: the clj emitter embeds absolute source paths.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
beagle="${BEAGLE_PATH:-$(cd "$here/../../../.." && pwd)/beagle/main}/bin/beagle"
mkdir -p "$here/build/spaces"
exec "$beagle" build --target clj "$here/src/spaces/main.bclj" \
  "$here/build/spaces/main.clj"
