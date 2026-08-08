#!/usr/bin/env bash
# Materialize one committed Claude settings seed into writable runtime state.
# Each activation converges exactly; Claude owns the regular file between runs.
set -euo pipefail

die() {
  printf 'claude-settings-seed: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 2 ] || die 'usage: claude-settings-seed STORE_SEED TARGET'

seed="$1"
target="$2"

case "$seed" in
  /nix/store/*) ;;
  *)
    [ "${CLAUDE_SETTINGS_SEED_ALLOW_NONSTORE:-0}" = 1 ] ||
      die "seed must be generation-owned store content: $seed"
    ;;
esac
case "$target" in
  /*) ;;
  *) die "target must be absolute: $target" ;;
esac

INSTALL_BIN="${INSTALL_BIN:-install}"
MKDIR_BIN="${MKDIR_BIN:-mkdir}"
MV_BIN="${MV_BIN:-mv}"
REALPATH_BIN="${REALPATH_BIN:-realpath}"
RM_BIN="${RM_BIN:-rm}"
FLOCK_BIN="${FLOCK_BIN:-flock}"
JQ_BIN="${JQ_BIN:-jq}"

[ -f "$seed" ] && [ ! -L "$seed" ] || die "seed is not a regular file: $seed"
"$JQ_BIN" -e . "$seed" >/dev/null || die "seed is not valid JSON: $seed"

parent="${target%/*}"
[ -n "$parent" ] && [ "$parent" != "$target" ] ||
  die "target has no parent directory: $target"
"$MKDIR_BIN" -p -- "$parent"

parent_real="$("$REALPATH_BIN" -m -- "$parent")"
case "$parent_real" in
  /nix/store|/nix/store/*)
    die "target parent is read-only store content: $parent_real"
    ;;
esac

lock="$parent/.firn-settings-seed.lock"
stage="$parent/.firn-settings-seed.tmp"
exec 9>"$lock"
"$FLOCK_BIN" 9

# Symlinks (including the legacy checkout link) and regular runtime files are
# replaceable. Directories/devices/FIFOs fail closed rather than being clobbered.
if { [ -e "$target" ] || [ -L "$target" ]; } &&
   [ ! -L "$target" ] && [ ! -f "$target" ]; then
  die "refusing to replace non-file target: $target"
fi

# The exact stage name is ours. A SIGKILL before rename can leave it behind;
# holding the lock makes reclaim + restage safe and retryable.
"$RM_BIN" -f -- "${stage:?}"
"$INSTALL_BIN" -m 0600 -- "$seed" "$stage"
"$JQ_BIN" -e . "$stage" >/dev/null || die "staged settings are not valid JSON"
"$MV_BIN" -fT -- "$stage" "$target"

[ -f "$target" ] && [ ! -L "$target" ] && [ -w "$target" ] ||
  die "runtime settings did not become a writable regular file: $target"

# The seed is the all-off baseline; the switchboard layers enabled items back.
agents_cli="$HOME/code/nixos-config/main/dotfiles/bin/agents"
[ -x "$agents_cli" ] && "$agents_cli" apply || true
