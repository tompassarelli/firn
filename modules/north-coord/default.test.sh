#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
runtime=$here/north-coord-runtime
scratch=$(mktemp -d)
trap 'rm -rf "${scratch:?}"' EXIT

state=$scratch/state
repo=$scratch/fram
package=$scratch/package
north_package=$scratch/north-package
log=$scratch/coordination.log
telemetry_log=$scratch/telemetry.log
north_calls=$scratch/north-calls
north_fail=$scratch/north-fail
test_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
mkdir -p "$repo/bin" "$package/bin" "$north_package/bin"
export NORTH_COORD_TEST_CALLS=$north_calls
export NORTH_COORD_TEST_FAIL=$north_fail

cat >"$north_package/bin/north" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'args=%s\n' "$*"
  printf 'coordination=%s\n' "$FRAM_LOG"
  printf 'telemetry=%s\n' "$FRAM_TELEMETRY_LOG"
  printf 'fram-port=%s\n' "$FRAM_PORT"
  printf 'north-port=%s\n' "$NORTH_PORT"
  printf 'controller=%s\n' "$NORTH_CORPUS_CONTROLLER"
  printf 'unit=%s\n' "$NORTH_COORD_SYSTEMD_UNIT"
  printf 'transaction-state=%s\n' "$NORTH_CORPUS_TRANSACTION_DIR"
} >>"$NORTH_COORD_TEST_CALLS"
[[ ! -e "$NORTH_COORD_TEST_FAIL" ]] || exit 17
printf '{:result "clean"}\n'
EOF
chmod +x "$north_package/bin/north"

git -C "$repo" init -q
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name runtime-test

