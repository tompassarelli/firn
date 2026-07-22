#!/usr/bin/env bash
# Cross-hook regression: installed managed hooks must consume complete delayed
# envelopes before disabled and fast-allow exits.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/hook-stdin-drain-test.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT

HOME_DIR="$SCRATCH/home"
PLAIN_DIR="$SCRATCH/plain"
STATE="$SCRATCH/harness.conf"
mkdir -p "$HOME_DIR" "$PLAIN_DIR" "$SCRATCH/session-state"
touch "$PLAIN_DIR/notes.txt"
printf '%s\n' 'dispatch=native' 'guards=on' >"$STATE"

hooks=(
  agent-spawn-guard.sh
  code-upstream-guard.sh
  firn-guard.sh
  tripwire-guard.sh
  beagle-session-start.sh
  racket-build-guard.sh
)
sizes=(524288 1048576)
modes=(disabled fast-allow)

pass=0
fail=0
for mode in "${modes[@]}"; do
  for size in "${sizes[@]}"; do
    for hook in "${hooks[@]}"; do
      result="$(python3 - "$HERE/$hook" "$mode" "$size" "$HOME_DIR" "$PLAIN_DIR" "$STATE" <<'PY'
import json
import os
import subprocess
import sys
import time

hook, mode, size_text, home, plain, state = sys.argv[1:]
size = int(size_text)
name = os.path.basename(hook)
target = os.path.join(plain, "notes.txt")

envelopes = {
    "agent-spawn-guard.sh": {
        "hook_event_name": "PreToolUse",
        "tool_name": "Agent",
        "tool_input": {
            "subagent_type": "general-purpose",
            "prompt": "transport allow",
        },
        "cwd": plain,
    },
    "code-upstream-guard.sh": {
        "hook_event_name": "PreToolUse",
        "tool_name": "Edit",
        "tool_input": {"file_path": target},
        "cwd": plain,
    },
    "firn-guard.sh": {
        "hook_event_name": "PreToolUse",
        "tool_name": "Edit",
        "tool_input": {"file_path": target},
        "cwd": plain,
    },
    "tripwire-guard.sh": {
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": "true"},
        "cwd": plain,
    },
    "beagle-session-start.sh": {
        "hook_event_name": "SessionStart",
        "session_id": f"drain-{mode}-{size}",
        "source": "startup",
        "cwd": plain,
    },
    "racket-build-guard.sh": {
        "hook_event_name": "PostToolUse",
        "tool_name": "Edit",
        "tool_input": {"file_path": target},
        "cwd": plain,
    },
}
envelope = dict(envelopes[name])
envelope["padding"] = ""
base = json.dumps(envelope, separators=(",", ":")).encode()
padding_size = size - len(base)
if padding_size < 0:
    raise SystemExit("target envelope smaller than fixture")
envelope["padding"] = "x" * padding_size
payload = json.dumps(envelope, separators=(",", ":")).encode()
assert len(payload) == size

env = os.environ.copy()
for key in ("BASH_ENV", "ENV", "CLAUDE_PROJECT_DIR"):
    env.pop(key, None)
env.update({
    "HOME": home,
    "NORTH_HARNESS_STATE": state,
    "GRAPH_UPSTREAM_REGISTRY": os.path.join(home, "missing-registry"),
    "BEAGLE_SESSION_STATE_DIR": os.path.join(home, "session-state"),
    "AGENT_TOPOLOGY": "orchestrator",
    "AGENT_NO_AUTHORING_HOOKS": "1" if mode == "disabled" else "0",
})

process = subprocess.Popen(
    [hook],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    env=env,
)
broken = False
assert process.stdin is not None
for offset in range(0, len(payload), 8192):
    try:
        process.stdin.write(payload[offset:offset + 8192])
        process.stdin.flush()
    except BrokenPipeError:
        broken = True
        break
    if offset == 0:
        time.sleep(0.05)
    else:
        time.sleep(0.001)
try:
    process.stdin.close()
except BrokenPipeError:
    broken = True
