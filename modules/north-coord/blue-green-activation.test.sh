#!/usr/bin/env bash
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

token=$scratch/cutover.token
route=$scratch/route.map
gate_state=$scratch/gate
fake_state=$scratch/fake
mkdir -p "$gate_state" "$fake_state"
printf 'test-secret\n' >"$token"
chmod 0600 "$token"
printf 'active blue\n' >"$route"

cat >"$scratch/runtime" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s %s\n' \
  "$NORTH_COORD_SLOT" "$FRAM_COORD_ROLE" "$FRAM_REQUIRE_LOG_FENCE" \
  >>"$NORTH_COORD_TEST_ROLE_LOG"
[[ "$FRAM_CUTOVER_TOKEN" == test-secret ]]
[[ "$1" == start ]]
SH
chmod 0700 "$scratch/runtime"

run_slot() {
  NORTH_COORD_SLOT=$1 \
  NORTH_COORD_SELECTOR_MAP=$route \
  NORTH_COORD_CUTOVER_TOKEN_FILE=$token \
  NORTH_COORD_SLOT_RUNTIME=$scratch/runtime \
  NORTH_COORD_TEST_ROLE_LOG=$scratch/roles \
    "$here/north-coord-slot-start"
}

# Every private unit derives authority from the one durable key on every
# restart. This is the four-unit start contract, including a post-cutover
# restart on both sides.
run_slot blue
run_slot blue
run_slot green
run_slot green
cat >"$scratch/roles.expected" <<'EOF'
blue active 1
blue active 1
green standby 1
green standby 1
EOF
cmp "$scratch/roles.expected" "$scratch/roles"

printf 'active green\n' >"$route"
: >"$scratch/roles"
run_slot blue
run_slot blue
run_slot green
run_slot green
cat >"$scratch/roles.expected" <<'EOF'
blue standby 1
blue standby 1
green active 1
green active 1
EOF
cmp "$scratch/roles.expected" "$scratch/roles"

write_endpoint() {
  printf '%s %s %s %s\n' "$2" "$3" "$4" "${5:-none}" >"$fake_state/$1"
}
write_endpoint 17977 active blue-coord 10
write_endpoint 17978 active blue-telemetry 20
write_endpoint 27977 standby green-coord 10
write_endpoint 27978 standby green-telemetry 20

cat >"$scratch/fram-cutover" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

command=$1
shift
port= log= cutover_id= expected_instance= marker_out= marker_file=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) port=$2 ;;
    --log) log=$2 ;;
    --cutover-id) cutover_id=$2 ;;
    --expected-instance) expected_instance=$2 ;;
    --marker-out) marker_out=$2 ;;
    --marker-file) marker_file=$2 ;;
  esac
  shift 2
done

endpoint=$NORTH_COORD_TEST_FAKE_STATE/$port
read -r phase instance version endpoint_cutover_id <"$endpoint"
endpoint_cutover_id=${endpoint_cutover_id:-none}
authorized=false
[[ "$phase" == active ]] && authorized=true

