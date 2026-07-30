#!/usr/bin/env bash
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

token=$scratch/cutover.token
route=$scratch/route.map
gate_state=$scratch/gate
fake_state=$scratch/fake
systemd_state=$scratch/systemd
jcmd_state=$scratch/jcmd-state
proc_root=$scratch/proc
cutover_log=$scratch/cutover.log
mkdir -p "$gate_state" "$fake_state" "$systemd_state" "$jcmd_state" "$proc_root"
printf 'test-secret\n' >"$token"
chmod 0600 "$token"
printf 'active blue\n' >"$route"

cat >"$scratch/runtime" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s %s\n' \
  "$NORTH_COORD_SLOT" "$FRAM_COORD_ROLE" "$FRAM_REQUIRE_LOG_FENCE" \
  >>"$NORTH_COORD_TEST_ROLE_LOG"
[[ "$FRAM_CUTOVER_TOKEN" == test-secret ]]
[[ "$1" == start ]]
SH
chmod 0700 "$scratch/runtime"

run_slot() {
  NORTH_COORD_SLOT=$1 \
  NORTH_COORD_SELECTOR_MAP=$route \
  NORTH_COORD_CUTOVER_TOKEN_FILE=$token \
  NORTH_COORD_SLOT_RUNTIME=$scratch/runtime \
  NORTH_COORD_TEST_ROLE_LOG=$scratch/roles \
    "$here/north-coord-slot-start"
}

# Every private unit derives authority from the one durable key on every
# restart. This is the four-unit start contract, including a post-cutover
# restart on both sides.
run_slot blue
run_slot blue
run_slot green
run_slot green
cat >"$scratch/roles.expected" <<'EOF'
blue active 1
blue active 1
green standby 1
green standby 1
EOF
cmp "$scratch/roles.expected" "$scratch/roles"

printf 'active green\n' >"$route"
: >"$scratch/roles"
run_slot blue
run_slot blue
run_slot green
run_slot green
cat >"$scratch/roles.expected" <<'EOF'
blue standby 1
blue standby 1
green active 1
green active 1
EOF
cmp "$scratch/roles.expected" "$scratch/roles"

printf 'active blue\n' >"$route"

write_endpoint() {
  printf '%s %s %s %s\n' "$2" "$3" "$4" "${5:-none}" >"$fake_state/$1"
}
write_endpoint 17977 active blue-coord 10
write_endpoint 17978 active blue-telemetry 20
write_endpoint 27977 standby green-coord 10
write_endpoint 27978 standby green-telemetry 20

write_process_identity() {
  local unit=$1 main_pid=$2 port=$3 birth=$4
  local revision=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  local origin=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-fram-test
  mkdir -p "$proc_root/$main_pid"
  {
    printf '%s (java) S' "$main_pid"
    for _ in {1..18}; do printf ' 0'; done
    printf ' %s\n' "$birth"
  } >"$proc_root/$main_pid/stat"
  printf '%s\0' \
    "NORTH_FRAM_RUNTIME=package" \
    "FRAM_RUNTIME_SOURCE=$origin/libexec/fram" \
    "FRAM_RUNTIME_REV=$revision" \
    "FRAM_RUNTIME_TREE=immutable:$revision" \
    "FRAM_RUNTIME_ORIGIN=$origin" \
    "FRAM_RUNTIME_DAEMON=$origin/bin/fram-daemon" \
    "NORTH_COORD_SYSTEMD_UNIT=$unit" \
    "FRAM_PORT=$port" \
    >"$proc_root/$main_pid/environ"
}

write_unit_health() {
  local memory_current=${2:-1200000000}
  local tasks_current=${3:-24}
  local memory_max=${4:-}
  local memory_swap_max=${5:-0}
  local cpu_quota=${6:-infinity}
  local n_restarts=${7:-0}
  local drop_in_paths=${8:-}
  local main_pid port runtime_name
  local invocation=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  local exec_start=1000000
  case "$1" in
    north-coord-blue.service)
      main_pid=4101; port=17977; memory_max=${memory_max:-8589934592} ;;
    north-telemetry-coord-blue.service)
      main_pid=4102; port=17978; memory_max=${memory_max:-6442450944}
      invocation=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; exec_start=2000000 ;;
    north-coord-green.service)
      main_pid=4201; port=27977; memory_max=${memory_max:-8589934592}
      invocation=cccccccccccccccccccccccccccccccc; exec_start=3000000 ;;
    north-telemetry-coord-green.service)
      main_pid=4202; port=27978; memory_max=${memory_max:-6442450944}
      invocation=dddddddddddddddddddddddddddddddd; exec_start=4000000 ;;
    *) return 2 ;;
  esac
  runtime_name=${1%.service}-runtime
  cat >"$systemd_state/$1" <<EOF
