#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
runtime=$here/north-coord-runtime
source_module=$here/default.bnix
generated_module=$here/default.nix
scratch=$(mktemp -d)
trap 'rm -rf "${scratch:?}"' EXIT

state=$scratch/state
repo=$scratch/fram
package=$scratch/package
package_source=$package/libexec/fram
package_daemon=$package/bin/fram-daemon
north_package=$scratch/north-package
log=$scratch/coordination.log
telemetry_log=$scratch/telemetry.log
north_calls=$scratch/north-calls
north_fail=$scratch/north-fail
fram_calls=$scratch/fram-calls
fram_fail=$scratch/fram-fail
fram_down=$scratch/fram-down
test_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
mkdir -p "$repo/bin" "$package/bin" "$package_source/bin" "$north_package/bin"
export NORTH_COORD_TEST_CALLS=$north_calls
export NORTH_COORD_TEST_FAIL=$north_fail
export NORTH_COORD_TEST_FRAM_CALLS=$fram_calls
export NORTH_COORD_TEST_FRAM_FAIL=$fram_fail
export NORTH_COORD_TEST_FRAM_DOWN=$fram_down
# Refusals deliberately pace systemd's retry loop; the simulation asserts the
# decision, not the wall clock.
export NORTH_COORD_PREFLIGHT_REFUSAL_BACKOFF=0

grep -Fq ':ExecStartPre [(s northCoordRuntime "/bin/north-coord-runtime preflight")' \
  "$source_module"
grep -Fq '(s northCoordRuntime "/bin/north-coord-runtime ensure-default")' \
  "$source_module"
grep -Fq '${northCoordRuntime}/bin/north-coord-runtime ensure-default' \
  "$generated_module"
if rg -n 'ExecCondition.*north-coord-runtime preflight' \
  "$source_module" "$generated_module"; then
  printf 'occupied-port preflight still skips the unit through ExecCondition\n' >&2
  exit 1
fi
if rg -n 'ExecStartPre.*north-coord-runtime package' \
  "$source_module" "$generated_module"; then
  printf 'systemd startup still resets the sealed runtime to package mode\n' >&2
  exit 1
fi

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

cat >"$package/bin/fram" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == doctor ]]
{
  printf 'log=%s\n' "$FRAM_LOG"
  printf 'telemetry=%s\n' "$FRAM_TELEMETRY_LOG"
  printf 'port=%s\n' "$FRAM_PORT"
  printf 'fence=%s\n' "$FRAM_REQUIRE_LOG_FENCE"
} >>"$NORTH_COORD_TEST_FRAM_CALLS"
if [[ -e "$NORTH_COORD_TEST_FRAM_FAIL" ]]; then
  printf 'REJECTED by coordinator: the daemon serves a different log\n'
  exit 17
fi
# The real `fram doctor` is a REPORT, not a gate: it exits 0 even when the
# listener is not a coordinator on the canonical log (verified 2026-07-26
# against a foreign listener). The first line — never the exit status — is
# what preflight is allowed to trust.
if [[ -e "$NORTH_COORD_TEST_FRAM_DOWN" ]]; then
  printf 'coordinator DOWN on 127.0.0.1:%s — start it with bin/fram-up\n' "$FRAM_PORT"
  exit 0
fi
printf 'coordinator UP on 127.0.0.1:%s (v1)\n' "$FRAM_PORT"
EOF
chmod +x "$package/bin/fram"

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

write_daemon "$package_daemon" package
write_daemon "$package_source/bin/fram-daemon" package-inner-wrong
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

file_source_package=$scratch/file-source-package
mkdir -p "$file_source_package/libexec" "$file_source_package/bin"
: >"$file_source_package/libexec/fram"
write_daemon "$file_source_package/bin/fram-daemon" file-source-package
if package=$file_source_package \
   run_runtime_in_state "$scratch/file-source-state" initialize >/dev/null 2>&1; then
  printf 'regular-file package source was accepted\n' >&2
  exit 1
