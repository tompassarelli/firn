#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NORTH_REPO="${AGENT_CONFIG_NORTH_REPO:-$HOME/code/north/main}"
BEAGLE_INTEGRATION="${AGENT_CONFIG_BEAGLE_INTEGRATION:-$HOME/code/beagle/main/integrations/north}"
export PROBE_ENV_BIN="${PROBE_ENV_BIN:-$(command -v env)}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-check.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
trap 'status=$? line=$LINENO command=$BASH_COMMAND; trap - ERR; printf "agent-config-check.test.sh:%s: unhandled failure status=%s command=%s\n" "$line" "$status" "$command" >&2; exit "$status"' ERR

run_quiet_child() {
  local label="$1"
  local output status
  shift

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    return 0
  fi

  printf '%s failed with rc=%s\n' "$label" "$status" >&2
  [ -z "$output" ] || printf '%s\n' "$output" >&2
  return "$status"
}

run_quiet_child_regression() {
  local output status

  output="$(
    run_quiet_child 'successful fixture' \
      bash -c 'printf "suppressed stdout\n"; printf "suppressed stderr\n" >&2' \
      2>&1
  )"
  [ -z "$output" ] || {
    printf 'successful quiet child leaked output: %s\n' "$output" >&2
    return 1
  }

  if output="$(
    run_quiet_child 'failing fixture' \
      bash -c 'printf "fixture stdout\n"; printf "fixture stderr\n" >&2; exit 7' \
      2>&1
  )"; then
    printf 'failing quiet child unexpectedly succeeded\n' >&2
    return 1
  else
    status=$?
  fi

  [ "$status" -eq 7 ]
  grep -Fq 'failing fixture failed with rc=7' <<<"$output"
  grep -Fq 'fixture stdout' <<<"$output"
  grep -Fq 'fixture stderr' <<<"$output"
}

run_err_trap_regression() {
  local expected_line output status

  if output="$("$BASH" "$REPO/scripts/agent-config-check.test.sh" \
    --err-trap-regression-child 2>&1)"; then
    printf 'ERR trap regression child unexpectedly succeeded\n' >&2
    return 1
  else
    status=$?
  fi

  expected_line="$(
    rg -n '^  false # err-trap-regression-child$' \
      "$REPO/scripts/agent-config-check.test.sh"
  )"
  expected_line="${expected_line%%:*}"
  [ "$status" -eq 1 ]
  grep -Fq \
    "agent-config-check.test.sh:$expected_line: unhandled failure status=1 command=false" \
    <<<"$output"
}

if [ "${1:-}" = '--err-trap-regression-child' ]; then
  false # err-trap-regression-child
fi

if [ "${1:-}" = '--err-trap-regression-only' ]; then
  run_err_trap_regression
  printf 'ok: top-level ERR trap reports line, status, and command\n'
  exit 0
fi

if [ "${1:-}" = '--quiet-child-regression-only' ]; then
  run_quiet_child_regression
  printf 'ok: quiet child failures preserve status and diagnostics\n'
  exit 0
fi

if [ "${1:-}" = '--lifecycle-child-only' ]; then
  run_quiet_child 'Codex lifecycle wrapper tests' \
    "$REPO/dotfiles/codex/hooks/codex-lifecycle-wrappers.test.sh"
  printf 'ok: Codex lifecycle wrapper child is quiet and green\n'
  exit 0
fi

run_codex_mcp_inventory_fixture() {
  local codex_inventory codex_inventory_elapsed_ms codex_inventory_start_ns

  mkdir -p "$scratch/bin"
  cat >"$scratch/bin/codex-credential-gate" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CODEX_CREDENTIAL_GATE_CALLS"
if [ "$*" != '-c mcp_servers.linear-mcp-msa-new.enabled=false mcp list --json' ]; then
  printf 'credential backend entered\n' >"$CODEX_CREDENTIAL_GATE_MARKER"
  trap 'exit 0' TERM
  while :; do sleep 3600; done
fi
printf '%s\n' '[
  {"name":"linear-mcp-msa-new","enabled":false},
  {"name":"north","enabled":true}
]'
SH
  chmod +x "$scratch/bin/codex-credential-gate"
  : >"$scratch/codex-credential-gate-calls"
  if CODEX_CREDENTIAL_GATE_CALLS="$scratch/codex-credential-gate-calls" \
     CODEX_CREDENTIAL_GATE_MARKER="$scratch/codex-credential-gate-marker" \
     timeout --signal=TERM --kill-after=0.1 0.1 \
       "$scratch/bin/codex-credential-gate" mcp list >/dev/null 2>&1; then
    printf 'credential-gated Codex inventory unexpectedly succeeded\n' >&2
    exit 1
  else
    [ "$?" -eq 124 ]
  fi
  [ -s "$scratch/codex-credential-gate-marker" ]
  rm -f "$scratch/codex-credential-gate-marker"

  codex_inventory_start_ns="$(date +%s%N)"
  codex_inventory="$(
    CODEX_BIN="$scratch/bin/codex-credential-gate" \
    CODEX_CREDENTIAL_GATE_CALLS="$scratch/codex-credential-gate-calls" \
    CODEX_CREDENTIAL_GATE_MARKER="$scratch/codex-credential-gate-marker" \
      run_codex_mcp_inventory 0.5
  )"
  codex_inventory_elapsed_ms=$((($(date +%s%N) - codex_inventory_start_ns) / 1000000))
  [ "$codex_inventory_elapsed_ms" -lt 1000 ]
  [ ! -e "$scratch/codex-credential-gate-marker" ]
  [ "$(tail -n 1 "$scratch/codex-credential-gate-calls")" = \
    '-c mcp_servers.linear-mcp-msa-new.enabled=false mcp list --json' ]
  codex_mcp_inventory_server_has_state "$codex_inventory" north true
  codex_mcp_inventory_server_has_state \
    "$codex_inventory" linear-mcp-msa-new false
  if codex_mcp_inventory_server_has_state \
     "$codex_inventory" linear-mcp-msa-new true; then
    printf 'disabled Linear OAuth server was accepted as enabled\n' >&2
    exit 1
  fi
}

run_locked_hook_provenance_fixture() {
  local source_repo="$scratch/locked-hook-source"
  local live="$scratch/locked-hook-live"
  local post_lock_live="$scratch/post-lock-hook-live"
  local relative='hooks/provider-hook.sh'
  local post_lock_relative='hooks/post-lock-hook.sh'
  local locked_revision
  local firn_source="$scratch/firn-hook-source"
  local firn_live="$scratch/firn-hook-live"

  mkdir -p "$source_repo/hooks"
  git -C "$source_repo" init -q
  git -C "$source_repo" config user.email test@example.invalid
  git -C "$source_repo" config user.name hook-provenance-test
  printf '%s\n' '#!/usr/bin/env bash' 'printf locked\\n' \
    >"$source_repo/$relative"
  git -C "$source_repo" add "$relative"
  git -C "$source_repo" commit -qm locked
  locked_revision="$(git -C "$source_repo" rev-parse HEAD)"
  cp "$source_repo/$relative" "$live"

  printf '%s\n' '#!/usr/bin/env bash' 'printf checkout-ahead\\n' \
    >"$source_repo/$relative"
  printf '%s\n' '#!/usr/bin/env bash' 'printf post-lock\\n' \
    >"$source_repo/$post_lock_relative"
  git -C "$source_repo" add "$relative" "$post_lock_relative"
  git -C "$source_repo" commit -qm checkout-ahead

  managed_hook_source_matches \
    "$live" "$source_repo/$relative" north "$source_repo" \
    "$locked_revision" "$relative"

  cp "$source_repo/$relative" "$live"
  if managed_hook_source_matches \
     "$live" "$source_repo/$relative" north "$source_repo" \
     "$locked_revision" "$relative"; then
    printf 'checkout-ahead provider bytes were accepted as locked bytes\n' >&2
    exit 1
  fi

  cp "$source_repo/$post_lock_relative" "$post_lock_live"
  if managed_hook_source_matches \
     "$post_lock_live" "$source_repo/$post_lock_relative" north "$source_repo" \
     "$locked_revision" "$post_lock_relative"; then
    printf 'post-lock-added provider path was accepted at the locked revision\n' >&2
    exit 1
  fi

  cp "$source_repo/$relative" "$live"
  if managed_hook_source_matches \
     "$live" "$source_repo/$relative" north "$source_repo" \
     invalid "$relative"; then
    printf 'invalid provider revision was accepted\n' >&2
    exit 1
  fi
  if managed_hook_source_matches \
     "$live" "$source_repo/$relative" north "$source_repo" \
     '' "$relative"; then
    printf 'missing provider revision was accepted\n' >&2
    exit 1
  fi
  if managed_hook_source_matches \
     "$live" "$source_repo/$relative" north "$source_repo" \
     ffffffffffffffffffffffffffffffffffffffff "$relative"; then
    printf 'unavailable provider revision was accepted\n' >&2
    exit 1
  fi

  printf '%s\n' '#!/usr/bin/env bash' 'printf firn\\n' >"$firn_source"
  cp "$firn_source" "$firn_live"
  managed_hook_source_matches \
    "$firn_live" "$firn_source" self '' '' 'unused'
  printf '%s\n' '#!/usr/bin/env bash' 'printf mutated\\n' >"$firn_source"
  if managed_hook_source_matches \
     "$firn_live" "$firn_source" self '' '' 'unused'; then
    printf 'Firn self-source mutation was accepted\n' >&2
    exit 1
  fi
}

