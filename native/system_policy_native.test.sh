#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-system-policy-native.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'system-policy-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'printf "system-policy-native: line %s failed: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

die() {
  printf 'system-policy-native: %s\n' "$*" >&2
  exit 1
}

for command in jq timeout; do
  command -v "$command" >/dev/null 2>&1 \
    || die "missing command: $command"
done
bun="${FIRN_BUN:-$(command -v bun || true)}"
[[ -n "$bun" && -x "$bun" ]] || die "Bun runtime is unavailable"

pure="$repo/native/system_policy_test.ts"
driver="$repo/native/system_policy_native.ts"
bridge="$repo/native/system_policy_host.mjs"
pure_js="$pure"
driver_js="$driver"

printf 'system-policy-ts: running one closed typed family graph\n' >&2
FIRN_SYSTEM_POLICY_TEST_MODULE="$pure_js" timeout --foreground 30 "$bun" --eval \
  'const m = await import(process.env.FIRN_SYSTEM_POLICY_TEST_MODULE); process.exitCode = m.runScenarios() + m.runProperties(process.env.CI ? 512 : 128);' \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die "pure policy fixtures failed"

cat >"$scratch/system-policy" <<EOF
#!/usr/bin/env bash
exec env FIRN_SYSTEM_POLICY_MODULE='$driver_js' '$bun' '$bridge'
EOF
chmod +x "$scratch/system-policy"

mkdir -p "$scratch/runtime" "$scratch/home/.local/state/north" \
  "$scratch/agent-state/current"
export XDG_RUNTIME_DIR="$scratch/runtime"
export HOME="$scratch/home"
export NORTH_AGENT_STATE_ROOT="$scratch/agent-state"
unset NORTH_HARNESS_STATE
unset AGENT_NO_AUTHORING_HOOKS

