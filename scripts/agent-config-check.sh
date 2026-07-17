#!/usr/bin/env bash
# Provider-neutral anti-rot check for the shared agent harness and its adapters.
# Default output is intentionally a small status report. Use --verbose for the
# individual assertions; failures always print their full diagnostic.
set -uo pipefail

gaffer_version_matches() {
  local version="$1" commit="$2"
  [ -n "$commit" ] &&
    { [ "$version" = "$commit" ] || [ "$version" = "${commit:0:12}" ]; }
}

# Classify cache freshness without treating an excluded feature checkout as an
# eligible plugin source. Tests source this file and exercise this pure seam.
classify_gaffer_cache() {
  local version="$1" checkout_head="$2" main_head="$3" branch="$4" dirty="$5"

  if [ "$branch" = main ]; then
    if gaffer_version_matches "$version" "$checkout_head"; then
      if [ -n "$dirty" ]; then
        GAFFER_CACHE_STATE='held-dirty-main'
      else
        GAFFER_CACHE_STATE='current-main'
      fi
    else
      GAFFER_CACHE_STATE='stale-main'
    fi
  else
    if [ -z "$main_head" ]; then
      GAFFER_CACHE_STATE='deferred-no-main-ref'
    elif gaffer_version_matches "$version" "$main_head"; then
      GAFFER_CACHE_STATE='held-off-main'
    else
      GAFFER_CACHE_STATE='deferred-off-main'
    fi
  fi
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$REPO/dotfiles/agents"
CLAUDE="$REPO/dotfiles/claude"
CODEX="$REPO/dotfiles/codex"
CODEX_REQUIREMENTS="$REPO/modules/codex/requirements.toml"
CLAUDE_MODULE="$REPO/modules/claude/default.bnix"
GAFFER_SYNC="$REPO/scripts/claude-gaffer-plugin-sync.sh"
LOCAL=0
VERBOSE=0
CANONICAL_FRAM_LOG="$HOME/.local/state/north/coordination.log"
CANONICAL_FRAM_TELEMETRY_LOG="$HOME/.local/state/north/telemetry.log"
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
if [ -s "$SHARED/AGENTS.md" ]; then ok_detail "canonical AGENTS.md present"
else bad "canonical AGENTS.md is missing or empty"; fi
group shared "$hook_count hooks linted · $skill_count skills · canonical instructions" "$before"

# Validate a provider hook manifest. In-repo commands must resolve to the shared
# hook implementation. External North lifecycle hooks are strict on a local
# machine and informational in repository-only/CI mode.
validate_hooks() {
  local manifest="$1" provider="$2" expected_provider="$3"
  local count=0 ev command raw_command provider_marker identity_kind first resolved expected basename declared_shared
  while IFS=$'\t' read -r ev command; do
    [ -n "$command" ] || continue
    count=$((count + 1))
    raw_command="$command"
    provider_marker=''
    if [[ "$command" =~ ^AGENT_PROVIDER=([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
      provider_marker="${BASH_REMATCH[1]}"
      command="${BASH_REMATCH[2]}"
    fi
    first="${command%% *}"
    basename="${first##*/}"
    identity_kind=''
    case "$first" in
      /home/tom/code/north/bin/north-on-spawn) identity_kind='spawn' ;;
      /home/tom/code/north/bin/north-on-tooluse) identity_kind='repair' ;;
    esac
    expected="$SHARED/hooks/$basename"
    declared_shared=0
    case "$first" in
      "/home/tom/code/nixos-config/dotfiles/agents/hooks/$basename"|"/home/tom/code/nixos-config/dotfiles/claude/hooks/$basename"|"$expected"|"$basename")
        declared_shared=1
        ;;
    esac
    if [ -n "$provider_marker" ] && [ -z "$identity_kind" ]; then
      bad "$provider $ev sets AGENT_PROVIDER on an unrelated hook: $raw_command"
    elif [ -n "$identity_kind" ] && [ "$provider_marker" != "$expected_provider" ]; then
      bad "$provider $ev North identity $identity_kind must set AGENT_PROVIDER=$expected_provider: $raw_command"
    elif [[ "$first" = /home/tom/code/north/bin/* ]]; then
      if [ "$LOCAL" -eq 1 ]; then
        if [ -x "$first" ]; then ok_detail "$provider $ev → North ${first##*/}"
        else bad "$provider $ev external North hook missing/not executable: $first"; fi
      else note "$provider $ev uses external North hook ${first##*/} (local check deferred)"; fi
    elif [ "$declared_shared" -eq 1 ] && [ -x "$expected" ]; then
      if [ "$LOCAL" -eq 1 ]; then
        resolved="$(readlink -f "$first" 2>/dev/null || true)"
        if [ "$resolved" = "$(readlink -f "$expected" 2>/dev/null || true)" ]; then
          ok_detail "$provider $ev → $basename"
        else
          bad "$provider $ev live hook resolves to '${resolved:-missing}', expected '$expected'"
        fi
      else
        ok_detail "$provider $ev declares canonical shared hook $basename"
      fi
    else bad "$provider $ev hook is missing, non-executable, or outside canonical hooks: $raw_command"; fi
  done < <(jq -r '.hooks // {} | to_entries[] | .key as $event | .value[] | .hooks[]? | select(.type == "command") | [$event,.command] | @tsv' "$manifest")
  HOOK_BINDINGS="$count"
}

manifest_guard_count() {
  local manifest="$1" matcher_token="$2"
  jq -r --arg token "$matcher_token" '
    [.hooks.PreToolUse[]? |
     select(((.matcher // "") | split("|") | index($token)) != null) |
     .hooks[]? |
     select(.type == "command" and (.command | endswith("/agent-spawn-guard.sh")))] |
    length
  ' "$manifest"
}

require_manifest_guard_count() {
  local manifest="$1" provider="$2" matcher_token="$3" expected="$4" contract="$5" count
  count="$(manifest_guard_count "$manifest" "$matcher_token" 2>/dev/null || printf invalid)"
  if [ "$count" = "$expected" ]; then ok_detail "$provider $contract"
  else bad "$provider $contract: found $count matching guard binding(s), expected $expected"; fi
}

validate_codex_managed_worker_guard() {
  if ! need_toml "$CODEX_REQUIREMENTS" 'Codex managed requirements'; then return; fi
  if python3 - "$CODEX_REQUIREMENTS" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as handle:
    policy = tomllib.load(handle)
assert set(policy) == {"features", "hooks"}
assert policy["features"] == {"hooks": True}
hooks = policy["hooks"]
assert set(hooks) == {"managed_dir", "PreToolUse"}
assert hooks["managed_dir"] == "/etc/codex/hooks"
assert len(hooks["PreToolUse"]) == 1
binding = hooks["PreToolUse"][0]
assert binding["matcher"] == "^Bash$"
assert len(binding["hooks"]) == 1
assert binding["hooks"][0] == {
    "type": "command",
    "command": "/etc/codex/hooks/agent-spawn-guard.sh",
    "timeout": 10,
}
PY
  then ok_detail 'Codex managed policy is exactly one trusted Bash topology guard; user/plugin hooks remain permitted'
  else bad "Codex managed requirements add policy beyond the single approved Bash topology guard"; fi

  local module="$REPO/modules/codex/default.bnix"
  for source in '/modules/codex/requirements.toml' '/dotfiles/agents/hooks/agent-spawn-guard.sh' '/dotfiles/agents/hooks/lib/authoring-killswitch.sh'; do
    if grep -Fq "(s flakeRoot \"$source\")" "$module"; then :
    else bad "Codex module does not install managed-hook source $source"; fi
  done

  if [ "$LOCAL" -eq 1 ]; then
    if cmp -s "$CODEX_REQUIREMENTS" /etc/codex/requirements.toml &&
       cmp -s "$SHARED/hooks/agent-spawn-guard.sh" /etc/codex/hooks/agent-spawn-guard.sh &&
       cmp -s "$SHARED/hooks/lib/authoring-killswitch.sh" /etc/codex/hooks/lib/authoring-killswitch.sh; then
      ok_detail 'Codex managed Bash topology guard is live from /etc (policy-trusted, no /hooks action)'
    else
      bad 'Codex managed Bash topology guard is not the current /etc generation; run firn rebuild after commit'
    fi
  fi
}

before=$fail
claude_north='connection deferred to --local'
claude_fram='connection deferred to --local'
claude_fram_topology='topology deferred'
claude_linear='connection deferred to --local'
claude_gaffer='cache freshness deferred to --local'
need_json "$CLAUDE/settings.json" 'Claude settings'
if command -v shellcheck >/dev/null 2>&1 && shellcheck -S warning "$CLAUDE/statusline.sh"; then
  ok_detail "Claude statusline shellcheck"
else bad "Claude statusline shellcheck failed"; fi
if jq -e '.statusLine.type == "command" and .statusLine.command == "bash \"$HOME/code/nixos-config/dotfiles/claude/statusline.sh\""' "$CLAUDE/settings.json" >/dev/null; then
  ok_detail "Claude statusline points at canonical adapter"
else bad "Claude statusline is not wired to $CLAUDE/statusline.sh"; fi
if bash "$CLAUDE/statusline.test.sh" >/dev/null; then
  ok_detail "Claude statusline observer is detached and output-safe"
else bad "Claude statusline observer test failed"; fi
if jq -e '.autoMemoryEnabled == false' "$CLAUDE/settings.json" >/dev/null; then ok_detail "auto-memory disabled"
else bad "Claude autoMemoryEnabled must be false"; fi
if jq -e '
  .enabledPlugins["gaffer@gaffer"] == true
  and .extraKnownMarketplaces.gaffer.source == {
    "source": "directory",
    "path": "/home/tom/code/gaffer"
  }
' "$CLAUDE/settings.json" >/dev/null; then
  ok_detail "Gaffer plugin uses the canonical local directory marketplace"
else
  bad "Claude Gaffer plugin must be enabled from /home/tom/code/gaffer"
fi
if command -v shellcheck >/dev/null 2>&1 && shellcheck -S warning "$GAFFER_SYNC"; then
  ok_detail "Gaffer plugin sync shellcheck"
else bad "Gaffer plugin sync shellcheck failed"; fi
if grep -Fq ':home.activation.syncGafferPlugin' "$CLAUDE_MODULE" &&
   grep -Fq '/scripts/claude-gaffer-plugin-sync.sh' "$CLAUDE_MODULE" &&
   ! grep -Fq 'installed_plugins.json' "$GAFFER_SYNC"; then
  ok_detail "Firn rebuild declares Claude-owned Gaffer cache reconciliation"
else
  bad "Claude module must reconcile Gaffer through the supported plugin CLI"
fi
validate_hooks "$CLAUDE/settings.json" Claude anthropic
require_manifest_guard_count "$CLAUDE/settings.json" Claude Bash 1 'user Bash topology guard is bound once'
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
    fram_telemetry_log="$(jq -r '.mcpServers.fram.env.FRAM_TELEMETRY_LOG // empty' "$HOME/.claude.json")"
    [ "$fram_log" = "$CANONICAL_FRAM_LOG" ] || bad "Claude Fram FRAM_LOG is '${fram_log:-unset}', expected '$CANONICAL_FRAM_LOG'"
    [ "$fram_telemetry_log" = "$CANONICAL_FRAM_TELEMETRY_LOG" ] || bad "Claude Fram FRAM_TELEMETRY_LOG is '${fram_telemetry_log:-unset}', expected '$CANONICAL_FRAM_TELEMETRY_LOG'"
    if [ "$fram_log" = "$CANONICAL_FRAM_LOG" ] && [ "$fram_telemetry_log" = "$CANONICAL_FRAM_TELEMETRY_LOG" ]; then
      claude_fram_topology='canonical split corpus'
    else
      claude_fram_topology='stale corpus configuration'
    fi
    project_count="$(jq '[.projects[]? | select(.mcpServers != null)] | length' "$HOME/.claude.json")"
    note "$project_count project-scoped Claude MCP registrations (allowed)"
    ok_detail "Claude MCP: North + canonical split Fram corpus + Linear"
  else bad "$HOME/.claude.json is missing"; fi
  if command -v claude >/dev/null 2>&1; then
    claude_mcp_output="$(claude mcp list 2>&1)" || bad "claude rejected its config while checking MCP health:\n$claude_mcp_output"
    for server in north fram linear-mcp-msa-new; do
      grep -Eq "^${server}:.*Connected" <<<"$claude_mcp_output" || bad "Claude MCP '$server' is missing or not connected:\n$claude_mcp_output"
    done
    claude_north='connected'
    claude_fram="connected; $claude_fram_topology"
    claude_linear='connected'
    ok_detail "Claude reports North + Fram + Linear MCP connected"
    if gaffer_plugins="$(timeout 30 claude plugin list --json 2>/dev/null)" &&
       gaffer_version="$(jq -er '
         [.[] | select(.id == "gaffer@gaffer")]
         | if length == 1 then .[0].version else error("expected one Gaffer plugin") end
       ' <<<"$gaffer_plugins")" &&
       gaffer_head_full="$(git -C "$HOME/code/gaffer" rev-parse HEAD 2>/dev/null)"; then
      gaffer_head="${gaffer_head_full:0:12}"
      gaffer_branch="$(git -C "$HOME/code/gaffer" symbolic-ref --quiet --short HEAD 2>/dev/null || printf detached)"
      gaffer_dirty="$(git -C "$HOME/code/gaffer" status --porcelain --untracked-files=normal 2>/dev/null || printf status-unavailable)"
      gaffer_main_full=''
      gaffer_main_label='local main'
      if gaffer_main_full="$(git -C "$HOME/code/gaffer" rev-parse --verify 'refs/heads/main^{commit}' 2>/dev/null)"; then
        :
      elif gaffer_main_full="$(git -C "$HOME/code/gaffer" rev-parse --verify 'refs/remotes/origin/main^{commit}' 2>/dev/null)"; then
        gaffer_main_label='origin/main'
      else
        gaffer_main_full=''
        gaffer_main_label='main ref unavailable'
      fi
      gaffer_main="${gaffer_main_full:0:12}"
      classify_gaffer_cache \
        "$gaffer_version" "$gaffer_head_full" "$gaffer_main_full" \
        "$gaffer_branch" "$gaffer_dirty"

      gaffer_source_state='clean main'
      [ "$gaffer_branch" = main ] ||
        gaffer_source_state="branch $gaffer_branch"
      if [ -n "$gaffer_dirty" ]; then
        if [ "$gaffer_source_state" = 'clean main' ]; then
          gaffer_source_state='dirty worktree'
        else
          gaffer_source_state="$gaffer_source_state + dirty worktree"
        fi
      fi

      case "$GAFFER_CACHE_STATE" in
        current-main)
          claude_gaffer="current at $gaffer_head"
          ok_detail "Claude Gaffer cache matches committed source $gaffer_head"
          ;;
        held-dirty-main)
          claude_gaffer="held at committed $gaffer_head · $gaffer_source_state excluded"
          ok_detail "Claude Gaffer cache is safely held at committed $gaffer_head; $gaffer_source_state is not copied"
          ;;
        stale-main)
          bad "Claude Gaffer cache is $gaffer_version, committed main source is $gaffer_head ($gaffer_source_state); make the checkout clean, then run firn rebuild"
          claude_gaffer="stale ($gaffer_version → $gaffer_head)"
          ;;
        held-off-main)
          claude_gaffer="held at $gaffer_main_label $gaffer_main · $gaffer_source_state excluded"
          ok_detail "Claude Gaffer cache matches eligible $gaffer_main_label $gaffer_main; $gaffer_source_state is not copied"
          ;;
        deferred-off-main)
          claude_gaffer="deferred ($gaffer_version → $gaffer_main_label $gaffer_main) · $gaffer_source_state excluded"
          soft "Claude Gaffer cache is $gaffer_version and eligible $gaffer_main_label is $gaffer_main; $gaffer_source_state is excluded, so reconciliation is deferred until a clean main checkout"
          ;;
        deferred-no-main-ref)
          claude_gaffer="deferred ($gaffer_version · no eligible main ref) · $gaffer_source_state excluded"
          soft "Claude Gaffer cache is $gaffer_version, but no eligible main ref is available; $gaffer_source_state is excluded, so freshness is deferred"
          ;;
      esac
    else
      bad "Claude Gaffer plugin/source freshness could not be determined (plugin-list probe is capped at 30s)"
      claude_gaffer='freshness unknown'
    fi
  else bad "claude CLI is missing from PATH"; fi
