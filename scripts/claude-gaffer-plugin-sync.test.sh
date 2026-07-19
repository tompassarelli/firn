#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/claude-gaffer-sync.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

REAL_GIT="$(command -v git)"
REAL_MV="$(command -v mv)"
REAL_PS="$(command -v ps)"
REAL_TIMEOUT="$(command -v timeout)"
GAFFER="$SCRATCH/gaffer"
MANAGED_SOURCE="$SCRATCH/state/north/gaffer-plugin-source"
mkdir -p "$GAFFER/.claude-plugin" "$SCRATCH/bin"
printf '%s\n' \
  '{"name":"gaffer","plugins":[{"name":"gaffer","source":"./"}]}' \
  >"$GAFFER/.claude-plugin/marketplace.json"
printf '%s\n' '{"name":"gaffer"}' >"$GAFFER/.claude-plugin/plugin.json"
printf '%s\n' 'base doctrine' >"$GAFFER/doctrine.md"
"$REAL_GIT" -C "$GAFFER" init -q -b main
"$REAL_GIT" -C "$GAFFER" config user.name test
"$REAL_GIT" -C "$GAFFER" config user.email test@example.invalid
"$REAL_GIT" -C "$GAFFER" add .
"$REAL_GIT" -C "$GAFFER" commit -qm base
BASE_REV="$("$REAL_GIT" -C "$GAFFER" rev-parse HEAD)"
printf '%s\n' 'verified doctrine' >"$GAFFER/doctrine.md"
"$REAL_GIT" -C "$GAFFER" add doctrine.md
"$REAL_GIT" -C "$GAFFER" commit -qm verified
VERIFIED_REV="$("$REAL_GIT" -C "$GAFFER" rev-parse HEAD)"
ALTERNATE_REV="$(
  printf '%s\n' 'alternate exact build' |
    "$REAL_GIT" -C "$GAFFER" commit-tree "$VERIFIED_REV^{tree}" -p "$VERIFIED_REV"
)"

# The primary checkout deliberately stays on a dirty feature branch throughout
# reconciliation. Its branch, HEAD, refs/heads/main, and dirty bytes are not
# inputs; only GAFFER_REV is.
"$REAL_GIT" -C "$GAFFER" switch -qc feature "$BASE_REV"
printf '%s\n' 'dirty feature bytes' >>"$GAFFER/doctrine.md"
printf '%s\n' 'untracked feature bytes' >"$GAFFER/untracked"
FEATURE_REV="$("$REAL_GIT" -C "$GAFFER" rev-parse HEAD)"

# Fake Git records every command but delegates to a hermetic temporary repo, so
# the test exercises real worktree/ref semantics without touching user state.
cat >"$SCRATCH/bin/git" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GIT_CALL_LOG"
if [ "${GIT_CRASH_AFTER_ADD:-0}" -eq 1 ] &&
   [[ " $* " == *" worktree add --detach "* ]]; then
  "$REAL_GIT_BIN" "$@"
  exit 99
fi
if [ "${GIT_CRASH_AFTER_CHECKOUT:-0}" -eq 1 ] &&
   [[ " $* " == *" checkout --detach "* ]]; then
  "$REAL_GIT_BIN" "$@"
  exit 98
fi
exec "$REAL_GIT_BIN" "$@"
SH
chmod +x "$SCRATCH/bin/git"

cat >"$SCRATCH/bin/timeout" <<'SH'
#!/usr/bin/env bash
[ "${TIMEOUT_ZERO_EXIT:-0}" -eq 0 ] || exit 0
exec "$REAL_TIMEOUT_BIN" "$@"
SH
chmod +x "$SCRATCH/bin/timeout"

cat >"$SCRATCH/bin/mv" <<'SH'
#!/usr/bin/env bash
"$REAL_MV_BIN" "$@" || exit
if [ "${MV_CRASH_AFTER_INTENT_REPLACE:-0}" -eq 1 ] &&
   [ "${*: -1}" = "$FAKE_INTENT_PATH" ]; then
  exit 97
fi
SH
chmod +x "$SCRATCH/bin/mv"

cat >"$SCRATCH/bin/ps" <<'SH'
#!/usr/bin/env bash
output="$("$REAL_PS_BIN" "$@")" || exit
pid="${*: -1}"
pgid="${output//[[:space:]]/}"
printf '%s %s\n' "$pid" "$pgid" >>"$PS_CALL_LOG"
printf '%s\n' "$output"
SH
chmod +x "$SCRATCH/bin/ps"

mkdir "$SCRATCH/bsd-bin"
cat >"$SCRATCH/bsd-bin/mv" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BSD_MV_CALLS"
for arg in "$@"; do
  [ "$arg" != -T ] || exit 91
done
exec "$REAL_MV_BIN" "$@"
SH
chmod +x "$SCRATCH/bsd-bin/mv"

