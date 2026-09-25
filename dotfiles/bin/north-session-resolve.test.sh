#!/usr/bin/env bash
# Behavioural tests for dotfiles/bin/north-session-resolve. Runs against a
# synthetic HOME, so no real account home is read or resolved.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVE="$ROOT/dotfiles/bin/north-session-resolve"
CODEX="$ROOT/dotfiles/bin/codex"
CODEX_POOLED="$ROOT/dotfiles/bin/codex-pooled"
CODEX_PARSER_RUNTIME="${CODEX_PARSER_RUNTIME:-$HOME/.local/lib/codex/current/bin/codex}"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture:?}"' EXIT

mkdir -p "$fixture/launchers"
cp "$CODEX" "$CODEX_POOLED" "$RESOLVE" "$ROOT/dotfiles/bin/north" "$fixture/launchers/"
export CODEX_TEST_SHARED_HOME_LOG="$fixture/shared-home"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\\n" "${NORTH_CODEX_CONVERSATION_HOME:-${NORTH_CODEX_POOLED_HOME:-$HOME/.local/state/north/codex-pooled}}" >"$CODEX_TEST_SHARED_HOME_LOG"' \
  'printf "%s\\n" "unix:///synthetic/shared/app-server.sock"' \
  >"$fixture/launchers/codex-shared-server"
chmod +x "$fixture/launchers/codex-shared-server"
CODEX="$fixture/launchers/codex"
CODEX_POOLED="$fixture/launchers/codex-pooled"

export HOME="$fixture"
fail() { printf 'north-session-resolve.test.sh:%s: %s\n' "${BASH_LINENO[0]}" "$1" >&2; exit 1; }
[ -x "$CODEX_PARSER_RUNTIME" ] || fail "installed Codex parser is unavailable at $CODEX_PARSER_RUNTIME"

OSID=33333333-dddd-eeee-ffff-444444444444
base="$HOME/.local/state/north/accounts"
odir="$base/openai/acct/sessions/2026/08/12"
mkdir -p "$odir"

otrans="$odir/rollout-2026-08-12T09-00-00-$OSID.jsonl"
printf '{"type":"session_meta","payload":{"id":"%s","cwd":"/synthetic/demo"}}\n' \
  "$OSID" >"$otrans"
# padding, so the archive is not resolved out of a single tiny frame by luck
for _ in $(seq 200); do
  printf '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"padding padding padding"}]}}\n' >>"$otrans"
done

expect_home() { # <provider> <sid> <expected home>
  local out
  out="$("$RESOLVE" "$1" "$2")" || fail "$1 $2 did not resolve"
  [ "$(cut -f5 <<<"$out")" = "$3" ] ||
    fail "$1 $2 resolved to $(cut -f5 <<<"$out"), wanted $3"
}

write_session() { # <home> <sid>
  local home="$1" sid="$2" session_dir
  session_dir="$home/sessions/2026/08/12"
  mkdir -p "$session_dir"
  printf '{"type":"session_meta","payload":{"id":"%s","cwd":"/synthetic/demo"}}\n' \
    "$sid" >"$session_dir/rollout-2026-08-12T09-00-00-$sid.jsonl"
}

# ---- plain transcripts resolve -------------------------------------------
expect_home openai "$OSID" "$base/openai/acct"

# ---- pooled transcripts select the pooled foreground launcher -------------
PSID=55555555-aaaa-bbbb-cccc-666666666666
pooled="$HOME/.local/state/north/codex-pooled"
write_session "$pooled" "$PSID"

# A different account session proves exact-UUID resolution does not fall
# through into the normal account selector or another provider home.
ASID=77777777-aaaa-bbbb-cccc-888888888888
write_session "$base/openai/fallback" "$ASID"

resolved="$($RESOLVE openai "$PSID")" || fail "pooled session did not resolve"
[ "$(cut -f3 <<<"$resolved")" = pooled ] || fail "pooled authority was not selected"
[ "$(cut -f5 <<<"$resolved")" = "$pooled" ] || fail "pooled home was not selected"

