#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
source_file=$repo/modules/north-profile/default.bnix
generated_file=$repo/modules/north-profile/default.nix
firn_skill=$repo/modules/north-profile/firn/skills/firn/SKILL.md
checker=$repo/scripts/agent-config-check.sh

for target in \
  instructions/shared/AGENTS.md \
  skills/shared \
  provider-hooks \
  instructions/code/AGENTS.md; do
  grep -Fq "\"/.local/state/north/agents/current/$target\"" "$source_file"
  grep -Fq "/.local/state/north/agents/current/$target\";" "$generated_file"
done
if rg -n 'agent-profile|\.config/agents|profiles/tom|\.agents/docs' \
  "$source_file" "$generated_file"; then
  printf 'Home Manager still declares a retired agent projection\n' >&2
  exit 1
fi

grep -Fq 'category: nixos' "$firn_skill"
grep -Fq 'modules/north-profile/default.bnix' "$checker"

nix_bin=${NIX_BIN:-nix}
flake="path:$repo"

realized_source() {
  local attribute=$1 evaluated built
  evaluated=$("$nix_bin" eval --raw "$attribute")
  built=$("$nix_bin" build --no-link --print-out-paths "$attribute")
  if [ "$evaluated" != "$built" ]; then
    printf 'evaluated source %s differs from focused build %s\n' \
      "$evaluated" "$built" >&2
    return 1
  fi
  printf '%s\n' "$built"
}

for spec in \
  '.agents/AGENTS.md|instructions/shared/AGENTS.md' \
  '.agents/skills|skills/shared' \
  '.agents/hooks|provider-hooks' \
  'code/AGENTS.md|instructions/code/AGENTS.md'; do
  home_file=${spec%%|*}
  target=${spec#*|}
  realized=$(
    realized_source \
      "$flake#nixosConfigurations.whiterabbit.config.home-manager.users.tom.home.file.\"$home_file\".source"
  )
  [ -L "$realized" ]
  [ "$(readlink "$realized")" = "/home/tom/.local/state/north/agents/current/$target" ]
done

printf 'ok: evaluated Home Manager agent wiring follows the current North generation\n'
