#!/usr/bin/env bash
set -euo pipefail

# Test doubles record only this test's synthetic user-service state.
case "${0##*/}" in
  systemctl)
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
      fi
      previous="$argument"
    done
    touch "$SHARED_TEST_ROOT/active"
    exit
    ;;
esac

source_dir="$(dirname "$(realpath "$0")")"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture:?}"' EXIT
mkdir -p "$fixture/bin" "$fixture/runtime" "$fixture/home/pool"
chmod 700 "$fixture/runtime"
ln -s "$(realpath "$0")" "$fixture/bin/systemctl"
ln -s "$(realpath "$0")" "$fixture/bin/systemd-run"
export SHARED_TEST_ROOT="$fixture"
export PATH="$fixture/bin:$PATH"
export XDG_RUNTIME_DIR="$fixture/runtime"
export NORTH_CODEX_POOLED_HOME="$fixture/home/pool"
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

mv "$fixture/active" "$fixture/inactive"
if "$helper" >"$fixture/failed" 2>"$fixture/error"; then
  fail "ownerless socket allowed another writer"
fi
[[ "$(wc -l <"$fixture/starts")" = 1 ]] || fail "failure started another owner"
[[ -S "${endpoint#unix://}" ]] || fail "failure deleted socket"
printf 'codex-shared-server.test.sh: all assertions passed\n'
