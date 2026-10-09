#!/usr/bin/env bash
set -euo pipefail
bin="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
scratch=$(mktemp -d)
trap 'rm -rf "${scratch:?}"' EXIT
repo="$scratch/repo"
git init -q -b main "$repo"
git -C "$repo" config user.name instruction-test
git -C "$repo" config user.email instruction-test@example.invalid
mkdir -p "$repo/nested" "$scratch/bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$scratch/bin/gitleaks"
chmod +x "$scratch/bin/gitleaks"
git init --bare -q -b main "$scratch/remote"
git -C "$repo" remote add origin "$scratch/remote"

lines() { awk -v count="$1" 'BEGIN {for (i=0;i<count;i++) print "rule"}'; }
save() { git -C "$repo" add AGENTS.md nested/AGENTS.md dotfiles 2>/dev/null || git -C "$repo" add AGENTS.md nested/AGENTS.md; git -C "$repo" commit -qm fixture; }
cases=0
expect() {
  local want="$1" name="$2" status=0
  shift 2
  "$@" >"$scratch/output" 2>&1 || status=$?
  if [[ "$status" != "$want" ]]; then
    printf 'FAIL [spec firn#9] %s: got exit %s, want %s\n' "$name" "$status" "$want" >&2
    cat "$scratch/output" >&2
    exit 1
  fi
  if [[ "$want" == 1 ]]; then
    rg -q 'CLI --help, help TOPIC, or indexed docs' "$scratch/output"
  fi
  cases=$((cases + 1))
}

lines 100 >"$repo/AGENTS.md"
lines 100 >"$repo/nested/AGENTS.md"
save
valid=$(git -C "$repo" rev-parse HEAD)
expect 0 'root and nested accept 100 lines' "$bin/agent-instruction-check" --repo "$repo"
lines 101 >"$repo/AGENTS.md"
save
expect 1 'root refuses 101 lines' "$bin/agent-instruction-check" --repo "$repo"
expect 0 'captured ref ignores newer oversized file' "$bin/agent-instruction-check" --repo "$repo" --ref "$valid"
lines 100 >"$repo/AGENTS.md"
lines 101 >"$repo/nested/AGENTS.md"
save
expect 1 'nested refuses 101 lines' "$bin/agent-instruction-check" --repo "$repo"
expect 1 'branch publication refuses oversized instructions' bash -c 'cd "$1"; PATH="$2:$PATH" "$3" --dry-run' _ "$repo" "$scratch/bin" "$bin/safe-push"
git -C "$repo" tag -a release -m release
expect 1 'tag publication checks its oversized target' bash -c 'cd "$1"; PATH="$2:$PATH" "$3" --dry-run --tag release' _ "$repo" "$scratch/bin" "$bin/safe-push"

lines 200 >"$scratch/global"
expect 0 'generated global accepts 200 lines' "$bin/agent-instruction-check" --global "$scratch/global"
lines 201 >"$scratch/global"
expect 1 'generated global refuses 201 lines' "$bin/agent-instruction-check" --global "$scratch/global"

lines 100 >"$repo/nested/AGENTS.md"
mkdir -p "$repo/dotfiles/agents"
cat >"$repo/dotfiles/agents/catalog-config.json" <<'JSON'
{"baselines":[{"owner":{"repo":"nixos-config","path":"dotfiles/agents/AGENTS.md"},"targets":["shared","codex"]}]}
JSON
lines 197 >"$repo/dotfiles/agents/AGENTS.md"
save
expect 0 'proposed catalog renders 200 lines including source header and spacing' "$bin/agent-instruction-check" --repo "$repo"
lines 198 >"$repo/dotfiles/agents/AGENTS.md"
save
expect 1 'proposed catalog refuses 201 rendered lines' "$bin/agent-instruction-check" --repo "$repo"
printf 'agent-instruction-check: %s [spec firn#9] cases passed\n' "$cases"
