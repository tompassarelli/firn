#!/usr/bin/env bash
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
selector=${NORTH_COORD_SELECTOR_TEST_BINARY:-$here/north-coord-selector}
source_module=$here/default.bnix
generated_module=$here/default.nix

for command in haproxy socat python3 timeout; do
  command -v "$command" >/dev/null || {
    printf 'missing test dependency: %s\n' "$command" >&2
    exit 2
  }
done

grep -Fq '"  timeout client 1h"' "$source_module"
grep -Fq '"  timeout server 1h"' "$source_module"
grep -Fq 'timeout client 1h' "$generated_module"
grep -Fq 'timeout server 1h' "$generated_module"
grep -Fq '(s "export NORTH_COORD_SELECTOR_OWNER=" username)' \
  "$source_module"
grep -Fq '"export NORTH_COORD_SELECTOR_GROUP=users"' "$source_module"
# shellcheck disable=SC2016
grep -Fq 'export NORTH_COORD_SELECTOR_OWNER=${username}' \
  "$generated_module"
grep -Fq 'export NORTH_COORD_SELECTOR_GROUP=users' "$generated_module"
if rg -n 'timeout (client|server) 30s' \
  "$source_module" "$generated_module"; then
  printf 'proxy still expires idle North subscriptions after 30 seconds\n' >&2
  exit 1
fi

scratch=$(mktemp -d)
trap '[[ ${NORTH_COORD_TEST_KEEP:-0} -eq 1 ]] || rm -rf -- "$scratch"' EXIT

admin_socket=$scratch/admin.sock
route_map=$scratch/route.map
selector_lock=$scratch/selector.lock
transaction=$scratch/transaction
config=$scratch/haproxy.cfg
promotion_log=$scratch/promotion.log
backend_log=$scratch/backend.log
public_ports=$scratch/public.ports
backend_ports=$scratch/backend.ports
proxy_pid_file=$scratch/haproxy.pid
restart_gate=$scratch/restart.allow
admin_log=$scratch/admin.log
admin_fail=$scratch/admin.fail

printf 'active blue\n' >"$route_map"
chmod 0666 "$route_map"

python3 - "$backend_ports" "$backend_log" <<'PY' &
import socket
import sys
import threading

ports_path, log_path = sys.argv[1:]
listeners = {}
for name in ("coord-blue", "coord-green", "telemetry-blue", "telemetry-green"):
    sock = socket.socket()
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    sock.listen(128)
    listeners[name] = sock
with open(ports_path, "w") as out:
    for name, sock in listeners.items():
        print(name, sock.getsockname()[1], file=out)

def serve(name, listener):
    while True:
        conn, _ = listener.accept()
        try:
            with conn:
                data = conn.recv(4096)
                if data.startswith(b"hold"):
                    conn.sendall((name + ":held\n").encode())
                    data = conn.recv(4096)
                if data:
                    conn.sendall(
                        (name + ":" + data.decode(errors="replace")).encode()
                    )
                with open(log_path, "a") as log:
                    print(name, repr(data), file=log)
        except (BrokenPipeError, ConnectionResetError):
            with open(log_path, "a") as log:
                print(name, "session-reset", file=log)

for item in listeners.items():
    threading.Thread(target=serve, args=item, daemon=True).start()
threading.Event().wait()
PY
backend_pid=$!

for _ in $(seq 1 100); do
  [[ -s "$backend_ports" ]] && break
  sleep 0.02
done
[[ -s "$backend_ports" ]]

port_of() {
  awk -v name="$1" '$1 == name { print $2 }' "$backend_ports"
}

coord_blue=$(port_of coord-blue)
coord_green=$(port_of coord-green)
telemetry_blue=$(port_of telemetry-blue)
telemetry_green=$(port_of telemetry-green)

