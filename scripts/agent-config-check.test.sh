#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-check.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

assert_native_identity() {
  local manifest="$1" expected_provider="$2" label="$3"
  local expected_spawn="AGENT_PROVIDER=$expected_provider /home/tom/code/north/bin/north-on-spawn"
  local expected_repair="AGENT_PROVIDER=$expected_provider /home/tom/code/north/bin/north-on-tooluse"
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
  done < <(jq -r '.hooks | to_entries[] | .key as $event | .value[] | .hooks[]? | select(.type == "command" and ((.command | contains("/north-on-spawn")) or (.command | contains("/north-on-tooluse")))) | [$event,.command] | @tsv' "$manifest")

  [ "$spawn_count" -eq 2 ] || {
    printf '%s has %s north-on-spawn bindings, expected 2\n' "$label" "$spawn_count" >&2
    exit 1
  }
  [ "$repair_count" -eq 1 ] || {
    printf '%s has %s north-on-tooluse bindings, expected 1\n' "$label" "$repair_count" >&2
    exit 1
  }
  jq -e '[.hooks | to_entries[] | .value[] | .hooks[]? | select(.type == "command" and (.command | startswith("AGENT_PROVIDER=")) and ((.command | test("/north-on-(spawn|tooluse)$")) | not))] | length == 0' "$manifest" >/dev/null
}

assert_native_identity "$REPO/dotfiles/claude/settings.json" anthropic Claude
report="$("$REPO/scripts/agent-config-check.sh")"
grep -Fq '17 managed authoritative bindings' <<<"$report"
# shellcheck disable=SC2088  # report intentionally renders the literal user-facing alias
grep -Fq '~/.codex/hooks.json ignored by managed-only policy (0 active bindings)' <<<"$report"
"$REPO/dotfiles/codex/hooks/codex-lifecycle-wrappers.test.sh" >/dev/null
"$REPO/dotfiles/codex/hooks/north-clock-guard-codex.test.sh" >/dev/null

# A deterministic route probe is diagnostic evidence, not provider preference.
# The compact harness report must summarize the allocation policy itself.
if grep -Fq '.diagnosticRouteProbe' "$REPO/scripts/agent-config-check.sh"; then
  printf 'agent-config-check must not present diagnosticRouteProbe as routing policy\n' >&2
  exit 1
fi
grep -Fq '"Allocation  ' \
  "$REPO/scripts/agent-config-check.sh"

source "$REPO/scripts/agent-config-check.sh"

managed_policy="$REPO/modules/codex/requirements.toml"
[ "$(codex_managed_policy_binding_count "$managed_policy")" = 17 ]
cp "$managed_policy" "$scratch/managed-policy-failure-mode-missing.toml"
sed -i '/^managed_hook_failure_mode = "block"$/d' \
  "$scratch/managed-policy-failure-mode-missing.toml"
if codex_managed_policy_binding_count \
  "$scratch/managed-policy-failure-mode-missing.toml" >/dev/null 2>&1; then
  printf 'Codex managed policy without a hook failure mode was accepted\n' >&2
  exit 1
fi
cp "$managed_policy" "$scratch/managed-policy-failure-mode-continue.toml"
sed -i 's/^managed_hook_failure_mode = "block"$/managed_hook_failure_mode = "continue"/' \
  "$scratch/managed-policy-failure-mode-continue.toml"
if codex_managed_policy_binding_count \
  "$scratch/managed-policy-failure-mode-continue.toml" >/dev/null 2>&1; then
  printf 'Codex managed policy with continuing hook failures was accepted\n' >&2
  exit 1
fi
cp "$managed_policy" "$scratch/managed-policy-failure-mode-boolean.toml"
sed -i 's/^managed_hook_failure_mode = "block"$/managed_hook_failure_mode = true/' \
  "$scratch/managed-policy-failure-mode-boolean.toml"
if codex_managed_policy_binding_count \
  "$scratch/managed-policy-failure-mode-boolean.toml" >/dev/null 2>&1; then
  printf 'Codex managed policy with a boolean hook failure mode was accepted\n' >&2
  exit 1
fi
cp "$managed_policy" "$scratch/managed-policy-failure-mode-invalid.toml"
sed -i 's/^managed_hook_failure_mode = "block"$/managed_hook_failure_mode = "BLOCK"/' \
  "$scratch/managed-policy-failure-mode-invalid.toml"
if codex_managed_policy_binding_count \
  "$scratch/managed-policy-failure-mode-invalid.toml" >/dev/null 2>&1; then
  printf 'Codex managed policy with an invalid hook failure mode was accepted\n' >&2
  exit 1
