#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$here/nexus-checks.sh"

expect() {
  local healthy=$1 result=$2
  if [[ "$healthy" == true ]]; then
    [[ "$result" == ok ]] || return 1
  else
    [[ -n "$result" && "$result" != ok ]] || return 1
  fi
}

login=$(cat "$here/../../native/fixtures/openssh-10.5p1-2026-10-11-login.txt")
session=$(cat "$here/../../native/fixtures/systemd-loginctl-260.5-2026-10-11-sessions.txt")
expect true "$(check_logins "$login" "" 'peer-fixture=known' 'SHA256:fixture' "")"
expect false "$(check_logins "$login" "" 'peer-fixture=known' 'SHA256:other' "")"
expect false "$(check_logins "$login" "" "" 'SHA256:fixture' "")"
expect false "$(check_logins "" "$session" "" "" "")"
expect true "$(check_logins "" "$session" "" "" fixture-session)"
expect true "$(check_units "" "")"
expect false "$(check_units 'fixture.service loaded failed failed fixture' "")"
expect true "$(check_backup '' 946684800)"
expect true "$(check_lynis '' '' 80 baseline)"

property() {
  local seed=$1 now days percent hours previous_index current_index previous_ids current_ids unexpected healthy
  days=$((seed % 15))
  now=$((946684800 + days * 86400))
  expect "$([[ "$days" -le 7 ]] && echo true || echo false)" \
    "$(check_updates '26.05.20000101.fixture' /same /same "$now" "$now")" || return 1
  hours=$((seed % 100))
  expect "$([[ "$hours" -le 48 ]] && echo true || echo false)" \
    "$(check_updates '26.05.20000101.fixture' /old /new "$((946684800 - hours * 3600))" 946684800)" || return 1
  percent=$((seed % 101))
  expect "$([[ "$percent" -le 80 ]] && echo true || echo false)" \
    "$(check_disk " $percent%")" || return 1
  expect "$([[ "$hours" -lt 26 ]] && echo true || echo false)" \
    "$(check_backup "$((946684800 - hours * 3600))" 946684800)" || return 1
  previous_index=$((seed % 101))
  current_index=$(((seed / 101) % 101))
  previous_ids="warning-$((seed % 4)) warning-$(((seed / 101) % 4))"
  current_ids="warning-$(((seed / 7) % 4)) warning-$(((seed / 13) % 4))"
  unexpected=false
  for id in $current_ids; do
    [[ " $previous_ids " == *" $id "* ]] || unexpected=true
  done
  healthy=false
  if ((current_index >= previous_index)) && [[ "$unexpected" == false ]]; then healthy=true; fi
  expect "$healthy" "$(check_lynis "$previous_index" "$previous_ids" "$current_index" "$current_ids")" || return 1
  # apply reads the action/status/timestamp fields from decide.
  [[ "$(decide ok 0 ok "$now")" == 'none ok 0' ]] || return 1
  [[ "$(decide fail 0 ok "$now")" == 'recover ok 0' ]] || return 1
  [[ "$(decide ok 0 failure "$now")" == "alert fail $now" ]] || return 1
  [[ "$(decide fail "$now" failure "$now")" == "none fail $now" ]] || return 1
  [[ "$(decide fail "$((now - 86400))" failure "$now")" == "alert fail $now" ]] || return 1
}

samples=128
[[ -z "${CI:-}" ]] || samples=512
seed=73421
for ((index=0; index<samples; index++)); do
  property "$seed" || { printf 'FAIL Nexus health property seed=%s\n' "$seed" >&2; exit 1; }
  seed=$((seed * 48271 % 2147483647))