run_north_activation_fixture() {
  local activation="$scratch/activation.json"
  local missing="$scratch/missing-activation.json"

  [ "$(AGENT_CONFIG_ACTIVATION_FILE="$missing" north_unit_activity_state module coordination)" = unknown ]
  ! AGENT_CONFIG_ACTIVATION_FILE="$missing" north_unit_activity_is_active module coordination

  cat >"$activation" <<'JSON'
{"schema":"north.agent-activation/v1","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[{"id":"coordination","kind":"module","permission":"off","active":false},{"id":"agent-spawn-guard","kind":"hook","permission":"on","active":true}]}
JSON
  [ "$(AGENT_CONFIG_ACTIVATION_FILE="$activation" north_unit_activity_state module coordination)" = off ]
  ! AGENT_CONFIG_ACTIVATION_FILE="$activation" north_unit_activity_is_active module coordination
  [ "$(AGENT_CONFIG_ACTIVATION_FILE="$activation" north_unit_activity_state hook agent-spawn-guard)" = on ]
  AGENT_CONFIG_ACTIVATION_FILE="$activation" north_unit_activity_is_active hook agent-spawn-guard
  [ "$(AGENT_CONFIG_ACTIVATION_FILE="$activation" north_unit_activity_state hook absent-hook)" = off ]
  ! AGENT_CONFIG_ACTIVATION_FILE="$activation" north_unit_activity_is_active hook absent-hook

  sed -i 's/"permission":"on"/"permission":"off:until=2099-01-01T00:00:00Z"/' "$activation"
  [ "$(AGENT_CONFIG_ACTIVATION_FILE="$activation" north_unit_activity_state hook agent-spawn-guard)" = invalid ]
  ! AGENT_CONFIG_ACTIVATION_FILE="$activation" north_unit_activity_is_active hook agent-spawn-guard

  sed -i 's/"permission":"off:until=2099-01-01T00:00:00Z"/"permission":"off"/' "$activation"
  [ "$(AGENT_CONFIG_ACTIVATION_FILE="$activation" north_unit_activity_state hook agent-spawn-guard)" = invalid ]
  ! AGENT_CONFIG_ACTIVATION_FILE="$activation" north_unit_activity_is_active hook agent-spawn-guard

  sed -i 's#north.agent-activation/v1#north.agent-activation/invalid#' "$activation"
  [ "$(AGENT_CONFIG_ACTIVATION_FILE="$activation" north_unit_activity_state hook agent-spawn-guard)" = invalid ]
  ! AGENT_CONFIG_ACTIVATION_FILE="$activation" north_unit_activity_is_active hook agent-spawn-guard
}

run_policy_contract_fixture() {
  local base="$scratch/policy-contract-base"
  local north_root="$NORTH_REPO"
  local north_catalog="${NORTH_AGENT_CATALOG:-$north_root/agent-catalog/sources.json}"
  local north_bb="${NORTH_BB:-$HOME/.local/state/north/runtime-profile/bin/bb}"
  local preamble='Provider-neutral bootstrap.'
  local route='- Repository edits, lanes, pins, commits, landing, or pushes → `repo-safety`.'
  local destination='Repository writes belong in a lane.'
  local firn_destination='Firn belongs to this repository.'
  local credential='Never expose credentials.'
  local repo_claim='Use repository modules.'
  local preamble_digest route_digest destination_digest firn_destination_digest credential_digest repo_digest

  NORTH_AGENT_CATALOG="$north_catalog" \
  NORTH_REPO_ROOTS="{\"nixos-config\":\"$REPO\",\"north\":\"$north_root\"}" \
  AGENT_POLICY_NORTH_CATALOG_LIB="$north_root/cli/agent-catalog.clj" \
    "$REPO/scripts/agent-config-check.sh" --policy-only >/dev/null

  preamble_digest="$(printf %s "$preamble" | sha256sum | awk '{print $1}')"
  route_digest="$(printf %s "$route" | sha256sum | awk '{print $1}')"
  destination_digest="$(printf %s "$destination" | sha256sum | awk '{print $1}')"
  firn_destination_digest="$(printf %s "$firn_destination" | sha256sum | awk '{print $1}')"
  credential_digest="$(printf %s "$credential" | sha256sum | awk '{print $1}')"
  repo_digest="$(printf %s "$repo_claim" | sha256sum | awk '{print $1}')"
  mkdir -p "$base/policy" "$base/skills/repo-safety" "$base/skills/firn" \
    "$base/skills/source-fixture" "$base/skills/package-fixture" \
    "$base/hooks" "$base/support" "$base/agent-catalog" \
    "$base/dotfiles/agents" "$base/contracts"
  printf '# Global\n\n%s\n\n## Routes\n\n%s\n\n## Credentials\n\n%s\n' \
    "$preamble" "$route" "$credential" >"$base/policy/AGENTS.md"
  printf '# Repository\n\n## Architecture\n\n%s\n' "$repo_claim" \
    >"$base/policy/REPO-AGENTS.md"
  printf '%s\n' '---' 'name: repo-safety' 'category: git' \
    'description: Protect repository work.' '---' '' '# Repo safety' '' "$destination" \
    >"$base/skills/repo-safety/SKILL.md"
  printf '%s\n' '---' 'name: firn' 'category: nixos' \
    'description: Author Firn configuration.' '---' '' '# Firn' '' "$firn_destination" \
    >"$base/skills/firn/SKILL.md"
  printf '%s\n' '---' 'name: source-fixture' \
    'description: Source catalog fixture.' '---' '' '# Source fixture' \
    >"$base/skills/source-fixture/SKILL.md"
  printf '%s\n' '---' 'name: package-fixture' \
    'description: Package catalog fixture.' '---' '' '# Package fixture' \
    >"$base/skills/package-fixture/SKILL.md"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
    >"$base/hooks/launch-critical-worktree-guard.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$base/support/harness-dial.sh"
  cat >"$base/requirements.toml" <<'TOML'
[hooks]
managed_dir = "/etc/codex/hooks"
[[hooks.PreToolUse]]
matcher = "^(Edit|Write|MultiEdit|apply_patch)$"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "/etc/codex/hooks/runtime/bash /etc/codex/hooks/launch-critical-worktree-guard.sh"
[[hooks.PreToolUse]]
matcher = "^Bash$"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "/etc/codex/hooks/runtime/bash /etc/codex/hooks/launch-critical-worktree-guard.sh"
TOML
  cat >"$base/claude-hooks.json" <<'JSON'
{"hooks":{"PreToolUse":[
  {"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"/home/tom/.agents/hooks/launch-critical-worktree-guard.sh"}]},
  {"matcher":"Bash","hooks":[{"type":"command","command":"/home/tom/.agents/hooks/launch-critical-worktree-guard.sh"}]}
]}}
JSON
  cat >"$base/manifest.toml" <<TOML
version = 1
approved_route = [
  { key = "repository.write-route", owner = "skill:repo-safety", text = "$route", destination_section = "preamble", destination_digest = "$destination_digest" },
]
claim = [
  { key = "bootstrap.discovery", owner = "bootstrap", role = "bootstrap", scope = "machine", surface = "bootstrap", section = "preamble", digest = "$preamble_digest" },
  { key = "repository.write-route", owner = "skill:repo-safety", role = "route", scope = "machine", surface = "bootstrap", section = "Routes", digest = "$route_digest", destination_section = "preamble", destination_digest = "$destination_digest" },
  { key = "firn.source-root", owner = "skill:firn", role = "owner", scope = "machine", surface = "skill", destination_section = "preamble", destination_digest = "$firn_destination_digest" },
  { key = "credentials.boundary", owner = "bootstrap", role = "bootstrap", scope = "machine", surface = "bootstrap", section = "Credentials", digest = "$credential_digest" },
  { key = "repo.example.architecture", owner = "repo:example", role = "owner", scope = "repo:example", surface = "repo", section = "Architecture", digest = "$repo_digest" },
]
guard = [
  { key = "guard.worktree", unit = "launch-critical-worktree-guard", command = "launch-critical-worktree-guard.sh", claude_command = "/home/tom/.agents/hooks/launch-critical-worktree-guard.sh", claude = ["PreToolUse:Edit|Write|MultiEdit", "PreToolUse:Bash"], codex_command = "/etc/codex/hooks/runtime/bash /etc/codex/hooks/launch-critical-worktree-guard.sh", codex = ["PreToolUse:^(Edit|Write|MultiEdit|apply_patch)$", "PreToolUse:^Bash$"] },
]
TOML
  cat >"$base/agent-catalog/sources.json" <<'JSON'
{"$schema":"sources.schema.json","schema":"north.agent-catalog-sources/v1","sources":[
{"id":"north","role":"source","owner":{"repo":"north","path":"agent-catalog/north.json"}},
{"id":"agent-machinery","role":"package","owner":{"repo":"agent-machinery","path":"catalog.json"}},
{"id":"operator","role":"operator","owner":{"repo":"nixos-config","path":"dotfiles/agents/catalog-config.json"}}
]}
JSON
  cat >"$base/agent-catalog/north.json" <<'JSON'
{"$schema":"catalog-config.schema.json","schema":"north.agent-catalog-config/v1","role":"source","units":[
{"id":"source-fixture","kind":"skill","owner":{"repo":"north","path":"skills/source-fixture/SKILL.md"}}
]}
JSON
  cat >"$base/catalog.json" <<'JSON'
{"$schema":"urn:agent-machinery:schema:catalog:v1","schema":"agent-machinery.catalog/v1",
"package":{"name":"@tompassarelli/agent-machinery","version":"0.0.0","license":"MIT OR Apache-2.0"},
"units":[{"id":"package-fixture","kind":"skill","source":"skills/package-fixture/SKILL.md"}],
"assets":[{"id":"package-fixture-asset","type":"instructions","path":"doctrine.md"}],
"contracts":[{"id":"package-fixture-contract","schema":"contracts/schema.json","schemaScope":"structural","fixtures":"contracts/fixtures.json","validator":"validateContract"}]}
JSON
  printf '%s\n' 'Package fixture.' >"$base/doctrine.md"
  printf '%s\n' '{}' >"$base/contracts/schema.json"
  printf '%s\n' '{}' >"$base/contracts/fixtures.json"
  cat >"$base/dotfiles/agents/catalog-config.json" <<'JSON'
{"$schema":"catalog-config.schema.json","schema":"north.agent-catalog-config/v1","role":"operator",
"baselines":[{"id":"global-bootstrap","owner":{"repo":"nixos-config","path":"policy/AGENTS.md"},"targets":["shared"]}],
"providerSupport":[{"id":"activation-gate","owner":{"repo":"nixos-config","path":"support/harness-dial.sh"},"path":"lib/harness-dial.sh"}],
"rootOrder":["repo-safety","firn"],
"registrations":{
"repo-safety":{"kind":"skill","category":"git","owner":{"repo":"nixos-config","path":"skills/repo-safety/SKILL.md"}},
"firn":{"kind":"skill","category":"nixos","owner":{"repo":"nixos-config","path":"skills/firn/SKILL.md"}},
"launch-critical-worktree-guard":{"kind":"hook","category":"authoring","owner":{"repo":"nixos-config","path":"hooks/launch-critical-worktree-guard.sh"}}
},
"activation":{
"source-fixture":{"distributions":[{"type":"skill","targets":["shared"]}]},
"package-fixture":{"distributions":[{"type":"skill","targets":["shared"]}]},
"repo-safety":{"distributions":[{"type":"skill","targets":["shared"]}]},
"firn":{"distributions":[{"type":"skill","targets":["shared"]}]},
"launch-critical-worktree-guard":{"supports":["repo-safety"],"distributions":[{"type":"hook","targets":["codex"]}]}
}}
JSON

  chmod 0644 "$base/skills/repo-safety/SKILL.md" "$base/skills/firn/SKILL.md" \
    "$base/hooks/launch-critical-worktree-guard.sh" "$base/support/harness-dial.sh"
  git -C "$base" init -q
  git -C "$base" config user.name 'Policy Fixture'
  git -C "$base" config user.email 'policy-fixture@example.invalid'
  git -C "$base" add policy/AGENTS.md policy/REPO-AGENTS.md \
    skills/repo-safety/SKILL.md skills/firn/SKILL.md \
    skills/source-fixture/SKILL.md skills/package-fixture/SKILL.md requirements.toml \
    claude-hooks.json \
    hooks/launch-critical-worktree-guard.sh support/harness-dial.sh \
    manifest.toml catalog.json doctrine.md contracts/schema.json \
    contracts/fixtures.json agent-catalog/sources.json agent-catalog/north.json \
    dotfiles/agents/catalog-config.json
  git -C "$base" commit -qm 'Build policy fixture'

  NORTH_AGENT_CATALOG="$base/agent-catalog/sources.json" \
  NORTH_REPO_ROOTS="{\"nixos-config\":\"$base\",\"north\":\"$base\",\"agent-machinery\":\"$base\"}" \
    bb -e '
      (require (quote [cheshire.core :as json]))
      (load-file (first *command-line-args*))
      (let [load-catalog (ns-resolve (quote north.agent-catalog) (quote load-catalog))
            compile-activation (ns-resolve (quote north.agent-catalog) (quote compile-activation))
            default-permissions (ns-resolve (quote north.agent-catalog) (quote default-permissions))
            catalog (load-catalog)]
        (print (json/generate-string
                 (compile-activation
                   catalog
                   (assoc (default-permissions catalog)
                          "repo-safety" "on"
                          "firn" "on"
                          "launch-critical-worktree-guard" "on")))))' \
      "$north_root/cli/agent-catalog.clj" >"$base/activation.json"

  run_policy_case() {
    local root="$1"
    NORTH_BB="$north_bb" \
    HOME="$root" \
    AGENT_POLICY_MANIFEST="$root/manifest.toml" \
    AGENT_POLICY_BOOTSTRAP="$root/policy/AGENTS.md" \
    AGENT_POLICY_REPO_AGENTS="$root/policy/REPO-AGENTS.md" \
    AGENT_POLICY_CODEX_REQUIREMENTS="$root/requirements.toml" \
    AGENT_POLICY_CLAUDE_HOOKS="$root/claude-hooks.json" \
    AGENT_POLICY_ACTIVATION="$root/activation.json" \
    NORTH_AGENT_CATALOG="$root/agent-catalog/sources.json" \
    NORTH_REPO_ROOTS="{\"nixos-config\":\"$root\",\"north\":\"$root\",\"agent-machinery\":\"$root\"}" \
    AGENT_POLICY_NORTH_CATALOG_LIB="$north_root/cli/agent-catalog.clj" \
      python3 "$REPO/scripts/agent-policy-contract.py" --repo "$root" --local
  }

  run_policy_source_case() {
    local root="$1"
    NORTH_BB="$north_bb" \
    HOME="$root" \
    AGENT_POLICY_MANIFEST="$root/manifest.toml" \
    AGENT_POLICY_BOOTSTRAP="$root/policy/AGENTS.md" \
    AGENT_POLICY_REPO_AGENTS="$root/policy/REPO-AGENTS.md" \
    AGENT_POLICY_CODEX_REQUIREMENTS="$root/requirements.toml" \
    AGENT_POLICY_CLAUDE_HOOKS="$root/claude-hooks.json" \
    NORTH_AGENT_CATALOG="$root/agent-catalog/sources.json" \
    NORTH_REPO_ROOTS="{\"nixos-config\":\"$root\",\"north\":\"$root\",\"agent-machinery\":\"$root\"}" \
    AGENT_POLICY_NORTH_CATALOG_LIB="$north_root/cli/agent-catalog.clj" \
      python3 "$REPO/scripts/agent-policy-contract.py" --repo "$root"
  }

  expect_policy_reject() {
    local name="$1" expected="$2" root="$scratch/policy-$1" output
    cp -a "$base" "$root"
    shift 2
    "$@" "$root"
    if output="$(run_policy_case "$root" 2>&1)"; then
      printf 'policy fixture %s unexpectedly passed\n' "$name" >&2
      return 1
    fi
    grep -Fq "$expected" <<<"$output" || {
      printf 'policy fixture %s missed diagnostic %s:\n%s\n' "$name" "$expected" "$output" >&2
      return 1
    }
  }

  expect_policy_source_reject() {
    local name="$1" expected="$2" root="$scratch/policy-$1" output
    cp -a "$base" "$root"
    shift 2
    "$@" "$root"
    if output="$(run_policy_source_case "$root" 2>&1)"; then
      printf 'policy source fixture %s unexpectedly passed\n' "$name" >&2
      return 1
    fi
    grep -Fq "$expected" <<<"$output" || {
      printf 'policy source fixture %s missed diagnostic %s:\n%s\n' "$name" "$expected" "$output" >&2
      return 1
    }
  }

  mutate_duplicate_owner() {
    sed -i '0,/key = "bootstrap.discovery"/s//key = "credentials.boundary"/' "$1/manifest.toml"
  }
  mutate_unmapped() { printf '\nA newly unmapped rule.\n' >>"$1/policy/AGENTS.md"; }
  mutate_skill_procedure() {
    sed -i 's/owner = "bootstrap", role = "bootstrap", scope = "machine", surface = "bootstrap", section = "Credentials"/owner = "skill:repo-safety", role = "owner", scope = "machine", surface = "bootstrap", section = "Credentials"/' "$1/manifest.toml"
  }
  mutate_procedural_route() {
    local old='- Repository edits, lanes, pins, commits, landing, or pushes → `repo-safety`.'
    local new='- Repository writes; create a lane and stage paths → `repo-safety`.'
    local old_digest new_digest
    old_digest="$(printf %s "$old" | sha256sum | awk '{print $1}')"
    new_digest="$(printf %s "$new" | sha256sum | awk '{print $1}')"
    sed -i "s|$old_digest|$new_digest|" "$1/manifest.toml"
    sed -i 's/Repository edits, lanes, pins, commits, landing, or pushes →/Repository writes; create a lane and stage paths →/' "$1/policy/AGENTS.md"
  }
  mutate_codex_hook_path() {
    sed -i 's#/etc/codex/hooks/launch-critical-worktree-guard.sh#/tmp/launch-critical-worktree-guard.sh#' "$1/requirements.toml"
  }
  mutate_claude_hook_path() {
    sed -i 's#/home/tom/.agents/hooks/launch-critical-worktree-guard.sh#/tmp/launch-critical-worktree-guard.sh#' "$1/claude-hooks.json"
  }
  mutate_activation_schema() {
    sed -i 's#north.agent-activation/v1#north.agent-activation/invalid#' "$1/activation.json"
  }
  mutate_activation_permission() {
    sed -i 's/"permission":"on"/"permission":true/' "$1/activation.json"
  }
  mutate_activation_ttl_permission() {
    sed -i 's/"permission":"on"/"permission":"off:until=2099-01-01T00:00:00Z"/' "$1/activation.json"
  }
  mutate_activation_off_active() {
    sed -i 's/"permission":"on"/"permission":"off"/' "$1/activation.json"
  }
  mutate_activation_catalog_digest() {
    sed -i 's/"catalogDigest":"sha256:[0-9a-f]*"/"catalogDigest":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"/' "$1/activation.json"
  }
  mutate_activation_missing_hook() {
    jq '.units |= map(select(.id != "launch-critical-worktree-guard"))' \
      "$1/activation.json" >"$1/activation.next"
    mv "$1/activation.next" "$1/activation.json"
  }
  mutate_activation_missing_skill() {
    jq '.units |= map(select(.id != "firn"))' \
      "$1/activation.json" >"$1/activation.next"
    mv "$1/activation.next" "$1/activation.json"
  }
  mutate_activation_duplicate_skill() {
    jq '.units += [.units[] | select(.id == "firn")]' \
      "$1/activation.json" >"$1/activation.next"
    mv "$1/activation.next" "$1/activation.json"
  }
  mutate_activation_owner() {
    jq '(.units[] | select(.id == "repo-safety") | .owner.path) = "skills/firn/SKILL.md"' \
      "$1/activation.json" >"$1/activation.next"
    mv "$1/activation.next" "$1/activation.json"
  }
  mutate_missing_owner_provenance() {
    jq 'del(.units[] | select(.id == "repo-safety") | .ownerProvenance)' \
      "$1/activation.json" >"$1/activation.next"
    mv "$1/activation.next" "$1/activation.json"
  }
  mutate_wrong_provenance_owner() {
    jq '(.units[] | select(.id == "repo-safety") | .ownerProvenance.owner.path) = "skills/firn/SKILL.md"' \
      "$1/activation.json" >"$1/activation.next"
    mv "$1/activation.next" "$1/activation.json"
  }
  mutate_wrong_provenance_revision() {
    jq '(.units[] | select(.id == "repo-safety") | .ownerProvenance.revision) = "ffffffffffffffffffffffffffffffffffffffff"' \
      "$1/activation.json" >"$1/activation.next"
    mv "$1/activation.next" "$1/activation.json"
  }
  mutate_wrong_provenance_digest() {
    jq '(.units[] | select(.id == "repo-safety") | .ownerProvenance.contentDigest) = "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"' \
      "$1/activation.json" >"$1/activation.next"
    mv "$1/activation.next" "$1/activation.json"
  }
  mutate_missing_destination_block() {
    sed -i 's/Repository writes belong in a lane./A different procedure lives here./' \
      "$1/skills/repo-safety/SKILL.md"
  }
  mutate_route_destination() {
    sed -i '/role = "route"/s/destination_section = "preamble"/destination_section = "missing"/' \
      "$1/manifest.toml"
  }
  mutate_missing_destination_metadata() {
    sed -i '/key = "firn.source-root"/s/destination_section = "preamble", //' \
      "$1/manifest.toml"
  }
  mutate_malformed_destination_digest() {
    sed -i '/key = "firn.source-root"/s/[0-9a-f]\{64\}/not-a-digest/' \
      "$1/manifest.toml"
  }
  mutate_wrong_destination_digest() {
    sed -i '/key = "firn.source-root"/s/[0-9a-f]\{64\}/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee/' \
      "$1/manifest.toml"
  }
  mutate_stale_skill_source() {
    printf '\nA stale unclaimed block.\n' >>"$1/skills/repo-safety/SKILL.md"
  }
  mutate_catalog_owner_escape() {
    sed -i 's#skills/repo-safety/SKILL.md#../outside/SKILL.md#' \
      "$1/dotfiles/agents/catalog-config.json"
  }
  mutate_catalog_owner_swap() {
    sed -i 's#skills/repo-safety/SKILL.md#skills/firn/SKILL.md#' \
      "$1/dotfiles/agents/catalog-config.json"
  }
  mutate_repo_scope() {
    sed -i 's/scope = "repo:example", surface = "repo"/scope = "machine", surface = "repo"/' "$1/manifest.toml"
  }

  run_policy_source_case "$base" >/dev/null
  run_policy_case "$base" >/dev/null
  expect_policy_reject duplicate-owner 'multiple owners for policy key' mutate_duplicate_owner
  expect_policy_reject unmapped 'unmapped normative block' mutate_unmapped
  expect_policy_reject skill-procedure 'skill-owned procedure remains in bootstrap' mutate_skill_procedure
  expect_policy_reject procedural-route 'route differs from the closed approved-route catalog' mutate_procedural_route
  expect_policy_reject codex-hook-path 'Codex provider command drift' mutate_codex_hook_path
  expect_policy_reject claude-hook-path 'native-Claude provider command drift' mutate_claude_hook_path
  expect_policy_reject activation-schema 'North activation schema is not' mutate_activation_schema
  expect_policy_reject activation-permission 'invalid permission' mutate_activation_permission
  expect_policy_reject activation-ttl-permission 'invalid permission' mutate_activation_ttl_permission
  expect_policy_reject activation-off-active 'active despite off permission' mutate_activation_off_active
  expect_policy_reject activation-catalog-digest 'catalogDigest differs from the canonical catalog' mutate_activation_catalog_digest
  expect_policy_reject activation-missing-hook 'provider-bound hook is absent' mutate_activation_missing_hook
  expect_policy_reject activation-missing-skill 'destination skill is absent from North activation' mutate_activation_missing_skill
  expect_policy_reject activation-duplicate-skill 'duplicates global unit id' mutate_activation_duplicate_skill
  expect_policy_reject activation-owner 'activation owner differs from the catalog owner' mutate_activation_owner
  expect_policy_reject missing-owner-provenance 'lacks ownerProvenance' mutate_missing_owner_provenance
  expect_policy_reject wrong-provenance-owner 'activation ownerProvenance differs from the North catalog' mutate_wrong_provenance_owner
  expect_policy_reject wrong-provenance-revision 'activation ownerProvenance differs from the North catalog' mutate_wrong_provenance_revision
  expect_policy_reject wrong-provenance-digest 'activation ownerProvenance differs from the North catalog' mutate_wrong_provenance_digest
  expect_policy_reject stale-skill-source 'activation ownerProvenance differs from the North catalog' mutate_stale_skill_source
  expect_policy_source_reject missing-destination-block 'destination skill block is absent' mutate_missing_destination_block
  expect_policy_source_reject missing-destination-metadata 'destination skill section or digest is invalid' mutate_missing_destination_metadata
  expect_policy_source_reject malformed-destination-digest 'destination skill section or digest is invalid' mutate_malformed_destination_digest
  expect_policy_source_reject wrong-destination-digest 'destination skill block is absent' mutate_wrong_destination_digest
  expect_policy_source_reject catalog-owner-escape 'owner escapes its repository' mutate_catalog_owner_escape
  expect_policy_source_reject catalog-owner-swap 'source declares name' mutate_catalog_owner_swap
  expect_policy_reject route-destination 'route destination differs from the approved catalog' mutate_route_destination
  expect_policy_reject repo-global 'owner role has invalid repository authority' mutate_repo_scope
}

if [ "${1:-}" = '--codex-mcp-inventory-only' ]; then
  source "$REPO/scripts/agent-config-check.sh"
  run_codex_mcp_inventory_fixture
  printf 'ok: Codex noninteractive MCP inventory excludes the credential-gated Linear server\n'
  exit 0
fi

if [ "${1:-}" = '--locked-hook-provenance-only' ]; then
  source "$REPO/scripts/agent-config-check.sh"
  run_locked_hook_provenance_fixture
  printf 'ok: managed hooks distinguish locked provider blobs from Firn self sources\n'
  exit 0
fi

if [ "${1:-}" = '--north-activation-only' ]; then
  source "$REPO/scripts/agent-config-check.sh"
  run_north_activation_fixture
  printf 'ok: advisory reads the singular North activation generation\n'
  exit 0
fi

if [ "${1:-}" = '--policy-contract-only' ]; then
  run_policy_contract_fixture
  printf 'ok: singular catalog policy rejects ownership, provider, and activation drift\n'
  exit 0
fi

report="$("$REPO/scripts/agent-config-check.sh")"
managed_binding_count="$(python3 - "$REPO/modules/codex/requirements.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    requirements = tomllib.load(handle)

print(sum(
    len(group.get("hooks", []))
    for groups in requirements["hooks"].values()
    if isinstance(groups, list)
    for group in groups
))
PY
)"
python3 - "$REPO/modules/codex/requirements.toml" <<'PY'
import pathlib
import sys
import tomllib

with pathlib.Path(sys.argv[1]).open("rb") as handle:
    hooks = tomllib.load(handle)["hooks"]
for event in ("SubagentStop",):
    groups = hooks.get(event)
    assert isinstance(groups, list) and len(groups) == 1
    commands = groups[0].get("hooks")
    assert isinstance(commands, list) and len(commands) == 1
    command = commands[0]
    assert command["timeout"] == 3
    assert command["command"].endswith(
        "/etc/codex/hooks/runtime/bash /etc/codex/hooks/north-on-terminal-codex"
    )
PY
grep -Fq "$managed_binding_count managed authoritative bindings" <<<"$report"
run_quiet_child 'Codex lifecycle wrapper tests' \
  "$REPO/dotfiles/codex/hooks/codex-lifecycle-wrappers.test.sh"
grep -Fq '"/code/nixos-config/main/dotfiles/bin"' \
  "$REPO/modules/bash/default.bnix"
grep -Fq 'Live safe-push follows the Firn checkout and supports explicit --to destinations' \
  "$REPO/scripts/agent-config-check.sh"

# A deterministic route probe is diagnostic evidence, not provider preference.
# The compact harness report must summarize the allocation policy itself.
if grep -Fq '.diagnosticRouteProbe' "$REPO/scripts/agent-config-check.sh"; then
  printf 'agent-config-check must not present diagnosticRouteProbe as routing policy\n' >&2
  exit 1
fi
grep -Fq '"Allocation  ' \
  "$REPO/scripts/agent-config-check.sh"

source "$REPO/scripts/agent-config-check.sh"
run_locked_hook_provenance_fixture

for target in \
  instructions/shared/AGENTS.md \
  skills/shared \
  provider-hooks \
  instructions/code/AGENTS.md; do
  grep -Fq "/.local/state/north/agents/current/$target" \
    "$REPO/scripts/agent-config-check.sh"
done
if rg -n 'LIVE_SHARED|LIVE_SKILLS_FARM|AGENT_CONFIG_LIVE_NORTH_PROFILE' \
  "$REPO/scripts/agent-config-check.sh"; then
  printf 'agent-config-check still carries a legacy live profile farm\n' >&2
  exit 1
fi

# Sealed promotion replaces store residency as the immutability proof for the
# North/Beagle managed hooks. Only a real promote can produce root-owned 0444
# content, so the accepted shape is the live deployment; each rejection case
# mutates exactly one clause of that shape.
promoted_root="$scratch/enforcement"
promoted_live="$scratch/live-promoted"
promoted_relative=''
promoted_sibling=''
real_enforcement="${NORTH_ENFORCEMENT_STATE_ROOT:-/var/lib/north-enforcement}"
mkdir -p "$promoted_root/active" "$promoted_live"
if [ -d "$real_enforcement/deployments" ] && [ -r "$real_enforcement/active/record" ]; then
  ln -s "$real_enforcement/deployments" "$promoted_root/deployments"
  ln -s "$(readlink -f "$real_enforcement/active/current")" "$promoted_root/active/current"
  cp "$real_enforcement/active/record" "$promoted_root/active/record"
  chmod u+w "$promoted_root/active/record"
  if ! grep -q '^NIXOS_REV ' "$promoted_root/active/record"; then
    nixos_fixture_revision="$(git -C "$REPO" rev-parse HEAD)"
    sed -i "/^NORTH_REV /i NIXOS_REV $nixos_fixture_revision" \
      "$promoted_root/active/record"
  fi
  promoted_relative="$(
    awk '$1 == "FILE" { print $3; exit }' "$promoted_root/active/record"
  )"
  promoted_sibling="$(
    awk -v first="$promoted_relative" \
      '$1 == "FILE" && $3 != first { print $3; exit }' \
      "$promoted_root/active/record"
  )"
  [ -n "$promoted_relative" ]
  [ -n "$promoted_sibling" ]
  NORTH_ENFORCEMENT_ROOT="$promoted_root"

  [ "$(stat -c '%u:%a:%h' "$promoted_root/active/current/$promoted_relative")" = '0:444:1' ]
  ln -s "$promoted_root/active/current/$promoted_relative" \
    "$promoted_live/agent-spawn-guard.sh"
  sealed_promoted_file "$promoted_live/agent-spawn-guard.sh" "$promoted_relative"
  [[ "$(promote_record_revision nixos)" =~ ^[0-9a-f]{40}$ ]]
  [[ "$(promote_record_revision north)" =~ ^[0-9a-f]{40}$ ]]
  [[ "$(promote_record_revision beagle)" =~ ^[0-9a-f]{40}$ ]]

  ln -s "$promoted_root/active/current/$promoted_sibling" \
    "$promoted_live/wrong-target.sh"
  if sealed_promoted_file "$promoted_live/wrong-target.sh" "$promoted_relative"; then
    printf 'a sealed file from the wrong promoted path was accepted\n' >&2
    exit 1
  fi

  sed -i "s|^FILE [0-9a-f]\{64\}  $promoted_relative\$|FILE $(printf 'f%.0s' {1..64})  $promoted_relative|" \
    "$promoted_root/active/record"
  if sealed_promoted_file "$promoted_live/agent-spawn-guard.sh" "$promoted_relative"; then
    printf 'a promoted file that differs from its recorded digest was accepted\n' >&2
    exit 1
  fi

  grep -v "  $promoted_relative\$" "$real_enforcement/active/record" \
    >"$promoted_root/active/record"
  if sealed_promoted_file "$promoted_live/agent-spawn-guard.sh" "$promoted_relative"; then
    printf 'a promoted file absent from the promote record was accepted\n' >&2
    exit 1
  fi

  sed 's/^NORTH_REV .*/NORTH_REV not-a-revision/' "$real_enforcement/active/record" \
    >"$promoted_root/active/record"
  if promote_record_revision north >/dev/null 2>&1; then
    printf 'a malformed promote record revision was accepted\n' >&2
    exit 1
  fi

  rm -f "$promoted_root/active/record"
  if promote_record_revision north >/dev/null 2>&1; then
    printf 'a missing promote record produced a revision\n' >&2
    exit 1
  fi
  if sealed_promoted_file "$promoted_live/agent-spawn-guard.sh" "$promoted_relative"; then
    printf 'a promoted file with no promote record was accepted\n' >&2
    exit 1
  fi