LoadState=loaded
FragmentPath=/etc/systemd/system/$1
DropInPaths=$drop_in_paths
NeedDaemonReload=no
ActiveState=active
SubState=running
InvocationID=$invocation
MainPID=$main_pid
ExecMainStartTimestampMonotonic=$exec_start
MemoryCurrent=$memory_current
MemoryMax=$memory_max
MemorySwapMax=$memory_swap_max
CPUQuotaPerSecUSec=$cpu_quota
TasksCurrent=$tasks_current
TasksMax=512
NRestarts=$n_restarts
Restart=always
ExecStart={ path=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-north-coord-slot-start/bin/north-coord-slot-start ; argv[]=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-north-coord-slot-start/bin/north-coord-slot-start ; }
ExecStartPre={ path=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-$runtime_name/bin/$runtime_name ; argv[]=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-$runtime_name/bin/$runtime_name ensure-default ; }
EOF
  write_process_identity "$1" "$main_pid" "$port" "$((exec_start + 10))"
}

write_unit_health north-coord-blue.service
write_unit_health north-telemetry-coord-blue.service
write_unit_health north-coord-green.service
write_unit_health north-telemetry-coord-green.service

cat >"$scratch/systemctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == show ]]
cat "$NORTH_COORD_TEST_SYSTEMD_STATE/$2"
SH
chmod 0700 "$scratch/systemctl"

cat >"$scratch/jcmd" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
pid=$1
command=$2
mode=$(<"$NORTH_COORD_TEST_JCMD_MODE_FILE")
if [[ -f "$NORTH_COORD_TEST_JCMD_MODE_FILE.$pid" ]]; then
  mode=$(<"$NORTH_COORD_TEST_JCMD_MODE_FILE.$pid")
fi
if (( pid % 2 == 1 )); then
  max_heap=6442450944
  heap_total=6291456K
  heap_high=3145728K
else
  max_heap=4294967296
  heap_total=4194304K
  heap_high=2097152K
fi
case "$command:$mode" in
  VM.flags:healthy|VM.flags:heap-high)
    printf '%s:\n-XX:+UseG1GC -XX:MaxHeapSize=%s\n' "$pid" "$max_heap"
    ;;
  VM.flags:oversized)
    printf '%s:\n-XX:+UseG1GC -XX:MaxHeapSize=8589934592\n' "$pid"
    ;;
  VM.flags:serial)
    printf '%s:\n-XX:MaxHeapSize=1073741824 -XX:+UseSerialGC\n' "$pid"
    ;;
  VM.flags:missing)
    exit 1
    ;;
  VM.flags:malformed)
    printf '%s:\nnot-jvm-flags\n' "$pid"
    ;;
  GC.heap_info:healthy|GC.heap_info:serial|GC.heap_info:oversized)
    printf '%s:\n garbage-first heap   total %s, used 1200000K [0x0, 0x1)\n' \
      "$pid" "$heap_total"
    ;;
  GC.heap_info:heap-high)
    printf '%s:\n garbage-first heap   total %s, used %s [0x0, 0x1)\n' \
      "$pid" "$heap_total" "$heap_high"
    ;;
  GC.heap_info:missing)
    exit 1
    ;;
  GC.heap_info:malformed)
    printf '%s:\nunknown heap\n' "$pid"
    ;;
  *)
    exit 2
    ;;
esac
if [[ "$command" == GC.heap_info &&
      -n "${NORTH_COORD_TEST_JCMD_ROLLOVER_UNIT:-}" ]]; then
  cp -- "$NORTH_COORD_TEST_JCMD_ROLLOVER_STATE" \
    "$NORTH_COORD_TEST_SYSTEMD_STATE/$NORTH_COORD_TEST_JCMD_ROLLOVER_UNIT"
fi
if [[ "$command" == GC.heap_info &&
      -n "${NORTH_COORD_TEST_JCMD_FRAM_ROLLOVER_PORT:-}" ]]; then
  endpoint=$NORTH_COORD_TEST_FAKE_STATE/$NORTH_COORD_TEST_JCMD_FRAM_ROLLOVER_PORT
  read -r phase _ version cutover_id <"$endpoint"
  printf '%s replacement-instance %s %s\n' \
    "$phase" "$version" "$cutover_id" >"$endpoint"
fi
SH
chmod 0700 "$scratch/jcmd"
printf 'healthy\n' >"$jcmd_state/mode"

cat >"$scratch/fram-cutover" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

command=$1
shift
port= log= cutover_id= expected_instance= marker_out= marker_file=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) port=$2 ;;
    --log) log=$2 ;;
    --cutover-id) cutover_id=$2 ;;
    --expected-instance) expected_instance=$2 ;;
    --marker-out) marker_out=$2 ;;
    --marker-file) marker_file=$2 ;;
  esac
  shift 2
