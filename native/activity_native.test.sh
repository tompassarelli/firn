#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [[ -n "${BEAGLE_PATH:-}" ]]; then
  beagle="$BEAGLE_PATH"
else
  git_common_dir="$(
    timeout --foreground 5 git -C "$repo" rev-parse \
      --path-format=absolute --git-common-dir
  )" || {
    printf 'activity-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-activity-native.XXXXXX")"
daemon_one=""
daemon_two=""

stop_pid() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 50); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.02
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  wait "$pid" 2>/dev/null || true
}

cleanup() {
  local status=$?
  trap - EXIT
  stop_pid "$daemon_two"
  stop_pid "$daemon_one"
  if [[ -f "$scratch/event-children.log" ]]; then
    while read -r verb invocation pid; do
      if [[ "$verb" == start ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
      fi
    done <"$scratch/event-children.log"
  fi
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'activity-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'activity-native: %s\n' "$*" >&2
  exit 1
}

for command in awk bash cmp git jq od rg seq timeout; do
  command -v "$command" >/dev/null 2>&1 \
    || die "missing command: $command"
done
[[ -x "$beagle/bin/beagle-build-all" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

json="$beagle/native-core/src/native/json.bjs"
core="$repo/native/activity_core.bjs"
driver="$repo/native/activity_driver.bjs"
focus_test="$repo/native/activity_focus_test.bjs"
native="$repo/native/activity_native.bjs"
host="$repo/native/activity_host.mjs"
bun="${FIRN_BUN:-$(command -v bun || true)}"
executable="$scratch/activity"
modules="$scratch/modules"
[[ -n "$bun" && -x "$bun" ]] || die "Bun runtime is unavailable"

printf 'activity-native: building controlled Beagle/JS modules\n' >&2
mkdir -p "$modules/activity"
timeout --foreground 120 "$beagle/bin/beagle-build-all" \
  "$json" "$core" "$driver" "$focus_test" "$native" --out "$modules" \
  >"$scratch/build.out" 2>"$scratch/build.err" \
  || {
    sed -n '1,300p' "$scratch/build.err" >&2
    die "Beagle/JS compilation failed"
  }
[[ -f "$modules/activity/native.js" ]] \
  || die "activity JS module was not produced"
mkdir -p "$modules/node_modules/beagle"
cp -- "$beagle/beagle-lib/lib/beagle/core.js" \
  "$modules/node_modules/beagle/core.js"
printf '%s\n' '{"type":"module"}' \
  >"$modules/node_modules/beagle/package.json"

printf 'activity-native: post-reorder focus behavior\n' >&2
FIRN_ACTIVITY_TEST_MODULE="$modules/activity/focus-test.js" \
timeout --foreground 30 "$bun" --eval \
  'const m = await import(process.env.FIRN_ACTIVITY_TEST_MODULE); process.exitCode = m.run([]);' \
  >"$scratch/focus-test.out" 2>"$scratch/focus-test.err" \
  || die "post-reorder focus behavior failed"
cmp -s "$scratch/focus-test.out" \
  <(printf 'PASS post-reorder-focus\nPASS empty-activity-reuses-trailing-seed\n') \
  || die "post-reorder focus behavior output changed"
[[ ! -s "$scratch/focus-test.err" ]] \
  || die "post-reorder focus behavior wrote stderr"

cat >"$executable" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export FIRN_ACTIVITY_MODULE='$modules/activity/native.js'
exec '$bun' '$host' "\$@"
EOF
chmod +x "$executable"

home="$scratch/home"
runtime="$scratch/runtime"
state="$scratch/state"
config="$scratch/config"
fake_bin="$scratch/fake-bin"
mkdir -p "$home" "$runtime" "$state" "$config/activity" "$fake_bin"

cat >"$config/activity/activities.json" <<'EOF'
{"default":"home","activities":[{"id":"home","label":"home"},{"id":"gjoa","label":"gjoa","bind_names":["render"],"bind_prefixes":["gjoa"]},{"id":"msa","label":"msa","bind_names":["heist"],"bind_prefixes":["msa"]}]}
EOF

cat >"$scratch/workspaces.json" <<'EOF'
[{"id":1,"idx":1,"name":"notes","output":"DP-1","is_focused":true,"is_active":true,"is_urgent":false,"active_window_id":10},{"id":2,"idx":2,"name":"render","output":"DP-1","is_focused":false,"is_active":false,"is_urgent":true,"active_window_id":20},{"id":3,"idx":3,"name":null,"output":"DP-1","is_focused":false,"is_active":false,"is_urgent":false,"active_window_id":null}]
EOF

cat >"$scratch/event-one.json" <<'EOF'
{"WorkspacesChanged":{"workspaces":[{"id":1,"idx":1,"name":"notes","output":"DP-1","is_focused":false,"is_active":false,"is_urgent":false,"active_window_id":10},{"id":2,"idx":2,"name":"render","output":"DP-1","is_focused":true,"is_active":true,"is_urgent":true,"active_window_id":20},{"id":3,"idx":3,"name":null,"output":"DP-1","is_focused":false,"is_active":false,"is_urgent":false,"active_window_id":null}]}}
EOF

cat >"$scratch/event-two.json" <<'EOF'
{"WorkspacesChanged":{"workspaces":[{"id":1,"idx":1,"name":"notes","output":"DP-1","is_focused":true,"is_active":true,"is_urgent":false,"active_window_id":10},{"id":2,"idx":2,"name":"render","output":"DP-1","is_focused":false,"is_active":false,"is_urgent":true,"active_window_id":20},{"id":3,"idx":3,"name":null,"output":"DP-1","is_focused":false,"is_active":false,"is_urgent":false,"active_window_id":null}]}}
EOF

printf '0\n' >"$scratch/event-count"
: >"$scratch/event-children.log"
: >"$scratch/actions.log"

cat >"$fake_bin/niri" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  'msg --json workspaces')
    exec cat "$FAKE_WORKSPACES"
    ;;
  'msg --json event-stream')
    invocation="$(( $(<"$FAKE_EVENT_COUNT") + 1 ))"
    printf '%s\n' "$invocation" >"$FAKE_EVENT_COUNT"
    printf 'start %s %s\n' "$invocation" "$$" >>"$FAKE_EVENT_CHILDREN"
    trap 'printf "exit %s %s\n" "$invocation" "$$" >>"$FAKE_EVENT_CHILDREN"' EXIT
    if [[ "$invocation" == 1 ]]; then
      cat "$FAKE_EVENT_ONE"
      exit 0
    fi
    cat "$FAKE_EVENT_TWO"
    while :; do
      printf '{}\n'
      sleep 0.05
    done
    ;;
  'msg action '*)
    shift 2
    printf '%s\n' "$*" >>"$FAKE_ACTIONS"
    ;;
  *)
    exit 97
    ;;