else
  printf 'note: no promoted enforcement deployment; sealed-promotion cases skipped\n' >&2
fi
NORTH_ENFORCEMENT_ROOT="$real_enforcement"

# The generation must name the promoted payload, and the promoted hooks must no
# longer be pinned to a flake input.
grep -Fq '(promoted "agent-spawn-guard.sh" "north/agent-runtime/hooks/agent-spawn-guard.sh")' \
  "$REPO/modules/codex/default.bnix"
for adapter in \
  north-on-spawn-codex \
  north-on-tooluse-codex \
  north-mark-delegated-codex \
  north-on-stop-codex \
  north-on-terminal-codex; do
  grep -Fq \
    "{:source (s flakeRoot \"/dotfiles/codex/hooks/$adapter\")}" \
    "$REPO/modules/codex/default.bnix"
done
grep -Fq '(promoted "beagle-session-start.sh" "beagle/integrations/north/hooks/beagle-session-start.sh")' \
  "$REPO/modules/codex/default.bnix"
grep -Fq '(promoted "firn-system-policy" "north/agent-runtime/hooks/firn-system-policy.sh")' \
  "$REPO/modules/codex/default.bnix"
grep -Fq '(providerAdapter "lib/north-agent-activation.sh")' \
  "$REPO/modules/codex/default.bnix"