fi
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
cp "$managed_policy" "$scratch/managed-policy-timeout-drift.toml"
sed -i '0,/^timeout = 10$/s//timeout = 11/' \
  "$scratch/managed-policy-timeout-drift.toml"
if codex_managed_policy_binding_count \
  "$scratch/managed-policy-timeout-drift.toml" >/dev/null 2>&1; then
  printf 'Codex managed hook timeout drift was accepted\n' >&2
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
grep -Fq '17 managed authoritative bindings' <<<"$missing_legacy_report"
grep -Fq 'ignored by managed-only policy (0 active bindings)' \
  <<<"$missing_legacy_report"
printf '%s\n' '{not-json' >"$scratch/invalid-legacy-hooks.json"
invalid_legacy_report="$(
  CODEX_LEGACY_HOOKS="$scratch/invalid-legacy-hooks.json" \
    "$REPO/scripts/agent-config-check.sh"
)"
grep -Fq '17 managed authoritative bindings' <<<"$invalid_legacy_report"
grep -Fq 'ignored by managed-only policy (0 active bindings)' \
  <<<"$invalid_legacy_report"

# A logical state path may traverse symlinks before Git reports its physical
# worktree root. Canonical identity must accept that alias, but never a distinct
# repository merely because its lexical path looks related.
mkdir -p "$scratch/gaffer-real" "$scratch/gaffer-distinct"
git -C "$scratch/gaffer-real" init -q
git -C "$scratch/gaffer-distinct" init -q
ln -s "$scratch/gaffer-real" "$scratch/gaffer-logical"
gaffer_observed="$(
  git -C "$scratch/gaffer-logical" rev-parse --path-format=absolute --show-toplevel
)"
managed_source_root_matches "$scratch/gaffer-logical" "$gaffer_observed"
distinct_observed="$(
  git -C "$scratch/gaffer-distinct" rev-parse --path-format=absolute --show-toplevel
)"
if managed_source_root_matches "$scratch/gaffer-logical" "$distinct_observed"; then
  printf 'distinct managed Gaffer worktree root was accepted through a logical alias\n' >&2
  exit 1
fi

# Checkout-first hooks carry explicit mutable provenance. Canonical targets
# fingerprint cleanly; a split target/hash for one basename+role is rejected.
IFS=$'\t' read -r north_spawn_target north_spawn_sha \
  < <(hook_target_fingerprint \
    /home/tom/code/north/bin/north-on-spawn \
    /home/tom/code/north)
[ "$north_spawn_target" = /home/tom/code/north/bin/north-on-spawn ]
[[ "$north_spawn_sha" =~ ^[0-9a-f]{64}$ ]]
if hook_target_fingerprint \
  /home/tom/code/north/bin/north-on-spawn \
  /home/tom/code/nixos-config >/dev/null; then
  printf 'North checkout hook was accepted under the wrong canonical repo\n' >&2
  exit 1
fi
record_live_hook_binding \
  north-on-spawn:north-lifecycle "$north_spawn_target" "$north_spawn_sha"
if record_live_hook_binding \
  north-on-spawn:north-lifecycle "$north_spawn_target" \
  0000000000000000000000000000000000000000000000000000000000000000; then
  printf 'split bytes for one live hook role were accepted\n' >&2
  exit 1
fi
grep -q 'north-on-spawn:north-lifecycle changed from' <<<"$HOOK_SPLIT_REASON"

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
gaffer_revisions_converged \
  "$verified_revision" "$verified_revision" "$verified_revision"
if gaffer_revisions_converged \
  "$stale_intent_revision" "$verified_revision" "$verified_revision"; then
  printf 'stale but valid Gaffer intent revision was accepted\n' >&2
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

# The live coordinator must positively identify the immutable runtime-selector
# launcher. Direct checkout and direct package execution both bypass atomic
# promotion/rollback and are rejected.
nix_hash='0123456789abcdfghijklmnpqrsvwxyz'
selector_path="/nix/store/${nix_hash}-north-coord-runtime/bin/north-coord-runtime"
selector_exec="{ path=$selector_path ; argv[]=$selector_path start ; ignore_errors=no ; }"
classify_north_coord_exec "$selector_exec"
[ "$NORTH_COORD_EXEC_KIND" = runtime-selector ]
[ "$NORTH_COORD_EXEC_PATH" = "$selector_path" ]

pinned_path="/nix/store/${nix_hash}-fram-0-unstable-2026-06-28/bin/fram-daemon"
pinned_exec="{ path=$pinned_path ; argv[]=$pinned_path 7977 /home/tom/.local/state/north/coordination.log ; ignore_errors=no ; }"
if classify_north_coord_exec "$pinned_exec"; then
  printf 'direct pinned north-coord package was accepted\n' >&2
  exit 1