case "$command" in
  status)
    outer_phase=$phase
    cutover_phase=$phase
    writer_role=$phase
    if [[ "$phase" == demoted ]]; then
      outer_phase=retired
      cutover_phase=demoted
      writer_role=retired
    elif [[ "$phase" == rejected ]]; then
      outer_phase=standby
      cutover_phase=promotion-rejected
      writer_role=standby
    fi
    if [[ "$endpoint_cutover_id" == none ]]; then
      printf '{:ok true :protocol "fram-coordinator-cutover/v1" :phase :%s :instance "%s" :version %s :writer-authority {:role :%s :write-authorized %s} :cutover {:phase :%s}}\n' \
        "$outer_phase" "$instance" "$version" "$writer_role" "$authorized" "$cutover_phase"
    else
      printf '{:ok true :protocol "fram-coordinator-cutover/v1" :phase :%s :instance "%s" :version %s :writer-authority {:role :%s :write-authorized %s} :cutover {:phase :%s :cutover-id "%s"}}\n' \
        "$outer_phase" "$instance" "$version" "$writer_role" "$authorized" \
        "$cutover_phase" "$endpoint_cutover_id"
    fi
    ;;
  demote)
    [[ "$phase" == active && "$expected_instance" == "$instance" ]]
    printf 'demoted %s %s %s\n' \
      "$instance" "$version" "$cutover_id" >"$endpoint"
    printf '{:format "fram-coordinator-cutover-marker/v1" :cutover-id "%s" :version %s :instance "%s"}\n' \
      "$cutover_id" "$version" "$instance" >"$marker_out"
    chmod 0600 "$marker_out"
    printf '{:ok true :protocol "fram-coordinator-cutover/v1"}\n'
    ;;
  promote)
    if [[ -n "${NORTH_COORD_TEST_FAIL_PROMOTE_PORT:-}" &&
          "$port" == "$NORTH_COORD_TEST_FAIL_PROMOTE_PORT" &&
          ! -e "$NORTH_COORD_TEST_FAKE_STATE/failure.used" ]]; then
      : >"$NORTH_COORD_TEST_FAKE_STATE/failure.used"
      printf 'rejected %s %s %s\n' \
        "$instance" "$version" "$cutover_id" >"$endpoint"
      if [[ -n "${NORTH_COORD_TEST_STALE_OLD_PORT:-}" ]]; then
        old_endpoint=$NORTH_COORD_TEST_FAKE_STATE/$NORTH_COORD_TEST_STALE_OLD_PORT
        read -r old_phase old_instance old_version old_cutover_id <"$old_endpoint"
        printf '%s %s %s %s\n' \
          "$old_phase" "$old_instance" "$((old_version + 1))" \
          "$old_cutover_id" >"$old_endpoint"
      fi
      exit 3
    fi
    [[ "$phase" == standby || "$phase" == demoted || "$phase" == rejected ]]
    [[ -f "$marker_file" ]]
    read -r marker_cutover_id marker_version < <(
      bb -e '(require (quote [clojure.edn :as edn]))
             (let [m (edn/read-string (slurp (first *command-line-args*)))]
               (println (:cutover-id m) (:version m)))' \
        "$marker_file"
    )
    if [[ "$marker_cutover_id" != "$cutover_id" ||
          "$marker_version" != "$version" ]]; then
      printf 'rejected %s %s %s\n' \
        "$instance" "$version" "$cutover_id" >"$endpoint"
      exit 3
    fi
    if [[ -n "${NORTH_COORD_TEST_DROP_PROMOTE_PORT:-}" &&
          "$port" == "$NORTH_COORD_TEST_DROP_PROMOTE_PORT" ]]; then
      exit 4
    fi
    if [[ -n "${NORTH_COORD_TEST_TIMEOUT_PROMOTE_PORT:-}" &&
          "$port" == "$NORTH_COORD_TEST_TIMEOUT_PROMOTE_PORT" ]]; then
      (
        sleep "${NORTH_COORD_TEST_PRETRANSITION_DELAY_SECONDS:-0.15}"
        printf 'promoting %s %s %s\n' \
          "$instance" "$version" "$cutover_id" >"$endpoint"
        sleep "${NORTH_COORD_TEST_DELAY_PROMOTE_SECONDS:-0.2}"
        printf 'active %s %s %s\n' \
          "$instance" "$version" "$cutover_id" >"$endpoint"
      ) >/dev/null 2>&1 &
      exit 4
    fi
    if [[ -n "${NORTH_COORD_TEST_DELAY_PROMOTE_PORT:-}" &&
          "$port" == "$NORTH_COORD_TEST_DELAY_PROMOTE_PORT" ]]; then
      printf 'promoting %s %s %s\n' \
        "$instance" "$version" "$cutover_id" >"$endpoint"
      (
        sleep "${NORTH_COORD_TEST_DELAY_PROMOTE_SECONDS:-0.2}"
        printf 'active %s %s %s\n' \
          "$instance" "$version" "$cutover_id" >"$endpoint"
      ) >/dev/null 2>&1 &
    else
      printf 'active %s %s %s\n' \
        "$instance" "$version" "$cutover_id" >"$endpoint"
    fi
    printf '{:ok true :protocol "fram-coordinator-cutover/v1"}\n'
    ;;
  *) exit 2 ;;
