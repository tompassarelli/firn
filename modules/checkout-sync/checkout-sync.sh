#!/usr/bin/env bash
set -uo pipefail
synced=0 skipped=0 failed=0
for dir in "$HOME"/code/*/main; do
  [ -e "$dir/.git" ] || continue
  name=${dir#"$HOME"/code/}
  branch=$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  if [ "$branch" != main ] || [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
    echo "skip $name: not a clean main checkout"; skipped=$((skipped + 1)); continue
  fi
  if git -C "$dir" fetch --quiet origin main && git -C "$dir" merge --ff-only --quiet origin/main; then
    synced=$((synced + 1))
  else
    echo "fail $name: fetch or fast-forward failed"; failed=$((failed + 1))
  fi
done
echo "checkout-sync: synced=$synced skipped=$skipped failed=$failed"
