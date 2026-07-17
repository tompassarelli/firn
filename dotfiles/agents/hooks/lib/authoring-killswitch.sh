# shellcheck shell=bash
# authoring-killswitch.sh — the ONE implementation of the authoring-guard
# kill-switch. Sourced by every guard hook AND by north config, so the
# report and the enforcement can never disagree.
#
# Effective state, in precedence order (explicit session env beats state):
#   AGENT_NO_AUTHORING_HOOKS = anything but 0/false/empty   → guards OFF (this session)
#   AGENT_NO_AUTHORING_HOOKS = 0|false                      → guards LIVE (force-live, state ignored)
#   CLAUDE_NO_AUTHORING_HOOKS remains a compatibility alias.
#   unset/empty → state file decides: `guards=off` → guards OFF, else LIVE
#
# Persistent flip (all sessions, takes effect immediately — hooks re-read
# state on every call, no relaunch): `north config guards on|off`.
# The env var remains the launch-time override for a single pinned session:
#   AGENT_NO_AUTHORING_HOOKS=1 claude   # or codex
# Canonical persistent state is provider-neutral:
#   ~/.local/state/north/harness.conf
# A pre-migration ~/.claude/my-config.state is read only when canonical state is
# absent. Tests may override via NORTH_HARNESS_STATE; the older
# AUTHORING_KILLSWITCH_STATE test seam remains compatible.

north_harness_state_path() {
  if [ -n "${NORTH_HARNESS_STATE:-}" ]; then
    printf '%s\n' "$NORTH_HARNESS_STATE"
  elif [ -n "${AUTHORING_KILLSWITCH_STATE:-}" ]; then
    printf '%s\n' "$AUTHORING_KILLSWITCH_STATE"
  elif [ -f "$HOME/.local/state/north/harness.conf" ]; then
    printf '%s\n' "$HOME/.local/state/north/harness.conf"
  else
    printf '%s\n' "$HOME/.claude/my-config.state"
  fi
}

authoring_guards_off() {
  case "${AGENT_NO_AUTHORING_HOOKS:-${CLAUDE_NO_AUTHORING_HOOKS:-}}" in
    0|false) return 1 ;;
    ?*)      return 0 ;;
  esac
  [ "$(grep -E '^guards=' "$(north_harness_state_path)" 2>/dev/null | tail -1 | cut -d= -f2-)" = off ]
}
