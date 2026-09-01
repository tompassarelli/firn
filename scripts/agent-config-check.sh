#!/usr/bin/env bash
# Provider-neutral anti-rot check for the shared agent harness and its adapters.
# Default output is intentionally a small status report. Use --verbose for the
# individual assertions; failures always print their full diagnostic.
set -uo pipefail

if [ -n "${NORTH_AGENT_PYTHON:-}" ]; then
  AGENT_CONFIG_PYTHON="$NORTH_AGENT_PYTHON"
elif command -v python3 >/dev/null 2>&1; then
  AGENT_CONFIG_PYTHON="$(command -v python3)"
else
  AGENT_CONFIG_PYTHON=/etc/codex/hooks/runtime/python3
fi

codex_managed_policy_binding_count() {
  "$AGENT_CONFIG_PYTHON" - "$1" <<'PY'
import sys
import tomllib

def command(path, timeout, with_path=True):
    interpreter = "python3" if path.endswith(".py") else "bash"
    environment = (
        "PATH=/etc/codex/hooks/runtime:/home/tom/.local/bin:/run/current-system/sw/bin "
        if interpreter == "bash" and with_path
        else ""
    )
    return {
        "type": "command",
        "command": (
            "/etc/codex/hooks/runtime/env -u BASH_ENV -u ENV %s"
            "/etc/codex/hooks/runtime/%s /etc/codex/hooks/%s"
            % (environment, interpreter, path)
        ),
        "timeout": timeout,
    }

enabled = {
    "allow_managed_hooks_only": True,
    "allow_remote_control": False,
    "managed_hook_failure_mode": "block",
    "features": {"hooks": True},
    "hooks": {
        "managed_dir": "/etc/codex/hooks",
        "SessionStart": [{
            "hooks": [command("beagle-session-start.sh", 30)],
        }],
        "PreToolUse": [
            {
                "hooks": [command("firn-system-policy", 10, False)],
            },
            {
                "matcher": "^(Edit|Write|MultiEdit|apply_patch)$",
                "hooks": [
                    command("launch-critical-worktree-guard.sh", 10),
                    command("concrete-model-identity-guard.sh", 10),
                ],
            },
            {
                "matcher": "^Bash$",
                "hooks": [
                    command("tripwire-guard.sh", 10),
                    command("launch-critical-worktree-guard.sh", 10),
                    command("corpus-scan-guard.sh", 10),
                    command("resource-safe-search-guard.sh", 10),
                    command("session-kill-guard.sh", 10),
                    command("concrete-model-identity-guard.sh", 10),
                ],
            },
        ],
    },
}

disabled = {
    "allow_managed_hooks_only": True,
    "allow_remote_control": False,
    "features": {"hooks": False},
}

with open(sys.argv[1], "rb") as handle:
    policy = tomllib.load(handle)
if type(policy.get("allow_managed_hooks_only")) is not bool:
    raise SystemExit("allow_managed_hooks_only must be a boolean")
if type(policy.get("allow_remote_control")) is not bool:
    raise SystemExit("allow_remote_control must be a boolean")
if policy == disabled:
    print(0)
elif policy == enabled:
    print(sum(
        len(binding["hooks"])
        for event, bindings in policy["hooks"].items()
        if event != "managed_dir"
        for binding in bindings
    ))
else:
    raise SystemExit("managed Codex policy differs from an authoritative enabled or disabled contract")
PY
}

canonical_link() {
  local link="$1" expected="$2" label="$3"
  local got want
  got="$(readlink -f "$link" 2>/dev/null || true)"
  want="$(readlink -f "$expected" 2>/dev/null || true)"
  if [ -n "$got" ] && [ "$got" = "$want" ]; then ok_detail "$label → ${want#"$REPO"/}"
  else bad "$label resolves to '${got:-missing}', expected '$want'"; fi
}

