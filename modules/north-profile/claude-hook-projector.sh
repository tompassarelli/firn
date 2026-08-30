#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'north-claude-hook-projector: %s\n' "$*" >&2
  exit 1
}

[[ $# -eq 2 ]] || die 'usage: north-claude-hook-projector PROJECTION TARGET'

projection=$1
target=$2

case "$projection" in
  /nix/store/*) ;;
  *)
    [[ ${NORTH_CLAUDE_HOOKS_ALLOW_NONSTORE:-0} == 1 ]] ||
      die "projection must be generation-owned store content: $projection"
    ;;
esac
case "$target" in
  /*) ;;
  *) die "target must be absolute: $target" ;;
esac

CHMOD_BIN=${CHMOD_BIN:-chmod}
FLOCK_BIN=${FLOCK_BIN:-flock}
JQ_BIN=${JQ_BIN:-jq}
MKDIR_BIN=${MKDIR_BIN:-mkdir}
MV_BIN=${MV_BIN:-mv}
REALPATH_BIN=${REALPATH_BIN:-realpath}
RM_BIN=${RM_BIN:-rm}

[[ -f $projection && ! -L $projection ]] ||
  die "projection is not a regular file: $projection"
"$JQ_BIN" -e '
  type == "object"
  and keys == ["hooks"]
  and (.hooks | type == "object")
' "$projection" >/dev/null || die "projection is not a hooks-only JSON object: $projection"

parent=${target%/*}
[[ -n $parent && $parent != "$target" ]] ||
  die "target has no parent directory: $target"
"$MKDIR_BIN" -p -- "$parent"

parent_real=$("$REALPATH_BIN" -m -- "$parent")
case "$parent_real" in
  /nix/store|/nix/store/*)
    die "target parent is read-only store content: $parent_real"
    ;;
esac

umask 077
lock=$parent/.north-claude-hooks.lock
stage=$parent/.north-claude-hooks.tmp
exec 9>"$lock"
"$FLOCK_BIN" 9

[[ ! -L $target ]] || die "refusing to replace symlink target: $target"
[[ ! -e $target || -f $target ]] ||
  die "refusing to replace non-file target: $target"

"$RM_BIN" -f -- "$stage"
trap '"$RM_BIN" -f -- "$stage"' EXIT
if [[ -e $target ]]; then
  # The name below is jq's slurpfile binding.
  # shellcheck disable=SC2016
  "$JQ_BIN" --slurpfile projection "$projection" '
    if type != "object" then
      error("Claude settings must be a JSON object")
    else
      .hooks = $projection[0].hooks
    end
  ' "$target" >"$stage"
else
  # The name below is jq's slurpfile binding.
  # shellcheck disable=SC2016
  "$JQ_BIN" -n --slurpfile projection "$projection" '$projection[0]' >"$stage"
fi
"$JQ_BIN" -e 'type == "object" and (.hooks | type == "object")' "$stage" >/dev/null
"$CHMOD_BIN" 0600 "$stage"
"$MV_BIN" -fT -- "$stage" "$target"
trap - EXIT

[[ -f $target && ! -L $target && -w $target ]] ||
  die "runtime settings did not become a writable regular file: $target"
