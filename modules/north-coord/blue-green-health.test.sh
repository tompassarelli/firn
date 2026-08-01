#!/usr/bin/env bash
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_module=$here/default.bnix
generated_module=$here/default.nix
selector=$here/north-coord-selector
gate=$here/north-coord-cutover-gate
health=$here/north-coord-health

for command in haproxy socat python3 timeout rg bb; do
  command -v "$command" >/dev/null || {
    printf 'missing test dependency: %s\n' "$command" >&2
    exit 2
  }
done

for module in "$source_module" "$generated_module"; do
  [[ $(rg -c 'option tcp-check' "$module") -eq 4 ]]
  [[ $(rg -c 'send-binary 0a' "$module") -eq 4 ]]
  [[ $(rg -c 'expect string :version' "$module") -eq 4 ]]
  [[ $(rg -c 'timeout check 5s' "$module") -eq 1 ]]
  [[ $(rg -c 'north-coord-health' "$module") -ge 4 ]]
  [[ $(rg -c 'NORTH_COORD_SELECTOR_FAILOVER_COMMAND' "$module") -ge 2 ]]
done
bash -n "$selector"
bash -n "$gate"
bash -n "$health"
[[ $(rg -c 'failover-prepare' "$gate") -ge 2 ]]
[[ $(rg -c '^  failover\)' "$gate") -eq 1 ]]
[[ $(rg -c '^  failover\)' "$selector") -eq 1 ]]
if rg -n 'unmask' "$health"; then
  printf 'health controller contains forbidden mask reversal\n' >&2
  exit 1
fi

# The gate's emergency path must settle uncertainty, prove the successor,
# stop the old pair, and only then capture fresh promotion markers.
failover_body=$(sed -n '/^failover_pair()/,/^rollback_pair()/p' "$gate")
settle_line=$(rg -n 'settle_recorded_unknown' <<<"$failover_body" | cut -d: -f1)
verify_line=$(rg -n 'verify_pair "\$target" read-only' <<<"$failover_body" | cut -d: -f1)
stop_line=$(rg -n 'timeout 30s "\$systemctl_bin" stop' <<<"$failover_body" | cut -d: -f1)
prepare_line=$(rg -n 'prepare_endpoint "\$target"' <<<"$failover_body" | cut -d: -f1)
promote_line=$(rg -n 'promote_endpoint "\$target"' <<<"$failover_body" | cut -d: -f1)
(( settle_line < verify_line && verify_line < stop_line &&
   stop_line < prepare_line && prepare_line < promote_line ))
rg -q 'old pair is healthy-active; use switch' <<<"$failover_body"
rg -q 'outcome\.unknown' "$gate"

scratch=$(mktemp -d)
proxy_pid=
blue_pid=
green_pid=

