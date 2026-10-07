#!/usr/bin/env bash
# Codex behavior guard: UserPromptSubmit, PreToolUse(update_plan) and Stop.
# ============================================================================
# Turns the Codex overlay's worst recorded failures into checks Codex can't
# skip. A correction from Tom adds the correction rule as context. A plan step
# that adds reviews, soaks, attestation, compatibility or policy edits is
# rejected unless Tom's recent prompts asked for it, and a first plan must end
# with a checklist citing the profile, Done-when, extra checks and workers
# rules. An ending that asks permission, narrates the next step or lists what
# isn't proven is rejected once per turn. Decisions live in
# lib/codex_behavior.py; a missing interpreter or malformed input allows.
#
# Kill-switch: persistent `north config agents off codex-behavior-guard` OR env
# AGENT_NO_AUTHORING_HOOKS (any value but 0/false). Shared impl:
# lib/authoring-killswitch.sh.
# ============================================================================
set -uo pipefail

payload="$(head -c 1048576)"

authoring_killswitch="$(dirname "$0")/lib/authoring-killswitch.sh"
[ -r "$authoring_killswitch" ] \
  || authoring_killswitch="$(dirname "$0")/../lib/authoring-killswitch.sh"
# shellcheck disable=SC1090,SC1091
. "$authoring_killswitch" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

decider="$(dirname "$0")/lib/codex_behavior.py"
python_bin="${NORTH_AGENT_PYTHON:-python3}"
command -v -- "$python_bin" >/dev/null 2>&1 && [ -r "$decider" ] || exit 0
printf '%s' "$payload" | "$python_bin" "$decider" 2>/dev/null
exit 0
