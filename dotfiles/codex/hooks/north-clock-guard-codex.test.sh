#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
AGENT_PROFILE="${AGENT_CONFIG_NORTH_PROFILE:-$HOME/code/north/main/profiles/tom}"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/north-clock-codex-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
export XDG_STATE_HOME="$SCRATCH/state"
TEST_PYTHON="$(readlink -f "$(command -v python3)")"
HOOKS="$SCRATCH/hooks"
mkdir -p "$HOOKS/lib" "$HOOKS/runtime"
for dependency in bash cat env git mktemp python3 rm timeout; do
  resolved="$(readlink -f "$(command -v "$dependency")")"
  ln -s "$resolved" "$HOOKS/runtime/$dependency"
done
cp "$HERE/north-clock-guard-codex" "$HOOKS/north-clock-guard-codex"
cp "$AGENT_PROFILE/hooks/lib/authoring-killswitch.sh" \
  "$HOOKS/lib/authoring-killswitch.sh"
cp "$AGENT_PROFILE/hooks/lib/harness-dial.sh" \
  "$HOOKS/lib/harness-dial.sh"
chmod +x "$HOOKS/north-clock-guard-codex"

cat >"$HOOKS/north-clock-guard.py" <<'STUB'
import os
import signal
import subprocess
import sys
import time

sys.stdin.buffer.read()
mode = os.environ.get("CLOCK_STUB_MODE", "")
outputs = {
    "allow": '{"northClockGuard":"allow"}\n',
    "na": '{"northClockGuard":"not-applicable"}\n',
    "deny": '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"clock required"}}\n',
    "malformed": "{not-json\n",
    "two-lines": '{"northClockGuard":"allow"}\n{"northClockGuard":"allow"}\n',
    "extra": '{"northClockGuard":"allow","extra":true}\n',
    "duplicate-key": '{"northClockGuard":"allow","northClockGuard":"allow"}\n',
}
if mode in outputs:
    sys.stdout.write(outputs[mode])
elif mode == "empty":
    pass
elif mode == "nonzero":
    raise SystemExit(7)
elif mode == "hang":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    subprocess.Popen(
        [
            sys.executable,
            "-c",
            (
                "import os,signal,time;"
                "signal.signal(signal.SIGTERM,signal.SIG_IGN);"
                "time.sleep(4);"
                "open(os.environ['CLOCK_STUB_LATE_FILE'],'w').write('late')"
            ),
        ],
        env=os.environ,
    )
    while True:
        time.sleep(1)
elif mode == "flood":
    while True:
        sys.stdout.write("0" * 800 + "\n")
else:
    raise SystemExit(9)
STUB

NOOP='{"hookSpecificOutput":{"hookEventName":"PreToolUse"}}'
UNAVAILABLE='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"billable_clock_guard_unavailable"}}'
VALID_DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"clock required"}}'
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"true"},"cwd":"/tmp"}'
STATE="$SCRATCH/harness.conf"
printf '%s\n' 'guards=on' >"$STATE"
pass=0
fail=0

invoke() {
  local mode="$1"
  shift
  printf '%s' "$PAYLOAD" | env -u AGENT_NO_AUTHORING_HOOKS \
    -u CLAUDE_NO_AUTHORING_HOOKS CLOCK_STUB_MODE="$mode" \
    NORTH_HARNESS_STATE="$STATE" "$@" \
    "$HOOKS/runtime/env" -u BASH_ENV -u ENV \
      "$HOOKS/runtime/bash" "$HOOKS/north-clock-guard-codex"
}

expect() {
  local description="$1" expected="$2"
  shift 2
  local output
  output="$("$@")"
  if [ "$output" = "$expected" ]; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$description"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n      expected=%s\n      actual=%s\n' \
      "$description" "$expected" "$output"
  fi
}

