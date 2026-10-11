#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [[ -n "${BEAGLE_PATH:-}" ]]; then
  beagle="$BEAGLE_PATH"
else
  git_common_dir="$(
    timeout --foreground 5 git -C "$repo" rev-parse \
      --path-format=absolute --git-common-dir
  )" || {
    printf 'window-marks-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-window-marks-native.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'window-marks-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'window-marks-native: %s\n' "$*" >&2
  exit 1
}

for command in bb bun cmp cp find git rg timeout; do
  command -v "$command" >/dev/null 2>&1 \
    || die "missing command: $command"
done
[[ -x "$beagle/bin/beagle" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

json="$beagle/native-core/src/native/json.bjs"
datum="$beagle/native-core/src/beagle/datum_reader.bjs"
schema_path="$beagle/native-core/src/beagle/nix_schema_path.bjs"
core="$repo/native/window_marks.bjs"
pure="$repo/native/window_marks_test.bjs"
native="$repo/native/window_marks_native.bjs"
bridge="$repo/native/window_marks_host.mjs"

printf 'window-marks-js: building one closed typed family graph\n' >&2
mkdir -p "$scratch/build"
timeout --foreground 180 "$beagle/bin/beagle-build-all" \
  "$json" "$datum" "$schema_path" \
  "$core" "$pure" "$native" \
  --out "$scratch/build" \
  >"$scratch/build.out" 2>"$scratch/build.err" || {
    sed -n '1,260p' "$scratch/build.err" >&2
    die 'closed Beagle/JS family build failed'
  }
pure_js="$(find "$scratch/build" -name window-marks-test.js -print -quit)"
native_js="$(find "$scratch/build" -name window-marks-native.js -print -quit)"
[[ -n "$native_js" && -f "$native_js" ]] || die 'window marks module was not emitted'

cat >"$scratch/window-marks" <<EOF
#!/usr/bin/env bash
exec env FIRN_WINDOW_MARKS_MODULE='$native_js' bun '$bridge' "\$@"
EOF
chmod +x "$scratch/window-marks"

FIRN_WINDOW_MARKS_TEST_MODULE="$pure_js" \
timeout --foreground 30 bun --eval \
  'const m = await import(process.env.FIRN_WINDOW_MARKS_TEST_MODULE); process.exitCode = m.run([]);' \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die 'pure JSONL append/fold/identity fixtures failed'
[[ ! -s "$scratch/pure.err" ]] || die 'pure fixtures wrote stderr'

fake_bin="$scratch/fake-bin"
fake_log="$scratch/fake-log"
mkdir -p "$fake_bin" "$fake_log"

cat >"$fake_bin/niri" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'niri %s\n' "$*" >>"$FAKE_EVENTS"
case "$*" in
  'msg -j windows') printf '%s' "$FAKE_NIRI_WINDOWS" ;;
  'msg -j focused-window') printf '%s' "$FAKE_NIRI_FOCUSED" ;;
  'msg action focus-window --id '*)
    printf '%s\n' "$*" >>"$FAKE_FOCUS"
    ;;
  *) exit 97 ;;
esac
EOF

cat >"$fake_bin/rofi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'rofi %s\n' "$*" >>"$FAKE_EVENTS"
printf '%s\n' "$*" >>"$FAKE_ROFI_ARGS"
if [[ " $* " == *' -e '* ]]; then
  exit 0
fi
input="$(cat)"
printf '%s' "$input" >"$FAKE_ROFI_STDIN"
printf '%s' "${ROFI_SELECTION:-}"
EOF

chmod +x "$fake_bin/niri" "$fake_bin/rofi"

export PATH="$fake_bin:$PATH"
export FAKE_EVENTS="$fake_log/events"
export FAKE_FOCUS="$fake_log/focus"
export FAKE_ROFI_ARGS="$fake_log/rofi-args"
export FAKE_ROFI_STDIN="$fake_log/rofi-stdin"
export MARKS_LOG="$scratch/state/nested/marks.jsonl"
export FAKE_NIRI_FOCUSED='{"id":42,"app_id":"org.term","title":"Shell"}'
export FAKE_NIRI_WINDOWS='[]'
: >"$FAKE_EVENTS"
: >"$FAKE_FOCUS"
: >"$FAKE_ROFI_ARGS"