fi
provider_group Claude "$before" \
  "Hooks       $claude_bindings bindings" \
  'Identity    adapter-pinned native spawn + repair → anthropic' \
  'Topology    user Bash hook (loaded directly by Claude)' \
  "Bootstrap   static config parsed · Gaffer $claude_gaffer" \
  "MCP         North: $claude_north" \
  "            Fram: $claude_fram" \
  "            Linear: $claude_linear"

before=$fail
need_json "$CODEX/hooks.json" 'Codex hooks'
need_toml "$CODEX/config.toml" 'Codex config'
validate_hooks "$CODEX/hooks.json" Codex openai
require_manifest_guard_count "$CODEX/hooks.json" Codex Bash 0 'user Bash guard is absent (managed binding is the sole Bash guard)'
require_manifest_guard_count "$CODEX/hooks.json" Codex Agent 1 'native Agent redirect remains a trust-reviewed user hook'
validate_codex_managed_worker_guard
codex_bindings="$HOOK_BINDINGS"
codex_north='declared; live probe deferred'
codex_fram='declared; canonical split corpus; live probe deferred'
codex_linear='auth probe deferred to --local'
grep -q '^\[mcp_servers\.north\]' "$CODEX/config.toml" || bad "Codex config does not declare North MCP"
grep -q '^\[mcp_servers\.fram\]' "$CODEX/config.toml" || bad "Codex config does not declare Fram MCP"
grep -q '^\[mcp_servers\.linear-mcp-msa-new\]' "$CODEX/config.toml" || bad "Codex config does not declare Linear MCP"
codex_fram_paths="$(python3 -c 'import sys,tomllib; c=tomllib.load(open(sys.argv[1],"rb")); e=c.get("mcp_servers",{}).get("fram",{}).get("env",{}); print(e.get("FRAM_LOG","")); print(e.get("FRAM_TELEMETRY_LOG",""))' "$CODEX/config.toml" 2>/dev/null || true)"
codex_fram_log="$(sed -n '1p' <<<"$codex_fram_paths")"
codex_fram_telemetry_log="$(sed -n '2p' <<<"$codex_fram_paths")"
[ "$codex_fram_log" = "$CANONICAL_FRAM_LOG" ] || bad "Codex Fram FRAM_LOG is '${codex_fram_log:-unset}', expected '$CANONICAL_FRAM_LOG'"
[ "$codex_fram_telemetry_log" = "$CANONICAL_FRAM_TELEMETRY_LOG" ] || bad "Codex Fram FRAM_TELEMETRY_LOG is '${codex_fram_telemetry_log:-unset}', expected '$CANONICAL_FRAM_TELEMETRY_LOG'"
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
    codex_fram='enabled; canonical split corpus'
  else bad "codex CLI is missing from PATH"; fi
