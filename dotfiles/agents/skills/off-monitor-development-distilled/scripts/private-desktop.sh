#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  private-desktop.sh start [--port PORT] [--resolution WIDTHxHEIGHT] [--render-node PATH] [--seconds SECONDS] [-- COMMAND ARG...]
  private-desktop.sh control RUN_DIRECTORY VNC_ACTION...
  private-desktop.sh capture RUN_DIRECTORY ABSOLUTE_PNG_PATH

Start a private GPU desktop. Ctrl-C ends the session. Default resolution:
2560x1440. VNC listens only on localhost. Default lifetime: until stopped.
Use --seconds to set an optional deadline.
Run directories and logs remain under /run/user/UID until logout.
The shared machine-capacity helper bounds CPU and memory; an existing helper
scope is reused. Do not start two clients sharing one mutable Wine prefix.
EOF
}
die() { printf 'private-desktop: %s\n' "$*" >&2; exit 1; }
self=$(realpath -- "$0")
action=${1:---help}
case "$action" in
    -h|--help|help) usage; exit 0 ;;
    control|capture)
        [[ $# -ge 3 ]] || die 'a run directory and action/path are required'
        run=$(realpath -- "$2")
        shift 2
        [[ -O "$run" && -f "$run/active" && -S "$run/runtime/wayland-0" ]] || die 'run is not active or not owned by this user'
        port=$(cat "$run/port")
        [[ "$port" =~ ^[0-9]+$ ]] || die 'invalid run port'
        if [[ "$action" == capture ]]; then
            [[ $# == 1 && "$1" == /* ]] || die 'capture needs one absolute output path'
            set -- capture "$1"
        fi
        exec "$run/venv/bin/vncdo" -s "127.0.0.1::$port" -t 8 "$@"
        ;;
    start) shift ;;
    *) die "unknown action: $action" ;;
esac

original_args=("$@")
port=5999
port_was_explicit=0
resolution=2560x1440
render_node=${WLR_RENDER_DRM_DEVICE:-/dev/dri/renderD128}
seconds=
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) [[ $# -ge 2 ]] || die '--port needs a value'; port=$2; port_was_explicit=1; shift 2 ;;
        --resolution) [[ $# -ge 2 ]] || die '--resolution needs a value'; resolution=$2; shift 2 ;;
        --render-node) [[ $# -ge 2 ]] || die '--render-node needs a value'; render_node=$2; shift 2 ;;
        --seconds) [[ $# -ge 2 ]] || die '--seconds needs a value'; seconds=$2; shift 2 ;;
        --) shift; break ;;
        *) die "unknown start option: $1" ;;
    esac
done
[[ "$port" =~ ^[1-9][0-9]{3,4}$ ]] && ((port <= 65535)) || die 'port must be between 1024 and 65535'
((port >= 1024)) || die 'port must be between 1024 and 65535'
[[ -z "$seconds" || "$seconds" =~ ^[1-9][0-9]*$ ]] || die 'seconds must be a positive integer'
[[ "$resolution" =~ ^[1-9][0-9]{2,4}x[1-9][0-9]{2,4}$ ]] || die 'resolution must look like 2560x1440'
[[ "$render_node" == /dev/dri/renderD* && -r "$render_node" ]] || die "GPU render node is unavailable: $render_node"

# An actual helper cgroup, not an inherited environment marker, proves containment.
if ! grep -Eq '/agent-capacity-[0-9a-f]+\.scope(/|$)' /proc/self/cgroup; then
    if ! command -v bun >/dev/null; then
        exec nix shell nixpkgs#bun --command bash "$self" start "${original_args[@]}"
    fi
    capacity_skill=$(dirname -- "$(agents path machine-capacity-distilled)")
    lifetime=(session)
    [[ -z "$seconds" ]] || lifetime=(run --timeout-seconds "$seconds")
    exec bun "$capacity_skill/scripts/machine-capacity.mjs" "${lifetime[@]}" --class heavy \
        --owner "private-desktop:$$" -- bash "$self" start "${original_args[@]}"
fi

for executable in labwc wayvnc wlr-randr uv python3 glxinfo setsid; do
    if ! command -v "$executable" >/dev/null; then
        exec nix shell nixpkgs#labwc nixpkgs#wayvnc nixpkgs#wlr-randr nixpkgs#uv nixpkgs#python3 \
            nixpkgs#mesa-demos nixpkgs#util-linux \
            --command bash "$self" start "${original_args[@]}"
    fi
done
umask 077
run=$(mktemp -d "/run/user/$(id -u)/private-desktop.XXXXXXXX")
mkdir "$run/runtime" "$run/config"
port_free() {
    python3 - "$1" <<'PY'
import socket, sys
s = socket.socket()
try:
    s.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
finally:
    s.close()
PY
}
if ((port_was_explicit)); then
    port_free "$port" || die "localhost port $port is already occupied"
else
    while ! port_free "$port"; do
        ((port < 65535)) || die 'no available localhost VNC port'
        ((port += 1))
    done
fi
printf '%s\n' "$port" > "$run/port"
desktop_pid= vnc_pid= client_pid= timer_pid=
cleanup() {
    trap - EXIT INT TERM
    rm -f -- "$run/active"
    for pid in "$client_pid" "$vnc_pid" "$desktop_pid"; do
        [[ -z "$pid" ]] || kill -TERM -- "-$pid" 2>/dev/null || true
    done
    [[ -z "$timer_pid" ]] || kill -TERM "$timer_pid" 2>/dev/null || true
    wait 2>/dev/null || true
    printf 'Session ended; logs: %s\n' "$run"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
uv venv --python python3 "$run/venv"
uv pip install --python "$run/venv/bin/python" vncdotool==1.4.2
cat > "$run/startup.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$DISPLAY" > "$PRIVATE_DESKTOP_RUN/display"
printf '%s\n' "$WAYLAND_DISPLAY" > "$PRIVATE_DESKTOP_RUN/wayland-display"
printf '%s\n' "${XAUTHORITY-}" > "$PRIVATE_DESKTOP_RUN/xauthority"
touch "$PRIVATE_DESKTOP_RUN/ready"
EOF
chmod 700 "$run/startup.sh"
export PRIVATE_DESKTOP_RUN="$run"
unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET XAUTHORITY
export XDG_RUNTIME_DIR="$run/runtime"
WLR_BACKENDS=headless WLR_RENDERER=gles2 WLR_RENDER_DRM_DEVICE="$render_node" \
    WLR_HEADLESS_OUTPUTS=1 setsid labwc -C "$run/config" -s "$run/startup.sh" > "$run/labwc.log" 2>&1 &
desktop_pid=$!
for ((attempt=0; attempt<100; attempt++)); do
    [[ ! -f "$run/ready" ]] || break
    kill -0 "$desktop_pid" 2>/dev/null || die "desktop exited; see $run/labwc.log"
    sleep 0.1
done
[[ -f "$run/ready" ]] || die "desktop startup timed out; see $run/labwc.log"
export DISPLAY=$(cat "$run/display")
export WAYLAND_DISPLAY=$(cat "$run/wayland-display")
[[ -n "$DISPLAY" && -n "$WAYLAND_DISPLAY" ]] || die 'desktop did not provide its displays'
if [[ -s "$run/xauthority" && -n "$(cat "$run/xauthority")" ]]; then
    export XAUTHORITY=$(cat "$run/xauthority")
fi
output=$(wlr-randr | awk '/^HEADLESS-[0-9]+ / {print $1; exit}')
[[ -n "$output" ]] || die 'could not find labwc headless output'
wlr-randr --output "$output" --custom-mode "${resolution}@60Hz" || die "could not set private output to $resolution"
printf 'address=127.0.0.1\nport=%s\nenable_auth=false\n' "$port" > "$run/wayvnc.conf"
setsid wayvnc -C "$run/wayvnc.conf" > "$run/wayvnc.log" 2>&1 &
vnc_pid=$!
sleep 0.5
kill -0 "$vnc_pid" 2>/dev/null || die "VNC exited; see $run/wayvnc.log"
touch "$run/active"
printf 'Run: %s\nPort: %s\nDISPLAY=%s WAYLAND_DISPLAY=%s XDG_RUNTIME_DIR=%s\n' "$run" "$port" "$DISPLAY" "$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR"
printf 'Control: %q control %q key enter\n' "$self" "$run"
printf 'Capture: %q capture %q /tmp/private-desktop.png\n' "$self" "$run"
printf 'GPU diagnostics: %s/glxinfo.log\n' "$run"
glxinfo -B > "$run/glxinfo.log" 2>&1 || die "GPU query failed; see $run/glxinfo.log"
session_pids=("$desktop_pid" "$vnc_pid")
if [[ -n "$seconds" ]]; then
    sleep "$seconds" &
    timer_pid=$!
    session_pids+=("$timer_pid")
fi
if [[ $# -gt 0 ]]; then
    setsid -- "$@" &
    client_pid=$!
    session_pids+=("$client_pid")
fi
wait -n "${session_pids[@]}"
