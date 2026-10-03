#!/usr/bin/env bash
set -euo pipefail
# Run with python3 on PATH; the socket fixture never controls a desktop.
launcher=$(dirname -- "$(realpath -- "$0")")/private-desktop.sh
fixture=$(mktemp -d)
socket_pid=
cleanup() {
    [[ -z "$socket_pid" ]] || kill "$socket_pid" 2>/dev/null || true
    [[ -z "$socket_pid" ]] || wait "$socket_pid" 2>/dev/null || true
    rm -f -- "$fixture/runtime/wayland-test" "$fixture/active" "$fixture/wayland-display" \
        "$fixture/grim" "$fixture/fake-grim" "$fixture/frame.png"
    rmdir "$fixture/runtime" "$fixture"
}
trap cleanup EXIT
mkdir "$fixture/runtime"
printf 'wayland-test\n' > "$fixture/wayland-display"
touch "$fixture/active"
python3 - "$fixture/runtime/wayland-test" <<'PY' &
import signal, socket, sys
with socket.socket(socket.AF_UNIX) as server:
    server.bind(sys.argv[1])
    server.listen()
    signal.pause()
PY
socket_pid=$!
for ((attempt=0; attempt<100; attempt++)); do
    [[ ! -S "$fixture/runtime/wayland-test" ]] || break
    sleep 0.01
done
[[ -S "$fixture/runtime/wayland-test" ]]
cat > "$fixture/fake-grim" <<'GRIM'
#!/usr/bin/env bash
set -euo pipefail
[[ "$XDG_RUNTIME_DIR" == "$EXPECTED_RUN/runtime" && "$WAYLAND_DISPLAY" == wayland-test && ! -v WAYLAND_SOCKET ]]
[[ "$1" == -t && "$2" == png ]]
case "$CAPTURE_CASE" in
    success) printf 'fresh fixture pixels\n' > "$3" ;;
    partial) printf partial > "$3"; exit 1 ;;
    empty) : ;;
esac
GRIM
chmod +x "$fixture/fake-grim"
printf '%s\n' "$fixture/fake-grim" > "$fixture/grim"
export EXPECTED_RUN="$fixture" WAYLAND_SOCKET=999 XDG_RUNTIME_DIR=/invalid WAYLAND_DISPLAY=wrong
CAPTURE_CASE=success "$launcher" capture "$fixture" "$fixture/frame.png"
[[ $(cat "$fixture/frame.png") == 'fresh fixture pixels' ]]
for failure in partial empty; do
    if CAPTURE_CASE=$failure "$launcher" capture "$fixture" "$fixture/frame.png"; then
        echo "FAIL: $failure capture succeeded" >&2; exit 1
    fi
    [[ $(cat "$fixture/frame.png") == 'fresh fixture pixels' ]]
done
rm "$fixture/active"
if CAPTURE_CASE=success "$launcher" capture "$fixture" "$fixture/frame.png"; then
    echo 'FAIL: inactive run captured' >&2; exit 1
fi
printf 'PASS: exact private environment, fresh success, partial/empty failure, inactive rejection\n'
