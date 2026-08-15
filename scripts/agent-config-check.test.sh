#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_PROFILE="${AGENT_CONFIG_NORTH_PROFILE:-$HOME/code/north/main/profiles/tom}"
BEAGLE_INTEGRATION="${AGENT_CONFIG_BEAGLE_INTEGRATION:-$HOME/code/beagle/main/integrations/north}"
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
  {"name":"fram","enabled":true},
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
  codex_mcp_inventory_server_has_state "$codex_inventory" fram true
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

run_switchboard_activity_fixture() {
  local activity="$scratch/activity.conf"
  local missing="$scratch/missing-activity.conf"

  [ "$(AGENTS_ACTIVITY_FILE="$missing" switchboard_activity_state module coordination)" = unknown ]
  AGENTS_ACTIVITY_FILE="$missing" switchboard_activity_is_active module coordination

  printf '%s\n' \
    'module coordination off' \
    'hook agent-spawn-guard on' >"$activity"
  [ "$(AGENTS_ACTIVITY_FILE="$activity" switchboard_activity_state module coordination)" = off ]
  ! AGENTS_ACTIVITY_FILE="$activity" switchboard_activity_is_active module coordination
  [ "$(AGENTS_ACTIVITY_FILE="$activity" switchboard_activity_state hook agent-spawn-guard)" = on ]
  AGENTS_ACTIVITY_FILE="$activity" switchboard_activity_is_active hook agent-spawn-guard
  [ "$(AGENTS_ACTIVITY_FILE="$activity" switchboard_activity_state hook absent-hook)" = off ]
  ! AGENTS_ACTIVITY_FILE="$activity" switchboard_activity_is_active hook absent-hook
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

if [ "${1:-}" = '--switchboard-activity-only' ]; then
  source "$REPO/scripts/agent-config-check.sh"
  run_switchboard_activity_fixture
  printf 'ok: advisory follows the derived switchboard activity projection\n'
  exit 0
fi

assert_native_identity() {
  local lifecycle_fragment="$1" repair_fragment="$2" expected_provider="$3" label="$4"
  local expected_spawn="AGENT_PROVIDER=$expected_provider /run/current-system/sw/bin/north-on-spawn"
  local expected_repair="AGENT_PROVIDER=$expected_provider /home/tom/.agents/hooks/hook-detach.sh /run/current-system/sw/bin/north-on-tooluse"
  local event command spawn_count=0 repair_count=0

  while IFS=$'\t' read -r event command; do
    [ -n "$command" ] || continue
    case "$command" in
      *'/north-on-spawn')
        spawn_count=$((spawn_count + 1))
        case "$event" in SessionStart|SubagentStart) ;; *)
          printf 'unexpected %s north-on-spawn event: %s\n' "$label" "$event" >&2
          exit 1
        esac
        [ "$command" = "$expected_spawn" ] || {
          printf '%s %s has wrong spawn provider identity: %s\n' "$label" "$event" "$command" >&2
          exit 1
        }
        ;;
      *'/north-on-tooluse')
        repair_count=$((repair_count + 1))
        [ "$event" = PostToolUse ] || {
          printf 'unexpected %s north-on-tooluse event: %s\n' "$label" "$event" >&2
          exit 1
        }
        [ "$command" = "$expected_repair" ] || {
          printf '%s %s has wrong repair provider identity: %s\n' "$label" "$event" "$command" >&2
          exit 1
        }
        ;;
    esac
  done < <(jq -sr '.[] | .entries[] | select(.hook.type == "command" and ((.hook.command | contains("/north-on-spawn")) or (.hook.command | contains("/north-on-tooluse")))) | [.event,.hook.command] | @tsv' "$lifecycle_fragment" "$repair_fragment")

  [ "$spawn_count" -eq 2 ] || {
    printf '%s has %s north-on-spawn bindings, expected 2\n' "$label" "$spawn_count" >&2
    exit 1
  }
  [ "$repair_count" -eq 1 ] || {
    printf '%s has %s north-on-tooluse bindings, expected 1\n' "$label" "$repair_count" >&2
    exit 1
  }
  jq -se '[.[] | .entries[] | .hook | select(.type == "command" and (.command | startswith("AGENT_PROVIDER=")) and ((.command | test("/north-on-(spawn|tooluse)$")) | not))] | length == 0' "$lifecycle_fragment" "$repair_fragment" >/dev/null
}