cat >"$SCRATCH/bin/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALL_LOG"
case "$*" in
  'plugin marketplace list --json')
    case "${OUTPUT_FLOOD_MODE:-}" in
      stdout)
        while printf '%064d\n' 0; do :; done
        ;;
      stderr)
        while printf '%064d\n' 0 >&2; do :; done
        ;;
    esac
    if [ "${RESISTANT_LIST_MODE:-0}" -eq 1 ]; then
      (
        trap '' TERM
        printf '%s\n' "$BASHPID" >"$RESISTANT_DESCENDANT_PID_FILE"
        sleep "$RESISTANT_MUTATION_DELAY"
        printf '%s\n' leaked >"$POST_LOCK_MUTATION_FILE"
      ) &
      trap 'exit 0' TERM
      wait
    fi
    [ "${MARKETPLACE_LIST_EXIT:-0}" -eq 0 ] || exit "$MARKETPLACE_LIST_EXIT"
    if [ "${MARKETPLACE_LIST_MODE:-}" = malformed ]; then
      printf '%s\n' 'not-json'
      exit 0
    fi
    marketplace_state="$(cat "$MARKETPLACE_STATE_FILE")"
    case "$marketplace_state" in
      absent)
        printf '%s\n' '[]'
        ;;
      exact)
        printf '[{"name":"gaffer","source":"directory","path":"%s","installLocation":"%s"}]\n' \
          "$FAKE_MARKETPLACE_PATH" "$FAKE_MARKETPLACE_PATH"
        ;;
      legacy)
        printf '[{"name":"gaffer","source":"directory","path":"%s","installLocation":"%s"}]\n' \
          "$FAKE_LEGACY_SOURCE" "$FAKE_LEGACY_SOURCE"
        ;;
      hostile)
        printf '%s\n' \
          '[{"name":"gaffer","source":"directory","path":"/tmp/hostile","installLocation":"/tmp/hostile"}]'
        ;;
      duplicate)
        printf '[{"name":"gaffer","source":"directory","path":"%s","installLocation":"%s"},{"name":"gaffer","source":"directory","path":"%s","installLocation":"%s"}]\n' \
          "$FAKE_SOURCE" "$FAKE_SOURCE" "$FAKE_SOURCE" "$FAKE_SOURCE"
        ;;
      *)
        exit 95
        ;;
    esac
    ;;
  'plugin marketplace add '*)
    [ "$*" = "plugin marketplace add $FAKE_SOURCE --scope user" ] || exit 94
    [ "${MARKETPLACE_ADD_EXIT:-0}" -eq 0 ] || exit "$MARKETPLACE_ADD_EXIT"
    printf '%s\n' exact >"$MARKETPLACE_STATE_FILE"
    ;;
  'plugin list --json')
    count=0
    if [ -s "$LIST_COUNT_FILE" ]; then
      count="$(cat "$LIST_COUNT_FILE")"
    fi
    count=$((count + 1))
    printf '%s\n' "$count" >"$LIST_COUNT_FILE"
    if [ "${LIST_FAIL_ON:-0}" -eq "$count" ]; then
      exit "${LIST_FAIL_EXIT:-7}"
    fi
    [ "${LIST_EXIT:-0}" -eq 0 ] || exit "$LIST_EXIT"
    if [ "${LIST_MODE:-}" = malformed ]; then
      printf '%s\n' 'not-json'
      exit 0
    fi
    state="$(cat "$PLUGIN_STATE_FILE")"
    case "$state" in
      absent) printf '%s\n' '[]' ;;
      stale)
        printf '[{"id":"gaffer@gaffer","version":"deadbeefdead"}]\n'
        ;;
      current)
        printf '[{"id":"gaffer@gaffer","version":"%s"}]\n' "$FAKE_REV_SHORT"
        ;;
      current-full)
        printf '[{"id":"gaffer@gaffer","version":"%s"}]\n' "$FAKE_REV_FULL"
        ;;
      exact:*)
        exact_revision="${state#exact:}"
        printf '[{"id":"gaffer@gaffer","version":"%s"}]\n' "${exact_revision:0:12}"
        ;;
      *) exit 96 ;;
    esac
    ;;
  'plugin update gaffer@gaffer --scope user')
    [ "${UPDATE_EXIT:-0}" -eq 0 ] || exit "$UPDATE_EXIT"
    if [ -n "${MUTATION_GUARD:-}" ]; then
      mkdir "$MUTATION_GUARD" || exit 88
      trap 'rmdir "$MUTATION_GUARD"' EXIT
      sleep "${MUTATION_SLEEP_SECONDS:-0}"
    fi
    printf '%s\n' "${UPDATE_STATE:-exact:$FAKE_REV_FULL}" >"$PLUGIN_STATE_FILE"
    ;;
  'plugin install gaffer@gaffer --scope user')
    [ "${INSTALL_EXIT:-0}" -eq 0 ] || exit "$INSTALL_EXIT"
    if [ -n "${MUTATION_GUARD:-}" ]; then
      mkdir "$MUTATION_GUARD" || exit 88
      trap 'rmdir "$MUTATION_GUARD"' EXIT
      sleep "${MUTATION_SLEEP_SECONDS:-0}"
    fi
    printf '%s\n' "${INSTALL_STATE:-exact:$FAKE_REV_FULL}" >"$PLUGIN_STATE_FILE"
    ;;
  *)
    exit 97
    ;;