cleanup() {
  for pid in "$proxy_pid" "$blue_pid" "$green_pid"; do
    [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true
  done
  for pid in "$proxy_pid" "$blue_pid" "$green_pid"; do
    [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true
  done
  [[ ${NORTH_COORD_TEST_KEEP:-0} -eq 1 ]] || rm -rf -- "$scratch"
}
trap cleanup EXIT

cat >"$scratch/backend.py" <<'PY'
import os
import socket
import sys
import threading
import time

mode_path, port_path, requested = sys.argv[1:]
listener = socket.socket()
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", int(requested)))
listener.listen(128)
with open(port_path, "w") as out:
    print(listener.getsockname()[1], file=out)

def handle(conn):
    with conn:
        conn.recv(4096)
        mode = open(mode_path).read().strip()
        if mode == "healthy":
            conn.sendall(b"{:version 1}\n")
        elif mode == "reject":
            conn.sendall(b"{:ok false :error :log-mismatch}\n")
        elif mode == "silent":
            time.sleep(8)

while True:
    conn, _ = listener.accept()
    threading.Thread(target=handle, args=(conn,), daemon=True).start()
PY

start_backend() {
  local mode_path=$1 port_path=$2 requested=$3 pid_name=$4
  python3 "$scratch/backend.py" "$mode_path" "$port_path" "$requested" &
  printf -v "$pid_name" '%s' "$!"
  for _ in $(seq 1 100); do
    [[ -s "$port_path" ]] && return 0
    sleep 0.02
  done
  return 1
}

printf 'healthy\n' >"$scratch/blue.mode"
printf 'healthy\n' >"$scratch/green.mode"
start_backend "$scratch/blue.mode" "$scratch/blue.port" 0 blue_pid
start_backend "$scratch/green.mode" "$scratch/green.port" 0 green_pid
blue_port=$(<"$scratch/blue.port")
green_port=$(<"$scratch/green.port")
admin_socket=$scratch/admin.sock
route_map=$scratch/route.map
config=$scratch/haproxy.cfg
printf 'active blue\n' >"$route_map"

cat >"$config" <<EOF
global
  stats socket $admin_socket mode 600 level admin

defaults
  mode tcp
  timeout connect 2s
  timeout check 5s
  timeout client 1h
  timeout server 1h

frontend north-public
  bind $scratch/public.sock
  acl route_blue str(active),map($route_map) -m str blue
  default_backend coord-blue

backend coord-blue
  option tcp-check
  tcp-check send '{:op :for-log :expected-log "$scratch/coordination.log" :request {:op :version-free}}'
  tcp-check send-binary 0a
  tcp-check expect string :version
  server only 127.0.0.1:$blue_port check inter 2s fastinter 500ms downinter 1s rise 2 fall 3
backend telemetry-blue
  option tcp-check
  tcp-check send '{:op :for-log :expected-log "$scratch/telemetry.log" :request {:op :version-free}}'
  tcp-check send-binary 0a
  tcp-check expect string :version
  server only 127.0.0.1:$blue_port check inter 2s fastinter 500ms downinter 1s rise 2 fall 3
backend coord-green
  option tcp-check
  tcp-check send '{:op :for-log :expected-log "$scratch/coordination.log" :request {:op :version-free}}'
  tcp-check send-binary 0a
  tcp-check expect string :version
  server only 127.0.0.1:$green_port check inter 2s fastinter 500ms downinter 1s rise 2 fall 3
backend telemetry-green
  option tcp-check
  tcp-check send '{:op :for-log :expected-log "$scratch/telemetry.log" :request {:op :version-free}}'
  tcp-check send-binary 0a
  tcp-check expect string :version
  server only 127.0.0.1:$green_port check inter 2s fastinter 500ms downinter 1s rise 2 fall 3
EOF

haproxy -c -f "$config"
haproxy -db -f "$config" &
proxy_pid=$!
for _ in $(seq 1 100); do
  [[ -S "$admin_socket" ]] && break
  sleep 0.02
done
[[ -S "$admin_socket" ]]

backend_status() {
  local backend=$1
  printf 'show stat\n' | socat -t 2 - "UNIX-CONNECT:$admin_socket" |
    awk -F, -v backend="$backend" '$1 == backend && $2 == "only" {print $18}'
}

wait_status() {
  local backend=$1 expected=$2
  for _ in $(seq 1 75); do
    [[ $(backend_status "$backend") == "$expected" ]] && return 0
    sleep 0.2
  done
  printf '%s did not reach %s\n' "$backend" "$expected" >&2
  return 1
}

set_server_state() {
  local backend=$1 state=$2 expected=$3
  printf 'set server %s/only state %s\n' "$backend" "$state" |
    socat -t 2 - "UNIX-CONNECT:$admin_socket"
  wait_status "$backend" "$expected"
}

wait_status coord-blue UP
printf 'reject\n' >"$scratch/blue.mode"
wait_status coord-blue DOWN
printf 'silent\n' >"$scratch/blue.mode"
wait_status coord-blue DOWN
kill "$blue_pid"
wait "$blue_pid" 2>/dev/null || true
blue_pid=
wait_status coord-blue DOWN
rm -f -- "$scratch/blue.port"
printf 'healthy\n' >"$scratch/blue.mode"
start_backend "$scratch/blue.mode" "$scratch/blue.port" "$blue_port" blue_pid
wait_status coord-blue UP

# A planned switch must reject a DOWN target before invoking preparation.
printf 'reject\n' >"$scratch/green.mode"
wait_status coord-green DOWN
selector_state=$scratch/selector
mkdir -p "$selector_state"
for name in prepare promote rollback verify failover; do
  cat >"$selector_state/$name" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "${0##*/}" "$*" >>"$NORTH_COORD_TEST_SELECTOR_LOG"
SH
  chmod 0700 "$selector_state/$name"
done
export NORTH_COORD_TEST_SELECTOR_LOG=$scratch/selector.log
export NORTH_COORD_SELECTOR_SOCKET=$admin_socket
export NORTH_COORD_SELECTOR_MAP=$route_map
export NORTH_COORD_SELECTOR_FRONTEND=north-public
export NORTH_COORD_SELECTOR_LOCK=$scratch/selector.lock
export NORTH_COORD_SELECTOR_OWNER
NORTH_COORD_SELECTOR_OWNER=$(id -un)
export NORTH_COORD_SELECTOR_GROUP
NORTH_COORD_SELECTOR_GROUP=$(id -gn)
export NORTH_COORD_SELECTOR_TRANSACTION=$scratch/selector.transaction
export NORTH_COORD_SELECTOR_PREPARE_COMMAND=$selector_state/prepare
export NORTH_COORD_SELECTOR_PROMOTE_COMMAND=$selector_state/promote
export NORTH_COORD_SELECTOR_ROLLBACK_COMMAND=$selector_state/rollback
export NORTH_COORD_SELECTOR_VERIFY_COMMAND=$selector_state/verify
export NORTH_COORD_SELECTOR_FAILOVER_COMMAND=$selector_state/failover
if "$selector" switch green >"$scratch/switch.out" 2>"$scratch/switch.err"; then
  printf 'selector switched to a DOWN target\n' >&2
  exit 1
fi
rg -q 'not passing haproxy health checks' "$scratch/switch.err"
[[ ! -e "$NORTH_COORD_TEST_SELECTOR_LOG" ]]

# Controller tests use real HAProxy status and deterministic authority/unit
# shims, so each decision-table conjunction remains independently movable.
systemd_state=$scratch/systemd
mkdir -p "$systemd_state"
systemctl_log=$scratch/systemctl.log
for unit in \
  north-coord-blue.service north-telemetry-coord-blue.service \
  north-coord-green.service north-telemetry-coord-green.service; do
  printf 'enabled\n' >"$systemd_state/$unit.enabled"
  printf 'active\n' >"$systemd_state/$unit.ActiveState"
  printf 'running\n' >"$systemd_state/$unit.SubState"
  printf 'success\n' >"$systemd_state/$unit.Result"
done
cat >"$scratch/systemctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$NORTH_COORD_TEST_SYSTEMCTL_LOG"
case "$1" in
  is-enabled) cat "$NORTH_COORD_TEST_SYSTEMD_STATE/$2.enabled" ;;
  show)
    property=${2#--property=}
    unit=$4
    cat "$NORTH_COORD_TEST_SYSTEMD_STATE/$unit.$property"
    ;;
  mask)
    shift
    [[ "$1" == --runtime ]]
    shift
    for unit in "$@"; do printf 'masked-runtime\n' >"$NORTH_COORD_TEST_SYSTEMD_STATE/$unit.enabled"; done
    ;;
  stop)
    shift
    for unit in "$@"; do printf 'inactive\n' >"$NORTH_COORD_TEST_SYSTEMD_STATE/$unit.ActiveState"; done
    ;;
  *) exit 2 ;;