assert_native_identity \
  "$REPO/dotfiles/agents/hooks.d/north-session-lifecycle.json" \
  "$REPO/dotfiles/agents/hooks.d/hook-detach.json" \
  anthropic "Claude switchboard fragments"
if rg -n '/home/tom/code/(north|fram)/bin/(north-(on-|mark-|stream)|concern|fram-code-status)' \
  "$REPO/dotfiles/claude/settings.json" \
  "$REPO/dotfiles/codex/hooks.json" \
  "$REPO/dotfiles/claude/statusline.sh" \
  "$BEAGLE_INTEGRATION/hooks/beagle-session-start.sh" \
  "$AGENT_PROFILE/hooks/north-session-end.sh"; then
  printf 'authoritative lifecycle configuration still references a mutable checkout command\n' >&2
  exit 1
fi
if rg -n 'dotfiles/claude/hooks' \
  "$REPO/dotfiles/claude/settings.json" \
  "$REPO/dotfiles/codex/hooks.json" \
  "$REPO/modules/north-profile/default.bnix" \
  "$REPO/modules/claude/default.bnix" \
  "$REPO/modules/codex/default.bnix" \
  "$REPO/modules/hermes/default.bnix"; then
  printf 'active provider wiring still references the retired Firn agent tree\n' >&2
  exit 1
fi
grep -Fq '"/.config/agents/AGENTS.md"' \
  "$REPO/modules/north-profile/default.bnix"
grep -Fq '"/.agents/hooks"' "$REPO/modules/claude/default.bnix"
grep -Fq '"/.config/agents/AGENTS.md"' "$REPO/modules/codex/default.bnix"
grep -Fq '"/.config/agents/AGENTS.md"' "$REPO/modules/hermes/default.bnix"
grep -Fq '"/home/tom/.agents/hooks/north-session-end.sh"' \
  "$REPO/dotfiles/agents/hooks.d/north-session-lifecycle.json"
! grep -Fq 'writeShellScriptBin "north-session-end"' \
  "$REPO/modules/claude/default.bnix"
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
grep -Fq "$managed_binding_count managed authoritative bindings" <<<"$report"
# shellcheck disable=SC2088  # report intentionally renders the literal user-facing alias
grep -Fq '~/.codex/hooks.json ignored by managed-only policy (0 active bindings)' <<<"$report"
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

# Sealed promotion replaces store residency as the immutability proof for the
# North/Beagle managed hooks. Only a real promote can produce root-owned 0444
# content, so the accepted shape is the live deployment; each rejection case
# mutates exactly one clause of that shape.
promoted_root="$scratch/enforcement"
promoted_live="$scratch/live-promoted"
promoted_relative='north/profiles/tom/hooks/agent-spawn-guard.sh'
promoted_sibling='north/profiles/tom/hooks/tripwire-guard.sh'
real_enforcement="${NORTH_ENFORCEMENT_STATE_ROOT:-/var/lib/north-enforcement}"
mkdir -p "$promoted_root/active" "$promoted_live"
if [ -d "$real_enforcement/deployments" ] && [ -r "$real_enforcement/active/record" ]; then
  ln -s "$real_enforcement/deployments" "$promoted_root/deployments"
  ln -s "$(readlink -f "$real_enforcement/active/current")" "$promoted_root/active/current"
  cp "$real_enforcement/active/record" "$promoted_root/active/record"
  chmod u+w "$promoted_root/active/record"
  NORTH_ENFORCEMENT_ROOT="$promoted_root"

  [ "$(stat -c '%u:%a:%h' "$promoted_root/active/current/$promoted_relative")" = '0:444:1' ]
  ln -s "$promoted_root/active/current/$promoted_relative" \
    "$promoted_live/agent-spawn-guard.sh"
  sealed_promoted_file "$promoted_live/agent-spawn-guard.sh" "$promoted_relative"
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
grep -Fq '(promoted "agent-spawn-guard.sh" "north/profiles/tom/hooks/agent-spawn-guard.sh")' \
  "$REPO/modules/codex/default.bnix"
