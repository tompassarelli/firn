#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAP="$ROOT/dotfiles/bin/harness-map"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture:?}"' EXIT

home="$fixture/home"
code_root="$home/code"
nixos_root="$code_root/nixos-config/main"
north_root="$code_root/north/main"
praxis_root="$north_root/orchestration/docs"
build_marker="$fixture/build-agents.marker"

mkdir -p \
  "$home/.claude" \
  "$code_root" \
  "$nixos_root" \
  "$north_root/sdk/src" \
  "$north_root/orchestration/scripts" \
  "$praxis_root/deltas"

printf '# code-root instructions\n' >"$code_root/CLAUDE.md"
printf '# selected nixos instructions\n' >"$nixos_root/CLAUDE.md"
printf '%s\n' roles >"$praxis_root/roles.md"
printf '%s\n' postures >"$praxis_root/postures.md"
printf '%s\n' comms >"$praxis_root/comms.md"

cat >"$north_root/sdk/src/harness.ts" <<EOF
const PRAXIS_DIR = \`$praxis_root\`;
function globalLawsAppendix() {}
function esoAppendix() {}
function praxisAppendix() {}
EOF

cat >"$north_root/orchestration/scripts/build-agents.mjs" <<'EOF'
import { writeFileSync } from "node:fs";
writeFileSync(process.env.HARNESS_MAP_BUILD_MARKER, process.argv[2] || "");
EOF

cat >"$nixos_root/.mcp.json" <<'EOF'
{"mcpServers":{"selected-nixos":{"command":"selected-nixos-command"}}}
EOF
cat >"$code_root/.mcp.json" <<'EOF'
{"mcpServers":{"selected-code":{"command":"selected-code-command"}}}
EOF

run_map() {
  env HOME="$home" \
    HARNESS_MAP_BUILD_MARKER="$build_marker" \
    "$MAP"
}

first="$(run_map)"
grep -Fq '~/code/CLAUDE.md' <<<"$first"
grep -Fq '~/code/nixos-config/main/CLAUDE.md' <<<"$first" # hardcoded-repo-path:allow
grep -Fq '~/code/north/main/sdk/src/harness.ts' <<<"$first" # hardcoded-repo-path:allow
grep -Fq "selected-code-command" <<<"$first"
grep -Fq "PASS  orchestration build-agents --check" <<<"$first"
grep -Fxq -- "--check" "$build_marker"

rm -f "${code_root:?}/.mcp.json"
second="$(run_map)"
grep -Fq "selected-nixos-command" <<<"$second"

echo "harness-map canonical roots: PASS"
