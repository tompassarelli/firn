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
mkdir -p "$BIN" "$NBIN"
for tool in env bash realpath jq find sort sed head mktemp paste rm cat; do
  real="$(command -v "$tool" 2>/dev/null)" || { echo "missing host tool: $tool" >&2; exit 2; }
  # Link straight to the resolved command-v path; do NOT depend on `readlink`
  # (agent-config-check.test.sh runs this under a readlink-fails shim).
  ln -s "$real" "$BIN/$tool"
done

# Stub north: env-driven so one script covers every backend outcome.
cat >"$NBIN/north" <<'NORTH'
#!/usr/bin/env bash
[ -n "${NORTH_STDERR:-}" ] && printf '%s\n' "$NORTH_STDERR" >&2
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
    "${envv[@]}" bash "$HERE/$launcher" "${argv[@]}" 2>&1 1>/dev/null)"
}
record_field() { sed -n "s/^$2=//p" "$RECORD"; }

# Per-launcher config: provider key + binding limit + the env var a successful
# selection must export into the real CLI.
declare -A PROV=([claude]=anthropic [codex]=openai)
declare -A LIMIT=([claude]="claude:seven_day" [codex]="codex:primary")
declare -A SUB=([claude]=anthropic [codex]=openai)
declare -A PINVAR=([claude]=CLAUDE_CONFIG_DIR [codex]=CODEX_HOME)

for launcher in claude codex; do
  prov="${PROV[$launcher]}"; limit="${LIMIT[$launcher]}"
  sub="${SUB[$launcher]}"; pinvar="${PINVAR[$launcher]}"

  # Fresh $HOME per launcher; account roots live under it.
  HOME_DIR="$SCRATCH/home-$launcher"
  ROOT="$HOME_DIR/.local/state/north/accounts/$sub"
  mkdir -p "$ROOT"

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
    test "$(record_field _ args)" = "extra --flag"
  if [ "$launcher" = codex ]; then
    check "codex/success also exports CODEX_SQLITE_HOME" \
      test "$(record_field _ CODEX_SQLITE_HOME)" = "$ROOT/acctA/sqlite"
  fi

  # 8. explicit `as <id>` pin bypasses north entirely (dir present).
  run "$launcher" 0 -- as acctA hello ; s="$STDERR"
  check "$launcher/explicit-pin exports the pin env" \
    test "$(record_field _ "$pinvar")" = "$ROOT/acctA"
  check "$launcher/explicit-pin forwards argv after id" \
    test "$(record_field _ args)" = "hello"
  check "$launcher/explicit-pin prints no auto banner" not_contains "$s" "→ ambient]"

  # 8b. explicit `as <unknown>` errors, does not exec the real CLI.
  run "$launcher" 0 -- as ghost ; s="$STDERR"
  check "$launcher/explicit-unknown reports unknown account" contains "$s" "unknown account 'ghost'"
  check "$launcher/explicit-unknown never exec'd the real CLI" test ! -f "$RECORD"

  # 9. already-pinned passthrough: env var set -> exec straight through, silent.
  run "$launcher" 1 "$pinvar=$ROOT/acctA" "NORTH_JSON=$eligible" -- ; s="$STDERR"
  check "$launcher/passthrough emits no banner" test -z "$s"
  check "$launcher/passthrough preserves the caller pin" \
    test "$(record_field _ "$pinvar")" = "$ROOT/acctA"
done

printf '\n== result: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
