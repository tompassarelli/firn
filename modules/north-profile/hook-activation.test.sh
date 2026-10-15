#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
north_bin=${NORTH_HOOK_CHECK_BIN:-$HOME/.local/share/north/bin/north}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/north-home-hook-activation.XXXXXX")
trap 'rm -r -- "$scratch"' EXIT
entry=$(nix eval --json "path:$repo#nixosConfigurations.whiterabbit.config.home-manager.users.tom.home.activation.validateNorthHookPaths")
jq -e '.before | index("writeBoundary") != null' <<<"$entry" >/dev/null
activation=$(jq -r '.data' <<<"$entry")
claude=$scratch/claude.json
codex=$scratch/requirements.toml
provider=$scratch/provider-hooks
mkdir -p "$provider" "$scratch/generations/41" "$scratch/generations/42" "$scratch/generations/43"
touch "$provider/present.sh"
ln -s generations/41 "$scratch/current"
printf '%s\n' '{"model":"preserved"}' >"$scratch/settings.json"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash /home/tom/.agents/hooks/present.sh"}]}]}}' >"$claude"
printf '%s\n' '[[hooks.Stop]]' '[[hooks.Stop.hooks]]' 'type = "command"' 'command = "bash /etc/codex/hooks/present.sh"' >"$codex"

run() {
  local -a args=("$@")
  local i
  args[0]=$north_bin
  for ((i=1; i<${#args[@]}; i++)); do
    case "${args[i]}" in
      --claude) args[i+1]=$claude ;;
      --codex) args[i+1]=$codex ;;
      --provider-hooks) args[i+1]=$provider ;;
    esac
  done
  "${args[@]}"
}
export -f run
next_generation=42
export activation north_bin claude codex provider scratch next_generation
activate() {
  bash -e -c 'eval "$activation"; ln -sfn "generations/$next_generation" "$scratch/current"; cp "$claude" "$scratch/settings.json"'
}
activate
next_generation=43
before=$(readlink "$scratch/current")
digest=$(sha256sum "$scratch/settings.json")
for registration in "$claude" "$codex"; do
  sed -i 's/present\.sh/missing.sh/g' "$registration"
  if activate >"$scratch/output" 2>&1; then
    printf 'home activation unexpectedly accepted missing hook in %s\n' "$registration" >&2
    exit 1
  fi
  cat "$scratch/output"
  rg -F 'missing.sh' "$scratch/output" >/dev/null
  rg -F "$registration" "$scratch/output" >/dev/null
  [[ $(readlink "$scratch/current") == "$before" ]]
  [[ $(sha256sum "$scratch/settings.json") == "$digest" ]]
  sed -i 's/missing\.sh/present.sh/g' "$registration"
done
printf 'ok: missing Claude and Codex hooks refused before home writes; generation before=%s after=%s\n' "$before" "$(readlink "$scratch/current")"
