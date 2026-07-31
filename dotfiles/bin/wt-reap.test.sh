#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO/dotfiles/bin/wt-reap"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/wt-reap-test.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT

export GIT_AUTHOR_NAME=wt-reap-test
export GIT_AUTHOR_EMAIL=wt-reap-test@example.invalid
export GIT_COMMITTER_NAME=wt-reap-test
export GIT_COMMITTER_EMAIL=wt-reap-test@example.invalid

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

assert_ok() { # assert_ok <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then check "$desc" 0; else check "$desc" 1; fi
}

assert_not_ok() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then check "$desc" 1; else check "$desc" 0; fi
}

aged() { # a worktree older than wt-reap's 2h freshness gate
  touch -h -d '3 hours ago' "$1/.git"
}

# --- fixture: one container, one sibling per case --------------------------
container="$scratch/proj"
mkdir -p "$container"
# git records resolved paths in `worktree list`; compare against the same form.
container="$(cd "$container" && pwd -P)"
git init -q -b main "$container/main"
printf 'base\n' >"$container/main/f.txt"
git -C "$container/main" add f.txt
git -C "$container/main" commit -qm base

# 1. merged + clean -> reaped (the pre-existing ancestor path)
git -C "$container/main" worktree add -q -b merged-clean "$container/wt-merged-clean" main
printf 'merged\n' >>"$container/wt-merged-clean/f.txt"
git -C "$container/wt-merged-clean" commit -qam 'merged change'
git -C "$container/main" merge -q merged-clean

# The intervening commit is load-bearing: cherry-picking straight onto the
# branch's own parent reproduces a byte-identical sha, i.e. a plain ancestor.
land_equivalent() { # land <branch>'s commit onto main under a different sha
  local branch="$1" sha
  sha=$(git -C "$container/main" rev-parse "$branch")
  printf '%s landed\n' "$branch" >>"$container/main/log.txt"
  git -C "$container/main" add log.txt
  git -C "$container/main" commit -qm "main advances before $branch lands"
  git -C "$container/main" cherry-pick "$sha" >/dev/null
}

# 2. patch-equivalent + aged -> reaped (equiv)
git -C "$container/main" worktree add -q -b equiv-aged "$container/wt-equiv-aged" main
printf 'equiv-aged payload\n' >"$container/wt-equiv-aged/equiv-aged.txt"
git -C "$container/wt-equiv-aged" add equiv-aged.txt
git -C "$container/wt-equiv-aged" commit -qm 'equiv-aged work'
equiv_aged_sha=$(git -C "$container/main" rev-parse equiv-aged)
land_equivalent equiv-aged
aged "$container/wt-equiv-aged"

# 3. patch-equivalent but FRESH -> kept
git -C "$container/main" worktree add -q -b equiv-fresh "$container/wt-equiv-fresh" main
printf 'equiv-fresh payload\n' >"$container/wt-equiv-fresh/equiv-fresh.txt"
git -C "$container/wt-equiv-fresh" add equiv-fresh.txt
git -C "$container/wt-equiv-fresh" commit -qm 'equiv-fresh work'
land_equivalent equiv-fresh
touch -h "$container/wt-equiv-fresh/.git"

# 4. dirty tracked change -> kept
git -C "$container/main" worktree add -q -b dirty-branch "$container/wt-dirty" main
printf 'uncommitted\n' >>"$container/wt-dirty/f.txt"
aged "$container/wt-dirty"

# 5. clean tracked, but an untracked file present -> kept
git -C "$container/main" worktree add -q -b untracked-branch "$container/wt-untracked" main
printf 'untracked payload\n' >"$container/wt-untracked/scratch.txt"
aged "$container/wt-untracked"

# 6. rescue-* branch with a unique commit -> kept
git -C "$container/main" worktree add -q -b rescue-test "$container/wt-rescue-test" main
printf 'rescued\n' >"$container/wt-rescue-test/rescue.txt"
git -C "$container/wt-rescue-test" add rescue.txt
git -C "$container/wt-rescue-test" commit -qm 'rescued work'
aged "$container/wt-rescue-test"