fi

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

# Read-only operations never infer package mode from missing state. The
# service-facing ensure-default transition initializes only pristine state.
if run_runtime status >/dev/null 2>&1; then
  printf 'missing selector silently initialized package mode\n' >&2
  exit 1
fi
run_runtime ensure-default
fresh_status=$(run_runtime status)
grep -Fxq 'mode=package' <<<"$fresh_status"
grep -Fxq "source=$package_source" <<<"$fresh_status"
grep -Fxq "revision=$package_revision" <<<"$fresh_status"
grep -Fxq "tree=immutable:$package_revision" <<<"$fresh_status"
[[ $(readlink "$state/current") == active/current ]]
[[ $(readlink "$state/previous") == active/previous ]]
[[ $(readlink -f "$state/current") == "$package_source" ]]
[[ $(readlink -f "$state/previous") == "$package_source" ]]

# A persisted pre-upgrade package generation names the immutable outer package
# as both source and origin. The explicit package selection recognizes only
# that exact current-system shape, then atomically republishes the two-level
# package identity while preserving the prior checkout as the rollback target.
legacy_state=$scratch/legacy-state
run_runtime_in_state "$legacy_state" initialize
run_runtime_in_state "$legacy_state" promote "$repo" "$revision_one" >/dev/null
run_runtime_in_state "$legacy_state" rollback >/dev/null
legacy_seed_generation=$(readlink -f "$legacy_state/active")
legacy_previous=$(readlink -f "$legacy_state/previous")
[[ "$legacy_previous" == "$legacy_state/deployments/$revision_one" ]]
unlink "$legacy_seed_generation/current"
ln -s "$package" "$legacy_seed_generation/current"
{
  printf '%s\n' north-fram-runtime-v1 package "$package" "$package_revision"
  printf '%s\n' "immutable:$package_revision" "$package" "$package_daemon"
} >"$legacy_seed_generation/current.identity"
run_runtime_in_state "$legacy_state" package >/dev/null
legacy_migrated_generation=$(readlink -f "$legacy_state/active")
[[ "$legacy_migrated_generation" != "$legacy_seed_generation" ]]
[[ $(readlink -f "$legacy_state/current") == "$package_source" ]]
[[ $(readlink -f "$legacy_state/previous") == "$legacy_previous" ]]
[[ $(sed -n '3p' "$legacy_migrated_generation/current.identity") == "$package_source" ]]
[[ $(sed -n '6p' "$legacy_migrated_generation/current.identity") == "$package" ]]
[[ $(sed -n '7p' "$legacy_migrated_generation/current.identity") == "$package_daemon" ]]
grep -Fxq "source=$package_source" < <(run_runtime_in_state "$legacy_state" status)
run_runtime_in_state "$legacy_state" rollback >/dev/null
[[ $(readlink -f "$legacy_state/current") == "$legacy_previous" ]]
[[ $(readlink -f "$legacy_state/previous") == "$package_source" ]]
grep -Fxq "source=$legacy_previous" < <(run_runtime_in_state "$legacy_state" status)

# A system upgrade must not strand the selector on the historical v1 package
# shape. The old generation named its immutable outer package as both source
# and origin; loading normalizes that identity to its own libexec/fram, then an
# explicit package selection atomically publishes new-current/old-previous.
historical_hash=0123456789abcdfghijklmnpqrsvwxyz
historical_package=$scratch/${historical_hash}-fram-old
historical_source=$historical_package/libexec/fram
historical_daemon=$historical_package/bin/fram-daemon
historical_revision=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
outside_package=$scratch/outside/${historical_hash}-fram-old
outside_source=$outside_package/libexec/fram
outside_daemon=$outside_package/bin/fram-daemon
mkdir -p "$historical_source" "$historical_package/bin"
mkdir -p "$outside_source" "$outside_package/bin"
write_daemon "$historical_daemon" historical-package
write_daemon "$outside_daemon" outside-package