write_daemon() {
  local path=$1 label=$2
  # The single-quoted bodies are the generated daemon's process probes.
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "printf 'label=$label\\n'" \
    "printf 'mode=%s\\n' \"\$NORTH_FRAM_RUNTIME\"" \
    "printf 'source=%s\\n' \"\$FRAM_RUNTIME_SOURCE\"" \
    "printf 'revision=%s\\n' \"\$FRAM_RUNTIME_REV\"" \
    "printf 'tree=%s\\n' \"\$FRAM_RUNTIME_TREE\"" \
    "printf 'origin=%s\\n' \"\$FRAM_RUNTIME_ORIGIN\"" \
    "printf 'daemon=%s\\n' \"\$FRAM_RUNTIME_DAEMON\"" \
    "printf 'owner=%s\\n' \"\${FRAM_RUNTIME_OWNER_TOKEN-unset}\"" \
    "printf 'generation=%s\\n' \"\$NORTH_COORD_RUNTIME_GENERATION\"" \
    "printf 'generation-identity=%s\\n' \"\$NORTH_COORD_RUNTIME_IDENTITY\"" \
    "printf 'runtime-file=%s\\n' \"\$NORTH_COORD_RUNTIME_FILE\"" \
    "printf 'coordination=%s\\n' \"\$FRAM_LOG\"" \
    "printf 'telemetry=%s\\n' \"\$FRAM_TELEMETRY_LOG\"" \
    "printf 'fence=%s\\n' \"\$FRAM_REQUIRE_LOG_FENCE\"" \
    "printf 'unit=%s\\n' \"\$NORTH_COORD_SYSTEMD_UNIT\"" \
    'printf '\''pid=%s\n'\'' "$$"' \
    'stat_line=$(</proc/$$/stat); remainder=${stat_line##*) }; read -r -a stat_fields <<<"$remainder"; printf '\''birth=proc:%s\n'\'' "${stat_fields[19]}"' \
    "printf 'home=%s\\n' \"\$FRAM_HOME\"" \
    "printf 'bin=%s\\n' \"\$FRAM_BIN\"" \
    "printf 'args=%s|%s\\n' \"\$1\" \"\$2\"" \
    'if [[ -n "${NORTH_COORD_TEST_READY:-}" ]]; then : >"$NORTH_COORD_TEST_READY"; fi' \
    'if [[ -n "${NORTH_COORD_TEST_RELEASE:-}" ]]; then IFS= read -r _ <"$NORTH_COORD_TEST_RELEASE"; fi' \
    >"$path"
  chmod +x "$path"
}

write_daemon "$repo/bin/fram-daemon" checkout
printf 'one\n' >"$repo/revision.txt"
git -C "$repo" add bin/fram-daemon revision.txt
git -C "$repo" commit -qm one
revision_one=$(git -C "$repo" rev-parse HEAD)
tree_one=$(git -C "$repo" rev-parse 'HEAD^{tree}')

printf 'two\n' >"$repo/revision.txt"
git -C "$repo" commit -qam two
revision_two=$(git -C "$repo" rev-parse HEAD)

printf 'three\n' >"$repo/revision.txt"
git -C "$repo" commit -qam three
revision_three=$(git -C "$repo" rev-parse HEAD)

write_daemon "$package/bin/fram-daemon" package
package_revision=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

run_runtime_in_state() {
  local selected_state=$1
  shift
  NORTH_COORD_RUNTIME_STATE=$selected_state \
  NORTH_COORD_FRAM_PACKAGE=$package \
  NORTH_COORD_FRAM_PACKAGE_REV=$package_revision \
  NORTH_COORD_FRAM_CHECKOUT=$repo \
  NORTH_COORD_NORTH_PACKAGE=$north_package \
  NORTH_COORD_FRAM_LOG=$log \
  NORTH_COORD_TELEMETRY_LOG=$telemetry_log \
  NORTH_COORD_FRAM_PORT=$test_port \
  NORTH_COORD_SYSTEMD_UNIT=north-coord.service \
    "$runtime" "$@"
}

run_runtime() {
  run_runtime_in_state "$state" "$@"
}

read_pair() {
  printf '%s|%s\n' "$(readlink -f "$state/current")" "$(readlink -f "$state/previous")"
}

record_value() {
  local record=$1 key=$2
  sed -n "s/^${key}=//p" "$record"
}

assert_active_record() {
  local generation=$1 expected_source=$2 expected_revision=$3 expected_tree=$4
  local expected_origin=$5 expected_daemon=$6 record identity pid birth

  record=$generation/active.runtime
  identity=$generation/current.identity
  [[ -f "$record" && ! -L "$record" ]]
  [[ $(stat -c '%a' "$record") == 600 ]]
  [[ $(stat -c '%h' "$record") == 1 ]]
  [[ $(wc -l <"$record") == 18 ]]
  [[ $(record_value "$record" FORMAT) == north-fram-active-runtime/v1 ]]
  [[ $(record_value "$record" GENERATION) == "$generation" ]]
  [[ $(record_value "$record" GENERATION_IDENTITY) == "$identity" ]]
  [[ $(record_value "$record" GENERATION_IDENTITY_SHA256) == "$(sha256sum "$identity" | cut -d' ' -f1)" ]]
  [[ $(record_value "$record" NORTH_FRAM_RUNTIME) == "$(sed -n '2p' "$identity")" ]]
  [[ $(record_value "$record" FRAM_RUNTIME_SOURCE) == "$expected_source" ]]
  [[ $(record_value "$record" FRAM_RUNTIME_REV) == "$expected_revision" ]]
  [[ $(record_value "$record" FRAM_RUNTIME_TREE) == "$expected_tree" ]]
  [[ $(record_value "$record" FRAM_RUNTIME_ORIGIN) == "$expected_origin" ]]
  [[ $(record_value "$record" FRAM_RUNTIME_DAEMON) == "$expected_daemon" ]]
  [[ $(record_value "$record" FRAM_PORT) == "$test_port" ]]
  [[ $(record_value "$record" FRAM_LOG) == "$log" ]]
  [[ $(record_value "$record" FRAM_TELEMETRY_LOG) == "$telemetry_log" ]]
  pid=$(record_value "$record" PID)
  birth=$(record_value "$record" PID_BIRTH)
  [[ "$pid" =~ ^[0-9]+$ ]]
  [[ "$birth" =~ ^proc:[0-9]+$ ]]
  [[ $(record_value "$record" OWNER_TOKEN) =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
  [[ $(record_value "$record" CONTROLLER_UNIT) == north-coord.service ]]
  [[ $(record_value "$record" CONTROLLER_MAIN_PID) == "$pid" ]]
}

assert_pair_is() {
  local actual allowed
  actual=$(read_pair)
  for allowed in "$@"; do
    [[ "$actual" != "$allowed" ]] || return 0
  done
  printf 'unexpected selector pair: %s (allowed: %s)\n' "$actual" "$*" >&2
  exit 1
}

# Read-only operations never infer package mode from missing state. First
# installation is an explicit, persistent transaction.
if run_runtime status >/dev/null 2>&1; then
  printf 'missing selector silently initialized package mode\n' >&2
  exit 1
fi
run_runtime initialize
fresh_status=$(run_runtime status)
grep -Fxq 'mode=package' <<<"$fresh_status"
grep -Fxq "source=$package" <<<"$fresh_status"
grep -Fxq "revision=$package_revision" <<<"$fresh_status"
grep -Fxq "tree=immutable:$package_revision" <<<"$fresh_status"
[[ $(readlink "$state/current") == active/current ]]
[[ $(readlink "$state/previous") == active/previous ]]
[[ $(readlink -f "$state/current") == "$package" ]]
[[ $(readlink -f "$state/previous") == "$package" ]]

# A symlinked state ancestor never leaks a lexical alias into generation-scoped
# process authority. The record and exported discovery paths are canonical.
canonical_state_parent=$scratch/canonical-state-parent
state_parent_alias=$scratch/state-parent-alias
mkdir "$canonical_state_parent"
ln -s "$canonical_state_parent" "$state_parent_alias"
aliased_state=$state_parent_alias/state
run_runtime_in_state "$aliased_state" initialize
aliased_start=$(run_runtime_in_state "$aliased_state" start)
aliased_generation=$(readlink -f "$aliased_state/active")
grep -Fxq "generation=$aliased_generation" <<<"$aliased_start"
grep -Fxq "generation-identity=$aliased_generation/current.identity" <<<"$aliased_start"
grep -Fxq "runtime-file=$aliased_generation/active.runtime" <<<"$aliased_start"
assert_active_record "$aliased_generation" "$package" "$package_revision" "immutable:$package_revision" "$package" "$package/bin/fram-daemon"

# The systemd preparation seam resolves any active corpus journal while the
# coordinator is still offline; the post-start seam waits for the initiating
# transaction and settles only after the real daemon is queryable.
: >"$north_calls"
run_runtime prepare >/dev/null
grep -Fxq 'args=corpus-transaction recover --launcher' "$north_calls"
grep -Fxq "coordination=$log" "$north_calls"
grep -Fxq "telemetry=$telemetry_log" "$north_calls"
grep -Fxq "fram-port=$test_port" "$north_calls"
grep -Fxq "north-port=$test_port" "$north_calls"
grep -Fxq 'controller=systemd' "$north_calls"
grep -Fxq 'unit=north-coord.service' "$north_calls"
grep -Fxq "transaction-state=$scratch/corpus-transactions" "$north_calls"

: >"$north_calls"
run_runtime settle >/dev/null
grep -Fxq 'args=corpus-transaction settle --wait --launcher' "$north_calls"

touch "$north_fail"
if run_runtime prepare >/dev/null 2>&1; then
  printf 'failed recovery was allowed to reach coordinator start\n' >&2
  exit 1
fi
unlink "$north_fail"

# A killed first-install transaction is distinguishable from lost initialized
# state and can be safely retried; its partial tree is quarantined, not trusted.
crash_init_state=$scratch/crash-init-state
if NORTH_COORD_SELECTOR_CRASH_AT=previous-written \
   run_runtime_in_state "$crash_init_state" initialize >/dev/null 2>&1; then
  printf 'first-install crash injection reported success\n' >&2
  exit 1
fi
run_runtime_in_state "$crash_init_state" initialize
grep -Fxq mode=package < <(run_runtime_in_state "$crash_init_state" status)
[[ -n $(find "$scratch" -maxdepth 1 -name '.crash-init-state.incomplete.*' -print -quit) ]]

# Losing an initialized active selection is corruption, not a package fallback.
missing_state=$scratch/missing-state
run_runtime_in_state "$missing_state" initialize
unlink "$missing_state/active"
if run_runtime_in_state "$missing_state" status >/dev/null 2>&1; then
  printf 'missing initialized selection silently fell back to package mode\n' >&2
  exit 1
fi
if run_runtime_in_state "$missing_state" initialize >/dev/null 2>&1; then
  printf 'initialization repaired a lost active selection without evidence\n' >&2
  exit 1
fi

# Promotion materializes and selects the exact detached requested revision.
run_runtime promote "$repo" "$revision_one" >/dev/null
deployment_one=$state/deployments/$revision_one
[[ -d "$deployment_one" && ! -L "$deployment_one" ]]
[[ $(readlink -f "$state/current") == "$deployment_one" ]]
[[ $(git -C "$deployment_one" rev-parse HEAD) == "$revision_one" ]]
if git -C "$deployment_one" symbolic-ref -q HEAD >/dev/null 2>&1; then
  printf 'promoted deployment is attached to a branch\n' >&2
  exit 1
fi

checkout_start=$(run_runtime start)
generation_one=$(readlink -f "$state/active")
runtime_record_one=$generation_one/active.runtime
grep -Fxq 'label=checkout' <<<"$checkout_start"
grep -Fxq 'mode=checkout' <<<"$checkout_start"
grep -Fxq "source=$deployment_one" <<<"$checkout_start"
grep -Fxq "revision=$revision_one" <<<"$checkout_start"
grep -Fxq "tree=$tree_one" <<<"$checkout_start"
grep -Fxq "origin=$repo" <<<"$checkout_start"
grep -Fxq "daemon=$deployment_one/bin/fram-daemon" <<<"$checkout_start"
grep -Eq '^owner=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' <<<"$checkout_start"
grep -Fxq "generation=$generation_one" <<<"$checkout_start"
grep -Fxq "generation-identity=$generation_one/current.identity" <<<"$checkout_start"
grep -Fxq "runtime-file=$runtime_record_one" <<<"$checkout_start"
grep -Fxq "coordination=$log" <<<"$checkout_start"
grep -Fxq "telemetry=$telemetry_log" <<<"$checkout_start"
grep -Fxq 'fence=1' <<<"$checkout_start"
grep -Fxq 'unit=north-coord.service' <<<"$checkout_start"
grep -Fxq "home=$deployment_one" <<<"$checkout_start"
grep -Fxq "bin=$deployment_one/bin" <<<"$checkout_start"
grep -Fxq "args=$test_port|$log" <<<"$checkout_start"
assert_active_record "$generation_one" "$deployment_one" "$revision_one" "$tree_one" "$repo" "$deployment_one/bin/fram-daemon"
[[ $(record_value "$runtime_record_one" PID) == "$(sed -n 's/^pid=//p' <<<"$checkout_start")" ]]
[[ $(record_value "$runtime_record_one" PID_BIRTH) == "$(sed -n 's/^birth=//p' <<<"$checkout_start")" ]]
first_pid=$(record_value "$runtime_record_one" PID)
first_birth=$(record_value "$runtime_record_one" PID_BIRTH)
first_owner=$(record_value "$runtime_record_one" OWNER_TOKEN)
if kill -0 "$first_pid" 2>/dev/null; then
  printf 'completed daemon left its recorded PID alive\n' >&2
  exit 1
fi

# A same-generation restart replaces stale process authority without changing
# the sealed generation or static identity.
checkout_restart=$(run_runtime start)
[[ $(readlink -f "$state/active") == "$generation_one" ]]
assert_active_record "$generation_one" "$deployment_one" "$revision_one" "$tree_one" "$repo" "$deployment_one/bin/fram-daemon"
restart_pid=$(record_value "$runtime_record_one" PID)
restart_birth=$(record_value "$runtime_record_one" PID_BIRTH)
restart_owner=$(record_value "$runtime_record_one" OWNER_TOKEN)
[[ "$restart_pid" != "$first_pid" ]]
[[ "$restart_birth" != "$first_birth" ]]
[[ "$restart_owner" != "$first_owner" ]]
[[ "$restart_pid" == "$(sed -n 's/^pid=//p' <<<"$checkout_restart")" ]]
[[ "$restart_birth" == "$(sed -n 's/^birth=//p' <<<"$checkout_restart")" ]]

# These direct starts test producer mechanics only. They do not acquire
# systemd authority: the consumer must still require controller-unit/MainPID
# equality before treating this record as live process evidence.
hold_ready=$scratch/hold-ready
hold_release=$scratch/hold-release
hold_output=$scratch/hold-output
mkfifo "$hold_release"
NORTH_COORD_TEST_READY=$hold_ready NORTH_COORD_TEST_RELEASE=$hold_release \
  run_runtime start >"$hold_output" & held_start_pid=$!
for _ in $(seq 1 100); do
  [[ -e "$hold_ready" ]] && break
  sleep 0.01
done
if [[ ! -e "$hold_ready" ]]; then
  printf 'held direct start did not reach the daemon\n' >&2
  kill "$held_start_pid" 2>/dev/null || true
  wait "$held_start_pid" 2>/dev/null || true
  exit 1
fi
assert_active_record "$generation_one" "$deployment_one" "$revision_one" "$tree_one" "$repo" "$deployment_one/bin/fram-daemon"
held_record_sha=$(sha256sum "$runtime_record_one" | cut -d' ' -f1)
held_record_pid=$(record_value "$runtime_record_one" PID)
if competing_output=$(run_runtime start 2>&1); then
  printf 'competing direct start replaced live generation authority\n' >&2
  printf 'release\n' >"$hold_release"
  wait "$held_start_pid"
  exit 1
fi
grep -Fq 'selected runtime generation already has an active start' <<<"$competing_output"
[[ $(sha256sum "$runtime_record_one" | cut -d' ' -f1) == "$held_record_sha" ]]
[[ $(record_value "$runtime_record_one" PID) == "$held_record_pid" ]]
printf 'release\n' >"$hold_release"
wait "$held_start_pid"
[[ $(record_value "$runtime_record_one" PID) == "$(sed -n 's/^pid=//p' "$hold_output")" ]]

# Every active-record crash point leaves either the byte-exact prior record or
# one complete new record. The killed process releases its generation lifetime
# lock, and a subsequent start always converges to fresh valid authority.
for boundary in active-runtime-written active-runtime-synced active-runtime-published active-runtime-generation-synced; do
  prior_sha=$(sha256sum "$runtime_record_one" | cut -d' ' -f1)
  prior_owner=$(record_value "$runtime_record_one" OWNER_TOKEN)
  if NORTH_COORD_SELECTOR_CRASH_AT=$boundary run_runtime start >/dev/null 2>&1; then
    printf 'active-record crash injection %s reported success\n' "$boundary" >&2
    exit 1
  else
    crash_status=$?
  fi
  [[ "$crash_status" == 137 ]]
  assert_active_record "$generation_one" "$deployment_one" "$revision_one" "$tree_one" "$repo" "$deployment_one/bin/fram-daemon"
  crashed_sha=$(sha256sum "$runtime_record_one" | cut -d' ' -f1)
  case "$boundary" in
    active-runtime-written|active-runtime-synced)
      [[ "$crashed_sha" == "$prior_sha" ]]
      [[ $(record_value "$runtime_record_one" OWNER_TOKEN) == "$prior_owner" ]]
      ;;
    active-runtime-published|active-runtime-generation-synced)
      [[ "$crashed_sha" != "$prior_sha" ]]
      [[ $(record_value "$runtime_record_one" OWNER_TOKEN) != "$prior_owner" ]]
      ;;
  esac
  crashed_pid=$(record_value "$runtime_record_one" PID)
  if kill -0 "$crashed_pid" 2>/dev/null; then
    printf 'crash hook %s left its recorded PID alive\n' "$boundary" >&2
    exit 1
  fi
  crashed_owner=$(record_value "$runtime_record_one" OWNER_TOKEN)
  converged_start=$(run_runtime start)
  assert_active_record "$generation_one" "$deployment_one" "$revision_one" "$tree_one" "$repo" "$deployment_one/bin/fram-daemon"
  [[ $(record_value "$runtime_record_one" OWNER_TOKEN) != "$crashed_owner" ]]
  [[ $(record_value "$runtime_record_one" PID) == "$(sed -n 's/^pid=//p' <<<"$converged_start")" ]]
  [[ $(record_value "$runtime_record_one" PID_BIRTH) == "$(sed -n 's/^birth=//p' <<<"$converged_start")" ]]
done

# Ordinary North launchers consume the same exact validation/export path.
identity_probe=$scratch/identity-probe
# The single-quoted body is the generated probe, not this test's environment.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" "$NORTH_FRAM_RUNTIME" "$FRAM_RUNTIME_SOURCE" "$FRAM_RUNTIME_REV" "$FRAM_RUNTIME_TREE" "$FRAM_RUNTIME_ORIGIN" "$FRAM_RUNTIME_DAEMON" "${FRAM_RUNTIME_OWNER_TOKEN-unset}" "$NORTH_COORD_RUNTIME_GENERATION" "$NORTH_COORD_RUNTIME_IDENTITY" "$NORTH_COORD_RUNTIME_FILE" "$FRAM_LOG" "$FRAM_TELEMETRY_LOG" "$FRAM_REQUIRE_LOG_FENCE" "$NORTH_COORD_SYSTEMD_UNIT"' \
  >"$identity_probe"
chmod +x "$identity_probe"
probe_output=$(run_runtime exec-checkout "$identity_probe")
[[ "$probe_output" == "checkout|$deployment_one|$revision_one|$tree_one|$repo|$deployment_one/bin/fram-daemon|unset|$generation_one|$generation_one/current.identity|$runtime_record_one|$log|$telemetry_log|1|north-coord.service" ]]

# Selector publication immediately rebinds runtime-record discovery to the new
# generation. Until that generation is started it has no active authority;
# the previous generation's stale record is never reused.
run_runtime promote "$repo" "$revision_two" >/dev/null
deployment_two=$state/deployments/$revision_two
generation_two=$(readlink -f "$state/active")
runtime_record_two=$generation_two/active.runtime
[[ "$generation_two" != "$generation_one" ]]
[[ ! -e "$runtime_record_two" && ! -L "$runtime_record_two" ]]
[[ -f "$runtime_record_one" && ! -L "$runtime_record_one" ]]
probe_output=$(run_runtime exec-checkout "$identity_probe")
tree_two=$(git -C "$deployment_two" rev-parse 'HEAD^{tree}')
[[ "$probe_output" == "checkout|$deployment_two|$revision_two|$tree_two|$repo|$deployment_two/bin/fram-daemon|unset|$generation_two|$generation_two/current.identity|$runtime_record_two|$log|$telemetry_log|1|north-coord.service" ]]
rebound_start=$(run_runtime start)
assert_active_record "$generation_two" "$deployment_two" "$revision_two" "$tree_two" "$repo" "$deployment_two/bin/fram-daemon"
[[ $(record_value "$runtime_record_two" PID) == "$(sed -n 's/^pid=//p' <<<"$rebound_start")" ]]
run_runtime promote "$repo" "$revision_one" >/dev/null

# A failed promotion cannot move the active generation.
before_failed_promote=$(read_pair)
if run_runtime promote "$repo" does-not-exist >/dev/null 2>&1; then
  printf 'invalid revision was promoted\n' >&2
  exit 1
fi
[[ $(read_pair) == "$before_failed_promote" ]]

# Tracked drift and attached deployment state both fail closed.
printf 'drift\n' >"$deployment_one/revision.txt"
if run_runtime start >/dev/null 2>&1; then
  printf 'dirty deployment was started\n' >&2
  exit 1
fi
if run_runtime exec-checkout "$identity_probe" >/dev/null 2>&1; then
  printf 'ordinary launcher accepted dirty deployment\n' >&2
  exit 1
fi
git -C "$deployment_one" restore revision.txt

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$deployment_one/bin/UNTRACKED-EXECUTABLE"
chmod +x "$deployment_one/bin/UNTRACKED-EXECUTABLE"
if run_runtime status >/dev/null 2>&1 || run_runtime start >/dev/null 2>&1; then
  printf 'untracked executable in selected deployment was accepted\n' >&2
  exit 1
fi
if run_runtime exec-checkout "$identity_probe" >/dev/null 2>&1; then
  printf 'ordinary launcher accepted untracked deployment bytes\n' >&2
  exit 1
fi
unlink "$deployment_one/bin/UNTRACKED-EXECUTABLE"

run_runtime promote "$repo" "$revision_two" >/dev/null
run_runtime promote "$repo" "$revision_three" >/dev/null
deployment_three=$state/deployments/$revision_three

# Promotion/rollback/package publish a linearizable pair under overlap. A/B
# may complete in either order, but a hybrid pair is impossible.
for _ in $(seq 1 20); do
  run_runtime package >/dev/null
  run_runtime promote "$repo" "$revision_one" >/dev/null & promote_one=$!
  run_runtime promote "$repo" "$revision_two" >/dev/null & promote_two=$!
  wait "$promote_one"
  wait "$promote_two"
  assert_pair_is \
    "$deployment_one|$deployment_two" \
    "$deployment_two|$deployment_one"
done

for _ in $(seq 1 20); do
  run_runtime package >/dev/null
  run_runtime promote "$repo" "$revision_one" >/dev/null & promote_pid=$!
  run_runtime package >/dev/null & package_pid=$!
  wait "$promote_pid"
  wait "$package_pid"
  assert_pair_is \
    "$deployment_one|$package" \
    "$package|$deployment_one"
done

for _ in $(seq 1 20); do
  run_runtime promote "$repo" "$revision_two" >/dev/null
  run_runtime package >/dev/null
  run_runtime promote "$repo" "$revision_one" >/dev/null & promote_pid=$!
  run_runtime rollback >/dev/null & rollback_pid=$!
  wait "$promote_pid"
  wait "$rollback_pid"
  assert_pair_is \
    "$package|$deployment_one" \
    "$deployment_one|$deployment_two"
done

# Killing a writer at every publication seam leaves the exact pre-state or
# exact post-state; readers can never observe a half-published pair.
for boundary in generation-created current-written previous-written generation-synced active-prepared active-published state-synced; do
  current=$(readlink -f "$state/current")
  if [[ "$current" == "$deployment_three" ]]; then
    target_revision=$revision_two
    target=$deployment_two
  else
    target_revision=$revision_three
    target=$deployment_three
  fi
  pre_pair=$(read_pair)
  expected_post="$target|$current"
  if NORTH_COORD_SELECTOR_CRASH_AT=$boundary run_runtime promote "$repo" "$target_revision" >/dev/null 2>&1; then
    printf 'crash injection %s reported success\n' "$boundary" >&2
    exit 1
  fi
  run_runtime status >/dev/null
  assert_pair_is "$pre_pair" "$expected_post"
done

# A symlink substituted for a revision-owned deployment cannot bless another
# SHA, even if the target is itself a valid detached deployment.
run_runtime package >/dev/null
git -C "$repo" worktree remove --force "$deployment_one"
ln -s "$deployment_two" "$deployment_one"
before_substitution=$(read_pair)
if run_runtime promote "$repo" "$revision_one" >/dev/null 2>&1; then
  printf 'symlink-substituted deployment was promoted\n' >&2
  exit 1
fi
[[ $(read_pair) == "$before_substitution" ]]
unlink "$deployment_one"

# An attached worktree at the exact revision-owned path remains mutable and is
# rejected by promote, status, and start.
git -C "$repo" worktree add -b runtime-attached-test "$deployment_one" "$revision_one" >/dev/null
if run_runtime promote "$repo" "$revision_one" >/dev/null 2>&1; then
  printf 'attached deployment was promoted\n' >&2
  exit 1
fi
git -C "$repo" worktree remove --force "$deployment_one"
git -C "$repo" branch -D runtime-attached-test >/dev/null
run_runtime promote "$repo" "$revision_one" >/dev/null
if git -C "$deployment_one" switch --detach >/dev/null 2>&1; then
  git -C "$deployment_one" switch -c runtime-attached-selected >/dev/null
  if run_runtime status >/dev/null 2>&1 || run_runtime start >/dev/null 2>&1; then
    printf 'attached selected deployment was accepted\n' >&2
    exit 1
  fi
  git -C "$deployment_one" switch --detach "$revision_one" >/dev/null
  git -C "$repo" branch -D runtime-attached-selected >/dev/null
fi

# Package mode is explicit, reversible, and cannot satisfy checkout launchers.
run_runtime package >/dev/null
package_start=$(run_runtime start)
package_generation=$(readlink -f "$state/active")
grep -Fxq 'label=package' <<<"$package_start"
grep -Fxq 'mode=package' <<<"$package_start"
grep -Fxq "source=$package" <<<"$package_start"
grep -Fxq "revision=$package_revision" <<<"$package_start"
grep -Eq '^owner=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' <<<"$package_start"
assert_active_record "$package_generation" "$package" "$package_revision" "immutable:$package_revision" "$package" "$package/bin/fram-daemon"
if run_runtime exec-checkout "$identity_probe" >/dev/null 2>&1; then
  printf 'checkout launcher accepted package selection\n' >&2
  exit 1
fi

# Systemd's ExecCondition refuses an occupied port before loading the fact log.
run_runtime preflight
python3 -m http.server "$test_port" --bind 127.0.0.1 >/dev/null 2>&1 & listener_pid=$!
for _ in $(seq 1 50); do
  [[ -n $(ss -H -ltn "sport = :$test_port") ]] && break
  sleep 0.02
done
if run_runtime preflight >/dev/null 2>&1; then
  printf 'occupied coordinator port passed preflight\n' >&2
  kill "$listener_pid"
  wait "$listener_pid" 2>/dev/null || true
  exit 1
fi
kill "$listener_pid"
wait "$listener_pid" 2>/dev/null || true
run_runtime preflight

# Stable selectors and active generations themselves are protected from path
# substitution rather than canonicalized into attacker-selected state.
unlink "$state/current"
ln -s active/previous "$state/current"
if run_runtime status >/dev/null 2>&1; then
  printf 'substituted stable selector was accepted\n' >&2
  exit 1
fi

printf 'ok: north-coord runtime is explicit, linearizable, crash-atomic, exact, identity-bearing, and fail-closed\n'