esac
SH
chmod +x "$SCRATCH/bin/claude"

run_sync() {
  local revision="${GAFFER_REV_OVERRIDE:-$VERIFIED_REV}"
  : >"$SCRATCH/list-count"
  CALL_LOG="$SCRATCH/claude-calls" \
  GIT_CALL_LOG="$SCRATCH/git-calls" \
  REAL_GIT_BIN="$REAL_GIT" \
  GIT_CRASH_AFTER_ADD="${GIT_CRASH_AFTER_ADD:-0}" \
  GIT_CRASH_AFTER_CHECKOUT="${GIT_CRASH_AFTER_CHECKOUT:-0}" \
  CLAUDE_BIN="$SCRATCH/bin/claude" \
  GIT_BIN="$SCRATCH/bin/git" \
  JQ_BIN="$(command -v jq)" \
  TIMEOUT_BIN="$SCRATCH/bin/timeout" \
  REAL_TIMEOUT_BIN="$REAL_TIMEOUT" \
  TIMEOUT_ZERO_EXIT="${TIMEOUT_ZERO_EXIT:-0}" \
  FLOCK_BIN="$(command -v flock)" \
  MV_BIN="$SCRATCH/bin/mv" \
  REAL_MV_BIN="$REAL_MV" \
  MV_CRASH_AFTER_INTENT_REPLACE="${MV_CRASH_AFTER_INTENT_REPLACE:-0}" \
  FAKE_INTENT_PATH="${GAFFER_SOURCE_OVERRIDE:-$MANAGED_SOURCE}.intent" \
  SLEEP_BIN="$(command -v sleep)" \
  PS_BIN="$SCRATCH/bin/ps" \
  REAL_PS_BIN="$REAL_PS" \
  PS_CALL_LOG="$SCRATCH/ps-calls" \
  WC_BIN="$(command -v wc)" \
  GAFFER_HOME="$GAFFER" \
  GAFFER_SOURCE="${GAFFER_SOURCE_OVERRIDE:-$MANAGED_SOURCE}" \
  GAFFER_LOCK="${GAFFER_LOCK_OVERRIDE:-$SCRATCH/state/north/gaffer-plugin-source.lock}" \
  GAFFER_REV="$revision" \
  LOCK_TIMEOUT_SECONDS="${LOCK_TIMEOUT_SECONDS:-5}" \
  LIST_TIMEOUT_SECONDS="${LIST_TIMEOUT_SECONDS:-2}" \
  MUTATION_TIMEOUT_SECONDS="${MUTATION_TIMEOUT_SECONDS:-2}" \
  KILL_AFTER_SECONDS="${KILL_AFTER_SECONDS:-0.2}" \
  BOUND_POLL_SECONDS="${BOUND_POLL_SECONDS:-0.01}" \
  MAX_OUTPUT_KIB="${MAX_OUTPUT_KIB:-64}" \
  PLUGIN_STATE_FILE="$SCRATCH/plugin-state" \
  MARKETPLACE_STATE_FILE="$SCRATCH/marketplace-state" \
  LIST_COUNT_FILE="$SCRATCH/list-count" \
  FAKE_SOURCE="${GAFFER_SOURCE_OVERRIDE:-$MANAGED_SOURCE}" \
  FAKE_MARKETPLACE_PATH="${FAKE_MARKETPLACE_PATH:-${GAFFER_SOURCE_OVERRIDE:-$MANAGED_SOURCE}}" \
  FAKE_LEGACY_SOURCE="$GAFFER" \
  FAKE_REV_FULL="$revision" \
  FAKE_REV_SHORT="${revision:0:12}" \
  LIST_EXIT="${LIST_EXIT:-0}" \
  LIST_FAIL_ON="${LIST_FAIL_ON:-0}" \
  LIST_FAIL_EXIT="${LIST_FAIL_EXIT:-7}" \
  LIST_MODE="${LIST_MODE:-}" \
  MARKETPLACE_LIST_EXIT="${MARKETPLACE_LIST_EXIT:-0}" \
  MARKETPLACE_LIST_MODE="${MARKETPLACE_LIST_MODE:-}" \
  MARKETPLACE_ADD_EXIT="${MARKETPLACE_ADD_EXIT:-0}" \
  OUTPUT_FLOOD_MODE="${OUTPUT_FLOOD_MODE:-}" \
  RESISTANT_LIST_MODE="${RESISTANT_LIST_MODE:-0}" \
  RESISTANT_DESCENDANT_PID_FILE="${RESISTANT_DESCENDANT_PID_FILE:-$SCRATCH/resistant-descendant.pid}" \
  RESISTANT_MUTATION_DELAY="${RESISTANT_MUTATION_DELAY:-0.5}" \
  POST_LOCK_MUTATION_FILE="${POST_LOCK_MUTATION_FILE:-$SCRATCH/post-lock-mutation}" \
  UPDATE_EXIT="${UPDATE_EXIT:-0}" \
  UPDATE_STATE="${UPDATE_STATE:-}" \
  INSTALL_EXIT="${INSTALL_EXIT:-0}" \
  INSTALL_STATE="${INSTALL_STATE:-}" \
  MUTATION_GUARD="${MUTATION_GUARD:-}" \
  MUTATION_SLEEP_SECONDS="${MUTATION_SLEEP_SECONDS:-0}" \
    "$REPO/scripts/claude-gaffer-plugin-sync.sh"
}

