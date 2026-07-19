#!/usr/bin/env bash
# Hermetic transport tests for racket-build-guard.sh.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/racket-build-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/racket-build-guard-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

PROJECT="$SCRATCH/project"
BIN="$SCRATCH/bin"
HOME_DIR="$SCRATCH/home"
STATE="$SCRATCH/harness.conf"
SOURCE="$PROJECT/main.rkt"
PIN_CURRENT="$PROJECT/racket-current"
PIN_OLD="$PROJECT/racket-old"
PIN_HANG="$PROJECT/racket-hang"
HANG_PID="$SCRATCH/hung-racket.pid"
mkdir -p "$PROJECT/bin" "$PROJECT/compiled" "$BIN" "$HOME_DIR"
touch "$PROJECT/flake.nix" "$SOURCE"

make_fake_racket() {
  local path="$1" version="$2"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "printf '%s\\n' 'Welcome to Racket ${version}'" \
    >"$path"
  chmod +x "$path"
}

select_pin() {
  printf 'export RACKET=%q\n' "$1" >"$PROJECT/bin/_beagle-racket"
}

event_json() {
  python3 -c '
import json
import sys

print(json.dumps({
    "hook_event_name": "PostToolUse",
    "tool_input": {"file_path": sys.argv[1]},
}))
' "$1"
}

patch_event_json() {
  local target="${1:-main.rkt}" body="${2:-+new}"
  python3 -c '
import json
import sys

patch = "\n".join([
    "*** Begin Patch",
    "*** Update File: " + sys.argv[1],
    "@@",
    "-old",
    sys.argv[2],
    "*** End Patch",
])
print(json.dumps({
    "hook_event_name": "PostToolUse",
    "tool_name": "apply_patch",
    "tool_input": {"command": patch},
    "cwd": sys.argv[3],
}))
' "$target" "$body" "$PROJECT"
}

run_hook() {
  local guards="$1" payload="${2:-}"
  [ -n "$payload" ] || payload="$(event_json "$SOURCE")"
  env PATH="$BIN:$PATH" \
    HOME="$HOME_DIR" \
    AGENT_NO_AUTHORING_HOOKS="$guards" \
    NORTH_HARNESS_STATE="$STATE" \
    "$HOOK" >"$SCRATCH/stdout" 2>"$SCRATCH/stderr" <<<"$payload"
  RUN_STATUS=$?
  RUN_STDOUT="$(<"$SCRATCH/stdout")"
  RUN_STDERR="$(<"$SCRATCH/stderr")"
}

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

assert_empty() {
  local value="$1" label="$2"
  if [ -z "$value" ]; then ok "$label"
  else not_ok "$label (got: $value)"; fi
}

make_fake_racket "$BIN/racket" v9.2
make_fake_racket "$PIN_CURRENT" v9.2
make_fake_racket "$PIN_OLD" v9.1
printf '%s\n' \
  '#!/usr/bin/env bash' \
  "printf '%s' \"\$\$\" >'$HANG_PID'" \
  'exec sleep 30' \
  >"$PIN_HANG"
chmod +x "$PIN_HANG"

select_pin "$PIN_CURRENT"
run_hook 0
if [ "$RUN_STATUS" -eq 0 ]; then ok 'clean Racket edit exits 0'
else not_ok "clean Racket edit exits 0 (status=$RUN_STATUS)"; fi
assert_empty "$RUN_STDOUT" 'clean Racket edit emits no hook payload'
assert_empty "$RUN_STDERR" 'clean Racket edit emits no stderr'

select_pin "$PIN_OLD"
touch -t 202607180100 "$PROJECT/compiled/main_rkt.zo"
touch -t 202607180200 "$SOURCE"
run_hook 0
if [ "$RUN_STATUS" -eq 0 ]; then ok 'diagnostic Racket edit exits 0'
else not_ok "diagnostic Racket edit exits 0 (status=$RUN_STATUS)"; fi
assert_empty "$RUN_STDERR" 'diagnostic transport emits no hook-failure stderr'
if jq -e '
  .hookSpecificOutput.hookEventName == "PostToolUse"
  and (.hookSpecificOutput.additionalContext | type == "string")
' <<<"$RUN_STDOUT" >/dev/null 2>&1; then
  ok 'diagnostic transport emits valid PostToolUse JSON'
else
  not_ok "diagnostic transport emits valid PostToolUse JSON (got: $RUN_STDOUT)"
fi
context="$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$RUN_STDOUT")"
if [[ "$context" == *'Racket version mismatch'* ]]; then
  ok 'structured context preserves version-mismatch guidance'
else
  not_ok 'structured context preserves version-mismatch guidance'
fi
if [[ "$context" == *'Stale bytecode'* ]]; then
  ok 'structured context preserves stale-bytecode guidance'
else
  not_ok 'structured context preserves stale-bytecode guidance'
fi

run_hook 0 "$(patch_event_json)"
if jq -e '
  .hookSpecificOutput.hookEventName == "PostToolUse"
  and (.hookSpecificOutput.additionalContext | contains("Stale bytecode"))
' <<<"$RUN_STDOUT" >/dev/null 2>&1; then
  ok 'Codex canonical apply_patch target receives Racket diagnostics'
else
  not_ok "Codex canonical apply_patch target receives Racket diagnostics (got: $RUN_STDOUT)"
fi

touch "$PROJECT/notes.txt"
run_hook 0 "$(patch_event_json notes.txt '+# main.rkt is prose, not a target')"
assert_empty "$RUN_STDOUT" 'apply_patch body text cannot impersonate a .rkt target'
assert_empty "$RUN_STDERR" 'apply_patch non-target decoy emits no stderr'

select_pin "$PIN_HANG"
started_ms="$(date +%s%3N)"
run_hook 0
elapsed_ms=$(( $(date +%s%3N) - started_ms ))
if [ "$RUN_STATUS" -eq 0 ]; then ok 'hung pin probe exits 0'
else not_ok "hung pin probe exits 0 (status=$RUN_STATUS)"; fi
assert_empty "$RUN_STDOUT" 'hung pin probe emits no partial JSON'
assert_empty "$RUN_STDERR" 'hung pin probe emits no hook-failure stderr'
if [ "$elapsed_ms" -ge 3500 ] && [ "$elapsed_ms" -lt 6000 ]; then
  ok "hung pin probe respects inner deadline (${elapsed_ms}ms)"
else
  not_ok "hung pin probe respects inner deadline (${elapsed_ms}ms)"
fi
if [ -s "$HANG_PID" ]; then
  hung_pid="$(<"$HANG_PID")"
  if kill -0 "$hung_pid" 2>/dev/null; then
    not_ok "hung pin child is not stranded (pid $hung_pid survived)"
    kill -9 "$hung_pid" 2>/dev/null || true
  else
    ok 'hung pin child is not stranded'
  fi
else
  not_ok 'hung pin probe reached the injected stall'
fi

run_hook 1
if [ "$RUN_STATUS" -eq 0 ]; then ok 'killswitch remains a clean no-op'
else not_ok "killswitch remains a clean no-op (status=$RUN_STATUS)"; fi
assert_empty "$RUN_STDOUT" 'killswitch suppresses structured context'
assert_empty "$RUN_STDERR" 'killswitch suppresses stderr'

printf '\n%d/%d passed\n' "$pass" "$((pass + fail))"
[ "$fail" -eq 0 ]