grep -Fq '(promoted "beagle-session-start.sh" "beagle/integrations/north/hooks/beagle-session-start.sh")' \
  "$REPO/modules/codex/default.bnix"
grep -Fq 'enforcement "/var/lib/north-enforcement/active/current"' \
  "$REPO/modules/codex/default.bnix"
if grep -Fq '(s inputs.north "/agent-profile/hooks/' "$REPO/modules/codex/default.bnix"; then
  printf 'Codex module still pins a promoted North hook to the flake input\n' >&2
  exit 1
fi
if grep -Fq '(s inputs.beagle "/integrations/north/hooks/' "$REPO/modules/codex/default.bnix"; then
  printf 'Codex module still pins a promoted Beagle hook to the flake input\n' >&2
  exit 1
fi

claude_mcp_server_connected \
  $'north: /run/current-system/sw/bin/north-mcp - ✔ Connected\nfram: ✔ Connected' \
  north
if claude_mcp_server_connected \
   $'north: /run/current-system/sw/bin/north-mcp - ! Connected · failed\nfram: ✔ Connected' \
   north; then
  printf 'Claude MCP failure marker was accepted as connected\n' >&2
  exit 1
fi

mkdir -p "$scratch/bin"
cat >"$scratch/bin/claude-probe" <<'SH'
#!/usr/bin/env bash
printf 'CLAUDE_CONFIG_DIR=%s\n' "${CLAUDE_CONFIG_DIR-unset}" >"$CLAUDE_PROBE_CALLS"
printf 'argv=%s\n' "$*" >>"$CLAUDE_PROBE_CALLS"
SH
chmod +x "$scratch/bin/claude-probe"
(
  export CLAUDE_CONFIG_DIR="$scratch/wrong-claude-state"
  export CLAUDE_BIN="$scratch/bin/claude-probe"
  export CLAUDE_PROBE_CALLS="$scratch/claude-probe-calls"
  claude_probe_binary_is_authoritative
  run_claude_probe 0.2 mcp list >/dev/null
)
diff -u \
  <(printf '%s\n' 'CLAUDE_CONFIG_DIR=unset' 'argv=mcp list') \
  "$scratch/claude-probe-calls"

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
# shellcheck disable=SC2016  # match source text, not this test process environment
if grep -Fq 'validate_hooks "$CODEX/hooks.json"' \
  "$REPO/scripts/agent-config-check.sh"; then
  printf 'ignored Codex user manifest is still counted as active policy\n' >&2
  exit 1
fi

missing_legacy="$scratch/missing-legacy-hooks.json"
missing_legacy_report="$(
  CODEX_LEGACY_HOOKS="$missing_legacy" \
    "$REPO/scripts/agent-config-check.sh"
)"
grep -Fq "$managed_binding_count managed authoritative bindings" <<<"$missing_legacy_report"
grep -Fq 'ignored by managed-only policy (0 active bindings)' \
  <<<"$missing_legacy_report"
printf '%s\n' '{not-json' >"$scratch/invalid-legacy-hooks.json"
invalid_legacy_report="$(
  CODEX_LEGACY_HOOKS="$scratch/invalid-legacy-hooks.json" \
    "$REPO/scripts/agent-config-check.sh"
)"
grep -Fq "$managed_binding_count managed authoritative bindings" <<<"$invalid_legacy_report"
grep -Fq 'ignored by managed-only policy (0 active bindings)' \
  <<<"$invalid_legacy_report"

# A logical state path may traverse symlinks before Git reports its physical
# worktree root. Canonical identity must accept that alias, but never a distinct
# repository merely because its lexical path looks related.
mkdir -p "$scratch/orchestration-real" "$scratch/orchestration-distinct"
git -C "$scratch/orchestration-real" init -q
git -C "$scratch/orchestration-distinct" init -q
ln -s "$scratch/orchestration-real" "$scratch/orchestration-logical"
orchestration_observed="$(
  git -C "$scratch/orchestration-logical" rev-parse --path-format=absolute --show-toplevel
)"
managed_source_root_matches "$scratch/orchestration-logical" "$orchestration_observed"
distinct_observed="$(
  git -C "$scratch/orchestration-distinct" rev-parse --path-format=absolute --show-toplevel
)"
if managed_source_root_matches "$scratch/orchestration-logical" "$distinct_observed"; then
  printf 'distinct managed Orchestration worktree root was accepted through a logical alias\n' >&2
  exit 1