reset_calls() {
  : >"$SCRATCH/claude-calls"
  : >"$SCRATCH/git-calls"
}

assert_calls() {
  diff -u <(printf '%s\n' "$@") "$SCRATCH/claude-calls"
}

assert_no_calls() {
  [ ! -s "$SCRATCH/claude-calls" ] || {
    printf 'Claude was called before managed-source admission succeeded\n' >&2
    return 1
  }
}

assert_exact_managed_source() {
  local source="${1:-$MANAGED_SOURCE}" revision="${2:-$VERIFIED_REV}"
  local managed_git_dir

  [ "$("$REAL_GIT" -C "$source" rev-parse HEAD)" = "$revision" ]
  if "$REAL_GIT" -C "$source" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
    printf 'managed Gaffer source must stay detached\n' >&2
    return 1
  fi
  [ -z "$("$REAL_GIT" -C "$source" status --porcelain --untracked-files=all)" ]
  managed_git_dir="$("$REAL_GIT" -C "$source" rev-parse --path-format=absolute --git-dir)"
  [ "$(<"$managed_git_dir/north-managed-gaffer-plugin-source")" = \
    north-gaffer-plugin-source-v1 ]
  jq -e \
    --arg source "$source" \
    --arg revision "$revision" \
    '.version == "north-gaffer-plugin-source-intent-v1"
     and .source == $source
     and .revision == $revision' \
    "$source.intent" >/dev/null
  "$REAL_GIT" -C "$GAFFER" worktree list --porcelain |
    grep -A4 -F "worktree $(realpath -m "$source")" |
    grep -Fx 'locked north-gaffer-plugin-source-v1' >/dev/null
  [ "$("$REAL_GIT" -C "$GAFFER" rev-parse HEAD)" = "$FEATURE_REV" ]
  grep -q 'dirty feature bytes' "$GAFFER/doctrine.md"
  [ -f "$GAFFER/untracked" ]
}

# Fresh install is sourced from a newly created exact detached worktree even
# though the primary checkout is off-main and dirty.
printf '%s\n' absent >"$SCRATCH/plugin-state"
printf '%s\n' absent >"$SCRATCH/marketplace-state"
reset_calls
run_sync
assert_calls \
  'plugin marketplace list --json' \
  "plugin marketplace add $MANAGED_SOURCE --scope user" \
  'plugin marketplace list --json' \
  'plugin list --json' \
  'plugin install gaffer@gaffer --scope user' \
  'plugin list --json'
assert_exact_managed_source

# The single historical v0 source is a versioned deterministic migration.
# Every other same-name source, duplicate, malformed, or failed supported
# marketplace operation fails before plugin mutation.
printf '%s\n' current >"$SCRATCH/plugin-state"
printf '%s\n' legacy >"$SCRATCH/marketplace-state"
reset_calls
run_sync
assert_calls \
  'plugin marketplace list --json' \
  "plugin marketplace add $MANAGED_SOURCE --scope user" \
  'plugin marketplace list --json' \
  'plugin list --json'
[ "$(<"$SCRATCH/marketplace-state")" = exact ]

printf '%s\n' hostile >"$SCRATCH/marketplace-state"
reset_calls
if run_sync 2>/dev/null; then
  printf 'hostile same-name marketplace source was accepted\n' >&2
  exit 1
fi
assert_calls 'plugin marketplace list --json'

printf '%s\n' duplicate >"$SCRATCH/marketplace-state"
reset_calls
if run_sync 2>/dev/null; then
  printf 'duplicate Gaffer marketplace records were accepted\n' >&2
  exit 1
fi
assert_calls 'plugin marketplace list --json'

printf '%s\n' exact >"$SCRATCH/marketplace-state"
reset_calls
if MARKETPLACE_LIST_MODE=malformed run_sync 2>/dev/null; then
  printf 'malformed marketplace-list output was accepted\n' >&2
  exit 1
fi
assert_calls 'plugin marketplace list --json'

reset_calls
if MARKETPLACE_LIST_EXIT=6 run_sync 2>/dev/null; then
  printf 'failed marketplace-list command was ignored\n' >&2
  exit 1
fi
assert_calls 'plugin marketplace list --json'

printf '%s\n' absent >"$SCRATCH/marketplace-state"
reset_calls
if MARKETPLACE_ADD_EXIT=5 run_sync 2>/dev/null; then
  printf 'failed marketplace-add command was ignored\n' >&2
  exit 1
fi
assert_calls \
  'plugin marketplace list --json' \
  "plugin marketplace add $MANAGED_SOURCE --scope user"