esac
EOF
chmod +x "$fake_bin/niri"

export PATH="$fake_bin:$PATH"
export HOME="$home"
export XDG_RUNTIME_DIR="$runtime"
export XDG_STATE_HOME="$state"
export XDG_CONFIG_HOME="$config"
export FAKE_WORKSPACES="$scratch/workspaces.json"
export FAKE_EVENT_ONE="$scratch/event-one.json"
export FAKE_EVENT_TWO="$scratch/event-two.json"
export FAKE_EVENT_COUNT="$scratch/event-count"
export FAKE_EVENT_CHILDREN="$scratch/event-children.log"
export FAKE_ACTIONS="$scratch/actions.log"

wait_for() {
  local label="$1"
  shift
  for _ in $(seq 1 200); do
    if "$@"; then
      return 0
    fi
    sleep 0.05
  done
  die "timed out waiting for $label"
}

snapshot="$state/activity/state.json"
assignments="$state/activity/assignments.json"
pid_path="$runtime/activity/pid"

snapshot_is_ordered() {
  [[ -f "$snapshot" ]] || return 1
  jq -e '.current == "home" and .previous == "gjoa"' \
    "$snapshot" >/dev/null 2>&1
}

child_one_exited() {
  rg -q '^exit 1 ' "$scratch/event-children.log"
}

printf 'activity-native: FIFO, event ordering, and reconnect\n' >&2
"$executable" daemon \
  >"$scratch/daemon-one.out" 2>"$scratch/daemon-one.err" &
daemon_one=$!
wait_for 'control FIFO' test -p "$runtime/activity/ctl"
wait_for 'ordered second event' snapshot_is_ordered
wait_for 'first event child reap' child_one_exited
child_one="$(awk '$1 == "start" && $2 == "1" {print $3}' \
  "$scratch/event-children.log")"
[[ -n "$child_one" ]] || die "first event child pid was not recorded"
kill -0 "$child_one" 2>/dev/null \
  && die "reconnected event child was not reaped"

[[ "$(tail -c 1 "$snapshot" | od -An -tu1 | tr -d ' ')" == 10 ]] \
  || die "snapshot lacks its trailing newline"