esac
SH
cat >"$scratch/gate" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == verify-phase ]]
observed=$(<"$NORTH_COORD_TEST_PHASE_STATE/$2.phase")
case "$3:$observed" in
  active:active|read-only:read-only) exit 0 ;;
  *) exit 1 ;;
esac
SH
cat >"$scratch/health-selector" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$NORTH_COORD_TEST_HEALTH_SELECTOR_LOG"
[[ "$1" == failover ]]
printf 'active %s\n' "$2" >"$NORTH_COORD_SELECTOR_MAP"
SH
chmod 0700 "$scratch/systemctl" "$scratch/gate" "$scratch/health-selector"
phase_state=$scratch/phases
health_state=$scratch/health
mkdir -p "$phase_state" "$health_state"
printf 'active\n' >"$phase_state/blue.phase"
printf 'read-only\n' >"$phase_state/green.phase"
printf 'healthy\n' >"$scratch/green.mode"
wait_status coord-green UP

export NORTH_COORD_TEST_SYSTEMCTL_LOG=$systemctl_log
export NORTH_COORD_TEST_SYSTEMD_STATE=$systemd_state
export NORTH_COORD_TEST_PHASE_STATE=$phase_state
export NORTH_COORD_TEST_HEALTH_SELECTOR_LOG=$scratch/health-selector.log
export NORTH_COORD_HEALTH_STATE=$health_state
export NORTH_COORD_HEALTH_JOURNAL=$health_state/journal.log
export NORTH_COORD_HEALTH_FAIL_THRESHOLD=3
export NORTH_COORD_HEALTH_LOCK=$health_state/health.lock
export NORTH_COORD_BOOTSTRAP_MARKER=$scratch/bootstrap-complete
export NORTH_COORD_CUTOVER_GATE=$scratch/gate
export NORTH_COORD_SELECTOR=$scratch/health-selector
export NORTH_COORD_SYSTEMCTL_BIN=$scratch/systemctl
export NORTH_COORD_BLUE_COORD_UNIT=north-coord-blue.service
export NORTH_COORD_BLUE_TELEMETRY_UNIT=north-telemetry-coord-blue.service
export NORTH_COORD_GREEN_COORD_UNIT=north-coord-green.service
export NORTH_COORD_GREEN_TELEMETRY_UNIT=north-telemetry-coord-green.service
: >"$NORTH_COORD_BOOTSTRAP_MARKER"

