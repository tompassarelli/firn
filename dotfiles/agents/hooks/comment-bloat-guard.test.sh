#!/usr/bin/env bash
# Fixture matrix for the comment-bloat ADVISORY guard. This guard must NEVER
# deny — every assertion below checks that the decision is never "deny", in
# addition to whether the advisory context fires.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/comment-bloat-guard.sh"

pass=0 fail=0

# build_input TOOL_NAME FILE_PATH PY_KWARGS_JSON
# PY_KWARGS_JSON is a JSON object merged into tool_input (new_string / content
# / edits), so one helper covers all three tool shapes.
build_input() {
  python3 -c '
import json, sys
tool_name, file_path, extra_json = sys.argv[1], sys.argv[2], sys.argv[3]
extra = json.loads(extra_json)
ti = {"file_path": file_path}
ti.update(extra)
print(json.dumps({"tool_name": tool_name, "tool_input": ti}))
' "$1" "$2" "$3"
}

# run EXPECT_TRIGGER DESC TOOL_NAME FILE_PATH EXTRA_JSON [ENV...]
# EXPECT_TRIGGER: trigger = additionalContext present; silent = no stdout.
run() {
  local expect="$1" desc="$2" tool="$3" fp="$4" extra="$5"; shift 5
  local input out decision context ok=0
  input="$(build_input "$tool" "$fp" "$extra")"
  out="$(printf '%s' "$input" | env -u AGENT_NO_AUTHORING_HOOKS \
    AGENT_NO_AUTHORING_HOOKS=0 "$@" "$HOOK" 2>&1)"
  decision="$(python3 -c '
import json, sys
try:
    d = json.loads(sys.argv[1] or "null")
except Exception:
    print("malformed"); raise SystemExit
print((d or {}).get("hookSpecificOutput", {}).get("permissionDecision", "silent"))
' "${out:-}")"
  context="$(python3 -c '
import json, sys
try:
    d = json.loads(sys.argv[1] or "null")
except Exception:
    print(""); raise SystemExit
print((d or {}).get("hookSpecificOutput", {}).get("additionalContext", ""))
' "${out:-}")"
  # Invariant across EVERY fixture: never a deny.
  if [ "$decision" = deny ]; then
    fail=$((fail + 1))
    printf 'FAIL  %-8s  %s\n      DENY EMITTED (advisory guard must never deny) out=%s\n' "$expect" "$desc" "$out"
    return
  fi
  case "$expect" in
    trigger) [ "$decision" = allow ] && [ -n "$context" ] && ok=1 ;;
    silent)  [ -z "$out" ] && ok=1 ;;
  esac
  if [ "$ok" = 1 ]; then
    pass=$((pass + 1)); printf 'PASS  %-8s  %s\n' "$expect" "$desc"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-8s  %s\n      decision=%s context=%s out=%s\n' "$expect" "$desc" "$decision" "$context" "$out"
  fi
}

nlines() {
  # Join args with real newlines for a python string literal built via json.
  python3 -c 'import json,sys; print(json.dumps("\n".join(sys.argv[1:])))' "$@"
}

echo '== bloat / rot triggers =='
NARR="$(nlines \
  '// Fixed on 2026-07-14 after chasing a race for two days.' \
  '// Observed the counter jump from 3 to 11 under load.' \
  '// Root cause: unlocked increment in the hot path.' \
  '// Tried mutex first, too slow (added 40ms).' \
  '// Then tried atomic, worked, latency dropped to 2ms.' \
  '// This matches the incident from INC-4821.' \
  '// See also PR #221 for the earlier attempt.' \
  '// Discussed with the team on 2026-07-15.' \
  '// Verified with a 10k-iteration stress test.' \
  '// Do not revert without re-running that test.' \
  '// Consider this line load-bearing for the fix.' \
  '// Timing budget stays under 5ms per call.' \
  'func doWork() {}')"
run trigger '12-line dated narrative comment (Edit new_string)' Edit /tmp/foo.go \
  "{\"old_string\": \"func doWork() {}\", \"new_string\": $NARR}"

