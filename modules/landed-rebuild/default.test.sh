#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
python3 "$here/fixtures.py"
bash "$here/south-fetch.test.sh"
"${FIRN_BUN:-$HOME/.local/lib/firn/cli/current/bin/bun}" "$here/runtime.test.mjs"