printf '2\n' >"$health_state/blue.fails"
"$health" reconcile
[[ $(<"$health_state/blue.fails") == 0 ]]

# Current evidence wins over history: a fully healthy routed pair clears even
# an already-latched counter instead of remaining permanently failed.
printf '3\n' >"$health_state/blue.fails"
"$health" reconcile
[[ $(<"$health_state/blue.fails") == 0 ]]

# A missing HAProxy sample is unknown, never proof that the routed pair serves.
NORTH_COORD_SELECTOR_SOCKET=$scratch/missing-admin.sock "$health" reconcile
[[ $(<"$health_state/blue.fails") == 1 ]]
"$health" reconcile
[[ $(<"$health_state/blue.fails") == 0 ]]

# Coordination and telemetry are equal members of the serving contract. A
# telemetry-only failure must trip the same bounded failover path while the
# coordination backend remains healthy.
set_server_state telemetry-blue maint MAINT
[[ $(backend_status coord-blue) == UP ]]
printf '2\n' >"$health_state/blue.fails"
"$health" reconcile
[[ $(<"$health_state/blue.fails") == 3 ]]
[[ $(rg -c '^failover green$' "$NORTH_COORD_TEST_HEALTH_SELECTOR_LOG") -eq 1 ]]
grep -Fxq 'active green' "$route_map"

# Restore the initial topology for the existing coordination-failure case.
set_server_state telemetry-blue ready UP
printf 'active blue\n' >"$route_map"
printf 'enabled\n' >"$systemd_state/north-coord-blue.service.enabled"
printf 'enabled\n' >"$systemd_state/north-telemetry-coord-blue.service.enabled"
printf 'active\n' >"$systemd_state/north-coord-blue.service.ActiveState"
printf 'active\n' >"$systemd_state/north-telemetry-coord-blue.service.ActiveState"
printf '0\n' >"$health_state/blue.fails"
rm -f -- "$NORTH_COORD_TEST_HEALTH_SELECTOR_LOG"

