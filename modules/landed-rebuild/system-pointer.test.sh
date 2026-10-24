#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rg -q 'systemPointer = "/etc/firn-landed-rebuild/system-flake";' "$here/default.nix"
rg -q 'serve .*\$\{environmentSwitch\} \$\{systemPointer\}"' "$here/default.nix"
rg -q '"firn-landed-rebuild/system-flake"\.source = systemSource;' "$here/default.nix"
rg -q 'os\.path\.realpath\(system_source\)' "$here/landed-rebuild.py"
echo "ok: the service resolves the installed south flake from the switched /etc link on each request"