grep -Fq '(promoted "lib/authoring-killswitch.sh" "north/agent-runtime/hooks/lib/authoring-killswitch.sh")' \
  "$REPO/modules/codex/default.bnix"
grep -Fq '(promoted "lib/harness-dial.sh" "north/agent-runtime/hooks/lib/harness-dial.sh")' \
  "$REPO/modules/codex/default.bnix"
grep -Fq 'enforcement "/var/lib/north-enforcement/active/current"' \
  "$REPO/modules/codex/default.bnix"
if grep -Fq '(s inputs.north "/agent-profile/hooks/' "$REPO/modules/codex/default.bnix"; then
  printf 'Codex module still pins a promoted North hook to the flake input\n' >&2
  exit 1
fi
if grep -Eq 'providerAdapter "(beagle-session-start\.sh|north-(on|mark-))' \
  "$REPO/modules/codex/default.bnix"; then
  printf 'Codex module still sources sealed or Nix-supplied hooks from activation\n' >&2
  exit 1
fi

managed_policy="$REPO/modules/codex/requirements.toml"
[ "$(codex_managed_policy_binding_count "$managed_policy")" = "$managed_binding_count" ]
cp "$managed_policy" "$scratch/managed-policy-not-exclusive.toml"
sed -i 's/^allow_managed_hooks_only = true$/allow_managed_hooks_only = false/' \
  "$scratch/managed-policy-not-exclusive.toml"
