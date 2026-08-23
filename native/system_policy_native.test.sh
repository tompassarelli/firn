#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [[ -n "${BEAGLE_PATH:-}" ]]; then
  beagle="$BEAGLE_PATH"
else
  git_common_dir="$(
    timeout --foreground 5 git -C "$repo" rev-parse \
      --path-format=absolute --git-common-dir
  )" || {
    printf 'system-policy-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
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

die() {
  printf 'system-policy-native: %s\n' "$*" >&2
  exit 1
}

[[ -f "$beagle/bin/beagle" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

json="$beagle/native-core/src/native/json.bgl"
policy="$repo/native/system_policy.bgl"
driver="$repo/native/system_policy_native.bgl"

timeout --foreground 90 "$beagle/bin/beagle" check --agent \
  "$json" "$policy" "$driver" \
  >"$scratch/check.out" 2>"$scratch/check.err" \
  || {
    sed -n '1,240p' "$scratch/check.err" >&2
    die "strict source check failed"
  }

timeout --foreground 620 "$beagle/bin/beagle" native-exe \
  --out "$scratch/system-policy" \
  --entry firn.system-policy-native/-main \
  --artifacts "$scratch/artifacts" \
  "$json" "$policy" "$driver" \
  >"$scratch/build.out" 2>"$scratch/build.err" \
  || {
    sed -n '1,260p' "$scratch/build.err" >&2
    die "native executable build failed"
  }
[[ -x "$scratch/system-policy" ]] || die "native executable is missing"

if command -v ldd >/dev/null 2>&1; then
  ldd "$scratch/system-policy" >"$scratch/ldd.out" 2>"$scratch/ldd.err" || true
  ! rg -i 'racket|python|java|clojure|babashka|libjvm' "$scratch/ldd.out" \
    || die "native executable links a hosted runtime"
fi

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
{"schema":"$schema","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[{"id":"firn-system-policy","kind":"hook","title":"Firn system policy","triggerDescription":"Protect Firn authoring and system switching.","permission":"$permission","active":$active,"owner":{"repo":"nixos-config","path":"native/system_policy_native.bgl"},"members":[],"supports":["firn"],"distributions":[{"type":"providerAdapter","targets":["firn","codex","bridge"],"owner":{"repo":"north","path":"profiles/tom/hooks/firn-system-policy.sh"},"adapterId":"firn-system-policy"}],"activationPaths":[["firn-system-policy"]]}]}
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

ln -s "$repo" "$scratch/repo-through-symlink"
inject_payload="$(printf \
  '{"tool_name":"Edit","tool_input":{"file_path":"%s/native/system_policy.bgl"},"session_id":"inject/session"}' \
  "$scratch/repo-through-symlink")"
run_case inject "$inject_payload"
digest='You are editing the Firn system configuration. Edit .bnix sources, never .nix; run firn repo build and firn repo validate after .bnix changes. Raw nixos-rebuild, darwin-rebuild, nh switching, and firn repo upgrade now remain user-only. Secrets use sops-nix only.'
expected_inject="$(printf \
  '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' \
  "$digest")"
[[ "$(<"$scratch/inject.out")" == "${expected_inject%$'\n'}" ]] \
  || die "additionalContext JSON changed"
[[ -f "$scratch/runtime/firn-system-policy.inject_session" ]] \
  || die "session marker was not created"
run_case inject-second "$inject_payload"
[[ ! -s "$scratch/inject-second.out" ]] \
  || die "second edit in one session repeated the intro"

write_payload="$(printf \
  '{"tool_name":"Write","tool_input":{"filePath":"%s/native/system_policy.bgl"},"session_id":"write-session"}' \
  "$scratch/repo-through-symlink")"
run_case write "$write_payload"
[[ "$(<"$scratch/write.out")" == "${expected_inject%$'\n'}" ]] \
  || die "Write camel-case path was not decoded"

multiedit_payload="$(printf \
  '{"tool_name":"MultiEdit","tool_input":{"file_path":"%s/native/system_policy.bgl"},"session_id":"multiedit-session"}' \
  "$scratch/repo-through-symlink")"
run_case multiedit "$multiedit_payload"
[[ "$(<"$scratch/multiedit.out")" == "${expected_inject%$'\n'}" ]] \
  || die "MultiEdit path was not decoded"

run_case apply-patch \
  '{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch"},"session_id":"apply-patch"}'
[[ ! -s "$scratch/apply-patch.out" ]] \
  || die "apply_patch without a decodable path claimed Firn handling"

run_case deny \
  '{"tool_name":"Bash","tool_input":{"command":"sudo nixos-rebuild switch"},"session_id":"deny"}'
reason="BLOCKED: that command switches the system outside the sanctioned path. Raw nixos-rebuild/darwin-rebuild/nh and \`firn repo upgrade now\` stay the user's. Agents may run \`firn rebuild\` after the relevant checks pass and their own changes are committed."
expected_deny="$(printf \
  '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
  "$reason")"
[[ "$(<"$scratch/deny.out")" == "${expected_deny%$'\n'}" ]] \
  || die "permission deny JSON changed"

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
[[ "$(<"$scratch/forced-live.out")" == "${expected_deny%$'\n'}" ]] \
  || die "per-session force-live override did not outrank stored activity"
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

printf 'system-policy-native: activation edit/write/multiedit apply-patch-omitted bash kill-switch fail-open no-hosted-runtime PASS\n'