assert process.stdout is not None
assert process.stderr is not None
stdout = process.stdout.read()
stderr = process.stderr.read()
try:
    status = process.wait(timeout=8)
except subprocess.TimeoutExpired:
    process.kill()
    status = process.wait()
    broken = True

ok = not broken and status == 0 and stdout == b"" and stderr == b""
print(
    f"{'PASS' if ok else 'FAIL'}  {name} {mode} bytes={size} "
    f"status={status} broken={str(broken).lower()} "
    f"stdout={len(stdout)} stderr={len(stderr)}"
)
raise SystemExit(0 if ok else 1)
PY
)"
      if [ "$?" -eq 0 ]; then
        pass=$((pass + 1))
      else
        fail=$((fail + 1))
      fi
      printf '%s\n' "$result"
    done
  done
done

# Keep representative decision paths pinned while transport mechanics change.
printf '%s\n' 'dispatch=north' 'guards=on' >"$STATE"
agent_out="$(
  python3 -c 'import json; print(json.dumps({"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"work"}}))' |
    env HOME="$HOME_DIR" NORTH_HARNESS_STATE="$STATE" AGENT_NO_AUTHORING_HOOKS=0 \
      "$HERE/agent-spawn-guard.sh"
)"
if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$agent_out" >/dev/null; then
  pass=$((pass + 1))
  printf '%s\n' 'PASS  agent-spawn-guard.sh decision remains deny'
else
  fail=$((fail + 1))
  printf '%s\n' 'FAIL  agent-spawn-guard.sh decision changed'
fi

canonical="$PLAIN_DIR/canonical.bclj"
touch "$canonical"
printf '%s\n' "$canonical" >"$SCRATCH/graph-registry"
upstream_out="$(
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1]}}))' "$canonical" |
    env HOME="$HOME_DIR" NORTH_HARNESS_STATE="$STATE" AGENT_NO_AUTHORING_HOOKS=0 \
      GRAPH_UPSTREAM_REGISTRY="$SCRATCH/graph-registry" \
      "$HERE/code-upstream-guard.sh"
)"
if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$upstream_out" >/dev/null; then
  pass=$((pass + 1))
  printf '%s\n' 'PASS  code-upstream-guard.sh decision remains deny'
else
  fail=$((fail + 1))
  printf '%s\n' 'FAIL  code-upstream-guard.sh decision changed'
fi

firn_out="$(
  python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"nixos-rebuild switch"}}))' |
    env HOME="$HOME_DIR" NORTH_HARNESS_STATE="$STATE" AGENT_NO_AUTHORING_HOOKS=0 \
      "$HERE/firn-guard.sh"
)"
if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$firn_out" >/dev/null; then
  pass=$((pass + 1))
  printf '%s\n' 'PASS  firn-guard.sh decision remains deny'
else
  fail=$((fail + 1))
  printf '%s\n' 'FAIL  firn-guard.sh decision changed'
fi

tripwire_status=0
tripwire_err="$(
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"git push","cwd":sys.argv[1]}}))' "$PLAIN_DIR" |
    env -u SAFE_PUSH_ACTIVE HOME="$HOME_DIR" NORTH_HARNESS_STATE="$STATE" \
      AGENT_NO_AUTHORING_HOOKS=0 TRIPWIRE_LOG_DIR="$SCRATCH/tripwire-log" \
      "$HERE/tripwire-guard.sh" 2>&1
)" || tripwire_status=$?
if [ "$tripwire_status" -eq 2 ] && [[ "$tripwire_err" == *"raw 'git push'"* ]]; then
  pass=$((pass + 1))
  printf '%s\n' 'PASS  tripwire-guard.sh decision remains hard deny'
else
  fail=$((fail + 1))
  printf 'FAIL  tripwire-guard.sh decision changed status=%s stderr=%s\n' \
    "$tripwire_status" "$tripwire_err"
fi

printf '\n%d/%d passed\n' "$pass" "$((pass + fail))"
[ "$fail" -eq 0 ]
