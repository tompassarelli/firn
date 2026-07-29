#!/usr/bin/env bash
# PreToolUse guard — agents edit launch-critical repos in a worktree, never the
# primary checkout.
# ============================================================================
# STATUS: LIVE. Wired into settings.json (PreToolUse, Edit|Write|MultiEdit|Bash).
#
# BASH IS THE ENTRANCE THAT MATTERED (2026-07-29)
#   This guard was live and wired, and an agent still modified all three
#   launch-critical primaries: patching .clj files with `python3 - <<EOF`
#   heredocs, running git add/commit/reset --hard, and pushing from the primary.
#   It never fired, because it only inspected tool_input.file_path and a Bash
#   call carries tool_input.command. Enforcement on one door is not enforcement.
#
# WHY THIS EXISTS (observed 2026-07-29, not hypothetical)
#   `north up` refuses to launch on a tracked-dirty Fram checkout, deliberately:
#   a coordinator serving a half-edited engine is worse than one that refuses.
#   An agent left ten modified files in ~/code/fram. The coordinator therefore
#   could not restart, so a rebuilt closure could not be adopted, so a measured
#   200x performance fix sat built-but-unused while every `firn rebuild`
#   reported failure AFTER the build had already succeeded. One dirty primary
#   stalled the machine, and nothing had told that agent to work elsewhere.
#
#   Policy lives in ~/code/AGENTS.md ("Launch-critical repos"). A rule with no
#   enforcement is a suggestion, so enforcement lives here — PreToolUse is the
#   only event that can refuse a call before the write lands.
#
# SCOPE — deliberately narrow, and it must stay narrow
#   Denies ONLY a write whose realpath sits inside one of the PRIMARY checkouts
#   named in LAUNCH_CRITICAL below. Every other path returns empty stdout, which
#   the harness reads as "no opinion".
#
#   Worktrees are the sanctioned destination and must never be caught: a
#   worktree lives at ~/code/<project>/wt-<slug> and is carved out by name, so
#   the rule holds both today (checkout at ~/code/<project>) and after the move
#   to ~/code/<project>/main. Nothing to keep in sync, nothing to sequence.
#
#   The human is unaffected: they edit through their editor, not through the
#   harness's Edit/Write tools, so this code never runs for them.
#
# FAIL-OPEN
#   Missing python3, unreadable payload, unresolvable path, malformed JSON, or
#   any unexpected error -> print nothing, exit 0, edit proceeds. A guard that
#   blocks work when it is itself broken is worse than the leak it prevents.
#
# KILL-SWITCH (opt-out, consistent with the other authoring guards)
#   `north config guards off`, or launch with AGENT_NO_AUTHORING_HOOKS set to
#   anything but 0/false. Do NOT un-wire it from settings.json.
# ============================================================================
set -uo pipefail

# Drain stdin before any decision — an un-drained payload can block the writer.
payload=""
while :; do
  chunk=""
  IFS= read -r -N 65536 chunk
  status=$?
  [ -n "$chunk" ] && payload+="$chunk"
  [ "$status" -eq 0 ] || break
done

# Kill-switch — the shared implementation, so this guard can never disagree with
# what `north config guards` reports. Sourced, never shelled out to: this runs on
# EVERY Edit/Write, and a north CLI call here would re-create the 2.1s-per-tool
# hook cost that was removed on 2026-07-29.
# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

# Cheap bash pre-filter — this runs on EVERY Edit/Write, and a python3 start is
# ~4ms of interpreter boot that the overwhelmingly common case (a path in none
# of these repos) must not pay. Measured: 460ms/100 invocations with python
# unconditional, vs a substring test here.
#
# Safe because it only ever SKIPS work: if not one of these literals appears
# anywhere in the payload, no file_path under those roots can be present either,
# so the precise check below could not have denied. Worktree paths
# (~/code/worktrees/fram/...) do not contain "/code/fram", so they stay cheap too.
case "$payload" in
  */code/fram*|*/code/north*|*/code/beagle*|*/code/nixos-config*) ;;
  *) exit 0 ;;
esac

# A GITIGNORED path can never make the tree tracked-dirty, so it cannot cause
# either failure this guard exists to prevent: `north up` refuses on a
# tracked-dirty Fram checkout, and `firn rebuild` snapshots COMMITTED state.
# Blocking them bought nothing and cost real work — an agent could not write
# docs/private/ notes, which is where policy says internal notes must go.
#
# Runs only after the pre-filter has already matched one of the four repos, so
# the git call is off the common path. Fail-open: if git is unavailable or
# errors, fall through to the precise check below rather than admitting blindly.
if command -v git >/dev/null 2>&1; then
  _lc_path="$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print((json.load(sys.stdin).get("tool_input") or {}).get("file_path") or "")
except Exception: print("")' 2>/dev/null)"
  if [ -n "$_lc_path" ] && git -C "$(dirname "$_lc_path")" check-ignore -q "$_lc_path" 2>/dev/null; then
    exit 0
  fi
  unset _lc_path
fi

command -v python3 >/dev/null 2>&1 || exit 0

# The decision lives in lib/launch_critical_decide.py so it can be tested
# directly (launch-critical-worktree-guard.test.py) rather than through a
# heredoc. Fail-open on any error, as everywhere else in this guard.
printf '%s' "$payload" | python3 "$(dirname "$0")/lib/launch_critical_decide.py" 2>/dev/null || exit 0
exit 0