fi

# Mutable checkout lifecycle bindings are rejected even when their provider
# identity is otherwise correct.
mutable_claude="$scratch/claude-mutable"
cp -a "$REPO/dotfiles/claude" "$mutable_claude"
jq '.hooks.SessionStart = [{
      "hooks": [{
        "type": "command",
        "command": "AGENT_PROVIDER=anthropic /home/tom/code/north/main/bin/north-on-spawn",
        "timeout": 15
      }]
    }]' "$mutable_claude/settings.json" >"$scratch/mutable-claude-settings.json"
mv "$scratch/mutable-claude-settings.json" "$mutable_claude/settings.json"
if AGENT_CONFIG_CLAUDE="$mutable_claude" \
  "$REPO/scripts/agent-config-check.sh" >"$scratch/mutable-claude.out" 2>&1; then
  printf 'mutable checkout North lifecycle hook was accepted\n' >&2
  exit 1
fi
grep -Fq 'uses mutable checkout North lifecycle command' \
  "$scratch/mutable-claude.out"

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

CLAUDE_BIN="$scratch/bin/hostile-probe" \
  assert_hung_probe_reaped claude run_claude_probe 0.1 mcp list
CODEX_BIN="$scratch/bin/hostile-probe" \
  assert_hung_probe_reaped codex run_codex_probe 0.1 mcp list
NORTH_PACKAGED_BIN="$scratch/bin/hostile-probe" \
NORTH_PROBE_TIMEOUT_SECONDS=0.1 \
  assert_hung_probe_reaped north run_north_packaged providers --json

# The real Codex inventory consults Secret Service for enabled OAuth servers.
# Model that credential backend as an indefinite wait: the checker must disable
# only Linear while still requiring enabled North and Fram entries.
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
orchestration_revisions_converged \
  "$verified_revision" "$verified_revision" "$verified_revision"
if orchestration_revisions_converged \
  "$stale_intent_revision" "$verified_revision" "$verified_revision"; then
  printf 'stale but valid Orchestration intent revision was accepted\n' >&2
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
sed -i 's#^FRAM_LOG = "/home/tom/.local/state/north/coordination.log"$#FRAM_LOG = "/tmp/wrong.log"#' \
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

store_target="$(readlink -f /run/current-system/sw/bin/true)"
cp "$store_target" "$scratch/store-copy-expected"
chmod u+w "$scratch/store-copy-expected"
ln -s "$store_target" "$scratch/store-copy-link"
immutable_store_link_matches \
  "$scratch/store-copy-link" "$scratch/store-copy-expected" \
  'generation-owned fixture'
[ "$fail" -eq 0 ]
printf 'drift\n' >>"$scratch/store-copy-expected"
if immutable_store_link_matches \
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

# writeShellScriptBin prepends one store Bash shebang to the complete source
# and appends exactly one blank line. No other body normalization is allowed.
session_source="$scratch/north-session-end.sh"
session_pkg="$fixture_store/${nix_hash}-north-session-end"
session_live="$session_pkg/bin/north-session-end"
mkdir -p "$session_pkg/bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf session-end\\n' >"$session_source"
{
  printf '#!%s\n' "$fixture_bash"
  cat "$session_source"
  printf '\n'
} >"$session_live"
chmod +x "$session_live"
write_shell_script_bin_matches_source \
  "$session_live" "$session_source" "$fixture_store"
printf 'drift\n' >>"$session_live"
if write_shell_script_bin_matches_source \
   "$session_live" "$session_source" "$fixture_store"; then
  printf 'north-session-end generated body drift was accepted\n' >&2
  exit 1
fi
{
  printf '#!/bin/bash\n'
  cat "$session_source"
  printf '\n'
} >"$session_live"
chmod +x "$session_live"
if write_shell_script_bin_matches_source \
   "$session_live" "$session_source" "$fixture_store"; then
  printf 'north-session-end non-store shebang was accepted\n' >&2
  exit 1
