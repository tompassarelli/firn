#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
for unit in lane-gc lane-gc-remote; do
  method=$(nix eval --raw "$root#nixosConfigurations.whiterabbit.config.home-manager.users.tom.systemd.user.services.$unit.Unit.X-SwitchMethod")
  [[ "$method" == keep-old ]] || { printf 'FAIL: %s switches with %s; a restarted oneshot blocks activation\n' "$unit" "$method" >&2; exit 1; }
done
printf 'ok: activation leaves the lane-gc oneshots running instead of restarting them\n'
