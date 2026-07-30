#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
source_file="$repo/modules/codex/default.bnix"
generated_file="$repo/modules/codex/default.nix"
config_file="$repo/dotfiles/codex/config.toml"
hooks_file="$repo/dotfiles/codex/hooks.json"
requirements_file="$repo/modules/codex/requirements.toml"

grep -Fq '{:source (s flakeRoot "/dotfiles/codex/config.toml")}' "$source_file"
grep -Fq '{:source (s flakeRoot "/dotfiles/codex/hooks.json")}' "$source_file"
# These assertions intentionally match literal Nix interpolation syntax.
# shellcheck disable=SC2016
grep -Fq '".codex/config.toml".source = "${flakeRoot}/dotfiles/codex/config.toml";' "$generated_file"
# shellcheck disable=SC2016
grep -Fq '".codex/hooks.json".source = "${flakeRoot}/dotfiles/codex/hooks.json";' "$generated_file"

python3 - "$requirements_file" "$source_file" "$generated_file" <<'PY'
import pathlib
import re
import shlex
import sys
import tomllib

requirements_path, *module_paths = map(pathlib.Path, sys.argv[1:])
with requirements_path.open("rb") as handle:
    requirements = tomllib.load(handle)

managed_dir = requirements["hooks"]["managed_dir"].rstrip("/")


def commands(value):
    if isinstance(value, dict):
        command = value.get("command")
        if isinstance(command, str):
            yield command
        for nested in value.values():
            yield from commands(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from commands(nested)


required_paths = {
    token
    for command in commands(requirements["hooks"])
    for token in shlex.split(command)
    if token.startswith(f"{managed_dir}/")
}


def declared_paths(path):
    text = path.read_text()
    relative_paths = set(re.findall(r'"codex/hooks/([^"]+)"', text))
    relative_paths.update(
        re.findall(r'\(promoted\s+"([^"]+)"\s+"[^"]+"\)', text)
    )
    return {f"{managed_dir}/{relative}" for relative in relative_paths}


for module_path in module_paths:
    missing = sorted(required_paths - declared_paths(module_path))
    if missing:
        print(
            f"{module_path}: requirements reference unmanaged hook paths:",
            *missing,
            sep="\n  ",
            file=sys.stderr,
        )
        raise SystemExit(1)

print(
    f"ok: {len(required_paths)} requirements command paths have source and generated install declarations"
)
PY

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