ROT="$(nlines '// Observed on 2026-07-14, latency was 5ms.' 'x = 1')"
run trigger '1-line rot-signature comment (Observed + date + ms)' Edit /tmp/foo.go \
  "{\"old_string\": \"x\", \"new_string\": $ROT}"

WRITE_NARR="$(nlines \
  '# Added this loop 2026-06-01 after a long debugging session.' \
  '# Observed it fixed the flaky test in CI.' \
  '# Runtime was 800ms before, 12ms after.' \
  '# Do not touch without re-reading the incident thread.' \
  'x = 1')"
run trigger 'Write content narrative block' Write /tmp/foo.py \
  "{\"content\": $WRITE_NARR}"

MULTI_NARR="$(nlines \
  ';; Circled back on 2026-05-05 to revisit this decision.' \
  ';; Observed the earlier approach caused a stall.' \
  ';; Benchmarked at 300ms per call, too slow.' \
  ';; Switched approach, now 4ms per call.' \
  '(define x 1)')"
run trigger 'MultiEdit edits[].new_string narrative block' MultiEdit /tmp/foo.rkt \
  "{\"edits\": [{\"old_string\": \"(define x 1)\", \"new_string\": $MULTI_NARR}]}"

echo '== non-triggers =='
CONSTRAINT="$(nlines \
  '// Invariant: writers hold LOCK before touching this counter.' \
  '// Never call this from an interrupt context.' \
  'counter++;')"
run silent '2-line constraint comment' Edit /tmp/foo.go \
  "{\"old_string\": \"counter++;\", \"new_string\": $CONSTRAINT}"

MD="$(nlines '## header' '## header' '## header' '## header' 'some line')"
run silent '.md edit is skipped entirely' Edit /tmp/foo.md \
  "{\"old_string\": \"x\", \"new_string\": $MD}"

SPDX="$(nlines \
  '// SPDX-License-Identifier: MIT' \
  '// Copyright 2020 Foo Corp' \
  '// this is a license header block that is quite long' \
  '// and continues for a while just like real headers do' \
  'func f() {}')"
run silent 'SPDX/Copyright header is exempt' Edit /tmp/foo.go \
  "{\"old_string\": \"x\", \"new_string\": $SPDX}"

GEN="$(nlines '// GENERATED — do not edit by hand.' '// GENERATED from schema.proto.' '// GENERATED at build time.' '// GENERATED, see build.sh.' 'func g() {}')"
run silent 'GENERATED-marked block is exempt' Edit /tmp/foo.go \
  "{\"old_string\": \"x\", \"new_string\": $GEN}"

JSONF="$(nlines '// one' '// two' '// three' '// four' 'x')"
run silent '.json edit is skipped entirely' Edit /tmp/foo.json \
  "{\"old_string\": \"x\", \"new_string\": $JSONF}"

TSVF="$(nlines '# one' '# two' '# three' '# four')"
run silent '.tsv edit is skipped entirely' Edit /tmp/foo.tsv \
  "{\"old_string\": \"x\", \"new_string\": $TSVF}"

LOCKF="$(nlines '# one' '# two' '# three' '# four')"
run silent '.lock edit is skipped entirely' Edit /tmp/foo.lock \
  "{\"old_string\": \"x\", \"new_string\": $LOCKF}"

NONCOMMENT="$(nlines 'this is a made-up narrative-ish string with a date 2026-07-14' 'not_a_comment_line();')"
run silent 'non-comment prose (not comment-prefixed) is ignored' Edit /tmp/foo.go \
  "{\"old_string\": \"x\", \"new_string\": $NONCOMMENT}"

echo '== other tool / non-mutation calls are ignored =='
run silent 'Read tool call is ignored' Read /tmp/foo.go '{}'
run silent 'Bash tool call is ignored' Bash /tmp/foo.go '{"command": "echo hi"}'

echo '== kill-switch =='
run silent 'guards off via env still never denies/never advises' Edit /tmp/foo.go \
  "{\"old_string\": \"func doWork() {}\", \"new_string\": $NARR}" AGENT_NO_AUTHORING_HOOKS=1

echo
printf '== result: %s passed, %s failed ==\n' "$pass" "$fail"
[ "$fail" = 0 ]
