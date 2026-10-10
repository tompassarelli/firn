#!/usr/bin/env bash
# Recorded scenario through the credit-floor core: show instances and show
# ssh-keys as recorded on 2026-10-10 with the runner VM up. No-op at $9, one
# warning on crossing $5, teardown order at $2.50, re-arm after a top-up.
set -uo pipefail
target="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vast-reaper"
pass=0 fail=0
check() { if [ "$1" = "$2" ]; then pass=$((pass + 1)); printf 'PASS  %s\n' "$3"; else fail=$((fail + 1)); printf 'FAIL  %s\n      got:  %s\n      want: %s\n' "$3" "$1" "$2"; fi; }
insts='[{"id":55161577,"label":"vast-launch-check","actual_status":"running","dph_total":0.3518518518518518},{"id":7,"label":"vast-job-whiterabbit-42-1999999999-ab12","actual_status":"running"}]'
keys='[{"id":1531483,"public_key":"ssh-ed25519 AAAAC3Nza vast-launch-check"},{"id":9,"public_key":"ssh-ed25519 AAAAC3Nzb vast-job-whiterabbit-42-ab12"}]'
decide() { printf '{"credit":%s,"instances":%s,"keys":%s,"state":%s}' "$1" "${3:-$insts}" "$keys" "$2" | bun "$target" floor-decide | jq -c "$4"; }
kinds='[.actions[].kind]'

check "$(decide 9.28 '{"warned":false}' "$insts" '[.actions, .state]')" '[[],{"warned":false}]' 'no-op at $9.28'
check "$(decide 5.00 '{"warned":false}' "$insts" "$kinds")" '["warn"]' 'warn once at $5.00'
check "$(decide 4.10 '{"warned":true}' "$insts" "$kinds")" '[]' 'no repeat warning below $5 in the same crossing'
check "$(decide 2.50 '{"warned":true}' "$insts" '[.actions[] | [.kind, (.id // .repos)]]')" '[["unset-farm-runner",["tompassarelli/smashcraft","tompassarelli/wisp"]],["destroy",55161577],["delete-key",1531483]]' 'teardown at $2.50: variable, then runner VM only, then its key only'
check "$(decide 2.40 '{"warned":false}' "$insts" "$kinds")" '["warn","unset-farm-runner","destroy","delete-key"]' 'jump straight below $2.50 still warns first'
check "$(decide 2.00 '{"warned":true}' '[]' "$kinds")" '["delete-key"]' 'runner gone: only the leftover key'
check "$(decide 9.00 '{"warned":true}' "$insts" '.state.warned')" 'false' 'top-up re-arms the warning'
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