runtime="$fixture/codex-runtime"
argv_log="$fixture/codex.argv"
env_log="$fixture/codex.env"
cat >"$runtime" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CODEX_TEST_ARGV_LOG"
printf '%s\n%s\n%s\n' "${CODEX_HOME:-}" "${CODEX_SQLITE_HOME:-}" "${NORTH_CODEX_ENDPOINT:-}" >"$CODEX_TEST_ENV_LOG"
EOF
chmod +x "$runtime"

env -u CODEX_HOME -u CODEX_SQLITE_HOME \
  CODEX_RUNTIME="$runtime" \
  CODEX_TEST_ARGV_LOG="$argv_log" \
  CODEX_TEST_ENV_LOG="$env_log" \
  NORTH_NO_SLICE=1 \
  "$CODEX" resume "$PSID" >/dev/null 2>&1 || fail "pooled resume launch failed"

mapfile -t launched_env <"$env_log"
[ "${launched_env[0]}" = "$pooled" ] ||
  fail "launch used ${launched_env[0]}, wanted $pooled"
[ "${launched_env[1]}" = "$pooled/sqlite" ] || fail "launch used the wrong pooled SQLite home"
grep -Fxq 'model_provider="codex-lb"' "$argv_log" || fail "pooled provider was not selected"
grep -Fxq 'model_providers.codex-lb.base_url="http://127.0.0.1:2455/backend-api/codex"' "$argv_log" ||
  fail "pooled provider base URL was not passed"
[ "$(grep -Fxc "$PSID" "$argv_log")" -eq 1 ] || fail "exact pooled UUID was not passed once"
if grep -Fxq "$ASID" "$argv_log"; then
  fail "launch fell through into another account home"
fi

# Automatic sessions use the same pooled entrypoint, including North's
# app-server launch. Explicit account and inherited homes remain authoritative.
run_automatic() {
  env -u CODEX_HOME -u CODEX_SQLITE_HOME \
    CODEX_RUNTIME="$runtime" \
    CODEX_TEST_ARGV_LOG="$argv_log" \
    CODEX_TEST_ENV_LOG="$env_log" \
    NORTH_CODEX_POOLED_HOME="$pooled" \
    NORTH_NO_SLICE=1 XDG_RUNTIME_DIR= \
    "$CODEX" "$@" >"$fixture/automatic.stdout" 2>"$fixture/automatic.stderr" ||
    fail "automatic launch failed: $*"
}

for invocation in interactive app-server exec; do
  case "$invocation" in
    interactive) run_automatic ;;
    app-server) run_automatic app-server --listen stdio:// ;;
    exec) run_automatic exec "hello pool" ;;
  esac
  mapfile -t launched_env <"$env_log"
  [ "${launched_env[0]}" = "$pooled" ] || fail "$invocation did not use pooled home"
  [ "${launched_env[1]}" = "$pooled/sqlite" ] || fail "$invocation lost SQLite home"
  grep -Fxq 'model_provider="codex-lb"' "$argv_log" || fail "$invocation lost pooled provider"
  grep -Fxq 'model="gpt-6-astra"' "$argv_log" || fail "$invocation lost Astra root default"
  grep -Fxq 'model_reasoning_effort="medium"' "$argv_log" || fail "$invocation lost medium root effort"
  if [[ "$invocation" = interactive ]]; then
    grep -Fxq 'unix:///synthetic/shared/app-server.sock' "$argv_log" ||
      fail "interactive launch did not attach to shared owner"
  elif grep -Fxq -- '--remote' "$argv_log"; then
    fail "$invocation unexpectedly attached instead of running its native command"
  fi
  if grep -Eq 'north providers|fallback' "$fixture/automatic.stderr"; then
    fail "$invocation invoked retired selection"
  fi
done

