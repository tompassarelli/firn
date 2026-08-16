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

[[ -f "$beagle/bin/_beagle-racket" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

# shellcheck disable=SC1091
source "$beagle/bin/_beagle-racket"

build_native() {
  local name="$1" entry="$2"
  shift 2
  local output="$scratch/$name"
  mkdir -p "$scratch/$name-artifacts"
  timeout --foreground 620 "$beagle/bin/beagle" native-exe \
    --out "$output" \
    --entry "$entry" \
    --artifacts "$scratch/$name-artifacts" \
    "$@" >"$scratch/$name.build.out" 2>"$scratch/$name.build.err" \
    || {
      sed -n '1,260p' "$scratch/$name.build.err" >&2
      die "$name compilation failed"
    }
  [[ -x "$output" ]] || die "$name is not executable"
}

datum="$beagle/native-core/src/beagle/datum_reader.bgl"
edn="$beagle/native-core/src/native/edn.bgl"
json="$beagle/native-core/src/native/json.bgl"
core="$repo/native/window_marks.bgl"

build_native window-marks-test firn.window-marks-test/-main \
  "$datum" "$edn" "$json" "$core" "$repo/native/window_marks_test.bgl"
build_native window-marks firn.window-marks-native/-main \
  "$datum" "$edn" "$json" "$core" "$repo/native/window_marks_native.bgl"

"$scratch/window-marks-test" >"$scratch/pure.out"
[[ "$(rg -c '^PASS ' "$scratch/pure.out")" == "5" ]] \
  || die "pure append/fold/identity cases did not all pass"

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

cat >"$fake_bin/wm-mark" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_WM_MARK"
EOF

cat >"$fake_bin/wm-jump" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_WM_JUMP"
EOF

chmod +x "$fake_bin/niri" "$fake_bin/rofi" \
  "$fake_bin/wm-mark" "$fake_bin/wm-jump"

export PATH="$fake_bin:$PATH"
export FAKE_EVENTS="$fake_log/events"
export FAKE_FOCUS="$fake_log/focus"
export FAKE_ROFI_ARGS="$fake_log/rofi-args"
export FAKE_ROFI_STDIN="$fake_log/rofi-stdin"
export FAKE_WM_MARK="$fake_log/wm-mark"
export FAKE_WM_JUMP="$fake_log/wm-jump"
export MARKS_LOG="$scratch/state/nested/marks.log"
export FAKE_NIRI_FOCUSED='{"id":42,"app_id":"org.term","title":"Shell"}'
export FAKE_NIRI_WINDOWS='[]'
: >"$FAKE_EVENTS"
: >"$FAKE_FOCUS"
: >"$FAKE_ROFI_ARGS"
: >"$FAKE_WM_MARK"
: >"$FAKE_WM_JUMP"

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
cmp -s "$scratch/invalid-mark.err" \
  <(printf 'usage: wm-mark <letter> [id]  (letter = single alphanumeric)\n') \
  || die "wm-mark usage changed"
run_case invalid-unmark "$scratch/window-marks" wm-unmark ''
expect_status invalid-unmark 2
cmp -s "$scratch/invalid-unmark.err" <(printf 'usage: wm-unmark <letter>\n') \
  || die "wm-unmark usage changed"
run_case invalid-jump "$scratch/window-marks" wm-jump aa
expect_status invalid-jump 2
cmp -s "$scratch/invalid-jump.err" <(printf 'usage: wm-jump <letter>\n') \
  || die "wm-jump usage changed"

run_case mark-focused "$scratch/window-marks" wm-mark A
expect_status mark-focused 0
cmp -s "$scratch/mark-focused.out" \
  <(printf 'marked a -> @w42  org.term  Shell\n') \
  || die "focused mark output changed"
[[ ! -s "$scratch/mark-focused.err" ]] || die "focused mark wrote stderr"
[[ -f "$MARKS_LOG" ]] || die "MARKS_LOG parent creation failed"
[[ "$(rg -c ':op "assert"' "$MARKS_LOG")" == "4" ]] \
  || die "focused mark did not append four assertions"
for tx in 1 2 3 4; do
  rg -q "\\{:tx $tx," "$MARKS_LOG" || die "missing transaction $tx"
done

export FAKE_NIRI_WINDOWS='[{"id":77,"app_id":"org.web","title":"Browser old"},{"id":5,"app_id":"x","title":"x"}]'
run_case mark-explicit "$scratch/window-marks" wm-mark B 77
expect_status mark-explicit 0
cmp -s "$scratch/mark-explicit.out" \
  <(printf 'marked b -> @w77  org.web  Browser old\n') \
  || die "explicit mark output changed"
for tx in 5 6 7 8; do
  rg -q "\\{:tx $tx," "$MARKS_LOG" || die "missing transaction $tx"
done

run_case mark-missing "$scratch/window-marks" wm-mark c 404
expect_status mark-missing 1
cmp -s "$scratch/mark-missing.err" <(printf 'no window with id 404\n') \
  || die "missing explicit id diagnostic changed"

run_case unmark "$scratch/window-marks" wm-unmark A
expect_status unmark 0
cmp -s "$scratch/unmark.out" <(printf 'unmarked a\n') \
  || die "unmark output changed"
rg -q '^\{:tx 9, :op "retract", :l "@mark-a", :frame "wm-mark", :ts ' \
  "$MARKS_LOG" || die "unmark retract encoding changed"

export FAKE_NIRI_WINDOWS='[{"id":77,"app_id":"org.web","title":"Browser old"}]'
run_case list "$scratch/window-marks" wm-marks
expect_status list 0
cmp -s "$scratch/list.out" \
  <(printf '%-3s @w%-5s %s  %-24s %s\n' \
      b 77 alive org.web 'Browser old') \
  || die "wm-marks listing changed"

: >"$FAKE_FOCUS"
run_case jump-exact "$scratch/window-marks" wm-jump B
expect_status jump-exact 0
cmp -s "$scratch/jump-exact.out" <(printf 'exact -> @w77  org.web\n') \
  || die "exact jump output changed"
tail -n 1 "$FAKE_FOCUS" | rg -qx 'msg action focus-window --id 77' \
  || die "exact jump focus argv changed"

export FAKE_NIRI_WINDOWS='[{"id":88,"app_id":"org.web","title":"Browser old restored"},{"id":89,"app_id":"org.web","title":"Other"}]'
run_case jump-identity "$scratch/window-marks" wm-jump b
expect_status jump-identity 0
cmp -s "$scratch/jump-identity.out" \
  <(printf 'resolved-by-identity -> @w88  org.web  Browser old restored\n') \
  || die "identity jump output changed"
tail -n 1 "$FAKE_FOCUS" | rg -qx 'msg action focus-window --id 88' \
  || die "identity jump focus argv changed"

export FAKE_NIRI_WINDOWS='[{"id":4,"app_id":"other","title":"Other"}]'
run_case jump-dead "$scratch/window-marks" wm-jump b
expect_status jump-dead 1
cmp -s "$scratch/jump-dead.err" \
  <(printf 'unresolvable: mark b -> org.web (no live window of that app)\n') \
  || die "unresolvable diagnostic changed"
run_case jump-missing "$scratch/window-marks" wm-jump c
expect_status jump-missing 1
cmp -s "$scratch/jump-missing.err" <(printf 'no mark c\n') \
  || die "missing mark diagnostic changed"

: >"$FAKE_EVENTS"
: >"$FAKE_WM_MARK"
export FAKE_NIRI_FOCUSED='{"id":42,"app_id":"org.term","title":"Shell"}'
export ROFI_SELECTION=$'C\n'
run_case mark-rofi "$scratch/window-marks" wm-mark-rofi
expect_status mark-rofi 0
cmp -s "$FAKE_WM_MARK" <(printf 'C 42\n') \
  || die "wm-mark-rofi child argv changed"
sed -n '1p' "$FAKE_EVENTS" | rg -qx 'niri msg -j focused-window' \
  || die "wm-mark-rofi did not snapshot focus first"
sed -n '2p' "$FAKE_EVENTS" | \
  rg -qx 'rofi -dmenu -p set mark for: org.term' \
  || die "wm-mark-rofi rofi argv changed"
[[ ! -s "$FAKE_ROFI_STDIN" ]] || die "wm-mark-rofi stdin was not empty"

before_mark_calls="$(wc -l <"$FAKE_WM_MARK")"
export ROFI_SELECTION='not-a-letter'
run_case mark-rofi-invalid "$scratch/window-marks" wm-mark-rofi
expect_status mark-rofi-invalid 0
[[ "$(wc -l <"$FAKE_WM_MARK")" == "$before_mark_calls" ]] \
  || die "invalid rofi selection invoked wm-mark"

: >"$FAKE_ROFI_ARGS"
export FAKE_NIRI_FOCUSED='null'
run_case mark-rofi-empty "$scratch/window-marks" wm-mark-rofi
expect_status mark-rofi-empty 1
tail -n 1 "$FAKE_ROFI_ARGS" | rg -qx -- '-e no focused window to mark' \
  || die "empty-focus rofi diagnostic changed"

: >"$FAKE_WM_JUMP"
export FAKE_NIRI_WINDOWS='[]'
export ROFI_SELECTION=$'b  ○  org.web — Browser old\n'
run_case jump-rofi "$scratch/window-marks" wm-jump-rofi
expect_status jump-rofi 0
cmp -s "$FAKE_ROFI_STDIN" <(printf 'b  ○  org.web — Browser old') \
  || die "wm-jump-rofi menu changed"
cmp -s "$FAKE_WM_JUMP" <(printf 'b\n') \
  || die "wm-jump-rofi child argv changed"
tail -n 1 "$FAKE_ROFI_ARGS" | rg -qx -- '-dmenu -i -p jump to mark' \
  || die "wm-jump-rofi rofi argv changed"

empty_log="$scratch/empty.log"
: >"$empty_log"
: >"$FAKE_ROFI_ARGS"
run_case jump-rofi-empty env MARKS_LOG="$empty_log" \
  "$scratch/window-marks" wm-jump-rofi
expect_status jump-rofi-empty 0
tail -n 1 "$FAKE_ROFI_ARGS" | rg -qx -- '-e no marks set' \
  || die "empty marks rofi diagnostic changed"

default_home="$scratch/default-home"
run_case default-path env -u MARKS_LOG HOME="$default_home" \
  "$scratch/window-marks" wm-unmark z
expect_status default-path 0
[[ -f "$default_home/.local/state/wm-world/marks.log" ]] \
  || die "default HOME state path changed"

if ldd "$scratch/window-marks" | rg -qi 'racket|clojure|babashka|java'; then
  die "hosted runtime leaked into window-marks executable"
fi

printf 'ok: native window marks preserves append/fold/identity and six CLI contracts\n'
