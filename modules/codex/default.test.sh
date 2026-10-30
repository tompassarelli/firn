#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
config_file="${CODEX_BASE_CONFIG:-$repo/dotfiles/codex/config.toml}"
context_file="$repo/modules/north-profile/context.json"

if [ -n "${CODEX_CONFIG_SOURCE:-}" ]; then
  config_source=$CODEX_CONFIG_SOURCE
else
  config_source=$(
    nix build --no-link --print-out-paths \
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
  if [ ! -f "$actual" ]; then
    printf '%s store copy does not match its generation source: %s\n' "$label" "$actual" >&2
    exit 1
  fi
  python3 - "$expected" "$actual" "$context_file" <<'PYTEST'
import json, pathlib, sys, tomllib
base, rendered, context_path = map(pathlib.Path, sys.argv[1:])
context = json.loads(context_path.read_text())
prefix = f"model_context_window = {min(context['window'], context['modelMaxContextWindow'])}\nmodel_auto_compact_token_limit = {context['autoCompactTokenLimit']}\n"
assert rendered.read_bytes() == prefix.encode() + base.read_bytes()
expected = tomllib.loads(base.read_text())
expected.update(model_context_window=min(context['window'], context['modelMaxContextWindow']), model_auto_compact_token_limit=context['autoCompactTokenLimit'])
assert tomllib.loads(rendered.read_text()) == expected
PYTEST
  printf '%s\n' "$actual"
}

config_source=$(assert_store_copy 'Codex config.toml' "$config_file" "$config_source")

printf 'ok: Codex config.toml is a generation-retained store copy\n'