esac
SH
chmod 0700 "$scratch/fram-cutover"

export NORTH_COORD_CUTOVER_BIN=$scratch/fram-cutover
export NORTH_COORD_CUTOVER_TOKEN_FILE=$token
export NORTH_COORD_CUTOVER_STATE=$gate_state
export NORTH_COORD_COORD_LOG=$scratch/coordination.log
export NORTH_COORD_TELEMETRY_LOG=$scratch/telemetry.log
export NORTH_COORD_BLUE_COORD_PORT=17977
export NORTH_COORD_BLUE_TELEMETRY_PORT=17978
export NORTH_COORD_GREEN_COORD_PORT=27977
export NORTH_COORD_GREEN_TELEMETRY_PORT=27978
export NORTH_COORD_TEST_FAKE_STATE=$fake_state
export NORTH_COORD_CUTOVER_TIMEOUT_MS=3000
export NORTH_COORD_CUTOVER_SETTLE_TIMEOUT_MS=3000
export NORTH_COORD_CUTOVER_SETTLE_POLL_SECONDS=0.02
: >"$NORTH_COORD_COORD_LOG"
: >"$NORTH_COORD_TELEMETRY_LOG"

transaction=$scratch/selector.transaction

# A partial pair promotion must fail closed, then independently reconcile the
# already-promoted coordination endpoint and the merely-demoted telemetry
# endpoint back to the old pair.
export NORTH_COORD_TEST_FAIL_PROMOTE_PORT=27978
if "$here/north-coord-cutover-gate" promote blue green "$transaction"; then
  echo "partial promotion unexpectedly succeeded" >&2
  exit 1
fi
"$here/north-coord-cutover-gate" rollback green blue "$transaction"
"$here/north-coord-cutover-gate" verify blue
unset NORTH_COORD_TEST_FAIL_PROMOTE_PORT

# A successful daemon demotion reports outer lifecycle :retired plus nested
# cutover phase :demoted. Promotion may acknowledge while status is still
# :promoting. Prove both real shapes settle without a false gate failure.
export NORTH_COORD_TEST_DELAY_PROMOTE_PORT=27977
export NORTH_COORD_TEST_TIMEOUT_PROMOTE_PORT=27977
"$here/north-coord-cutover-gate" promote blue green "$transaction"
unset NORTH_COORD_TEST_DELAY_PROMOTE_PORT NORTH_COORD_TEST_TIMEOUT_PROMOTE_PORT
"$here/north-coord-cutover-gate" verify green
"$here/north-coord-cutover-gate" promote green blue "$transaction"
"$here/north-coord-cutover-gate" verify blue

