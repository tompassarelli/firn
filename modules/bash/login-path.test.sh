#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)

path=$(env -i HOME=/home/test PATH=/opt/sys/bin:/usr/bin "$BASH" --noprofile --norc -c ". '$here/login-path.sh'; printf %s \"\$PATH\"")
want=/home/test/.local/bin:/opt/sys/bin:/usr/bin:/home/test/.local/share/firn/bin:/home/test/.local/share/north/bin:/home/test/.local/share/south/bin
[ "$path" = "$want" ] || { printf 'login PATH is\n  %s\nwant\n  %s\n' "$path" "$want" >&2; exit 1; }

again=$(env -i HOME=/home/test PATH="$path" "$BASH" --noprofile --norc -c ". '$here/login-path.sh'; printf %s \"\$PATH\"")
[ "$again" = "$want" ] || { printf 'sourcing twice changed PATH to %s\n' "$again" >&2; exit 1; }

grep -q 'builtins.readFile ./login-path.sh' "$here/default.nix" || { printf 'default.nix does not source login-path.sh into bashrcExtra\n' >&2; exit 1; }
