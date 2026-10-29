#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/update-notify-test.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT

mkdir -p "$scratch/bin"
cat >"$scratch/bin/notify-send" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NOTIFIED"
wc -l <"$NOTIFIED"
FAKE
chmod +x "$scratch/bin/notify-send"
export PATH="$scratch/bin:$PATH" XDG_STATE_HOME="$scratch/state" NOTIFIED="$scratch/notified"
: >"$NOTIFIED"

pass=0
fail_count=0
check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'PASS: %s\n' "$1"
    pass=$((pass + 1))
  else
    printf 'FAIL: %s: expected %s, got %s\n' "$1" "$2" "$3" >&2
    fail_count=$((fail_count + 1))
  fi
}
count() { grep -c " $1 failed" "$NOTIFIED" || true; }

for _ in 1 2 3 4 5 6 7 8 9 10; do
  "$REPO/dotfiles/bin/update-notify" fleet-relay.service
done
check "ten consecutive failures of one timer notify once" 1 "$(count fleet-relay.service)"

"$REPO/dotfiles/bin/update-notify" pace-enforcement
check "another timer's failure inside that hour still notifies" 1 "$(count pace-enforcement.service)"

printf '%s 1\n' "$(($(date +%s) - 3601))" >"$XDG_STATE_HOME/update-notify/fleet-relay.service"
"$REPO/dotfiles/bin/update-notify" fleet-relay.service
check "a failure an hour after the last notification notifies again" 2 "$(count fleet-relay.service)"
check "the later notification replaces the unit's earlier one" 1 "$(tail -n 1 "$NOTIFIED" | grep -c -- '--replace-id=1 ')"

printf '#!/usr/bin/env bash\necho "no D-Bus" >&2\nexit 1\n' >"$scratch/bin/notify-send"
if "$REPO/dotfiles/bin/update-notify" headless.service 2>"$scratch/err"; then headless=0; else headless=$?; fi
check "a host with no notification daemon leaves the notifier unit green" 0 "$headless"
check "the missing daemon is named in the journal" 1 "$(grep -c 'no notification daemon; headless.service failed' "$scratch/err")"

printf '%s passed, %s failed\n' "$pass" "$fail_count"
[ "$fail_count" -eq 0 ]
