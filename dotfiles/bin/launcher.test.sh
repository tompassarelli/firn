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
for tool in env bash realpath jq find sort sed head mktemp paste rm cat; do
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
  printf 'args=%s\n' "$*"
} >"$REAL_RECORD"
CLI
  chmod +x "$BIN/$cli"
done

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

codex_config_has_economical_defaults() {
  python3 - "$HERE/../codex/config.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    config = tomllib.load(handle)

assert config.get("model") == "gpt-5.6-terra"
assert config.get("model_reasoning_effort") == "medium"
availability = config.get("tui", {}).get("model_availability_nux", {})
assert availability.get("gpt-5.6-terra") == 1
assert "gpt-5.6-sol" not in availability
PY
}

# Run one wrapper hermetically. Args: launcher, with_north(0/1), then k=v env
# assignments, then `--` and the wrapper's own argv. Sets globals STDERR/RECORD.
STDERR=""; RECORD=""
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
}
record_field() { sed -n "s/^$2=//p" "$RECORD"; }

# Per-launcher config: provider key + binding limit + the env var a successful
# selection must export into the real CLI.
declare -A PROV=([claude]=anthropic [codex]=openai)
declare -A LIMIT=([claude]="claude:seven_day" [codex]="codex:primary")
declare -A SUB=([claude]=anthropic [codex]=openai)
declare -A PINVAR=([claude]=CLAUDE_CONFIG_DIR [codex]=CODEX_HOME)
declare -A ROOT_DEFAULT_ARGS=(
  [claude]='--model claude-fable-5 --effort xhigh --disallowedTools Agent,Task,Workflow'
  [codex]='-c approval_policy="never" -c sandbox_mode="danger-full-access" -c default_permissions=":danger-full-access" -c model="gpt-5.6-terra" -c model_reasoning_effort="medium" --disable multi_agent'
)
declare -A WARN_DEFAULT_ARGS=(
  [claude]='--model claude-fable-5 --effort xhigh'
  [codex]='-c approval_policy="never" -c sandbox_mode="danger-full-access" -c default_permissions=":danger-full-access" -c model="gpt-5.6-terra" -c model_reasoning_effort="medium"'
)
declare -A PASSTHROUGH_ARGS=(
  [claude]=''
  [codex]='-c approval_policy="never" -c sandbox_mode="danger-full-access" -c default_permissions=":danger-full-access"'
)

check 'codex/global config defaults to economical terra/medium' \
  codex_config_has_economical_defaults

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

  # 9b. The North-native defaults precede explicit user model/effort argv, so
  # the provider CLI's ordinary last-option-wins behavior remains available.
  if [ "$launcher" = claude ]; then
    override_argv=(--model claude-sonnet-5 --effort medium)
    override_suffix='--model claude-sonnet-5 --effort medium'
  else
    override_argv=(--model gpt-5.6-sol -c 'model_reasoning_effort="xhigh"')
    override_suffix='--model gpt-5.6-sol -c model_reasoning_effort="xhigh"'
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
  printf 'dispatch=north\nguards=off\n' >"$HOME_DIR/.local/state/north/harness.conf"

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
      -c 'model="gpt-5.6-terra"' \
      -c 'model_reasoning_effort="medium"' \
      --disable multi_agent \
      --model gpt-5.6-sol \
      --help
fi

printf '\n== result: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
