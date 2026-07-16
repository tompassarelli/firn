#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/code/north/bin" "$TMP/home/.claude"
printf 'lite\n' > "$TMP/home/.claude/.caveman-active"

cat > "$TMP/home/code/north/bin/north" <<'FAKE'
#!/usr/bin/env bash
sleep 1
cat > "$STATUSLINE_CAPTURE"
printf 'call\n' >> "$STATUSLINE_CALLS"
printf 'observer output must stay hidden\n'
FAKE
chmod +x "$TMP/home/code/north/bin/north"

payload='{"cwd":"/private/project","rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600}}}'
start="$EPOCHREALTIME"
output="$(printf '%s' "$payload" | HOME="$TMP/home" STATUSLINE_CAPTURE="$TMP/capture.json" STATUSLINE_CALLS="$TMP/calls" bash "$HERE/statusline.sh")"
elapsed="$(awk -v start="$start" -v finish="$EPOCHREALTIME" 'BEGIN { print finish - start }')"

[[ "$output" == $'\033[38;5;172m[CAVEMAN:LITE]\033[0m' ]]
awk -v elapsed="$elapsed" 'BEGIN { exit !(elapsed < 0.5) }'

for _ in {1..30}; do
  [[ -f "$TMP/capture.json" ]] && break
  sleep 0.1
done
cmp -s <(printf '%s' "$payload") "$TMP/capture.json"

# Let the cooldown expire, then race a render burst. Every render must remain
# fast/output-safe while exactly one detached observer receives the burst.
sleep 1.2
rm -f "$TMP/calls" "$TMP/capture.json"
for i in {1..20}; do
  printf '%s' "$payload" | HOME="$TMP/home" STATUSLINE_CAPTURE="$TMP/capture.json" STATUSLINE_CALLS="$TMP/calls" \
    bash "$HERE/statusline.sh" > "$TMP/output-$i" &
done
wait
for i in {1..20}; do
  [[ "$(< "$TMP/output-$i")" == $'\033[38;5;172m[CAVEMAN:LITE]\033[0m' ]]
done
for _ in {1..30}; do
  [[ -f "$TMP/calls" ]] && break
  sleep 0.1
done
[[ "$(wc -l < "$TMP/calls")" -eq 1 ]]
printf 'ok: Claude statusline output preserved; burst forwarding single-flight, detached, and silent\n'