# 7. genuinely unique commit -> kept
git -C "$container/main" worktree add -q -b unmerged-branch "$container/wt-unmerged" main
printf 'unique\n' >"$container/wt-unmerged/unique.txt"
git -C "$container/wt-unmerged" add unique.txt
git -C "$container/wt-unmerged" commit -qm 'unique work'
aged "$container/wt-unmerged"

# 8. locked, otherwise equiv + aged -> kept
git -C "$container/main" worktree add -q -b equiv-locked "$container/wt-equiv-locked" main
printf 'equiv-locked payload\n' >"$container/wt-equiv-locked/equiv-locked.txt"
git -C "$container/wt-equiv-locked" add equiv-locked.txt
git -C "$container/wt-equiv-locked" commit -qm 'equiv-locked work'
land_equivalent equiv-locked
aged "$container/wt-equiv-locked"
git -C "$container/main" worktree lock "$container/wt-equiv-locked"

# 9. --dry-run subject: equiv + aged, must survive the dry run
git -C "$container/main" worktree add -q -b equiv-dry "$container/wt-equiv-dry" main
printf 'equiv-dry payload\n' >"$container/wt-equiv-dry/equiv-dry.txt"
git -C "$container/wt-equiv-dry" add equiv-dry.txt
git -C "$container/wt-equiv-dry" commit -qm 'equiv-dry work'
land_equivalent equiv-dry
aged "$container/wt-equiv-dry"

# --- case 9 first: --dry-run must not disturb the fixture ------------------
dry_output="$(cd "$container" && "$TARGET" --dry-run 2>&1)"
dry_status=$?
check "--dry-run exits 0" "$dry_status"
if grep -Fq "would reap (equiv): $container/wt-equiv-dry" <<<"$dry_output"; then
  check "--dry-run reports would-reap for the equivalent lane" 0
else
  printf '%s\n' "$dry_output" >&2
  check "--dry-run reports would-reap for the equivalent lane" 1
fi
[ -d "$container/wt-equiv-dry" ] \
  && check "--dry-run left the worktree in place" 0 \
  || check "--dry-run left the worktree in place" 1
assert_ok "--dry-run left the branch in place" \
  git -C "$container/main" rev-parse --verify equiv-dry
if grep -Fq 'would reap: ' <<<"$dry_output"; then
  check "--dry-run reports would-reap for the merged lane" 0
else
  check "--dry-run reports would-reap for the merged lane" 1
fi
[ -d "$container/wt-merged-clean" ] \
  && check "--dry-run left the merged worktree in place" 0 \
  || check "--dry-run left the merged worktree in place" 1

# --- the real sweep --------------------------------------------------------
output="$(cd "$container" && "$TARGET" 2>&1)"
status=$?
check "wt-reap exits 0" "$status"

# 1. merged + clean
[ ! -d "$container/wt-merged-clean" ] \
  && check "merged+clean worktree reaped" 0 \
  || check "merged+clean worktree reaped" 1
assert_not_ok "merged-clean branch deleted" \
  git -C "$container/main" rev-parse --verify merged-clean
if grep -Fq "reaped: $container/wt-merged-clean (merged-clean)" <<<"$output"; then
  check "merged reap reported in the original format" 0
else
  printf '%s\n' "$output" >&2
  check "merged reap reported in the original format" 1
fi

# 2. patch-equivalent + aged
[ ! -d "$container/wt-equiv-aged" ] \
  && check "equivalent+aged worktree reaped" 0 \
  || check "equivalent+aged worktree reaped" 1
assert_not_ok "equiv-aged branch deleted" \
  git -C "$container/main" rev-parse --verify equiv-aged
if grep -Fq "reaped (equiv): $container/wt-equiv-aged (equiv-aged was $equiv_aged_sha)" <<<"$output"; then
  check "equiv reap reports path, branch, and tip sha" 0
else
  printf '%s\n' "$output" >&2
  check "equiv reap reports path, branch, and tip sha" 1
fi
assert_ok "reaped equiv tip sha still resolvable (recoverable)" \
  git -C "$container/main" cat-file -e "${equiv_aged_sha}^{commit}"

# 3. equivalent but fresh
[ -d "$container/wt-equiv-fresh" ] \
  && check "equivalent+fresh worktree kept" 0 \
  || check "equivalent+fresh worktree kept" 1
