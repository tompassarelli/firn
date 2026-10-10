CHECKS="logins units updates disk backup"
TITLE_SUFFIX=""

urgency_of() {
  case "$1" in logins|lynis) echo urgent ;; *) echo normal ;; esac
}

check_logins() {
  local accepted=$1 sessions=$2 ips=$3 fps=$4 line ip fp tty seat bad=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ip=$(printf '%s\n' "$line" | sed -nE 's/.* from ([^ ]+) port .*/\1/p')
    fp=$(printf '%s\n' "$line" | grep -oE 'SHA256:[A-Za-z0-9+/=]+' || true)
    if ! printf ' %s ' "$ips" | grep -qF " $ip "; then
      bad="${bad:+$bad; }ssh login from unexpected address ${ip:-unknown}"
    elif [ -z "$fp" ] || ! printf ' %s ' "$fps" | grep -qF " $fp "; then
      bad="${bad:+$bad; }ssh login from $ip with an unknown key ${fp:-(no key)}"
    fi
  done <<<"$accepted"
  while read -r _ _ user seat _ _ tty _; do
    [ -n "${user:-}" ] || continue
    if [ "${seat:--}" != "-" ] || [[ "${tty:--}" == tty* ]]; then
      bad="${bad:+$bad; }console login by $user on ${tty:-$seat}"
    fi
  done <<<"$sessions"
  if [ -n "$bad" ]; then echo "fail: $bad"; else echo "ok"; fi
}

check_units() {
  local system=$1 user=$2 names
  names=$(printf '%s\n%s\n' "$system" "$user" | awk 'NF {print $1}' | paste -sd ' ' -)
  if [ -n "$names" ]; then echo "fail: these services have failed: $names"; else echo "ok"; fi
}

check_updates() {
  local version=$1 booted=$2 current=$3 upgraded=$4 now=$5 stamp nixpkgs_epoch days
  stamp=$(printf '%s\n' "$version" | grep -oE '\.[0-9]{8}\.' | tr -d . || true)
  if [ -z "$stamp" ]; then echo "fail: cannot read the nixpkgs date from version $version"; return; fi
  nixpkgs_epoch=$(date -u -d "$stamp" +%s)
  days=$(( (now - nixpkgs_epoch) / 86400 ))
  if [ "$days" -gt 7 ]; then
    echo "fail: the running system's nixpkgs is $days days old (from $stamp); the nightly upgrade is not landing"
  elif [ "$booted" != "$current" ] && [ $(( now - upgraded )) -gt $(( 48 * 3600 )) ]; then
    echo "fail: an upgrade installed $(( (now - upgraded) / 3600 )) hours ago is still waiting for a reboot"
  else
    echo "ok"
  fi
}

check_disk() {
  local pct=${1//[ %]/}
  if [ "$pct" -gt 80 ]; then echo "fail: the root disk is $pct% full (limit 80%)"; else echo "ok"; fi
}

check_backup() {
  local marker=$1 now=$2 hours
  if [ -z "$marker" ]; then echo "ok"; return; fi
  hours=$(( (now - marker) / 3600 ))
  if [ "$hours" -ge 26 ]; then echo "fail: the last successful backup was $hours hours ago (limit 26)"; else echo "ok"; fi
}

check_lynis() {
  local prev_index=$1 prev_ids=$2 index=$3 ids=$4 new bad=""
  if [ -n "$prev_index" ] && [ "$index" -lt "$prev_index" ]; then
    bad="hardening index dropped from $prev_index to $index"
  fi
  new=$(comm -13 <(printf '%s\n' "$prev_ids" | tr ' ' '\n' | sort -u) <(printf '%s\n' "$ids" | tr ' ' '\n' | sort -u) | awk NF | paste -sd ' ' -)
  if [ -n "$prev_index" ] && [ -n "$new" ]; then
    bad="${bad:+$bad; }new warnings: $new"
  fi
  if [ -n "$bad" ]; then echo "fail: lynis $bad"; else echo "ok"; fi
}

decide() {
  local prev=$1 notified=$2 result=$3 now=$4
  if [ "$result" = ok ]; then
    if [ "$prev" = fail ]; then echo "recover ok 0"; else echo "none ok 0"; fi
  elif [ "$prev" != fail ] || [ $(( now - notified )) -ge 86400 ]; then
    echo "alert fail $now"
  else
    echo "none fail $notified"
  fi
}

apply() {
  local state=$1 check=$2 result=$3 now=$4 prev=ok notified=0 action status stamp
  [ -f "$state/$check.state" ] && read -r prev notified <"$state/$check.state"
  read -r action status stamp <<<"$(decide "$prev" "$notified" "$result" "$now")"
  case "$action" in
    alert) nexus-alert "$(urgency_of "$check")" "${result#fail: }" "Nexus: $check failing$TITLE_SUFFIX" ;;
    recover) nexus-alert normal "$check is healthy again." "Nexus: $check recovered$TITLE_SUFFIX" ;;
  esac
  echo "$status $stamp" >"$state/$check.state"
}