if codex_managed_policy_binding_count \
  "$scratch/managed-policy-not-exclusive.toml" >/dev/null 2>&1; then
  printf 'non-exclusive Codex managed policy was accepted\n' >&2
  exit 1
fi
cp "$managed_policy" "$scratch/managed-policy-remote-control-missing.toml"
sed -i '/^allow_remote_control = false$/d' \
  "$scratch/managed-policy-remote-control-missing.toml"
if codex_managed_policy_binding_count \
  "$scratch/managed-policy-remote-control-missing.toml" >/dev/null 2>&1; then
  printf 'Codex managed policy without an explicit remote-control deny was accepted\n' >&2
  exit 1
fi
cp "$managed_policy" "$scratch/managed-policy-remote-control-enabled.toml"
sed -i 's/^allow_remote_control = false$/allow_remote_control = true/' \
  "$scratch/managed-policy-remote-control-enabled.toml"
if codex_managed_policy_binding_count \
  "$scratch/managed-policy-remote-control-enabled.toml" >/dev/null 2>&1; then
  printf 'Codex managed policy with remote control enabled was accepted\n' >&2
  exit 1
fi
cp "$managed_policy" "$scratch/managed-policy-remote-control-wrong-type.toml"
sed -i 's/^allow_remote_control = false$/allow_remote_control = 0/' \
  "$scratch/managed-policy-remote-control-wrong-type.toml"