python3 - "$public_ports" "$config" "$admin_socket" "$route_map" \
  "$coord_blue" "$coord_green" "$telemetry_blue" "$telemetry_green" \
  "$proxy_pid_file" "$restart_gate" <<'PY' &
import os
import signal
import socket
import subprocess
import sys
import time

(ports_path, config_path, admin_socket, route_map,
 coord_blue, coord_green, telemetry_blue, telemetry_green,
 pid_path, restart_gate) = sys.argv[1:]

listeners = []
for _ in range(2):
    sock = socket.socket()
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    sock.listen(4096)
    listeners.append(sock)

with open(ports_path, "w") as out:
    for sock in listeners:
        print(sock.getsockname()[1], file=out)

def write_config():
    coord_public, telemetry_public = [s.getsockname()[1] for s in listeners]
    with open(config_path, "w") as out:
        out.write(f"""global
  stats socket {admin_socket} mode 600 level admin
  maxconn 4096

defaults
  mode tcp
  timeout connect 2s
  timeout client 1h
  timeout server 1h

frontend north-public
  bind fd@{listeners[0].fileno()}
  bind fd@{listeners[1].fileno()}
  acl is_coord dst_port {coord_public}
  acl route_blue str(active),map({route_map}) -m str blue
  use_backend coord-blue if is_coord route_blue
  use_backend coord-green if is_coord !route_blue
  use_backend telemetry-blue if !is_coord route_blue
  default_backend telemetry-green

backend coord-blue
  server only 127.0.0.1:{coord_blue}
backend coord-green
  server only 127.0.0.1:{coord_green}
backend telemetry-blue
  server only 127.0.0.1:{telemetry_blue}
backend telemetry-green
  server only 127.0.0.1:{telemetry_green}
""")

write_config()
child = None
restart_requested = False

def request_restart(_signum, _frame):
    global restart_requested
    restart_requested = True
    if child is not None:
        child.terminate()

signal.signal(signal.SIGUSR1, request_restart)

while True:
    restart_requested = False
    child = subprocess.Popen(
        ["haproxy", "-db", "-f", config_path],
        pass_fds=tuple(s.fileno() for s in listeners),
    )
    with open(pid_path, "w") as out:
        print(child.pid, file=out)
    status = child.wait()
    if restart_requested:
        while not os.path.exists(restart_gate):
            time.sleep(0.01)
        os.unlink(restart_gate)
        continue
    sys.exit(status)
PY
proxy_parent_pid=$!

cleanup_processes() {
  kill "$proxy_parent_pid" "$backend_pid" 2>/dev/null || true
  wait "$proxy_parent_pid" "$backend_pid" 2>/dev/null || true
}
trap 'cleanup_processes; [[ ${NORTH_COORD_TEST_KEEP:-0} -eq 1 ]] || rm -rf -- "$scratch"' EXIT

for _ in $(seq 1 100); do
  [[ -S "$admin_socket" && -s "$public_ports" && -s "$proxy_pid_file" ]] && break
  sleep 0.02
done
[[ -S "$admin_socket" && -s "$public_ports" && -s "$proxy_pid_file" ]]

coord_public=$(sed -n '1p' "$public_ports")
telemetry_public=$(sed -n '2p' "$public_ports")

export NORTH_COORD_SELECTOR_SOCKET=$admin_socket
export NORTH_COORD_SELECTOR_MAP=$route_map
export NORTH_COORD_SELECTOR_FRONTEND=north-public
export NORTH_COORD_SELECTOR_LOCK=$selector_lock
export NORTH_COORD_SELECTOR_OWNER
NORTH_COORD_SELECTOR_OWNER=$(id -un)
export NORTH_COORD_SELECTOR_GROUP
NORTH_COORD_SELECTOR_GROUP=$(id -gn)
export NORTH_COORD_SELECTOR_TRANSACTION=$transaction
export NORTH_COORD_SELECTOR_DRAIN_GRACE_MS=250
export NORTH_COORD_SELECTOR_DRAIN_TIMEOUT=1

