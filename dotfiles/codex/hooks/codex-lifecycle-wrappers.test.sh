#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/codex-lifecycle-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
HOOKS="$SCRATCH/hooks"
mkdir -p "$HOOKS/north/bin" "$HOOKS/runtime"
ln -s "$(readlink -f "$(command -v bash)")" "$HOOKS/runtime/bash"

wrappers=(
  north-on-spawn-codex
  north-on-tooluse-codex
  north-mark-delegated-codex
  north-on-stop-codex
)
targets=(
  north-on-spawn
  north-on-tooluse
  north-mark-delegated
  north-on-stop
)
for wrapper in "${wrappers[@]}"; do
  cp "$HERE/$wrapper" "$HOOKS/$wrapper"
  chmod +x "$HOOKS/$wrapper"
done

for target in "${targets[@]}"; do
  cat >"$HOOKS/north/bin/$target" <<'STUB'
#!/usr/bin/env bash
{
  printf 'target=%s\n' "${0##*/}"
  printf 'provider=%s\n' "${AGENT_PROVIDER:-}"
  printf 'north_home=%s\n' "${NORTH_HOME:-}"
  printf 'agent_id=%s\n' "${AGENT_ID:-}"
  printf 'topology=%s\n' "${AGENT_TOPOLOGY:-}"
  printf 'managed_lane=%s\n' "${NORTH_MANAGED_LANE:-}"
  printf 'input='
  cat
  printf '\n'
} >>"$WRAPPER_TEST_RECORD"
printf '{"delegated":"%s"}\n' "${0##*/}"
STUB
  chmod +x "$HOOKS/north/bin/$target"
done

pass=0
fail=0
check() {
  local description="$1"
  shift
  if "$@"; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$description"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$description"
  fi
}

no_derived_session() {
  ! grep -q '^@agent:session-' "$1"
}

record_has_no_managed_env() {
  grep -Fxq 'agent_id=' "$1" &&
    grep -Fxq 'topology=' "$1" &&
    grep -Fxq 'managed_lane=' "$1"
}

drain_probe() {
  local wrapper="$1" delay="$2" result
  result="$(python3 - "$HOOKS/$wrapper" "$delay" <<'PY'
import os
import subprocess
import sys
import time

wrapper, delay = sys.argv[1:]
payload = b'{"padding":"' + b"x" * (512 * 1024) + b'"}'
env = os.environ | {
    "NORTH_MANAGED_LANE": "1",
    "AGENT_ID": "lane-123",
    "AGENT_TOPOLOGY": "worker",
}
process = subprocess.Popen(
    [wrapper], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env
)
broken = False
for offset in range(0, len(payload), 8192):
    try:
        process.stdin.write(payload[offset : offset + 8192])
        process.stdin.flush()
    except BrokenPipeError:
        broken = True
        break
    if delay == "delayed":
        time.sleep(0.001)
try:
    process.stdin.close()
except BrokenPipeError:
    broken = True
stdout = process.stdout.read()
stderr = process.stderr.read()
try:
    status = process.wait(timeout=5)
except subprocess.TimeoutExpired:
    process.kill()
    status = process.wait()
    broken = True
print("DRAIN_FAILED" if broken or status or stdout or stderr else "DRAINED")
PY
)" || result=DRAIN_FAILED
  test "$result" = DRAINED
}

# This is the exact graph shape the managed branch must leave untouched: one
# harness-owned lane identity and no provider-derived session row.
GRAPH="$SCRATCH/graph"
printf '%s\n' '@agent:lane-123 kind lane' >"$GRAPH"
graph_before="$(sha256sum "$GRAPH")"
for wrapper in "${wrappers[@]}"; do
  record="$SCRATCH/$wrapper.managed"
  output="$(
    printf '%s' '{"session_id":"provider-session"}' |
      NORTH_MANAGED_LANE=1 AGENT_ID=lane-123 AGENT_TOPOLOGY=worker \
      WRAPPER_TEST_RECORD="$record" "$HOOKS/$wrapper"
  )"
  check "$wrapper managed branch is output-silent" test -z "$output"
  check "$wrapper managed branch never delegates to native lifecycle" test ! -e "$record"
  check "$wrapper managed branch drains a pipe-buffer payload" \
    drain_probe "$wrapper" immediate
  check "$wrapper managed branch drains delayed writer payload" \
    drain_probe "$wrapper" delayed
