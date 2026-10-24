#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q repo
git -C "$work/repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m tip
sha="$(git -C "$work/repo" rev-parse HEAD)"
ln -s system-1384-link "$work/system"
mkdir "$work/bin"
printf '#!/bin/sh\nexit 0\n' > "$work/bin/python3"
chmod +x "$work/bin/python3"
sed "s#/run/current-system/sw/bin/python3#$work/bin/python3#" "$root/dotfiles/bin/firn" > "$work/firn"
FIRN_REPO="$work/repo" FIRN_SYSTEM_PROFILE="$work/system" bash "$work/firn" rebuild --landed "$sha"
test "$(git -C "$work/repo" rev-parse 'gen-1384^{commit}')" = "$sha"
echo "ok: landed rebuild tags the active generation in the requester checkout"
other="$(printf 'f%.0s' {1..40})"
for generation in 1385:"$sha" 1386:"$other"; do
  mkdir -p "$work/system-${generation%%:*}-link/sw/bin"
  printf '#!/bin/sh\necho %s\n' "${generation#*:}" > "$work/system-${generation%%:*}-link/sw/bin/nixos-version"
  chmod +x "$work/system-${generation%%:*}-link/sw/bin/nixos-version"
done
printf '#!/bin/sh\nexit 7\n' > "$work/bin/python3"
for generation in 1385 1386; do
  ln -sfn "system-$generation-link" "$work/system"
  status=0
  FIRN_REPO="$work/repo" FIRN_SYSTEM_PROFILE="$work/system" bash "$work/firn" rebuild --landed "$sha" || status=$?
  test "$status" = 7
done
test "$(git -C "$work/repo" rev-parse 'gen-1385^{commit}')" = "$sha"
! git -C "$work/repo" rev-parse -q --verify gen-1386 >/dev/null
echo "ok: a failed landed rebuild tags a generation it switched to and not one it did not"