write_activation() {
  local active="$1" schema="${2:-north.agent-activation/v1}"
  local permission="${3:-}"
  if [ -z "$permission" ]; then
    permission=off
    [ "$active" = true ] && permission=on
  fi
  cat >"$NORTH_AGENT_STATE_ROOT/current/activation.json" <<JSON
{"schema":"$schema","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[{"id":"firn-system-policy","kind":"hook","title":"Firn system policy","triggerDescription":"Protect Firn authoring and system switching.","permission":"$permission","active":$active,"owner":{"repo":"nixos-config","path":"native/system_policy_native.ts"},"members":[],"supports":["firn"],"distributions":[{"type":"providerAdapter","targets":["firn","codex","claude"],"owner":{"repo":"nixos-config","path":"dotfiles/agents/hooks/firn-system-policy"},"adapterId":"firn-system-policy"}],"activationPaths":[["firn-system-policy"]]}]}
JSON
}

write_activation true

run_case() {
  local name="$1" payload="$2"
  set +e
  printf '%s' "$payload" | timeout --foreground 10 "$scratch/system-policy" \
    >"$scratch/$name.out" 2>"$scratch/$name.err"
  local status=$?
  set -e
  [[ "$status" == 0 ]] || die "$name exited $status"
  [[ ! -s "$scratch/$name.err" ]] || die "$name wrote stderr"
}

run_case pass \
  '{"tool_name":"Bash","tool_input":{"command":"firn rebuild"},"session_id":"pass"}'
[[ ! -s "$scratch/pass.out" ]] || die "pass emitted output"

mkdir -p "$scratch/checkout/code/nixos-config/native"
: >"$scratch/checkout/code/nixos-config/native/system_policy.ts"
ln -s "$scratch/checkout/code/nixos-config" "$scratch/repo-through-symlink"
inject_payload="$(printf \
  '{"tool_name":"Edit","tool_input":{"file_path":"%s/native/system_policy.ts"},"session_id":"inject/session"}' \
  "$scratch/repo-through-symlink")"
run_case inject "$inject_payload"
jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and (.hookSpecificOutput.additionalContext | type) == "string"' "$scratch/inject.out" >/dev/null
jq -e '.hookSpecificOutput.additionalContext | startswith("You are editing the Firn system configuration. Edit .gal sources, never .nix; run firn repo build and firn repo validate after .gal changes. Check uncertain Galileo syntax and schema facts with the runtime'"'"'s galileo help, galileo refs and galileo schema explain. ")' "$scratch/inject.out" >/dev/null \
  || die "inject context does not carry the .gal instruction text"
[[ -f "$scratch/runtime/firn-system-policy.inject_session" ]] \
  || die "session marker was not created"
run_case inject-second "$inject_payload"
[[ ! -s "$scratch/inject-second.out" ]] \
  || die "second edit in one session repeated the intro"

write_payload="$(printf \
  '{"tool_name":"Write","tool_input":{"filePath":"%s/native/system_policy.ts"},"session_id":"write-session"}' \
  "$scratch/repo-through-symlink")"
run_case write "$write_payload"
jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and (.hookSpecificOutput.additionalContext | type) == "string"' "$scratch/write.out" >/dev/null

multiedit_payload="$(printf \
  '{"tool_name":"MultiEdit","tool_input":{"file_path":"%s/native/system_policy.ts"},"session_id":"multiedit-session"}' \
  "$scratch/repo-through-symlink")"
run_case multiedit "$multiedit_payload"
jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and (.hookSpecificOutput.additionalContext | type) == "string"' "$scratch/multiedit.out" >/dev/null

run_case apply-patch \
  '{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch"},"session_id":"apply-patch"}'
[[ ! -s "$scratch/apply-patch.out" ]] \
  || die "apply_patch without a decodable path claimed Firn handling"

run_case deny \
  '{"tool_name":"Bash","tool_input":{"command":"sudo nixos-rebuild switch"},"session_id":"deny"}'
jq -e '.hookSpecificOutput.permissionDecision == "deny"' "$scratch/deny.out" >/dev/null

run_case upgrade-allowed \
  '{"tool_name":"Bash","tool_input":{"command":"firn repo upgrade now"},"session_id":"upgrade-allowed"}'
[[ ! -s "$scratch/upgrade-allowed.out" ]] \
  || die "sanctioned Firn input upgrade was denied"

write_activation false
run_case inactive \
  '{"tool_name":"Bash","tool_input":{"command":"nixos-rebuild switch"},"session_id":"inactive"}'
[[ ! -s "$scratch/inactive.out" ]] \
  || die "North activation did not disable firn-system-policy"

write_activation true north.agent-activation/invalid
run_case invalid-activation \
  '{"tool_name":"Bash","tool_input":{"command":"nixos-rebuild switch"},"session_id":"invalid-activation"}'
[[ ! -s "$scratch/invalid-activation.out" ]] \
  || die "invalid activation schema did not fail inactive"

write_activation true north.agent-activation/v1 'off:until=2099-01-01T00:00:00Z'
run_case ttl-permission \
  '{"tool_name":"Bash","tool_input":{"command":"nixos-rebuild switch"},"session_id":"ttl-permission"}'
[[ ! -s "$scratch/ttl-permission.out" ]] \
  || die "TTL activation permission did not fail inactive"

write_activation true north.agent-activation/v1 off
run_case off-active \
  '{"tool_name":"Bash","tool_input":{"command":"nixos-rebuild switch"},"session_id":"off-active"}'
[[ ! -s "$scratch/off-active.out" ]] \
  || die "off permission with active activity did not fail inactive"

write_activation false
AGENT_NO_AUTHORING_HOOKS=0 run_case forced-live \
  '{"tool_name":"Bash","tool_input":{"command":"nixos-rebuild switch"},"session_id":"forced-live"}'
jq -e '.hookSpecificOutput.permissionDecision == "deny"' "$scratch/forced-live.out" >/dev/null
write_activation true

run_case malformed '{not-json'
[[ ! -s "$scratch/malformed.out" ]] || die "malformed payload did not fail open"

head -c 1048577 /dev/zero | tr '\0' x >"$scratch/oversized.input"
set +e
timeout --foreground 10 "$scratch/system-policy" \
  <"$scratch/oversized.input" \
  >"$scratch/oversized.out" 2>"$scratch/oversized.err"
oversized_status=$?
set -e
[[ "$oversized_status" == 0 ]] || die "oversized payload exited $oversized_status"
[[ ! -s "$scratch/oversized.out" && ! -s "$scratch/oversized.err" ]] \
  || die "oversized payload did not fail open silently"

AGENT_NO_AUTHORING_HOOKS=1 run_case killed \
  '{"tool_name":"Bash","tool_input":{"command":"nixos-rebuild switch"},"session_id":"killed"}'
[[ ! -s "$scratch/killed.out" ]] || die "kill-switch did not disable the guard"

printf 'system-policy-ts: activation edit/write/multiedit apply-patch-omitted bash kill-switch fail-open Bun-host PASS\n'