immutable_store_link_matches() {
  local link="$1" expected="$2" label="$3" resolved
  local store_prefix="${NIX_STORE_PREFIX:-/nix/store}"

  if [ ! -L "$link" ]; then
    bad "$label must be a generation-owned symlink"
    return 1
  fi
  resolved="$(readlink -f "$link" 2>/dev/null || true)"
  case "$resolved" in
    "$store_prefix"/*) ;;
    *)
      bad "$label resolves outside $store_prefix: ${resolved:-missing}"
      return 1
      ;;
  esac
  if cmp -s "$resolved" "$expected"; then
    ok_detail "$label is an exact generation-owned store copy"
  else
    bad "$label differs from the committed generation source"
    return 1
  fi
}

run_agent_policy_contract() {
  local repo="$1" local_mode="${2:-0}"
  local -a args=(--repo "$repo")
  [ "$local_mode" -eq 0 ] || args+=(--local)
  "$AGENT_CONFIG_PYTHON" "$repo/scripts/agent-policy-contract.py" "${args[@]}"
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BEAGLE_INTEGRATION="${AGENT_CONFIG_BEAGLE_INTEGRATION:-$HOME/code/beagle/main/integrations/north}"
FIRN_INTEGRATION="$REPO/modules/north-profile/firn"
CODEX="$REPO/dotfiles/codex"
LIVE_AGENT_ROOT="${NORTH_AGENT_STATE_ROOT:-$HOME/.local/state/north/agents}"
CODEX_REQUIREMENTS="$REPO/modules/codex/requirements.toml"
LOCAL=0
VERBOSE=0
POLICY_ONLY=0
# This repository declares Tom's machine profile; CI's HOME is runner scratch.
for arg in "$@"; do
  case "$arg" in
    --local) LOCAL=1 ;;
    --policy-only) POLICY_ONLY=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    *) printf 'usage: %s [--local] [--policy-only] [--verbose]\n' "$0" >&2; exit 2 ;;
  esac
done

if [ "$POLICY_ONLY" -eq 1 ]; then
  run_agent_policy_contract "$REPO" "$LOCAL"
  exit $?
fi

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
  if "$AGENT_CONFIG_PYTHON" -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$file" >/dev/null 2>&1; then
    ok_detail "$label is valid TOML"
  else
    bad "$label is not valid TOML: $file"
    return 1
  fi
}
need_yaml() {
  # Strict parse only when a YAML parser is present (PyYAML is not stdlib and
  # is absent from the minimal system python / CI). When absent, structural
  # grep assertions below carry the load — this never hard-fails on a missing
  # parser, only on a genuinely malformed document.
  local file="$1" label="$2"
  [ -f "$file" ] || { bad "$label is missing: $file"; return 1; }
  if "$AGENT_CONFIG_PYTHON" -c 'import yaml' >/dev/null 2>&1; then
    if "$AGENT_CONFIG_PYTHON" -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$file" >/dev/null 2>&1; then
      ok_detail "$label is valid YAML"
    else
      bad "$label is not valid YAML: $file"
      return 1
    fi
  else
    note "$label YAML strict-parse skipped (no PyYAML); structural checks apply"
  fi
}
printf 'agent harness check%s\n' "$([ "$LOCAL" -eq 1 ] && printf ' (local)' || true)"

before=$fail
if policy_output="$(run_agent_policy_contract "$REPO" "$LOCAL" 2>&1)"; then
  ok_detail "$policy_output"
else
  bad "$policy_output"
fi
group policy 'explicit ownership and exact Firn provider bindings' "$before"

# North-composed constitution plus hook/skill implementations from each owner.
before=$fail
hook_count=0
if command -v shellcheck >/dev/null 2>&1; then
  for hook_root in \
    "$LIVE_AGENT_ROOT/current/provider-hooks" \
    "$BEAGLE_INTEGRATION/hooks" \
    "$FIRN_INTEGRATION/hooks"; do
    if [ ! -d "$hook_root" ]; then
      if [ "$LOCAL" -eq 1 ]; then
        bad "composed hook owner root is missing: $hook_root"
      else
        note "external hook owner root unavailable in repository-only mode: $hook_root"
      fi
      continue
    fi
    while IFS= read -r hook; do
      hook_count=$((hook_count + 1))
      if output="$(shellcheck -S warning "$hook" 2>&1)"; then
        ok_detail "shellcheck ${hook##*/}"
      else bad "shellcheck ${hook##*/}:\n$output"; fi
    done < <(find "$hook_root" -maxdepth 1 -type f -name '*.sh' -print | sort)
  done
