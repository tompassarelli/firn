#!/usr/bin/env bash
# Provider-neutral anti-rot check for the shared agent harness and its adapters.
# Default output is intentionally a small status report. Use --verbose for the
# individual assertions; failures always print their full diagnostic.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$REPO/dotfiles/agents"
CLAUDE="$REPO/dotfiles/claude"
CODEX="$REPO/dotfiles/codex"
LOCAL=0
VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --local) LOCAL=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    *) printf 'usage: %s [--local] [--verbose]\n' "$0" >&2; exit 2 ;;
  esac
done

fail=0
warn=0
details=()
ok_detail() { details+=("ok: $*"); }
note() { [ "$VERBOSE" -eq 0 ] || printf '  note: %s\n' "$*"; }
bad() { printf '  FAIL: %s\n' "$*" >&2; fail=$((fail + 1)); }
soft() { printf '  warn: %s\n' "$*" >&2; warn=$((warn + 1)); }
group() {
  local name="$1" summary="$2" before="$3"
  if [ "$fail" -eq "$before" ]; then printf '✓ %-13s %s\n' "$name" "$summary"
  else printf '✗ %-13s %s\n' "$name" "$summary" >&2; fi
  if [ "$VERBOSE" -eq 1 ]; then
    local line
    for line in "${details[@]}"; do printf '  %s\n' "$line"; done
  fi
  details=()
}
provider_group() {
  local name="$1" before="$2"
  shift 2
  if [ "$fail" -eq "$before" ]; then printf '✓ %s\n' "$name"
  else printf '✗ %s\n' "$name" >&2; fi
  local line
  for line in "$@"; do printf '  %s\n' "$line"; done
  if [ "$VERBOSE" -eq 1 ]; then
    for line in "${details[@]}"; do printf '    %s\n' "$line"; done
  fi
  details=()
}
need_json() {
  local file="$1" label="$2"
  if jq -e . "$file" >/dev/null 2>&1; then ok_detail "$label is valid JSON"
  else bad "$label is not valid JSON: $file"; return 1; fi
}
need_toml() {
  local file="$1" label="$2"
  if python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$file" >/dev/null 2>&1; then
    ok_detail "$label is valid TOML"
  else
    bad "$label is not valid TOML: $file"
    return 1
  fi
}
canonical_link() {
  local link="$1" expected="$2" label="$3"
  local got want
  got="$(readlink -f "$link" 2>/dev/null || true)"
  want="$(readlink -f "$expected" 2>/dev/null || true)"
  if [ -n "$got" ] && [ "$got" = "$want" ]; then ok_detail "$label → ${want#"$REPO"/}"
  else bad "$label resolves to '${got:-missing}', expected '$want'"; fi
}

printf 'agent harness check%s\n' "$([ "$LOCAL" -eq 1 ] && printf ' (local)' || true)"

# Shared constitution, skills, and executable hook implementations.
before=$fail
hook_count=0
if command -v shellcheck >/dev/null 2>&1; then
  while IFS= read -r hook; do
    hook_count=$((hook_count + 1))
    if output="$(shellcheck -S warning "$hook" 2>&1)"; then
      ok_detail "shellcheck ${hook##*/}"
    else bad "shellcheck ${hook##*/}:\n$output"; fi
  done < <(find "$SHARED/hooks" -maxdepth 1 -type f -name '*.sh' -print | sort)
else bad "shellcheck is required to lint shared hooks"; fi
skill_count=0
while IFS= read -r skill; do
  skill_count=$((skill_count + 1))
  if [ "$(head -n 1 "$skill")" = '---' ]; then ok_detail "${skill%/SKILL.md} has frontmatter"
  else soft "${skill#"$REPO"/} lacks SKILL.md frontmatter"; fi
