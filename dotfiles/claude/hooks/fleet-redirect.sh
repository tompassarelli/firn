#!/usr/bin/env bash
# PreToolUse fleet-redirect — intercept raw Agent/Workflow and REDIRECT to the fleet.
# ============================================================================
# This is not a dumb wall. It denies the ephemeral Agent/Workflow call, then
# hands back the exact fleet recipe to accomplish the SAME work on the
# persistent, role-based, observable (framescope :8088), steerable substrate.
#
# Why redirect, not just block: raw Agent/Workflow are one-shot, unobservable,
# un-steerable, and leave no claim trail. The lodestar/fram fleet is the default
# engine — the redirect tells the model how to switch engines, not to give up.
#
# Kill-switch: CLAUDE_NO_AUTHORING_HOOKS=1 disables this (same as other guards).
# Per-session bypass: touch ~/.claude/fleet-redirect.off (via /fleet-redirect off).
# ============================================================================
set -uo pipefail

[ -n "${CLAUDE_NO_AUTHORING_HOOKS:-}" ] && exit 0

# Personal per-session toggle (see the /fleet-redirect command). The sentinel
# file bypasses this redirect so you can use raw Agent/Workflow (e.g. ultracode
# Workflow orchestration) without unsetting the global kill-switch.
# `/fleet-redirect off` creates it; `/fleet-redirect on` removes it.
[ -f "$HOME/.claude/fleet-redirect.off" ] && exit 0

read -r -d '' PY <<'PYEOF' || true
import sys, json

def allow():
    sys.exit(0)

try:
    data = json.load(sys.stdin)
except Exception:
    allow()

tool = data.get("tool_name", "")
if tool not in ("Agent", "Workflow"):
    allow()

reason = (
    "REDIRECTED: raw " + tool + " is ephemeral and bypasses the lodestar fleet "
    "substrate (no roles, no observability, no steering, no claim trail). Do the "
    "SAME work on the fleet instead:\n"
    "  1. Trivial lookup / single file? No agent at all — bash/grep/read inline.\n"
    "  2. One delegated job? Spawn a worker and steer it:\n"
    "       ~/code/fleet-data/spawn-agent.sh <role>        # mints @agent:<uuid>, holds the role\n"
    "       ~/code/lodestar/fleet/cli/msg-cli.clj 7978 send <you> <role> \"<subject>\" \"<task>\"\n"
    "     AGENT_LIFECYCLE=ephemeral for one-and-discard; standing (default) to reuse context.\n"
    "  3. Fan-out / parallel research? Spawn N role-holders (spawn-agent.sh takes\n"
    "     comma-separated roles, or call it N times), fan work out with msg-cli\n"
    "     `send`, then collect via `inbox`/`thread`. This replaces a Workflow's\n"
    "     parallel+barrier; you own the join.\n"
    "  Observe: framescope :8088. Coordinate: claims on :7978. Work queue: lodestar :7977.\n"
    "  Full lifecycle (spawn -> role/lease -> steer -> observe -> stop): "
    "~/code/fleet-data/RUNBOOK.md.\n"
    "To bypass deliberately (e.g. ultracode Workflow): /fleet-redirect off."
)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }
}))
sys.exit(0)
PYEOF

exec python3 -c "$PY"
