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
  if [[ -n "${NORTH_HARNESS_STATE:-}" ]]; then
    builtin printf '%s\n' "$NORTH_HARNESS_STATE"
  elif [[ -n "${AUTHORING_KILLSWITCH_STATE:-}" ]]; then
    builtin printf '%s\n' "$AUTHORING_KILLSWITCH_STATE"
  elif [[ -f "$HOME/.local/state/north/harness.conf" ]]; then
    builtin printf '%s\n' "$HOME/.local/state/north/harness.conf"
  else
    builtin printf '%s\n' "$HOME/.claude/my-config.state"
  fi
}

authoring_guards_off() {
  local line state_path state_value=''
  case "${AGENT_NO_AUTHORING_HOOKS:-${CLAUDE_NO_AUTHORING_HOOKS:-}}" in
    0|false) return 1 ;;
    ?*)      return 0 ;;
  esac
  state_path="$(north_harness_state_path)" || return 1
  [[ -r "$state_path" ]] || return 1
  while IFS= builtin read -r line; do
    case "$line" in
      guards=*) state_value="${line#guards=}" ;;
    esac
  done <"$state_path"
  [[ "$state_value" == off ]]
}