done < <(find "$SHARED/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f -print | sort)
[ -s "$SHARED/AGENTS.md" ] && ok_detail "canonical AGENTS.md present" || bad "canonical AGENTS.md is missing or empty"
group shared "$hook_count hooks linted · $skill_count skills · canonical instructions" "$before"

# Validate a provider hook manifest. In-repo commands must resolve to the shared
# hook implementation. External North lifecycle hooks are strict on a local
# machine and informational in repository-only/CI mode.
validate_hooks() {
  local manifest="$1" provider="$2"
  local count=0 ev command first resolved expected
  while IFS=$'\t' read -r ev command; do
    [ -n "$command" ] || continue
    count=$((count + 1)); first="${command%% *}"
    if [[ "$first" = /* ]]; then resolved="$(readlink -f "$first" 2>/dev/null || true)"
    else resolved="$(readlink -f "$SHARED/hooks/${first##*/}" 2>/dev/null || true)"; fi
    expected="$(readlink -f "$SHARED/hooks/${first##*/}" 2>/dev/null || true)"
    if [ -n "$expected" ] && [ "$resolved" = "$expected" ] && [ -x "$expected" ]; then
      ok_detail "$provider $ev → ${first##*/}"
    elif [[ "$first" = /home/tom/code/north/bin/* ]]; then
      if [ "$LOCAL" -eq 1 ]; then
        [ -x "$first" ] && ok_detail "$provider $ev → North ${first##*/}" || bad "$provider $ev external North hook missing/not executable: $first"
      else note "$provider $ev uses external North hook ${first##*/} (local check deferred)"; fi
    else bad "$provider $ev hook is missing, non-executable, or outside canonical hooks: $command"; fi
  done < <(jq -r '.hooks // {} | to_entries[] | .key as $event | .value[] | .hooks[]? | select(.type == "command") | [$event,.command] | @tsv' "$manifest")
  HOOK_BINDINGS="$count"
}

before=$fail
claude_north='connection deferred to --local'
claude_fram='connection deferred to --local'
claude_linear='connection deferred to --local'
need_json "$CLAUDE/settings.json" 'Claude settings'
if jq -e '.autoMemoryEnabled == false' "$CLAUDE/settings.json" >/dev/null; then ok_detail "auto-memory disabled"
else bad "Claude autoMemoryEnabled must be false"; fi
validate_hooks "$CLAUDE/settings.json" Claude
claude_bindings="$HOOK_BINDINGS"
if [ "$LOCAL" -eq 1 ]; then
  canonical_link "$HOME/.claude/settings.json" "$CLAUDE/settings.json" "$HOME/.claude/settings.json"
  canonical_link "$HOME/.claude/skills" "$SHARED/skills" "$HOME/.claude/skills"
  canonical_link "$HOME/.claude/hooks" "$SHARED/hooks" "$HOME/.claude/hooks"
  canonical_link "$HOME/.claude/CLAUDE.md" "$SHARED/AGENTS.md" "$HOME/.claude/CLAUDE.md"
  canonical_link "$HOME/.claude/commands" "$CLAUDE/commands" "$HOME/.claude/commands"
  if [ -f "$HOME/.claude.json" ]; then
    for server in fram north linear-mcp-msa-new; do
      jq -e --arg s "$server" '.mcpServers[$s]' "$HOME/.claude.json" >/dev/null || bad "Claude user MCP '$server' is missing"
    done
    extra="$(jq -r '.mcpServers | keys[] | select(. != "fram" and . != "north" and . != "linear-mcp-msa-new")' "$HOME/.claude.json")"
    [ -z "$extra" ] || bad "unexpected Claude user MCP server(s): ${extra//$'\n'/, }"
    fram_log="$(jq -r '.mcpServers.fram.env.FRAM_LOG // empty' "$HOME/.claude.json")"
    [[ "$fram_log" = *north* && "$fram_log" != *'/code/fram'* ]] || bad "Claude fram MCP is not pointed at the live North corpus: '${fram_log:-unset}'"
    project_count="$(jq '[.projects[]? | select(.mcpServers != null)] | length' "$HOME/.claude.json")"
    note "$project_count project-scoped Claude MCP registrations (allowed)"
    ok_detail "Claude MCP: north + fram live corpus + Linear"
  else bad "$HOME/.claude.json is missing"; fi
  if command -v claude >/dev/null 2>&1; then
    claude_mcp_output="$(claude mcp list 2>&1)" || bad "claude rejected its config while checking MCP health:\n$claude_mcp_output"
    for server in north fram linear-mcp-msa-new; do
      grep -Eq "^${server}:.*Connected" <<<"$claude_mcp_output" || bad "Claude MCP '$server' is missing or not connected:\n$claude_mcp_output"
    done
    claude_north='connected'
    claude_fram='connected'
    claude_linear='connected'
    ok_detail "Claude reports North + Fram + Linear MCP connected"
  else bad "claude CLI is missing from PATH"; fi
fi
provider_group Claude "$before" \
  "Hooks       $claude_bindings bindings" \
  'Bootstrap   config policy OK' \
  "MCP         North: $claude_north" \
  "            Fram: $claude_fram" \
  "            Linear: $claude_linear"

before=$fail
need_json "$CODEX/hooks.json" 'Codex hooks'
need_toml "$CODEX/config.toml" 'Codex config'
validate_hooks "$CODEX/hooks.json" Codex
codex_bindings="$HOOK_BINDINGS"
codex_north='declared; live probe deferred'
codex_fram='declared; live probe deferred'
codex_linear='auth probe deferred to --local'
grep -q '^\[mcp_servers\.north\]' "$CODEX/config.toml" || bad "Codex config does not declare North MCP"
grep -q '^\[mcp_servers\.fram\]' "$CODEX/config.toml" || bad "Codex config does not declare Fram MCP"
grep -q '^\[mcp_servers\.linear-mcp-msa-new\]' "$CODEX/config.toml" || bad "Codex config does not declare Linear MCP"
if [ "$LOCAL" -eq 1 ]; then
  canonical_link "$HOME/.codex/config.toml" "$CODEX/config.toml" "$HOME/.codex/config.toml"
  canonical_link "$HOME/.codex/hooks.json" "$CODEX/hooks.json" "$HOME/.codex/hooks.json"
  canonical_link "$HOME/.codex/AGENTS.md" "$SHARED/AGENTS.md" "$HOME/.codex/AGENTS.md"
  canonical_link "$HOME/.agents/skills" "$SHARED/skills" "$HOME/.agents/skills"
  if command -v codex >/dev/null 2>&1; then
    mcp_output="$(codex mcp list 2>&1)" || bad "codex rejected its config while listing MCPs:\n$mcp_output"
    for server in north fram linear-mcp-msa-new; do
      grep -Eq "^${server}[[:space:]]" <<<"$mcp_output" || bad "Codex MCP '$server' is missing/disabled"
    done
    linear_line="$(grep -E '^linear-mcp-msa-new[[:space:]]' <<<"$mcp_output" || true)"
    if [[ "$linear_line" = *'Not logged in'* ]]; then codex_linear='not logged in'
    elif [[ "$linear_line" = *OAuth* || "$linear_line" = *'Logged in'* ]]; then codex_linear='authenticated'
    else codex_linear='auth unknown'; fi
    ok_detail "Codex config parsed; North + Fram + Linear MCP listed"
    codex_north='enabled'
    codex_fram='enabled'
  else bad "codex CLI is missing from PATH"; fi
fi
provider_group Codex/OpenAI "$before" \
  "Hooks       $codex_bindings bindings" \
  'Bootstrap   config policy OK' \
  "MCP         North: $codex_north" \
  "            Fram: $codex_fram" \
  "            Linear: $codex_linear"

before=$fail
if [ "$LOCAL" -eq 1 ]; then
  if command -v north >/dev/null 2>&1; then
    provider_output="$(north providers 2>&1)" || bad "installed North provider readiness failed:\n$provider_output"
    grep -Eq '^anthropic[[:space:]]+ready' <<<"$provider_output" || bad "North reports Anthropic unavailable:\n$provider_output"
    grep -Eq '^openai[[:space:]]+ready' <<<"$provider_output" || bad "North reports OpenAI/Codex unavailable:\n$provider_output"
    grep -Eq '^auto[[:space:]]+(anthropic|openai)' <<<"$provider_output" || bad "North auto-route decision missing:\n$provider_output"
    auto_provider="$(awk '/^auto[[:space:]]/ { print $2; exit }' <<<"$provider_output")"
    ok_detail "$(tr '\n' ';' <<<"$provider_output" | sed 's/;$/ /; s/;/ · /g')"
  else bad "installed North CLI is missing from PATH"; fi
else ok_detail "provider readiness deferred to --local"; fi
if [ "$LOCAL" -eq 1 ]; then
  provider_group North "$before" \
    'Providers   Anthropic ready · OpenAI ready' \
    "Routing     auto→${auto_provider:-unknown}"
else
  provider_group North "$before" 'Providers   readiness deferred to --local'
fi

if [ "$fail" -ne 0 ]; then printf 'agent-config-check: FAILED\n' >&2; exit 1; fi
if [ "$warn" -gt 0 ]; then printf 'agent-config-check: passed with %s warning(s)\n' "$warn"
else printf 'agent-config-check: all green\n'; fi