printf '%s\n' exact >"$SCRATCH/marketplace-state"

# A supervisor that exits zero without the authenticated child-status record is
# an internal failure, never proof that Claude succeeded.
printf '%s\n' current >"$SCRATCH/plugin-state"
reset_calls
if TIMEOUT_ZERO_EXIT=1 run_sync 2>/dev/null; then
  printf 'missing bounded-child status was accepted as success\n' >&2
  exit 1
fi
assert_no_calls

reset_calls
if LIST_TIMEOUT_SECONDS=0 run_sync 2>/dev/null; then
  printf 'zero Claude probe deadline was accepted\n' >&2
  exit 1
fi
assert_no_calls
reset_calls
if KILL_AFTER_SECONDS=0 run_sync 2>/dev/null; then
  printf 'disabled Claude process-group KILL grace was accepted\n' >&2
  exit 1
fi
assert_no_calls

# Exact state is idempotent; full and Claude's canonical 12-character versions
# both resolve unambiguously to the verified 40-character input revision.
printf '%s\n' current >"$SCRATCH/plugin-state"
reset_calls
: >"$SCRATCH/ps-calls"
fast_start_ns="$(date +%s%N)"
run_sync
fast_elapsed_ms=$((($(date +%s%N) - fast_start_ns) / 1000000))
[ "$fast_elapsed_ms" -lt 1500 ] || {
  printf 'successful bounded probes waited %sms instead of reaping immediately\n' \
    "$fast_elapsed_ms" >&2
  exit 1
}
mapfile -t fast_pgid_calls <"$SCRATCH/ps-calls"
[ "${#fast_pgid_calls[@]}" -eq 4 ]
for pgid_offset in 0 2; do
  read -r timeout_process timeout_group \
    <<<"${fast_pgid_calls[$pgid_offset]}"
  read -r child_process child_group \
    <<<"${fast_pgid_calls[$((pgid_offset + 1))]}"
  [ "$timeout_process" = "$timeout_group" ]
  [ "$child_process" != "$timeout_process" ]
  [ "$child_group" = "$timeout_group" ]
done
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json'
assert_exact_managed_source

printf '%s\n' current-full >"$SCRATCH/plugin-state"
reset_calls
run_sync
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json'

# The bounded-status publication uses portable same-directory rename syntax;
# a BSD-like mv that rejects GNU -T still completes every child handshake.
: >"$SCRATCH/bsd-mv-calls"
export BSD_MV_CALLS="$SCRATCH/bsd-mv-calls"
portable_path="$SCRATCH/bsd-bin:$PATH"
reset_calls
PATH="$portable_path" run_sync
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json'
[ "$(wc -l <"$SCRATCH/bsd-mv-calls")" -eq 4 ]
if grep -Eq '(^| )-T( |$)' "$SCRATCH/bsd-mv-calls"; then
  printf 'bounded child used nonportable mv -T\n' >&2
  exit 1
fi
unset BSD_MV_CALLS

# Sequential exact-revision changes atomically converge all three observable
# identities: managed HEAD, durable intent, and Claude's reported cache.
printf '%s\n' stale >"$SCRATCH/plugin-state"
reset_calls
GAFFER_REV_OVERRIDE="$ALTERNATE_REV" run_sync
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json' \
  'plugin update gaffer@gaffer --scope user' \
  'plugin list --json'
assert_exact_managed_source "$MANAGED_SOURCE" "$ALTERNATE_REV"
[ "$(<"$SCRATCH/plugin-state")" = "exact:$ALTERNATE_REV" ]

printf '%s\n' stale >"$SCRATCH/plugin-state"
reset_calls
run_sync
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json' \
  'plugin update gaffer@gaffer --scope user' \
  'plugin list --json'
assert_exact_managed_source
[ "$(<"$SCRATCH/plugin-state")" = "exact:$VERIFIED_REV" ]

printf '%s\n' stale >"$SCRATCH/plugin-state"
reset_calls
run_sync
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json' \
  'plugin update gaffer@gaffer --scope user' \
  'plugin list --json'
assert_exact_managed_source

# Every supported Claude surface failure is fatal and never falls through to a
# different mutation. Post-update state is also re-read through the CLI.
printf '%s\n' stale >"$SCRATCH/plugin-state"
reset_calls
if UPDATE_EXIT=8 run_sync 2>/dev/null; then
  printf 'sync must surface a failed update without falling through to install\n' >&2
  exit 1
fi
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json' \
  'plugin update gaffer@gaffer --scope user'

printf '%s\n' stale >"$SCRATCH/plugin-state"
reset_calls
if UPDATE_STATE=stale run_sync 2>/dev/null; then
  printf 'sync must verify Claude reports the exact input revision after update\n' >&2
  exit 1
fi
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json' \
  'plugin update gaffer@gaffer --scope user' \
  'plugin list --json'

printf '%s\n' absent >"$SCRATCH/plugin-state"
reset_calls
if INSTALL_EXIT=9 run_sync 2>/dev/null; then
  printf 'sync must surface a failed install\n' >&2
  exit 1
