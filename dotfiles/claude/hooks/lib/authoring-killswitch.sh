# shellcheck shell=bash
# authoring-killswitch.sh — the ONE implementation of the authoring-guard
# kill-switch. Sourced by every guard hook AND by north config, so the
# report and the enforcement can never disagree.
#
# Effective state, in precedence order (explicit session env beats state):
#   CLAUDE_NO_AUTHORING_HOOKS = anything but 0/false/empty  → guards OFF (this session)
#   CLAUDE_NO_AUTHORING_HOOKS = 0|false                     → guards LIVE (force-live, state ignored)
#   unset/empty → state file decides: `guards=off` → guards OFF, else LIVE
#
# Persistent flip (all sessions, takes effect immediately — hooks re-read
# state on every call, no relaunch): `north config guards on|off`.
# The env var remains the launch-time override for a single pinned session:
#   CLAUDE_NO_AUTHORING_HOOKS=1 claude
# Tests override the state path via AUTHORING_KILLSWITCH_STATE.

authoring_guards_off() {
  case "${CLAUDE_NO_AUTHORING_HOOKS:-}" in
    0|false) return 1 ;;
    ?*)      return 0 ;;
  esac
  [ "$(grep -E '^guards=' "${AUTHORING_KILLSWITCH_STATE:-$HOME/.claude/my-config.state}" 2>/dev/null | tail -1 | cut -d= -f2-)" = off ]
}