fi
[ "$NORTH_COORD_EXEC_KIND" = direct-package ]
[ "$NORTH_COORD_EXEC_PATH" = "$pinned_path" ]

checkout_path='/home/tom/code/fram/bin/fram-daemon'
if classify_north_coord_exec "{ path=$checkout_path ; argv[]=$checkout_path 7977 /tmp/facts.log ; }"; then
  printf 'direct checkout north-coord was accepted\n' >&2
  exit 1
fi
[ "$NORTH_COORD_EXEC_KIND" = direct-checkout ]

mapfile -t parsed_coord_pids < <(
  printf '%s\n' \
    'LISTEN 0 50 127.0.0.1:7977 0.0.0.0:* users:(("java",pid=42,fd=16))' \
    'LISTEN 0 50 [::1]:7977 [::]:* users:(("java",pid=42,fd=17))' \
    'LISTEN 0 50 127.0.0.1:7977 0.0.0.0:* users:(("other",pid=99,fd=18))' |
    north_coord_listener_pids_from_ss
)
[ "${parsed_coord_pids[*]}" = '42 99' ]
north_coord_listener_set_matches_mainpid 42 42
if north_coord_listener_set_matches_mainpid 42 99 ||
   north_coord_listener_set_matches_mainpid 42 42 99 ||
   north_coord_listener_set_matches_mainpid 42; then
  printf 'foreign or ambiguous :7977 listener set matched systemd MainPID\n' >&2
  exit 1
fi

# Ordinary North/MCP execute the exact package. Only explicit *-dev wrappers
# delegate checkout execution through the runtime selector.
[ "$(grep -c 'exec /run/current-system/sw/bin/north-coord-runtime exec-checkout' \
  "$REPO/modules/north/default.bnix")" -eq 1 ]
[ "$(grep -c 'NORTH_MANAGED_CODEX_BIN=' \
  "$REPO/modules/north/default.bnix")" -eq 1 ]
grep -Fq '(get (get inputs.north.packages pkgs.stdenv.hostPlatform.system) :codex)' \
  "$REPO/modules/north/default.bnix"
if grep -q 'export FRAM_RUNTIME_SOURCE\|export FRAM_RUNTIME_REV' \
  "$REPO/modules/north/default.bnix"; then
  printf 'North wrapper duplicates selector identity instead of delegating it\n' >&2
  exit 1
fi

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
grep -q ':ExecStartPre \[(s northCoordRuntime "/bin/north-coord-runtime package")' \
  "$REPO/modules/north-coord/default.bnix"
grep -q ':ExecStartPost (s northCoordRuntime "/bin/north-coord-runtime settle")' \
  "$REPO/modules/north-coord/default.bnix"
grep -q ':ExecCondition (s northCoordRuntime "/bin/north-coord-runtime preflight")' \
  "$REPO/modules/north-coord/default.bnix"
grep -q ':startLimitIntervalSec 60' "$REPO/modules/north-coord/default.bnix"
grep -q ':startLimitBurst       3' "$REPO/modules/north-coord/default.bnix"
grep -Fq 'command = "/run/current-system/sw/bin/north-mcp"' \
  "$REPO/dotfiles/codex/config.toml"
grep -Fq 'command = "/run/current-system/sw/bin/fram-mcp"' \
  "$REPO/dotfiles/codex/config.toml"
grep -Fq 'FRAM_MCP_BIN="${FRAM_MCP_BIN:-/run/current-system/sw/bin/fram-mcp}"' \
  "$REPO/scripts/claude-mcp-register.sh"
grep -Fq 'NORTH_MCP_BIN="${NORTH_MCP_BIN:-/run/current-system/sw/bin/north-mcp}"' \
  "$REPO/scripts/claude-mcp-register.sh"

wrapper_path="/nix/store/${nix_hash}-fram-daemon-packaged/bin/fram-daemon-packaged"
if classify_north_coord_exec "{ path=$wrapper_path ; argv[]=$wrapper_path 7977 /tmp/facts.log ; }"; then
  printf 'indirect store wrapper was accepted as the pinned Fram package\\n' >&2
  exit 1
fi
[ "$NORTH_COORD_EXEC_KIND" = unrecognized ]