real_socat=$(command -v socat)
cat >"$scratch/admin-client" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
command=$(cat)
printf '%s\n' "$command" >>"$NORTH_COORD_TEST_ADMIN_LOG"
if [[ -e "$NORTH_COORD_TEST_ADMIN_FAIL" &&
      "$command" == "shutdown sessions server "* ]]; then
  exit 17
fi
printf '%s\n' "$command" |
  "$NORTH_COORD_TEST_REAL_SOCAT" "$@"
SH
chmod 0700 "$scratch/admin-client"
export NORTH_COORD_SELECTOR_ADMIN_CLIENT=$scratch/admin-client
export NORTH_COORD_TEST_ADMIN_LOG=$admin_log
export NORTH_COORD_TEST_ADMIN_FAIL=$admin_fail
export NORTH_COORD_TEST_REAL_SOCAT=$real_socat

probe() {
  local port=$1 payload=$2
  python3 - "$port" "$payload" <<'PY'
import socket
import sys
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=5) as conn:
    conn.sendall(sys.argv[2].encode())
    print(conn.recv(4096).decode(), end="")
PY
}

cat >"$scratch/promote" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'promote %s %s %s\n' "$1" "$2" "$3" >>"$NORTH_COORD_TEST_PROMOTION_LOG"
[[ "${NORTH_COORD_TEST_PROMOTION_FAIL:-0}" -eq 0 ]]
SH
cat >"$scratch/rollback" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'rollback %s %s %s\n' "$1" "$2" "$3" >>"$NORTH_COORD_TEST_PROMOTION_LOG"
[[ "${NORTH_COORD_TEST_ROLLBACK_FAIL:-0}" -eq 0 ]]
SH
cat >"$scratch/verify" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'verify %s\n' "$1" >>"$NORTH_COORD_TEST_PROMOTION_LOG"
[[ "${NORTH_COORD_TEST_VERIFY_FAIL:-0}" -eq 0 ]]
SH
chmod 0700 "$scratch/promote" "$scratch/rollback" "$scratch/verify"
export NORTH_COORD_SELECTOR_PROMOTE_COMMAND=$scratch/promote
export NORTH_COORD_SELECTOR_ROLLBACK_COMMAND=$scratch/rollback
export NORTH_COORD_SELECTOR_VERIFY_COMMAND=$scratch/verify
export NORTH_COORD_TEST_PROMOTION_LOG=$promotion_log

# The systemd-like socket parent keeps both public listeners open while the
# proxy starts. With no transaction, HAProxy may immediately serve the durable
# route; transaction recovery is a separate ExecStartPre gate.
printf 'show stat\n' | socat -t 3 - "UNIX-CONNECT:$admin_socket" >"$scratch/show-stat.initial"
"$selector" prestart
"$selector" recover
grep -Fxq frontend=OPEN < <("$selector" status)
[[ $(probe "$coord_public" one) == coord-blue:one ]]
[[ $(probe "$telemetry_public" one) == telemetry-blue:one ]]

# One existing connection is allowed to drain on the old generation. The
# switch waits for it while public sockets remain owned by the parent.
python3 - "$coord_public" "$scratch/held.ready" <<'PY' &
import socket
import sys
import time
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=5) as conn:
    conn.sendall(b"hold")
    response = conn.recv(4096)
    assert response == b"coord-blue:held\n", response
    open(sys.argv[2], "w").close()
    time.sleep(0.05)
    conn.sendall(b"drained")
    response = conn.recv(4096)
    assert response == b"coord-blue:drained", response
PY
held_pid=$!
for _ in $(seq 1 100); do
  [[ -e "$scratch/held.ready" ]] && break
  sleep 0.01
done
[[ -e "$scratch/held.ready" ]]