fi
provider_group Codex "$before" \
  "Hooks       $codex_bindings bindings" \
  'Identity    adapter-pinned native spawn + repair → openai' \
  'Topology    managed /etc Bash guard (policy-trusted) · native redirect user hook (trust-reviewed)' \
  'Bootstrap   static config parsed' \
  "MCP         North: $codex_north" \
  "            Fram: $codex_fram" \
  "            Linear: $codex_linear"

before=$fail
if [ "$LOCAL" -eq 1 ]; then
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet north-coord; then
    north_coord_env="$(systemctl show north-coord -p Environment --value 2>/dev/null || true)"
    north_coord_exec="$(systemctl show north-coord -p ExecStart --value 2>/dev/null || true)"
    [[ "$north_coord_env" == *"FRAM_TELEMETRY_LOG=$CANONICAL_FRAM_TELEMETRY_LOG"* ]] || bad "north-coord lacks canonical FRAM_TELEMETRY_LOG in its live environment"
    [[ "$north_coord_exec" == *" $CANONICAL_FRAM_LOG "* ]] || bad "north-coord does not serve canonical coordination.log: $north_coord_exec"
  else bad "north-coord systemd service is not active"; fi
  anthropic_installed='unknown'
  anthropic_authenticated='unknown'
  anthropic_headroom='unknown'
  openai_installed='unknown'
  openai_authenticated='unknown'
  openai_headroom='unknown'
  if command -v north >/dev/null 2>&1; then
    if provider_output="$(north providers --json 2>&1)"; then
      if anthropic_fields="$(printf '%s\n' "$provider_output" | "$REPO/scripts/agent-provider-status.sh" anthropic)"; then
        IFS='|' read -r anthropic_installed anthropic_authenticated anthropic_headroom <<<"$anthropic_fields"
        [ "$anthropic_installed" = yes ] || bad "North reports Anthropic not installed"
        [ "$anthropic_authenticated" = yes ] || bad "North reports Anthropic not authenticated"
      else bad "North omitted or malformed Anthropic capability status:\n$provider_output"; fi
      if openai_fields="$(printf '%s\n' "$provider_output" | "$REPO/scripts/agent-provider-status.sh" openai)"; then
        IFS='|' read -r openai_installed openai_authenticated openai_headroom <<<"$openai_fields"
        [ "$openai_installed" = yes ] || bad "North reports OpenAI/Codex not installed"
        [ "$openai_authenticated" = yes ] || bad "North reports OpenAI/Codex not authenticated"
      else bad "North omitted or malformed OpenAI capability status:\n$provider_output"; fi
      if allocation_summary="$(jq -er '
        .allocationMode as $mode
        | if ($mode == "balanced" or $mode == "preferential" or $mode == "reserved") then
            ([.providers[]?.targets[]? | select(.routing == "eligible")] | length) as $eligible
            | if $eligible > 0 then "\($mode) · \($eligible) eligible accounts"
              else error("no eligible routing accounts") end
          else error("unsupported allocation mode") end
      ' <<<"$provider_output")"; then
        :
      else bad "North allocation policy missing or malformed:\n$provider_output"; fi
      provider_source="$(jq -r '.source // "unknown source"' <<<"$provider_output")"
      provider_target_count="$(jq '[.providers[]?.targets[]?] | length' <<<"$provider_output")"
      ok_detail "North providers JSON v2 · $provider_target_count targets · $provider_source"
    else bad "installed North provider readiness failed:\n$provider_output"; fi
  else bad "installed North CLI is missing from PATH"; fi
else ok_detail "provider readiness deferred to --local"; fi
if [ "$LOCAL" -eq 1 ]; then
  provider_group North "$before" \
    "Anthropic   installed=$anthropic_installed · authenticated=$anthropic_authenticated · headroom=$anthropic_headroom" \
    "OpenAI      installed=$openai_installed · authenticated=$openai_authenticated · headroom=$openai_headroom" \
    "Allocation  ${allocation_summary:-unknown}"
else
  provider_group North "$before" 'Providers   readiness deferred to --local'
fi

if [ "$fail" -ne 0 ]; then printf 'agent-config-check: FAILED\n' >&2; exit 1; fi
if [ "$warn" -gt 0 ]; then printf 'agent-config-check: passed with %s warning(s)\n' "$warn"
else printf 'agent-config-check: all green\n'; fi
