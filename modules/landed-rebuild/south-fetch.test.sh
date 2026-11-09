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
echo module >"$work/south/makgora-store-sync.nix"
git -C "$work/south" add makgora-store-sync.nix
git -C "$work/south" commit -qm module
echo planted >"$work/checkout/flake.nix"
git -C "$work/checkout" commit -qam planted
git -C "$work/checkout" update-ref refs/remotes/origin/main HEAD
python3 -I -c '
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("landed", sys.argv[1])
landed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(landed)
mirror = Path(sys.argv[3]) / "mirror"
landed.materialize(mirror, landed.fetch_main(mirror, sys.argv[2]), Path(sys.argv[3]) / "system")
' "$here/landed-rebuild.py" "$work/south" "$work"
test "$(cat "$work/system/makgora-store-sync.nix")" = module
test "$(cat "$work/system/flake.nix")" = old
test "$(git -C "$work/system" rev-parse HEAD)" = "$(git -C "$work/south" rev-parse HEAD)"
echo "ok: a landed rebuild builds the system flake as of its origin's main at request time, and a commit planted in a login user's checkout does not reach it"
