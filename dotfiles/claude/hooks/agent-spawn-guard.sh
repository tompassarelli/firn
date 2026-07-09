#!/usr/bin/env bash
# PreToolUse agent-spawn-guard — enforcement half of the /my-agent-config dispatch setting.
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
# State:       ~/.claude/my-config.state  (flip via `my-agent-config dispatch <mode>`)
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
ti = data.get("tool_input", {}) or {}

# gaffer squad role -> tern spawn dials. CANONICAL source is gaffer's RECIPES
# (~/code/gaffer/scripts/build-agents.mjs, which also generates the tern-adapter
# doctrine block docs/adapters/tern.md); duplicated here for enforcement because
# a PreToolUse hook can't import from the plugin. Keep the two in sync.
# The five praxis roles map to a tern `role` block; the read-only tiers
# (analyst / verifier / judge) have no tern role block, so they pin
# model+effort+posture and carry the role in-prompt.
ROLE_MAP = {
    "executor":    {"model": "sonnet", "effort": "low",    "role": "executor",    "posture": "deliver"},
    "implementer": {"model": "sonnet", "effort": "medium", "role": "implementer", "posture": "deliver"},
    "integrator":  {"model": "opus",   "effort": "high",   "role": "integrator",  "posture": "deliver"},
    "designer":    {"model": "opus",   "effort": "xhigh",  "role": "designer",    "posture": "explore"},
    "researcher":  {"model": "sonnet", "effort": "low",    "role": "researcher",  "posture": "explore"},
    "analyst":     {"model": "opus",   "effort": "high",                          "posture": "explore"},
    "verifier":    {"model": "opus",   "effort": "high",                          "posture": "explore"},
    "judge":       {"model": "opus",   "effort": "high",                          "posture": "explore"},
}

def tern_call(d):
    parts = ['model:"%s"' % d["model"], 'effort:"%s"' % d["effort"]]
    if "role" in d:
        parts.append('role:"%s"' % d["role"])
    parts.append('posture:"%s"' % d["posture"])
    parts.append("prompt:<your same prompt, verbatim>")
    return "mcp__tern__spawn { " + ", ".join(parts) + " }"

# Was this a gaffer squad pick? If so, translate it to the EXACT tern call so
# recovery is a single paste — no re-deriving role->dials by hand every time.
subagent = ""
if tool in ("Agent", "Task"):
    subagent = ti.get("subagent_type") or ti.get("subagentType") or ""
role_key = subagent.split(":")[-1].strip().lower() if subagent else ""

if role_key in ROLE_MAP:
    recipe = (
        "Native " + tool + " (" + subagent + ") is ephemeral — no claim trail, "
        "no steering, no observability. Re-issue the SAME work on tern; dials are "
        "already resolved for gaffer:" + role_key + " — just paste your prompt in:\n"
        "  " + tern_call(ROLE_MAP[role_key]) + "\n"
        "Fan-out? fire one mcp__tern__spawn per lane in the same turn. "
        "Observe: web :8088. Deliberate bypass: my-agent-config dispatch warn|native."
    )
else:
    where = subagent or tool
    recipe = (
        "Native " + tool + " (" + where + ") is ephemeral — no claim trail, no "
        "steering, no observability. Do the SAME work on tern:\n"
        "  1. Trivial lookup / single file? No agent at all — bash/grep/read inline.\n"
        "  2. One job: mcp__tern__spawn {prompt, model, effort} (pick dials by task "
        "shape), or capture a thread + mcp__tern__dispatch (thread-driven posture).\n"
        "  3. Fan-out: N x mcp__tern__spawn in parallel; message workers via "
        "bb ~/code/tern/cli/msg-cli.clj 7977 send; observe via web :8088.\n"
        "  Caveman + model tier ride the SDK path (AGENT_CAVEMAN / AGENT_MODEL).\n"
        "Bypass deliberately: my-agent-config dispatch warn|native (or /my-config)."
    )

if mode == "warn":
    out = {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "additionalContext": "/my-agent-config dispatch = warn. " + recipe,
    }}
else:
    out = {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "DENIED by /my-agent-config dispatch setting (tern). " + recipe,
    }}

print(json.dumps(out))
sys.exit(0)
PYEOF

exec python3 -c "$PY"