done

endpoint=$NORTH_COORD_TEST_FAKE_STATE/$port
read -r phase instance version endpoint_cutover_id <"$endpoint"
endpoint_cutover_id=${endpoint_cutover_id:-none}
authorized=false
[[ "$phase" == active ]] && authorized=true

case "$command" in
  status)
    outer_phase=$phase
    cutover_phase=$phase
    writer_role=$phase
    if [[ "$phase" == demoted ]]; then
      outer_phase=retired
      cutover_phase=demoted
      writer_role=retired
    elif [[ "$phase" == rejected ]]; then
      outer_phase=standby
      cutover_phase=promotion-rejected
      writer_role=standby
    elif [[ "$phase" == prepared-standby ]]; then
      outer_phase=standby
      cutover_phase=prepared
      writer_role=standby
    elif [[ "$phase" == prepared-demoted ]]; then
      outer_phase=retired
      cutover_phase=prepared
      writer_role=retired
    fi
    if [[ "$endpoint_cutover_id" == none ]]; then
      printf '{:ok true :protocol "fram-coordinator-cutover/v1" :phase :%s :instance "%s" :version %s :writer-authority {:role :%s :write-authorized %s} :cutover {:phase :%s}}\n' \
        "$outer_phase" "$instance" "$version" "$writer_role" "$authorized" "$cutover_phase"
    else
      printf '{:ok true :protocol "fram-coordinator-cutover/v1" :phase :%s :instance "%s" :version %s :writer-authority {:role :%s :write-authorized %s} :cutover {:phase :%s :cutover-id "%s"}}\n' \
        "$outer_phase" "$instance" "$version" "$writer_role" "$authorized" \
        "$cutover_phase" "$endpoint_cutover_id"
    fi
    ;;
  prepare)
    printf 'prepare %s %s\n' "$port" "$cutover_id" \
      >>"$NORTH_COORD_TEST_CUTOVER_LOG"
    if [[ -n "${NORTH_COORD_TEST_FAIL_PREPARE_PORT:-}" &&
          "$port" == "$NORTH_COORD_TEST_FAIL_PREPARE_PORT" ]]; then
      exit 3
    fi
    case "$phase" in
      standby|rejected|prepared-standby)
        phase=prepared-standby
        response_phase=standby
        ;;
      demoted|prepared-demoted)
        phase=prepared-demoted
        response_phase=retired
        ;;
      *) exit 3 ;;
    esac
    printf '%s %s %s %s\n' \
      "$phase" "$instance" "$version" "$cutover_id" >"$endpoint"
    prewarmed=${NORTH_COORD_TEST_PREWARMED:-true}
    proof_mode=${NORTH_COORD_TEST_PREPARE_PROOF_MODE:-healthy}
    source_instance=$instance
    primary_log=$log
    case "$port" in
      17977|27977) peer_log=$NORTH_COORD_TELEMETRY_LOG ;;
      17978|27978) peer_log=$NORTH_COORD_COORD_LOG ;;
      *) exit 2 ;;
    esac
    primary_label=primary
    peer_label=telemetry
    case "$proof_mode" in
      healthy) ;;
      missing-peer) peer_log= ;;
      duplicate-label) peer_label=primary ;;
      duplicate-path) peer_log=$primary_log ;;
      foreign-label) peer_label=foreign ;;
      foreign-path) peer_log=/tmp/foreign-cutover-peer.log ;;
      swapped-paths)
        swapped=$primary_log
        primary_log=$peer_log
        peer_log=$swapped
        ;;
      instance-mismatch) source_instance=wrong-instance ;;
      trailing|malformed) ;;
      *) exit 2 ;;
    esac
    if [[ "$proof_mode" == malformed ]]; then
      printf '{:ok true :protocol\n'
      exit 0
    fi
    if [[ -n "$peer_log" ]]; then
      printf -v log_proofs '[{:label :%s :path "%s" :bytes 0 :file-key "fake-%s-primary" :identity "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" :boundary-sha "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"} {:label :%s :path "%s" :bytes 0 :file-key "fake-%s-peer" :identity "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" :boundary-sha "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}]' \
        "$primary_label" "$primary_log" "$port" \
        "$peer_label" "$peer_log" "$port"
    else
      printf -v log_proofs '[{:label :%s :path "%s" :bytes 0 :file-key "fake-%s-primary" :identity "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" :boundary-sha "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]' \
        "$primary_label" "$primary_log" "$port"
    fi
    printf '{:ok true :protocol "fram-coordinator-cutover/v1" :phase :%s :prepared true :cutover-id "%s" :instance "%s" :version %s :marker {:format "fram-coordinator-cutover-marker/v1" :cutover-id "%s" :source-instance "%s" :version %s :logs %s} :sync {:reload :unchanged :attempts 1 :prewarmed %s :elapsed-ms 1} :writer-authority {:role :%s :write-authorized false}}\n' \
      "$response_phase" "$cutover_id" "$instance" "$version" \
      "$cutover_id" "$source_instance" "$version" "$log_proofs" "$prewarmed" \
      "$response_phase"
    if [[ "$proof_mode" == trailing ]]; then
      printf '{:trailing true}\n'
    fi
    ;;
  demote)
    printf 'demote %s %s\n' "$port" "$cutover_id" \
      >>"$NORTH_COORD_TEST_CUTOVER_LOG"
    [[ "$phase" == active && "$expected_instance" == "$instance" ]]
    printf 'demoted %s %s %s\n' \
      "$instance" "$version" "$cutover_id" >"$endpoint"
    printf '{:format "fram-coordinator-cutover-marker/v1" :cutover-id "%s" :version %s :instance "%s"}\n' \
      "$cutover_id" "$version" "$instance" >"$marker_out"
    chmod 0600 "$marker_out"
    printf '{:ok true :protocol "fram-coordinator-cutover/v1"}\n'
    ;;
  promote)
    printf 'promote %s %s\n' "$port" "$cutover_id" \
      >>"$NORTH_COORD_TEST_CUTOVER_LOG"
    if [[ -n "${NORTH_COORD_TEST_FAIL_PROMOTE_PORT:-}" &&
          "$port" == "$NORTH_COORD_TEST_FAIL_PROMOTE_PORT" &&
          ! -e "$NORTH_COORD_TEST_FAKE_STATE/failure.used" ]]; then
      : >"$NORTH_COORD_TEST_FAKE_STATE/failure.used"
      printf 'rejected %s %s %s\n' \
        "$instance" "$version" "$cutover_id" >"$endpoint"
      if [[ -n "${NORTH_COORD_TEST_STALE_OLD_PORT:-}" ]]; then
        old_endpoint=$NORTH_COORD_TEST_FAKE_STATE/$NORTH_COORD_TEST_STALE_OLD_PORT
        read -r old_phase old_instance old_version old_cutover_id <"$old_endpoint"
        printf '%s %s %s %s\n' \
          "$old_phase" "$old_instance" "$((old_version + 1))" \
          "$old_cutover_id" >"$old_endpoint"
      fi
      exit 3
    fi
    [[ "$phase" == standby ||
       "$phase" == demoted ||
       "$phase" == prepared-standby ||
       "$phase" == prepared-demoted ||
       "$phase" == rejected ]]
    [[ -f "$marker_file" ]]
    read -r marker_cutover_id marker_version < <(
      bb -e '(require (quote [clojure.edn :as edn]))
             (let [m (edn/read-string (slurp (first *command-line-args*)))]
               (println (:cutover-id m) (:version m)))' \
        "$marker_file"
    )
    if [[ "$marker_cutover_id" != "$cutover_id" ||
          "$marker_version" != "$version" ]]; then
      printf 'rejected %s %s %s\n' \
        "$instance" "$version" "$cutover_id" >"$endpoint"
      exit 3
    fi
    if [[ -n "${NORTH_COORD_TEST_DROP_PROMOTE_PORT:-}" &&
          "$port" == "$NORTH_COORD_TEST_DROP_PROMOTE_PORT" ]]; then
      exit 4
    fi
    if [[ -n "${NORTH_COORD_TEST_TIMEOUT_PROMOTE_PORT:-}" &&
          "$port" == "$NORTH_COORD_TEST_TIMEOUT_PROMOTE_PORT" ]]; then
      (
        sleep "${NORTH_COORD_TEST_PRETRANSITION_DELAY_SECONDS:-0.15}"
        printf 'promoting %s %s %s\n' \
          "$instance" "$version" "$cutover_id" >"$endpoint"
        sleep "${NORTH_COORD_TEST_DELAY_PROMOTE_SECONDS:-0.2}"
        printf 'active %s %s %s\n' \
          "$instance" "$version" "$cutover_id" >"$endpoint"
      ) >/dev/null 2>&1 &
      exit 4
    fi
    if [[ -n "${NORTH_COORD_TEST_DELAY_PROMOTE_PORT:-}" &&
          "$port" == "$NORTH_COORD_TEST_DELAY_PROMOTE_PORT" ]]; then
      printf 'promoting %s %s %s\n' \
        "$instance" "$version" "$cutover_id" >"$endpoint"
      (
        sleep "${NORTH_COORD_TEST_DELAY_PROMOTE_SECONDS:-0.2}"
        printf 'active %s %s %s\n' \
          "$instance" "$version" "$cutover_id" >"$endpoint"
      ) >/dev/null 2>&1 &
    else
      printf 'active %s %s %s\n' \
        "$instance" "$version" "$cutover_id" >"$endpoint"
    fi
    if [[ -n "${NORTH_COORD_TEST_POST_PROMOTE_HEALTH_PORT:-}" &&
          "$port" == "$NORTH_COORD_TEST_POST_PROMOTE_HEALTH_PORT" ]]; then
      printf '%s\n' "$NORTH_COORD_TEST_POST_PROMOTE_HEALTH_MODE" \
        >"$NORTH_COORD_TEST_JCMD_MODE_FILE"
    fi
    printf '{:ok true :protocol "fram-coordinator-cutover/v1"}\n'
    ;;
  *) exit 2 ;;
