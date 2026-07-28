#!/usr/bin/env bash
# Tests for launch-critical-worktree-guard.sh.
#
# The two properties that matter, in order:
#   1. It denies writes to the PRIMARY checkout of a launch-critical repo.
#   2. It never denies anything else — a guard that blocks ordinary work gets
#      switched off, and then it protects nothing. The worktree cases and the
#      ~/code/north-data sibling are the ones that would regress in practice.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/launch-critical-worktree-guard.sh"
pass=0 fail=0

# Guards are OFF in harness.conf on this machine, so every case forces them live
# with AGENT_NO_AUTHORING_HOOKS=0. That is the force-live value, not the
# disable value — see lib/authoring-killswitch.sh.
decide() {
  printf '{"tool_input":{"file_path":"%s"}}' "$1" \
    | AGENT_NO_AUTHORING_HOOKS=0 "$HOOK" 2>/dev/null
}

check() { # check <expect deny|allow> <path> <why>
  local want=$1 path=$2 why=$3 out got
  out="$(decide "$path")"
  case "$out" in
    *'"permissionDecision": "deny"'*|*'"permissionDecision":"deny"'*) got=deny ;;
    "") got=allow ;;
    *) got="malformed:$out" ;;
  esac
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  want=%s got=%s  %s\n      %s\n' "$want" "$got" "$path" "$why" >&2
  fi
}

# --- 1. primaries are denied -------------------------------------------------
check deny "$HOME/code/fram/coord_daemon.clj"      "fram primary: dirty tree makes north up refuse"
check deny "$HOME/code/north/cli/dashboard-cli.clj" "north primary"
check deny "$HOME/code/beagle/bin/beagle-build"     "beagle primary"
check deny "$HOME/code/nixos-config/flake.nix"      "nixos-config primary"
check deny "$HOME/code/fram"                        "the repo root itself, not only files under it"

# --- 2. the sanctioned destinations are NOT denied ---------------------------
check allow "$HOME/code/worktrees/fram/topic/coord_daemon.clj" "durable worktree is where agents are TOLD to work"
check allow "/tmp/north-lane-abc123/cli/x.clj"                 "managed lane worktree"
check allow "/tmp/fram-indexed-show-lane/bin/fram-fast.clj"    "ad-hoc lane worktree"

# --- 3. near-miss paths must not be swept in ---------------------------------
# north-data is a SIBLING of north; a naive prefix test without a separator
# check denies it and breaks all runtime-state writes.
check allow "$HOME/code/north-data/threads/x.md"   "north-data is runtime state, not the north repo"
check allow "$HOME/code/framework/x.clj"           "framework != fram"
check allow "$HOME/code/gjoa/x.clj"                "unrelated project"
check allow "/tmp/scratch.txt"                     "outside ~/code entirely"

# --- 4. fail-open ------------------------------------------------------------
check allow "" "empty file_path"
printf 'not json at all' | AGENT_NO_AUTHORING_HOOKS=0 "$HOOK" >/dev/null 2>&1 \
  && pass=$((pass + 1)) \
  || { fail=$((fail + 1)); echo "FAIL  malformed payload must exit 0" >&2; }

# --- 5. kill-switch ----------------------------------------------------------
out="$(printf '{"tool_input":{"file_path":"%s"}}' "$HOME/code/fram/x.clj" \
       | AGENT_NO_AUTHORING_HOOKS=1 "$HOOK" 2>/dev/null)"
if [ -z "$out" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL  AGENT_NO_AUTHORING_HOOKS=1 must disable the guard" >&2
fi

# --- 6. cost -----------------------------------------------------------------
# This fires on EVERY Edit/Write. An unconditional python3 start measured 4.6ms
# per call; the bash pre-filter must keep the common path well under that.
start=$(date +%s%N)
for _ in $(seq 50); do
  printf '{"tool_input":{"file_path":"/tmp/x.txt"}}' \
    | AGENT_NO_AUTHORING_HOOKS=0 "$HOOK" >/dev/null 2>&1
done
per_ms=$(( ( $(date +%s%N) - start ) / 50 / 1000000 ))
if [ "$per_ms" -le 25 ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL  allow path ${per_ms}ms/call — too slow for PreToolUse" >&2
fi

printf '%s\n' "launch-critical-worktree-guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