# Continuous clients span HOLD+SWAP+RESUME. Every connection must complete;
# none may observe ECONNREFUSED or a cross-origin mixed target after resume.
for port in "$coord_public" "$telemetry_public"; do
  python3 - "$port" "$scratch/results.$port" <<'PY' &
import socket
import sys
import time
port = int(sys.argv[1])
with open(sys.argv[2], "w") as out:
    for i in range(20):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=5) as conn:
                conn.sendall(f"loop-{i}\n".encode())
                response = conn.recv(4096).decode().strip()
                print("ok " + response, file=out)
        except Exception as error:
            print("error " + repr(error), file=out)
        time.sleep(0.005)
PY
  eval "loop_${port}_pid=$!"
done

"$selector" switch green
coord_loop_var=loop_${coord_public}_pid
telemetry_loop_var=loop_${telemetry_public}_pid
wait "$held_pid" "${!coord_loop_var}" "${!telemetry_loop_var}"
grep -Fxq durable=green < <("$selector" status)
[[ $(probe "$coord_public" two) == coord-green:two ]]
[[ $(probe "$telemetry_public" two) == telemetry-green:two ]]
if rg -n '^error ' "$scratch"/results.*; then
  printf 'a continuous client observed a refused or failed connection\n' >&2
  exit 1
fi
grep -Fxq 'active green' "$route_map"
route_metadata=$(stat -c '%U:%G %a' "$route_map")
[[ "$route_metadata" == "$NORTH_COORD_SELECTOR_OWNER:$NORTH_COORD_SELECTOR_GROUP 600" ]]
grep -Fq 'promote blue green' "$promotion_log"

# Long-lived coordination and telemetry subscriptions cannot drain
# voluntarily. The selector closes only the old green backend sessions after
# its grace period. Both clients reconnect through the still-bound public
# sockets and are served by blue after RESUME.
python3 - "$coord_public" "$scratch/persistent.coord.ready" \
  "$scratch/persistent.coord.result" coord-green coord-blue <<'PY' &
import socket
import sys

port, ready_path, result_path, old_backend, new_backend = sys.argv[1:]
with socket.create_connection(("127.0.0.1", int(port)), timeout=5) as conn:
    conn.sendall(b"hold")
    response = conn.recv(4096)
    assert response == (old_backend + ":held\n").encode(), response
    open(ready_path, "w").close()
    conn.settimeout(5)
    try:
        closed = conn.recv(4096)
    except ConnectionResetError:
        closed = b""
    assert closed == b"", closed
with socket.create_connection(("127.0.0.1", int(port)), timeout=5) as conn:
    conn.settimeout(5)
    conn.sendall(b"reconnected")
    response = conn.recv(4096)
    assert response == (new_backend + ":reconnected").encode(), response
with open(result_path, "w") as out:
    out.write(response.decode())
PY
persistent_coord_pid=$!
python3 - "$telemetry_public" "$scratch/persistent.telemetry.ready" \
  "$scratch/persistent.telemetry.result" telemetry-green telemetry-blue <<'PY' &
import socket
import sys

port, ready_path, result_path, old_backend, new_backend = sys.argv[1:]
with socket.create_connection(("127.0.0.1", int(port)), timeout=5) as conn:
    conn.sendall(b"hold")
    response = conn.recv(4096)
    assert response == (old_backend + ":held\n").encode(), response
    open(ready_path, "w").close()
    conn.settimeout(5)
    try:
        closed = conn.recv(4096)
    except ConnectionResetError:
        closed = b""
    assert closed == b"", closed
with socket.create_connection(("127.0.0.1", int(port)), timeout=5) as conn:
    conn.settimeout(5)
    conn.sendall(b"reconnected")
    response = conn.recv(4096)
    assert response == (new_backend + ":reconnected").encode(), response
with open(result_path, "w") as out:
    out.write(response.decode())
PY
persistent_telemetry_pid=$!
for _ in $(seq 1 100); do
  [[ -e "$scratch/persistent.coord.ready" &&
     -e "$scratch/persistent.telemetry.ready" ]] && break
  sleep 0.01
