#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/codex-lifecycle-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
TEST_PYTHON="$(readlink -f "$(command -v python3)")"
HOOKS="$SCRATCH/hooks"
mkdir -p "$HOOKS/north/bin" "$HOOKS/runtime" "$HOOKS/lib"
ln -s "$(readlink -f "$(command -v bash)")" "$HOOKS/runtime/bash"
ln -s "$TEST_PYTHON" "$HOOKS/runtime/python3"
cp "$HERE/../../agents/lib/north-agent-activation.sh" "$HOOKS/lib/"
NORTH_AGENT_STATE_ROOT="$SCRATCH/agent-state"
export NORTH_AGENT_STATE_ROOT
mkdir -p "$NORTH_AGENT_STATE_ROOT/current"

write_activation() {
  local active="$1"
  local permission="${2:-}"
  if [ -z "$permission" ]; then
    permission=off
    [ "$active" = true ] && permission=on
  fi
  cat >"$NORTH_AGENT_STATE_ROOT/current/activation.json" <<JSON
{"schema":"north.agent-activation/v1","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[
{"id":"north-on-spawn","kind":"hook","title":"North on spawn","triggerDescription":"Publish spawn telemetry.","permission":"$permission","active":$active,"owner":{"repo":"north","path":"bin/north-on-spawn"},"members":[],"supports":["assignments"],"distributions":[{"type":"providerAdapter","targets":["codex"],"owner":{"repo":"nixos-config","path":"dotfiles/codex/hooks/north-on-spawn-codex"},"adapterId":"north-on-spawn-codex"}],"activationPaths":[]},
{"id":"north-on-tooluse","kind":"hook","title":"North on tool use","triggerDescription":"Publish tool-use telemetry.","permission":"$permission","active":$active,"owner":{"repo":"north","path":"bin/north-on-tooluse"},"members":[],"supports":["assignments"],"distributions":[{"type":"providerAdapter","targets":["codex"],"owner":{"repo":"nixos-config","path":"dotfiles/codex/hooks/north-on-tooluse-codex"},"adapterId":"north-on-tooluse-codex"}],"activationPaths":[]},
{"id":"north-mark-delegated","kind":"hook","title":"North mark delegated","triggerDescription":"Publish delegation telemetry.","permission":"$permission","active":$active,"owner":{"repo":"north","path":"bin/north-mark-delegated"},"members":[],"supports":["assignments"],"distributions":[{"type":"providerAdapter","targets":["codex"],"owner":{"repo":"nixos-config","path":"dotfiles/codex/hooks/north-mark-delegated-codex"},"adapterId":"north-mark-delegated-codex"}],"activationPaths":[]},
{"id":"north-on-stop","kind":"hook","title":"North on stop","triggerDescription":"Publish stop telemetry.","permission":"$permission","active":$active,"owner":{"repo":"north","path":"bin/north-on-stop"},"members":[],"supports":["assignments"],"distributions":[{"type":"providerAdapter","targets":["codex"],"owner":{"repo":"nixos-config","path":"dotfiles/codex/hooks/north-on-stop-codex"},"adapterId":"north-on-stop-codex"}],"activationPaths":[]},
{"id":"north-on-terminal","kind":"hook","title":"North on terminal","triggerDescription":"Publish terminal telemetry.","permission":"$permission","active":$active,"owner":{"repo":"north","path":"bin/north-on-terminal"},"members":[],"supports":["assignments"],"distributions":[{"type":"providerAdapter","targets":["codex"],"owner":{"repo":"nixos-config","path":"dotfiles/codex/hooks/north-on-terminal-codex"},"adapterId":"north-on-terminal-codex"}],"activationPaths":[]}]}
JSON
}

helper_reports_spawn_active() {
  "$HOOKS/runtime/bash" -c \
    'source "$1" && north_agent_unit_active hook north-on-spawn' \
    lifecycle-helper "$HOOKS/lib/north-agent-activation.sh"
}

helper_rejects_spawn_active() {
  ! helper_reports_spawn_active
}

write_activation true

