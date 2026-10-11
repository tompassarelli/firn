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

property() {
  local seed=$1 peer fingerprint login session now days percent hours
  peer="peer-$seed"
  fingerprint="SHA256:K$seed"
  login="Accepted publickey for fixture$seed from $peer port 4242 ssh2: ED25519 $fingerprint"
  session="s$seed 1000 fixture$seed seat0 737 user tty1 no -"
  expect true "$(check_logins "$login" "" "$peer=known" "$fingerprint" "")" || return 1
  expect false "$(check_logins "$login" "" "$peer=known" "SHA256:other" "")" || return 1
  expect false "$(check_logins "$login" "" "" "$fingerprint" "")" || return 1
  expect false "$(check_logins "" "$session" "" "" "")" || return 1
  expect true "$(check_logins "" "$session" "" "" "s$seed")" || return 1
  expect true "$(check_units "" "")" || return 1
  expect false "$(check_units "u$seed.service loaded failed failed fixture" "")" || return 1
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
  expect true "$(check_backup '' 946684800)" || return 1
  expect true "$(check_lynis 80 "A$seed" 80 "A$seed")" || return 1
  expect false "$(check_lynis 80 "A$seed" 79 "A$seed")" || return 1
  expect false "$(check_lynis 80 "A$seed" 80 "A$seed B$seed")" || return 1
  expect true "$(check_lynis '' '' 80 "A$seed")" || return 1
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
printf 'ok: Nexus health property cases=1 generated=%s\n' "$samples"