done
printf 'ok: Nexus health property cases=1 generated=%s plus recorded login/session references\n' "$samples"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
for ((sample=0; sample<64; sample++)); do
  age=$((sample * 8191))
  jq -n --argjson stamp "$((2000000000 - age))" '{root:"root",nodes:{root:{inputs:{nixpkgs:"selected",other:"decoy"}},selected:{locked:{lastModified:$stamp}},decoy:{locked:{lastModified:2000000000}}}}' > "$work/flake.lock"
  expect "$([[ "$age" -le 259200 ]] && echo true || echo false)" "$(check_lock "$work/flake.lock" 2000000000)"
  until=$(date -u -d 2026-12-31 +%s)
  remaining=$((sample - 16))
  expect "$([[ "$remaining" -ge 30 ]] && echo true || echo false)" "$(check_release 26.05.fixture "$((until - remaining * 86400))")"
done
expect false "$(check_lock "$work/missing.lock" 2000000000)"
expect false "$(check_release 99.99.fixture 2000000000)"
printf 'ok: direct selected lock freshness and official NixOS 26.05 support deadline properties (64 generated cases)\n'

alerts=0
nexus-alert() { alerts=$((alerts + 1)); }
SECURITY_LOCK="$work/flake.lock"
CHECKS=lock
jq -n '{root:"root",nodes:{root:{inputs:{nixpkgs:"selected"}},selected:{locked:{lastModified:1}}}}' > "$SECURITY_LOCK"
if run_checks "$work" >/dev/null; then echo 'stale selected lock did not fail the owning job' >&2; exit 1; fi
[[ "$alerts" == 1 && "$(cat "$work/status")" == fail:lock ]]
if run_checks "$work" >/dev/null; then exit 1; fi
[[ "$alerts" == 1 ]]
jq -n --argjson now "$(date +%s)" '{root:"root",nodes:{root:{inputs:{nixpkgs:"selected"}},selected:{locked:{lastModified:$now}}}}' > "$SECURITY_LOCK"
run_checks "$work" >/dev/null
[[ "$alerts" == 2 && "$(cat "$work/status")" == ok ]]
printf 'ok: stale-lock owning job fails, deduplicates and recovers\n'

nix build --impure --no-link --json --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    config.myConfig.modules = {
      nexus-alerts.enable = true;
      nexus-checks.enable = true;
      nexus-vulnix.enable = true;
    };
    module = name: (import (./modules + "/${name}/default.nix") {
      inherit config pkgs;
      lib = pkgs.lib;
      jobRun = name: command: command;
    }).config.content.systemd.packages;
  in pkgs.symlinkJoin {
    name = "nexus-notification-dropins";
    paths = builtins.concatLists (map module ["nexus-alerts" "nexus-checks" "nexus-vulnix"]);
  }
' > "$work/dropins.json"
root="$work/systemd-root"
mkdir -p "$root/etc/systemd/system"
cp -rL --no-preserve=mode "$(jq -r '.[0].outputs.out' "$work/dropins.json")/lib/systemd/system/." "$root/etc/systemd/system/"
printf '#!/bin/sh\nexit 0\n' > "$root/fixture"
chmod +x "$root/fixture"
for unit in nexus-checks nexus-vulnix control 'nexus-notify@'; do
  printf '[Unit]\nDefaultDependencies=no\n[Service]\nType=oneshot\nExecStart=/fixture\n' > "$root/etc/systemd/system/$unit.service"
done
SYSTEMD_LOG_LEVEL=debug systemd-analyze verify --root="$root" --generators=no \
  nexus-checks.service nexus-vulnix.service control.service > "$work/systemd-parse.log" 2>&1
python3 - "$work/systemd-parse.log" <<'PYTHON'
from pathlib import Path
import re
import sys
log = Path(sys.argv[1]).read_text()
for name in ("nexus-checks", "nexus-vulnix", "control"):
    match = re.search(r"→ Unit " + name + r"\.service:\n(.*?)(?=\n\s*→ Unit |\Z)", log, re.S)
    assert match, f"systemd did not parse {name}"
    failures = re.findall(r"^\s*OnFailure: (.*)$", match[1], re.M)
    assert bool(failures) == (name == "control"), (name, failures)
print("ok: systemd type-wide notification remains on control and is masked for both deduplicating jobs")
PYTHON
