# shellcheck shell=bash
# Shared authoring kill-switch entry point backed by North activation.

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

hook_error() {
  local hook_id="${NORTH_HOOK_ID:-${0##*/}}" file
  hook_id="${hook_id%.sh}"
  file="${AGENT_HOOK_ERRORS:-$HOME/.local/state/agents/hooks/errors.tsv}"
  mkdir -p -- "${file%/*}" 2>/dev/null
  { TZ=UTC0 printf '%(%Y-%m-%dT%H:%M:%SZ)T\t%s\t%s\n' -1 "$hook_id" "$1" >>"$file"; } 2>/dev/null
  return 0
}

# Deciders exit 65 for an unparsable payload; any failure allows, as Claude treats exit 1 as non-blocking.
hook_decide() {
  local out status
  out="$(printf '%s' "${payload-}" | "$@" 2>/dev/null)"
  status=$?
  case "$status" in
    0) [ -z "$out" ] || printf '%s\n' "$out" ;;
    1) hook_error decider-exception ;;
    65) hook_error unparsable-payload ;;
    126|127) hook_error missing-interpreter ;;
    *) hook_error "decider-exit-$status" ;;
  esac
  return 0
}