fi

grep -Fq 'CODEX_HOME="$HOME/.codex"' "$REPO/scripts/agent-config-check.sh"
grep -Fq 'CODEX_SQLITE_HOME="$HOME/.codex/sqlite"' \
  "$REPO/scripts/agent-config-check.sh"

claude_runtime_settings="$scratch/claude-runtime-settings.json"
cp "$REPO/dotfiles/claude/settings.json" "$claude_runtime_settings"
chmod 600 "$claude_runtime_settings"
writable_claude_settings_match_control_plane \
  "$claude_runtime_settings" "$REPO/dotfiles/claude/settings.json" \
  'writable Claude fixture'
[ "$fail" -eq 0 ]
jq '.enabledPlugins += ["runtime-only@test"]' \
  "$claude_runtime_settings" >"$scratch/claude-runtime-settings.next"
mv "$scratch/claude-runtime-settings.next" "$claude_runtime_settings"
writable_claude_settings_match_control_plane \
  "$claude_runtime_settings" "$REPO/dotfiles/claude/settings.json" \
  'mutated writable Claude fixture'
[ "$fail" -eq 0 ]
ln -s "$REPO/dotfiles/claude/settings.json" "$scratch/claude-settings-link"
if writable_claude_settings_match_control_plane \
   "$scratch/claude-settings-link" "$REPO/dotfiles/claude/settings.json" \
   'symlinked Claude fixture' 2>/dev/null; then
  printf 'symlinked writable Claude settings were accepted\n' >&2
  exit 1
fi
[ "$fail" -eq 1 ]
fail=0
details=()
jq '(.hooks.SessionEnd[0].hooks[0].command) = "/home/tom/code/north/bin/north-on-stop"' \
  "$claude_runtime_settings" >"$scratch/claude-runtime-settings.next"
mv "$scratch/claude-runtime-settings.next" "$claude_runtime_settings"
if writable_claude_settings_match_control_plane \
   "$claude_runtime_settings" "$REPO/dotfiles/claude/settings.json" \
   'checkout-backed Claude fixture' 2>/dev/null; then
  printf 'checkout-backed Claude hook control plane was accepted\n' >&2
  exit 1
fi
[ "$fail" -eq 1 ]
fail=0
details=()
if grep -Fq 'CLAUDE_CONFIG_DIR="$HOME/.claude"' \
   "$REPO/scripts/agent-config-check.sh"; then
  printf 'Claude health still forces the wrong config directory\n' >&2
  exit 1
fi
grep -Fq '/run/current-system/sw/bin/env -u CLAUDE_CONFIG_DIR' \
  "$REPO/scripts/agent-config-check.sh"
grep -Fq '${CLAUDE_BIN:-/run/current-system/sw/bin/claude}' \
  "$REPO/scripts/agent-config-check.sh"

# The client-scoped Linear MCP's live connection health must be advisory
# (soft warn), never a FAIL, while North and Fram stay required. Its config
# declaration still stays required, so the entry keeps working on clock-in.
if grep -Fq 'for server in north fram linear-mcp-msa-new; do' \
   "$REPO/scripts/agent-config-check.sh"; then
  printf 'Linear MCP is still enforced through the required-connection loop\n' >&2
  exit 1
fi
grep -Fq 'CLIENT_SCOPED_MCP_SERVERS=(linear-mcp-msa-new)' \
  "$REPO/scripts/agent-config-check.sh"
grep -Fq 'client MCP '"'"'$server'"'"': unauthenticated (advisory — client-scoped)' \
  "$REPO/scripts/agent-config-check.sh"
grep -Fq 'command = "/run/current-system/sw/bin/north-mcp"' \
  "$REPO/dotfiles/codex/config.toml"
grep -Fq 'command = "/run/current-system/sw/bin/fram-mcp"' \
  "$REPO/dotfiles/codex/config.toml"
grep -Fq 'FRAM_MCP_BIN="${FRAM_MCP_BIN:-/run/current-system/sw/bin/fram-mcp}"' \
  "$REPO/scripts/claude-mcp-register.sh"
