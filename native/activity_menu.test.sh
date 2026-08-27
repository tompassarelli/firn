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
    printf 'activity-menu: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-activity-menu.XXXXXX")"
cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'activity-menu: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'activity-menu: %s\n' "$*" >&2
  exit 1
}

for command in bash cmp git ln mkdir mktemp timeout; do
  command -v "$command" >/dev/null 2>&1 \
    || die "missing command: $command"
done
[[ -x "$beagle/bin/beagle-build-all" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

bun="${FIRN_BUN:-$(command -v bun || true)}"
[[ -n "$bun" && -x "$bun" ]] || die "Bun runtime is unavailable"

modules="$scratch/modules"
mkdir -p "$modules/node_modules/beagle"
timeout --foreground 120 "$beagle/bin/beagle-build-all" \
  "$repo/native/activity_menu.bjs" --out "$modules" \
  >"$scratch/build.out" 2>"$scratch/build.err" || {
    sed -n '1,240p' "$scratch/build.err" >&2
    die "Beagle/JS compilation failed"
  }
[[ -f "$modules/activity/menu.js" ]] \
  || die "activity menu module was not produced"
cp -- "$beagle/beagle-lib/lib/beagle/core.js" \
  "$modules/node_modules/beagle/core.js"
printf '%s\n' '{"type":"module"}' \
  >"$modules/node_modules/beagle/package.json"

all_bin="$scratch/all-bin"
activity_bin="$scratch/activity-bin"
empty_bin="$scratch/empty-bin"
mkdir -p "$all_bin" "$activity_bin" "$empty_bin"
bash_path="$(command -v bash)"
ln -s "$bash_path" "$all_bin/bash"
ln -s "$bash_path" "$activity_bin/bash"
ln -s "$bash_path" "$empty_bin/bash"

cat >"$all_bin/activity" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_ACTIVITY_LOG"
if [[ "$*" == 'list --menu' ]]; then
  printf '%s' "$FAKE_MENU_ITEMS"
  exit "$FAKE_LIST_STATUS"
fi
exit "$FAKE_ACTION_STATUS"
EOF
chmod +x "$all_bin/activity"
ln -s "$all_bin/activity" "$activity_bin/activity"

cat >"$all_bin/rofi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_ROFI_LOG"
while IFS= read -r line || [[ -n "$line" ]]; do
  printf '%s\n' "$line"
done >"$FAKE_ROFI_INPUT"
printf '%s' "$FAKE_ROFI_CHOICE"
exit "$FAKE_ROFI_STATUS"
EOF
chmod +x "$all_bin/rofi"

export FAKE_ACTIVITY_LOG="$scratch/activity.log"
export FAKE_ROFI_LOG="$scratch/rofi.log"
export FAKE_ROFI_INPUT="$scratch/rofi.input"
export FAKE_MENU_ITEMS=$'home\ngjoa\nmsa\n'
export FAKE_LIST_STATUS=0
export FAKE_ACTION_STATUS=0
export FAKE_ROFI_CHOICE=$'gjoa\n'
export FAKE_ROFI_STATUS=0

prepare_case() {
  : >"$FAKE_ACTIVITY_LOG"
  : >"$FAKE_ROFI_LOG"
  : >"$FAKE_ROFI_INPUT"
  export FAKE_LIST_STATUS=0
  export FAKE_ACTION_STATUS=0
  export FAKE_ROFI_CHOICE=$'gjoa\n'
  export FAKE_ROFI_STATUS=0
}

run_menu() {
  local label="$1"
  local path="$2"
  shift 2
  set +e
  PATH="$path" \
    FIRN_ACTIVITY_MENU_MODULE="$modules/activity/menu.js" \
    "$bun" "$repo/native/activity_menu_host.mjs" "$@" \
    >"$scratch/$label.out" 2>"$scratch/$label.err"
  menu_status=$?
  set -e
}

assert_empty() {
  local path="$1"
  [[ ! -s "$path" ]] || die "expected empty output: $path"
}

assert_status() {
  local expected="$1"
  local label="$2"
  [[ "$menu_status" == "$expected" ]] \
    || die "$label returned $menu_status, expected $expected"
}

assert_activity_log() {
  local expected="$1"
  cmp -s "$FAKE_ACTIVITY_LOG" <(printf '%s' "$expected") \
    || die "activity invocations changed"
}

assert_rofi() {
  local prompt="$1"
  cmp -s "$FAKE_ROFI_LOG" <(printf '%s\n' "-dmenu -p $prompt") \
    || die "$prompt rofi invocation changed"
  cmp -s "$FAKE_ROFI_INPUT" <(printf '%s' "$FAKE_MENU_ITEMS") \
    || die "$prompt menu items changed"
}

prepare_case
run_menu goto "$all_bin"
assert_status 0 goto
assert_empty "$scratch/goto.out"
assert_empty "$scratch/goto.err"
assert_activity_log $'list --menu\ngoto gjoa\n'
assert_rofi activity

prepare_case
export FAKE_ROFI_CHOICE=$' msa \n'
run_menu move "$all_bin" --move
assert_status 0 move
assert_empty "$scratch/move.out"
assert_empty "$scratch/move.err"
assert_activity_log $'list --menu\nmove-to-activity msa\n'
assert_rofi 'move to activity'

prepare_case
export FAKE_ROFI_CHOICE=$'home\n'
run_menu assign "$all_bin" --assign
assert_status 0 assign
assert_empty "$scratch/assign.out"
assert_empty "$scratch/assign.err"
assert_activity_log $'list --menu\nassign home\n'
assert_rofi 'assign to activity'

prepare_case
export FAKE_ROFI_STATUS=1
run_menu cancel "$all_bin"
assert_status 0 cancel
assert_empty "$scratch/cancel.out"
assert_empty "$scratch/cancel.err"
assert_activity_log $'list --menu\n'
assert_rofi activity

prepare_case
export FAKE_ROFI_CHOICE=$'  \n'
run_menu blank "$all_bin"
assert_status 0 blank-selection
assert_empty "$scratch/blank.out"
assert_empty "$scratch/blank.err"
assert_activity_log $'list --menu\n'
assert_rofi activity

prepare_case
export FAKE_LIST_STATUS=17
run_menu list_failure "$all_bin"
assert_status 17 list-failure
assert_empty "$scratch/list_failure.out"
assert_empty "$scratch/list_failure.err"
assert_activity_log $'list --menu\n'
assert_empty "$FAKE_ROFI_LOG"

prepare_case
export FAKE_ACTION_STATUS=23
run_menu action_failure "$all_bin"
assert_status 23 action-failure
assert_empty "$scratch/action_failure.out"
assert_empty "$scratch/action_failure.err"
assert_activity_log $'list --menu\ngoto gjoa\n'
assert_rofi activity

prepare_case
run_menu missing_activity "$empty_bin"
assert_status 1 missing-activity
assert_empty "$scratch/missing_activity.out"
cmp -s "$scratch/missing_activity.err" \
  <(printf 'activity-menu: cannot start activity: errno 2\n') \
  || die "missing activity diagnostic changed"
assert_empty "$FAKE_ACTIVITY_LOG"
assert_empty "$FAKE_ROFI_LOG"

prepare_case
run_menu missing_rofi "$activity_bin"
assert_status 0 missing-rofi
assert_empty "$scratch/missing_rofi.out"
cmp -s "$scratch/missing_rofi.err" \
  <(printf 'activity-menu: cannot start rofi: errno 2\n') \
  || die "missing rofi diagnostic changed"
assert_activity_log $'list --menu\n'
assert_empty "$FAKE_ROFI_LOG"

printf 'ok: activity chooser preserves goto, move, assign, cancel, and failure flows\n'