printf 'reject\n' >"$scratch/blue.mode"
printf 'down\n' >"$phase_state/blue.phase"
wait_status coord-blue DOWN
"$health" reconcile
[[ $(<"$health_state/blue.fails") == 1 ]]
"$health" reconcile
[[ $(<"$health_state/blue.fails") == 2 ]]
[[ ! -e "$NORTH_COORD_TEST_HEALTH_SELECTOR_LOG" ]]
"$health" reconcile
[[ $(rg -c '^failover green$' "$NORTH_COORD_TEST_HEALTH_SELECTOR_LOG") -eq 1 ]]
rg -q '^mask --runtime north-coord-blue.service north-telemetry-coord-blue.service$' "$systemctl_log"
rg -q '^stop north-coord-blue.service north-telemetry-coord-blue.service$' "$systemctl_log"

# A masked successor produces an alert and leaves the durable route untouched.
printf 'active blue\n' >"$route_map"
printf 'enabled\n' >"$systemd_state/north-coord-blue.service.enabled"
printf 'enabled\n' >"$systemd_state/north-telemetry-coord-blue.service.enabled"
printf 'active\n' >"$systemd_state/north-coord-blue.service.ActiveState"
printf 'active\n' >"$systemd_state/north-telemetry-coord-blue.service.ActiveState"
printf 'masked-runtime\n' >"$systemd_state/north-coord-green.service.enabled"
printf '2\n' >"$health_state/blue.fails"
before=$(rg -c '^failover ' "$NORTH_COORD_TEST_HEALTH_SELECTOR_LOG")
"$health" reconcile
after=$(rg -c '^failover ' "$NORTH_COORD_TEST_HEALTH_SELECTOR_LOG")
[[ "$before" == "$after" ]]
grep -q 'CRITICAL no-successor' "$NORTH_COORD_HEALTH_JOURNAL"
grep -Fxq 'active blue' "$route_map"

# An in-flight selector transaction suppresses every controller action.
printf 'holding blue green\n' >"$NORTH_COORD_SELECTOR_TRANSACTION"
before=$(wc -l <"$systemctl_log")
"$health" reconcile
after=$(wc -l <"$systemctl_log")
[[ "$before" == "$after" ]]
rm -f -- "$NORTH_COORD_SELECTOR_TRANSACTION"

# Split authority is alert-only and returns nonzero.
printf 'enabled\n' >"$systemd_state/north-coord-green.service.enabled"
printf 'active\n' >"$phase_state/blue.phase"
printf 'active\n' >"$phase_state/green.phase"
if "$health" reconcile; then
  printf 'split authority unexpectedly reconciled\n' >&2
  exit 1
fi
grep -q 'CRITICAL split-authority' "$NORTH_COORD_HEALTH_JOURNAL"

# A failed standby is masked and stopped without touching the selected slot.
printf 'read-only\n' >"$phase_state/green.phase"
printf 'failed\n' >"$systemd_state/north-coord-green.service.ActiveState"
printf '2\n' >"$health_state/blue.fails"
"$health" reconcile || true
rg -q '^mask --runtime north-coord-green.service north-telemetry-coord-green.service$' "$systemctl_log"

# Journal compaction keeps only a bounded diagnostic tail.
dd if=/dev/zero of="$NORTH_COORD_HEALTH_JOURNAL" bs=1048577 count=1 status=none
printf 'active\n' >"$systemd_state/north-coord-green.service.ActiveState"
printf 'masked-runtime\n' >"$systemd_state/north-coord-green.service.enabled"
"$health" reconcile || true
(( $(stat -c %s "$NORTH_COORD_HEALTH_JOURNAL") <= 1048576 ))

status_output=$({ "$health" status || true; })
[[ $(grep -c '^slot=blue state=.* units=.*/.* checks=.*/.* fails=[0-9][0-9]*$' <<<"$status_output") -eq 1 ]]
[[ $(grep -c '^slot=green state=.* units=.*/.* checks=.*/.* fails=[0-9][0-9]*$' <<<"$status_output") -eq 1 ]]
[[ $(grep -c '^route=blue transaction=none$' <<<"$status_output") -eq 1 ]]

# Existing metadata-incomplete rollback coverage is retained in the activation
# suite; keep its exact no-op proof anchored here as a source regression.
rg -q 'if \[\[ ! -e "\$state/gate.current"' "$gate"
rg -q 'verify_pair "\$old_arg" active' "$gate"

printf 'blue/green health checks and controller behavior: PASS\n'
