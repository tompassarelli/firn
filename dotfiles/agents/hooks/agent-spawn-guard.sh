#!/usr/bin/env bash
# PreToolUse agent-spawn-guard — enforcement half of the north config dispatch setting.
# ============================================================================
# Successor of agent-redirect.sh (removed in the P6 hook cleanup, ae3b31e).
# Reinstated 2026-07-03: without a mechanical intercept, native catch-all
# spawns (general-purpose, serial, no claim trail) recurred — prose in
# CLAUDE.md demonstrably does not hold. Fires on subagent tool calls too,
# so nested native spawns are covered.
#
#   dispatch=north  -> DENY native Agent/Task/Workflow; hand back the north recipe
#   dispatch=warn   -> allow, inject a nudge (additionalContext)
#   dispatch=native -> allow silently
#
# State:       ~/.claude/my-config.state  (flip via `north config dispatch <mode>`)
# Kill-switch: persistent `north config guards off` (state) OR env
#              CLAUDE_NO_AUTHORING_HOOKS (any value but 0/false; 0/false forces
#              guards live). Shared impl: lib/authoring-killswitch.sh.
# ============================================================================
set -uo pipefail

# Kill-switch: shared semantics in lib/authoring-killswitch.sh — persistent
# `north config guards off` (state, live) or env CLAUDE_NO_AUTHORING_HOOKS
# (any value but 0/false kills this session; 0/false forces guards live).
# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

MODE=$(grep -E '^dispatch=' "$HOME/.claude/my-config.state" 2>/dev/null | tail -1 | cut -d= -f2-)
MODE="${MODE:-north}"
[ "$MODE" = "native" ] && exit 0
export AGENT_SPAWN_GUARD_MODE="$MODE"

read -r -d '' PY <<'PYEOF' || true
import sys, json, os, re

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = data.get("tool_name", "")
if tool not in ("Agent", "Task", "Workflow"):
    sys.exit(0)

mode = os.environ.get("AGENT_SPAWN_GUARD_MODE", "north")
ti = data.get("tool_input", {}) or {}

GAFFER_AGENTS = os.path.expanduser("~/code/gaffer/agents")
SAFE_ROLE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
ROUTING_COMMENT = re.compile(r"<!--\s*GAFFER_ROUTING\s+(\{.*?\})\s*-->")

def routing_for(invoked_role):
    """Read the generated adapter contract; never infer provider dials here."""
    if not SAFE_ROLE.fullmatch(invoked_role):
        return None
    path = os.path.join(GAFFER_AGENTS, invoked_role + ".md")
    try:
        with open(path, encoding="utf-8") as handle:
            match = ROUTING_COMMENT.search(handle.read())
        routing = json.loads(match.group(1)) if match else None
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None
    required = ("role", "taskGrade", "tier", "posture", "composition")
    if not isinstance(routing, dict) or any(key not in routing for key in required):
        return None
    if not all(isinstance(routing[key], str) for key in ("role", "taskGrade", "tier", "posture")):
        return None
    if not isinstance(routing["composition"], dict):
        return None
    return routing

def north_call(d):
    parts = ['provider:"auto"', 'tier:%s' % json.dumps(d["tier"])]
    parts.append('role:%s' % json.dumps(d["role"]))
    parts.append('posture:%s' % json.dumps(d["posture"]))
    parts.append('taskGrade:%s' % json.dumps(d["taskGrade"]))
    parts.append('composition:%s' % json.dumps(d["composition"], separators=(",", ":")))
    parts.append("prompt:<your same prompt, verbatim>")
    return "mcp__north__spawn { " + ", ".join(parts) + " }"

# Was this a gaffer squad pick? If so, translate it to the EXACT north call so
# recovery is a single paste — no re-deriving role->dials by hand every time.
subagent = ""
if tool in ("Agent", "Task"):
    subagent = ti.get("subagent_type") or ti.get("subagentType") or ""
is_gaffer = subagent.lower().startswith("gaffer:")
role_key = subagent.split(":", 1)[1].strip().lower() if is_gaffer else ""
routing = routing_for(role_key) if role_key else None

if routing:
    recipe = (
        "Native " + tool + " (" + subagent + ") is ephemeral — no claim trail, "
        "no steering, no observability. Re-issue the SAME work on north; dials are "
        "read from canonical gaffer:" + role_key + " metadata — just paste your prompt in:\n"
        "  " + north_call(routing) + "\n"
        "Fan-out? fire one mcp__north__spawn per lane in the same turn. "
        "Observe: web :8088. Deliberate bypass: north config dispatch warn|native."
    )
else:
    where = subagent or tool
    recipe = (
        "Native " + tool + " (" + where + ") is ephemeral — no claim trail, no "
        "steering, no observability. Do the SAME work on north:\n"
        "  1. Trivial lookup / single file? No agent at all — bash/grep/read inline.\n"
        "  2. One job: mcp__north__spawn {prompt, provider:\"auto\", tier, role, "
        "posture} (pick semantic tier by task shape), or capture a thread + "
        "mcp__north__dispatch (thread-driven posture).\n"
        "  3. Fan-out: N x mcp__north__spawn in parallel; message workers via "
        "bb ~/code/north/cli/msg-cli.clj 7977 send; observe via web :8088.\n"
        "  Provider resolution and concrete model selection belong to North.\n"
        "Bypass deliberately: north config dispatch warn|native (or /north-config)."
    )

if mode == "warn":
    out = {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "additionalContext": "north config dispatch = warn. " + recipe,
    }}
else:
    out = {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "DENIED by north config dispatch setting (north). " + recipe,
    }}

print(json.dumps(out))
sys.exit(0)
PYEOF

exec python3 -c "$PY"