else bad "shellcheck is required to lint shared hooks"; fi
skill_count=0
for skill_root in \
  "$REPO/dotfiles/agents/skills" \
  "$LIVE_AGENT_ROOT/current/skills/shared" \
  "$BEAGLE_INTEGRATION/skills" \
  "$FIRN_INTEGRATION/skills"; do
  if [ ! -d "$skill_root" ]; then
    if [ "$LOCAL" -eq 1 ]; then
      bad "composed skill owner root is missing: $skill_root"
    else
      note "external skill owner root unavailable in repository-only mode: $skill_root"
    fi
    continue
  fi
  while IFS= read -r skill; do
    skill_count=$((skill_count + 1))
    if [ "$(head -n 1 "$skill")" = '---' ]; then ok_detail "${skill%/SKILL.md} has frontmatter"
    else soft "${skill#"$REPO"/} lacks SKILL.md frontmatter"; fi
  done < <(find "$skill_root" -mindepth 2 -maxdepth 2 -name SKILL.md -type f -print | sort)
done
if [ -s "$REPO/dotfiles/agents/AGENTS.md" ]; then
  ok_detail "global AGENTS.md owner source present"
else
  bad "global AGENTS.md owner source is missing or empty"
fi
north_profile_module="$REPO/modules/north-profile/default.bnix"
if grep -Fq '"/.local/state/north/agents/current/instructions/shared/AGENTS.md"' "$north_profile_module"; then
  ok_detail "~/.agents/AGENTS.md is wired to North-generation instructions"
else
  bad "~/.agents/AGENTS.md must be wired to the current North activation generation"
fi
if grep -Fq '"/.local/state/north/agents/current/skills/shared"' "$north_profile_module"; then
  ok_detail 'shared agent skills are wired to the current North projection'
else
  bad 'shared agent skills must be wired to the current North activation generation'
fi
if grep -Fq '"/.local/state/north/agents/current/provider-hooks"' "$north_profile_module"; then
  ok_detail 'shared agent hooks are wired to the current North provider hooks'
else
  bad 'shared agent hooks must be wired to the current North activation generation'
fi
if grep -Fq '"/.local/state/north/agents/current/instructions/code/AGENTS.md"' "$north_profile_module"; then
  ok_detail 'code-root instructions are wired to North-generation instructions'
else
  bad 'code-root instructions must be wired to the current North activation generation'
fi
if rg -n 'agent-profile|\.config/agents|profiles/tom|\.agents/docs' \
  "$north_profile_module" >/dev/null; then
  bad 'north-profile module still declares a retired agent projection'
else
  ok_detail 'north-profile module contains no retired agent projection'
fi
if [ "$LOCAL" -eq 1 ]; then
  canonical_link "$HOME/.agents/AGENTS.md" "$LIVE_AGENT_ROOT/current/instructions/shared/AGENTS.md" "$HOME/.agents/AGENTS.md"
  canonical_link "$HOME/.agents/hooks" "$LIVE_AGENT_ROOT/current/provider-hooks" "$HOME/.agents/hooks"
  canonical_link "$HOME/.agents/skills" "$LIVE_AGENT_ROOT/current/skills/shared" "$HOME/.agents/skills"
  canonical_link "$HOME/code/AGENTS.md" "$LIVE_AGENT_ROOT/current/instructions/code/AGENTS.md" "$HOME/code/AGENTS.md"
  if [ -e "$HOME/.agents/docs" ] || [ -L "$HOME/.agents/docs" ]; then
    bad "$HOME/.agents/docs must be absent because the generation has no docs artifact"
  else
    ok_detail "$HOME/.agents/docs is absent"
  fi
fi
group shared "$hook_count owner hooks linted · $skill_count owner skills · North-generation instructions" "$before"