fi
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json' \
  'plugin install gaffer@gaffer --scope user'

printf '%s\n' current >"$SCRATCH/plugin-state"
reset_calls
if LIST_EXIT=7 run_sync 2>/dev/null; then
  printf 'sync must surface a failed initial plugin-list probe\n' >&2
  exit 1
fi
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json'

reset_calls
if LIST_MODE=malformed run_sync 2>/dev/null; then
  printf 'sync must reject malformed plugin-list output\n' >&2
  exit 1
fi
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json'

printf '%s\n' stale >"$SCRATCH/plugin-state"
reset_calls
if LIST_FAIL_ON=2 run_sync 2>/dev/null; then
  printf 'sync must surface a failed post-update plugin-list probe\n' >&2
  exit 1
fi
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json' \
  'plugin update gaffer@gaffer --scope user' \
  'plugin list --json'

# Missing, rewound, and divergent local main refs are irrelevant after the
# exact revision has been selected by the built flake input.
printf '%s\n' current >"$SCRATCH/plugin-state"
"$REAL_GIT" -C "$GAFFER" branch -D main >/dev/null
reset_calls
run_sync
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json'
assert_exact_managed_source

"$REAL_GIT" -C "$GAFFER" branch main "$BASE_REV"
reset_calls
run_sync
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json'
assert_exact_managed_source

DIVERGED_REV="$(
  printf '%s\n' 'diverged local main' |
    "$REAL_GIT" -C "$GAFFER" commit-tree "$BASE_REV^{tree}" -p "$BASE_REV"
)"
"$REAL_GIT" -C "$GAFFER" branch -f main "$DIVERGED_REV"
reset_calls
run_sync
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json'
assert_exact_managed_source

# An unknown existing path and unexpected dirt in our own worktree both fail
# closed without clobbering bytes or invoking Claude.
UNKNOWN_SOURCE="$SCRATCH/state/north/unknown-source"
mkdir -p "$UNKNOWN_SOURCE"
printf '%s\n' 'do not clobber' >"$UNKNOWN_SOURCE/user-file"
reset_calls
if GAFFER_SOURCE_OVERRIDE="$UNKNOWN_SOURCE" run_sync 2>/dev/null; then
  printf 'sync must reject an unknown existing managed-source path\n' >&2
  exit 1
fi
assert_no_calls
grep -q 'do not clobber' "$UNKNOWN_SOURCE/user-file"

printf '%s\n' 'do not clobber either' >"$MANAGED_SOURCE/unexpected"
reset_calls
if run_sync 2>/dev/null; then
  printf 'sync must reject unexpected changes in its managed worktree\n' >&2
  exit 1
fi
assert_no_calls
grep -q 'do not clobber either' "$MANAGED_SOURCE/unexpected"
rm "$MANAGED_SOURCE/unexpected"

# A durable creation intent is published before `git worktree add`. Simulate a
# process dying after Git successfully registers/materializes the worktree but
# before the marker is written: the next invocation verifies the exact
# common-dir/source/revision intent and safely completes ownership with no
# manual cleanup or pointer change.
CRASH_SOURCE="$SCRATCH/state/north/crash-heal-source"
CRASH_LOCK="$SCRATCH/state/north/crash-heal-source.lock"
printf '%s\n' current >"$SCRATCH/plugin-state"
reset_calls
if GIT_CRASH_AFTER_ADD=1 \
   GAFFER_SOURCE_OVERRIDE="$CRASH_SOURCE" \
   GAFFER_LOCK_OVERRIDE="$CRASH_LOCK" \
   run_sync 2>/dev/null; then
  printf 'injected post-worktree-add crash unexpectedly succeeded\n' >&2
  exit 1
fi
assert_no_calls
[ "$("$REAL_GIT" -C "$CRASH_SOURCE" rev-parse HEAD)" = "$VERIFIED_REV" ]
crash_git_dir="$("$REAL_GIT" -C "$CRASH_SOURCE" rev-parse --path-format=absolute --git-dir)"
[ ! -e "$crash_git_dir/north-managed-gaffer-plugin-source" ]
[ -f "$CRASH_SOURCE.intent" ]
reset_calls
GAFFER_SOURCE_OVERRIDE="$CRASH_SOURCE" \
GAFFER_LOCK_OVERRIDE="$CRASH_LOCK" \
  run_sync
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json'
[ "$(<"$crash_git_dir/north-managed-gaffer-plugin-source")" = \
  north-gaffer-plugin-source-v1 ]
"$REAL_GIT" -C "$GAFFER" worktree list --porcelain |
  grep -A4 -F "worktree $CRASH_SOURCE" |
  grep -Fx 'locked north-gaffer-plugin-source-v1' >/dev/null
assert_exact_managed_source "$CRASH_SOURCE" "$VERIFIED_REV"

