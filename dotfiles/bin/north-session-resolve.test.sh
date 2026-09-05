#!/usr/bin/env bash
# Behavioural tests for dotfiles/bin/north-session-resolve. Runs against a
# synthetic HOME, so no real account home is read or resolved.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVE="$ROOT/dotfiles/bin/north-session-resolve"
CODEX="$ROOT/dotfiles/bin/codex"
CODEX_POOLED="$ROOT/dotfiles/bin/codex-pooled"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture:?}"' EXIT

export HOME="$fixture"
fail() { printf 'north-session-resolve.test.sh:%s: %s\n' "${BASH_LINENO[0]}" "$1" >&2; exit 1; }

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
printf '%s\n%s\n' "$CODEX_HOME" "$CODEX_SQLITE_HOME" >"$CODEX_TEST_ENV_LOG"
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

# Pooled non-interactive execution owns its provider and permission argv.
# Plain exec needs the executable full-access switch. Nested exec resume needs
# every pooled override after the real nested subcommand, even when exec-level
# options precede it; option values and prompt operands named resume are not
# subcommands.
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
  local entrypoint_line resume_line provider_line bypass_line session_line
  [ "$(grep -Fxc -- '--dangerously-bypass-approvals-and-sandbox' "$argv_log")" -eq 1 ] ||
    fail "$label did not pass the full-access switch exactly once"
  entrypoint_line="$(argv_line "$entrypoint")"
  resume_line="$(argv_line resume)"
  provider_line="$(argv_line 'model_provider="codex-lb"')"
  bypass_line="$(argv_line '--dangerously-bypass-approvals-and-sandbox')"
  session_line="$(argv_line "$PSID")"
  [ "$entrypoint_line" -lt "$resume_line" ] && [ "$resume_line" -lt "$provider_line" ] &&
    [ "$provider_line" -lt "$bypass_line" ] && [ "$bypass_line" -lt "$session_line" ] ||
    fail "$label did not pass provider and permission argv after resume"
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
