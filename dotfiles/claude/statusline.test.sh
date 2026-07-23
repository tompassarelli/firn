#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.claude" "$TMP/runtime"

grep -Fqx '  local north="/run/current-system/sw/bin/north"' "$HERE/statusline.sh"
! grep -Fq '/home/tom/code/north/bin/' "$HERE/statusline.sh"
sed "s|/run/current-system/sw/bin/north|$TMP/bin/north|" \
  "$HERE/statusline.sh" > "$TMP/statusline.sh"

cat > "$TMP/bin/north" <<'FAKE'
#!/usr/bin/env bash
printf 'started\n' > "$STATUSLINE_STARTED"
sleep 2
cat > "$STATUSLINE_CAPTURE"
printf 'call\n' >> "$STATUSLINE_CALLS"
printf 'observer output must stay hidden\n'
FAKE
chmod +x "$TMP/bin/north" "$TMP/statusline.sh"

payload='{"cwd":"/private/project","rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600}}}'
output="$(printf '%s' "$payload" | HOME="$TMP/home" XDG_RUNTIME_DIR="$TMP/runtime" STATUSLINE_STARTED="$TMP/started" \
  STATUSLINE_CAPTURE="$TMP/capture.json" STATUSLINE_CALLS="$TMP/calls" bash "$TMP/statusline.sh")"

[[ "$output" == "" ]]
for _ in {1..30}; do
  [[ -f "$TMP/started" ]] && break
  sleep 0.1
done
[[ -f "$TMP/started" ]]
[[ ! -f "$TMP/capture.json" ]] # caller returned while observer was still sleeping

for _ in {1..50}; do
  [[ -f "$TMP/capture.json" ]] && break
  sleep 0.1
done
cmp -s <(printf '%s' "$payload") "$TMP/capture.json"

# Let the cooldown expire, then race a render burst. Every render must remain
# fast/output-safe while exactly one detached observer receives the burst.
sleep 1.2
rm -f "$TMP/calls" "$TMP/capture.json"
for i in {1..20}; do
  printf '%s' "$payload" | HOME="$TMP/home" XDG_RUNTIME_DIR="$TMP/runtime" STATUSLINE_STARTED="$TMP/started" \
    STATUSLINE_CAPTURE="$TMP/capture.json" STATUSLINE_CALLS="$TMP/calls" \
    bash "$TMP/statusline.sh" > "$TMP/output-$i" &
done
wait
for i in {1..20}; do
  [[ "$(< "$TMP/output-$i")" == "" ]]
done
for _ in {1..30}; do
  [[ -f "$TMP/calls" ]] && break
  sleep 0.1
done
[[ "$(wc -l < "$TMP/calls")" -eq 1 ]]
printf 'ok: Claude statusline output preserved; burst forwarding single-flight, detached, and silent\n'