# A crash after the exact checkout but before intent replacement leaves a
# marker-owned, clean worktree that the next invocation can safely converge.
# A crash injected after the atomic intent rename is equally recoverable: the
# source+intent winner is durable, and only the Claude cache remains to update.
printf '%s\n' "exact:$VERIFIED_REV" >"$SCRATCH/plugin-state"
reset_calls
if GIT_CRASH_AFTER_CHECKOUT=1 \
   GAFFER_REV_OVERRIDE="$ALTERNATE_REV" \
   run_sync 2>/dev/null; then
  printf 'injected post-checkout crash unexpectedly succeeded\n' >&2
  exit 1
fi
assert_no_calls
[ "$("$REAL_GIT" -C "$MANAGED_SOURCE" rev-parse HEAD)" = "$ALTERNATE_REV" ]
[ "$(jq -r '.revision' "$MANAGED_SOURCE.intent")" = "$VERIFIED_REV" ]
[ "$(<"$SCRATCH/plugin-state")" = "exact:$VERIFIED_REV" ]
reset_calls
GAFFER_REV_OVERRIDE="$ALTERNATE_REV" run_sync
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json' \
  'plugin update gaffer@gaffer --scope user' \
  'plugin list --json'
assert_exact_managed_source "$MANAGED_SOURCE" "$ALTERNATE_REV"
[ "$(<"$SCRATCH/plugin-state")" = "exact:$ALTERNATE_REV" ]

reset_calls
if MV_CRASH_AFTER_INTENT_REPLACE=1 run_sync 2>/dev/null; then
  printf 'injected post-intent-replace crash unexpectedly succeeded\n' >&2
  exit 1
fi
assert_no_calls
assert_exact_managed_source
[ "$(<"$SCRATCH/plugin-state")" = "exact:$ALTERNATE_REV" ]
reset_calls
run_sync
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json' \
  'plugin update gaffer@gaffer --scope user' \
  'plugin list --json'
assert_exact_managed_source
[ "$(<"$SCRATCH/plugin-state")" = "exact:$VERIFIED_REV" ]

# Lock acquisition is bounded and occurs before any Claude read/mutation.
SYNC_LOCK="$SCRATCH/state/north/gaffer-plugin-source.lock"
exec {HELD_LOCK_FD}>>"$SYNC_LOCK"
flock -n "$HELD_LOCK_FD"
printf '%s\n' current >"$SCRATCH/plugin-state"
reset_calls
if LOCK_TIMEOUT_SECONDS=0.1 run_sync 2>/dev/null; then
  printf 'sync must fail when its bounded process lock cannot be acquired\n' >&2
  exit 1
fi
assert_no_calls
flock -u "$HELD_LOCK_FD"
exec {HELD_LOCK_FD}>&-

# Tiny JSON probes inherit a hard per-stream file-size limit. A hostile stdout
# or stderr flood fails quickly, stays below the configured cap, and releases
# the process lock without filling temporary storage.
for flood_stream in stdout stderr; do
  reset_calls
  flood_start_ns="$(date +%s%N)"
  if OUTPUT_FLOOD_MODE="$flood_stream" \
     MAX_OUTPUT_KIB=4 \
     LIST_TIMEOUT_SECONDS=0.2 \
     KILL_AFTER_SECONDS=0.1 \
     run_sync >/dev/null 2>&1; then
    printf '%s flood unexpectedly passed the bounded JSON probe\n' \
      "$flood_stream" >&2
    exit 1
  fi
  flood_elapsed_ms=$((($(date +%s%N) - flood_start_ns) / 1000000))
  [ "$flood_elapsed_ms" -lt 1000 ] || {
    printf '%s flood took %sms to stop\n' "$flood_stream" "$flood_elapsed_ms" >&2
    exit 1
  }
  assert_calls 'plugin marketplace list --json'
  exec {AFTER_FLOOD_LOCK_FD}>>"$SYNC_LOCK"
  flock -n "$AFTER_FLOOD_LOCK_FD"
  flock -u "$AFTER_FLOOD_LOCK_FD"
  exec {AFTER_FLOOD_LOCK_FD}>&-
done

# A TERM-resistant Claude descendant cannot survive the deadline or retain the
# sync lock. The group anchor forces timeout's KILL phase even when the direct
# CLI exits on TERM, preventing delayed mutation after this invocation returns.
rm -f "$SCRATCH/resistant-descendant.pid" "$SCRATCH/post-lock-mutation"
printf '%s\n' current >"$SCRATCH/plugin-state"
reset_calls
if RESISTANT_LIST_MODE=1 \
   LIST_TIMEOUT_SECONDS=0.1 \
   KILL_AFTER_SECONDS=0.1 \
   run_sync 2>/dev/null; then
  printf 'TERM-resistant Claude marketplace probe unexpectedly succeeded\n' >&2
  exit 1
