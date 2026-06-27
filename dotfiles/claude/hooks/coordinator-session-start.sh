#!/usr/bin/env bash
# SessionStart hook (global) — inject the layer-0 coordinator operating posture.
# ============================================================================
# Deterministic, harness-enforced counterpart to the CLAUDE.md agent rules.
# Fires once per session, every project. Tells the agent it is the ROOT of this
# session's work DAG — decompose and delegate substantial work to lodestar's
# persistent agent pool rather than grinding solo.
#
# Kill-switch: CLAUDE_NO_AUTHORING_HOOKS=1 no-ops (parity with the other hooks).
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

posture="You are the layer-0 coordinator — the single root of this session's work DAG (no title, just depth 0). Substantial task -> decompose and delegate to the persistent agent pool (~/code/fleet-data/spawn-agent.sh, address agents by role, coordinate via lodestar :7977/:7978); don't grind multi-part work solo. You own each sub-agent's lifecycle: standing (persists, reusable context) vs ephemeral (one job, then discard). Past depth 1, teams coordinate peer-to-peer (msg-cli + the claim graph). Trivial / conversational / single-fact turn -> just answer. The agent pool is the default engine — persistent, observable (lodestar web :8088), steerable — not Anthropic's ephemeral Agent/Workflow. Coordinator tier: effortLevel=${effort}; Agent/Workflow redirect ${redirect}."

python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$posture"
exit 0
