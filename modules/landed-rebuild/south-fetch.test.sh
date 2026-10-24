#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
git init -q -b main "$work/south"
echo old >"$work/south/flake.nix"
git -C "$work/south" add flake.nix
git -C "$work/south" commit -qm old
git clone -q "$work/south" "$work/checkout"
echo module >"$work/south/smashcraft-store-sync.nix"
git -C "$work/south" add smashcraft-store-sync.nix
git -C "$work/south" commit -qm module
python3 -I -c '
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("landed", sys.argv[1])
landed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(landed)
landed.prepare_system(Path(sys.argv[2]), Path(sys.argv[3]), [])
' "$here/landed-rebuild.py" "$work/checkout" "$work/system"
test "$(cat "$work/system/smashcraft-store-sync.nix")" = module
test "$(git -C "$work/system" rev-parse HEAD)" = "$(git -C "$work/south" rev-parse HEAD)"
echo "ok: a landed rebuild builds south as of origin/main at request time, including modules landed after the checkout last fetched"