# Process identity must resolve through the stable selector to an exact, clean,
# revision-owned deployment. SHA equality alone cannot bless a different root.
identity_repo="$scratch/runtime-identity-repo"
identity_state="$scratch/runtime-identity-state"
mkdir -p "$identity_repo/bin" "$identity_state/deployments"
git -C "$identity_repo" init -q
git -C "$identity_repo" config user.email test@example.invalid
git -C "$identity_repo" config user.name runtime-test
printf '%s\n' '#!/bin/sh' 'exit 0' >"$identity_repo/bin/fram-daemon"
chmod +x "$identity_repo/bin/fram-daemon"
git -C "$identity_repo" add bin/fram-daemon
git -C "$identity_repo" commit -qm runtime
identity_revision="$(git -C "$identity_repo" rev-parse HEAD)"
identity_tree="$(git -C "$identity_repo" rev-parse 'HEAD^{tree}')"
identity_deployment="$identity_state/deployments/$identity_revision"
git -C "$identity_repo" worktree add --detach "$identity_deployment" "$identity_revision" >/dev/null
mkdir -p "$identity_state/generations/g1"
ln -s "$identity_deployment" "$identity_state/generations/g1/current"
ln -s "$identity_deployment" "$identity_state/generations/g1/previous"
ln -s generations/g1 "$identity_state/active"
ln -s active/current "$identity_state/current"
north_coord_runtime_identity_is_valid \
  checkout "$identity_deployment" "$identity_revision" "$identity_tree" \
  "$identity_repo" "$identity_deployment/bin/fram-daemon" "$identity_state/current"
if north_coord_runtime_identity_is_valid \
   checkout "$identity_repo" "$identity_revision" "$identity_tree" \
   "$identity_repo" "$identity_deployment/bin/fram-daemon" "$identity_state/current"; then
  printf 'same-revision runtime outside the selected deployment was accepted\n' >&2
  exit 1
fi
if north_coord_runtime_identity_is_valid \
   checkout "$identity_deployment" "$identity_revision" \
   aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
   "$identity_repo" "$identity_deployment/bin/fram-daemon" "$identity_state/current"; then
  printf 'wrong checkout tree identity was accepted\n' >&2
  exit 1
fi
if north_coord_runtime_identity_is_valid \
   checkout "$identity_deployment" "$identity_revision" "$identity_tree" \
   "$identity_repo" /bin/true "$identity_state/current"; then
  printf 'wrong checkout daemon identity was accepted\n' >&2
  exit 1
fi
printf '%s\n' '#!/bin/sh' 'exit 0' >"$identity_deployment/UNTRACKED-EXECUTABLE"
chmod +x "$identity_deployment/UNTRACKED-EXECUTABLE"
if north_coord_runtime_identity_is_valid \
   checkout "$identity_deployment" "$identity_revision" "$identity_tree" \
   "$identity_repo" "$identity_deployment/bin/fram-daemon" "$identity_state/current"; then
  printf 'untracked selected runtime bytes were accepted\n' >&2
  exit 1
fi
unlink "$identity_deployment/UNTRACKED-EXECUTABLE"
printf 'drift\n' >>"$identity_deployment/bin/fram-daemon"
if north_coord_runtime_identity_is_valid \
   checkout "$identity_deployment" "$identity_revision" "$identity_tree" \
   "$identity_repo" "$identity_deployment/bin/fram-daemon" "$identity_state/current"; then
  printf 'dirty selected runtime was accepted\n' >&2
  exit 1
fi

# North has no web package or service; keep the config check CLI/MCP-only.
if rg -n -- 'check-web|NORTH_WEB|north-web' "$REPO/scripts/agent-config-check.sh"; then
  printf 'agent-config-check still carries retired North web health checks\n' >&2
  exit 1
fi

# Repository/CI mode validates canonical declarations against this checkout,
# not whether Tom's absolute live path happens to exist. A failing readlink shim
# simulates a relocated checkout; only --local may require live resolution.
# The legacy user manifest is ignored by managed-only policy, but its state
# coordinate parser remains deterministic for diagnostics and migration.
expected_north_spawn='AGENT_PROVIDER=openai /home/tom/code/north/bin/north-on-spawn'
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

mkdir -p "$scratch/bin"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$scratch/bin/readlink"
chmod +x "$scratch/bin/readlink"
PATH="$scratch/bin:$PATH" "$REPO/scripts/agent-config-check.sh" >/dev/null

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
# The module must pin the exact reviewed hermes-agent commit and drive the
# WRAPPED North package bin, never the raw source checkout.
grep -qF '"github:NousResearch/hermes-agent/244dabbd9c4b542bf5c1ad0159af512c2b5d6e08"' \
  "$REPO/modules/hermes/default.bnix"
grep -qF 'inputs.north.packages' "$REPO/modules/hermes/default.bnix"
if grep -qF '(s inputs.north "/bin")' "$REPO/modules/hermes/default.bnix"; then
  printf 'Hermes lifecycle dir still points at the raw inputs.north source\n' >&2
  exit 1
fi

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

printf 'ok: Claude native identity + authoritative Codex managed policy + canonical Gaffer source identity are exact\n'
printf 'ok: Hermes controller adapter — fail-closed north-bridge, disabled native delegation, packaged North MCP\n'
