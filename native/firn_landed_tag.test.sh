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
