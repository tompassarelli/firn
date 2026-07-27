#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
source_module=$here/default.bnix
generated_module=$here/default.nix

# Home Manager's pinned systemd module interprets keep-old as leaving an
# active unit alone while installing its replacement definition.
grep -Fq ':X-SwitchMethod "keep-old"' "$source_module"
grep -Fq 'X-SwitchMethod = "keep-old";' "$generated_module"

printf 'ok: north-stream-sync keeps an in-flight oneshot out of Home Manager activation\n'