upgrade_state=$scratch/upgrade-state
run_runtime_in_state "$upgrade_state" initialize
run_runtime_in_state "$upgrade_state" promote "$repo" "$revision_one" >/dev/null
run_runtime_in_state "$upgrade_state" rollback >/dev/null
upgrade_seed_generation=$(readlink -f "$upgrade_state/active")
unlink "$upgrade_seed_generation/current"
ln -s "$historical_package" "$upgrade_seed_generation/current"

# A legacy identity still has to bind tree, daemon, and the trusted immutable
# store root before its source can be normalized.
{
  printf '%s\n' north-fram-runtime-v1 package "$historical_package" "$historical_revision"
  printf '%s\n' "immutable:$package_revision" "$historical_package" "$historical_daemon"
} >"$upgrade_seed_generation/current.identity"
if run_runtime_in_state "$upgrade_state" package >/dev/null 2>&1; then
  printf 'historical legacy package with a mismatched tree marker was accepted\n' >&2
  exit 1
fi
[[ $(readlink -f "$upgrade_state/active") == "$upgrade_seed_generation" ]]

{
  printf '%s\n' north-fram-runtime-v1 package "$historical_package" "$historical_revision"
  printf '%s\n' "immutable:$historical_revision" "$historical_package" "$package_daemon"
} >"$upgrade_seed_generation/current.identity"
if run_runtime_in_state "$upgrade_state" package >/dev/null 2>&1; then
  printf 'historical legacy package with a foreign daemon was accepted\n' >&2
  exit 1
fi
[[ $(readlink -f "$upgrade_state/active") == "$upgrade_seed_generation" ]]

unlink "$upgrade_seed_generation/current"
ln -s "$outside_package" "$upgrade_seed_generation/current"
{
  printf '%s\n' north-fram-runtime-v1 package "$outside_package" "$historical_revision"
  printf '%s\n' "immutable:$historical_revision" "$outside_package" "$outside_daemon"
} >"$upgrade_seed_generation/current.identity"
if run_runtime_in_state "$upgrade_state" package >/dev/null 2>&1; then
  printf 'historical legacy package outside the current package store root was accepted\n' >&2
  exit 1
fi
[[ $(readlink -f "$upgrade_state/active") == "$upgrade_seed_generation" ]]

unlink "$upgrade_seed_generation/current"
ln -s "$historical_package" "$upgrade_seed_generation/current"
{
  printf '%s\n' north-fram-runtime-v1 package "$historical_package" "$historical_revision"
  printf '%s\n' "immutable:$historical_revision" "$historical_package" "$historical_daemon"
} >"$upgrade_seed_generation/current.identity"
run_runtime_in_state "$upgrade_state" package >/dev/null
upgrade_generation=$(readlink -f "$upgrade_state/active")
[[ "$upgrade_generation" != "$upgrade_seed_generation" ]]
[[ $(readlink -f "$upgrade_state/current") == "$package_source" ]]
[[ $(readlink -f "$upgrade_state/previous") == "$historical_source" ]]
[[ $(sed -n '3p' "$upgrade_generation/current.identity") == "$package_source" ]]
[[ $(sed -n '6p' "$upgrade_generation/current.identity") == "$package" ]]
[[ $(sed -n '3p' "$upgrade_generation/previous.identity") == "$historical_source" ]]
[[ $(sed -n '4p' "$upgrade_generation/previous.identity") == "$historical_revision" ]]
[[ $(sed -n '5p' "$upgrade_generation/previous.identity") == "immutable:$historical_revision" ]]
[[ $(sed -n '6p' "$upgrade_generation/previous.identity") == "$historical_package" ]]
[[ $(sed -n '7p' "$upgrade_generation/previous.identity") == "$historical_daemon" ]]
grep -Fxq "source=$package_source" < <(run_runtime_in_state "$upgrade_state" status)

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
assert_active_record "$aliased_generation" "$package_source" "$package_revision" "immutable:$package_revision" "$package" "$package_daemon"

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
   run_runtime_in_state "$crash_init_state" ensure-default >/dev/null 2>&1; then
  printf 'first-install crash injection reported success\n' >&2
  exit 1
