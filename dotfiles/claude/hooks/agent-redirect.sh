#!/usr/bin/env bash
# PreToolUse agent-redirect — intercept raw Agent/Workflow and REDIRECT to lodestar agents.
# ============================================================================
# Denies the ephemeral Agent/Workflow call, then hands back the exact lodestar
# recipe to accomplish the SAME work on the persistent, role-based, observable
# (lodestar web :8088), steerable substrate.
#
# Raw Agent/Workflow are one-shot, unobservable, un-steerable, leave no claim
# trail. Lodestar agents are the default engine — this redirect tells the model
# how to switch engines, not to give up.
#
# Kill-switch: CLAUDE_NO_AUTHORING_HOOKS=1 disables this.
# Per-session bypass: touch ~/.claude/agent-redirect.off (via /agent-redirect off).
# ============================================================================
set -uo pipefail

[ -n "${CLAUDE_NO_AUTHORING_HOOKS:-}" ] && exit 0
[ -f "$HOME/.claude/agent-redirect.off" ] && exit 0

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
    "REDIRECTED: raw " + tool + " is ephemeral and bypasses lodestar's agent "
    "substrate (no roles, no observability, no steering, no claim trail). Do the "
    "SAME work via lodestar instead:\n"
    "  1. Trivial lookup / single file? No agent at all — bash/grep/read inline.\n"
    "  2. One delegated job? Spawn a worker and steer it:\n"
    "       ~/code/fleet-data/spawn-agent.sh <role>\n"
    "       ~/code/lodestar/fleet/cli/msg-cli.clj 7978 send <you> <role> \"<task>\"\n"
    "     AGENT_LIFECYCLE=ephemeral for one-and-discard; standing (default) to reuse context.\n"
    "  3. Fan-out? Spawn N role-holders, fan work out with msg-cli send, collect via inbox.\n"
    "  Observe: lodestar web :8088. Coordinate: claims on :7978. Work queue: lodestar :7977.\n"
    "To bypass deliberately (e.g. ultracode Workflow): /agent-redirect off."
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