gather() {
  local check=$1 state=$2 now=$3
  case "$check" in
    logins)
      local accepted
      if [ -f "$state/sshd.cursor" ]; then
        accepted=$(journalctl -u sshd.service --cursor-file="$state/sshd.cursor" -o cat --no-pager | grep 'Accepted ' || true)
      else
        accepted=$(journalctl -u sshd.service --since=-15min --cursor-file="$state/sshd.cursor" -o cat --no-pager | grep 'Accepted ' || true)
      fi
      check_logins "$accepted" "$(loginctl list-sessions --no-legend)" "$ALLOWED_IPS" "$(ssh-keygen -lf "$AUTHORIZED_KEYS" | awk '{print $2}' | paste -sd ' ' -)" ;;
    units)
      check_units "$(systemctl --failed --plain --no-legend)" "$(systemctl --user -M "$USER_NAME@" --failed --plain --no-legend 2>/dev/null || true)" ;;
    updates)
      check_updates "$(cat /run/booted-system/nixos-version)" "$(readlink /run/booted-system)" "$(readlink /run/current-system)" "$(stat -c %Y /nix/var/nix/profiles/system)" "$now" ;;
    disk)
      check_disk "$(df --output=pcent / | tail -n 1)" ;;
    backup)
      check_backup "$(stat -c %Y "$BACKUP_MARKER" 2>/dev/null || true)" "$now" ;;
  esac
}

run_checks() {
  local state=$1 now failing="" check result
  now=$(date +%s)
  for check in $CHECKS; do
    result=$(gather "$check" "$state" "$now")
    echo "$check: $result"
    apply "$state" "$check" "$result" "$now"
    [ "$result" = ok ] || failing="${failing:+$failing,}$check"
  done
  if [ -n "$failing" ]; then echo "fail:$failing"; else echo "ok"; fi >"$state/status"
}

run_lynis() {
  local state=$1 report index ids prev_index="" prev_ids="" result
  report=$(mktemp)
  lynis audit system --quiet --no-colors --cronjob --report-file "$report" --logfile /dev/null >/dev/null
  index=$(sed -n 's/^hardening_index=//p' "$report")
  ids=$(sed -n 's/^warning\[\]=\([^|]*\)|.*/\1/p' "$report" | sort -u | paste -sd ' ' -)
  rm -f "$report"
  [ -f "$state/lynis.index" ] && prev_index=$(cat "$state/lynis.index")
  [ -f "$state/lynis.warnings" ] && prev_ids=$(cat "$state/lynis.warnings")
  result=$(check_lynis "$prev_index" "$prev_ids" "$index" "$ids")
  echo "lynis: index $index, warnings: ${ids:-none}; $result"
  echo "$index" >"$state/lynis.index"
  echo "$ids" >"$state/lynis.warnings"
  [ "$result" = ok ] || nexus-alert urgent "${result#fail: }" "Nexus: lynis failing"
}

selftest() {
  local state now check result
  state=$(mktemp -d)
  now=$(date +%s)
  TITLE_SUFFIX=" (self-test, no action needed)"
  for check in $CHECKS lynis; do
    case "$check" in
      logins) result=$(check_logins "Accepted publickey for tom from 192.0.2.7 port 4242 ssh2: ED25519 SHA256:selftest" "" "10.77.0.2 10.77.0.3" "SHA256:known") ;;
      units) result=$(check_units "selftest-broken.service loaded failed failed Self-test" "") ;;
      updates) result=$(check_updates "26.05.20200101.0000000" /a /a "$now" "$now") ;;
      disk) result=$(check_disk " 93%") ;;
      backup) result=$(check_backup $(( now - 30 * 3600 )) "$now") ;;
      lynis) result=$(check_lynis 80 "AUTH-9999" 75 "AUTH-9999 SSH-0001") ;;
    esac
    echo "$check: $result"
    [ "$result" != ok ] || { echo "self-test: $check did not fail on its fixture" >&2; exit 1; }
    apply "$state" "$check" "$result" "$now"
  done
  rm -rf "$state"
}

state=${STATE_DIRECTORY:-/var/lib/nexus-checks}
case "${1:-run}" in
  run) run_checks "$state" ;;
  --lynis) run_lynis "$state" ;;
  --selftest) selftest ;;
  *) echo "usage: nexus-checks [run|--lynis|--selftest]" >&2; exit 2 ;;
esac
