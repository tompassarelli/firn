#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/firn-source-hash"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts/firn-cmds"
mkdir -p "$TMP/beagle/bin" "$TMP/beagle/beagle-lib/private"
printf '#lang racket/base\n' >"$TMP/scripts/firn.rkt"
printf '#!/usr/bin/env bash\n# recipe-v1\n' >"$TMP/scripts/firn-build-bin"
cp "$SCRIPT" "$TMP/scripts/firn-source-hash"
printf '#lang racket/base\n' >"$TMP/scripts/firn-cmds/a.rkt"
printf '#lang racket/base\n' >"$TMP/beagle/beagle-lib/private/parse.rkt"
printf 'toolchain-v1\n' >"$TMP/beagle/bin/_beagle-racket"
printf '{}\n' >"$TMP/beagle/flake.lock"
printf '{}\n' >"$TMP/beagle/flake.nix"

hash() { FIRN_REPO="$TMP" BEAGLE_PATH="$TMP/beagle" "$SCRIPT"; }
first="$(hash)"
second="$(hash)"
[ "$first" = "$second" ]
printf '(define changed #t)\n' >>"$TMP/scripts/firn-cmds/a.rkt"
third="$(hash)"
[ "$first" != "$third" ]

# A changed compilation recipe must rotate the immutable cache key even when
# the Racket source graph itself is unchanged.
before_recipe="$(hash)"
printf '# recipe-v2\n' >>"$TMP/scripts/firn-build-bin"
after_recipe="$(hash)"
[ "$before_recipe" != "$after_recipe" ]

# Dependency-only source and toolchain changes must each invalidate Firn.
before_dependency="$(hash)"
printf '(define dependency-changed #t)\n' >>"$TMP/beagle/beagle-lib/private/parse.rkt"
after_dependency="$(hash)"
[ "$before_dependency" != "$after_dependency" ]
printf 'toolchain-v2\n' >>"$TMP/beagle/bin/_beagle-racket"
after_toolchain="$(hash)"
[ "$after_dependency" != "$after_toolchain" ]
printf '{"pin":2}\n' >"$TMP/beagle/flake.lock"
after_pin="$(hash)"
[ "$after_toolchain" != "$after_pin" ]

printf 'ok: firn-source-hash\n'