fi
run_runtime_in_state "$crash_init_state" ensure-default
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
if run_runtime_in_state "$missing_state" ensure-default >/dev/null 2>&1; then
  printf 'ensure-default repaired a lost active selection without evidence\n' >&2
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

# The exact systemd restart prelude preserves an explicit development
# transaction rather than silently resetting it to the package default.
promoted_pair=$(read_pair)
run_runtime ensure-default
run_runtime prepare >/dev/null
[[ $(read_pair) == "$promoted_pair" ]]
grep -Fxq mode=checkout < <(run_runtime status)
[[ $(readlink -f "$state/current") == "$deployment_one" ]]

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
    "$deployment_one|$package_source" \
    "$package_source|$deployment_one"
done

for _ in $(seq 1 20); do
  run_runtime promote "$repo" "$revision_two" >/dev/null
  run_runtime package >/dev/null
  run_runtime promote "$repo" "$revision_one" >/dev/null & promote_pid=$!
  run_runtime rollback >/dev/null & rollback_pid=$!
  wait "$promote_pid"
  wait "$rollback_pid"
  assert_pair_is \
    "$package_source|$deployment_one" \
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
package_pair=$(read_pair)
run_runtime ensure-default
run_runtime prepare >/dev/null
[[ $(read_pair) == "$package_pair" ]]
grep -Fxq mode=package < <(run_runtime status)
[[ $(readlink -f "$state/current") == "$package_source" ]]
package_start=$(run_runtime start)
package_generation=$(readlink -f "$state/active")
grep -Fxq 'label=package' <<<"$package_start"
grep -Fxq 'mode=package' <<<"$package_start"
grep -Fxq "source=$package_source" <<<"$package_start"
grep -Fxq "revision=$package_revision" <<<"$package_start"
grep -Fxq "origin=$package" <<<"$package_start"
grep -Fxq "daemon=$package_daemon" <<<"$package_start"
grep -Fxq "home=$package_source" <<<"$package_start"
grep -Fxq "bin=$package/bin" <<<"$package_start"
grep -Eq '^owner=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' <<<"$package_start"
assert_active_record "$package_generation" "$package_source" "$package_revision" "immutable:$package_revision" "$package" "$package_daemon"
if run_runtime exec-checkout "$identity_probe" >/dev/null 2>&1; then
  printf 'checkout launcher accepted package selection\n' >&2
  exit 1
fi

# Simulate the rebuild activation window without a real socket: the ss fixture
# reports one live process as :7977's owner. A foreign-log listener is never
# signalled; a canonical user-scope Fram coordinator is terminated, and the
# ordinary service prelude then reaches the selected package runtime.
preflight_bin=$scratch/preflight-bin
preflight_proc=$scratch/preflight-proc
mkdir -p "$preflight_bin" "$preflight_proc"
cat >"$preflight_bin/ss" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
pid=${NORTH_COORD_TEST_LISTENER_PID:-}
if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
  printf 'LISTEN 0 50 127.0.0.1:%s 0.0.0.0:* users:(("java",pid=%s,fd=16))\n' \
    "$NORTH_COORD_FRAM_PORT" "$pid"
fi
EOF
chmod +x "$preflight_bin/ss"

sleep 60 & listener_pid=$!
mkdir -p "$preflight_proc/$listener_pid"
printf '0::/user.slice/user-1000.slice/user@1000.service/app.slice/ghostty.scope\n' \
  >"$preflight_proc/$listener_pid/cgroup"
touch "$fram_fail"
if foreign_output=$(
  PATH="$preflight_bin:$PATH" \
  NORTH_COORD_PROC_ROOT="$preflight_proc" \
  NORTH_COORD_TEST_LISTENER_PID="$listener_pid" \
    run_runtime preflight 2>&1
); then
  printf 'foreign-log user-scope listener passed preflight\n' >&2
  kill "$listener_pid"
  wait "$listener_pid" 2>/dev/null || true
  exit 1
