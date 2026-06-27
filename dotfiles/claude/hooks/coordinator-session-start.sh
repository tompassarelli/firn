#!/usr/bin/env bash
# SessionStart hook (global) — inject role-appropriate operating posture.
# ============================================================================
# COMPOSITIONAL MODEL: coordinator is a ROLE, not an identity.
#   - AGENT_ROLES contains "coordinator" → coordinator posture
#   - AGENT_ROLES empty (root session) → implicit coordinator posture
#   - AGENT_ROLES set without "coordinator" → worker posture
#
# Kill-switch: CLAUDE_NO_AUTHORING_HOOKS=1
set -uo pipefail

[ -n "${CLAUDE_NO_AUTHORING_HOOKS:-}" ] && exit 0

settings="$HOME/.claude/settings.json"

effort="unknown"
if [ -r "$settings" ]; then
  e="$(python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("effortLevel","unknown"))
except Exception:
    print("unknown")' "$settings" 2>/dev/null)"
  [ -n "$e" ] && effort="$e"
fi

if [ -f "$HOME/.claude/agent-redirect.off" ]; then
  redirect="OFF (raw Agent/Workflow allowed — bypass sentinel present)"
else
  redirect="ON (raw Agent/Workflow is redirected to lodestar agents)"
fi

# ── Does this agent hold the coordinator role? ──
has_coordinator() {
  [ -z "${AGENT_ROLES:-}" ] && return 0
  echo ",${AGENT_ROLES}," | grep -q ",coordinator,"
}

if has_coordinator; then
  posture="You are the layer-0 coordinator — the single root of this session's work DAG (no title, just depth 0). Substantial task -> decompose and delegate to the persistent agent pool (~/code/fleet-data/spawn-agent.sh, address agents by role, coordinate via lodestar :7977/:7978); don't grind multi-part work solo. You own each sub-agent's lifecycle: standing (persists, reusable context) vs ephemeral (one job, then discard). Past depth 1, teams coordinate peer-to-peer (msg-cli + the claim graph). Trivial / conversational / single-fact turn -> just answer. The agent pool is the default engine — persistent, observable (lodestar web :8088), steerable — not Anthropic's ephemeral Agent/Workflow. Coordinator tier: effortLevel=${effort}; Agent/Workflow redirect ${redirect}. EDIT GUARD: coordinator-edit-guard.sh enforces single-file scope — you can do one-file atomic edits directly, but touching a second file within 10 min triggers the guard. Multi-file work = spawn agents. Bypass: touch ~/.claude/coordinator-edit.once"
else
  posture="You are a lodestar worker agent (roles: ${AGENT_ROLES}). Execute your assigned task directly — read files, edit code, run commands. You are NOT a coordinator; do not decompose or delegate further unless the task is genuinely too large for one agent. Do the work, report results. effortLevel=${effort}."
fi

python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$posture"
exit 0