done
[[ -e "$scratch/persistent.coord.ready" ]]
[[ -e "$scratch/persistent.telemetry.ready" ]]

"$selector" switch blue
wait "$persistent_coord_pid" "$persistent_telemetry_pid"
grep -Fxq 'coord-blue:reconnected' "$scratch/persistent.coord.result"
grep -Fxq 'telemetry-blue:reconnected' \
  "$scratch/persistent.telemetry.result"
grep -Fxq 'shutdown sessions server coord-green/only' "$admin_log"
grep -Fxq 'shutdown sessions server telemetry-green/only' "$admin_log"
if rg -n 'shutdown sessions server (coord|telemetry)-blue/only' \
  "$admin_log"; then
  printf 'persistent handoff closed a target-generation session\n' >&2
  exit 1
fi
grep -Fxq 'active blue' "$route_map"
grep -Fq 'promote green blue' "$promotion_log"

# A forced-close command failure occurs before the authority gate. It must
# automatically restore the old blue route, remove the transaction, and
# RESUME. The established old session remains usable.
python3 - "$coord_public" "$scratch/force-fail.ready" \
  "$scratch/force-fail.release" "$scratch/force-fail.result" <<'PY' &
import os
import socket
import sys
import time

port, ready_path, release_path, result_path = sys.argv[1:]
with socket.create_connection(("127.0.0.1", int(port)), timeout=5) as conn:
    conn.sendall(b"hold")
    response = conn.recv(4096)
    assert response == b"coord-blue:held\n", response
    open(ready_path, "w").close()
    while not os.path.exists(release_path):
        time.sleep(0.01)
    conn.sendall(b"survived")
    response = conn.recv(4096)
    assert response == b"coord-blue:survived", response
with open(result_path, "w") as out:
    out.write(response.decode())
PY
force_fail_client_pid=$!
for _ in $(seq 1 100); do
  [[ -e "$scratch/force-fail.ready" ]] && break
  sleep 0.01
done
[[ -e "$scratch/force-fail.ready" ]]
: >"$admin_fail"
if "$selector" switch green \
  >"$scratch/force-fail.out" 2>"$scratch/force-fail.err"; then
  printf 'failed session close unexpectedly switched the route\n' >&2
  exit 1
fi
rm -f -- "$admin_fail"
[[ ! -e "$transaction" ]]
grep -Fxq 'active blue' "$route_map"
grep -Fxq frontend=OPEN < <("$selector" status)
rg -q 'pre-gate handoff failed; restored blue' "$scratch/force-fail.err"
: >"$scratch/force-fail.release"
wait "$force_fail_client_pid"
grep -Fxq 'coord-blue:survived' "$scratch/force-fail.result"

# A failed promotion never changes the map and always resumes the old pair.
export NORTH_COORD_TEST_PROMOTION_FAIL=1
if "$selector" switch green >"$scratch/fail.out" 2>"$scratch/fail.err"; then
  printf 'failed promotion unexpectedly switched the route\n' >&2
  exit 1
fi
unset NORTH_COORD_TEST_PROMOTION_FAIL
grep -Fxq 'active blue' "$route_map"
grep -Fq 'rollback green blue' "$promotion_log"
[[ $(probe "$coord_public" three) == coord-blue:three ]]
[[ $(probe "$telemetry_public" three) == telemetry-blue:three ]]

# A failed rollback is fail-closed: both public sockets remain bound and
# connects queue instead of refusing. The prestart gate reconciles authority
# and the durable map before a replacement proxy could receive those sockets.
export NORTH_COORD_TEST_PROMOTION_FAIL=1
export NORTH_COORD_TEST_ROLLBACK_FAIL=1
if "$selector" switch green >"$scratch/closed.out" 2>"$scratch/closed.err"; then
  printf 'failed rollback unexpectedly completed\n' >&2
  exit 1