esac
SH
chmod 0700 "$scratch/fram-cutover"

export NORTH_COORD_CUTOVER_BIN=$scratch/fram-cutover
export NORTH_COORD_CUTOVER_TOKEN_FILE=$token
export NORTH_COORD_CUTOVER_STATE=$gate_state
export NORTH_COORD_COORD_LOG=$scratch/coordination.log
export NORTH_COORD_TELEMETRY_LOG=$scratch/telemetry.log
export NORTH_COORD_SYSTEMCTL_BIN=$scratch/systemctl
export NORTH_COORD_JCMD_BIN=$scratch/jcmd
export NORTH_COORD_PROC_ROOT=$proc_root
export NORTH_COORD_BLUE_COORD_UNIT=north-coord-blue.service
export NORTH_COORD_BLUE_TELEMETRY_UNIT=north-telemetry-coord-blue.service
export NORTH_COORD_GREEN_COORD_UNIT=north-coord-green.service
export NORTH_COORD_GREEN_TELEMETRY_UNIT=north-telemetry-coord-green.service
export NORTH_COORD_BLUE_COORD_PORT=17977
export NORTH_COORD_BLUE_TELEMETRY_PORT=17978
export NORTH_COORD_GREEN_COORD_PORT=27977
export NORTH_COORD_GREEN_TELEMETRY_PORT=27978
export NORTH_COORD_TEST_FAKE_STATE=$fake_state
export NORTH_COORD_TEST_SYSTEMD_STATE=$systemd_state
export NORTH_COORD_TEST_JCMD_MODE_FILE=$jcmd_state/mode
export NORTH_COORD_TEST_CUTOVER_LOG=$cutover_log
export NORTH_COORD_CUTOVER_TIMEOUT_MS=3000
export NORTH_COORD_CUTOVER_SETTLE_TIMEOUT_MS=3000
export NORTH_COORD_CUTOVER_SETTLE_POLL_SECONDS=0.02
: >"$NORTH_COORD_COORD_LOG"
: >"$NORTH_COORD_TELEMETRY_LOG"