if codex_managed_policy_binding_count \
  "$scratch/managed-policy-remote-control-wrong-type.toml" >/dev/null 2>&1; then
  printf 'Codex managed policy with a non-boolean remote-control setting was accepted\n' >&2
  exit 1
fi
cp "$managed_policy" "$scratch/managed-policy-hooks-enabled.toml"
sed -i '/^\[hooks\]$/,$d' "$scratch/managed-policy-hooks-enabled.toml"
sed -i '/^managed_hook_failure_mode = "block"$/d' \
  "$scratch/managed-policy-hooks-enabled.toml"
if codex_managed_policy_binding_count \
  "$scratch/managed-policy-hooks-enabled.toml" >/dev/null 2>&1; then
  printf 'Codex policy enabled hooks without the authoritative hook table\n' >&2
  exit 1
fi
cp "$managed_policy" "$scratch/managed-policy-hooks-disabled.toml"
sed -i 's/^hooks = true$/hooks = false/' \
  "$scratch/managed-policy-hooks-disabled.toml"
if codex_managed_policy_binding_count \
  "$scratch/managed-policy-hooks-disabled.toml" >/dev/null 2>&1; then
  printf 'Codex policy disabled hooks while retaining authoritative bindings\n' >&2
  exit 1
fi
# A logical state path may traverse symlinks before Git reports its physical
# worktree root. Canonical identity must accept that alias, but never a distinct
# repository merely because its lexical path looks related.
mkdir -p "$scratch/agent-machinery-real" "$scratch/agent-machinery-distinct"
git -C "$scratch/agent-machinery-real" init -q
git -C "$scratch/agent-machinery-distinct" init -q
ln -s "$scratch/agent-machinery-real" "$scratch/agent-machinery-logical"
agent_machinery_observed="$(
  git -C "$scratch/agent-machinery-logical" rev-parse --path-format=absolute --show-toplevel
)"
managed_source_root_matches "$scratch/agent-machinery-logical" "$agent_machinery_observed"
distinct_observed="$(
  git -C "$scratch/agent-machinery-distinct" rev-parse --path-format=absolute --show-toplevel
)"
if managed_source_root_matches "$scratch/agent-machinery-logical" "$distinct_observed"; then
  printf 'distinct managed Agent Machinery worktree root was accepted through a logical alias\n' >&2
  exit 1
fi

# Deployed provider readiness goes through the packaged closure. The sourceable
# seam makes the exact argv contract hermetic.
mkdir -p "$scratch/bin"
cat >"$scratch/bin/north-packaged" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NORTH_PACKAGED_CALLS"
case "$*" in
  'providers --json')
    printf '%s\n' '{"schemaVersion":3}'
    ;;
  *)
    exit 97
    ;;
esac
SH
chmod +x "$scratch/bin/north-packaged"
: >"$scratch/north-packaged-calls"
NORTH_PACKAGED_CALLS="$scratch/north-packaged-calls" \
  NORTH_PACKAGED_BIN="$scratch/bin/north-packaged" \
  run_north_packaged providers --json >/dev/null
diff -u \
  <(printf '%s\n' 'providers --json') \
  "$scratch/north-packaged-calls"
: >"$scratch/north-packaged-calls"
PATH="$scratch/bin:$PATH" \
NORTH_PACKAGED_CALLS="$scratch/north-packaged-calls" \
  run_north_packaged providers --json >/dev/null
[ "$(<"$scratch/north-packaged-calls")" = 'providers --json' ]

# Successful probes reap their exact GNU-timeout process group immediately.
# The timeout PID is the group leader; the recursive child belongs to that
# group but has a distinct PID.
cat >"$scratch/bin/probe-ps" <<'SH'
#!/usr/bin/env bash
output="$("$REAL_PROBE_PS" "$@")" || exit
pid="${*: -1}"
pgid="${output//[[:space:]]/}"
printf '%s %s\n' "$pid" "$pgid" >>"$PROBE_PS_CALLS"
printf '%s\n' "$output"
SH
chmod +x "$scratch/bin/probe-ps"
: >"$scratch/probe-ps-calls"
fast_probe_start_ns="$(date +%s%N)"
PROBE_PS_BIN="$scratch/bin/probe-ps" \
REAL_PROBE_PS="$(command -v ps)" \
PROBE_PS_CALLS="$scratch/probe-ps-calls" \
NORTH_PACKAGED_CALLS="$scratch/north-packaged-calls" \
NORTH_PACKAGED_BIN="$scratch/bin/north-packaged" \
  run_north_packaged providers --json >/dev/null