# Crash after selector records gate-started but before the gate program writes
# its own state: no authority mutation occurred, so recovery proves old active
# and returns without inventing a marker.
rm -f -- "$gate_state/gate.current" "$gate_state"/*.edn
"$here/north-coord-cutover-gate" rollback green blue "$transaction"
"$here/north-coord-cutover-gate" verify blue

# Proxy startup has an independent authority-marker guard in addition to the
# systemd ConditionPathExists gate.
if NORTH_COORD_HAPROXY=/bin/true \
   NORTH_COORD_HAPROXY_CONFIG=$scratch/haproxy.cfg \
   NORTH_COORD_BOOTSTRAP_MARKER=$scratch/missing \
     "$here/north-coord-proxy-start"; then
  echo "proxy started without bootstrap authority marker" >&2
  exit 1
fi

# If an exact demotion marker goes stale before a never-active target can take
# authority, rollback must remain fail-closed. It may not change the marker,
# invent a version, or report the old pair restored.
write_endpoint 17977 active blue-coord 30
write_endpoint 17978 active blue-telemetry 40
write_endpoint 27977 standby green-coord 30
write_endpoint 27978 standby green-telemetry 40
rm -f -- "$fake_state/failure.used" "$gate_state"/*.edn
export NORTH_COORD_TEST_FAIL_PROMOTE_PORT=27978
export NORTH_COORD_TEST_STALE_OLD_PORT=17978
if "$here/north-coord-cutover-gate" promote blue green "$transaction"; then
  echo "stale-marker promotion unexpectedly succeeded" >&2
  exit 1
fi
cp -- "$gate_state/telemetry.old-demotion.edn" "$scratch/stale-marker.before"
read -r _ _ stale_blue_version _ <"$fake_state/17978"
read -r _ _ stale_green_version _ <"$fake_state/27978"
if "$here/north-coord-cutover-gate" rollback green blue "$transaction"; then
  echo "stale-marker rollback unexpectedly resumed authority" >&2
  exit 1
fi
cmp "$scratch/stale-marker.before" "$gate_state/telemetry.old-demotion.edn"
read -r blue_telemetry_phase _ <"$fake_state/17978"
read -r green_telemetry_phase _ <"$fake_state/27978"
read -r _ _ blue_telemetry_version _ <"$fake_state/17978"
read -r _ _ green_telemetry_version _ <"$fake_state/27978"
[[ "$blue_telemetry_phase" != active ]]
[[ "$green_telemetry_phase" != active ]]
[[ "$blue_telemetry_version" == "$stale_blue_version" ]]
[[ "$green_telemetry_version" == "$stale_green_version" ]]
unset NORTH_COORD_TEST_FAIL_PROMOTE_PORT NORTH_COORD_TEST_STALE_OLD_PORT

# A transport timeout may happen before the server installs :promoting. Keep
# polling the exact ID instead of sampling the old stable phase once.
write_endpoint 17977 active blue-coord 50
write_endpoint 17978 active blue-telemetry 60
write_endpoint 27977 standby green-coord 50
write_endpoint 27978 standby green-telemetry 60
rm -f -- "$gate_state"/*.edn "$fake_state/failure.used"
export NORTH_COORD_TEST_TIMEOUT_PROMOTE_PORT=27977
"$here/north-coord-cutover-gate" promote blue green "$transaction"
[[ ! -e "$gate_state/outcome.unknown" ]]
unset NORTH_COORD_TEST_TIMEOUT_PROMOTE_PORT

# If no terminal phase is ever observable, preserve the unresolved record and
# refuse rollback. A late queued server request can therefore never race a
# resumed frontend.
write_endpoint 17977 active blue-coord 70
write_endpoint 17978 active blue-telemetry 80
write_endpoint 27977 standby green-coord 70
write_endpoint 27978 standby green-telemetry 80
rm -f -- "$gate_state"/*.edn "$fake_state/failure.used"
export NORTH_COORD_TEST_DROP_PROMOTE_PORT=27978
export NORTH_COORD_CUTOVER_SETTLE_TIMEOUT_MS=200
if "$here/north-coord-cutover-gate" promote blue green "$transaction"; then
  echo "unobservable promotion unexpectedly succeeded" >&2
  exit 1
fi
[[ -f "$gate_state/outcome.unknown" ]]
if "$here/north-coord-cutover-gate" rollback green blue "$transaction"; then
  echo "rollback ignored an unresolved transport outcome" >&2
  exit 1
fi
[[ -f "$gate_state/outcome.unknown" ]]
unset NORTH_COORD_TEST_DROP_PROMOTE_PORT

printf 'blue/green activation behavior: PASS\n'
