#!/usr/bin/env bash
set -euo pipefail

target="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lane-gc"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/lane-gc-test.XXXXXX")"
sleeper=""
trap '[ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null; rm -rf "${scratch:?}"' EXIT
root="$scratch/code"
main="$root/proj/main"
lanes="$root/proj/worktrees"
mkdir -p "$lanes"
git init -q --bare -b main "$scratch/origin.git"
git init -q -b main "$main"
git -C "$main" config user.name lane-gc-test
git -C "$main" config user.email lane-gc-test@example.invalid
git -C "$main" remote add origin "$scratch/origin.git"
git -C "$main" commit -q --allow-empty -m base
git -C "$main" push -q -u origin main

lane() { git -C "$main" worktree add -q -b "$1" "$lanes/$1" main; }
commit() { printf '%s\n' "$2" >"$lanes/$1/$2"; git -C "$lanes/$1" add "$2"; git -C "$lanes/$1" commit -qm "$2 Refs proj#7"; }

lane merged; commit merged landed.txt
git -C "$lanes/merged" push -q origin merged:main merged:claude/merged
git -C "$main" pull -q --ff-only origin main
lane cherry; commit cherry picked.txt
git -C "$main" cherry-pick cherry >/dev/null
git -C "$main" push -q origin main
lane unique; commit unique work.txt
lane dirty; printf 'wip\n' >"$lanes/dirty/scratch.txt"
lane live; (cd "$lanes/live" && exec sleep 300) & sleeper=$!
git -C "$main" branch stale-merged main
git -C "$main" branch stale-unique unique

out="$("$target" --root "$root" --idle-hours 0 --state "$scratch/unlanded.txt")"
fail=0
check() { if eval "$2"; then :; else printf 'FAIL: %s\n%s\n' "$1" "$out" >&2; fail=1; fi; }
check "merged+clean worktree retired" '[ ! -e "$lanes/merged" ] && ! git -C "$main" rev-parse -q --verify refs/heads/merged >/dev/null'
check "patch-equivalent worktree retired" '[ ! -e "$lanes/cherry" ]'
check "unique commit kept" '[ -e "$lanes/unique" ] && git -C "$main" rev-parse -q --verify refs/heads/stale-unique >/dev/null'
check "dirty kept" '[ -e "$lanes/dirty/scratch.txt" ]'
check "live cwd kept" '[ -e "$lanes/live" ]'
check "merged branch without worktree deleted" '! git -C "$main" rev-parse -q --verify refs/heads/stale-merged >/dev/null'
check "merged origin claude branch deleted" '! git -C "$scratch/origin.git" rev-parse -q --verify refs/heads/claude/merged >/dev/null'
check "unlanded report lists unique with ref" 'grep -P "\tunique\t\+1\t-\twork.txt Refs proj#7\tproj#7" "$scratch/unlanded.txt" >/dev/null'
check "unlanded report lists dirty" 'grep -P "/dirty\tdirty\t\+0\tdirty\t" "$scratch/unlanded.txt" >/dev/null'
[ "$fail" -eq 0 ] && echo "lane-gc.test: ok"
exit "$fail"
