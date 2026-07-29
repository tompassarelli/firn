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
  printf '%s %s %s\n' "$2" "$3" "$4" >"$fake_state/$1"
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
read -r phase instance version <"$endpoint"
authorized=false
[[ "$phase" == active ]] && authorized=true

case "$command" in
  status)
    printf '{:ok true :protocol "fram-coordinator-cutover/v1" :phase :%s :instance "%s" :version %s :writer-authority {:write-authorized %s}}\n' \
      "$phase" "$instance" "$version" "$authorized"
    ;;
  demote)
    [[ "$phase" == active && "$expected_instance" == "$instance" ]]
    printf 'demoted %s %s\n' "$instance" "$version" >"$endpoint"
    printf '{:protocol "fram-coordinator-cutover-marker/v1" :version %s :instance "%s"}\n' \
      "$version" "$instance" >"$marker_out"
    chmod 0600 "$marker_out"
    printf '{:ok true :protocol "fram-coordinator-cutover/v1"}\n'
    ;;
  promote)
    if [[ -n "${NORTH_COORD_TEST_FAIL_PROMOTE_PORT:-}" &&
          "$port" == "$NORTH_COORD_TEST_FAIL_PROMOTE_PORT" &&
          ! -e "$NORTH_COORD_TEST_FAKE_STATE/failure.used" ]]; then
      : >"$NORTH_COORD_TEST_FAKE_STATE/failure.used"
      exit 3
    fi
    [[ "$phase" == standby || "$phase" == demoted ]]
    [[ -f "$marker_file" ]]
    printf 'active %s %s\n' "$instance" "$version" >"$endpoint"
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

# Retired generations are :demoted, not :standby. Prove repeat cutovers in
# both directions without restarting either generation.
"$here/north-coord-cutover-gate" promote blue green "$transaction"
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

printf 'blue/green activation behavior: PASS\n'
