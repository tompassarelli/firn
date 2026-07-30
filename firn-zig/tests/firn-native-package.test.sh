#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
system="${FIRN_TEST_SYSTEM:-x86_64-linux}"
package_attr="$repo_root#packages.$system.firn-native"

fail() {
  echo "firn native package test: $*" >&2
  exit 1
}

if ! package_out="$(nix eval --raw "$package_attr.outPath" 2>/dev/null)"; then
  fail "flake does not expose packages.$system.firn-native"
fi

system_packages="$(
  nix eval --json \
    "$repo_root#nixosConfigurations.whiterabbit.config.environment.systemPackages" \
    --apply 'packages: map (package: toString package) packages'
)"
jq -e --arg package "$package_out" 'index($package) != null' \
  <<<"$system_packages" >/dev/null \
  || fail "whiterabbit does not install $package_out"

grep -Fq "NATIVE_BIN=\"\${FIRN_NATIVE_BIN:-/run/current-system/sw/bin/firn-native}\"" \
  "$repo_root/dotfiles/bin/firn" \
  || fail "firn wrapper does not default to the installed native binary"

built_path="$(nix build --no-link --print-out-paths "$repo_root#firn-native")"
[ "$built_path" = "$package_out" ] \
  || fail "built output $built_path differs from evaluated output $package_out"
[ -x "$built_path/bin/firn-native" ] \
  || fail "built output lacks executable bin/firn-native"

status=0
"$built_path/bin/firn-native" || status=$?
[ "$status" -eq 2 ] \
  || fail "built native driver exited $status for unsupported empty command"

echo "firn native package test: ok"
