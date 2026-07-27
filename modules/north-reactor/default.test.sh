#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
source_module=$here/default.bnix
generated_module=$here/default.nix

grep -Fq ':restartIfChanged false' "$source_module"
grep -Fq 'restartIfChanged = false;' "$generated_module"
grep -Fq 'pkgs.git "/bin"' "$source_module"
# This assertion intentionally matches literal Nix interpolation syntax.
# shellcheck disable=SC2016
grep -Fq 'PATH=${pkgs.babashka}/bin:${pkgs.coreutils}/bin:${pkgs.git}/bin' \
  "$generated_module"

printf 'ok: north-reactor-sweep does not restart on Home Manager unit changes and resolves git at runtime\n'