run_automatic -c 'model="gpt-5.6-sol"' -c 'model_reasoning_effort="low"' app-server --listen stdio://
[[ "$(grep '^model=' "$argv_log" | tail -1)" = 'model="gpt-5.6-sol"' ]] ||
  fail "pooled default replaced explicit model"
[[ "$(grep '^model_reasoning_effort=' "$argv_log" | tail -1)" = 'model_reasoning_effort="low"' ]] ||
  fail "pooled default replaced explicit effort"

run_automatic resume "$ASID"
mapfile -t launched_env <"$env_log"
[[ "${launched_env[0]}" = "$base/openai/fallback" ]] || fail "historical resume moved conversation home"
[[ "${launched_env[1]}" = "$base/openai/fallback/sqlite" ]] || fail "historical resume moved SQLite home"
[[ "$(<"$CODEX_TEST_SHARED_HOME_LOG")" = "$base/openai/fallback" ]] ||
  fail "historical resume selected another server home"
grep -Fxq -- '--remote' "$argv_log" || fail "historical resume did not attach"
grep -Fxq 'model_provider="codex-lb"' "$argv_log" || fail "historical resume did not use managed provider"

run_automatic as acct exec "explicit account"
mapfile -t launched_env <"$env_log"
[ "${launched_env[0]}" = "$base/openai/acct" ] || fail "explicit account was replaced"
grep -Fxq 'model="gpt-6-astra"' "$argv_log" || fail "native root lost Astra default"
grep -Fxq 'model_reasoning_effort="medium"' "$argv_log" || fail "native root lost medium effort"
if grep -Fxq 'model_provider="codex-lb"' "$argv_log"; then
  fail "explicit account received pooled provider"
fi

run_automatic as acct -c 'model="gpt-5.6-sol"' -c 'model_reasoning_effort="low"' exec "explicit model"
[[ "$(grep '^model=' "$argv_log" | tail -1)" = 'model="gpt-5.6-sol"' ]] ||
  fail "native default replaced explicit model"
[[ "$(grep '^model_reasoning_effort=' "$argv_log" | tail -1)" = 'model_reasoning_effort="low"' ]] ||
  fail "native default replaced explicit effort"

env CODEX_HOME="$base/openai/acct" CODEX_SQLITE_HOME="$fixture/custom-sqlite" \
  CODEX_RUNTIME="$runtime" CODEX_TEST_ARGV_LOG="$argv_log" CODEX_TEST_ENV_LOG="$env_log" \
  NORTH_NO_SLICE=1 XDG_RUNTIME_DIR= \
  "$CODEX" app-server --listen stdio:// >/dev/null 2>&1 || fail "inherited launch failed"
mapfile -t launched_env <"$env_log"
[ "${launched_env[0]}" = "$base/openai/acct" ] || fail "inherited home was replaced"
[ "${launched_env[1]}" = "$fixture/custom-sqlite" ] || fail "inherited SQLite home was replaced"
if grep -Fxq 'model_provider="codex-lb"' "$argv_log"; then
  fail "inherited home received pooled provider"
fi
if grep -Eq '^(model|model_reasoning_effort)=' "$argv_log"; then
  fail "managed lane received root model defaults"
fi

mkdir -p "$HOME/.local/state/north-v2/current"
ln -s "$runtime" "$HOME/.local/state/north-v2/current/north"
env -u NORTH_CODEX_ENDPOINT \
  CODEX_HOME="$base/openai/acct" \
  CODEX_TEST_ARGV_LOG="$argv_log" CODEX_TEST_ENV_LOG="$env_log" \
  "$fixture/launchers/north" || fail "ordinary North launch failed"