run_case() {
  local name="$1"
  shift
  set +e
  timeout --foreground 30 "$@" >"$scratch/$name.out" 2>"$scratch/$name.err"
  local status=$?
  set -e
  printf '%s\n' "$status" >"$scratch/$name.status"
}

expect_status() {
  local name="$1" expected="$2"
  [[ "$(<"$scratch/$name.status")" == "$expected" ]] \
    || die "$name status was $(<"$scratch/$name.status"), expected $expected"
}

run_case invalid-mark "$scratch/window-marks" wm-mark '**'
expect_status invalid-mark 2
run_case invalid-unmark "$scratch/window-marks" wm-unmark ''
expect_status invalid-unmark 2
run_case invalid-jump "$scratch/window-marks" wm-jump aa
expect_status invalid-jump 2

run_case mark-focused "$scratch/window-marks" wm-mark A
expect_status mark-focused 0
[[ ! -s "$scratch/mark-focused.err" ]] || die "focused mark wrote stderr"
[[ -f "$MARKS_LOG" ]] || die "MARKS_LOG parent creation failed"
for tx in 1 2 3 4; do
  rg -q "^\\{\"tx\":$tx," "$MARKS_LOG" || die "missing transaction $tx"
done

export FAKE_NIRI_WINDOWS='[{"id":77,"app_id":"org.web","title":"Browser old"},{"id":5,"app_id":"x","title":"x"}]'
run_case mark-explicit "$scratch/window-marks" wm-mark B 77
expect_status mark-explicit 0
for tx in 5 6 7 8; do
  rg -q "^\\{\"tx\":$tx," "$MARKS_LOG" || die "missing transaction $tx"
done

run_case mark-missing "$scratch/window-marks" wm-mark c 404
expect_status mark-missing 1

run_case unmark "$scratch/window-marks" wm-unmark A
expect_status unmark 0
rg -q '^\{"tx":9,"op":"retract","l":"@mark-a","frame":"wm-mark","ts":' \
  "$MARKS_LOG" || die "unmark retract encoding changed"

export FAKE_NIRI_WINDOWS='[{"id":77,"app_id":"org.web","title":"Browser old"}]'
run_case list "$scratch/window-marks" wm-marks
expect_status list 0

: >"$FAKE_FOCUS"
run_case jump-exact "$scratch/window-marks" wm-jump B
expect_status jump-exact 0
tail -n 1 "$FAKE_FOCUS" | rg -qx 'msg action focus-window --id 77' \
  || die "exact jump focus argv changed"

export FAKE_NIRI_WINDOWS='[{"id":88,"app_id":"org.web","title":"Browser old restored"},{"id":89,"app_id":"org.web","title":"Other"}]'
run_case jump-identity "$scratch/window-marks" wm-jump b
expect_status jump-identity 0
tail -n 1 "$FAKE_FOCUS" | rg -qx 'msg action focus-window --id 88' \
  || die "identity jump focus argv changed"

export FAKE_NIRI_WINDOWS='[{"id":4,"app_id":"other","title":"Other"}]'
run_case jump-dead "$scratch/window-marks" wm-jump b
expect_status jump-dead 1
run_case jump-missing "$scratch/window-marks" wm-jump c
expect_status jump-missing 1

default_home="$scratch/default-home"
run_case default-path env -u MARKS_LOG HOME="$default_home" \
  "$scratch/window-marks" wm-unmark z
expect_status default-path 0
[[ -f "$default_home/.local/state/wm-world/marks.jsonl" ]] \
  || die "default HOME state path changed"

printf 'ok: Beagle/JS window marks preserves JSONL append/fold/identity and six Bun CLI contracts\n'
