#!/usr/bin/env bash
# Hermetic diagnostics test for the `claude` / `codex` bootloader wrappers.
#
# Everything the wrapper touches is faked: a restricted PATH (so "north missing"
# is real, not shadowed by the system north), a stub `north` whose exit code /
# stdout / stderr are env-driven, a fake "real" CLI that only records the env it
# was exec'd with, and a throwaway $HOME for the account roots. No real north,
# no real claude/codex, and no real account state is read or written.
#
# Both wrappers are exercised through the SAME matrix so their fallback
# behaviour stays consistent: missing north, nonzero snapshot (with stderr),
# empty output, malformed JSON, no eligible target, a selected-but-absent
# account dir, and a clean successful selection — plus explicit-pin and the
# already-pinned passthrough guard.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/launcher-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

# --- restricted toolbox: only what the wrappers need, so `north` absence is
#     genuine rather than masked by the ambient system north on PATH. ---
BIN="$SCRATCH/bin"      # coreutils + jq + fake real CLIs (always on PATH)
NBIN="$SCRATCH/nbin"    # holds the stub `north` (added to PATH only when present)
GIT_CALLS="$SCRATCH/git.calls"
mkdir -p "$BIN" "$NBIN"
for tool in env bash realpath jq find sort sed head mktemp paste rm cat grep dirname mkdir tr; do
  real="$(command -v "$tool" 2>/dev/null)" || { echo "missing host tool: $tool" >&2; exit 2; }
  # Link straight to the resolved command-v path; do NOT depend on `readlink`
  # (agent-config-check.test.sh runs this under a readlink-fails shim).
  ln -s "$real" "$BIN/$tool"
done

# Tripwire Git instead of omitting it: production launchers must not inspect a
# checkout at all, even when Git is present and inherited state could tempt a
# main-worktree discovery path.
cat >"$BIN/git" <<'GIT'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GIT_CALLS:?}"
exit 97
GIT
chmod +x "$BIN/git"

# Stub north: env-driven so one script covers every backend outcome.
cat >"$NBIN/north" <<'NORTH'
#!/usr/bin/env bash
[ -n "${NORTH_STDERR:-}" ] && printf '%s\n' "$NORTH_STDERR" >&2
# Record whether the production snapshot inherited NORTH_CHECKOUT. Ordinary
# launchers must always scrub it; only explicit north-dev surfaces may use it.
if [ -n "${NORTH_CHECKOUT_RECORD:-}" ]; then
  if [ -n "${NORTH_CHECKOUT+x}" ]; then
    printf '%s' "$NORTH_CHECKOUT" >"$NORTH_CHECKOUT_RECORD"
  else
    printf '<unset>' >"$NORTH_CHECKOUT_RECORD"
  fi
fi
if [ -n "${NORTH_CLAUDE_LAUNCHER_BYPASS_RECORD:-}" ]; then
  printf '%s' "${NORTH_CLAUDE_LAUNCHER_BYPASS:-<unset>}" \
    >"$NORTH_CLAUDE_LAUNCHER_BYPASS_RECORD"
fi
if [ -n "${NORTH_JSON:-}" ] && [ -f "$NORTH_JSON" ]; then
  cat "$NORTH_JSON"
fi
exit "${NORTH_RC:-0}"
NORTH
chmod +x "$NBIN/north"

# Fake "real" claude/codex: record the exec environment, touch nothing else.
for cli in claude codex; do
  cat >"$BIN/$cli" <<'CLI'
#!/usr/bin/env bash
{
  printf 'CLAUDE_CONFIG_DIR=%s\n' "${CLAUDE_CONFIG_DIR:-}"
  printf 'CODEX_HOME=%s\n' "${CODEX_HOME:-}"
  printf 'CODEX_SQLITE_HOME=%s\n' "${CODEX_SQLITE_HOME:-}"
  printf 'PATH=%s\n' "$PATH"
  printf 'args=%s\n' "$*"
} >"$REAL_RECORD"
CLI
  chmod +x "$BIN/$cli"
done

# Keep the native launchers hermetic by replacing only their hardcoded real CLI
# paths in scratch copies; every other byte remains production code under test.
CODEX_NATIVE_LAUNCHER="$SCRATCH/codex-native"
CLAUDE_NATIVE_LAUNCHER="$SCRATCH/claude-native"
sed "s|^REAL=.*|REAL=\"$BIN/codex\"|" "$HERE/codex-native" >"$CODEX_NATIVE_LAUNCHER"
sed "s|^REAL=.*|REAL=\"$BIN/claude\"|" "$HERE/claude-native" >"$CLAUDE_NATIVE_LAUNCHER"

