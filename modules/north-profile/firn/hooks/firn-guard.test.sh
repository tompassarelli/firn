#!/usr/bin/env bash
# firn-guard Job 2: the sanctioned rebuild wrapper stays allowed while raw bypasses
# remain denied. Every bypass denial names `firn rebuild` as the compliant move.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/firn-guard.sh"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-guard-test.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT
mkdir -p "$scratch/home"
printf '%s\n' 'guards=on' >"$scratch/harness.conf"

pass=0
fail=0

run_guard() {
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" |
    env HOME="$scratch/home" NORTH_HARNESS_STATE="$scratch/harness.conf" \
      XDG_RUNTIME_DIR="$scratch" AGENT_NO_AUTHORING_HOOKS=0 \
      "$GUARD"
}

# A bypass deny must both refuse and name the sanctioned wrapper.
expect_bypass_deny() {
  local label="$1" cmd="$2" out
  out="$(run_guard "$cmd")"
  if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null 2>&1 &&
    jq -e '.hookSpecificOutput.permissionDecisionReason | contains("firn rebuild")' <<<"$out" >/dev/null 2>&1; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s — got: %s\n' "$label" "$out" >&2
  fi
}

expect_allow() {
  local label="$1" cmd="$2" out
  out="$(run_guard "$cmd")"
  if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null 2>&1; then
    fail=$((fail + 1))
    printf 'FAIL  %s — denied: %s\n' "$label" "$out" >&2
  else
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$label"
  fi
}

# --- the sanctioned wrappers are agent-runnable ---
expect_allow 'firn rebuild is allowed'                          'firn rebuild'
expect_allow 'firn rebuild <host> is allowed'                   'firn rebuild whiterabbit'
expect_allow 'sudo firn rebuild is allowed'                     'sudo firn rebuild'
expect_allow 'chained firn rebuild is allowed'                  'git commit -m x && firn rebuild'

# --- raw bypasses stay denied and point back to the sanctioned wrapper ---
expect_bypass_deny 'nixos-rebuild switch still denied'          'sudo nixos-rebuild switch --flake .'
expect_bypass_deny 'nh os switch still denied'                  'nh os switch'
expect_bypass_deny 'darwin-rebuild switch still denied'         'darwin-rebuild switch'
expect_bypass_deny 'firn update still denied'                   'firn update'

# --- the compliant move itself must never be denied ---
expect_allow 'firn build is allowed'                            'firn build'
expect_allow 'firn validate is allowed'                         'firn validate'
expect_allow 'firn update --dry-run is allowed'                 'firn update --dry-run'
expect_allow 'firn-rebuild-impact is allowed'                   'firn-rebuild-impact'
# Mentions are not invocations: the anchor is what keeps docs writable.
expect_allow 'echoing the denied string is allowed'             'echo "never run firn rebuild directly"'
expect_allow 'grepping for the denied string is allowed'        'rg "firn rebuild" docs/'

expect_allow 'backticked firn rebuild prose is allowed'         'git commit -F - <<MSG
`firn rebuild` is agent-runnable.
MSG'

printf '\nfirn-guard.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
