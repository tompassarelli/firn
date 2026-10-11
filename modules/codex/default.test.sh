#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
config_file="$repo/dotfiles/codex/config.toml"

if [ -n "${CODEX_CONFIG_SOURCE:-}" ]; then
  config_source=$CODEX_CONFIG_SOURCE
else
  config_source=$( 
    nix eval --raw \
      "$repo#nixosConfigurations.whiterabbit.config.home-manager.users.tom.home.file.\".codex/config.toml\".source"
  )
fi
assert_store_copy() {
  local label=$1 expected=$2 actual
  actual=$(readlink -f "$3")
  case "$actual" in
    /nix/store/*) ;;
    *)
      printf '%s is not store-backed: %s\n' "$label" "$actual" >&2
      exit 1
      ;;
  esac
  if [ ! -f "$actual" ] || ! cmp -s "$expected" "$actual"; then
    printf '%s store copy does not match its generation source: %s\n' "$label" "$actual" >&2
    exit 1
  fi
  printf '%s\n' "$actual"
}

config_source=$(assert_store_copy 'Codex config.toml' "$config_file" "$config_source")

printf 'ok: Codex config.toml is a generation-retained store copy\n'