fi
grep -Fq 'did not prove the canonical North log; refusing takeover; north-coord.service will retry' \
  <<<"$foreign_output"
kill -0 "$listener_pid"
unlink "$fram_fail"

# The probe's exit status is worthless on its own: the real client reports a
# DOWN coordinator and still exits 0. Only the UP first line may authorize a
# takeover, so a zero-exit non-proof must leave the listener alone.
touch "$fram_down"
if down_output=$(
  PATH="$preflight_bin:$PATH" \
  NORTH_COORD_PROC_ROOT="$preflight_proc" \
  NORTH_COORD_TEST_LISTENER_PID="$listener_pid" \
    run_runtime preflight 2>&1
); then
  printf 'zero-exit DOWN probe authorized a takeover\n' >&2
  kill "$listener_pid"
  wait "$listener_pid" 2>/dev/null || true
  exit 1
fi
grep -Fq 'did not prove the canonical North log; refusing takeover; north-coord.service will retry' \
  <<<"$down_output"
kill -0 "$listener_pid"
unlink "$fram_down"
takeover_output=$(
  PATH="$preflight_bin:$PATH" \
  NORTH_COORD_PROC_ROOT="$preflight_proc" \
  NORTH_COORD_TEST_LISTENER_PID="$listener_pid" \
    run_runtime preflight 2>&1
)
wait "$listener_pid" 2>/dev/null || true
grep -Fq "verified canonical user-scope coordinator pid=$listener_pid; terminating it so north-coord.service owns port $test_port" \
  <<<"$takeover_output"
grep -Fq "reclaimed coordinator port $test_port for north-coord.service" \
  <<<"$takeover_output"
grep -Fxq "log=$log" "$fram_calls"
grep -Fxq "telemetry=$telemetry_log" "$fram_calls"
grep -Fxq "port=$test_port" "$fram_calls"
grep -Fxq 'fence=1' "$fram_calls"

# A system-scope owner is never a takeover candidate, canonical log or not:
# signalling another supervisor's process is the failure this guard prevents.
sleep 60 & system_listener_pid=$!
mkdir -p "$preflight_proc/$system_listener_pid"
printf '0::/system.slice/some-peer-coordinator.service\n' \
  >"$preflight_proc/$system_listener_pid/cgroup"
if system_output=$(
  PATH="$preflight_bin:$PATH" \
  NORTH_COORD_PROC_ROOT="$preflight_proc" \
  NORTH_COORD_TEST_LISTENER_PID="$system_listener_pid" \
    run_runtime preflight 2>&1
); then
  printf 'system-scope listener passed preflight\n' >&2
  kill "$system_listener_pid"
  wait "$system_listener_pid" 2>/dev/null || true
  exit 1
fi
grep -Fq "is not owned by a user-scope process; refusing takeover; north-coord.service will retry" \
  <<<"$system_output"
kill -0 "$system_listener_pid"
kill "$system_listener_pid"
wait "$system_listener_pid" 2>/dev/null || true

PATH="$preflight_bin:$PATH" \
NORTH_COORD_PROC_ROOT="$preflight_proc" \
NORTH_COORD_TEST_LISTENER_PID="$listener_pid" \
  run_runtime preflight
run_runtime ensure-default
run_runtime prepare >/dev/null
plain_switch=$(run_runtime start)
run_runtime settle >/dev/null
grep -Fxq 'mode=package' <<<"$plain_switch"
grep -Fxq "revision=$package_revision" <<<"$plain_switch"

printf 'simulation: foreign user-scope listener remained alive and systemd start failed loudly for retry\n'
printf 'simulation: zero-exit DOWN probe was refused (first line, not exit status, authorizes takeover)\n'
printf 'simulation: system-scope listener was refused without a signal\n'
printf 'simulation: canonical user-scope listener was terminated and port ownership reclaimed\n'
printf 'simulation: plain service prelude selected package@%s\n' "$package_revision"