transaction=$scratch/selector.transaction

# Invalid authority evidence must survive read_status's temporary-file cleanup.
write_endpoint 17978 standby blue-telemetry 20
if "$here/north-coord-cutover-gate" verify blue \
     >"$scratch/invalid-status.out" 2>"$scratch/invalid-status.err"; then
  invalid_status_rc=0
else
  invalid_status_rc=$?
fi
write_endpoint 17978 active blue-telemetry 20
if compgen -G "$gate_state/status.*" >/dev/null; then
  echo "invalid status left a temporary status file" >&2
  exit 1
fi
grep -q 'invalid cutover status' "$scratch/invalid-status.err"
if (( invalid_status_rc == 0 )); then
  echo "invalid telemetry authority status unexpectedly verified" >&2
  exit 1
fi

assert_prepare_rejected() {
  local label=$1 before_demotions after_demotions
  before_demotions=$(rg -c '^demote ' "$cutover_log" 2>/dev/null || true)
  if "$here/north-coord-cutover-gate" prepare blue green "$transaction"; then
    echo "$label target unexpectedly prepared" >&2
    exit 1
  fi
  [[ ! -e "$gate_state/gate.current" ]]
  [[ ! -e "$gate_state/readiness.coord" ]]
  [[ ! -e "$gate_state/readiness.telemetry" ]]
  [[ ! -e "$transaction" && ! -L "$transaction" ]]
  grep -Fxq 'active blue' "$route"
  read -r blue_coord_phase _ <"$fake_state/17977"
  read -r blue_telemetry_phase _ <"$fake_state/17978"
  [[ "$blue_coord_phase" == active ]]
  [[ "$blue_telemetry_phase" == active ]]
  after_demotions=$(rg -c '^demote ' "$cutover_log" 2>/dev/null || true)
  [[ "$after_demotions" == "$before_demotions" ]]
}

