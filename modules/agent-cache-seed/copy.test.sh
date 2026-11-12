#!/usr/bin/env bash
set -eu
here=$(cd "$(dirname "$0")" && pwd)
copy=$here/copy.sh
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
home=$work/home
outside=$work/outside
mkdir -p "$home" "$outside" "$work/source/registry"
printf 'crate\n' >"$work/source/registry/crate"
bash "$copy" "$home" "$work/source/registry" "$home/.cargo/registry"
[ -f "$home/.cargo/registry/crate" ] || { echo "a plain destination was not seeded"; exit 1; }
ln -s "$outside" "$home/.cache"
if bash "$copy" "$home" "$work/source/registry" "$home/.cache/registry" 2>/dev/null; then
  echo "a symbolic link parent was followed"
  exit 1
fi
[ -z "$(ls -A "$outside")" ] || { echo "a copy was written through a symbolic link parent"; exit 1; }