mapfile -t launched_env <"$env_log"
[[ -z "${launched_env[0]}" ]] || fail "North retained ambient account home"
[[ "${launched_env[2]}" = unix:///synthetic/shared/app-server.sock ]] ||
  fail "North and Codex chose different shared endpoints"
env -u NORTH_CODEX_ENDPOINT \
  CODEX_TEST_ARGV_LOG="$argv_log" CODEX_TEST_ENV_LOG="$env_log" \
  "$fixture/launchers/north" --resume "$ASID" || fail "North historical resume failed"
[[ "$(<"$CODEX_TEST_SHARED_HOME_LOG")" = "$base/openai/fallback" ]] ||
  fail "North historical resume selected another server home"
grep -Fxq -- --resume "$argv_log" || fail "North lost explicit resume action"
grep -Fxq -- "$ASID" "$argv_log" || fail "North lost requested conversation"
env -u NORTH_CODEX_ENDPOINT \
  CODEX_TEST_ARGV_LOG="$argv_log" CODEX_TEST_ENV_LOG="$env_log" \
  "$fixture/launchers/north" --help || fail "North help failed"
mapfile -t launched_env <"$env_log"
[[ -z "${launched_env[2]}" ]] || fail "North maintenance started a server"

# Pooled non-interactive execution owns its provider and permission argv.
# Plain exec needs the executable full-access switch. Nested exec resume needs
# exec-only workspace authority before the nested subcommand and every
# resume-owned override after it, even when exec-level options precede it;
# option values and prompt operands named resume are not subcommands.
run_pooled() {
  env -u CODEX_HOME -u CODEX_SQLITE_HOME \
    CODEX_RUNTIME="$runtime" \
    CODEX_TEST_ARGV_LOG="$argv_log" \
    CODEX_TEST_ENV_LOG="$env_log" \
    NORTH_CODEX_POOLED_HOME="$pooled" \
    NORTH_NO_SLICE=1 \
    "$CODEX_POOLED" "$@" >/dev/null 2>&1 || fail "pooled launch failed: $*"
}

argv_line() {
  grep -Fnx -- "$1" "$argv_log" | cut -d: -f1
}

assert_nested_resume_layout() {
  local entrypoint="$1" label="$2"
  local entrypoint_line workspace_line directory_line resume_line provider_line bypass_line session_line
  [ "$(grep -Fxc -- '--dangerously-bypass-approvals-and-sandbox' "$argv_log")" -eq 1 ] ||
    fail "$label did not pass the full-access switch exactly once"
  [ "$(grep -Fxc -- '--add-dir' "$argv_log")" -eq 1 ] ||
    fail "$label did not pass workspace authority exactly once"
  entrypoint_line="$(argv_line "$entrypoint")"
  workspace_line="$(argv_line --add-dir)"
  directory_line="$(argv_line "$HOME/code")"
  resume_line="$(argv_line resume)"
  provider_line="$(argv_line 'model_provider="codex-lb"')"
  bypass_line="$(argv_line '--dangerously-bypass-approvals-and-sandbox')"
  session_line="$(argv_line "$PSID")"
  [ "$entrypoint_line" -lt "$workspace_line" ] && [ "$workspace_line" -lt "$directory_line" ] &&
    [ "$directory_line" -lt "$resume_line" ] && [ "$resume_line" -lt "$provider_line" ] &&
    [ "$provider_line" -lt "$bypass_line" ] && [ "$bypass_line" -lt "$session_line" ] ||
    fail "$label did not split exec and resume argv at the nested parser boundary"
}

run_pooled exec plain-task

[ "$(grep -Fxc -- '--dangerously-bypass-approvals-and-sandbox' "$argv_log")" -eq 1 ] ||
  fail "plain pooled exec did not pass the full-access switch exactly once"
exec_line="$(argv_line exec)"
provider_line="$(argv_line 'model_provider="codex-lb"')"
bypass_line="$(argv_line '--dangerously-bypass-approvals-and-sandbox')"
[ "$exec_line" -lt "$provider_line" ] && [ "$provider_line" -lt "$bypass_line" ] ||
  fail "plain pooled exec passed provider or permission argv outside exec"

run_pooled exec --json resume "$PSID" resumed-task
assert_nested_resume_layout exec 'exec --json resume'
json_line="$(argv_line --json)"
resume_line="$(argv_line resume)"
[ "$json_line" -lt "$resume_line" ] || fail "exec --json was not preserved before resume"

run_pooled exec --disable multi_agent resume "$PSID" resumed-task
assert_nested_resume_layout exec 'exec --disable multi_agent resume'
disable_line="$(argv_line --disable)"
feature_line="$(argv_line multi_agent)"
resume_line="$(argv_line resume)"
[ "$disable_line" -lt "$feature_line" ] && [ "$feature_line" -lt "$resume_line" ] ||
  fail "exec --disable value was not preserved before resume"

run_pooled e --json resume "$PSID" resumed-task
assert_nested_resume_layout e 'e --json resume'

# Exercise the installed clap parser without starting a session. Appending
# --help forces a successful parse to exit before provider or session work.
parser_runtime="$fixture/codex-parser-runtime"
cat >"$parser_runtime" <<'EOF'
#!/usr/bin/env bash
exec "$CODEX_TEST_REAL_RUNTIME" "$@" --help >/dev/null
EOF
chmod +x "$parser_runtime"

env -u CODEX_HOME -u CODEX_SQLITE_HOME \
  CODEX_RUNTIME="$parser_runtime" \
  CODEX_TEST_REAL_RUNTIME="$CODEX_PARSER_RUNTIME" \
  NORTH_CODEX_POOLED_HOME="$pooled" \
  NORTH_NO_SLICE=1 XDG_RUNTIME_DIR= \
  "$CODEX" app-server --listen stdio:// --enable multi_agent_v2 \
    >/dev/null 2>&1 || fail "installed parser rejected automatic app-server argv"

env -u CODEX_HOME -u CODEX_SQLITE_HOME \
  CODEX_RUNTIME="$parser_runtime" \
  CODEX_TEST_REAL_RUNTIME="$CODEX_PARSER_RUNTIME" \
  NORTH_CODEX_POOLED_HOME="$pooled" \
  NORTH_NO_SLICE=1 \
  "$CODEX_POOLED" exec --json resume --disable multi_agent \
    -m gpt-5.6-sol -c 'model_reasoning_effort="xhigh"' "$PSID" - \
    >/dev/null 2>&1 || fail "installed parser rejected pooled exec resume argv"

run_pooled exec --disable resume plain-task
provider_line="$(argv_line 'model_provider="codex-lb"')"
disable_line="$(argv_line --disable)"
resume_line="$(argv_line resume)"
[ "$provider_line" -lt "$disable_line" ] && [ "$disable_line" -lt "$resume_line" ] ||
  fail "an exec option value named resume was treated as a subcommand"

run_pooled exec -- resume
provider_line="$(argv_line 'model_provider="codex-lb"')"
separator_line="$(argv_line --)"
resume_line="$(argv_line resume)"
[ "$provider_line" -lt "$separator_line" ] && [ "$separator_line" -lt "$resume_line" ] ||
  fail "a prompt operand named resume was treated as a subcommand"

# ---- an archived transcript resolves identically --------------------------
# `convo compress` rewrites a closed transcript as .jsonl.zst; a session must
# stay locatable afterwards, or archiving would strand it.
zstd -q --long=27 --rm "$otrans"
[ -f "$otrans.zst" ] && [ ! -f "$otrans" ] || fail "fixture was not archived"
expect_home openai "$OSID" "$base/openai/acct"

# ---- an unknown id is still unknown --------------------------------------
if "$RESOLVE" openai 99999999-9999-9999-9999-999999999999 >/dev/null 2>&1; then
  fail "resolved a session that does not exist"
fi

# ---- an archive whose first record is not session_meta is not a match -----
mkdir -p "$base/openai/other/sessions/2026/08/12"
decoy="$base/openai/other/sessions/2026/08/12/rollout-2026-08-12T10-00-00-$OSID.jsonl"
printf '{"type":"response_item","payload":{"type":"message"}}\n' >"$decoy"
zstd -q --long=27 --rm "$decoy"
expect_home openai "$OSID" "$base/openai/acct"

echo "north-session-resolve.test.sh: all assertions passed"