# Preparation failure is entirely pre-transaction and read-only. Even when one
# target endpoint acknowledged preparation, neither source endpoint is demoted.
export NORTH_COORD_TEST_FAIL_PREPARE_PORT=27978
if "$here/north-coord-cutover-gate" prepare blue green "$transaction"; then
  echo "partial target preparation unexpectedly succeeded" >&2
  exit 1
fi
unset NORTH_COORD_TEST_FAIL_PREPARE_PORT
[[ ! -e "$transaction" ]]
read -r blue_coord_phase _ <"$fake_state/17977"
read -r blue_telemetry_phase _ <"$fake_state/17978"
[[ "$blue_coord_phase" == active ]]
[[ "$blue_telemetry_phase" == active ]]
if rg -n '^demote ' "$cutover_log"; then
  echo "preparation failure demoted a source endpoint" >&2
  exit 1
fi

# Preparation must prove a current installed marker/cache and a live process
# that already runs the exact recovery envelope. Every rejection remains before
# selector transaction creation, frontend HOLD, or source authority mutation.
export NORTH_COORD_TEST_PREWARMED=false
assert_prepare_rejected missing-prewarm
unset NORTH_COORD_TEST_PREWARMED

for proof_mode in \
  missing-peer \
  duplicate-label \
  duplicate-path \
  foreign-label \
  foreign-path \
  swapped-paths \
  instance-mismatch \
  trailing \
  malformed
do
  export NORTH_COORD_TEST_PREPARE_PROOF_MODE=$proof_mode
  assert_prepare_rejected "prepare-proof-$proof_mode"
done
unset NORTH_COORD_TEST_PREPARE_PROOF_MODE

# Healthy telemetry cannot hide a bad coordination process.
printf 'oversized\n' >"$jcmd_state/mode.4201"
assert_prepare_rejected oversized-coordination-heap
rm -f -- "$jcmd_state/mode.4201"
write_unit_health north-coord-green.service 1200000000 24 1572864000
assert_prepare_rejected wrong-coordination-cgroup-limit
write_unit_health north-coord-green.service 1200000000 24 8589934592 1073741824
assert_prepare_rejected wrong-coordination-swap-limit
write_unit_health north-coord-green.service 1200000000 24 8589934592 0 500000
assert_prepare_rejected wrong-coordination-cpu-quota
write_unit_health north-coord-green.service 1200000000 129
assert_prepare_rejected coordination-task-bound
write_unit_health north-coord-green.service 1200000000 24 8589934592 0 infinity 1
assert_prepare_rejected coordination-restart
write_unit_health north-coord-green.service 1200000000 24 8589934592 0 infinity 0 \
  /run/systemd/system/north-coord-green.service.d/override.conf
assert_prepare_rejected coordination-drop-in
write_unit_health north-coord-green.service
sed -i 's/^MainPID=4201$/MainPID=4999/' \
  "$systemd_state/north-coord-green.service"
assert_prepare_rejected stale-coordination-pid-identity
write_unit_health north-coord-green.service

# Healthy coordination cannot hide a bad telemetry process.
printf 'serial\n' >"$jcmd_state/mode.4202"
assert_prepare_rejected serial-telemetry-1g
rm -f -- "$jcmd_state/mode.4202"

write_unit_health north-telemetry-coord-green.service 1200000000 24 1572864000
assert_prepare_rejected wrong-cgroup-limit
write_unit_health north-telemetry-coord-green.service 1200000000 24 6442450944 1073741824
assert_prepare_rejected wrong-swap-limit
write_unit_health north-telemetry-coord-green.service 3221225472
assert_prepare_rejected memory-current-at-limit
write_unit_health north-telemetry-coord-green.service 1200000000 129
assert_prepare_rejected task-bound
write_unit_health north-telemetry-coord-green.service

printf 'heap-high\n' >"$jcmd_state/mode"
assert_prepare_rejected heap-used-at-limit
printf 'missing\n' >"$jcmd_state/mode"
assert_prepare_rejected missing-jcmd-evidence
printf 'malformed\n' >"$jcmd_state/mode"
assert_prepare_rejected malformed-jcmd-evidence
printf 'healthy\n' >"$jcmd_state/mode"

cat >"$scratch/systemd-swap-rollover" <<'EOF'
ActiveState=active
SubState=running
InvocationID=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
MainPID=4202
ExecMainStartTimestampMonotonic=2000000
MemoryCurrent=1200000000
MemoryMax=6442450944
MemorySwapMax=1073741824
TasksCurrent=24
EOF
export NORTH_COORD_TEST_JCMD_ROLLOVER_UNIT=north-telemetry-coord-green.service
export NORTH_COORD_TEST_JCMD_ROLLOVER_STATE=$scratch/systemd-swap-rollover
assert_prepare_rejected systemd-swap-limit-rollover
unset NORTH_COORD_TEST_JCMD_ROLLOVER_UNIT NORTH_COORD_TEST_JCMD_ROLLOVER_STATE
write_unit_health north-telemetry-coord-green.service

