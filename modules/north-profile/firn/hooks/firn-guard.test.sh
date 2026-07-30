#!/usr/bin/env bash
# firn-guard Job 2: which commands an agent may run, and what the deny TEACHES.
# A deny that does not name the compliant move is a wall, not a guard — every
# rebuild-class denial here is asserted to name `north rebuild request --why`.
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

# A rebuild-class deny must both refuse AND name the queue verb.
expect_queue_deny() {
  local label="$1" cmd="$2" out
  out="$(run_guard "$cmd")"
  if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null 2>&1 &&
    jq -e '.hookSpecificOutput.permissionDecisionReason | contains("north rebuild request --why")' <<<"$out" >/dev/null 2>&1; then
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

# --- the flip: both rebuild wrappers are denied, and redirect to the queue ---
expect_queue_deny 'firn rebuild -> queue verb'                  'firn rebuild'
expect_queue_deny 'firn rebuild <host> -> queue verb'           'firn rebuild whiterabbit'
expect_queue_deny 'sudo firn rebuild -> queue verb'             'sudo firn rebuild'
expect_queue_deny 'chained firn rebuild -> queue verb'          'git commit -m x && firn rebuild'
expect_queue_deny 'firn-rebuild-coordinated -> queue verb'      'firn-rebuild-coordinated --why "x"'
expect_queue_deny 'path-prefixed firn-rebuild-coordinated'      '/opt/somewhere/bin/firn-rebuild-coordinated --why "x"'

# --- the pre-existing bypass denials survive, and also carry the queue verb ---
expect_queue_deny 'nixos-rebuild switch still denied'           'sudo nixos-rebuild switch --flake .'
expect_queue_deny 'nh os switch still denied'                   'nh os switch'
expect_queue_deny 'darwin-rebuild switch still denied'          'darwin-rebuild switch'
expect_queue_deny 'firn update still denied'                    'firn update'

# --- the compliant move itself must never be denied ---
expect_allow 'north rebuild request is allowed'                 'north rebuild request --why "flip probe"'
expect_allow 'north rebuild request --urgent is allowed'        'north rebuild request --why "x" --urgent "cannot wait"'
expect_allow 'north rebuild list is allowed'                    'north rebuild list'
expect_allow 'firn build is allowed'                            'firn build'
expect_allow 'firn validate is allowed'                         'firn validate'
expect_allow 'firn update --dry-run is allowed'                 'firn update --dry-run'
expect_allow 'firn-rebuild-impact is allowed'                   'firn-rebuild-impact'
# Mentions are not invocations: the anchor is what keeps docs writable.
expect_allow 'echoing the denied string is allowed'             'echo "never run firn rebuild directly"'
expect_allow 'grepping for the denied string is allowed'        'rg "firn rebuild" docs/'

# KNOWN and deliberate: a markdown code span is two backticks, and so is command
# substitution. Prose in a heredoc is denied; the deny text names the way out.
prose_out="$(run_guard 'git commit -F - <<MSG
`firn rebuild` is denied for agents.
MSG')"
if jq -e '.hookSpecificOutput.permissionDecisionReason | contains("git commit -F <file>")' <<<"$prose_out" >/dev/null 2>&1; then
  pass=$((pass + 1))
  printf 'PASS  backticked prose is denied but taught the file-path escape\n'
else
  fail=$((fail + 1))
  printf 'FAIL  backticked prose deny lost its escape — got: %s\n' "$prose_out" >&2
fi

printf '\nfirn-guard.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
