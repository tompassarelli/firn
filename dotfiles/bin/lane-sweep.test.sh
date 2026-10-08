#!/usr/bin/env bash
# Scratch container for lane-sweep: an idle dirty lane is archived, removed and
# restorable; an active lane is kept; an idle unlanded branch is archived and
# deleted; the bundle verifies.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
sweep=$repo/dotfiles/bin/lane-sweep
scratch=$(mktemp -d "${TMPDIR:-/tmp}/lane-sweep-test.XXXXXX")
trap 'rm -rf "${scratch:?}"' EXIT
export GIT_CONFIG_GLOBAL=$scratch/gitconfig GIT_CONFIG_NOSYSTEM=1
git config --global user.name t
git config --global user.email t@example.invalid
git config --global init.defaultBranch main

fail=0
check() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

backdate() { # set every mtime under the given paths to three days ago
  python3 - "$@" <<'PY'
import os, sys, time
t = time.time() - 3 * 86400
for root in sys.argv[1:]:
    for d, dirs, files in os.walk(root):
        for n in dirs + files:
            os.utime(os.path.join(d, n), (t, t), follow_symlinks=False)
    os.utime(root, (t, t), follow_symlinks=False)
PY
}

c=$scratch/code/proj
mkdir -p "$c/worktrees"
git init -q "$c/main"
echo base >"$c/main/a.txt"
printf 'node_modules/\nnotes/\n' >"$c/main/.gitignore"
git -C "$c/main" add a.txt .gitignore
git -C "$c/main" commit -qm base

old="$(date -d '3 days ago' -R)"
git -C "$c/main" worktree add -q "$c/worktrees/idle-12" -b idle-12
echo edited >"$c/worktrees/idle-12/a.txt"
echo new >"$c/worktrees/idle-12/untracked.txt"
mkdir -p "$c/worktrees/idle-12/notes" "$c/worktrees/idle-12/node_modules"
echo private >"$c/worktrees/idle-12/notes/handoff.md"
echo dep >"$c/worktrees/idle-12/node_modules/dep.js"

git -C "$c/main" worktree add -q "$c/worktrees/active" -b active
echo wip >"$c/worktrees/active/wip.txt"

git -C "$c/main" branch stale
git -C "$c/main" worktree add -q "$c/worktrees/tmp" stale
echo s >"$c/worktrees/tmp/s.txt"
git -C "$c/worktrees/tmp" add s.txt
GIT_COMMITTER_DATE=$old GIT_AUTHOR_DATE=$old git -C "$c/worktrees/tmp" commit -qm "stale work"
git -C "$c/main" worktree remove "$c/worktrees/tmp"
stale_tip=$(git -C "$c/main" rev-parse stale)

backdate "$c/worktrees/idle-12" "$c/main/.git"

out=$("$sweep" --root "$scratch/code" --archive-dir "$scratch/archive" --no-github --date 20260101 2>&1) || {
  echo "$out"; exit 1; }
echo "$out"

r=refs/archive/20260101
check "idle dirty lane removed" '[ ! -e "$c/worktrees/idle-12" ] && ! git -C "$c/main" rev-parse -q --verify refs/heads/idle-12 >/dev/null'
check "idle lane archived" 'git -C "$c/main" cat-file -e "$r/idle-12^{commit}"'
check "active lane kept" '[ -f "$c/worktrees/active/wip.txt" ] && git -C "$c/main" rev-parse -q --verify refs/heads/active >/dev/null'
check "active lane not archived" '! git -C "$c/main" rev-parse -q --verify "$r/active" >/dev/null'
check "unlanded branch archived at its tip" '[ "$(git -C "$c/main" rev-parse "$r/stale")" = "$stale_tip" ]'
check "unlanded branch deleted" '! git -C "$c/main" rev-parse -q --verify refs/heads/stale >/dev/null'
check "bundle verifies" 'git -C "$c/main" bundle verify "$scratch/archive/proj-20260101.bundle" >/dev/null 2>&1'

git -C "$c/main" worktree add -q "$c/worktrees/restored" "$r/idle-12"
w=$c/worktrees/restored
check "restore brings back the edit" '[ "$(cat "$w/a.txt")" = edited ]'
check "restore brings back untracked files" '[ "$(cat "$w/untracked.txt")" = new ]'
check "restore brings back ignored notes" '[ "$(cat "$w/notes/handoff.md")" = private ]'
check "dependency caches are not archived" '[ ! -e "$w/node_modules" ]'

exit "$fail"
