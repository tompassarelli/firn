#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
python3 "$here/fixtures.py"
"${FIRN_BUN:-$HOME/.local/lib/firn/cli/current/bin/bun}" "$here/runtime.test.mjs"
