#!/usr/bin/env bash
# PreToolUse guard — block raw Agent/Workflow; all agent work goes through lodestar.
# ============================================================================
# The lodestar/fram fleet substrate is persistent, role-based, lease-gated,
# observable (framescope :8088), and steerable. Raw Agent/Workflow calls are
# ephemeral, unobservable, and un-steerable — they bypass the entire substrate.
#
# POLICY: hard-block both Agent and Workflow. No exceptions.
#   - Need parallel research? Spawn through lodestar fleet protocol.
#   - Need a quick lookup? Do it inline (bash/grep/read).
#   - There is no middle case where raw Agent is the right call.
#
# Kill-switch: CLAUDE_NO_AUTHORING_HOOKS=1 disables this (same as other guards).
# ============================================================================
set -uo pipefail

[ -n "${CLAUDE_NO_AUTHORING_HOOKS:-}" ] && exit 0

# Personal per-session toggle (see the /fleet-guard command). A sentinel file
# bypasses this guard so you can use raw Agent/Workflow (e.g. ultracode Workflow
# orchestration) without unsetting the global kill-switch. `/fleet-guard off`
# creates it; `/fleet-guard on` removes it.
[ -f "$HOME/.claude/fleet-guard.off" ] && exit 0

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
    "BLOCKED: raw Agent/Workflow bypasses the lodestar fleet substrate. "
    "All agent work goes through the protocol:\n"
    "  - Quick lookup? Do it inline (bash/grep/read). No agent needed.\n"
    "  - Real work? Spawn via ~/code/fleet-data/spawn-agent.sh <role> "
    "and steer with msg-cli.clj.\n"
    "  - Observe: framescope :8088. Coordinate: claims on :7978.\n"
    "  - Consult FLEET PLAYBOOK (lodestar thread 2026-06-22-232740) + "
    "~/code/fleet-data/RUNBOOK.md.\n"
    "Do NOT carve out exceptions for 'simple' agents — that is how doctrine erodes."
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