grep -Fq 'NORTH_MCP_BIN="${NORTH_MCP_BIN:-/run/current-system/sw/bin/north-mcp}"' \
  "$REPO/scripts/claude-mcp-register.sh"

# North has no web package or service; keep the config check CLI/MCP-only.
if rg -n -- 'check-web|NORTH_WEB|north-web' "$REPO/scripts/agent-config-check.sh"; then
  printf 'agent-config-check still carries retired North web health checks\n' >&2
  exit 1
fi

# The legacy user manifest is ignored by managed-only policy, but its state
# coordinate parser remains deterministic for diagnostics and migration.
expected_north_spawn='/etc/codex/hooks/runtime/env -u BASH_ENV -u ENV /etc/codex/hooks/runtime/bash /etc/codex/hooks/north-on-spawn-codex'
[ "$(jq -r '.hooks.SessionStart[0].hooks[1].command' "$REPO/dotfiles/codex/hooks.json")" = "$expected_north_spawn" ]
disabled_fixture="$scratch/disabled-hook.toml"
printf '%s\n' \
  '[hooks.state]' \
  '[hooks.state."/home/tom/.codex/hooks.json:session_start:0:1"]' \
  'enabled = false' \
  '[hooks.state."/tmp/plugin/hooks.json:session_start:0:0"]' \
  'enabled = false' \
  >"$disabled_fixture"
[ "$(list_disabled_codex_hooks "$REPO/dotfiles/codex/hooks.json" "$disabled_fixture")" = \
  $'SessionStart\t0:1\t'"$expected_north_spawn" ]

# --- Hermes controller adapter coverage ------------------------------------
# The compact report must surface the Hermes group and its fail-closed adapter.
hermes_report="$("$REPO/scripts/agent-config-check.sh")"
grep -Fq 'native delegate_task disabled' <<<"$hermes_report"
grep -Fq 'fail-closed deny + unavailable + lifecycle proven' <<<"$hermes_report"

# The canonical config uses the absolute packaged command + Hermes' connect_timeout
# key, and must NOT carry the Codex-ism startup_timeout_sec.
grep -qE '^\s*command:\s*/run/current-system/sw/bin/north-mcp-packaged\s*$' \
  "$REPO/dotfiles/hermes/config.yaml"
grep -qE '^\s*connect_timeout:\s*[0-9]+\s*$' "$REPO/dotfiles/hermes/config.yaml"
! grep -qE '^\s*startup_timeout_sec:' "$REPO/dotfiles/hermes/config.yaml"

# The standalone north-bridge adapter tests are the fail-closed proof.
python3 "$REPO/dotfiles/hermes/plugins/north-bridge/north-bridge.test.py" >/dev/null 2>&1

# The adapter maps every North lifecycle seam Hermes exposes: it must declare
# the guard hook, the mail-context capture, the additionalContext injection
# points, and the north-on-stop keep-going decision gate.
for hook in pre_tool_call post_tool_call transform_tool_result \
            pre_llm_call pre_verify on_session_start on_session_end; do
  grep -qE "^\s*-\s*$hook\s*$" \
    "$REPO/dotfiles/hermes/plugins/north-bridge/plugin.yaml" || {
    printf 'north-bridge manifest is missing the %s hook\n' "$hook" >&2
    exit 1
  }
done
# Hermes is a controller host, not a North provider — the adapter must never
# stamp AGENT_PROVIDER=hermes so North records the provider unobserved.
if grep -qE '"AGENT_PROVIDER"[^#]*"hermes"' \
   "$REPO/dotfiles/hermes/plugins/north-bridge/__init__.py"; then
  printf 'north-bridge sets AGENT_PROVIDER=hermes (provider must stay unobserved)\n' >&2
  exit 1
fi
# The module must pin the exact reviewed hermes-agent commit and drive North's
# lifecycle scripts from its live launch-critical checkout.
grep -qF '"github:NousResearch/hermes-agent/244dabbd9c4b542bf5c1ad0159af512c2b5d6e08"' \
  "$REPO/modules/hermes/default.bnix"