fi
assert_calls 'plugin marketplace list --json'
[ -s "$SCRATCH/resistant-descendant.pid" ]
resistant_pid="$(<"$SCRATCH/resistant-descendant.pid")"
exec {AFTER_TIMEOUT_LOCK_FD}>>"$SYNC_LOCK"
flock -n "$AFTER_TIMEOUT_LOCK_FD"
flock -u "$AFTER_TIMEOUT_LOCK_FD"
exec {AFTER_TIMEOUT_LOCK_FD}>&-
sleep 0.6
[ ! -e "$SCRATCH/post-lock-mutation" ]
if kill -0 "$resistant_pid" 2>/dev/null; then
  resistant_state="$(ps -o stat= -p "$resistant_pid" 2>/dev/null | tr -d ' ' || true)"
  case "$resistant_state" in
    Z*|'') ;;
    *)
      printf 'TERM-resistant Claude descendant survived group KILL: %s (%s)\n' \
        "$resistant_pid" "$resistant_state" >&2
      exit 1
      ;;
  esac
fi

# Two activations selecting different exact built revisions serialize the whole
# worktree + Claude transaction. The fake Claude mutation guard would reject an
# overlap; both calls must instead complete and leave cache/source on the same
# last serialized revision.
printf '%s\n' stale >"$SCRATCH/plugin-state"
reset_calls
MUTATION_GUARD="$SCRATCH/active-claude-mutation" \
MUTATION_SLEEP_SECONDS=0.3 \
GAFFER_REV_OVERRIDE="$VERIFIED_REV" \
  run_sync >"$SCRATCH/concurrent-a.out" 2>&1 &
pid_a=$!
MUTATION_GUARD="$SCRATCH/active-claude-mutation" \
MUTATION_SLEEP_SECONDS=0.3 \
GAFFER_REV_OVERRIDE="$ALTERNATE_REV" \
  run_sync >"$SCRATCH/concurrent-b.out" 2>&1 &
pid_b=$!
concurrent_ok=1
wait "$pid_a" || concurrent_ok=0
wait "$pid_b" || concurrent_ok=0
if [ "$concurrent_ok" -ne 1 ]; then
  printf 'concurrent exact-revision sync failed\n' >&2
  sed 's/^/A: /' "$SCRATCH/concurrent-a.out" >&2
  sed 's/^/B: /' "$SCRATCH/concurrent-b.out" >&2
  exit 1
fi
[ ! -e "$SCRATCH/active-claude-mutation" ]
[ "$(grep -c '^plugin update gaffer@gaffer --scope user$' "$SCRATCH/claude-calls")" -eq 2 ]
final_source_revision="$("$REAL_GIT" -C "$MANAGED_SOURCE" rev-parse HEAD)"
final_intent_revision="$(jq -r '.revision' "$MANAGED_SOURCE.intent")"
final_plugin_state="$(<"$SCRATCH/plugin-state")"
[ "$final_plugin_state" = "exact:$final_source_revision" ]
[ "$final_intent_revision" = "$final_source_revision" ]
case "$final_source_revision" in
  "$VERIFIED_REV"|"$ALTERNATE_REV") ;;
  *)
    printf 'concurrent sync left an unknown exact source revision\n' >&2
    exit 1
    ;;
esac
[ "$("$REAL_GIT" -C "$GAFFER" rev-parse HEAD)" = "$FEATURE_REV" ]
grep -q 'dirty feature bytes' "$GAFFER/doctrine.md"
[ -f "$GAFFER/untracked" ]

# The managed source is declared at a stable logical path whose parent is an
# XDG-state symlink into the real repo tree; Git and Claude both report the
# symlink-resolved canonical path. A logical-vs-canonical alias is the SAME
# source, not a foreign conflict: the whole transaction (worktree identity,
# managed lock, marketplace state) must canonicalize both sides. The managed
# source is still created, marked, locked, and compared at the logical path,
# while Claude's canonical marketplace path resolves to it.
mkdir -p "$SCRATCH/canonical-root"
ln -s canonical-root "$SCRATCH/logical-root"
LOGICAL_SOURCE="$SCRATCH/logical-root/north/gaffer-plugin-source"
CANONICAL_SOURCE="$SCRATCH/canonical-root/north/gaffer-plugin-source"
printf '%s\n' current >"$SCRATCH/plugin-state"
printf '%s\n' exact >"$SCRATCH/marketplace-state"
reset_calls
GAFFER_SOURCE_OVERRIDE="$LOGICAL_SOURCE" \
GAFFER_LOCK_OVERRIDE="$SCRATCH/logical-root/north/gaffer-plugin-source.lock" \
FAKE_MARKETPLACE_PATH="$CANONICAL_SOURCE" \
  run_sync
assert_calls \
  'plugin marketplace list --json' \
  'plugin list --json'
assert_exact_managed_source "$LOGICAL_SOURCE"

if grep -Fq 'installed_plugins.json' "$REPO/scripts/claude-gaffer-plugin-sync.sh" ||
   grep -Fq 'plugin uninstall' "$REPO/scripts/claude-gaffer-plugin-sync.sh" ||
   grep -Fq 'plugin marketplace remove' "$REPO/scripts/claude-gaffer-plugin-sync.sh"; then
  printf 'sync must never mutate Claude cache state directly or remove marketplaces/plugins\n' >&2
  exit 1
fi

printf 'ok: exact built Gaffer revision owns a crash-healable source and supported Claude marketplace/update/install reconciliation\n'
