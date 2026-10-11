#!/usr/bin/env bash
set -euo pipefail
bun test "$(dirname "${BASH_SOURCE[0]}")/main-red.test.ts"