if grep -Fq "kept: fresh (equiv-fresh)" <<<"$output"; then
  check "fresh keep has its own reason string" 0
else
  printf '%s\n' "$output" >&2
  check "fresh keep has its own reason string" 1
fi

# 4. dirty tracked change
[ -d "$container/wt-dirty" ] \
  && check "dirty worktree kept" 0 \
  || check "dirty worktree kept" 1
assert_ok "dirty-branch not deleted" \
  git -C "$container/main" rev-parse --verify dirty-branch
if grep -Fq "kept: dirty ($container/wt-dirty)" <<<"$output"; then
  check "dirty keep reported in the original format" 0
else
  check "dirty keep reported in the original format" 1
fi

# 5. untracked file present
[ -d "$container/wt-untracked" ] \
  && check "untracked-only worktree kept" 0 \
  || check "untracked-only worktree kept" 1
if grep -Fq "kept: dirty ($container/wt-untracked)" <<<"$output"; then
  check "untracked file counts as unclean" 0
else
  printf '%s\n' "$output" >&2
  check "untracked file counts as unclean" 1
fi

# 6. rescue-*
[ -d "$container/wt-rescue-test" ] \
  && check "rescue-* worktree kept" 0 \
  || check "rescue-* worktree kept" 1
assert_ok "rescue-test branch not deleted" \
  git -C "$container/main" rev-parse --verify rescue-test

# 7. genuinely unique commit
[ -d "$container/wt-unmerged" ] \
  && check "unmerged worktree kept" 0 \
  || check "unmerged worktree kept" 1
assert_ok "unmerged-branch not deleted" \
  git -C "$container/main" rev-parse --verify unmerged-branch
if grep -Fq 'kept: unmerged (unmerged-branch, 1 commits ahead)' <<<"$output"; then
  check "unmerged keep reported in the original format" 0
else
  printf '%s\n' "$output" >&2
  check "unmerged keep reported in the original format" 1
fi

# 8. locked
[ -d "$container/wt-equiv-locked" ] \
  && check "locked equivalent worktree kept" 0 \
  || check "locked equivalent worktree kept" 1
assert_ok "equiv-locked branch not deleted" \
  git -C "$container/main" rev-parse --verify equiv-locked
if grep -Fq "kept: locked (equiv-locked)" <<<"$output"; then
  check "locked keep has its own reason string" 0
else
  printf '%s\n' "$output" >&2
  check "locked keep has its own reason string" 1
fi

# --- force discipline: -D is reachable only from the equivalence gate ------
if grep -Fq -- '--force' "$TARGET"; then
  check "wt-reap never force-removes a worktree" 1
else
  check "wt-reap never force-removes a worktree" 0
fi
if [ "$(grep -c -- 'branch -D' "$TARGET")" -eq 1 ]; then
  check "exactly one 'branch -D' call site" 0
else
  check "exactly one 'branch -D' call site" 1
fi

# --- --all sweeps every ~/code/*/main-shaped container ----------------------
all_root="$scratch/codehome"
mkdir -p "$all_root/code/projA"
git init -q -b main "$all_root/code/projA/main"
printf 'a\n' >"$all_root/code/projA/main/f.txt"
git -C "$all_root/code/projA/main" add f.txt
git -C "$all_root/code/projA/main" commit -qm base
git -C "$all_root/code/projA/main" worktree add -q -b done-branch "$all_root/code/projA/wt-done" main
git -C "$all_root/code/projA/main" merge -q done-branch >/dev/null

all_output="$(HOME="$all_root" bash -c 'cd "$1" && exec "$2" --all' _ "$all_root" "$TARGET" 2>&1)"
if grep -Fq 'reaped: ' <<<"$all_output"; then
  check "--all reaped the fixture" 0
else
  printf '%s\n' "$all_output" >&2
  check "--all reaped the fixture" 1
fi
[ ! -d "$all_root/code/projA/wt-done" ] \
  && check "--all removed the merged worktree" 0 \
  || check "--all removed the merged worktree" 1

if [ "$fail_count" -eq 0 ]; then
  printf 'wt-reap tests: PASS (%d checks)\n' "$pass"
else
  printf 'wt-reap tests: FAIL (%d passed, %d failed)\n' "$pass" "$fail_count" >&2
  exit 1
fi
