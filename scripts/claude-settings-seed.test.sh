#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SEEDER="$REPO/scripts/claude-settings-seed.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/claude-settings-seed.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT

seed="$SCRATCH/seed.json"
printf '%s\n' '{"effortLevel":"xhigh","hooks":{"SessionEnd":[]}}' >"$seed"

run_seed() {
  HOME="$SCRATCH/home" CLAUDE_SETTINGS_SEED_ALLOW_NONSTORE=1 \
    "$SEEDER" "$seed" "$1"
}

assert_seeded() {
  local target="$1"
  [ -f "$target" ]
  [ ! -L "$target" ]
  [ -w "$target" ]
  cmp -s "$seed" "$target"
}

# A fresh profile receives one writable regular copy with private permissions.
fresh="$SCRATCH/fresh/.claude/settings.json"
run_seed "$fresh"
assert_seeded "$fresh"
[ "$(stat -c '%a' "$fresh")" = 600 ]

# Runtime writes are permitted, but the next activation converges to its exact
# committed generation before the ordered plugin reconciliation runs.
printf '%s\n' '{"effortLevel":"medium","enabledPlugins":{"orchestration@orchestration":true}}' >"$fresh"
run_seed "$fresh"
assert_seeded "$fresh"

# A later committed seed revision converges an already-regular runtime file.
printf '%s\n' '{"effortLevel":"high","hooks":{"SessionEnd":[]},"seedRevision":2}' >"$seed"
run_seed "$fresh"
assert_seeded "$fresh"
grep -Fq '"seedRevision":2' "$fresh"

# The legacy mutable-checkout link and a dangling link both migrate to the seed.
mkdir -p "$SCRATCH/checkout" "$SCRATCH/legacy/.claude" "$SCRATCH/dangling/.claude"
printf '%s\n' '{"hooks":{"SessionEnd":[{"hooks":[{"command":"/home/tom/code/north/bin/north-on-stop"}]}]}}' \
  >"$SCRATCH/checkout/settings.json"
ln -s "$SCRATCH/checkout/settings.json" "$SCRATCH/legacy/.claude/settings.json"
run_seed "$SCRATCH/legacy/.claude/settings.json"
assert_seeded "$SCRATCH/legacy/.claude/settings.json"
grep -Fq '/home/tom/code/north/bin/north-on-stop' "$SCRATCH/checkout/settings.json"

ln -s "$SCRATCH/missing-settings.json" "$SCRATCH/dangling/.claude/settings.json"
run_seed "$SCRATCH/dangling/.claude/settings.json"
assert_seeded "$SCRATCH/dangling/.claude/settings.json"

# Simulate SIGKILL after the complete stage write but before the atomic rename.
mkdir -p "$SCRATCH/crash/.claude" "$SCRATCH/fake-bin"
ln -s "$SCRATCH/checkout/settings.json" "$SCRATCH/crash/.claude/settings.json"
fake_install="$SCRATCH/fake-bin/install-crash"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -eu' \
  'while [ "$#" -gt 2 ]; do shift; done' \
  'cp "$1" "$2"' \
  'kill -KILL "$PPID"' >"$fake_install"
chmod +x "$fake_install"
set +e
{
  CLAUDE_SETTINGS_SEED_ALLOW_NONSTORE=1 INSTALL_BIN="$fake_install" \
    "$SEEDER" "$seed" "$SCRATCH/crash/.claude/settings.json" \
    >/dev/null 2>&1
  crash_status=$?
} 2>/dev/null
set -e
[ "$crash_status" -ne 0 ]
[ -L "$SCRATCH/crash/.claude/settings.json" ]
[ -f "$SCRATCH/crash/.claude/.firn-settings-seed.tmp" ]
run_seed "$SCRATCH/crash/.claude/settings.json"
assert_seeded "$SCRATCH/crash/.claude/settings.json"
[ ! -e "$SCRATCH/crash/.claude/.firn-settings-seed.tmp" ]

