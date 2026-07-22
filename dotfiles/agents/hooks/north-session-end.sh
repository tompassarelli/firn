#!/usr/bin/env bash
# SessionEnd hook — deregister THIS agent from north on a clean session exit by
# marking its still-active concerns `done` (reach `landed`), so a peer's
# `concern ls` is instant-clean the moment the terminal closes.
#
# WHY reconstruct the id instead of reading a pidfile: the registrar
# The generation-owned north-on-spawn wrapper does NOT persist the agent id — it derives it
# deterministically as ${NORTH_AGENT_ID:-cc-<repo>-<session_id[:8]>} from the
# (NORTH_AGENT_ID primary; TERN_AGENT_ID accepted as transitional fallback)
# session_id + cwd that Claude Code also hands this hook on stdin. We mirror that
# derivation EXACTLY, so no spawn-side change (and no state file) is needed.
#
# Presence heartbeat death is handled elsewhere: it lapses on its own when the
# session process exits, and a separate change hides stale-heartbeat concerns from
# `concern ls` (that path covers crashes/kills). This hook only accelerates the
# CLEAN-exit case. Best-effort throughout: never block exit, never emit stdout.
set -uo pipefail

CONCERN="/run/current-system/sw/bin/concern"
[ -x "$CONCERN" ] || exit 0

# Claude Code delivers a JSON event on stdin; pull flat string fields without jq
# (jq is not on PATH in this hook environment) — same jget as north-on-spawn.
IN="$(cat 2>/dev/null || true)"
jget() { printf '%s' "$IN" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
cwd="$(jget cwd)"; [ -z "$cwd" ] && cwd="$PWD"
sid="$(jget session_id)"

REPO="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"
RN="$(basename "$REPO")"
ID="${NORTH_AGENT_ID:-${TERN_AGENT_ID:-cc-$RN-${sid:0:8}}}"
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
# SC2016: single quotes are DELIBERATE — $CONCERN/$ID/$AWKP must expand in the
# inner detached bash (they're exported), not here; and $0/$1 are awk fields.
# Owner match is "@<id> " (trailing space) — `concern ls` always space-delimits the
# owner token, and the anchor stops a hand-set agent-id pin that PREFIXES a peer's id
# from arming on the peer's header (which would mark a LIVE peer's concerns done).
# SC2089/SC2090: the double quotes ARE awk source, delivered intact via "$AWKP".
# shellcheck disable=SC2016,SC2089
AWKP='index($0,"@" a " "){p=1} p&&match($0,/concern-[0-9]+-[0-9a-f]+/){print substr($0,RSTART,RLENGTH);p=0}'
# shellcheck disable=SC2090
export CONCERN ID AWKP
# shellcheck disable=SC2016
setsid bash -c '
  timeout 10 "$CONCERN" ls 2>/dev/null \
    | awk -v a="$ID" "$AWKP" \
    | while IFS= read -r cid; do
        [ -n "$cid" ] && timeout 10 "$CONCERN" done "$cid" >/dev/null 2>&1 || true
      done
' >/dev/null 2>&1 </dev/null &

# Session-end flush of the transcript stream-sync (complements the systemd
# user timer — catches the tail of this session immediately instead of
# waiting up to 5min). Mechanical, zero-AI, budgeted at a few seconds; never
# block or fail this hook's exit.
timeout 5 /run/current-system/sw/bin/north-stream-sync >/dev/null 2>&1 || true

exit 0