cat >"$scratch/systemd-rollover" <<'EOF'
ActiveState=active
SubState=running
InvocationID=cccccccccccccccccccccccccccccccc
MainPID=5202
ExecMainStartTimestampMonotonic=3000000
MemoryCurrent=1200000000
MemoryMax=6442450944
MemorySwapMax=0
TasksCurrent=24
EOF
export NORTH_COORD_TEST_JCMD_ROLLOVER_UNIT=north-telemetry-coord-green.service
export NORTH_COORD_TEST_JCMD_ROLLOVER_STATE=$scratch/systemd-rollover
assert_prepare_rejected systemd-invocation-rollover
unset NORTH_COORD_TEST_JCMD_ROLLOVER_UNIT NORTH_COORD_TEST_JCMD_ROLLOVER_STATE
write_unit_health north-telemetry-coord-green.service

export NORTH_COORD_TEST_JCMD_FRAM_ROLLOVER_PORT=27978
assert_prepare_rejected fram-instance-rollover
unset NORTH_COORD_TEST_JCMD_FRAM_ROLLOVER_PORT
write_endpoint 27978 standby green-telemetry 20

# A process that was healthy during open preparation may not coast through a
# bad live-envelope recheck immediately before source demotion.
"$here/north-coord-cutover-gate" prepare blue green "$transaction"
printf 'serial\n' >"$jcmd_state/mode"
if "$here/north-coord-cutover-gate" promote blue green "$transaction"; then
  echo "serial/1g target unexpectedly passed the pre-demotion recheck" >&2
  exit 1
fi
if rg -n '^demote ' "$cutover_log"; then
  echo "pre-demotion health rejection changed source authority" >&2
  exit 1
fi
"$here/north-coord-cutover-gate" rollback green blue "$transaction"
printf 'healthy\n' >"$jcmd_state/mode"

# The same process is checked again after Fram has synchronized the final
# marker and promoted it, while the selector still holds the frontend. A live
# regression here returns failure so selector rollback restores the source.
: >"$cutover_log"
"$here/north-coord-cutover-gate" prepare blue green "$transaction"
export NORTH_COORD_TEST_POST_PROMOTE_HEALTH_PORT=27978
export NORTH_COORD_TEST_POST_PROMOTE_HEALTH_MODE=heap-high
if "$here/north-coord-cutover-gate" promote blue green "$transaction"; then
  echo "post-promotion heap regression unexpectedly passed" >&2
  exit 1
fi
unset NORTH_COORD_TEST_POST_PROMOTE_HEALTH_PORT \
  NORTH_COORD_TEST_POST_PROMOTE_HEALTH_MODE
printf 'healthy\n' >"$jcmd_state/mode"
grep -Eq '^demote (17977|17978) ' "$cutover_log"
"$here/north-coord-cutover-gate" rollback green blue "$transaction"
"$here/north-coord-cutover-gate" verify blue

# A partial pair promotion must fail closed, then independently reconcile the
# already-promoted coordination endpoint and the merely-demoted telemetry
# endpoint back to the old pair.
export NORTH_COORD_TEST_FAIL_PROMOTE_PORT=27978
"$here/north-coord-cutover-gate" prepare blue green "$transaction"
if "$here/north-coord-cutover-gate" promote blue green "$transaction"; then
  echo "partial promotion unexpectedly succeeded" >&2
  exit 1
fi
"$here/north-coord-cutover-gate" rollback green blue "$transaction"
"$here/north-coord-cutover-gate" verify blue
unset NORTH_COORD_TEST_FAIL_PROMOTE_PORT

# A successful daemon demotion reports outer lifecycle :retired plus nested
# cutover phase :demoted. Promotion may acknowledge while status is still
# :promoting. Prove both real shapes settle without a false gate failure.
export NORTH_COORD_TEST_DELAY_PROMOTE_PORT=27977
export NORTH_COORD_TEST_TIMEOUT_PROMOTE_PORT=27977
"$here/north-coord-cutover-gate" prepare blue green "$transaction"
"$here/north-coord-cutover-gate" promote blue green "$transaction"
unset NORTH_COORD_TEST_DELAY_PROMOTE_PORT NORTH_COORD_TEST_TIMEOUT_PROMOTE_PORT
"$here/north-coord-cutover-gate" verify green
"$here/north-coord-cutover-gate" prepare green blue "$transaction"
"$here/north-coord-cutover-gate" promote green blue "$transaction"
"$here/north-coord-cutover-gate" verify blue