pass=0
fail=0
check() {
  local description="$1"; shift
  if "$@"; then
    pass=$((pass + 1)); printf 'PASS  %s\n' "$description"
  else
    fail=$((fail + 1)); printf 'FAIL  %s\n' "$description"
  fi
}
contains()     { grep -qF -- "$2" <<<"$1"; }
not_contains() { ! grep -qF -- "$2" <<<"$1"; }
contains_once() {
  local value=$1 needle=$2 remainder
  [[ $value == *"$needle"* ]] || return 1
  remainder=${value#*"$needle"}
  [[ $remainder != *"$needle"* ]]
}

codex_config_has_economical_defaults() {
  python3 - "$HERE/../codex/config.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    config = tomllib.load(handle)

assert config.get("model") == "gpt-5.6-sol"
assert config.get("model_reasoning_effort") == "high"
availability = config.get("tui", {}).get("model_availability_nux", {})
assert availability.get("gpt-5.6-sol") == 1
assert availability.get("gpt-5.6-terra") == 1
PY
}

# Run one wrapper hermetically. Args: launcher, with_north(0/1), then k=v env
# assignments, then `--` and the wrapper's own argv. Sets globals STDERR/RECORD.
STDERR=""; RECORD=""; STATUS=0
run() {
  local launcher="$1" with_north="$2"; shift 2
  local -a envv=() argv=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envv+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  argv=("$@")
  local path="$BIN"
  [ "$with_north" = 1 ] && path="$NBIN:$BIN"
  RECORD="$SCRATCH/record"; rm -f "$RECORD"
  STDERR="$(env -i "HOME=$HOME_DIR" "PATH=$path" "REAL_RECORD=$RECORD" \
    "GIT_CALLS=$GIT_CALLS" \
    "${envv[@]}" bash "$HERE/$launcher" "${argv[@]}" 2>&1 1>/dev/null)"
  STATUS=$?
}
record_field() { sed -n "s/^$2=//p" "$RECORD"; }

# Per-launcher config: provider key + binding limit + the env var a successful
# selection must export into the real CLI.
declare -A PROV=([claude]=anthropic [codex]=openai)
declare -A LIMIT=([claude]="claude:seven_day" [codex]="codex:primary")
declare -A SUB=([claude]=anthropic [codex]=openai)
declare -A PINVAR=([claude]=CLAUDE_CONFIG_DIR [codex]=CODEX_HOME)
CODEX_THREAD_CEILING_ARG='-c agents.max_concurrent_threads_per_session=999'
declare -A ROOT_DEFAULT_ARGS=(
  [claude]='--model claude-fable-5 --effort xhigh --disallowedTools Agent,Task,Workflow'
  [codex]='-c approval_policy="never" -c sandbox_mode="danger-full-access" -c default_permissions=":danger-full-access" -c agents.max_concurrent_threads_per_session=999 --add-dir /home/tom/code -c model="gpt-5.6-sol" -c model_reasoning_effort="high" --disable multi_agent'
)
declare -A WARN_DEFAULT_ARGS=(
  [claude]='--model claude-fable-5 --effort xhigh'
  [codex]='-c approval_policy="never" -c sandbox_mode="danger-full-access" -c default_permissions=":danger-full-access" -c agents.max_concurrent_threads_per_session=999 --add-dir /home/tom/code -c model="gpt-5.6-sol" -c model_reasoning_effort="high"'
)
declare -A PASSTHROUGH_ARGS=(
  [claude]=''
  [codex]='-c approval_policy="never" -c sandbox_mode="danger-full-access" -c default_permissions=":danger-full-access" -c agents.max_concurrent_threads_per_session=999'
)

check 'codex/global config defaults to economical terra/medium' \
  codex_config_has_economical_defaults
check 'codex/root defaults set the subagent thread ceiling exactly once' \
  contains_once "${ROOT_DEFAULT_ARGS[codex]}" "$CODEX_THREAD_CEILING_ARG"
check 'codex/warn defaults set the subagent thread ceiling exactly once' \
  contains_once "${WARN_DEFAULT_ARGS[codex]}" "$CODEX_THREAD_CEILING_ARG"
check 'codex/passthrough defaults set the subagent thread ceiling exactly once' \
  contains_once "${PASSTHROUGH_ARGS[codex]}" "$CODEX_THREAD_CEILING_ARG"

HOME_DIR="$SCRATCH/home-codex-native"
mkdir -p "$HOME_DIR/.local/state/north/profiles/codex-native"
: >"$HOME_DIR/.local/state/north/profiles/codex-native/config.toml"
printf '{}\n' >"$HOME_DIR/.local/state/north/profiles/codex-native/auth.json"
RECORD="$SCRATCH/native-record"
NATIVE_PATH="$BIN:$SCRATCH/north/main/orchestration/bin:$SCRATCH/plugins/cache/orchestration/bin:$SCRATCH/keep/bin"
STDERR="$(env -i "HOME=$HOME_DIR" "PATH=$NATIVE_PATH" "REAL_RECORD=$RECORD" \
  bash "$CODEX_NATIVE_LAUNCHER" --model probe 2>&1 1>/dev/null)"
STATUS=$?
check 'codex-native launches the real CLI' test "$STATUS" -eq 0
check 'codex-native sets its isolated profile' \
  test "$(record_field _ CODEX_HOME)" = "$HOME_DIR/.local/state/north/profiles/codex-native"
check 'codex-native removes managed orchestration and plugin bins from PATH' \
  test "$(record_field _ PATH)" = "$BIN:$SCRATCH/keep/bin"
check 'codex-native sets the subagent thread ceiling exactly once' \
  contains_once "$(record_field _ args)" "$CODEX_THREAD_CEILING_ARG"
check 'codex-native injects the ceiling before existing arguments' \
  test "$(record_field _ args)" = \
    "$CODEX_THREAD_CEILING_ARG --add-dir /home/tom/code --model probe"

HOME_DIR="$SCRATCH/home-claude-native"
mkdir -p "$HOME_DIR/.local/state/north/profiles/claude-native"
: >"$HOME_DIR/.local/state/north/profiles/claude-native/settings.json"
printf '{}\n' >"$HOME_DIR/.local/state/north/profiles/claude-native/.credentials.json"
RECORD="$SCRATCH/native-record"
STDERR="$(env -i "HOME=$HOME_DIR" "PATH=$NATIVE_PATH" "REAL_RECORD=$RECORD" \
  bash "$CLAUDE_NATIVE_LAUNCHER" --model probe 2>&1 1>/dev/null)"
STATUS=$?
check 'claude-native launches the real CLI' test "$STATUS" -eq 0
check 'claude-native sets its isolated profile' \
  test "$(record_field _ CLAUDE_CONFIG_DIR)" = "$HOME_DIR/.local/state/north/profiles/claude-native"
check 'claude-native removes managed orchestration and plugin bins from PATH' \
  test "$(record_field _ PATH)" = "$BIN:$SCRATCH/keep/bin"

for launcher in claude codex; do
  prov="${PROV[$launcher]}"; limit="${LIMIT[$launcher]}"
  sub="${SUB[$launcher]}"; pinvar="${PINVAR[$launcher]}"

  # Fresh $HOME per launcher; account roots live under it.
  HOME_DIR="$SCRATCH/home-$launcher"
  ROOT="$HOME_DIR/.local/state/north/accounts/$sub"
  mkdir -p "$ROOT"
  default_args="${ROOT_DEFAULT_ARGS[$launcher]}"
  warn_args="${WARN_DEFAULT_ARGS[$launcher]}"
  passthrough_args="${PASSTHROUGH_ARGS[$launcher]}"
  if [ "$launcher" = codex ]; then
    check 'codex/default model is config, never duplicate --model' \
      not_contains "$default_args" '--model'
    check 'codex/direct sessions receive the stable code root' \
      contains "$default_args" '--add-dir /home/tom/code'
    check 'codex/managed passthrough does not broaden workspace scope' \
      not_contains "$passthrough_args" '--add-dir'
  fi

  eligible="$SCRATCH/$launcher-eligible.json"
  cat >"$eligible" <<JSON
{ "providers": [
  { "provider": "$prov",
    "targets": {
      "s0": {"id":"acctA","authenticated":true,"routing":"eligible","headroom":"plenty","usage":{"windows":[{"limitId":"$limit","usedPercent":10}]}},
      "s1": {"id":"acctB","authenticated":true,"routing":"eligible","headroom":"low","usage":{"windows":[{"limitId":"$limit","usedPercent":40}]}}
    } } ] }
JSON
  headroom_order="$SCRATCH/$launcher-headroom-order.json"
  cat >"$headroom_order" <<JSON
{ "providers": [
  { "provider": "$prov",
    "targets": {
      "s0": {"id":"acctNormal","authenticated":true,"routing":"eligible","headroom":"normal","usage":{"windows":[{"limitId":"$limit","usedPercent":92}]}},
      "s1": {"id":"acctLow","authenticated":true,"routing":"eligible","headroom":"low","usage":{"windows":[{"limitId":"$limit","usedPercent":63}]}}
    } } ] }
JSON
  ineligible="$SCRATCH/$launcher-ineligible.json"
  cat >"$ineligible" <<JSON
{ "providers": [
  { "provider": "$prov",
    "targets": {
      "s0": {"id":"acctA","authenticated":false,"routing":"eligible","headroom":"plenty","usage":{"windows":[]}},
      "s1": {"id":"acctB","authenticated":true,"routing":"ineligible","headroom":"plenty","usage":{"windows":[]}}
    } } ] }
JSON
  malformed="$SCRATCH/$launcher-malformed.json"
  printf '{ this is not json ]]\n' >"$malformed"

  # 1. north missing entirely.
  run "$launcher" 0 -- ; s="$STDERR"
  check "$launcher/missing-north names cause" contains "$s" "north not found on PATH"
  check "$launcher/missing-north still fails open (ambient)" contains "$s" "→ ambient]"
  check "$launcher/missing-north offers a pin recovery" contains "$s" "$launcher as"
  check "$launcher/missing-north exec'd real CLI unpinned" \
    test -f "$RECORD" && check "$launcher/missing-north left pin unset" \
    test -z "$(record_field _ "$pinvar")"
  check "$launcher/missing-north still applies dispatch=north native defaults" \
    test "$(record_field _ args)" = "$default_args"

  # 2. north exits nonzero, with stderr to surface.
  run "$launcher" 1 "NORTH_RC=7" "NORTH_STDERR=backend socket exploded" -- ; s="$STDERR"
  check "$launcher/nonzero names exit code" contains "$s" "north providers exited 7"
  check "$launcher/nonzero surfaces north stderr" contains "$s" "backend socket exploded"
  check "$launcher/nonzero does not claim generic unavailability" not_contains "$s" "north unavailable"

  # 3. empty stdout, exit 0.
  run "$launcher" 1 "NORTH_RC=0" -- ; s="$STDERR"
  check "$launcher/empty-output names cause" contains "$s" "north providers returned no output"

  # 4. malformed JSON.
  run "$launcher" 1 "NORTH_JSON=$malformed" -- ; s="$STDERR"
  check "$launcher/malformed names cause" contains "$s" "north providers JSON was malformed"

  # 5. valid snapshot but no eligible target.
  run "$launcher" 1 "NORTH_JSON=$ineligible" -- ; s="$STDERR"
  check "$launcher/no-eligible names provider" contains "$s" "no eligible $prov account"

  # 5b. no eligible, but real account dirs exist -> recovery lists real ids.
  mkdir -p "$ROOT/acctZ"
  run "$launcher" 1 "NORTH_JSON=$ineligible" -- ; s="$STDERR"
  check "$launcher/no-eligible surfaces a known on-disk id" contains "$s" "known: acctZ"
  rmdir "$ROOT/acctZ"

  # 6. eligible pick, but its account dir is absent -> must NOT auto-pick it.
  rm -rf "$ROOT/acctA"
  run "$launcher" 1 "NORTH_JSON=$eligible" -- ; s="$STDERR"
  check "$launcher/absent-dir names the vanished account" contains "$s" "selected acctA"
  check "$launcher/absent-dir flags it absent" contains "$s" "is absent"
  check "$launcher/absent-dir prints the exact pin recovery" contains "$s" "$launcher as acctA"
  check "$launcher/absent-dir did not pin a stale account" \
    test -z "$(record_field _ "$pinvar")"

  # 7. eligible pick with a present account dir -> clean selection.
  mkdir -p "$ROOT/acctA"
  run "$launcher" 1 "NORTH_JSON=$eligible" -- extra --flag ; s="$STDERR"
  check "$launcher/success banners the account" contains "$s" "[$launcher → acctA]"
  check "$launcher/success exports the pin env" \
    test "$(record_field _ "$pinvar")" = "$ROOT/acctA"
  check "$launcher/success forwards argv" \
    test "$(record_field _ args)" = "$default_args extra --flag"
  if [ "$launcher" = codex ]; then
    check "codex/success also exports CODEX_SQLITE_HOME" \
      test "$(record_field _ CODEX_SQLITE_HOME)" = "$ROOT/acctA/sqlite"
  fi

  # 7b. Measured usage outranks the coarse headroom label.
  mkdir -p "$ROOT/acctNormal" "$ROOT/acctLow"
  run "$launcher" 1 "NORTH_JSON=$headroom_order" -- ; s="$STDERR"
  check "$launcher/headroom ranks lower percentage ahead of label" \
    contains "$s" "[$launcher → acctLow]"
  check "$launcher/headroom pin uses the lower-percentage account" \
    test "$(record_field _ "$pinvar")" = "$ROOT/acctLow"

  # 8. explicit `as <id>` pin bypasses north entirely (dir present).
  run "$launcher" 0 -- as acctA hello ; s="$STDERR"
  check "$launcher/explicit-pin exports the pin env" \
    test "$(record_field _ "$pinvar")" = "$ROOT/acctA"
  check "$launcher/explicit-pin forwards argv after id" \
    test "$(record_field _ args)" = "$default_args hello"
  check "$launcher/explicit-pin prints no auto banner" not_contains "$s" "→ ambient]"

  # 8b. explicit `as <unknown>` errors, does not exec the real CLI.
  run "$launcher" 0 -- as ghost ; s="$STDERR"
  check "$launcher/explicit-unknown reports unknown account" contains "$s" "unknown account 'ghost'"
  check "$launcher/explicit-unknown never exec'd the real CLI" test ! -f "$RECORD"

  # 8c. An exact resume UUID is routed by transcript ownership, not by the
  # headroom winner.
  resume_id="11111111-2222-4333-8444-555555555555"
  owner="$ROOT/acctB"
  if [ "$launcher" = claude ]; then
    mkdir -p "$owner/projects/-work"
    printf '{"sessionId":"%s"}\n' "$resume_id" >"$owner/projects/-work/$resume_id.jsonl"
    resume_argv=(--resume "$resume_id" tail)
    resume_expected="$default_args --resume $resume_id tail"
  else
    mkdir -p "$owner/sessions/2026/07/29"
    printf '{"type":"session_meta","payload":{"id":"%s"}}\n' "$resume_id" \
      >"$owner/sessions/2026/07/29/rollout-2026-07-29T00-00-00-$resume_id.jsonl"
    resume_argv=(--resume "$resume_id" tail)
    resume_expected="$default_args resume $resume_id tail"
  fi
  run "$launcher" 0 -- "${resume_argv[@]}" ; s="$STDERR"
  check "$launcher/resume owner bypasses quota account selection" \
    test "$(record_field _ "$pinvar")" = "$owner"
  check "$launcher/resume owner is named" contains "$s" "resume → account:acctB"
  check "$launcher/resume forwards canonical native argv" \
    test "$(record_field _ args)" = "$resume_expected"
  if [ "$launcher" = codex ]; then
    check "codex/resume owner also switches sqlite authority" \
      test "$(record_field _ CODEX_SQLITE_HOME)" = "$owner/sqlite"
  fi

  # A deliberate environment pin is stronger than automatic lookup. This is
  # how managed lanes and one-off custom homes keep exact execution authority.
  run "$launcher" 0 "$pinvar=$ROOT/acctA" -- "${resume_argv[@]}" ; s="$STDERR"
  check "$launcher/resume preserves a deliberate environment pin" \
    test "$(record_field _ "$pinvar")" = "$ROOT/acctA"
  check "$launcher/pinned resume emits no ownership banner" \
    not_contains "$s" "resume →"
  if [ "$launcher" = codex ]; then
    check "codex/pinned friendly alias still reaches native syntax" \
      test "$(record_field _ args)" = "$passthrough_args resume $resume_id tail"
  fi

  # 8d. Ambient transcripts are first-class owners and must not be hidden by
  # normal account auto-selection.
  ambient_id="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
  if [ "$launcher" = claude ]; then
    ambient="$HOME_DIR/.claude"
    mkdir -p "$ambient/projects/-ambient"
    printf '{"sessionId":"%s"}\n' "$ambient_id" >"$ambient/projects/-ambient/$ambient_id.jsonl"
    ambient_argv=(--resume="$ambient_id")
    ambient_expected="$default_args --resume=$ambient_id"
  else
    ambient="$HOME_DIR/.codex"
    mkdir -p "$ambient/sessions/2026/07/29"
    printf '{"type":"session_meta","payload":{"id":"%s"}}\n' "$ambient_id" \
      >"$ambient/sessions/2026/07/29/rollout-2026-07-29T00-00-01-$ambient_id.jsonl"
    ambient_argv=(--resume="$ambient_id")
    ambient_expected="$default_args resume $ambient_id"
  fi
  run "$launcher" 0 -- "${ambient_argv[@]}" ; s="$STDERR"
  check "$launcher/ambient resume selects ambient home" \
    test "$(record_field _ "$pinvar")" = "$ambient"
  check "$launcher/ambient resume forwards native argv" \
    test "$(record_field _ args)" = "$ambient_expected"
  if [ "$launcher" = codex ]; then
    check "codex/ambient resume uses root sqlite home" \
      test "$(record_field _ CODEX_SQLITE_HOME)" = "$ambient"
  fi

  # 8e. Missing and cross-home ambiguous UUIDs fail closed without launching
  # the provider under a guessed account.
  missing_id="99999999-8888-4777-8666-555555555555"
  run "$launcher" 0 -- --resume "$missing_id" ; s="$STDERR"
  check "$launcher/missing resume exits nonzero" test "$STATUS" -ne 0
  check "$launcher/missing resume names the UUID" contains "$s" "$missing_id"
  check "$launcher/missing resume never launches provider" test ! -f "$RECORD"

  run "$launcher" 0 -- --resume "$missing_id" --help ; s="$STDERR"
  check "$launcher/help after missing UUID remains terminal" test "$STATUS" -eq 0
  if [ "$launcher" = claude ]; then
    missing_help_expected="$default_args --resume $missing_id --help"
  else
    missing_help_expected="$default_args resume $missing_id --help"
  fi
  check "$launcher/help after UUID reaches native CLI" \
    test "$(record_field _ args)" = "$missing_help_expected"

  duplicate_id="12345678-1234-4234-8234-123456789abc"
  if [ "$launcher" = claude ]; then
    mkdir -p "$ROOT/acctA/projects/-duplicate" "$ROOT/acctB/projects/-duplicate"
    printf '{"sessionId":"%s"}\n' "$duplicate_id" >"$ROOT/acctA/projects/-duplicate/$duplicate_id.jsonl"
    printf '{"sessionId":"%s"}\n' "$duplicate_id" >"$ROOT/acctB/projects/-duplicate/$duplicate_id.jsonl"
  else
    mkdir -p "$ROOT/acctA/sessions/2026/07/29" "$ROOT/acctB/sessions/2026/07/29"
    printf '{"type":"session_meta","payload":{"id":"%s"}}\n' "$duplicate_id" \
      >"$ROOT/acctA/sessions/2026/07/29/rollout-a-$duplicate_id.jsonl"
    printf '{"type":"session_meta","payload":{"id":"%s"}}\n' "$duplicate_id" \
      >"$ROOT/acctB/sessions/2026/07/29/rollout-b-$duplicate_id.jsonl"
  fi
  run "$launcher" 0 -- --resume "$duplicate_id" ; s="$STDERR"
  check "$launcher/ambiguous resume exits distinctly" test "$STATUS" -eq 2
  check "$launcher/ambiguous resume lists first authority" contains "$s" "account:acctA"
  check "$launcher/ambiguous resume lists second authority" contains "$s" "account:acctB"
  check "$launcher/ambiguous resume never launches provider" test ! -f "$RECORD"

  # A filename alone is not Claude ownership evidence; reject a renamed or
  # corrupt transcript whose embedded session id disagrees.
  if [ "$launcher" = claude ]; then
    mismatch_id="abcdefab-cdef-4abc-8def-abcdefabcdef"
    mkdir -p "$ROOT/acctA/projects/-mismatch"
    printf '{"sessionId":"00000000-0000-4000-8000-000000000000"}\n' \
      >"$ROOT/acctA/projects/-mismatch/$mismatch_id.jsonl"
    run "$launcher" 0 -- --resume "$mismatch_id" ; s="$STDERR"
    check "claude/mismatched transcript id is rejected" test "$STATUS" -ne 0
    check "claude/mismatched transcript never launches provider" test ! -f "$RECORD"

    run "$launcher" 0 -- --help --resume "$missing_id" ; s="$STDERR"
    check "claude/help stops resume owner parsing" test "$STATUS" -eq 0
    check "claude/help reaches native CLI unchanged" \
      test "$(record_field _ args)" = "$default_args --help --resume $missing_id"

    run "$launcher" 0 -- -- --resume "$resume_id" ; s="$STDERR"
    check "claude/double-dash prevents resume rewriting" \
      test "$(record_field _ args)" = "$default_args -- --resume $resume_id"
  fi

  # Codex permits resume-subcommand options before SESSION_ID.
  if [ "$launcher" = codex ]; then
    run "$launcher" 0 -- resume --all "$resume_id" tail ; s="$STDERR"
    check "codex/native resume finds UUID after resume options" \
      test "$(record_field _ CODEX_HOME)" = "$owner"
    check "codex/native resume preserves option ordering" \
      test "$(record_field _ args)" = "$default_args resume --all $resume_id tail"

    run "$launcher" 0 -- -C/tmp resume "$resume_id" tail ; s="$STDERR"
    check "codex/attached global option still reaches resume owner lookup" \
      test "$(record_field _ CODEX_HOME)" = "$owner"
    check "codex/attached global option ordering is preserved" \
      test "$(record_field _ args)" = "$default_args -C/tmp resume $resume_id tail"

    run "$launcher" 0 -- resume -mgpt-5.6-terra "$resume_id" tail ; s="$STDERR"
    check "codex/attached resume option still reaches owner lookup" \
      test "$(record_field _ CODEX_HOME)" = "$owner"

    run "$launcher" 1 "NORTH_JSON=$eligible" -- \
      resume named-thread "$resume_id" ; s="$STDERR"
    check "codex/UUID-shaped prompt after a session name does not reroute" \
      test "$(record_field _ CODEX_HOME)" = "$ROOT/acctA"
    check "codex/named resume preserves its UUID-shaped prompt" \
      test "$(record_field _ args)" = "$default_args resume named-thread $resume_id"

    run "$launcher" 1 "NORTH_JSON=$eligible" -- \
      resume --profile "$resume_id" named-thread ; s="$STDERR"
    check "codex/UUID-valued resume option is not mistaken for session id" \
      test "$(record_field _ CODEX_HOME)" = "$ROOT/acctA"

    run "$launcher" 1 "NORTH_JSON=$eligible" -- \
      resume --last "$resume_id" ; s="$STDERR"
    check "codex/UUID-shaped prompt after --last does not reroute" \
      test "$(record_field _ CODEX_HOME)" = "$ROOT/acctA"

    run "$launcher" 1 "NORTH_JSON=$eligible" -- \
      -- --resume "$resume_id" ; s="$STDERR"
    check "codex/double-dash prevents friendly alias rewriting" \
      test "$(record_field _ args)" = "$default_args -- --resume $resume_id"

    run "$launcher" 0 -- --help resume "$missing_id" ; s="$STDERR"
    check "codex/top-level help stops resume owner parsing" test "$STATUS" -eq 0
    check "codex/top-level help reaches native CLI unchanged" \
      test "$(record_field _ args)" = "$default_args --help resume $missing_id"

    run "$launcher" 0 -- resume --help "$missing_id" ; s="$STDERR"
    check "codex/resume help stops session owner parsing" test "$STATUS" -eq 0
    check "codex/resume help reaches native CLI unchanged" \
      test "$(record_field _ args)" = "$default_args resume --help $missing_id"

    run "$launcher" 0 -- resume "$missing_id" --help ; s="$STDERR"
    check "codex/help after native resume UUID remains terminal" test "$STATUS" -eq 0
    check "codex/help after native resume UUID reaches CLI unchanged" \
      test "$(record_field _ args)" = "$default_args resume $missing_id --help"
  fi

  # 8f. Picker/search forms remain native. Codex's compatibility alias is
  # normalized even when it carries no UUID to resolve.
  run "$launcher" 1 "NORTH_JSON=$eligible" -- --resume ; s="$STDERR"
  if [ "$launcher" = claude ]; then
    picker_expected="$default_args --resume"
  else
    picker_expected="$default_args resume"
  fi
  check "$launcher/resume picker keeps normal account routing" \
    test "$(record_field _ "$pinvar")" = "$ROOT/acctA"
  check "$launcher/resume picker reaches native syntax" \
    test "$(record_field _ args)" = "$picker_expected"

  # 9. already-pinned passthrough: env var set -> exec straight through, silent.
  managed_argv=()
  managed_expected="$passthrough_args"
  if [ "$launcher" = codex ]; then
    managed_argv=(--model gpt-5.6-sol -c 'model_reasoning_effort="xhigh"')
    managed_expected+=' --model gpt-5.6-sol -c model_reasoning_effort="xhigh"'
  fi
  run "$launcher" 1 "$pinvar=$ROOT/acctA" "NORTH_JSON=$eligible" -- "${managed_argv[@]}" ; s="$STDERR"
  check "$launcher/passthrough emits no banner" test -z "$s"
  check "$launcher/passthrough preserves the caller pin" \
    test "$(record_field _ "$pinvar")" = "$ROOT/acctA"
  check "$launcher/passthrough leaves managed argv unchanged" \
    test "$(record_field _ args)" = "$managed_expected"

  # 9a. North's own provider probe can resolve back through the bootloader.
  # The outer launcher marks its snapshot call, and a nested Claude launcher
  # must immediately exec the real binary instead of selecting again.
  if [ "$launcher" = claude ]; then
    bypass_record="$SCRATCH/claude-bypass-record"
    rm -f "$bypass_record"
    run "$launcher" 1 "NORTH_JSON=$eligible" \
      "NORTH_CLAUDE_LAUNCHER_BYPASS_RECORD=$bypass_record" -- ; s="$STDERR"
    check "claude/selection marks nested North provider probes for bypass" \
      test "$(cat "$bypass_record" 2>/dev/null)" = "1"

    run "$launcher" 0 "NORTH_CLAUDE_LAUNCHER_BYPASS=1" -- --version ; s="$STDERR"
    check "claude/nested provider probe emits no selection banner" test -z "$s"
    check "claude/nested provider probe execs real CLI directly" \
      test "$(record_field _ args)" = "--version"
  fi

  # 9b. The North-native defaults precede explicit user model/effort argv, so
  # the provider CLI's ordinary last-option-wins behavior remains available.
  if [ "$launcher" = claude ]; then
    override_argv=(--model claude-sonnet-5 --effort medium)
    override_suffix='--model claude-sonnet-5 --effort medium'
  else
    override_argv=(--model gpt-5.6-terra -c 'model_reasoning_effort="xhigh"')
    override_suffix='--model gpt-5.6-terra -c model_reasoning_effort="xhigh"'
  fi
  run "$launcher" 0 -- as acctA "${override_argv[@]}" ; s="$STDERR"
  check "$launcher/explicit model+effort override follows native defaults" \
    test "$(record_field _ args)" = "$default_args $override_suffix"

  # 9c. dispatch=native is the deliberate rollback/escape: account selection
  # and existing Codex permission flags remain, but North's native-root model
  # and topology policy disappear. Flipping back to north restores it.
  mkdir -p "$HOME_DIR/.local/state/north"
  printf 'dispatch=native\nguards=off\n' >"$HOME_DIR/.local/state/north/harness.conf"
  run "$launcher" 0 -- as acctA rollback-probe ; s="$STDERR"
  native_rollback_args="$passthrough_args"
  if [ "$launcher" = codex ]; then
    native_rollback_args+=' --add-dir /home/tom/code'
  fi
  [ -z "$native_rollback_args" ] || native_rollback_args+=" "
  native_rollback_args+='rollback-probe'
  check "$launcher/dispatch=native removes native-root defaults" \
    test "$(record_field _ args)" = "$native_rollback_args"
  printf 'dispatch=warn\nguards=off\n' >"$HOME_DIR/.local/state/north/harness.conf"
  run "$launcher" 0 -- as acctA warn-probe ; s="$STDERR"
  check "$launcher/dispatch=warn keeps cost defaults without topology controls" \
    test "$(record_field _ args)" = "$warn_args warn-probe"
  printf 'dispatch=north\nguards=off\n' >"$HOME_DIR/.local/state/north/harness.conf"
  run "$launcher" 0 -- as acctA restored-probe ; s="$STDERR"
  check "$launcher/dispatch=north restores defaults even with guards=off" \
    test "$(record_field _ args)" = "$default_args restored-probe"
  printf 'dispatch=unrecognized\nguards=off\n' >"$HOME_DIR/.local/state/north/harness.conf"
  run "$launcher" 0 -- as acctA malformed-state-probe ; s="$STDERR"
  check "$launcher/unknown dispatch state fails closed to north defaults" \
    test "$(record_field _ args)" = "$default_args malformed-state-probe"
  check "$launcher/unknown dispatch state says so out loud" \
    contains "$s" 'unrecognized dispatch mode "unrecognized"'

  # 9d. The four-mode vocabulary owned by `north config dispatch`. Only
  # managed-forced actually denies native dispatch, so only managed-forced may
  # strip the native spawn tools. On 2026-07-30 every one of these fell through
  # the unknown-value catch-all, so a `native-forced` session was launched with
  # no dispatch surface at all — the exact inverse of what the mode requests.
  for native_mode in native-forced native-biased managed-biased; do
    printf 'dispatch=%s\nguards=off\n' "$native_mode" \
      >"$HOME_DIR/.local/state/north/harness.conf"
    run "$launcher" 0 -- as acctA "$native_mode-probe" ; s="$STDERR"
    check "$launcher/dispatch=$native_mode keeps the native dispatch surface" \
      test "$(record_field _ args)" = "$warn_args $native_mode-probe"
    check "$launcher/dispatch=$native_mode is a recognized mode" \
      not_contains "$s" 'unrecognized dispatch mode'
  done
  printf 'dispatch=managed-forced\nguards=off\n' >"$HOME_DIR/.local/state/north/harness.conf"
  run "$launcher" 0 -- as acctA managed-forced-probe ; s="$STDERR"
  check "$launcher/dispatch=managed-forced withholds the native dispatch surface" \
    test "$(record_field _ args)" = "$default_args managed-forced-probe"
  check "$launcher/dispatch=managed-forced is a recognized mode" \
    not_contains "$s" 'unrecognized dispatch mode'

  printf 'dispatch=north\nguards=off\n' >"$HOME_DIR/.local/state/north/harness.conf"

  # 9d-bis. The collapsed vocabulary (2026-08-02): native | north | auto.
  # `auto` chooses the surface per dispatch, so it must KEEP native dispatch
  # available. Omitting it from the table sent every auto session through the
  # unknown-value catch-all and stripped its dispatch surface.
  printf 'dispatch=auto\nguards=off\n' >"$HOME_DIR/.local/state/north/harness.conf"
  run "$launcher" 0 -- as acctA auto-probe ; s="$STDERR"
  check "$launcher/dispatch=auto keeps the native dispatch surface" \
    test "$(record_field _ args)" = "$warn_args auto-probe"
  check "$launcher/dispatch=auto is a recognized mode" \
    not_contains "$s" 'unrecognized dispatch mode'

  # A failed probe must land on a deterministic AUTHENTICATED account instead
  # of an accountless ambient session (which cannot load a model at all). An
  # account without its auth marker is never eligible for that fallback.
  printf 'dispatch=north\nguards=off\n' >"$HOME_DIR/.local/state/north/harness.conf"
  if [ "$launcher" = codex ]; then auth_marker="auth.json"; else auth_marker=".credentials.json"; fi
  mkdir -p "$ROOT/acctA"
  printf '{}\n' >"$ROOT/acctA/$auth_marker"
  run "$launcher" 0 "NORTH_NO_SELECT_CACHE=1" -- fallback-probe ; s="$STDERR"
  check "$launcher/failed probe falls back to an authenticated account" \
    contains "$s" "→ acctA]"
  check "$launcher/fallback says why and how to override" \
    contains "$s" "fallback; override:"
  check "$launcher/fallback pins that account home" \
    test "$(record_field _ "$pinvar")" = "$ROOT/acctA"
  rm -f "$ROOT/acctA/$auth_marker"
  run "$launcher" 0 "NORTH_NO_SELECT_CACHE=1" -- ambient-probe ; s="$STDERR"
  check "$launcher/unauthenticated accounts never win the fallback" \
    contains "$s" "→ ambient]"

  # 9e. Compute governance (agent.slice). systemd-run is deliberately absent
  # from this harness's toolbox, so the FAIL-OPEN branch is what runs here:
  # governance must never be able to cost a session. Each decision is recorded
  # to a state file so a doctor lane can see a throttle-off estate.
  slice_state="$HOME_DIR/.local/state/north/agent-slice.state"
  slice_decision() { sed -n '1s/^[^\t]*\t\([^\t]*\)\t.*/\1/p' "$slice_state" 2>/dev/null; }

  rm -f "$slice_state"
  run "$launcher" 0 -- as acctA slice-open-probe ; s="$STDERR"
  check "$launcher/absent systemd-run still launches the session" \
    test "$(record_field _ args)" = "$default_args slice-open-probe"
  check "$launcher/absent systemd-run is recorded, not silent" \
    test "$(slice_decision)" = "off:no-systemd-run"
  check "$launcher/slice fallback prints no banner of its own" \
    not_contains "$s" "slice"

  rm -f "$slice_state"
  run "$launcher" 0 "NORTH_NO_SLICE=1" -- as acctA slice-escape-probe ; s="$STDERR"
  check "$launcher/NORTH_NO_SLICE bypasses governance" \
    test "$(slice_decision)" = "off:NORTH_NO_SLICE"
  check "$launcher/NORTH_NO_SLICE still launches the session" \
    test "$(record_field _ args)" = "$default_args slice-escape-probe"

  # Already inside the scope: no second entry, and the launcher says so.
  rm -f "$slice_state"
  run "$launcher" 0 "NORTH_SLICE_ENTERED=1" -- as acctA slice-inside-probe ; s="$STDERR"
  check "$launcher/an already-governed session is not re-entered" \
    test "$(slice_decision)" = "on"
  check "$launcher/an already-governed session still launches" \
    test "$(record_field _ args)" = "$default_args slice-inside-probe"
  rm -f "$slice_state"

  # --- immutable ordinary North selection ---
  checkout_record="$SCRATCH/$launcher-checkout-record"

  # 10. The default production snapshot carries no checkout selector.
  rm -f "$checkout_record" "$GIT_CALLS"
  run "$launcher" 1 "NORTH_JSON=$eligible" "NORTH_CHECKOUT_RECORD=$checkout_record" -- ; s="$STDERR"
  check "$launcher/ordinary snapshot leaves NORTH_CHECKOUT unset" \
    test "$(cat "$checkout_record" 2>/dev/null)" = "<unset>"
  check "$launcher/ordinary snapshot still selects an account" \
    contains "$s" "[$launcher → acctA]"
  check "$launcher/ordinary snapshot performs no checkout discovery" \
    test ! -e "$GIT_CALLS"

  # 11. Stale caller residue cannot steer an ordinary launcher into a checkout.
  explicit_checkout="/explicit/caller/checkout"
  rm -f "$checkout_record" "$GIT_CALLS"
  run "$launcher" 1 "NORTH_JSON=$eligible" "NORTH_CHECKOUT_RECORD=$checkout_record" \
    "NORTH_CHECKOUT=$explicit_checkout" -- ; s="$STDERR"
  check "$launcher/ordinary snapshot scrubs inherited NORTH_CHECKOUT" \
    test "$(cat "$checkout_record" 2>/dev/null)" = "<unset>"
  check "$launcher/scrubbed snapshot still selects an account" \
    contains "$s" "[$launcher → acctA]"
  check "$launcher/scrubbed snapshot performs no checkout discovery" \
    test ! -e "$GIT_CALLS"
done

# Real parser smoke: a config-layer Codex default and a later user --model must
# coexist. Repeating --model itself is rejected by current Codex, which is why
# the wrapper's default deliberately uses -c model=... instead.
REAL_CODEX_BIN="${REAL_CODEX_BIN:-/run/current-system/sw/bin/codex}"
if [ -x "$REAL_CODEX_BIN" ]; then
  check 'codex/real parser accepts config default plus later --model' \
    bash -c '"$@" >/dev/null' _ "$REAL_CODEX_BIN" \
      -c 'model="gpt-5.6-sol"' \
      -c 'model_reasoning_effort="high"' \
      --disable multi_agent \
      --model gpt-5.6-terra \
      --help
fi

printf '\n== result: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
