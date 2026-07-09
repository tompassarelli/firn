#!/usr/bin/env bash
# PreToolUse north-clock-guard — HARD-DENY billable client edits when no north
# clock is running. The forcing function for "never do billable work untracked."
# ============================================================================
# Prose in CLAUDE.md demonstrably did not hold: ~22h of MSA client work once
# shipped with ZERO north time logged, then had to be reconstructed by hand for an
# invoice. This makes untracked billable edits mechanically impossible instead of
# merely discouraged — the same reason agent-spawn-guard exists.
#
#   Edit/Write/MultiEdit whose target is under ~/code/client/**
#     AND no north clock running                      -> DENY (with a clock-in recipe)
#   any other path, or a clock IS running             -> allow
#   north unavailable (coordinator down / not installed)-> FAIL-OPEN (never lock you out)
#
# "Any running clock" satisfies the gate for v1 — the failure mode was NO clock at
# all. Tightening to "clock on a thread owned by THIS client" is a later refinement.
# Kill-switch: persistent `my-agent-config guards off` (state) OR env
# CLAUDE_NO_AUTHORING_HOOKS (any value but 0/false; 0/false forces guards live).
# Shared impl: lib/authoring-killswitch.sh.
# ============================================================================
set -uo pipefail

# Kill-switch: shared semantics in lib/authoring-killswitch.sh — persistent
# `my-agent-config guards off` (state, live) or env CLAUDE_NO_AUTHORING_HOOKS
# (any value but 0/false kills this session; 0/false forces guards live).
# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

IN="$(cat 2>/dev/null || true)"

# Target file path from tool_input (jq-free; python3 is on PATH per the other guards).
FP="$(printf '%s' "$IN" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
print((d.get("tool_input") or {}).get("file_path","") or "")' 2>/dev/null || true)"
[ -z "$FP" ] && exit 0
case "$FP" in /*) : ;; *) FP="$PWD/$FP" ;; esac      # relative -> absolute

# Only billable client work is gated.
case "$FP" in *"/code/client/"*) : ;; *) exit 0 ;; esac

NORTH="$HOME/code/north/bin/north"
[ -x "$NORTH" ] || exit 0                             # no north -> no gate (fail-open)

STATUS="$(timeout 6 "$NORTH" clock status 2>/dev/null || true)"
[ -z "$STATUS" ] && exit 0                            # unreadable (coord down) -> fail-open
# NOTE: "not clocked in" contains "clocked in" — test the negative FIRST.
case "$STATUS" in
  *"not clocked in"*) : ;;                            # fall through to DENY
  *"clocked in"*)     exit 0 ;;                        # a clock is running -> allow
  *)                  exit 0 ;;                        # unknown shape -> fail-open
esac

# ---- DENY. Best-effort: derive the Linear ticket from the branch and locate its
# thread, so recovery is one paste (the friction-kill layer). ------------------
REPO="$(git -C "$(dirname "$FP")" rev-parse --show-toplevel 2>/dev/null || true)"
BRANCH="$(git -C "${REPO:-$PWD}" branch --show-current 2>/dev/null || true)"
TICKET="$(printf '%s' "$BRANCH" | grep -oiE 'msa-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]' || true)"

if [ -n "$TICKET" ]; then
  LOG="${FRAM_LOG:-$HOME/.local/state/north/claims.log}"
  TID="$(sed -n "s/.*:l \"\(@[0-9a-f-]*\)\".*\"linear\".*\"$TICKET\".*/\1/p" "$LOG" 2>/dev/null | tail -1)"
  if [ -n "$TID" ]; then
    HINT="Thread for $TICKET exists — clock in:  north clock start ${TID#@}"
  else
    HINT="No thread for $TICKET yet:  north capture \"$TICKET <title>\" msa   then   north clock start <id>"
  fi
else
  HINT="Find/create the thread:  north ready  (or  north capture \"<title>\" msa ),  then  north clock start <id>"
fi

REASON="Billable client edit blocked — no north clock running. Client work is never done untracked (this gate exists because ~22h of MSA work once shipped with zero logged time and had to be reconstructed for an invoice). Start a clock, then retry the edit:
  ${HINT}
Deliberate bypass: my-agent-config guards off (persistent, live) — or a session launched with CLAUDE_NO_AUTHORING_HOOKS=1."

printf '%s' "$REASON" | python3 -c 'import sys,json
r=sys.stdin.read()
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":r}}))'
exit 0
