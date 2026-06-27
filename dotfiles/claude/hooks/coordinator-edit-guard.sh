#!/usr/bin/env bash
# PreToolUse (Edit|Write|MultiEdit) — role-based + task-aware edit guard.
# ============================================================================
# COMPOSITIONAL MODEL: coordinator is a ROLE, not an identity.
#   - AGENT_ROLES contains "coordinator" → has coordinator role
#   - AGENT_ROLES empty (root session) → implicit coordinator role
#   - AGENT_ROLES set without "coordinator" → worker, edits freely
#
# TASK-AWARE: coordinators CAN do single-file atomic work directly. Touching a
# second distinct file within a 10-minute window = composite work → blocked.
# The window resets after 10 min so separate trivial fixes don't accumulate.
#
# One-shot bypass: touch ~/.claude/coordinator-edit.once
# Reset window:    rm ~/.claude/coordinator-edit-state
# Kill-switch:     CLAUDE_NO_AUTHORING_HOOKS=1
# ============================================================================
set -uo pipefail

[ -n "${CLAUDE_NO_AUTHORING_HOOKS:-}" ] && exit 0

# ── Does this agent hold the coordinator role? ──
has_coordinator() {
  [ -z "${AGENT_ROLES:-}" ] && return 0
  echo ",${AGENT_ROLES}," | grep -q ",coordinator,"
}
has_coordinator || exit 0

# ── Parse target file path from tool input (JSON on stdin) ──
FILE_PATH="$(python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("tool_input", {}).get("file_path", ""))
except Exception:
    print("")
' 2>/dev/null)"
[ -z "$FILE_PATH" ] && exit 0

STATE="$HOME/.claude/coordinator-edit-state"
ONCE="$HOME/.claude/coordinator-edit.once"

# ── One-shot bypass (for genuine multi-file coordinator work like hook edits) ──
if [ -f "$ONCE" ]; then
  rm -f "$ONCE"
  echo "$FILE_PATH" > "$STATE"
  exit 0
fi

# ── Expire stale state (10 min window) ──
if [ -f "$STATE" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$STATE" 2>/dev/null || echo 0) ))
  [ "$age" -gt 600 ] && rm -f "$STATE"
fi

# ── First file in this window → allow, record it ──
if [ ! -f "$STATE" ]; then
  echo "$FILE_PATH" > "$STATE"
  exit 0
fi

# ── Same file → still single-file work, allow ──
PREV="$(cat "$STATE" 2>/dev/null)"
[ "$PREV" = "$FILE_PATH" ] && exit 0

# ── Different file → composite work. Block. ──
python3 -c "
import json, sys
prev = sys.argv[1]
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': (
            'MULTI-FILE EDIT BLOCKED: you already edited ' + prev + '. '
            'Touching a second file = composite work — delegate to lodestar agents.\n'
            '  1. Spawn:  ~/code/fleet-data/spawn-agent.sh <role>\n'
            '  2. Steer:  ~/code/lodestar/cli/msg-cli.clj 7978 send coordinator <role> \"<task>\"\n'
            '  3. Watch:  lodestar web :8088\n'
            '\n'
            'To force this edit:  touch ~/.claude/coordinator-edit.once\n'
            'To reset the window: rm ~/.claude/coordinator-edit-state'
        ),
    }
}))" "$PREV"
