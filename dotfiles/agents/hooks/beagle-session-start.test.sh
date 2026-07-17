#!/usr/bin/env bash
# Hermetic lifecycle/idempotency tests for beagle-session-start.sh.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/beagle-session-start.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/beagle-session-start-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

PROJECT="$SCRATCH/project"
PLAIN="$SCRATCH/plain"
STATE="$SCRATCH/state"
FAKE_BEAGLE="$SCRATCH/beagle"
TRACE="$SCRATCH/revive.trace"
mkdir -p "$PROJECT" "$PLAIN" "$STATE" "$FAKE_BEAGLE/bin" "$SCRATCH/home"
touch "$PROJECT/main.bnix"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >>"$BEAGLE_TEST_TRACE"' \
  'sleep "${BEAGLE_TEST_HOLD:-0.15}"' \
  >"$FAKE_BEAGLE/bin/beagle"
chmod +x "$FAKE_BEAGLE/bin/beagle"

pass=0
fail=0

ok() {
  pass=$((pass + 1))
  printf 'PASS  %s\n' "$1"
}

not_ok() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1" >&2
}

assert_contains() {
  local value="$1" needle="$2" label="$3"
  if [[ "$value" == *"$needle"* ]]; then ok "$label"
  else not_ok "$label (missing: $needle; got: $value)"; fi
}

assert_not_contains() {
  local value="$1" needle="$2" label="$3"
  if [[ "$value" != *"$needle"* ]]; then ok "$label"
  else not_ok "$label (unexpected: $needle; got: $value)"; fi
}

assert_empty() {
  local value="$1" label="$2"
  if [ -z "$value" ]; then ok "$label"
  else not_ok "$label (got: $value)"; fi
}

trace_count() {
  if [ -f "$TRACE" ]; then wc -l <"$TRACE"
  else printf '0\n'; fi
}

wait_for_trace_count() {
  local expected="$1" attempts=0
  while [ "$attempts" -lt 100 ]; do
    [ "$(trace_count)" -ge "$expected" ] && return 0
    sleep 0.02
    attempts=$((attempts + 1))
  done
  return 1
}

wait_for_warm_unlock() {
  local lock attempts=0
  lock="$(find "$STATE" -maxdepth 1 -name 'warm-*.lock' -print -quit)"
  [ -n "$lock" ] || return 1
  while [ "$attempts" -lt 100 ]; do
    if flock -n "$lock" true 2>/dev/null; then return 0; fi
    sleep 0.02
    attempts=$((attempts + 1))
  done
  return 1
}

event_json() {
  python3 -c '
import json
import sys
print(json.dumps({
    "hook_event_name": "SessionStart",
    "session_id": sys.argv[1],
    "source": sys.argv[2],
    "cwd": sys.argv[3],
}))
' "$1" "$2" "$3"
}

run_hook_raw() {
  local sid="$1" source="$2" cwd="$3"
  event_json "$sid" "$source" "$cwd" |
    env -u CLAUDE_PROJECT_DIR -u CLAUDE_NO_AUTHORING_HOOKS \
      HOME="$SCRATCH/home" \
      BEAGLE_PATH="$FAKE_BEAGLE" \
      BEAGLE_SESSION_STATE_DIR="$STATE" \
      BEAGLE_TEST_TRACE="$TRACE" \
      BEAGLE_TEST_HOLD="${BEAGLE_TEST_HOLD:-0.15}" \
      AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
      "$HOOK"
}

context_of() {
  jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$1"
}

first="$(run_hook_raw session-a startup "$PROJECT")"
if jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' <<<"$first" >/dev/null 2>&1; then
  ok 'startup emits valid SessionStart JSON'
else
  not_ok "startup emits valid SessionStart JSON (got: $first)"
fi
first_ctx="$(context_of "$first")"
assert_contains "$first_ctx" 'Beagle authoring is active.' 'startup injects the full handshake'
assert_contains "$first_ctx" 'beagle doctor --deep' 'startup uses the canonical doctor command'
assert_contains "$first_ctx" 'background `beagle doctor --revive --quiet` check was started' \
  'only the warm-lock winner announces a background check'
if wait_for_trace_count 1; then ok 'startup launches one non-blocking revive'
else not_ok 'startup launches one non-blocking revive'; fi

resume="$(run_hook_raw session-a resume "$PROJECT")"
assert_empty "$resume" 'resume in the same session is silent'
if [ "$(trace_count)" -eq 1 ]; then ok 'resume does not launch another revive'
else not_ok "resume does not launch another revive (count=$(trace_count))"; fi

second_session="$(run_hook_raw session-b startup "$PROJECT")"
second_ctx="$(context_of "$second_session")"
assert_contains "$second_ctx" 'Beagle authoring is active.' 'a new session receives the full handshake'
assert_not_contains "$second_ctx" 'background `beagle doctor --revive --quiet` check was started' \
  'a throttled session does not claim the daemon is warming'
