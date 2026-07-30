#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO/dotfiles/bin/wt-reap"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/wt-reap-test.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT

pass=0
fail_count=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  fail_count=$((fail_count + 1))
}

ok() {
  pass=$((pass + 1))
}

# --- fixture: a container with main + three sibling worktrees --------------
container="$scratch/proj"
mkdir -p "$container"
git init -q -b main "$container/main"
git -C "$container/main" config user.name wt-reap-test
git -C "$container/main" config user.email wt-reap-test@example.invalid
printf 'base\n' >"$container/main/f.txt"
git -C "$container/main" add f.txt
git -C "$container/main" commit -qm base

# merged + clean sibling -> should be reaped
git -C "$container/main" worktree add -q -b merged-clean "$container/wt-merged-clean" main
printf 'merged content\n' >>"$container/wt-merged-clean/f.txt"
git -C "$container/wt-merged-clean" commit -qam 'merged change'
git -C "$container/main" merge -q merged-clean

# dirty sibling -> must survive (uncommitted change)
git -C "$container/main" worktree add -q -b dirty-branch "$container/wt-dirty" main
printf 'uncommitted\n' >>"$container/wt-dirty/f.txt"

# unmerged sibling -> must survive (commit not on main)
git -C "$container/main" worktree add -q -b unmerged-branch "$container/wt-unmerged" main
printf 'unmerged change\n' >>"$container/wt-unmerged/f.txt"
git -C "$container/wt-unmerged" commit -qam 'unmerged change'

merged_path="$container/wt-merged-clean"
dirty_path="$container/wt-dirty"
unmerged_path="$container/wt-unmerged"

output="$(cd "$merged_path" && "$TARGET" 2>&1)"
status=$?

if [ "$status" -eq 0 ]; then ok; else fail "exit status: got $status"; fi

if [ -d "$dirty_path" ]; then ok; else fail "dirty worktree was removed"; fi
if git -C "$container/main" rev-parse --verify dirty-branch >/dev/null 2>&1; then
  ok
else
  fail "dirty-branch was deleted"
fi

if [ -d "$unmerged_path" ]; then ok; else fail "unmerged worktree was removed"; fi
if git -C "$container/main" rev-parse --verify unmerged-branch >/dev/null 2>&1; then
  ok
else
  fail "unmerged-branch was deleted"
fi

if [ ! -d "$merged_path" ]; then ok; else fail "merged+clean worktree was NOT removed"; fi
if git -C "$container/main" rev-parse --verify merged-clean >/dev/null 2>&1; then
  fail "merged-clean branch was NOT deleted"
else
  ok
fi

if grep -Fq 'kept: dirty' <<<"$output"; then ok; else fail "missing 'kept: dirty' in output"; fi
if grep -Fq 'kept: unmerged (unmerged-branch, 1 commits ahead)' <<<"$output"; then
  ok
else
  fail "missing expected 'kept: unmerged' line, got: $output"
fi
if grep -Fq 'reaped: ' <<<"$output"; then ok; else fail "missing 'reaped:' line"; fi
if grep -Fq 'reaped 1, kept dirty 1, kept unmerged 1' <<<"$output"; then
  ok
else
  fail "missing expected summary line, got: $output"
fi

# --- --force / -f safety: branch -d and worktree remove never use force ----
if grep -Fq -- '--force' "$TARGET" || grep -Eq -- '(^|[^-])-D([^A-Za-z]|$)' "$TARGET"; then
  fail "wt-reap source uses a force flag"
else
  ok
fi

# --- --all sweeps every ~/code/*/main-shaped container ----------------------
all_root="$scratch/codehome"
mkdir -p "$all_root/code/projA"
git init -q -b main "$all_root/code/projA/main"
git -C "$all_root/code/projA/main" config user.name wt-reap-test
git -C "$all_root/code/projA/main" config user.email wt-reap-test@example.invalid
printf 'a\n' >"$all_root/code/projA/main/f.txt"
git -C "$all_root/code/projA/main" add f.txt
git -C "$all_root/code/projA/main" commit -qm base
git -C "$all_root/code/projA/main" worktree add -q -b done-branch "$all_root/code/projA/wt-done" main
git -C "$all_root/code/projA/main" merge -q done-branch >/dev/null

all_output="$(HOME="$all_root" bash -c 'cd "$1" && exec "$2" --all' _ "$all_root" "$TARGET" 2>&1)"
if grep -Fq 'reaped: ' <<<"$all_output"; then
  ok
else
  fail "--all did not reap the fixture: $all_output"
fi
if [ ! -d "$all_root/code/projA/wt-done" ]; then
  ok
else
  fail "--all left the merged worktree in place"
fi

if [ "$fail_count" -eq 0 ]; then
  printf 'wt-reap tests: PASS (%d checks)\n' "$pass"
else
  printf 'wt-reap tests: FAIL (%d passed, %d failed)\n' "$pass" "$fail_count" >&2
  exit 1
fi