fi
unset NORTH_COORD_TEST_PROMOTION_FAIL NORTH_COORD_TEST_ROLLBACK_FAIL
held_status=$("$selector" status || true)
rg -q '^frontend=(STOP|PAUSED)$' <<<"$held_status"
timeout 0.2s python3 - "$coord_public" <<'PY' && {
import socket
import sys
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=1) as conn:
    conn.sendall(b"queued")
    conn.recv(4096)
PY
  printf 'held connection unexpectedly completed\n' >&2
  exit 1
}
"$selector" prestart
[[ ! -e "$transaction" ]]
grep -Fxq 'active blue' "$route_map"
# prestart never opens a held live proxy; systemd invokes it before ExecStart.
held_status=$("$selector" status || true)
rg -q '^frontend=(STOP|PAUSED)$' <<<"$held_status"
"$selector" recover
[[ $(probe "$coord_public" recovered) == coord-blue:recovered ]]
[[ $(probe "$telemetry_public" recovered) == telemetry-blue:recovered ]]

# Restart HAProxy while the systemd-like parent retains both public listeners.
# A connection opened during the proxy gap is accepted from the same permanent
# socket after the replacement starts; there is no bind/refusal window.
old_proxy_pid=$(<"$proxy_pid_file")
kill -USR1 "$proxy_parent_pid"
waited=0
while kill -0 "$old_proxy_pid" 2>/dev/null && (( waited < 100 )); do
  sleep 0.01
  waited=$((waited + 1))
done
rm -f -- "$admin_socket"
python3 - "$coord_public" "$scratch/restart-result" <<'PY' &
import socket
import sys
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=5) as conn:
    conn.sendall(b"restart")
    with open(sys.argv[2], "w") as out:
        out.write(conn.recv(4096).decode())
PY
restart_client_pid=$!
sleep 0.1
kill -0 "$restart_client_pid"
: >"$restart_gate"
for _ in $(seq 1 100); do
  [[ -S "$admin_socket" ]] && break
  sleep 0.02
done
[[ -S "$admin_socket" ]]
"$selector" recover
wait "$restart_client_pid"
grep -Fxq 'coord-blue:restart' "$scratch/restart-result"

if [[ "${NORTH_COORD_SELECTOR_SKIP_POWER_CHECKS:-0}" -eq 0 ]]; then
  missing_telemetry_close=$scratch/selector.missing-telemetry-close
  # shellcheck disable=SC2016
  sed '/cli_mutation "shutdown sessions server telemetry-\$old\/only"/d' \
    "$selector" >"$missing_telemetry_close"
  chmod 0700 "$missing_telemetry_close"
  if NORTH_COORD_SELECTOR_TEST_BINARY=$missing_telemetry_close \
     NORTH_COORD_SELECTOR_SKIP_POWER_CHECKS=1 \
     bash "$0" >"$scratch/power-close.out" 2>"$scratch/power-close.err"; then
    printf 'selector test passed without closing old telemetry sessions\n' >&2
    exit 1
  fi

  missing_pregate_rollback=$scratch/selector.missing-pregate-rollback
  # shellcheck disable=SC2016
  sed 's/    rollback_to "$old" "$target" 0 ||/    false ||/' \
    "$selector" >"$missing_pregate_rollback"
  chmod 0700 "$missing_pregate_rollback"
  if NORTH_COORD_SELECTOR_TEST_BINARY=$missing_pregate_rollback \
     NORTH_COORD_SELECTOR_SKIP_POWER_CHECKS=1 \
     bash "$0" >"$scratch/power-rollback.out" \
       2>"$scratch/power-rollback.err"; then
    printf 'selector test passed without pre-gate automatic rollback\n' >&2
    exit 1
  fi
fi

printf 'ok: permanent inherited sockets, pair-atomic routing, drain, rollback, and recovery are zero-refusal\n'