wrappers=(
  north-on-spawn-codex
  north-on-tooluse-codex
  north-mark-delegated-codex
  north-on-stop-codex
  north-on-terminal-codex
)
targets=(
  north-on-spawn
  north-on-tooluse
  north-mark-delegated
  north-on-stop
  north-on-terminal
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

drain_probe() {
  local wrapper="$1" mode="$2" result
  result="$("$TEST_PYTHON" - "$HOOKS/$wrapper" "$mode" <<'PY'
import os
import subprocess
import sys
import time

adapter, mode = sys.argv[1:]
env = os.environ.copy()
env.pop("AGENT_ID", None)
env.pop("AGENT_TOPOLOGY", None)
env.pop("NORTH_MANAGED_LANE", None)
if mode == "managed":
    env.update({
        "AGENT_ID": "lane-delayed-drain",
        "AGENT_TOPOLOGY": "worker",
        "NORTH_MANAGED_LANE": "1",
    })
payload = b'{"padding":"' + b"x" * (512 * 1024) + b'"}'
process = subprocess.Popen(
    [adapter],
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
    time.sleep(0.002)
try:
    process.stdin.close()
except BrokenPipeError:
    broken = True
assert process.stdout is not None
assert process.stderr is not None
stdout = process.stdout.read()
stderr = process.stderr.read()
try:
    status = process.wait(timeout=5)
except subprocess.TimeoutExpired:
    process.kill()
    status = process.wait()
    broken = True
if broken or status != 0 or stdout or stderr:
    print(
        f"DRAIN_FAILED broken={broken} status={status} "
        f"stdout={len(stdout)} stderr={len(stderr)}"
    )
else:
    print("DRAINED")
PY
)" || result=DRAIN_FAILED
  printf '%s\n' "$result"
}

no_derived_session() {
  ! grep -q '^@agent:session-' "$1"
}

record_has_no_managed_env() {
  grep -Fxq 'agent_id=' "$1" &&
    grep -Fxq 'topology=' "$1" &&
    grep -Fxq 'managed_lane=' "$1"
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
  check "$wrapper managed branch drains delayed larger-than-pipe stdin" \
    test "$(drain_probe "$wrapper" managed)" = DRAINED
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
  env -u NORTH_MANAGED_LANE AGENT_ID=stale-id AGENT_TOPOLOGY=worker \
    WRAPPER_TEST_RECORD="$record" "$HOOKS/north-on-spawn-codex" >/dev/null
check 'AGENT_ID + topology without explicit managed marker follows native lifecycle' \
  grep -Fxq 'target=north-on-spawn' "$record"
check 'stale complete tuple is scrubbed before native delegation' \
  record_has_no_managed_env "$record"

record="$SCRATCH/stale-agent-id.native"
printf '%s' '{"session_id":"native-with-stale-id"}' |
  env -u AGENT_TOPOLOGY -u NORTH_MANAGED_LANE AGENT_ID=stale-id \
    WRAPPER_TEST_RECORD="$record" "$HOOKS/north-on-spawn-codex" >/dev/null
check 'AGENT_ID without managed topology follows native lifecycle' \
  grep -Fxq 'target=north-on-spawn' "$record"
check 'stale native AGENT_ID is scrubbed before delegation' \
  grep -Fxq 'agent_id=' "$record"

record="$SCRATCH/topology-without-id.native"
printf '%s' '{"session_id":"native-with-stale-topology"}' |
  env -u AGENT_ID -u NORTH_MANAGED_LANE AGENT_TOPOLOGY=worker \
    WRAPPER_TEST_RECORD="$record" "$HOOKS/north-on-spawn-codex" >/dev/null
check 'managed topology without AGENT_ID follows native lifecycle' \
  grep -Fxq 'target=north-on-spawn' "$record"
check 'stale native topology is scrubbed before delegation' \
  grep -Fxq 'topology=' "$record"

record="$SCRATCH/invalid-managed-id.native"
printf '%s' '{"session_id":"native-with-invalid-id"}' |
  env -u NORTH_MANAGED_LANE AGENT_ID='../invalid' AGENT_TOPOLOGY=worker \
    WRAPPER_TEST_RECORD="$record" "$HOOKS/north-on-spawn-codex" >/dev/null
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
      env -u AGENT_ID -u AGENT_TOPOLOGY -u NORTH_MANAGED_LANE \
        WRAPPER_TEST_RECORD="$record" "$HOOKS/$wrapper"
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

write_activation false
for wrapper in "${wrappers[@]}"; do
  record="$SCRATCH/$wrapper.activation-off"
  output="$(
    printf '%s' '{"session_id":"activation-off"}' |
      WRAPPER_TEST_RECORD="$record" "$HOOKS/$wrapper"
  )"
  check "$wrapper is silent while lifecycle activity is off" test -z "$output"
  check "$wrapper does not delegate while lifecycle activity is off" test ! -e "$record"
  check "$wrapper drains delayed stdin while lifecycle activity is off" \
    test "$(drain_probe "$wrapper" native)" = DRAINED
done

write_activation true 'off:until=2099-01-01T00:00:00Z'
check 'activation helper rejects TTL permission syntax' \
  helper_rejects_spawn_active

write_activation true off
check 'activation helper rejects off permission with active activity' \
  helper_rejects_spawn_active

write_activation true

mv "$NORTH_AGENT_STATE_ROOT/current/activation.json" \
  "$NORTH_AGENT_STATE_ROOT/current/activation.missing"
for wrapper in "${wrappers[@]}"; do
  record="$SCRATCH/$wrapper.activation-missing"
  output="$(
    printf '%s' '{"session_id":"activation-missing"}' |
      WRAPPER_TEST_RECORD="$record" "$HOOKS/$wrapper"
  )"
  check "$wrapper is inactive without a North generation" test -z "$output"
  check "$wrapper does not delegate without a North generation" test ! -e "$record"
done
mv "$NORTH_AGENT_STATE_ROOT/current/activation.missing" \
  "$NORTH_AGENT_STATE_ROOT/current/activation.json"

sed -i 's#north.agent-activation/v1#north.agent-activation/invalid#' \
  "$NORTH_AGENT_STATE_ROOT/current/activation.json"
for wrapper in "${wrappers[@]}"; do
  record="$SCRATCH/$wrapper.activation-invalid"
  output="$(
    printf '%s' '{"session_id":"activation-invalid"}' |
      WRAPPER_TEST_RECORD="$record" "$HOOKS/$wrapper"
  )"
  check "$wrapper rejects an invalid North activation schema" test -z "$output"
  check "$wrapper does not delegate from an invalid generation" test ! -e "$record"
done
write_activation true

for index in "${!wrappers[@]}"; do
  wrapper="${wrappers[$index]}"
  target="${targets[$index]}"
  mv "$HOOKS/north/bin/$target" "$HOOKS/north/bin/$target.missing"
  check "$wrapper missing-target path drains delayed larger-than-pipe stdin" \
    test "$(drain_probe "$wrapper" missing-target)" = DRAINED
  mv "$HOOKS/north/bin/$target.missing" "$HOOKS/north/bin/$target"
done

printf '\n== result: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
