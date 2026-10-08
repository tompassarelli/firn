#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  private-desktop.sh start [--port PORT] [--resolution WIDTHxHEIGHT] [--render-node PATH] [--seconds SECONDS] [-- COMMAND ARG...]
  private-desktop.sh control RUN_DIRECTORY VNC_ACTION...
  private-desktop.sh type RUN_DIRECTORY < TEXT
  private-desktop.sh capture RUN_DIRECTORY ABSOLUTE_PNG_PATH

Start a private GPU desktop. Ctrl-C ends the session. Default resolution:
2560x1440. VNC listens only on localhost. Default lifetime: until stopped.
Use --seconds to set an optional deadline.
Type reads text only from stdin and sends it to the focused window with US-layout
Shift handling; it refuses any character outside that layout before typing.
Live run directories use /run/user/UID; ended-session logs move to the user's
state directory. Runtime files are removed on exit and after a crashed run.
VNC tools share one Python environment in the user's disk cache.
The shared machine-capacity helper bounds CPU and memory; an existing helper
scope is reused. Do not start two clients sharing one mutable Wine prefix.
EOF
}
die() { printf 'private-desktop: %s\n' "$*" >&2; exit 1; }
self=$(realpath -- "$0")
action=${1:---help}
case "$action" in
    -h|--help|help) usage; exit 0 ;;
    control|capture|type)
        [[ $# -ge 3 || ( "$action" == type && $# == 2 ) ]] || die 'a run directory and action/path are required'
        run=$(realpath -- "$2")
        shift 2
        [[ -O "$run" && -f "$run/active" ]] || die 'run is not active or not owned by this user'
        wayland_display=$(cat "$run/wayland-display")
        [[ -n "$wayland_display" && "$wayland_display" != */* && -S "$run/runtime/$wayland_display" ]] || die 'private Wayland socket is unavailable'
        if [[ "$action" == capture ]]; then
            [[ $# == 1 && "$1" == /* ]] || die 'capture needs one absolute output path'
            output=$1
            [[ ! -d "$output" ]] || die 'capture output must be a file'
            if [[ -f "$run/grim" ]]; then
                grim=$(cat "$run/grim")
            else
                grim=$(command -v grim) || die 'grim is required on PATH for this retained session'
            fi
            [[ "$grim" == /* && -x "$grim" ]] || die 'capture executable is unavailable'
            umask 077
            temporary=$(mktemp -- "${output}.XXXXXX")
            trap 'rm -f -- "$temporary"' EXIT
            trap 'exit 130' INT
            trap 'exit 143' TERM
            timeout --kill-after=1s 8s env -u WAYLAND_SOCKET \
                XDG_RUNTIME_DIR="$run/runtime" WAYLAND_DISPLAY="$wayland_display" \
                "$grim" -t png "$temporary" || die 'native capture failed; output was not replaced'
            [[ -s "$temporary" ]] || die 'native capture was empty; output was not replaced'
            [[ -f "$run/active" ]] || die 'run ended during capture; output was not replaced'
            mv -fT -- "$temporary" "$output"
            exit 0
        fi
        port=$(cat "$run/port")
        [[ "$port" =~ ^[0-9]+$ ]] || die 'invalid run port'
        if [[ "$action" == type ]]; then
            [[ $# == 0 ]] || die 'type reads its text from stdin only'
            exec "$run/venv/bin/python" "$(dirname -- "$self")/private-desktop-type.py" "$port"
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
if ! [[ "$port" =~ ^[1-9][0-9]{3,4}$ ]] || ((port > 65535)); then die 'port must be between 1024 and 65535'; fi
((port >= 1024)) || die 'port must be between 1024 and 65535'
[[ -z "$seconds" || "$seconds" =~ ^[1-9][0-9]*$ ]] || die 'seconds must be a positive integer'
[[ "$resolution" =~ ^[1-9][0-9]{2,4}x[1-9][0-9]{2,4}$ ]] || die 'resolution must look like 2560x1440'
[[ "$render_node" == /dev/dri/renderD* && -r "$render_node" ]] || die "GPU render node is unavailable: $render_node"

# An actual helper cgroup, not an inherited environment marker, proves containment.
if ! grep -Eq '/agent-capacity-[0-9a-f]+\.scope(/|$)' /proc/self/cgroup; then
    if ! command -v bun >/dev/null; then
        exec nix shell nixpkgs#bun --command bash "$self" start "${original_args[@]}"
    fi
    capacity_skill=$(dirname -- "$(agents path machine-capacity)")
    lifetime=(session)
    [[ -z "$seconds" ]] || lifetime=(run --timeout-seconds "$seconds")
    exec bun "$capacity_skill/scripts/machine-capacity.mjs" "${lifetime[@]}" --class heavy \
        --owner "private-desktop:$$" -- bash "$self" start "${original_args[@]}"
fi

for executable in labwc wayvnc wlr-randr grim uv python3 glxinfo setsid flock dbus-run-session; do
    if ! command -v "$executable" >/dev/null; then
        exec nix shell nixpkgs#labwc nixpkgs#wayvnc nixpkgs#wlr-randr nixpkgs#uv nixpkgs#python3 \
            nixpkgs#mesa-demos nixpkgs#util-linux nixpkgs#grim nixpkgs#dbus \
            --command bash "$self" start "${original_args[@]}"
    fi
done
umask 077
cache=${XDG_CACHE_HOME:-$HOME/.cache}/private-desktop
mkdir -p -- "$cache"
python_path=$(realpath -- "$(command -v python3)")
python_id=$(printf '%s' "$python_path" | sha256sum | cut -c1-16)
venv="$cache/vncdotool-1.4.2-$python_id"
# Parallel desktops share dependencies, but installation must finish before use.
exec 8>"$cache/install.lock"
flock -x 8
if [[ ! -x "$venv/bin/vncdo" ]]; then
    [[ -x "$venv/bin/python" ]] || uv venv --python "$python_path" "$venv"
    uv pip install --python "$venv/bin/python" vncdotool==1.4.2
fi
flock -u 8
exec 8>&-
runtime_root="/run/user/$(id -u)"
archive_root=${XDG_STATE_HOME:-$HOME/.local/state}/private-desktop
mkdir -p -- "$archive_root"
archive_run() {
    local stopped=$1
    [[ "$stopped" == "$runtime_root/private-desktop."* && -d "$stopped" && -O "$stopped" && -f "$stopped/lifecycle-owned" ]] || return
    rm -f -- "$stopped/active"
    rm -rf -- "$stopped/runtime"
    mv -T -- "$stopped" "$archive_root/$(basename -- "$stopped")"
}
# A lock retained by the session's processes keeps crash recovery off live peers.
while IFS= read -r -d '' stale; do
    [[ -O "$stale" && -f "$stale/lifecycle-owned" && -f "$stale/lifecycle.lock" ]] || continue
    exec 6<"$stale/lifecycle.lock" || continue
    if flock -n -x 6; then archive_run "$stale"; fi
    exec 6>&-
done < <(python3 - "$runtime_root" <<'PY'
import os, sys
for entry in os.scandir(sys.argv[1]):
    if entry.name.startswith("private-desktop.") and entry.is_dir(follow_symlinks=False):
        sys.stdout.buffer.write(os.fsencode(entry.path) + b"\0")
PY
)
run=$(mktemp -d "$runtime_root/private-desktop.XXXXXXXX")
desktop_pid='' vnc_pid='' client_pid='' timer_pid=''
exec 7>"$run/lifecycle.lock"
flock -x 7
touch "$run/lifecycle-owned"
printf '%s\n' "$$" > "$run/launcher-pid"
cleanup() {
    trap - EXIT INT TERM
    rm -f -- "$run/active"
    for pid in "$client_pid" "$vnc_pid" "$desktop_pid"; do
        [[ -z "$pid" ]] || kill -TERM -- "-$pid" 2>/dev/null || true
    done
    [[ -z "$timer_pid" ]] || kill -TERM "$timer_pid" 2>/dev/null || true
    wait 2>/dev/null || true
    archive_run "$run"
    printf 'Session ended; logs: %s/%s\n' "$archive_root" "$(basename -- "$run")"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$run/runtime" "$run/config"
ln -s -- "$venv" "$run/venv"
command -v grim > "$run/grim"
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
# Serialize discovery through actual VNC binding; parallel starts must not
# release a candidate port before their listener owns it.
exec 9>"$runtime_root/private-desktop-port.lock"
flock -x 9
if ((port_was_explicit)); then
    port_free "$port" || die "localhost port $port is already occupied"
else
    while ! port_free "$port"; do
        ((port < 65535)) || die 'no available localhost VNC port'
        ((port += 1))
    done
fi
printf '%s\n' "$port" > "$run/port"
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
    WLR_HEADLESS_OUTPUTS=1 setsid labwc -C "$run/config" -s "$run/startup.sh" > "$run/labwc.log" 2>&1 9>&- &
desktop_pid=$!
for ((attempt=0; attempt<100; attempt++)); do
    [[ ! -f "$run/ready" ]] || break
    kill -0 "$desktop_pid" 2>/dev/null || die "desktop exited; see $run/labwc.log"
    sleep 0.1
done
[[ -f "$run/ready" ]] || die "desktop startup timed out; see $run/labwc.log"
DISPLAY=$(cat "$run/display")
WAYLAND_DISPLAY=$(cat "$run/wayland-display")
export DISPLAY WAYLAND_DISPLAY
[[ -n "$DISPLAY" && -n "$WAYLAND_DISPLAY" ]] || die 'desktop did not provide its displays'
if [[ -s "$run/xauthority" && -n "$(cat "$run/xauthority")" ]]; then
    XAUTHORITY=$(cat "$run/xauthority")
    export XAUTHORITY
fi
output=$(wlr-randr | awk '/^HEADLESS-[0-9]+ / {print $1; exit}')
[[ -n "$output" ]] || die 'could not find labwc headless output'
wlr-randr --output "$output" --custom-mode "${resolution}@60Hz" || die "could not set private output to $resolution"
printf 'address=127.0.0.1\nport=%s\nenable_auth=false\n' "$port" > "$run/wayvnc.conf"
setsid wayvnc -C "$run/wayvnc.conf" > "$run/wayvnc.log" 2>&1 9>&- &
vnc_pid=$!
vnc_ready=0
for ((attempt=0; attempt<100; attempt++)); do
    kill -0 "$vnc_pid" 2>/dev/null || die "VNC exited; see $run/wayvnc.log"
    if ! port_free "$port"; then vnc_ready=1; break; fi
    sleep 0.1
done
((vnc_ready)) || die "VNC listener startup timed out; see $run/wayvnc.log"
flock -u 9
exec 9>&-
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
    setsid -- dbus-run-session -- "$@" &
    client_pid=$!
    session_pids+=("$client_pid")
fi
wait -n "${session_pids[@]}"
