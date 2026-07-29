#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
source_file=$repo/modules/north-profile/default.bnix
generated_file=$repo/modules/north-profile/default.nix
firn_skill=$repo/modules/north-profile/firn/skills/firn/SKILL.md
checker=$repo/scripts/agent-config-check.sh

grep -Fq '"/.local/state/north/skills"' "$source_file"
grep -Fq '/.local/state/north/skills";' "$generated_file"
grep -Fq '"/.agents/skills"' "$repo/modules/claude/default.bnix"
grep -Fq '/.agents/skills";' "$repo/modules/claude/default.nix"

if rg -n '/code/north/main/(agent-profile|profiles/tom)/skills' \
  "$source_file" "$generated_file"; then
  printf 'Home Manager still wires ~/.agents/skills directly to the source profile\n' >&2
  exit 1
fi

grep -Fq 'category: nixos' "$firn_skill"
grep -Fq 'modules/north-profile/default.bnix' "$checker"
grep -Fq 'LIVE_SKILLS_FARM=' "$checker"

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

agents_source=$(
  realized_source \
    "$flake#nixosConfigurations.whiterabbit.config.home-manager.users.tom.home.file.\".agents/skills\".source"
)
claude_source=$(
  realized_source \
    "$flake#nixosConfigurations.whiterabbit.config.home-manager.users.tom.home.file.\".claude/skills\".source"
)

[ -L "$agents_source" ]
[ "$(readlink "$agents_source")" = /home/tom/.local/state/north/skills ]
[ -L "$claude_source" ]
[ "$(readlink "$claude_source")" = /home/tom/.agents/skills ]

printf 'ok: evaluated Home Manager skills wiring follows stable agents→farm and Claude→agents chains\n'