cat >"$scratch/snapshot.expected.json" <<'EOF'
{"current":"home","previous":"gjoa","activities":[{"id":"home","label":"home","last_active":1,"workspaces":[{"id":1,"idx":1,"name":"notes","output":"DP-1","focused":true,"active":true,"urgent":false}]},{"id":"gjoa","label":"gjoa","last_active":2,"workspaces":[{"id":2,"idx":2,"name":"render","output":"DP-1","focused":false,"active":false,"urgent":true}]},{"id":"msa","label":"msa","last_active":null,"workspaces":[]}],"floating":[{"id":3,"idx":3,"name":null,"output":"DP-1","focused":false,"active":false,"urgent":false}]}
EOF
jq -c 'del(.generated_at)' "$snapshot" >"$scratch/snapshot.actual"
jq -c . "$scratch/snapshot.expected.json" >"$scratch/snapshot.expected"
cmp -s "$scratch/snapshot.expected" "$scratch/snapshot.actual" \
  || {
    diff -u "$scratch/snapshot.expected" "$scratch/snapshot.actual" >&2 || true
    die "exact snapshot payload changed"
  }
jq -e '(.generated_at | type) == "number" and
       (keys == ["activities","current","floating","generated_at","previous"])' \
  "$snapshot" >/dev/null || die "snapshot schema changed"

printf 'activity-native: CLI protocol and persistence\n' >&2
"$executable" current >"$scratch/current.out"
cmp -s "$scratch/current.out" <(printf 'home\n') \
  || die "current output changed"
"$executable" list --menu >"$scratch/menu.out"
cmp -s "$scratch/menu.out" <(printf 'home\ngjoa\nmsa\n') \
  || die "menu output changed"
"$executable" list >"$scratch/list.out"
cmp -s "$scratch/list.out" \
  <(printf '* home  (1)\n  gjoa  (1)\n  msa  (0)\n') \
  || die "list output changed"
"$executable" list --json >"$scratch/list-json.out"
cmp -s "$snapshot" "$scratch/list-json.out" \
  || die "list --json did not preserve exact snapshot bytes"

"$executable" goto gjoa
"$executable" move-to-activity msa
"$executable" assign gjoa

assignments_ready() {
  [[ -f "$assignments" ]] && \
    cmp -s "$assignments" <(printf '{"notes":"gjoa"}\n')
}
wait_for 'persisted assignment' assignments_ready

actions_ready() {
  [[ "$(wc -l <"$scratch/actions.log")" == 2 ]]
}
wait_for 'ordered niri actions' actions_ready
cmp -s "$scratch/actions.log" \
  <(printf 'focus-workspace render\nmove-column-to-workspace 3\n') \
  || die "command action order changed"

printf 'activity-native: sole-writer takeover and restart persistence\n' >&2
"$executable" daemon \
  >"$scratch/daemon-two.out" 2>"$scratch/daemon-two.err" &
daemon_two=$!

first_stopped() {
  ! kill -0 "$daemon_one" 2>/dev/null
}
second_owns_lease() {
  [[ -f "$pid_path" ]] && [[ "$(tr -d '[:space:]' <"$pid_path")" == "$daemon_two" ]]
}
persisted_state_loaded() {
  [[ -f "$snapshot" ]] && \
    jq -e '.current == "gjoa" and
           ([.activities[] | select(.id == "gjoa") | .workspaces[].id] == [1,2]) and
           ([.floating[].id] == [3])' "$snapshot" >/dev/null 2>&1
}

wait_for 'old daemon takeover' first_stopped
wait "$daemon_one" 2>/dev/null || true
daemon_one=""
wait_for 'new lease owner pid' second_owns_lease
wait_for 'assignment reload' persisted_state_loaded

printf 'activity-native: bounded unreachable-daemon timeout\n' >&2
stop_pid "$daemon_two"
daemon_two=""
set +e
timeout --foreground 3 "$executable" goto home \
  >"$scratch/unreachable.out" 2>"$scratch/unreachable.err"
unreachable_status=$?
set -e
[[ "$unreachable_status" == 1 ]] \
  || die "unreachable daemon returned $unreachable_status, expected 1"
cmp -s "$scratch/unreachable.out" \
  <(printf '%s\n' \
    'activity: daemon not reachable (systemctl --user status activity-daemon)') \
  || die "unreachable daemon diagnostic changed"
[[ ! -s "$scratch/unreachable.err" ]] \
  || die "unreachable daemon wrote stderr"

printf 'ok: Beagle/JS Activity preserves FIFO order, reconnect, lease takeover, persistence, snapshot, and CLI timeout\n'