done
graph_after="$(sha256sum "$GRAPH")"
check 'managed wrappers leave the sole kind=lane identity unchanged' \
  test "$graph_before" = "$graph_after"
check 'managed wrappers create no derived session row' \
  no_derived_session "$GRAPH"

# Only the explicit harness marker plus both coherent sealed fields authorizes
# suppression. Stale native residue must always take the native lifecycle path.
record="$SCRATCH/stale-complete-tuple.native"
printf '%s' '{"session_id":"native-with-stale-complete-tuple"}' |
  env -u NORTH_MANAGED_LANE AGENT_ID=stale-id AGENT_TOPOLOGY=worker WRAPPER_TEST_RECORD="$record" \
  "$HOOKS/north-on-spawn-codex" >/dev/null
check 'AGENT_ID + topology without explicit managed marker follows native lifecycle' \
  grep -Fxq 'target=north-on-spawn' "$record"
check 'stale complete tuple is scrubbed before native delegation' \
  record_has_no_managed_env "$record"

record="$SCRATCH/stale-agent-id.native"
printf '%s' '{"session_id":"native-with-stale-id"}' |
  env -u NORTH_MANAGED_LANE AGENT_ID=stale-id WRAPPER_TEST_RECORD="$record" \
  "$HOOKS/north-on-spawn-codex" >/dev/null
check 'AGENT_ID without managed topology follows native lifecycle' \
  grep -Fxq 'target=north-on-spawn' "$record"
check 'stale native AGENT_ID is scrubbed before delegation' \
  grep -Fxq 'agent_id=' "$record"

record="$SCRATCH/topology-without-id.native"
printf '%s' '{"session_id":"native-with-stale-topology"}' |
  env -u AGENT_ID AGENT_TOPOLOGY=worker WRAPPER_TEST_RECORD="$record" \
  "$HOOKS/north-on-spawn-codex" >/dev/null
check 'managed topology without AGENT_ID follows native lifecycle' \
  grep -Fxq 'target=north-on-spawn' "$record"
check 'stale native topology is scrubbed before delegation' \
  grep -Fxq 'topology=' "$record"

record="$SCRATCH/invalid-managed-id.native"
printf '%s' '{"session_id":"native-with-invalid-id"}' |
  AGENT_ID='../invalid' AGENT_TOPOLOGY=worker WRAPPER_TEST_RECORD="$record" \
  "$HOOKS/north-on-spawn-codex" >/dev/null
check 'noncanonical AGENT_ID with managed topology follows native lifecycle' \
  grep -Fxq 'target=north-on-spawn' "$record"
check 'incoherent managed residue is fully scrubbed before delegation' \
  record_has_no_managed_env "$record"

record="$SCRATCH/marker-without-identity.native"
printf '%s' '{"session_id":"native-with-lone-marker"}' |
  env -u AGENT_ID -u AGENT_TOPOLOGY NORTH_MANAGED_LANE=1 \
    WRAPPER_TEST_RECORD="$record" "$HOOKS/north-on-spawn-codex" >/dev/null
check 'managed marker without sealed identity follows native lifecycle' \
  grep -Fxq 'target=north-on-spawn' "$record"
check 'incomplete managed marker is scrubbed before delegation' \
  record_has_no_managed_env "$record"

for index in "${!wrappers[@]}"; do
  wrapper="${wrappers[$index]}"
  target="${targets[$index]}"
  record="$SCRATCH/$wrapper.native"
  payload='{"session_id":"native-session"}'
  output="$(
    printf '%s' "$payload" |
      env -u AGENT_ID WRAPPER_TEST_RECORD="$record" "$HOOKS/$wrapper"
  )"
  check "$wrapper native branch delegates to $target" \
    grep -Fxq "target=$target" "$record"
  check "$wrapper native branch pins provider=openai" \
    grep -Fxq 'provider=openai' "$record"
  check "$wrapper native branch pins NORTH_HOME" \
    grep -Fxq "north_home=$HOOKS/north" "$record"
  check "$wrapper native branch carries no managed identity residue" \
    record_has_no_managed_env "$record"
  check "$wrapper native branch preserves stdin" \
    grep -Fxq "input=$payload" "$record"
  check "$wrapper native branch preserves target output" \
    test "$output" = "{\"delegated\":\"$target\"}"
done

printf '\n== result: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
