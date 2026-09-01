# shellcheck shell=bash
# Shared authoring kill-switch entry point backed by North-v2 activation.

# shellcheck source=north-agent-activation.sh
. "${BASH_SOURCE[0]%/*}/north-agent-activation.sh"

authoring_guards_off() {
  local hook_id="${NORTH_HOOK_ID:-${0##*/}}"
  hook_id="${hook_id%.sh}"
  hook_id="${hook_id%.js}"
  case "${AGENT_NO_AUTHORING_HOOKS:-}" in
    0|false) return 1 ;;
    ?*) return 0 ;;
  esac
  north_agent_unit_active hook "$hook_id" || return 0
  return 1
}
