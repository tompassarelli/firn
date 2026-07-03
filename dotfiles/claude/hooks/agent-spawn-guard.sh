#!/usr/bin/env bash
# PreToolUse agent-spawn-guard — enforcement half of the DISPATCH knob (see `my-config`).
# ============================================================================
# Successor of agent-redirect.sh (removed in the P6 hook cleanup, ae3b31e).
# Reinstated 2026-07-03: without a mechanical intercept, native catch-all
# spawns (general-purpose, serial, no claim trail) recurred — prose in
# CLAUDE.md demonstrably does not hold. Fires on subagent tool calls too,
# so nested native spawns are covered.
#
#   dispatch=tern   -> DENY native Agent/Task/Workflow; hand back the tern recipe
#   dispatch=warn   -> allow, inject a nudge (additionalContext)
#   dispatch=native -> allow silently
#
# State:       ~/.claude/my-config.state  (flip via `my-config dispatch <mode>`)
# Kill-switch: CLAUDE_NO_AUTHORING_HOOKS=1 (same as the other authoring guards)
# ============================================================================
set -uo pipefail

[ -n "${CLAUDE_NO_AUTHORING_HOOKS:-}" ] && exit 0

MODE=$(grep -E '^dispatch=' "$HOME/.claude/my-config.state" 2>/dev/null | tail -1 | cut -d= -f2-)
MODE="${MODE:-tern}"
[ "$MODE" = "native" ] && exit 0
export AGENT_SPAWN_GUARD_MODE="$MODE"

read -r -d '' PY <<'PYEOF' || true
import sys, json, os

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = data.get("tool_name", "")
if tool not in ("Agent", "Task", "Workflow"):
    sys.exit(0)

mode = os.environ.get("AGENT_SPAWN_GUARD_MODE", "tern")

recipe = (
    "Native " + tool + " is ephemeral — no claim trail, no steering, no observability. "
    "Do the SAME work on tern:\n"
    "  1. Trivial lookup / single file? No agent at all — bash/grep/read inline.\n"
    "  2. One job: mcp__tern__spawn {prompt, model, effort} (ad-hoc), or capture a "
    "thread + mcp__tern__dispatch (thread-driven posture).\n"
    "  3. Fan-out: N x mcp__tern__spawn in parallel; message workers via "
    "bb ~/code/tern/cli/msg-cli.clj 7977 send; observe via web :8088.\n"
    "  Caveman + model tier ride the SDK path (AGENT_CAVEMAN / AGENT_MODEL).\n"
    "Bypass deliberately: my-config dispatch warn|native (or /my-config)."
)

if mode == "warn":
    out = {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "additionalContext": "dispatch knob = warn. " + recipe,
    }}
else:
    out = {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "DENIED by dispatch knob (tern). " + recipe,
    }}

print(json.dumps(out))
sys.exit(0)
PYEOF

exec python3 -c "$PY"