expect 'allow attestation becomes protocol-valid no-op' "$NOOP" invoke allow env
expect 'not-applicable attestation becomes protocol-valid no-op' "$NOOP" invoke na env
expect 'exact valid deny passes through' "$VALID_DENY" invoke deny env
expect 'empty core output fails closed' "$UNAVAILABLE" invoke empty env
expect 'malformed core output fails closed' "$UNAVAILABLE" invoke malformed env
expect 'multiple JSON lines fail closed' "$UNAVAILABLE" invoke two-lines env
expect 'extra marker fields fail closed' "$UNAVAILABLE" invoke extra env
expect 'duplicate JSON keys fail closed' "$UNAVAILABLE" invoke duplicate-key env
expect 'nonzero core exit fails closed' "$UNAVAILABLE" invoke nonzero env
expect 'output flood is capped and fails closed' "$UNAVAILABLE" invoke flood env

shadow_bin="$SCRATCH/shadow-bin"
mkdir -p "$shadow_bin"
for dependency in bash cat env git mktemp python3 rm timeout; do
  printf '%s\n' '#!/bin/sh' 'printf '\''forged\n'\''' >"$shadow_bin/$dependency"
  chmod +x "$shadow_bin/$dependency"
done
expect 'ambient PATH helpers cannot forge adapter admission' "$VALID_DENY" \
  invoke deny env PATH="$shadow_bin"

expect 'provider-neutral env bypass is an explicit no-op' "$NOOP" \
  invoke nonzero env AGENT_NO_AUTHORING_HOOKS=1
printf '%s\n' 'guards=off' >"$SCRATCH/harness-off.conf"
drain_probe() {
  local mode="$1" expected="$2" result
  result="$("$TEST_PYTHON" - \
    "$HOOKS/runtime/env" "$HOOKS/runtime/bash" \
    "$HOOKS/north-clock-guard-codex" "$STATE" \
    "$SCRATCH/harness-off.conf" "$mode" "$expected" <<'PY'
import json
import os
import subprocess
import sys
import time

env_bin, bash_bin, adapter, live_state, off_state, mode, expected = sys.argv[1:]
env = os.environ.copy()
env.pop("AGENT_NO_AUTHORING_HOOKS", None)
env.pop("CLAUDE_NO_AUTHORING_HOOKS", None)
env.update({
    "CLOCK_STUB_MODE": mode if mode in {"allow", "deny", "malformed"} else "nonzero",
})
if mode == "explicit":
    env["AGENT_NO_AUTHORING_HOOKS"] = "1"
    env["NORTH_HARNESS_STATE"] = live_state
elif mode == "persistent":
    env["NORTH_HARNESS_STATE"] = off_state
else:
    env["NORTH_HARNESS_STATE"] = live_state
payload = json.dumps({
    "tool_name": "Bash",
    "tool_input": {"command": "true", "padding": "x" * (512 * 1024)},
    "cwd": "/tmp",
}).encode()
process = subprocess.Popen(
    [env_bin, "-u", "BASH_ENV", "-u", "ENV", bash_bin, adapter],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    env=env,
)
broken = False
assert process.stdin is not None
for offset in range(0, len(payload), 8192):
    try:
        process.stdin.write(payload[offset : offset + 8192])
        process.stdin.flush()
    except BrokenPipeError:
        broken = True
        break
    if mode == "input-timeout" and offset == 0:
        time.sleep(1.2)
    else:
        time.sleep(0.002)
try:
    process.stdin.close()
except BrokenPipeError:
    broken = True
assert process.stdout is not None
assert process.stderr is not None
stdout = process.stdout.read().decode().strip()
stderr = process.stderr.read().decode().strip()
try:
    status = process.wait(timeout=5)
except subprocess.TimeoutExpired:
    process.kill()
    status = process.wait()
    broken = True
if broken or status != 0 or stdout != expected or stderr:
    print("DRAIN_FAILED")
else:
    print(stdout)
PY
)" || result=DRAIN_FAILED
  printf '%s\n' "$result"
}
expect 'env bypass drains a delayed large hook envelope before no-op' "$NOOP" \
  drain_probe explicit "$NOOP"