# Concurrent retries serialize; exactly the same complete seed wins.
mkdir -p "$SCRATCH/concurrent/.claude"
ln -s "$SCRATCH/checkout/settings.json" "$SCRATCH/concurrent/.claude/settings.json"
pids=()
for _ in 1 2 3 4; do
  run_seed "$SCRATCH/concurrent/.claude/settings.json" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
assert_seeded "$SCRATCH/concurrent/.claude/settings.json"

# Invalid seeds and non-file runtime targets fail without destructive repair.
printf '%s\n' '{not-json' >"$SCRATCH/invalid.json"
mkdir -p "$SCRATCH/invalid/.claude"
ln -s "$SCRATCH/checkout/settings.json" "$SCRATCH/invalid/.claude/settings.json"
if CLAUDE_SETTINGS_SEED_ALLOW_NONSTORE=1 "$SEEDER" \
  "$SCRATCH/invalid.json" "$SCRATCH/invalid/.claude/settings.json" \
  >/dev/null 2>&1; then
  printf 'invalid seed unexpectedly succeeded\n' >&2
  exit 1
fi
[ -L "$SCRATCH/invalid/.claude/settings.json" ]

mkdir -p "$SCRATCH/special/.claude/settings.json"
if run_seed "$SCRATCH/special/.claude/settings.json" >/dev/null 2>&1; then
  printf 'directory target unexpectedly succeeded\n' >&2
  exit 1
fi
[ -d "$SCRATCH/special/.claude/settings.json" ]

# The committed seed contains no mutable-checkout North hook command.
jq -e '
  [
    .hooks | to_entries[] | .value[]? | .hooks[]?
    | select(.type == "command")
    | .command
    | select(test("north"; "i"))
    | select(contains("/home/tom/code"))
  ] | length == 0
' "$REPO/dotfiles/claude/settings.json" >/dev/null

jq -e '
  any(.entries[];
    .event == "SessionEnd"
    and .hook.command == "/home/tom/.agents/hooks/north-session-end.sh")
' "$REPO/dotfiles/agents/hooks.d/north-session-lifecycle.json" >/dev/null

grep -Fq '(pkgs.writeText "claude-settings.json"' "$REPO/modules/claude/default.bnix"
grep -Fq '(pkgs.writeShellScript "claude-settings-seed"' "$REPO/modules/claude/default.bnix"
grep -Fq ':home.activation.seedClaudeSettings' "$REPO/modules/claude/default.bnix"
grep -Fq '/bin/flock JQ_BIN=' "$REPO/modules/claude/default.bnix"
grep -Fq '(config.lib.dag.entryAfter ["writeBoundary"]' "$REPO/modules/claude/default.bnix"
if grep -Fq 'writeShellScriptBin "north-session-end"' "$REPO/modules/claude/default.bnix"; then
  printf 'Claude module still packages the out-of-store profile SessionEnd hook\n' >&2
  exit 1
fi
if grep -Fq 'linkClaudeSettings' "$REPO/modules/claude/default.bnix" ||
   grep -Fq '/code/nixos-config/dotfiles/claude/settings.json' \
     "$REPO/modules/claude/default.bnix"; then
  printf 'Claude module still links runtime settings to the mutable checkout\n' >&2
  exit 1
fi

grep -Fq 'pkgs.writeText "claude-settings.json"' "$REPO/modules/claude/default.nix"
grep -Fq 'home.activation.seedClaudeSettings' "$REPO/modules/claude/default.nix"
if grep -Fq 'linkClaudeSettings' "$REPO/modules/claude/default.nix" ||
   grep -Fq '/code/nixos-config/dotfiles/claude/settings.json' \
     "$REPO/modules/claude/default.nix"; then
  printf 'generated Claude module still links runtime settings to the mutable checkout\n' >&2
  exit 1
fi

printf '%s\n' \
  'ok: Claude settings seed is generation-exact, writable, atomic, idempotent, and checkout-free'
