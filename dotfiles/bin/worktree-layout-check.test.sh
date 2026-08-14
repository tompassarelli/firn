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

new_container() { # new_container <name> [object-format]
  local c="$code/$1"
  mkdir -p "$c"
  if [ -n "${2:-}" ]; then
    git init -q --object-format="$2" -b main "$c/main"
  else
    git init -q -b main "$c/main"
  fi
  printf 'base\n' >"$c/main/f.txt"
  git -C "$c/main" add f.txt
  git -C "$c/main" commit -qm base
}

# The checker refuses to report OK below five discovered repositories, so the
# fixture has to clear that floor before either assertion means anything.
for n in alpha charlie delta echo; do new_container "$n"; done
# A SHA-256 fixture makes "full object ID" executable policy instead of a
# euphemism for SHA-1's historical 40-character spelling.
new_container bravo sha256

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

# --- T20: a content-addressed pin is reported as a pin, not as a stray -------
bravo_oid="$(git -C "$code/bravo/main" rev-parse HEAD)"
git -C "$code/bravo/main" worktree add -q --detach "$code/bravo/pins/$bravo_oid" "$bravo_oid"
printf 'Consumers: this layout test.\n' >"$code/bravo/pins/$bravo_oid.pin"
out="$(run)"; status=$?
check "a pin at pins/<full-object-id> exits 0" "$status"
grep -q 'STRAY' <<<"$out" \
  && { printf '%s\n' "$out" >&2; check "a pin is not a stray" 1; } \
  || check "a pin is not a stray" 0
grep -q '^PIN    bravo' <<<"$out" \
  && check "a pin is named as a pin, not silently swallowed" 0 \
  || { printf '%s\n' "$out" >&2; check "a pin is named as a pin, not silently swallowed" 1; }
grep -q '(1 pin(s))' <<<"$out" \
  && check "the OK line counts pins" 0 \
  || { printf '%s\n' "$out" >&2; check "the OK line counts pins" 1; }

# --- content addressing is checked, not merely documented ------------------
git -C "$code/delta/main" worktree add -q --detach "$code/delta/pins/site" main
out="$(run)"; status=$?
[ "$status" -ne 0 ] \
  && check "a semantic pin name fails the check" 0 \
  || { printf '%s\n' "$out" >&2; check "a semantic pin name fails the check" 1; }
grep -q "leaf is not the checkout's full object ID" <<<"$out" \
  && check "the invalid leaf has a pointed reason" 0 \
  || { printf '%s\n' "$out" >&2; check "the invalid leaf has a pointed reason" 1; }
git -C "$code/delta/main" worktree remove "$code/delta/pins/site"

charlie_oid="$(git -C "$code/charlie/main" rev-parse HEAD)"
wrong_prefix="${charlie_oid%?}"
wrong_last="${charlie_oid#"$wrong_prefix"}"
if [ "$wrong_last" = 0 ]; then wrong_oid="${wrong_prefix}1"
else wrong_oid="${wrong_prefix}0"
fi
git -C "$code/charlie/main" worktree add -q --detach "$code/charlie/pins/$wrong_oid" main
printf 'Consumers: this layout test.\n' >"$code/charlie/pins/$wrong_oid.pin"
out="$(run)"; status=$?
[ "$status" -ne 0 ] \
  && check "a path whose object ID differs from HEAD fails" 0 \
  || { printf '%s\n' "$out" >&2; check "a path whose object ID differs from HEAD fails" 1; }
grep -q "leaf is not the checkout's full object ID" <<<"$out" \
  && check "the HEAD mismatch has a pointed reason" 0 \
  || { printf '%s\n' "$out" >&2; check "the HEAD mismatch has a pointed reason" 1; }
git -C "$code/charlie/main" worktree remove "$code/charlie/pins/$wrong_oid"
rm "$code/charlie/pins/$wrong_oid.pin"

delta_oid="$(git -C "$code/delta/main" rev-parse HEAD)"
git -C "$code/delta/main" worktree add -q --detach "$code/delta/pins/$delta_oid" "$delta_oid"
out="$(run)"; status=$?
[ "$status" -ne 0 ] \
  && check "a hash pin without its consumer sidecar fails" 0 \
  || { printf '%s\n' "$out" >&2; check "a hash pin without its consumer sidecar fails" 1; }
grep -q 'same-name consumer sidecar is missing' <<<"$out" \
  && check "the missing sidecar has a pointed reason" 0 \
  || { printf '%s\n' "$out" >&2; check "the missing sidecar has a pointed reason" 1; }
printf '   \n\t\n' >"$code/delta/pins/$delta_oid.pin"
out="$(run)"; status=$?
[ "$status" -ne 0 ] \
  && check "a whitespace-only consumer sidecar fails" 0 \
  || { printf '%s\n' "$out" >&2; check "a whitespace-only consumer sidecar fails" 1; }
grep -q 'same-name consumer sidecar is empty' <<<"$out" \
  && check "the empty sidecar has a pointed reason" 0 \
  || { printf '%s\n' "$out" >&2; check "the empty sidecar has a pointed reason" 1; }
printf 'Consumers: this layout test.\n' >"$code/delta/pins/$delta_oid.pin"
out="$(run)"; status=$?
check "adding the same-hash consumer sidecar restores a clean layout" "$status"

echo_oid="$(git -C "$code/echo/main" rev-parse HEAD)"
git -C "$code/echo/main" worktree add -q -b attached-pin "$code/echo/pins/$echo_oid" "$echo_oid"
printf 'Consumers: this layout test.\n' >"$code/echo/pins/$echo_oid.pin"
out="$(run)"; status=$?
[ "$status" -ne 0 ] \
  && check "a hash-named pin attached to a branch fails" 0 \
  || { printf '%s\n' "$out" >&2; check "a hash-named pin attached to a branch fails" 1; }
grep -q 'HEAD is attached to a branch' <<<"$out" \
  && check "the attached HEAD has a pointed reason" 0 \
  || { printf '%s\n' "$out" >&2; check "the attached HEAD has a pointed reason" 1; }
git -C "$code/echo/main" worktree remove "$code/echo/pins/$echo_oid"
git -C "$code/echo/main" branch -d attached-pin >/dev/null
rm "$code/echo/pins/$echo_oid.pin"

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