# ONE desired-mode rule per system generation. Two store-shaped sibling Fram
# roots stand in for two generations' pinned packages: a package selection
# sealed by the previous generation is realigned by the ordinary service
# prelude, while an explicit checkout promotion is announced and survives.
fake_store=$scratch/fake-store
old_package=$fake_store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-fram-old
new_package=$fake_store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-fram-new
old_package_revision=1111111111111111111111111111111111111111
new_package_revision=2222222222222222222222222222222222222222
mode_state=$scratch/mode-state
mkdir -p "$old_package/bin" "$old_package/libexec/fram/bin" \
         "$new_package/bin" "$new_package/libexec/fram/bin"
write_daemon "$old_package/bin/fram-daemon" old-package
write_daemon "$new_package/bin/fram-daemon" new-package

run_mode_runtime() {
  local selected_package=$1 selected_revision=$2
  shift 2
  package=$selected_package package_revision=$selected_revision \
    run_runtime_in_state "$mode_state" "$@"
}

run_mode_runtime "$old_package" "$old_package_revision" ensure-default
grep -Fxq "revision=$old_package_revision" \
  <<<"$(run_mode_runtime "$old_package" "$old_package_revision" status)"

# The generation moved: same selector state, a newer pinned Fram package.
realign_output=$(run_mode_runtime "$new_package" "$new_package_revision" ensure-default 2>&1)
grep -Fq "realigned package selection to this system generation: $old_package/libexec/fram@$old_package_revision -> $new_package/libexec/fram@$new_package_revision" \
  <<<"$realign_output"
mode_status=$(run_mode_runtime "$new_package" "$new_package_revision" status)
grep -Fxq 'mode=package' <<<"$mode_status"
grep -Fxq "revision=$new_package_revision" <<<"$mode_status"
grep -Fxq "source=$new_package/libexec/fram" <<<"$mode_status"

# Idempotent: a second prelude on the same generation reseals nothing.
repeat_output=$(run_mode_runtime "$new_package" "$new_package_revision" ensure-default 2>&1)
if grep -Fq 'realigned package selection' <<<"$repeat_output"; then
  printf 'aligned package selection was resealed on an unchanged generation\n' >&2
  exit 1
fi
[[ "$(readlink -f "$mode_state/current")" == "$new_package/libexec/fram" ]]

# An explicit development override outlives the prelude and says so.
run_mode_runtime "$new_package" "$new_package_revision" \
  promote "$repo" "$revision_one" >/dev/null
override_output=$(run_mode_runtime "$new_package" "$new_package_revision" ensure-default 2>&1)
grep -Fq "keeping explicit checkout@$revision_one development override across this system generation" \
  <<<"$override_output"
grep -Fxq "revision=$revision_one" \
  <<<"$(run_mode_runtime "$new_package" "$new_package_revision" status)"

# ...until it is explicitly cleared, which is the only way back to package mode.
run_mode_runtime "$new_package" "$new_package_revision" package >/dev/null
grep -Fxq "revision=$new_package_revision" \
  <<<"$(run_mode_runtime "$new_package" "$new_package_revision" status)"

printf 'simulation: stale-generation package selection realigned %s -> %s by the ordinary prelude\n' \
  "$old_package_revision" "$new_package_revision"
printf 'simulation: checkout@%s override survived the prelude and was cleared only explicitly\n' \
  "$revision_one"

# Stable selectors and active generations themselves are protected from path
# substitution rather than canonicalized into attacker-selected state.
unlink "$state/current"
ln -s active/previous "$state/current"
if run_runtime status >/dev/null 2>&1; then
  printf 'substituted stable selector was accepted\n' >&2
  exit 1
fi

printf 'ok: north-coord runtime is explicit, linearizable, crash-atomic, exact, identity-bearing, and fail-closed\n'