expect 'persistent bypass drains a delayed large hook envelope before no-op' "$NOOP" \
  drain_probe persistent "$NOOP"
expect 'allow drains a delayed larger-than-pipe envelope before no-op' "$NOOP" \
  drain_probe allow "$NOOP"
expect 'deny drains a delayed larger-than-pipe envelope before protocol output' \
  "$VALID_DENY" drain_probe deny "$VALID_DENY"
expect 'malformed core output follows a drained larger-than-pipe envelope' \
  "$UNAVAILABLE" drain_probe malformed "$UNAVAILABLE"
expect 'input-spool timeout drains the remaining delayed envelope before deny' \
  "$UNAVAILABLE" drain_probe input-timeout "$UNAVAILABLE"
printf '%s\n' 'guards=off' >"$STATE"
expect 'persistent bypass is an explicit no-op' "$NOOP" invoke nonzero env
expect 'force-live overrides persistent bypass' "$NOOP" \
  invoke allow env AGENT_NO_AUTHORING_HOOKS=0
printf '%s\n' 'guards=on' >"$STATE"

mv "$HOOKS/north-clock-guard.py" "$HOOKS/north-clock-guard.py.missing"
expect 'missing core drains delayed larger-than-pipe stdin and fails closed' \
  "$UNAVAILABLE" drain_probe missing-core "$UNAVAILABLE"
mv "$HOOKS/north-clock-guard.py.missing" "$HOOKS/north-clock-guard.py"

mv "$HOOKS/runtime/python3" "$HOOKS/runtime/python3.missing"
expect 'missing pinned runtime drains delayed larger-than-pipe stdin and fails closed' \
  "$UNAVAILABLE" drain_probe missing-runtime "$UNAVAILABLE"
mv "$HOOKS/runtime/python3.missing" "$HOOKS/runtime/python3"

mv "$HOOKS/runtime/mktemp" "$HOOKS/runtime/mktemp.real"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$HOOKS/runtime/mktemp"
chmod +x "$HOOKS/runtime/mktemp"
expect 'mktemp preflight failure drains delayed larger-than-pipe stdin and denies' \
  "$UNAVAILABLE" drain_probe mktemp-failure "$UNAVAILABLE"
mv -f "$HOOKS/runtime/mktemp.real" "$HOOKS/runtime/mktemp"

LATE="$SCRATCH/late"
expect 'timeout with TERM-ignoring descendant fails closed' "$UNAVAILABLE" \
  invoke hang env CLOCK_STUB_LATE_FILE="$LATE"
sleep 1.2
if [ ! -e "$LATE" ]; then
  pass=$((pass + 1))
  printf 'PASS  timeout reaps the descendant process group\n'
else
  fail=$((fail + 1))
  printf 'FAIL  timeout descendant survived and wrote %s\n' "$LATE"
fi

cp "$AGENT_PROFILE/hooks/north-clock-guard.py" \
  "$HOOKS/north-clock-guard.py"
