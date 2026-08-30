#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
source_file=$repo/modules/north-profile/default.bnix
generated_file=$repo/modules/north-profile/default.nix
firn_skill=$repo/modules/north-profile/firn/skills/firn-distilled/SKILL.md
checker=$repo/scripts/agent-config-check.sh
claude_projection=$repo/modules/north-profile/claude-hooks.json
claude_projector=$repo/modules/north-profile/claude-hook-projector.sh
catalog=$repo/dotfiles/agents/catalog-config.json

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

grep -Fq 'name: firn-distilled' "$firn_skill"
grep -Fq 'modules/north-profile/default.bnix' "$checker"
grep -Fq 'projectNorthClaudeHooks' "$source_file"
grep -Fq 'projectNorthClaudeHooks' "$generated_file"

jq -e '
  [
    .hooks[] | .[] | .hooks[] | select(.type == "command") | .command
  ] as $commands
  | ($commands | length == 9)
    and ($commands | all(
      contains("NORTH_AGENT_PYTHON=/etc/codex/hooks/runtime/python3")
      and contains("PATH=/etc/codex/hooks/runtime:/home/tom/.local/bin:/run/current-system/sw/bin")
    ))
    and ([
      $commands[] | select(contains("firn-system-policy"))
    ] | length == 2)
    and ([
      $commands[] | select(contains("firn-system-policy"))
    ] | all(
      contains("/home/tom/.local/lib/firn/cli/current/bin/firn-system-policy")
      and (contains("/run/current-system/sw/bin/firn-system-policy") | not)
    ))
' "$claude_projection" >/dev/null

for unit in \
  beagle-session-start \
  corpus-scan-guard \
  firn-system-policy \
  git-blind-stage-guard \
  launch-critical-worktree-guard \
  session-kill-guard \
  tripwire-guard; do
  jq -e --arg unit "$unit" '
    any(.activation[$unit].distributions[]; .targets | index("claude"))
  ' "$catalog" >/dev/null
done

scratch=$(mktemp -d "${TMPDIR:-/tmp}/north-claude-hooks-test.XXXXXX")
trap 'rm -r -- "$scratch"' EXIT
target=$scratch/home/.claude/settings.json
mkdir -p "${target%/*}"
printf '%s\n' '{
  "model": "preserved-model",
  "permissions": {"allow": ["Read"]},
  "hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "/run/current-system/sw/bin/firn-system-policy"}]}]}
}' >"$target"

run_projector() {
  NORTH_CLAUDE_HOOKS_ALLOW_NONSTORE=1 \
  CHMOD_BIN=$(command -v chmod) \
  FLOCK_BIN=$(command -v flock) \
  JQ_BIN=$(command -v jq) \
  MKDIR_BIN=$(command -v mkdir) \
  MV_BIN=$(command -v mv) \
  REALPATH_BIN=$(command -v realpath) \
  RM_BIN=$(command -v rm) \
    "$claude_projector" "$claude_projection" "$1"
}

run_projector "$target"
jq -e --slurpfile projection "$claude_projection" '
  .model == "preserved-model"
  and .permissions == {"allow": ["Read"]}
  and .hooks == $projection[0].hooks
' "$target" >/dev/null
[[ $(stat -c '%a' "$target") == 600 ]]

first_digest=$(sha256sum "$target")
run_projector "$target"
[[ $(sha256sum "$target") == "$first_digest" ]]

fresh=$scratch/fresh/.claude/settings.json
run_projector "$fresh"
jq -e --slurpfile projection "$claude_projection" '. == $projection[0]' \
  "$fresh" >/dev/null

invalid=$scratch/invalid/.claude/settings.json
mkdir -p "${invalid%/*}"
printf '%s\n' '{not-json' >"$invalid"
invalid_digest=$(sha256sum "$invalid")
if run_projector "$invalid" >/dev/null 2>&1; then
  printf 'invalid Claude settings unexpectedly projected\n' >&2
  exit 1
fi
[[ $(sha256sum "$invalid") == "$invalid_digest" ]]

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
