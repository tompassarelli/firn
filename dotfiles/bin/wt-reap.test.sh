#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO/dotfiles/bin/wt-reap"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/wt-reap-test.XXXXXX")"
live_pid=''
trap 'if [ -n "${live_pid:-}" ]; then kill "$live_pid" 2>/dev/null || true; fi; rm -rf "${scratch:?}"' EXIT

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
# every lane inherits these ignores; the ignored-file gate is tested through them
printf 'docs/private/\n.direnv/\nresult\nresult-*\n' >"$container/main/.gitignore"
git -C "$container/main" add f.txt .gitignore
git -C "$container/main" commit -qm base

# 1. fresh + clean + merged -> kept. This is the race guard for a just-created
# worktree whose HEAD starts at main.
git -C "$container/main" worktree add -q -b merged-fresh "$container/wt-merged-fresh" main

# 2. aged + clean + merged -> reaped (the ordinary ancestor path).
git -C "$container/main" worktree add -q -b merged-aged "$container/wt-merged-aged" main
aged "$container/wt-merged-aged"

# 3-5. Aged ordinary-merged lanes are still protected by rescue, lock, and a
# live CWD, exactly as their patch-equivalent counterparts are.
git -C "$container/main" worktree add -q -b rescue-merged "$container/wt-rescue-merged" main
aged "$container/wt-rescue-merged"
git -C "$container/main" worktree add -q -b merged-locked "$container/wt-merged-locked" main
aged "$container/wt-merged-locked"
git -C "$container/main" worktree lock "$container/wt-merged-locked"
git -C "$container/main" worktree add -q -b merged-live "$container/wt-merged-live" main
aged "$container/wt-merged-live"
(cd "$container/wt-merged-live" && exec sleep 60) >/dev/null 2>&1 &
live_pid=$!

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

# 6. patch-equivalent + aged -> reaped (equiv)
git -C "$container/main" worktree add -q -b equiv-aged "$container/wt-equiv-aged" main
printf 'equiv-aged payload\n' >"$container/wt-equiv-aged/equiv-aged.txt"
git -C "$container/wt-equiv-aged" add equiv-aged.txt
git -C "$container/wt-equiv-aged" commit -qm 'equiv-aged work'
equiv_aged_sha=$(git -C "$container/main" rev-parse equiv-aged)
land_equivalent equiv-aged
aged "$container/wt-equiv-aged"

# 7. patch-equivalent but FRESH -> kept
git -C "$container/main" worktree add -q -b equiv-fresh "$container/wt-equiv-fresh" main
printf 'equiv-fresh payload\n' >"$container/wt-equiv-fresh/equiv-fresh.txt"
git -C "$container/wt-equiv-fresh" add equiv-fresh.txt
git -C "$container/wt-equiv-fresh" commit -qm 'equiv-fresh work'
land_equivalent equiv-fresh
touch -h "$container/wt-equiv-fresh/.git"

# 8. dirty tracked change -> kept
git -C "$container/main" worktree add -q -b dirty-branch "$container/wt-dirty" main
printf 'uncommitted\n' >>"$container/wt-dirty/f.txt"
aged "$container/wt-dirty"

# 9. clean tracked, but an untracked file present -> kept
git -C "$container/main" worktree add -q -b untracked-branch "$container/wt-untracked" main
printf 'untracked payload\n' >"$container/wt-untracked/scratch.txt"
aged "$container/wt-untracked"

# 10. rescue-* branch with a unique commit -> kept
git -C "$container/main" worktree add -q -b rescue-test "$container/wt-rescue-test" main
printf 'rescued\n' >"$container/wt-rescue-test/rescue.txt"
git -C "$container/wt-rescue-test" add rescue.txt
git -C "$container/wt-rescue-test" commit -qm 'rescued work'
aged "$container/wt-rescue-test"

# 11. genuinely unique commit -> kept
git -C "$container/main" worktree add -q -b unmerged-branch "$container/wt-unmerged" main
printf 'unique\n' >"$container/wt-unmerged/unique.txt"
git -C "$container/wt-unmerged" add unique.txt
git -C "$container/wt-unmerged" commit -qm 'unique work'
aged "$container/wt-unmerged"

