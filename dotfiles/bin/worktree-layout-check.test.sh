#!/usr/bin/env bash
# worktree-layout-check is the detector behind the container layout. Its two
# failure modes are opposite: calling a legal pin a stray (which teaches people
# to ignore it) and calling a legacy wt- sibling legal (which is the drift it
# exists to catch). Both directions are asserted here.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO/dotfiles/bin/worktree-layout-check"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/worktree-layout-check-test.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT

export GIT_AUTHOR_NAME=wlc-test
export GIT_AUTHOR_EMAIL=wlc-test@example.invalid
export GIT_COMMITTER_NAME=wlc-test
export GIT_COMMITTER_EMAIL=wlc-test@example.invalid

pass=0
fail_count=0

check() { # check <description> <0|1 truth>
  if [ "$2" -eq 0 ]; then
    printf 'PASS: %s\n' "$1"
    pass=$((pass + 1))
  else
    printf 'FAIL: %s\n' "$1" >&2
    fail_count=$((fail_count + 1))
  fi
}

code="$scratch/code"
mkdir -p "$code"
code="$(cd "$code" && pwd -P)"

new_container() { # new_container <name>
  local c="$code/$1"
  mkdir -p "$c"
  git init -q -b main "$c/main"
  printf 'base\n' >"$c/main/f.txt"
  git -C "$c/main" add f.txt
  git -C "$c/main" commit -qm base
}

# The checker refuses to report OK below five discovered repositories, so the
# fixture has to clear that floor before either assertion means anything.
for n in alpha bravo charlie delta echo; do new_container "$n"; done

run() { CODE_ROOT="$code" HOME="$scratch" "$TARGET" 2>&1; }

# --- baseline: main-only containers are clean ------------------------------
out="$(run)"; status=$?
check "clean layout exits 0" "$status"
grep -q 'worktree-layout: OK' <<<"$out" \
  && check "clean layout reports OK" 0 \
  || { printf '%s\n' "$out" >&2; check "clean layout reports OK" 1; }

# --- a lane under worktrees/ is legal --------------------------------------
git -C "$code/alpha/main" worktree add -q -b lane "$code/alpha/worktrees/lane" main
out="$(run)"; status=$?
check "a lane at worktrees/<slug> exits 0" "$status"
grep -q 'STRAY' <<<"$out" \
  && { printf '%s\n' "$out" >&2; check "a lane at worktrees/<slug> is not a stray" 1; } \
  || check "a lane at worktrees/<slug> is not a stray" 0

# --- T20: a pin is reported as a pin, not as a stray ------------------------
git -C "$code/bravo/main" worktree add -q --detach "$code/bravo/pins/site" main
out="$(run)"; status=$?
check "a pin at pins/<name> exits 0" "$status"
grep -q 'STRAY' <<<"$out" \
  && { printf '%s\n' "$out" >&2; check "a pin is not a stray" 1; } \
  || check "a pin is not a stray" 0
grep -q '^PIN    bravo' <<<"$out" \
  && check "a pin is named as a pin, not silently swallowed" 0 \
  || { printf '%s\n' "$out" >&2; check "a pin is named as a pin, not silently swallowed" 1; }
grep -q '(1 pin(s))' <<<"$out" \
  && check "the OK line counts pins" 0 \
  || { printf '%s\n' "$out" >&2; check "the OK line counts pins" 1; }

# --- T21: the legacy wt- sibling is the drift this detector exists for ------
git -C "$code/charlie/main" worktree add -q -b legacy "$code/charlie/wt-legacy" main
out="$(run)"; status=$?
[ "$status" -ne 0 ] \
  && check "a legacy wt-<slug> sibling fails the check" 0 \
  || { printf '%s\n' "$out" >&2; check "a legacy wt-<slug> sibling fails the check" 1; }
grep -q 'STRAY  charlie' <<<"$out" \
  && check "the legacy sibling is reported as a STRAY" 0 \
  || { printf '%s\n' "$out" >&2; check "the legacy sibling is reported as a STRAY" 1; }
grep -q 'worktrees/<slug>' <<<"$out" \
  && check "the remediation names the new layout" 0 \
  || { printf '%s\n' "$out" >&2; check "the remediation names the new layout" 1; }

# --- the false-green floor still holds -------------------------------------
small="$scratch/small"
mkdir -p "$small"
out="$(CODE_ROOT="$small" HOME="$scratch" "$TARGET" 2>&1)"; status=$?
[ "$status" -ne 0 ] \
  && check "too few repositories refuses to report clean" 0 \
  || { printf '%s\n' "$out" >&2; check "too few repositories refuses to report clean" 1; }

if [ "$fail_count" -eq 0 ]; then
  printf 'worktree-layout-check tests: PASS (%d checks)\n' "$pass"
else
  printf 'worktree-layout-check tests: FAIL (%d passed, %d failed)\n' "$pass" "$fail_count" >&2
  exit 1
fi
