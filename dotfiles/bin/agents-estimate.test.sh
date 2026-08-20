#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "${test_root:?}"' EXIT

mkdir -p "$test_root/code/nixos-config" "$test_root/.claude/plugins"
ln -s "$repo" "$test_root/code/nixos-config/main"
printf '{}\n' > "$test_root/.claude/settings.json"
printf '{"plugins": {}}\n' > "$test_root/.claude/plugins/installed_plugins.json"

ag() {
  HOME=$test_root \
    AGENTS_FRAGMENTS=$repo/dotfiles/agents/hooks.d \
    AGENTS_MODULES=$repo/dotfiles/agents/modules.d \
    "$repo/dotfiles/bin/agents" "$@"
}

ag on estimate >/dev/null
test -L "$test_root/.config/agents/skills/estimate"
test -L "$test_root/.codex/skills/estimate"
test -r "$test_root/.codex/skills/estimate/agents/openai.yaml"
test "$(ag path estimate)" = "$test_root/code/nixos-config/main/dotfiles/agents/skills/estimate/SKILL.md"

ag off estimate >/dev/null
test ! -e "$test_root/.config/agents/skills/estimate"
test ! -e "$test_root/.codex/skills/estimate"

printf 'ok: estimate skill activates on both agent surfaces\n'