# 12. locked, otherwise equiv + aged -> kept
git -C "$container/main" worktree add -q -b equiv-locked "$container/wt-equiv-locked" main
printf 'equiv-locked payload\n' >"$container/wt-equiv-locked/equiv-locked.txt"
git -C "$container/wt-equiv-locked" add equiv-locked.txt
git -C "$container/wt-equiv-locked" commit -qm 'equiv-locked work'
land_equivalent equiv-locked
aged "$container/wt-equiv-locked"
git -C "$container/main" worktree lock "$container/wt-equiv-locked"

# 13. --dry-run subject: equiv + aged, must survive the dry run
git -C "$container/main" worktree add -q -b equiv-dry "$container/wt-equiv-dry" main
printf 'equiv-dry payload\n' >"$container/wt-equiv-dry/equiv-dry.txt"
git -C "$container/wt-equiv-dry" add equiv-dry.txt
git -C "$container/wt-equiv-dry" commit -qm 'equiv-dry work'
land_equivalent equiv-dry
aged "$container/wt-equiv-dry"

# 14. equiv + aged, but carrying ignored files `git status` never shows.
#     Disposable caches alongside them must not be what holds the tree.
git -C "$container/main" worktree add -q -b equiv-ignored "$container/wt-equiv-ignored" main
printf 'equiv-ignored payload\n' >"$container/wt-equiv-ignored/equiv-ignored.txt"
git -C "$container/wt-equiv-ignored" add equiv-ignored.txt
git -C "$container/wt-equiv-ignored" commit -qm 'equiv-ignored work'
equiv_ignored_sha=$(git -C "$container/main" rev-parse equiv-ignored)
land_equivalent equiv-ignored
mkdir -p "$container/wt-equiv-ignored/docs/private" \
         "$container/wt-equiv-ignored/.direnv/bin" \
         "$container/wt-equiv-ignored/sub/.direnv"
printf 'handoff notes\n' >"$container/wt-equiv-ignored/docs/private/note.md"
printf 'cache\n' >"$container/wt-equiv-ignored/.direnv/bin/x"
printf 'cache\n' >"$container/wt-equiv-ignored/sub/.direnv/y"
ln -s /nix/store/nonexistent "$container/wt-equiv-ignored/result"
ln -s /nix/store/nonexistent "$container/wt-equiv-ignored/result-2"
aged "$container/wt-equiv-ignored"

# 15. every non-merge commit is cherry-equivalent, but the lane also carries a
#     merge whose conflict resolution exists nowhere else. `git cherry` is blind
#     to merges, so only the merge gate can keep this tree.
merge_lane_base=$(git -C "$container/main" rev-parse main)
git -C "$container/main" worktree add -q -b merge-lane "$container/wt-merge-lane" main
# merge-side edits the same file differently, so merging it conflicts
git -C "$container/wt-merge-lane" checkout -q -b merge-side
printf 'side version\n' >"$container/wt-merge-lane/f.txt"
git -C "$container/wt-merge-lane" commit -qam 'side work'
git -C "$container/wt-merge-lane" checkout -q merge-lane
printf 'merge-lane payload\n' >"$container/wt-merge-lane/merge-lane.txt"
printf 'lane version\n' >"$container/wt-merge-lane/f.txt"
git -C "$container/wt-merge-lane" add merge-lane.txt f.txt
git -C "$container/wt-merge-lane" commit -qm 'merge-lane work'
# land both patches on main, restoring f.txt between them so each applies clean
land_equivalent merge-lane
git -C "$container/main" show "$merge_lane_base:f.txt" >"$container/main/f.txt"
git -C "$container/main" commit -qam 'main restores f.txt'
git -C "$container/main" cherry-pick "$(git -C "$container/main" rev-parse merge-side)" >/dev/null
git -C "$container/wt-merge-lane" merge --no-ff --no-edit merge-side >/dev/null 2>&1 || true
printf 'evil resolution found nowhere else\n' >"$container/wt-merge-lane/f.txt"
git -C "$container/wt-merge-lane" add f.txt
git -C "$container/wt-merge-lane" commit -qm 'merge merge-side (evil resolution)'
aged "$container/wt-merge-lane"

