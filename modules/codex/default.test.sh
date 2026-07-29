#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
source_file="$repo/modules/codex/default.bnix"
generated_file="$repo/modules/codex/default.nix"
config_file="$repo/dotfiles/codex/config.toml"
hooks_file="$repo/dotfiles/codex/hooks.json"

grep -Fq '{:source (s flakeRoot "/dotfiles/codex/config.toml")}' "$source_file"
grep -Fq '{:source (s flakeRoot "/dotfiles/codex/hooks.json")}' "$source_file"
grep -Fq '{:source (s inputs.north "/agent-profile/hooks/lib/harness-dial.sh")}' "$source_file"
grep -Fq '{:source (s inputs.north "/agent-profile/hooks/registry.tsv")}' "$source_file"
# These assertions intentionally match literal Nix interpolation syntax.
# shellcheck disable=SC2016
grep -Fq '".codex/config.toml".source = "${flakeRoot}/dotfiles/codex/config.toml";' "$generated_file"
# shellcheck disable=SC2016
grep -Fq '".codex/hooks.json".source = "${flakeRoot}/dotfiles/codex/hooks.json";' "$generated_file"
# shellcheck disable=SC2016
grep -Fq '"codex/hooks/lib/harness-dial.sh".source = "${inputs.north}/agent-profile/hooks/lib/harness-dial.sh";' "$generated_file"
# shellcheck disable=SC2016
grep -Fq '"codex/hooks/registry.tsv".source = "${inputs.north}/agent-profile/hooks/registry.tsv";' "$generated_file"
if rg -n \
  'mkOutOfStoreSymlink.*(config\.toml|hooks\.json)|code/nixos-config/dotfiles/codex/(config\.toml|hooks\.json)' \
  "$source_file" "$generated_file"; then
  printf 'Codex config delivery still depends on a mutable checkout path\n' >&2
  exit 1
fi

if [ -n "${CODEX_CONFIG_SOURCE:-}" ]; then
  config_source=$CODEX_CONFIG_SOURCE
else
  config_source=$(
    nix eval --raw \
      "$repo#nixosConfigurations.whiterabbit.config.home-manager.users.tom.home.file.\".codex/config.toml\".source"
  )
fi
if [ -n "${CODEX_HOOKS_SOURCE:-}" ]; then
  hooks_source=$CODEX_HOOKS_SOURCE
else
  hooks_source=$(
    nix eval --raw \
      "$repo#nixosConfigurations.whiterabbit.config.home-manager.users.tom.home.file.\".codex/hooks.json\".source"
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
hooks_source=$(assert_store_copy 'Codex hooks.json' "$hooks_file" "$hooks_source")

managed_hook_sources=$(
  nix eval --json \
    "$repo#nixosConfigurations.whiterabbit.config.environment.etc" \
    --apply 'etc: builtins.mapAttrs (_: value: builtins.toString value.source) {
      authoring = etc."codex/hooks/lib/authoring-killswitch.sh";
      harnessDial = etc."codex/hooks/lib/harness-dial.sh";
      registry = etc."codex/hooks/registry.tsv";
      spawnGuard = etc."codex/hooks/agent-spawn-guard.sh";
    }'
)
python3 - "$managed_hook_sources" <<'PY'
import json
import pathlib
import sys

sources = {name: pathlib.Path(path) for name, path in json.loads(sys.argv[1]).items()}
assert all(str(path).startswith("/nix/store/") for path in sources.values())
assert sources["harnessDial"].parent == sources["authoring"].parent
assert sources["registry"].parent == sources["spawnGuard"].parent
PY

python3 - "$config_source" <<'PY'
import pathlib
import sys
import tomllib

with pathlib.Path(sys.argv[1]).open("rb") as handle:
    config = tomllib.load(handle)

assert config["model"] == "gpt-5.6-terra"
assert config["model_reasoning_effort"] == "medium"
assert config["mcp_servers"]["north"]["command"] == "/run/current-system/sw/bin/north-mcp"
assert config["mcp_servers"]["fram"]["command"] == "/run/current-system/sw/bin/fram-mcp"
PY

printf 'ok: Codex config.toml and legacy hooks.json are generation-retained store copies with no checkout delivery dependency\n'
printf 'ok: Codex keeps Terra/medium and immutable North/Fram MCP command paths\n'
printf 'ok: Codex hook dial resolver and registry are store-backed from the same North source as existing hooks\n'