detached_matrix_command=''
IFS= read -r -d '' detached_matrix_command <<'COMMAND' || true
set -u -o pipefail
snapshot_verify_root=$(mktemp -d /tmp/north-snapshot-detached.XXXXXX)
trap 'rm -rf "${snapshot_verify_root:?}"' EXIT
mkdir -p "$snapshot_verify_root/north" "$snapshot_verify_root/fram"
git archive f3174bb | tar -x -C "$snapshot_verify_root/north"
fram_rev=7f5bd88cc2cbfd3b74947eb205add75e76cc57bb
fram_tree=$(git -C /home/tom/code/fram rev-parse "$fram_rev^{tree}")
git -C /home/tom/code/fram archive "$fram_rev" | tar -x -C "$snapshot_verify_root/fram"
(
  FRAM_OUT="$snapshot_verify_root/fram/out" bb -cp "$snapshot_verify_root/fram/out" "$snapshot_verify_root/north/cli/tests/snapshot-test.clj"
) >"$snapshot_verify_root/snapshot-owner.log" 2>&1 &
p1=$!
(
  FRAM_PATH="$snapshot_verify_root/fram" FRAM_TEST_REV="$fram_rev" FRAM_TEST_TREE="$fram_tree" bash "$snapshot_verify_root/north/cli/tests/snapshot-cli-test.sh"
) >"$snapshot_verify_root/snapshot-cli.log" 2>&1 &
p2=$!
(
  bb "$snapshot_verify_root/north/cli/tests/pred-cli-test.clj"
) >"$snapshot_verify_root/pred.log" 2>&1 &
p3=$!
(
  bb "$snapshot_verify_root/north/cli/tests/pred-cli-lint-test.clj"
) >"$snapshot_verify_root/pred-lint.log" 2>&1 &
p4=$!
(
  FRAM_PATH="$snapshot_verify_root/fram" bb -cp "$snapshot_verify_root/fram/out" "$snapshot_verify_root/north/cli/tests/schema-migrate-integration-test.clj"
) >"$snapshot_verify_root/schema-integration.log" 2>&1 &
p5=$!
(
  FRAM_PATH="$snapshot_verify_root/fram" bash "$snapshot_verify_root/north/cli/tests/corpus-transaction-integration-test.sh"
) >"$snapshot_verify_root/corpus-integration.log" 2>&1 &
p6=$!
names=(snapshot-owner snapshot-cli pred pred-lint schema-integration corpus-integration)
pids=("$p1" "$p2" "$p3" "$p4" "$p5" "$p6")
logs=(snapshot-owner.log snapshot-cli.log pred.log pred-lint.log schema-integration.log corpus-integration.log)
status=0
for i in "${!names[@]}"; do
  if wait "${pids[$i]}"; then
    printf '%s: PASS\n' "${names[$i]}"
    tail -n 2 "$snapshot_verify_root/${logs[$i]}"
  else
    status=1
    printf '%s: FAIL\n' "${names[$i]}"
    sed -n '1,240p' "$snapshot_verify_root/${logs[$i]}"
  fi
done
exit "$status"
COMMAND

invoke_real_core() {
  local command="$1"
  "$TEST_PYTHON" - "$HOOKS/runtime/bash" \
    "$HOOKS/north-clock-guard-codex" "$STATE" "$command" <<'PY'
import json
import os
import subprocess
import sys

bash, adapter, state, command = sys.argv[1:]
env = os.environ.copy()
for key in (
    "AGENT_NO_AUTHORING_HOOKS",
    "CLAUDE_NO_AUTHORING_HOOKS",
    "BASH_ENV",
    "ENV",
    "TMPDIR",
):
    env.pop(key, None)
env["NORTH_HARNESS_STATE"] = state
payload = json.dumps({
    "tool_name": "Bash",
    "tool_input": {
        "command": command,
        "workdir": "/home/tom/code/north",
    },
    "cwd": "/home/tom/code/north",
}).encode()
result = subprocess.run(
    [bash, adapter],
    input=payload,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    env=env,
    timeout=8,
)
stdout = result.stdout.decode().strip()
stderr = result.stderr.decode().strip()
if result.returncode or stderr:
    print(f"REAL_CORE_FAILED rc={result.returncode} stderr={stderr}")
else:
    print(stdout)
PY
}

expect 'real adapter admits the full detached matrix as proved nonclient' \
  "$NOOP" invoke_real_core "$detached_matrix_command"
unsafe_detached_matrix_command="set -x${detached_matrix_command#set}"
expect 'real adapter rejects an unsafe detached-matrix set preamble' \
  "$UNAVAILABLE" invoke_real_core "$unsafe_detached_matrix_command"

printf '\n== result: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