# 16. a tag whose name equals the lane's branch, pointing at main's tip: bare
#     names resolve tags first, so an unqualified cherry would read "landed".
git -C "$container/main" worktree add -q -b tag-shadow "$container/wt-tag-shadow" main
printf 'tag-shadow unique\n' >"$container/wt-tag-shadow/tag-shadow.txt"
git -C "$container/wt-tag-shadow" add tag-shadow.txt
git -C "$container/wt-tag-shadow" commit -qm 'tag-shadow work'
git -C "$container/main" tag tag-shadow main
aged "$container/wt-tag-shadow"

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
if grep -Fq "would reap: $container/wt-merged-aged (merged-aged)" <<<"$dry_output"; then
  check "--dry-run reports would-reap for the merged lane" 0
else
  check "--dry-run reports would-reap for the merged lane" 1
fi
[ -d "$container/wt-merged-aged" ] \
  && check "--dry-run left the aged merged worktree in place" 0 \
  || check "--dry-run left the aged merged worktree in place" 1

# --- the real sweep --------------------------------------------------------
set +e
output="$(cd "$container" && "$TARGET" 2>&1)"
status=$?
set -e
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
live_pid=''
check "wt-reap exits 0" "$status"

# 1. fresh merged tree is held before the ancestor reap path
if [ -d "$container/wt-merged-fresh" ]; then
  check "fresh merged worktree kept" 0
else
  check "fresh merged worktree kept" 1
fi
if grep -Fq "kept: fresh (merged-fresh) ($container/wt-merged-fresh)" <<<"$output"; then
  check "fresh merged keep has its own reason string" 0
else
  printf '%s\n' "$output" >&2
  check "fresh merged keep has its own reason string" 1
fi

# 2. aged merged + clean
[ ! -d "$container/wt-merged-aged" ] \
  && check "aged merged+clean worktree reaped" 0 \
  || check "aged merged+clean worktree reaped" 1
assert_not_ok "merged-aged branch deleted" \
  git -C "$container/main" rev-parse --verify merged-aged
if grep -Fq "reaped: $container/wt-merged-aged (merged-aged)" <<<"$output"; then
  check "merged reap reported in the original format" 0
else
  printf '%s\n' "$output" >&2
  check "merged reap reported in the original format" 1
fi

# 3-5. ordinary merged protections
for protected in rescue-merged merged-locked merged-live; do
  if [ -d "$container/wt-$protected" ]; then
    check "aged $protected worktree kept" 0
  else
    check "aged $protected worktree kept" 1
  fi
done
for expectation in \
  "kept: rescue (rescue-merged) ($container/wt-rescue-merged)" \
  "kept: locked (merged-locked) ($container/wt-merged-locked)" \
  "kept: live cwd (merged-live) ($container/wt-merged-live)"; do
  if grep -Fq "$expectation" <<<"$output"; then
    check "ordinary merged protection reported: ${expectation%% (*}" 0
  else
    printf '%s\n' "$output" >&2
    check "ordinary merged protection reported: ${expectation%% (*}" 1
  fi
done

# 6. patch-equivalent + aged
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

# 7. equivalent but fresh
[ -d "$container/wt-equiv-fresh" ] \
  && check "equivalent+fresh worktree kept" 0 \
  || check "equivalent+fresh worktree kept" 1
if grep -Fq "kept: fresh (equiv-fresh)" <<<"$output"; then
  check "fresh keep has its own reason string" 0
else
  printf '%s\n' "$output" >&2
  check "fresh keep has its own reason string" 1
fi

# 8. dirty tracked change
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

# 9. untracked file present
[ -d "$container/wt-untracked" ] \
  && check "untracked-only worktree kept" 0 \
  || check "untracked-only worktree kept" 1
if grep -Fq "kept: dirty ($container/wt-untracked)" <<<"$output"; then
  check "untracked file counts as unclean" 0
