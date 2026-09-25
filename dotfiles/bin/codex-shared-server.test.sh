#!/usr/bin/env bash
set -euo pipefail

# Test doubles record only this test's synthetic user-service state.
case "${0##*/}" in
  systemctl)
    if [[ " $* " = *" show "* ]]; then
      if [[ -e "$SHARED_TEST_ROOT/transition" ]]; then
        cat "$SHARED_TEST_ROOT/transition"
      elif [[ -e "$SHARED_TEST_ROOT/active" ]]; then
        echo active
      else
        echo inactive
      fi
      exit
    fi
    [[ -e "$SHARED_TEST_ROOT/active" ]]
    exit
    ;;
  systemd-run)
    printf '%s\n' "$@" >>"$SHARED_TEST_ROOT/start.argv"
    printf 'start\n' >>"$SHARED_TEST_ROOT/starts"
    previous=""
    for argument in "$@"; do
      if [[ "$previous" = --listen ]]; then
        perl -MSocket -e 'socket(my $s, AF_UNIX, SOCK_STREAM, 0) or die $!; bind($s, sockaddr_un($ARGV[0])) or die $!;' "${argument#unix://}"
        printf '%s\n' "${argument#unix://}" >"$SHARED_TEST_ROOT/listener.path"
      fi
      previous="$argument"
    done
    touch "$SHARED_TEST_ROOT/active"
    touch "$SHARED_TEST_ROOT/listening"
    exit
    ;;
  ss)
    if [[ -e "$SHARED_TEST_ROOT/listening" && "${*: -1}" = "$(<"$SHARED_TEST_ROOT/listener.path")" ]]; then echo 'test listener'; fi
    exit 0
    ;;
esac

source_dir="$(dirname "$(realpath "$0")")"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture:?}"' EXIT
mkdir -p "$fixture/bin" "$fixture/runtime" "$fixture/home/pool"
chmod 700 "$fixture/runtime"
ln -s "$(realpath "$0")" "$fixture/bin/systemctl"
ln -s "$(realpath "$0")" "$fixture/bin/systemd-run"
ln -s "$(realpath "$0")" "$fixture/bin/ss"
export SHARED_TEST_ROOT="$fixture"
export PATH="$fixture/bin:$PATH"
export XDG_RUNTIME_DIR="$fixture/runtime"
export NORTH_CODEX_POOLED_HOME="$fixture/home/pool"
unset NORTH_CODEX_CONVERSATION_HOME NORTH_CODEX_CONVERSATION_SQLITE_HOME
export CODEX_RUNTIME
CODEX_RUNTIME="$(type -P bash)"

fail() { printf 'codex-shared-server.test.sh: %s\n' "$*" >&2; exit 1; }
helper="$source_dir/codex-shared-server"
"$helper" >"$fixture/first" &
first_pid=$!
"$helper" >"$fixture/second" &
second_pid=$!
first_status=0
second_status=0
wait "$first_pid" || first_status=$?
wait "$second_pid" || second_status=$?
[[ "$first_status" = 0 && "$second_status" = 0 ]] || fail "concurrent startup failed"
cmp "$fixture/first" "$fixture/second" || fail "launchers chose different owners"
[[ "$(wc -l <"$fixture/starts")" = 1 ]] || fail "concurrent launch started another owner"
endpoint="$(<"$fixture/first")"
[[ -S "${endpoint#unix://}" ]] || fail "endpoint is not a Unix socket"
[[ "$(stat -c %a "$(dirname "${endpoint#unix://}")")" = 700 ]] || fail "socket directory is not private"
grep -Fxq -- "--setenv=CODEX_RUNTIME=$(realpath "$CODEX_RUNTIME")" "$fixture/start.argv" ||
  fail "service did not pin the resolved runtime"
grep -Fxq -- "--setenv=NORTH_CODEX_CONVERSATION_HOME=$fixture/home/pool" "$fixture/start.argv" ||
  fail "service did not bind the conversation home"
grep -Fxq -- "--setenv=NORTH_CODEX_CONVERSATION_SQLITE_HOME=$fixture/home/pool/sqlite" "$fixture/start.argv" ||
  fail "service did not preserve the SQLite directory"
grep -Fxq -- app-server "$fixture/start.argv" || fail "service did not start supported app-server"

# Codex can publish the requested endpoint as a symlink to its control socket.
mv "${endpoint#unix://}" "$fixture/control.sock"
ln -s "$fixture/control.sock" "${endpoint#unix://}"
printf '%s\n' "$fixture/control.sock" >"$fixture/listener.path"
"$helper" >"$fixture/aliased"
cmp "$fixture/first" "$fixture/aliased" || fail "socket alias changed the client endpoint"
[[ "$(wc -l <"$fixture/starts")" = 1 ]] || fail "socket alias started another owner"
rm "${endpoint#unix://}"
mv "$fixture/control.sock" "${endpoint#unix://}"
printf '%s\n' "${endpoint#unix://}" >"$fixture/listener.path"

mv "$fixture/active" "$fixture/inactive"
if "$helper" >"$fixture/failed" 2>"$fixture/error"; then
  fail "live listener allowed another writer"
fi
[[ "$(wc -l <"$fixture/starts")" = 1 ]] || fail "failure started another owner"
[[ -S "${endpoint#unix://}" ]] || fail "failure deleted socket"
rm "$fixture/listening"
printf 'deactivating\n' >"$fixture/transition"
if "$helper" >"$fixture/failed" 2>"$fixture/error"; then
  fail "transitioning service allowed a replacement"
fi
[[ -S "${endpoint#unix://}" ]] || fail "transition deleted socket"
rm "$fixture/transition"
"$helper" >"$fixture/recovered"
cmp "$fixture/first" "$fixture/recovered" || fail "recovery changed endpoint"
[[ "$(wc -l <"$fixture/starts")" = 2 ]] || fail "dead socket did not recover"
grep -Fxq -- "--property=RuntimeDirectory=$(basename "$(dirname "${endpoint#unix://}")")" "$fixture/start.argv" ||
  fail "service did not give systemd ownership of cleanup"
printf 'codex-shared-server.test.sh: all assertions passed\n'
