#!/usr/bin/env bash
# Hermetic path-policy checks for the Gjoa launcher.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$HERE/gjoa}"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/gjoa-launcher-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

pass=0
fail=0
check() {
  local description="$1"; shift
  if "$@"; then
    pass=$((pass + 1)); printf 'PASS  %s\n' "$description"
  else
    fail=$((fail + 1)); printf 'FAIL  %s\n' "$description"
  fi
}
status_one_and_contains() {
  [ "$STATUS" -eq 1 ] && [[ "$OUTPUT" == *"$1"* ]]
}

run() {
  local home="$1"; shift
  OUTPUT="$(HOME="$home" PATH="$SCRATCH/bin:$PATH" RECORD="$SCRATCH/record" \
    "$TARGET" "$@" 2>&1)"
  STATUS=$?
}

mkdir -p "$SCRATCH/bin"
cat >"$SCRATCH/bin/direnv" <<'SH'
#!/usr/bin/env bash
printf 'BEAGLE_PIN_ROOT=%s\nargs=%s\n' "$BEAGLE_PIN_ROOT" "$*" >"$RECORD"
SH
chmod +x "$SCRATCH/bin/direnv"

wrong="$SCRATCH/wrong"
mkdir -p "$wrong/code/gjoa/worktrees/dev-runtime" "$wrong/code/gjoa/worktrees/other"
ln -s "$wrong/code/gjoa/worktrees/other" "$wrong/code/gjoa/active"
run "$wrong" status
check 'a selector outside worktrees/dev-runtime is rejected' \
  status_one_and_contains 'must resolve to '

noref="$SCRATCH/noref"
mkdir -p "$noref/code/gjoa/worktrees/dev-runtime"
ln -s "$noref/code/gjoa/worktrees/dev-runtime" "$noref/code/gjoa/active"
run "$noref" status
check 'a missing Beagle ref is rejected' status_one_and_contains 'configs/beagle.ref not found'

malformed="$SCRATCH/malformed"
mkdir -p "$malformed/code/gjoa/worktrees/dev-runtime/configs"
ln -s "$malformed/code/gjoa/worktrees/dev-runtime" "$malformed/code/gjoa/active"
printf 'not-an-object-id\n' >"$malformed/code/gjoa/worktrees/dev-runtime/configs/beagle.ref"
run "$malformed" status
check 'a malformed Beagle object ID is rejected' \
  status_one_and_contains 'must contain one lowercase hexadecimal full object ID'

missing="$SCRATCH/missing"
ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
mkdir -p "$missing/code/gjoa/worktrees/dev-runtime/configs"
ln -s "$missing/code/gjoa/worktrees/dev-runtime" "$missing/code/gjoa/active"
printf '%s\n' "$ref" >"$missing/code/gjoa/worktrees/dev-runtime/configs/beagle.ref"
run "$missing" status
check 'a missing canonical Beagle pin is rejected' \
  status_one_and_contains "Beagle pin $missing/code/beagle/pins/$ref not found"

valid="$SCRATCH/valid"
mkdir -p "$valid/code/gjoa/worktrees/dev-runtime/configs" "$valid/code/beagle/pins/$ref"
ln -s "$valid/code/gjoa/worktrees/dev-runtime" "$valid/code/gjoa/active"
printf '%s\n' "$ref" >"$valid/code/gjoa/worktrees/dev-runtime/configs/beagle.ref"
run "$valid" status
check 'the canonical runtime and Beagle pin reach direnv' test "$STATUS" -eq 0
check 'direnv receives the canonical Beagle pin root' \
  grep -Fxq "BEAGLE_PIN_ROOT=$valid/code/beagle/pins/$ref" "$SCRATCH/record"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