else
  printf '%s\n' "$output" >&2
  check "untracked file counts as unclean" 1
fi

# 10. rescue-*
[ -d "$container/wt-rescue-test" ] \
  && check "rescue-* worktree kept" 0 \
  || check "rescue-* worktree kept" 1
assert_ok "rescue-test branch not deleted" \
  git -C "$container/main" rev-parse --verify rescue-test

# 11. genuinely unique commit
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

# 12. locked
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

# 14. equiv + aged, holding an ignored file
[ -d "$container/wt-equiv-ignored" ] \
  && check "equivalent lane with ignored files kept" 0 \
  || check "equivalent lane with ignored files kept" 1
assert_ok "equiv-ignored branch not deleted" \
  git -C "$container/main" rev-parse --verify equiv-ignored
if grep -Fq "kept: ignored files (docs/private/note.md, 1 total) ($container/wt-equiv-ignored)" <<<"$output"; then
  check "ignored keep names the first survivor and the count" 0
else
  printf '%s\n' "$output" >&2
  check "ignored keep names the first survivor and the count" 1
fi

# 15. cherry-equivalent commits plus an evil merge
merge_lane_cherry_plus() {
  git -C "$container/main" cherry refs/heads/main refs/heads/merge-lane | grep -q '^+'
}
assert_not_ok "merge-lane's non-merge commits are all cherry-equivalent (isolates the merge gate)" \
  merge_lane_cherry_plus
merge_lane_merges=$(git -C "$container/main" rev-list --merges refs/heads/main..refs/heads/merge-lane 2>/dev/null) \
  || merge_lane_merges=""
[ -n "$merge_lane_merges" ] \
  && check "merge-lane is ahead by a merge commit" 0 \
  || check "merge-lane is ahead by a merge commit" 1
[ -d "$container/wt-merge-lane" ] \
  && check "lane carrying a merge commit kept" 0 \
  || check "lane carrying a merge commit kept" 1
assert_ok "merge-lane branch not deleted" \
  git -C "$container/main" rev-parse --verify refs/heads/merge-lane
if grep -Fq 'kept: unmerged (merge-lane,' <<<"$output"; then
  check "merge-carrying lane kept as unmerged" 0
else
  printf '%s\n' "$output" >&2
  check "merge-carrying lane kept as unmerged" 1
fi

# 16. tag shadowing the lane's branch name
[ -d "$container/wt-tag-shadow" ] \
  && check "tag-shadowed lane kept" 0 \
  || check "tag-shadowed lane kept" 1
assert_ok "tag-shadow branch not deleted" \
  git -C "$container/main" rev-parse --verify refs/heads/tag-shadow
assert_ok "tag-shadow tag still present" \
  git -C "$container/main" rev-parse --verify refs/tags/tag-shadow
if grep -Fq 'kept: unmerged (tag-shadow,' <<<"$output"; then
  check "tag-shadowed lane kept as unmerged" 0
else
  printf '%s\n' "$output" >&2
  check "tag-shadowed lane kept as unmerged" 1
fi

# --- second sweep: only the irreplaceable ignored file was holding case 10 --
rm "$container/wt-equiv-ignored/docs/private/note.md"
rmdir "$container/wt-equiv-ignored/docs/private" "$container/wt-equiv-ignored/docs"
second="$(cd "$container" && "$TARGET" 2>&1)"
[ ! -d "$container/wt-equiv-ignored" ] \
  && check "disposable ignored files alone do not block the reap" 0 \
  || check "disposable ignored files alone do not block the reap" 1
assert_not_ok "equiv-ignored branch deleted once the notes were gone" \
  git -C "$container/main" rev-parse --verify equiv-ignored
if grep -Fq "reaped (equiv): $container/wt-equiv-ignored (equiv-ignored was $equiv_ignored_sha)" <<<"$second"; then
  check "second sweep reports the equiv reap" 0
else
  printf '%s\n' "$second" >&2
  check "second sweep reports the equiv reap" 1
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
aged "$all_root/code/projA/wt-done"

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
