#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/claude-gaffer-sync.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

GAFFER="$SCRATCH/gaffer"
mkdir -p "$GAFFER/.claude-plugin" "$SCRATCH/bin" "$SCRATCH/cache"
printf '%s\n' \
  '{"name":"gaffer","plugins":[{"name":"gaffer","source":"./"}]}' \
  >"$GAFFER/.claude-plugin/marketplace.json"
printf '%s\n' '{"name":"gaffer"}' >"$GAFFER/.claude-plugin/plugin.json"
printf '%s\n' 'current doctrine' >"$GAFFER/doctrine.md"
git -C "$GAFFER" init -q -b main
git -C "$GAFFER" config user.name test
git -C "$GAFFER" config user.email test@example.invalid
git -C "$GAFFER" add .
git -C "$GAFFER" commit -qm initial
HEAD_FULL="$(git -C "$GAFFER" rev-parse HEAD)"
HEAD_SHORT="${HEAD_FULL:0:12}"

cat >"$SCRATCH/bin/timeout" <<'SH'
#!/usr/bin/env bash
shift
exec "$@"
SH
chmod +x "$SCRATCH/bin/timeout"

cat >"$SCRATCH/bin/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALL_LOG"
case "$*" in
  'plugin list --json')
    [ "${LIST_EXIT:-0}" -eq 0 ] || exit "$LIST_EXIT"
    if [ "${LIST_MODE:-}" = malformed ]; then
      printf '%s\n' 'not-json'
      exit 0
    fi
    state="$(cat "$PLUGIN_STATE_FILE")"
    case "$state" in
      absent) printf '%s\n' '[]' ;;
      stale)
        printf '[{"id":"gaffer@gaffer","version":"deadbeefdead","installPath":"%s"}]\n' "$FAKE_INSTALL_PATH"
        ;;
      current)
        printf '[{"id":"gaffer@gaffer","version":"%s","installPath":"%s"}]\n' "$FAKE_HEAD_SHORT" "$FAKE_INSTALL_PATH"
        ;;
      current-full)
        printf '[{"id":"gaffer@gaffer","version":"%s","installPath":"%s"}]\n' "$FAKE_HEAD_FULL" "$FAKE_INSTALL_PATH"
        ;;
      *) exit 96 ;;
    esac
    ;;
  'plugin update gaffer@gaffer --scope user')
    [ "${UPDATE_EXIT:-0}" -eq 0 ] || exit "$UPDATE_EXIT"
    printf '%s\n' "${UPDATE_STATE:-current}" >"$PLUGIN_STATE_FILE"
    ;;
  'plugin marketplace add '*)
    exit "${MARKETPLACE_EXIT:-0}"
    ;;
  'plugin install gaffer@gaffer --scope user')
    [ "${INSTALL_EXIT:-0}" -eq 0 ] || exit "$INSTALL_EXIT"
    printf '%s\n' "${INSTALL_STATE:-current}" >"$PLUGIN_STATE_FILE"
    ;;
  *)
    exit 97
    ;;
esac
SH
chmod +x "$SCRATCH/bin/claude"

run_sync() {
  CALL_LOG="$SCRATCH/calls" \
  CLAUDE_BIN="$SCRATCH/bin/claude" \
  GIT_BIN="$(command -v git)" \
  JQ_BIN="$(command -v jq)" \
  TIMEOUT_BIN="$SCRATCH/bin/timeout" \
  GAFFER_HOME="$GAFFER" \
  PLUGIN_STATE_FILE="$SCRATCH/plugin-state" \
  FAKE_HEAD_FULL="$HEAD_FULL" \
  FAKE_HEAD_SHORT="$HEAD_SHORT" \
  FAKE_INSTALL_PATH="$SCRATCH/cache" \
  LIST_EXIT="${LIST_EXIT:-0}" \
  LIST_MODE="${LIST_MODE:-}" \
  UPDATE_EXIT="${UPDATE_EXIT:-0}" \
  UPDATE_STATE="${UPDATE_STATE:-current}" \
  MARKETPLACE_EXIT="${MARKETPLACE_EXIT:-0}" \
  INSTALL_EXIT="${INSTALL_EXIT:-0}" \
  INSTALL_STATE="${INSTALL_STATE:-current}" \
    "$REPO/scripts/claude-gaffer-plugin-sync.sh"
}

