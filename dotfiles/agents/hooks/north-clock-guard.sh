#!/usr/bin/env bash
# Provider adapter for the billable-work clock admission core.
#
# The shared explicit authoring kill-switch remains shell-owned so every guard
# observes the same live state. Admission itself lives in
# north-clock-guard.py and is launched through either the exact Codex runtime
# or the root-managed system Python. Native Claude invokes this wrapper through
# an exact system Bash command in settings.json; the shebang is compatibility
# only.
set -uo pipefail

deny_unavailable() {
  builtin printf '%s\n' \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"billable_clock_guard_unavailable"}}'
  exit 0
}

SCRIPT_DIR="$(
  CDPATH='' builtin cd -- "${BASH_SOURCE[0]%/*}" 2>/dev/null &&
    builtin pwd -P
)" || deny_unavailable

# shellcheck disable=SC1090
builtin source "$SCRIPT_DIR/lib/authoring-killswitch.sh" 2>/dev/null ||
  deny_unavailable
authoring_guards_off && exit 0

# Dedicated clock-guard knob (tom, 2026-07-24): billing clock demoted to
# opt-in. First line "off" in the state file disables ONLY this guard;
# missing/other content leaves it active. Other guards unaffected.
# SDK managed-guard calls set NORTH_CLOCK_GUARD_ATTEST=1 and require a
# positive attestation — silence there is denied as unavailable, so the
# off branch must still emit {"northClockGuard":"not-applicable"}.
CLOCK_KNOB="${XDG_STATE_HOME:-${HOME:-}/.local/state}/north/clock-guard"
if [ -r "$CLOCK_KNOB" ]; then
  IFS= read -r CLOCK_KNOB_STATE < "$CLOCK_KNOB" || CLOCK_KNOB_STATE=""
  if [ "$CLOCK_KNOB_STATE" = "off" ]; then
    if [ "${NORTH_CLOCK_GUARD_ATTEST:-}" = "1" ]; then
      builtin printf '%s\n' '{"northClockGuard":"not-applicable"}'
    fi
    exit 0
  fi
fi

CORE="$SCRIPT_DIR/north-clock-guard.py"
[ -r "$CORE" ] || deny_unavailable

PYTHON="${NORTH_CLOCK_GUARD_PYTHON:-/run/current-system/sw/bin/python3}"
if [[ "$PYTHON" != /run/current-system/sw/bin/python3 &&
      ! "$PYTHON" =~ ^/nix/store/[a-z0-9]{32}-python3([^/]*)?/bin/python3([.][0-9]+)?$ ]]; then
  deny_unavailable
fi
[ -x "$PYTHON" ] || deny_unavailable

exec "$PYTHON" -I -S "$CORE"