fast_probe_elapsed_ms=$((($(date +%s%N) - fast_probe_start_ns) / 1000000))
[ "$fast_probe_elapsed_ms" -lt 1000 ]
mapfile -t probe_pgid_calls <"$scratch/probe-ps-calls"
[ "${#probe_pgid_calls[@]}" -eq 2 ]
read -r probe_timeout_pid probe_timeout_pgid <<<"${probe_pgid_calls[0]}"
read -r probe_child_pid probe_child_pgid <<<"${probe_pgid_calls[1]}"
[ "$probe_timeout_pid" = "$probe_timeout_pgid" ]
[ "$probe_child_pid" != "$probe_timeout_pid" ]
[ "$probe_child_pgid" = "$probe_timeout_pgid" ]

# Same-directory status publication is portable to BSD mv; no GNU -T leaks
# into the recursively executed checker child.
mkdir "$scratch/bsd-path"
cat >"$scratch/bsd-path/mv" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BSD_PROBE_MV_CALLS"
for arg in "$@"; do
  [ "$arg" != -T ] || exit 91
done
exec "$REAL_BSD_PROBE_MV" "$@"
SH
chmod +x "$scratch/bsd-path/mv"
: >"$scratch/bsd-probe-mv-calls"
export BSD_PROBE_MV_CALLS="$scratch/bsd-probe-mv-calls"
REAL_BSD_PROBE_MV="$(command -v mv)"
export REAL_BSD_PROBE_MV
PATH="$scratch/bsd-path:$PATH" \
  run_bounded_process 0.2 "$(command -v true)" >/dev/null
[ "$(wc -l <"$scratch/bsd-probe-mv-calls")" -eq 2 ]
if grep -Eq '(^| )-T( |$)' "$scratch/bsd-probe-mv-calls"; then
  printf 'checker bounded child used nonportable mv -T\n' >&2
  exit 1
fi
unset BSD_PROBE_MV_CALLS REAL_BSD_PROBE_MV

# Exit zero from the outer supervisor is not success without the authenticated
# child-status record. Zero-valued deadlines/kill grace are also rejected
# because GNU timeout treats them as disabled.
if PROBE_TIMEOUT_BIN="$(command -v true)" \
   run_bounded_process 0.1 "$(command -v true)" >/dev/null 2>&1; then
  printf 'missing bounded-probe status was accepted as success\n' >&2
  exit 1
else
  [ "$?" -eq 125 ]
fi
if run_bounded_process 0 "$(command -v true)" >/dev/null 2>&1; then
  printf 'zero probe deadline was accepted\n' >&2
  exit 1
else
  [ "$?" -eq 125 ]
fi
if PROBE_KILL_AFTER_SECONDS=0 \
   run_bounded_process 0.1 "$(command -v true)" >/dev/null 2>&1; then
  printf 'disabled probe KILL grace was accepted\n' >&2
  exit 1
else
  [ "$?" -eq 125 ]
fi

# Network/service-facing wrappers all share the same TERM→KILL boundary. A
# direct command exits on TERM while its descendant ignores TERM and attempts
# delayed mutation; the probe must return 124 only after the group is reaped.
cat >"$scratch/bin/hostile-probe" <<'SH'
#!/usr/bin/env bash
(
  trap '' TERM
  printf '%s\n' "$BASHPID" >"$HUNG_PID_FILE"
  sleep 0.5
  printf '%s\n' leaked >"$HUNG_MUTATION_FILE"
) &
trap 'exit 0' TERM
wait
SH
chmod +x "$scratch/bin/hostile-probe"

assert_hung_probe_reaped() {
  local label="$1" output status pid state
  shift
  rm -f "$scratch/$label.pid" "$scratch/$label.mutation"
  if output="$(
    export HUNG_PID_FILE="$scratch/$label.pid"
    export HUNG_MUTATION_FILE="$scratch/$label.mutation"
    export PROBE_KILL_AFTER_SECONDS=0.1
    export PROBE_POLL_SECONDS=0.01
    "$@" 2>&1
  )"; then
    printf '%s hostile probe unexpectedly succeeded\n' "$label" >&2
    exit 1
  else
    status=$?
  fi
  [ "$status" -eq 124 ]
  [ -z "$output" ]
  [ -s "$scratch/$label.pid" ]
  pid="$(<"$scratch/$label.pid")"
  sleep 0.6
  [ ! -e "$scratch/$label.mutation" ]
  if kill -0 "$pid" 2>/dev/null; then
    state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    case "$state" in Z*|'') ;; *) return 1 ;; esac
  fi
}

CODEX_BIN="$scratch/bin/hostile-probe" \
  assert_hung_probe_reaped codex run_codex_probe 0.1 mcp list
NORTH_PACKAGED_BIN="$scratch/bin/hostile-probe" \
NORTH_PROBE_TIMEOUT_SECONDS=0.1 \
  assert_hung_probe_reaped north run_north_packaged providers --json

# The real Codex inventory consults Secret Service for enabled OAuth servers.
# Model that credential backend as an indefinite wait: the checker must disable
# only Linear while still requiring an enabled North entry.
run_codex_mcp_inventory_fixture

# Per-stream RLIMIT_FSIZE prevents a hostile JSON producer from filling temp
# storage before its whole-process deadline.
cat >"$scratch/bin/flood-probe" <<'SH'
#!/usr/bin/env bash
while printf '%064d\n' 0; do :; done
SH
chmod +x "$scratch/bin/flood-probe"
if PROBE_MAX_OUTPUT_KIB=4 \
   PROBE_KILL_AFTER_SECONDS=0.1 \
   run_bounded_process 0.2 "$scratch/bin/flood-probe" >/dev/null 2>&1; then
  printf 'output-flood probe unexpectedly succeeded\n' >&2
  exit 1
fi

[ "$(printf '%s\n' '{"schemaVersion":2}' | north_provider_schema_version)" = 2 ]
[ "$(printf '%s\n' '{"schemaVersion":3}' | north_provider_schema_version)" = 3 ]
if printf '%s\n' '{"schemaVersion":"3"}' | north_provider_schema_version >/dev/null 2>&1; then
  printf 'string provider schemaVersion was accepted as canonical\n' >&2
  exit 1
fi

# A structurally valid but stale intent is drift, even when its object remains
# available: intent, managed HEAD, and verified flake input must be identical.
verified_revision=1111111111111111111111111111111111111111
stale_intent_revision=2222222222222222222222222222222222222222
agent_machinery_revisions_converged \
  "$verified_revision" "$verified_revision" "$verified_revision"
if agent_machinery_revisions_converged \
  "$stale_intent_revision" "$verified_revision" "$verified_revision"; then
  printf 'stale but valid Agent Machinery intent revision was accepted\n' >&2
  exit 1
fi

# Codex North carries one exact explicit env map. Missing, changed, or extra
# keys are drift rather than "materialized" implicitly by the wrapper.
codex_north_env_is_canonical "$REPO/dotfiles/codex/config.toml"
cp "$REPO/dotfiles/codex/config.toml" "$scratch/codex-extra-env.toml"
sed -i '/^NORTH_PORT = "7977"$/a EXTRA = "not-canonical"' \
  "$scratch/codex-extra-env.toml"
if codex_north_env_is_canonical "$scratch/codex-extra-env.toml" >/dev/null 2>&1; then
  printf 'extra Codex North MCP env key was accepted\n' >&2
  exit 1
fi
cp "$REPO/dotfiles/codex/config.toml" "$scratch/codex-wrong-env.toml"
sed -i 's#^BEAGLE_STORE_LOG = "/home/tom/.local/state/north/coordination.log"$#BEAGLE_STORE_LOG = "/tmp/wrong.log"#' \
  "$scratch/codex-wrong-env.toml"
if codex_north_env_is_canonical "$scratch/codex-wrong-env.toml" >/dev/null 2>&1; then
  printf 'wrong Codex North MCP coordination log was accepted\n' >&2
  exit 1
fi

# Shared fake Nix store hash for the package fixtures below.
nix_hash='0123456789abcdfghijklmnpqrsvwxyz'

# Local attestation follows the canonical live configuration root, not the
# clean worktree whose source is being tested. Worktree location is never
# runtime authority for the user's managed symlinks.
live_root="$scratch/live-nixos-config"
mkdir -p "$live_root/dotfiles/codex"
printf 'live\n' >"$live_root/dotfiles/codex/config.toml"
ln -s "$live_root/dotfiles/codex/config.toml" "$scratch/live-config-link"
fail=0
details=()
ok_detail() { details+=("ok: $*"); }
bad() { fail=$((fail + 1)); }
canonical_link \
  "$scratch/live-config-link" \
  "$live_root/dotfiles/codex/config.toml" \
  'worktree-independent live config'