assert_calls() {
  diff -u <(printf '%s\n' "$@") "$SCRATCH/calls"
}

printf '%s\n' current >"$SCRATCH/plugin-state"
: >"$SCRATCH/calls"
run_sync
assert_calls 'plugin list --json'

printf '%s\n' current-full >"$SCRATCH/plugin-state"
: >"$SCRATCH/calls"
run_sync
assert_calls 'plugin list --json'

printf '%s\n' stale >"$SCRATCH/plugin-state"
: >"$SCRATCH/calls"
run_sync
assert_calls \
  'plugin list --json' \
  'plugin update gaffer@gaffer --scope user' \
  'plugin list --json'

printf '%s\n' stale >"$SCRATCH/plugin-state"
: >"$SCRATCH/calls"
if UPDATE_EXIT=8 run_sync 2>/dev/null; then
  printf 'sync must surface a failed update without falling through to install\n' >&2
  exit 1
fi
assert_calls \
  'plugin list --json' \
  'plugin update gaffer@gaffer --scope user'

printf '%s\n' stale >"$SCRATCH/plugin-state"
: >"$SCRATCH/calls"
if UPDATE_STATE=stale run_sync 2>/dev/null; then
  printf 'sync must verify Claude reports the expected commit after update\n' >&2
  exit 1
fi
assert_calls \
  'plugin list --json' \
  'plugin update gaffer@gaffer --scope user' \
  'plugin list --json'

printf '%s\n' absent >"$SCRATCH/plugin-state"
: >"$SCRATCH/calls"
MARKETPLACE_EXIT=1 run_sync
assert_calls \
  'plugin list --json' \
  "plugin marketplace add $GAFFER --scope user" \
  'plugin install gaffer@gaffer --scope user' \
  'plugin list --json'

printf '%s\n' absent >"$SCRATCH/plugin-state"
: >"$SCRATCH/calls"
if INSTALL_EXIT=9 run_sync 2>/dev/null; then
  printf 'sync must surface a failed install\n' >&2
  exit 1
fi

: >"$SCRATCH/calls"
if LIST_MODE=malformed run_sync 2>/dev/null; then
  printf 'sync must reject malformed plugin-list output\n' >&2
  exit 1
fi
assert_calls 'plugin list --json'

: >"$SCRATCH/calls"
if LIST_EXIT=7 run_sync 2>/dev/null; then
  printf 'sync must surface a failed plugin-list probe\n' >&2
  exit 1
fi
assert_calls 'plugin list --json'

printf '%s\n' uncommitted >"$GAFFER/untracked"
printf '%s\n' current >"$SCRATCH/plugin-state"
: >"$SCRATCH/calls"
run_sync
assert_calls 'plugin list --json'

printf '%s\n' stale >"$SCRATCH/plugin-state"
: >"$SCRATCH/calls"
if run_sync 2>/dev/null; then
  printf 'sync must refuse to copy a dirty Gaffer worktree\n' >&2
  exit 1
fi
assert_calls 'plugin list --json'
rm "$GAFFER/untracked"

git -C "$GAFFER" switch -qc feature
printf '%s\n' current >"$SCRATCH/plugin-state"
: >"$SCRATCH/calls"
run_sync
assert_calls 'plugin list --json'

printf '%s\n' stale >"$SCRATCH/plugin-state"
: >"$SCRATCH/calls"
if run_sync 2>/dev/null; then
  printf 'sync must refuse to copy an off-main Gaffer checkout\n' >&2
  exit 1
fi
assert_calls 'plugin list --json'
git -C "$GAFFER" switch -q main

if grep -Fq 'installed_plugins.json' "$REPO/scripts/claude-gaffer-plugin-sync.sh" ||
   grep -Fq 'plugin uninstall' "$REPO/scripts/claude-gaffer-plugin-sync.sh"; then
  printf 'sync must use Claude-owned update/install surfaces only\n' >&2
  exit 1
fi

printf 'ok: Gaffer sync is commit-pure, idempotent, and verifies Claude installed the expected Git version\n'