# Crash after selector records gate-started but before the gate program writes
# its own state: no authority mutation occurred, so recovery proves old active
# and returns without inventing a marker.
rm -f -- "$gate_state/gate.current" "$gate_state"/*.edn
"$here/north-coord-cutover-gate" rollback green blue "$transaction"
"$here/north-coord-cutover-gate" verify blue

# Proxy startup has an independent authority-marker guard in addition to the
# systemd ConditionPathExists gate.
if NORTH_COORD_HAPROXY=/bin/true \
   NORTH_COORD_HAPROXY_CONFIG=$scratch/haproxy.cfg \
   NORTH_COORD_BOOTSTRAP_MARKER=$scratch/missing \
     "$here/north-coord-proxy-start"; then
  echo "proxy started without bootstrap authority marker" >&2
  exit 1
fi

# If an exact demotion marker goes stale before a never-active target can take
# authority, rollback must remain fail-closed. It may not change the marker,
# invent a version, or report the old pair restored.
write_endpoint 17977 active blue-coord 30
write_endpoint 17978 active blue-telemetry 40
write_endpoint 27977 standby green-coord 30
write_endpoint 27978 standby green-telemetry 40
rm -f -- "$fake_state/failure.used" "$gate_state"/*.edn
export NORTH_COORD_TEST_FAIL_PROMOTE_PORT=27978
export NORTH_COORD_TEST_STALE_OLD_PORT=17978
"$here/north-coord-cutover-gate" prepare blue green "$transaction"
if "$here/north-coord-cutover-gate" promote blue green "$transaction"; then
  echo "stale-marker promotion unexpectedly succeeded" >&2
  exit 1
fi
cp -- "$gate_state/telemetry.old-demotion.edn" "$scratch/stale-marker.before"
read -r _ _ stale_blue_version _ <"$fake_state/17978"
read -r _ _ stale_green_version _ <"$fake_state/27978"
if "$here/north-coord-cutover-gate" rollback green blue "$transaction"; then
  echo "stale-marker rollback unexpectedly resumed authority" >&2
  exit 1
fi
cmp "$scratch/stale-marker.before" "$gate_state/telemetry.old-demotion.edn"
read -r blue_telemetry_phase _ <"$fake_state/17978"
read -r green_telemetry_phase _ <"$fake_state/27978"
read -r _ _ blue_telemetry_version _ <"$fake_state/17978"
read -r _ _ green_telemetry_version _ <"$fake_state/27978"
[[ "$blue_telemetry_phase" != active ]]
[[ "$green_telemetry_phase" != active ]]
[[ "$blue_telemetry_version" == "$stale_blue_version" ]]
[[ "$green_telemetry_version" == "$stale_green_version" ]]
unset NORTH_COORD_TEST_FAIL_PROMOTE_PORT NORTH_COORD_TEST_STALE_OLD_PORT

# A transport timeout may happen before the server installs :promoting. Keep
# polling the exact ID instead of sampling the old stable phase once.
write_endpoint 17977 active blue-coord 50
write_endpoint 17978 active blue-telemetry 60
write_endpoint 27977 standby green-coord 50
write_endpoint 27978 standby green-telemetry 60
rm -f -- "$gate_state"/*.edn "$fake_state/failure.used"
export NORTH_COORD_TEST_TIMEOUT_PROMOTE_PORT=27977
"$here/north-coord-cutover-gate" prepare blue green "$transaction"
"$here/north-coord-cutover-gate" promote blue green "$transaction"
[[ ! -e "$gate_state/outcome.unknown" ]]
unset NORTH_COORD_TEST_TIMEOUT_PROMOTE_PORT

# If no terminal phase is ever observable, preserve the unresolved record and
# refuse rollback. A late queued server request can therefore never race a
# resumed frontend.
write_endpoint 17977 active blue-coord 70
write_endpoint 17978 active blue-telemetry 80
write_endpoint 27977 standby green-coord 70
write_endpoint 27978 standby green-telemetry 80
rm -f -- "$gate_state"/*.edn "$fake_state/failure.used"
export NORTH_COORD_TEST_DROP_PROMOTE_PORT=27978
export NORTH_COORD_CUTOVER_SETTLE_TIMEOUT_MS=200
"$here/north-coord-cutover-gate" prepare blue green "$transaction"
if "$here/north-coord-cutover-gate" promote blue green "$transaction"; then
  echo "unobservable promotion unexpectedly succeeded" >&2
  exit 1
fi
[[ -f "$gate_state/outcome.unknown" ]]
if "$here/north-coord-cutover-gate" rollback green blue "$transaction"; then
  echo "rollback ignored an unresolved transport outcome" >&2
  exit 1
fi
[[ -f "$gate_state/outcome.unknown" ]]
unset NORTH_COORD_TEST_DROP_PROMOTE_PORT

printf 'blue/green activation behavior: PASS\n'