[ "$fail" -eq 0 ]

store_target="$scratch/nix/store/${nix_hash}-coreutils/bin/true"
mkdir -p "${store_target%/*}"
cp "$(type -P true)" "$store_target"
cp "$store_target" "$scratch/store-copy-expected"
chmod u+w "$scratch/store-copy-expected"
ln -s "$store_target" "$scratch/store-copy-link"
NIX_STORE_PREFIX="$scratch/nix/store" immutable_store_link_matches \
  "$scratch/store-copy-link" "$scratch/store-copy-expected" \
  'generation-owned fixture'
[ "$fail" -eq 0 ]
printf 'drift\n' >>"$scratch/store-copy-expected"
if NIX_STORE_PREFIX="$scratch/nix/store" immutable_store_link_matches \
   "$scratch/store-copy-link" "$scratch/store-copy-expected" \
   'generation-owned drift fixture' 2>/dev/null; then
  printf 'store-backed copy drift was accepted\n' >&2
  exit 1
fi
[ "$fail" -eq 1 ]
fail=0
details=()

# Nix makeWrapper keeps the locked North body in a hidden sibling, patches
# only its shebang, and exposes a generated public launcher. Attest both exact
# body bytes and same-package dispatch provenance.
fixture_store="$scratch/nix/store"
fixture_bash_pkg="$fixture_store/${nix_hash}-bash-5.3p9"
fixture_bash="$fixture_bash_pkg/bin/bash"
fixture_north_repo="$scratch/locked-north"
fixture_north_pkg="$fixture_store/${nix_hash}-north-0.1.0"
fixture_public="$fixture_north_pkg/bin/north-on-spawn"
fixture_wrapped="$fixture_north_pkg/bin/.north-on-spawn-wrapped"
mkdir -p "$fixture_bash_pkg/bin" "$fixture_north_repo/bin" "$fixture_north_pkg/bin"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$fixture_bash"
chmod +x "$fixture_bash"
printf '%s\n' '#!/usr/bin/env bash' 'printf locked-body\\n' \
  >"$fixture_north_repo/bin/north-on-spawn"
git -C "$fixture_north_repo" init -q
git -C "$fixture_north_repo" config user.email test@example.invalid
git -C "$fixture_north_repo" config user.name wrapper-test
git -C "$fixture_north_repo" add bin/north-on-spawn
git -C "$fixture_north_repo" commit -qm locked
fixture_north_revision="$(git -C "$fixture_north_repo" rev-parse HEAD)"
{
  printf '#!%s\n' "$fixture_bash"
  git -C "$fixture_north_repo" show \
    "$fixture_north_revision:bin/north-on-spawn" | tail -n +2
} >"$fixture_wrapped"
printf '%s\n' \
  "#! $fixture_bash -e" \
  "PATH=\${PATH:+':'\$PATH':'}" \
  "PATH=\${PATH/':''${fixture_bash_pkg}/bin'':'/':'}" \
  "PATH='${fixture_bash_pkg}/bin'\$PATH" \
  "PATH=\${PATH#':'}" \
  "PATH=\${PATH%':'}" \
  'export PATH' \
  "export NORTH_HOME='$fixture_north_pkg'" \
  'exec -a "$0" "'"$fixture_wrapped"'"  "$@" ' \
  >"$fixture_public"
chmod +x "$fixture_public" "$fixture_wrapped"
north_wrapped_runtime_matches_locked_source \
  "$fixture_public" "$fixture_north_repo" "$fixture_north_revision" \
  bin/north-on-spawn "$fixture_store"

# A locked body larger than one pipe buffer: any shebang read that pipes
# `git show` into a truncating reader dies of SIGPIPE under pipefail and
# reports a byte-perfect wrapper as provenance drift.
{
  printf '%s\n' '#!/usr/bin/env bash'
  seq 1 4000 | sed 's/^/# padding line /'
} >"$fixture_north_repo/bin/north-on-spawn"
[ "$(wc -c <"$fixture_north_repo/bin/north-on-spawn")" -gt 65536 ]
git -C "$fixture_north_repo" add bin/north-on-spawn
git -C "$fixture_north_repo" commit -qm 'locked body wider than a pipe buffer'
fixture_wide_revision="$(git -C "$fixture_north_repo" rev-parse HEAD)"
{
  printf '#!%s\n' "$fixture_bash"
  git -C "$fixture_north_repo" show \
    "$fixture_wide_revision:bin/north-on-spawn" | tail -n +2
} >"$fixture_wrapped"
chmod +x "$fixture_wrapped"
north_wrapped_runtime_matches_locked_source \
  "$fixture_public" "$fixture_north_repo" "$fixture_wide_revision" \
  bin/north-on-spawn "$fixture_store"
{
  printf '#!%s\n' "$fixture_bash"
  git -C "$fixture_north_repo" show \
    "$fixture_north_revision:bin/north-on-spawn" | tail -n +2
} >"$fixture_wrapped"
chmod +x "$fixture_wrapped"

grep -Fq 'managed_source_root_matches "$HOME/code/north/main" "$resolved"' \
  "$REPO/scripts/agent-config-check.sh"
if grep -Fq '"$HOME/code/north" \' \
   "$REPO/scripts/agent-config-check.sh"; then
  printf 'managed North wrapper provenance still uses the non-repository container path\n' >&2
  exit 1
fi
printf 'drift\n' >>"$fixture_wrapped"
if north_wrapped_runtime_matches_locked_source \
   "$fixture_public" "$fixture_north_repo" "$fixture_north_revision" \
   bin/north-on-spawn "$fixture_store"; then
  printf 'tampered hidden North wrapper body was accepted\n' >&2
  exit 1
fi
{
  printf '#!%s\n' "$fixture_bash"
  git -C "$fixture_north_repo" show \
    "$fixture_north_revision:bin/north-on-spawn" | tail -n +2
} >"$fixture_wrapped"
cp "$fixture_public" "$scratch/good-public-wrapper"
sed -i 's#/.north-on-spawn-wrapped#/.wrong-wrapped#' "$fixture_public"
if north_wrapped_runtime_matches_locked_source \
   "$fixture_public" "$fixture_north_repo" "$fixture_north_revision" \
   bin/north-on-spawn "$fixture_store"; then
  printf 'North public wrapper with wrong hidden-body dispatch was accepted\n' >&2
  exit 1
fi
mv "$scratch/good-public-wrapper" "$fixture_public"
chmod +x "$fixture_public"
cp "$fixture_public" "$scratch/good-public-wrapper"
sed -i "/^export NORTH_HOME=/i printf 'injected-before-exec\\n'" \
  "$fixture_public"
if north_wrapped_runtime_matches_locked_source \
   "$fixture_public" "$fixture_north_repo" "$fixture_north_revision" \
   bin/north-on-spawn "$fixture_store"; then
  printf 'North public wrapper with injected pre-exec command was accepted\n' >&2
  exit 1
fi
mv "$scratch/good-public-wrapper" "$fixture_public"
chmod +x "$fixture_public"
cp "$fixture_public" "$scratch/good-public-wrapper"
grep -v '^export NORTH_HOME=' "$scratch/good-public-wrapper" \
  >"$fixture_public"
printf '%s\n' "export NORTH_HOME='$fixture_north_pkg'" >>"$fixture_public"
chmod +x "$fixture_public"
if north_wrapped_runtime_matches_locked_source \
   "$fixture_public" "$fixture_north_repo" "$fixture_north_revision" \
   bin/north-on-spawn "$fixture_store"; then
  printf 'North public wrapper with NORTH_HOME reordered after exec was accepted\n' >&2
  exit 1
fi
mv "$scratch/good-public-wrapper" "$fixture_public"
chmod +x "$fixture_public"

grep -Fq 'CODEX_HOME="$HOME/.codex"' "$REPO/scripts/agent-config-check.sh"
grep -Fq 'CODEX_SQLITE_HOME="$HOME/.codex/sqlite"' \
  "$REPO/scripts/agent-config-check.sh"

# The Codex MCP declaration remains required.
grep -Fq 'command = "/run/current-system/sw/bin/north-mcp"' \
  "$REPO/dotfiles/codex/config.toml"

# North has no web package or service; keep the config check CLI/MCP-only.
if rg -n -- 'check-web|NORTH_WEB|north-web' "$REPO/scripts/agent-config-check.sh"; then
  printf 'agent-config-check still carries retired North web health checks\n' >&2
  exit 1
fi

printf 'ok: Codex managed policy and canonical Agent Machinery source identity are exact\n'
