#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAP="$ROOT/dotfiles/bin/harness-map"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture:?}"' EXIT

home="$fixture/home"
code_root="$fixture/world/code"
nixos_root="$fixture/world/nixos"
north_root="$fixture/world/north"
praxis_root="$north_root/orchestration/docs"
manifest="$fixture/manifest.env"
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

{
  printf 'WORLD_CODE_ROOT=%q\n' "$code_root"
  printf 'WORLD_REPO_NIXOS_CONFIG=%q\n' "$nixos_root"
  printf 'WORLD_REPO_NORTH=%q\n' "$north_root"
} >"$manifest"

run_map() {
  env -u WORLD_BIN \
    HOME="$home" \
    WORLD_MANIFEST_PATH="$manifest" \
    HARNESS_MAP_BUILD_MARKER="$build_marker" \
    "$MAP"
}

first="$(run_map)"
grep -Fq "$code_root/CLAUDE.md" <<<"$first"
grep -Fq "$nixos_root/CLAUDE.md" <<<"$first"
grep -Fq "$north_root/sdk/src/harness.ts" <<<"$first"
grep -Fq "selected-code-command" <<<"$first"
grep -Fq "PASS  orchestration build-agents --check" <<<"$first"
grep -Fxq -- "--check" "$build_marker"

rm -f "${code_root:?}/.mcp.json"
second="$(run_map)"
grep -Fq "selected-nixos-command" <<<"$second"

echo "harness-map world manifest: PASS"