if [ "$(trace_count)" -eq 1 ]; then ok 'per-checkout throttle spans session ids'
else not_ok "per-checkout throttle spans session ids (count=$(trace_count))"; fi

first_resume="$(run_hook_raw session-resume-first resume "$PROJECT")"
first_resume_ctx="$(context_of "$first_resume")"
assert_contains "$first_resume_ctx" 'Beagle authoring is active.' \
  'a first-seen resume restores context after process/runtime-state loss'
repeat_resume="$(run_hook_raw session-resume-first resume "$PROJECT")"
assert_empty "$repeat_resume" 'a repeated resume remains deduplicated'

compact="$(run_hook_raw session-a compact "$PROJECT")"
compact_ctx="$(context_of "$compact")"
assert_contains "$compact_ctx" 'after compaction' 'compact restores concise authoring context'
assert_not_contains "$compact_ctx" 'Beagle authoring is active.' 'compact does not repeat the full handshake'
if [ "$(trace_count)" -eq 1 ]; then ok 'compact remains inside the warm throttle'
else not_ok "compact remains inside the warm throttle (count=$(trace_count))"; fi

clear="$(run_hook_raw session-a clear "$PROJECT")"
clear_ctx="$(context_of "$clear")"
assert_contains "$clear_ctx" 'Beagle authoring is active.' 'clear restores the full handshake'
assert_not_contains "$clear_ctx" 'background `beagle doctor --revive --quiet` check was started' \
  'clear does not misreport a throttled revive'

if wait_for_warm_unlock; then ok 'detached doctor releases the advisory lock'
else not_ok 'detached doctor releases the advisory lock'; fi

# With the cooldown disabled, simultaneous SessionStart events still admit one
# doctor because the detached child inherits the advisory lock.
BEAGLE_TEST_HOLD=0.3 BEAGLE_SESSION_WARM_TTL_SECONDS=0 \
  run_hook_raw session-race-a startup "$PROJECT" >"$SCRATCH/race-a.out" &
race_a=$!
BEAGLE_TEST_HOLD=0.3 BEAGLE_SESSION_WARM_TTL_SECONDS=0 \
  run_hook_raw session-race-b startup "$PROJECT" >"$SCRATCH/race-b.out" &
race_b=$!
wait "$race_a" "$race_b"
if wait_for_trace_count 2 && [ "$(trace_count)" -eq 2 ]; then
  ok 'simultaneous starts launch exactly one additional revive'
else
  not_ok "simultaneous starts launch exactly one additional revive (count=$(trace_count))"
fi
race_warm_count=0
for output in "$SCRATCH/race-a.out" "$SCRATCH/race-b.out"; do
  if grep -Fq 'background `beagle doctor --revive --quiet` check was started' "$output"; then
    race_warm_count=$((race_warm_count + 1))
  fi
done
if [ "$race_warm_count" -eq 1 ]; then ok 'exactly one racing hook reports the won warm launch'
else not_ok "exactly one racing hook reports the won warm launch (count=$race_warm_count)"; fi

plain="$(run_hook_raw session-plain startup "$PLAIN")"
assert_empty "$plain" 'a non-Beagle checkout is silent'
touch "$PLAIN/late.bnix"
late_beagle="$(run_hook_raw session-plain resume "$PLAIN")"
late_beagle_ctx="$(context_of "$late_beagle")"
assert_contains "$late_beagle_ctx" 'Beagle authoring is active.' \
  'a silent non-Beagle start does not consume the later Beagle context claim'
rm -f "$PLAIN/late.bnix"

disabled_payload="$(event_json session-disabled startup "$PROJECT")"
disabled="$(
  printf '%s' "$disabled_payload" |
    env HOME="$SCRATCH/home" \
      CLAUDE_NO_AUTHORING_HOOKS=1 \
      BEAGLE_PATH="$FAKE_BEAGLE" \
      BEAGLE_SESSION_STATE_DIR="$STATE" \
      BEAGLE_TEST_TRACE="$TRACE" \
      AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
      "$HOOK"
)"
assert_empty "$disabled" 'the authoring kill-switch is silent'

invalid="$(
  cd "$PROJECT" || exit 1
  printf 'not-json' |
    env -u CLAUDE_PROJECT_DIR -u CLAUDE_NO_AUTHORING_HOOKS \
      HOME="$SCRATCH/home" \
      BEAGLE_PATH="$FAKE_BEAGLE" \
      BEAGLE_SESSION_STATE_DIR="$STATE" \
      BEAGLE_TEST_TRACE="$TRACE" \
      AUTHORING_KILLSWITCH_STATE="$SCRATCH/killswitch.state" \
      "$HOOK"
)"
invalid_ctx="$(context_of "$invalid")"
assert_contains "$invalid_ctx" 'Beagle authoring is active.' 'invalid stdin falls back safely to process cwd'

if wait_for_warm_unlock; then :; fi
printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