validate_codex_managed_policy() {
  if ! need_toml "$CODEX_REQUIREMENTS" 'Codex managed requirements'; then return; fi
  CODEX_MANAGED_BINDINGS="$(
    codex_managed_policy_binding_count "$CODEX_REQUIREMENTS" 2>/dev/null
  )" || CODEX_MANAGED_BINDINGS=''
  if [ "$CODEX_MANAGED_BINDINGS" = 10 ]; then
    ok_detail 'Codex managed-only, fail-closed, remote-control-disabled policy is the exact 10-binding authoritative contract'
  elif [ "$CODEX_MANAGED_BINDINGS" = 0 ]; then
    ok_detail 'Codex managed hooks are authoritatively disabled; remote control remains disabled'
  else
    bad 'Codex managed requirements differ from the authoritative hook contract'
  fi

  local module="$REPO/modules/codex/default.bnix"
  local live resolved adapter expected_adapter
  local -a provider_adapters=(
    lib/north-agent-activation.sh
    beagle-session-start.sh
    firn-system-policy
    concrete-model-identity-guard.sh
    launch-critical-worktree-guard.sh
    lib/launch_critical_decide.py
    lib/launch_critical_paths.py
    tripwire-guard.sh
    corpus-scan-guard.sh
    resource-safe-search-guard.sh
    session-kill-guard.sh
    lib/authoring-killswitch.sh
  )
  if grep -Fq '(s flakeRoot "/modules/codex/requirements.toml")' "$module"; then :
  else bad 'Codex module does not install its managed requirements'; fi
  for adapter in "${provider_adapters[@]}"; do
    if grep -Fq "(providerAdapter \"$adapter\")" "$module"; then :
    else bad "Codex module does not link provider adapter $adapter from the current North generation"; fi
  done
  local runtime package binary
  local -a runtimes=(
    'bash|pkgs.bash|bash'
    'cat|pkgs.coreutils|cat'
    'env|pkgs.coreutils|env'
    'git|pkgs.git|git'
    'mktemp|pkgs.coreutils|mktemp'
    'python3|pkgs.python3|python3'
    'rm|pkgs.coreutils|rm'
    'timeout|pkgs.coreutils|timeout'
  )
  for source in "${runtimes[@]}"; do
    IFS='|' read -r runtime package binary <<<"$source"
    if grep -Fq "\"codex/hooks/runtime/$runtime\"" "$module" &&
       grep -Fq "{:source (s $package \"/bin/$binary\")}" "$module"; then :
    else bad "Codex module does not bind exact runtime $runtime from $package"; fi
  done
  if ! grep -Fq 'codexUpstreamPkg' "$module" &&
     ! grep -Fq 'codexPkg' "$module" &&
     ! grep -Fq ':environment.systemPackages' "$module" &&
     ! grep -Fq '"codex/runtime"' "$module"; then
    ok_detail 'Codex stays out of the NixOS system closure and uses its independently promoted user runtime'
  else
    bad 'Codex module must not install Codex or expose a Codex runtime through the NixOS system closure'
  fi
  if grep -Fq ':mode ' "$module"; then
    bad 'Codex hook sources must remain /etc symlinks into /nix/store; explicit mode copies are forbidden'
  fi

  if [ "$LOCAL" -eq 1 ]; then
    local generation_exact=1
    if cmp -s "$CODEX_REQUIREMENTS" /etc/codex/requirements.toml; then :
    else
      generation_exact=0
      bad 'Codex managed requirements are not the current /etc generation'
    fi
    for adapter in "${provider_adapters[@]}"; do
      live="/etc/codex/hooks/$adapter"
      expected_adapter="$LIVE_AGENT_ROOT/current/provider-hooks/$adapter"
      if [ -L "$live" ] && [ "$(readlink "$live")" = "$expected_adapter" ]; then :
      else
        generation_exact=0
        bad "Codex provider adapter $live is not the stable link to $expected_adapter"
      fi
    done
    for source in "${runtimes[@]}"; do
      IFS='|' read -r runtime package binary <<<"$source"
      live="/etc/codex/hooks/runtime/$runtime"
      resolved="$(readlink -f "$live" 2>/dev/null || true)"
      if [ -x "$live" ] && [[ "$resolved" = /nix/store/* ]]; then :
      else
        generation_exact=0
        bad "Codex runtime $live is missing, non-executable, or not store-backed"
      fi
    done
    local interactive_codex user_codex
    interactive_codex="$(command -v codex 2>/dev/null || true)"
    user_codex="$HOME/.local/lib/codex/current/bin/codex"
    interactive_codex="$(readlink -f "$interactive_codex" 2>/dev/null || true)"
    if [ -x "$user_codex" ]; then
      ok_detail 'Codex user runtime is installed and executable outside the NixOS system closure'
    else
      generation_exact=0
      bad 'Codex user runtime is missing or non-executable; run codex-runtime-update'
    fi
    if [ -n "$interactive_codex" ] &&
       [ "$interactive_codex" = "$(readlink -f "$user_codex" 2>/dev/null || true)" ]; then
      ok_detail 'Interactive Codex directly resolves to the promoted user runtime'
    elif [ -n "$interactive_codex" ]; then
      ok_detail 'Interactive Codex uses a distinct user launcher over the promoted user runtime'
    else
      soft 'Interactive Codex is absent from PATH; the promoted user runtime remains independently executable'
    fi
    if [ "$generation_exact" -eq 1 ]; then
      CODEX_HOOK_PROVENANCE='North-v2 activation generation · immutable Firn runtime tools'
      ok_detail 'Codex hook deployment is exact to the current North-v2 activation generation'
    else
      CODEX_HOOK_PROVENANCE='generation drift detected'
    fi
  else
    CODEX_HOOK_PROVENANCE='immutable /nix/store generation deferred to --local'
  fi
}

before=$fail
need_toml "$CODEX/config.toml" 'Codex config'
if grep -Fq '{:source (s flakeRoot "/dotfiles/codex/config.toml")}' \
     "$REPO/modules/codex/default.bnix" &&
   grep -Fq '".codex/config.toml".source = "${flakeRoot}/dotfiles/codex/config.toml";' \
     "$REPO/modules/codex/default.nix" &&
   ! rg -q 'code/nixos-config/dotfiles/codex/config\.toml' \
     "$REPO/modules/codex/default.bnix" "$REPO/modules/codex/default.nix"; then
  ok_detail 'Codex config is a generation-owned store source'
else
  bad 'Codex config must use the committed flake source'
fi
validate_codex_managed_policy
codex_bindings="${CODEX_MANAGED_BINDINGS:-invalid}"
codex_hook_provenance="${CODEX_HOOK_PROVENANCE:-declaration drift detected}"
if grep -q '^\[mcp_servers\.north\]' "$CODEX/config.toml"; then
  bad 'Codex config still declares the retired North MCP server'
else
  ok_detail 'Codex config has no North MCP server'
fi
if grep -q '^\[mcp_servers\.linear-mcp-msa-new\]' "$CODEX/config.toml"; then
  ok_detail 'Codex retains the independent Linear MCP declaration'
else
  bad 'Codex config does not declare Linear MCP'
fi
if [ "$LOCAL" -eq 1 ]; then
  immutable_store_link_matches \
    "$HOME/.codex/config.toml" "$CODEX/config.toml" "$HOME/.codex/config.toml"
  canonical_link "$HOME/.codex/AGENTS.md" "$LIVE_AGENT_ROOT/current/instructions/codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
  if [ -d "$HOME/.codex/skills" ] && [ ! -L "$HOME/.codex/skills" ]; then
    ok_detail 'Codex skills remains a provider/user-owned directory'
  else
    bad 'Codex skills must remain a real directory; North owns only exact compatibility links inside it'
  fi
fi
provider_group Codex "$before" \
  "Hooks       $codex_bindings managed authoritative bindings" \
  'Identity    managed lanes harness-owned · pinned native fallback → openai' \
  'Topology    sole policy: managed /etc/codex/hooks' \
  "Hook source $codex_hook_provenance" \
  'Bootstrap   static config parsed' \
  'MCP         North absent · Linear independently declared'

# --- worktree layout -------------------------------------------------------
# A rule with no detector silently stops being true. On 2026-07-29 a sweep found
# 63 worktrees across FOUR conventions at once, plus seven clones of north at
# ~/code root and orphaned trees whose gitdir no longer existed — after the
# layout had been written down and restated repeatedly. This is the detector.
if [ "$LOCAL" -eq 1 ] && command -v worktree-layout-check >/dev/null 2>&1; then
  if worktree_layout_out="$(worktree-layout-check 2>&1)"; then
    printf '\u2713 %s\n' "$worktree_layout_out"
  else
    bad "worktree layout drift — run worktree-layout-check for the list"
    printf '%s\n' "$worktree_layout_out" >&2
  fi
fi

if [ "$fail" -ne 0 ]; then printf 'agent-config-check: FAILED\n' >&2; exit 1; fi
if [ "$warn" -gt 0 ]; then printf 'agent-config-check: passed with %s warning(s)\n' "$warn"
else printf 'agent-config-check: all green\n'; fi
