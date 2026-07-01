#!/usr/bin/env bash
# SessionEnd hook — deregister THIS agent from tern on a clean session exit by
# marking its still-active concerns `done` (reach `landed`), so a peer's
# `concern ls` is instant-clean the moment the terminal closes.
#
# WHY reconstruct the id instead of reading a pidfile: the registrar
# (~/code/tern/bin/tern-on-spawn) does NOT persist the agent id — it derives it
# deterministically as ${TERN_AGENT_ID:-cc-<repo>-<session_id[:8]>} from the
# session_id + cwd that Claude Code also hands this hook on stdin. We mirror that
# derivation EXACTLY, so no spawn-side change (and no state file) is needed.
#
# Presence heartbeat death is handled elsewhere: it lapses on its own when the
# session process exits, and a separate change hides stale-heartbeat concerns from
# `concern ls` (that path covers crashes/kills). This hook only accelerates the
# CLEAN-exit case. Best-effort throughout: never block exit, never emit stdout.
set -uo pipefail

CONCERN="$HOME/code/tern/bin/concern"
[ -x "$CONCERN" ] || exit 0

# Claude Code delivers a JSON event on stdin; pull flat string fields without jq
# (jq is not on PATH in this hook environment) — same jget as tern-on-spawn.
IN="$(cat 2>/dev/null || true)"
jget() { printf '%s' "$IN" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
cwd="$(jget cwd)"; [ -z "$cwd" ] && cwd="$PWD"
sid="$(jget session_id)"

REPO="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"
RN="$(basename "$REPO")"
ID="${TERN_AGENT_ID:-cc-$RN-${sid:0:8}}"
# No session id and no explicit override -> we'd only be guessing. Bail.
case "$ID" in ""|"cc-$RN-") exit 0 ;; esac

# Detach the network-bound cleanup (bb + board socket, possibly several `done`
# calls) into its OWN session so it survives this hook's process-group teardown
# and never delays the CLI's exit — same setsid pattern beagle-session-start.sh
# uses for the daemon revive. Each step is timeout-bounded and silenced.
#
# `concern ls` prints two lines per concern: a header line carrying the owner
# token (@<agent-id>) and a following `↳ … (concern-…)` line carrying the id.
# The awk state machine pairs them: arm on our token, emit the id on the next line.
AWKP='index($0,a){p=1} p&&match($0,/concern-[0-9]+-[0-9a-f]+/){print substr($0,RSTART,RLENGTH);p=0}'
export CONCERN ID AWKP
setsid bash -c '
  timeout 10 "$CONCERN" ls 2>/dev/null \
    | awk -v a="@$ID" "$AWKP" \
    | while IFS= read -r cid; do
        [ -n "$cid" ] && timeout 10 "$CONCERN" done "$cid" >/dev/null 2>&1 || true
      done
' >/dev/null 2>&1 </dev/null &

exit 0