grep -qF 'northPkg (s homeDir "/code/north/main")' \
  "$REPO/modules/hermes/default.bnix"
grep -qF 'northBin (s northPkg "/bin")' \
  "$REPO/modules/hermes/default.bnix"

# Regression: a Hermes module whose hermes-agent URL floats (no pinned rev) must
# be REJECTED — the reviewed commit is load-bearing.
hermes_module_unpinned="$scratch/hermes-module-unpinned.bnix"
sed 's#github:NousResearch/hermes-agent/244dabbd9c4b542bf5c1ad0159af512c2b5d6e08#github:NousResearch/hermes-agent#' \
  "$REPO/modules/hermes/default.bnix" >"$hermes_module_unpinned"
if AGENT_CONFIG_HERMES_MODULE="$hermes_module_unpinned" \
   "$REPO/scripts/agent-config-check.sh" >/dev/null 2>&1; then
  printf 'agent-config-check accepted an unpinned hermes-agent module URL\n' >&2
  exit 1
fi

# Regression: a Hermes config that re-enables native delegation AND drops the
# north-bridge plugin AND points the North MCP at a checkout must be REJECTED.
hermes_fixture="$scratch/hermes-broken"
mkdir -p "$hermes_fixture/plugins/north-bridge"
cp "$REPO/dotfiles/hermes/plugins/north-bridge/plugin.yaml" \
   "$REPO/dotfiles/hermes/plugins/north-bridge/__init__.py" \
   "$REPO/dotfiles/hermes/plugins/north-bridge/north-bridge.test.py" \
   "$hermes_fixture/plugins/north-bridge/"
printf '%s\n' \
  'plugins:' \
  '  enabled: []' \
  'agent:' \
  '  disabled_toolsets: []' \
  'skills:' \
  '  external_dirs: []' \
  'mcp_servers:' \
  '  north:' \
  '    command: north-mcp' \
  >"$hermes_fixture/config.yaml"
if AGENT_CONFIG_HERMES="$hermes_fixture" \
   "$REPO/scripts/agent-config-check.sh" >/dev/null 2>&1; then
  printf 'agent-config-check accepted a Hermes config with native delegation re-enabled\n' >&2
  exit 1
fi

# Regression: a config that keeps the plugin/delegation/skills correct but uses
# the Codex-ism startup_timeout_sec + a bare (non-absolute) command must be
# REJECTED — the schema key and the absolute path are load-bearing.
hermes_fixture2="$scratch/hermes-timeout"
mkdir -p "$hermes_fixture2/plugins/north-bridge"
cp "$REPO/dotfiles/hermes/plugins/north-bridge/plugin.yaml" \
   "$REPO/dotfiles/hermes/plugins/north-bridge/__init__.py" \
   "$REPO/dotfiles/hermes/plugins/north-bridge/north-bridge.test.py" \
   "$hermes_fixture2/plugins/north-bridge/"
printf '%s\n' \
  'plugins:' \
  '  enabled:' \
  '    - north-bridge' \
  'agent:' \
  '  disabled_toolsets:' \
  '    - delegation' \
  'skills:' \
  '  external_dirs:' \
  '    - ~/.agents/skills' \
  'mcp_servers:' \
  '  north:' \
  '    command: north-mcp-packaged' \
  '    startup_timeout_sec: 15' \
  '    env:' \
  '      NORTH_PORT: "7977"' \
  '      FRAM_LOG: /home/tom/.local/state/north/coordination.log' \
  '      FRAM_TELEMETRY_LOG: /home/tom/.local/state/north/telemetry.log' \
  '      FRAM_THREADS: /home/tom/.local/state/north/threads' \
  >"$hermes_fixture2/config.yaml"
if AGENT_CONFIG_HERMES="$hermes_fixture2" \
   "$REPO/scripts/agent-config-check.sh" >/dev/null 2>&1; then
  printf 'agent-config-check accepted a Hermes config with startup_timeout_sec + bare command\n' >&2
  exit 1
fi

printf 'ok: Claude native identity + authoritative Codex managed policy + canonical Orchestration source identity are exact\n'
printf 'ok: Hermes controller adapter — fail-closed north-bridge, disabled native delegation, packaged North MCP\n'
