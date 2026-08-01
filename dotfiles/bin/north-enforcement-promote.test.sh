#!/usr/bin/env bash
# Logic tests for north-enforcement-promote. The privileged step (chown root) is
# factored behind NORTH_ENFORCEMENT_UNPRIVILEGED so the whole transaction —
# revision resolution, payload selection, sealing, manifest, record, atomic swap,
# rollback — runs unprivileged against a fixture root.
set -euo pipefail

PROMOTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/north-enforcement-promote"
FAILURES=0
CASES=0

fail() {
  printf 'FAIL %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

check() {
  CASES=$((CASES + 1))
  if ! "${@:2}"; then fail "$1"; fi
}

check_eq() {
  CASES=$((CASES + 1))
  if [ "$2" != "$3" ]; then
    fail "$1: expected '$3', got '$2'"
  fi
}

check_contains() {
  CASES=$((CASES + 1))
  case "$2" in
    *"$3"*) ;;
    *) fail "$1: output does not contain '$3'" ;;
  esac
}

resolve_dir() {
  (cd -P -- "$1" && pwd -P)
}

WORK="$(mktemp -d)"
trap 'chmod -R u+w "$WORK" 2>/dev/null || true; rm -rf -- "${WORK:?}"' EXIT

export NORTH_ENFORCEMENT_UNPRIVILEGED=1
export NORTH_ENFORCEMENT_STATE_ROOT="$WORK/state"

NORTH="$WORK/north"
BEAGLE_FIXTURE="$WORK/beagle"
BEAGLE="${NORTH_ENFORCEMENT_TEST_BEAGLE_REPO:-$BEAGLE_FIXTURE}"

git_init() {
  git init -q -b main "$1"
  git -C "$1" config user.email test@example.invalid
  git -C "$1" config user.name 'promote test'
}

commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -qm "$2"
  git -C "$1" rev-parse HEAD
}

# Fixture North: the hook tree (including a cross-repo symlink that must not be
# promoted, and a nested lib/ that must be), plus the lifecycle runtimes.
git_init "$NORTH"
mkdir -p "$NORTH/profiles/tom/hooks/lib" "$NORTH/bin"
printf 'guard v1\n' >"$NORTH/profiles/tom/hooks/agent-spawn-guard.sh"
printf 'registry v1\n' >"$NORTH/profiles/tom/hooks/registry.tsv"
printf 'dial v1\n' >"$NORTH/profiles/tom/hooks/lib/harness-dial.sh"
ln -s ../../../../../fram/main/integrations/north/hooks/code-upstream-guard.sh \
  "$NORTH/profiles/tom/hooks/code-upstream-guard.sh"
printf 'spawn v1\n' >"$NORTH/bin/north-on-spawn"
printf 'tooluse v1\n' >"$NORTH/bin/north-on-tooluse"
printf 'stop v1\n' >"$NORTH/bin/north-on-stop"
printf 'delegated v1\n' >"$NORTH/bin/north-mark-delegated"
NORTH_V1="$(commit_all "$NORTH" 'north v1')"

if [ "$BEAGLE" = "$BEAGLE_FIXTURE" ]; then
  git_init "$BEAGLE"
  mkdir -p "$BEAGLE/integrations/north/hooks" "$BEAGLE/share"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'dir="$PWD"' \
    'hook_root="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../.." && pwd)"' \
    '. "$hook_root/share/targets.sh"' \
    'for target in "${BEAGLE_TARGET_IDS[@]}"; do' \
    '  extension="${BEAGLE_TARGET_SRC_EXT[$target]}"' \
    '  for source in "$dir"/*."$extension" "$dir"/src/*."$extension"; do' \
    '    [ -e "$source" ] || continue' \
    '    printf "%s\\n" "Beagle authoring is active."' \
    '    exit 0' \
    '  done' \
    'done' \
    >"$BEAGLE/integrations/north/hooks/beagle-session-start.sh"
  printf 'racket v1\n' >"$BEAGLE/integrations/north/hooks/racket-build-guard.sh"
  printf '%s\n' \
    'BEAGLE_TARGET_IDS=(nix zig)' \
    'declare -A BEAGLE_TARGET_SRC_EXT=([nix]=bnix [zig]=bzig)' \
    >"$BEAGLE/share/targets.sh"
  BEAGLE_V1="$(commit_all "$BEAGLE" 'beagle v1')"
else
  BEAGLE_V1="$({ git -C "$BEAGLE" rev-parse --verify "${NORTH_ENFORCEMENT_TEST_BEAGLE_REV:-HEAD}^{commit}"; } 2>/dev/null)" || {
    printf 'invalid committed Beagle source: %s@%s\n' \
      "$BEAGLE" "${NORTH_ENFORCEMENT_TEST_BEAGLE_REV:-HEAD}" >&2
    exit 1
  }
fi

promote() {
  "$PROMOTE" "$@" --north-repo "$NORTH" --beagle-repo "$BEAGLE"
}

# --- a promote must state why -------------------------------------------------
status=0
out="$(promote "$NORTH_V1" 2>&1)" || status=$?
check_eq 'promote without --why exits 2' "$status" 2
check_contains 'promote without --why explains itself' "$out" 'must record --why'

# --- first promote ------------------------------------------------------------
record="$(promote "$NORTH_V1" --beagle-rev "$BEAGLE_V1" --why 'initial seed')"
ID="north-$NORTH_V1.beagle-$BEAGLE_V1"
DEPLOY="$NORTH_ENFORCEMENT_STATE_ROOT/deployments/$ID"
CURRENT="$NORTH_ENFORCEMENT_STATE_ROOT/active/current"

check_contains 'record declares its format' "$record" 'FORMAT north-enforcement-promote/v1'
check_contains 'record names the deployment id' "$record" "ID $ID"
check_contains 'record pins the North revision' "$record" "NORTH_REV $NORTH_V1"
check_contains 'record pins the Beagle revision' "$record" "BEAGLE_REV $BEAGLE_V1"
check_contains 'record carries why' "$record" 'WHY initial seed'
check_contains 'record names who promoted' "$record" "WHO $(id -un)"

check 'active/current resolves to the deployment' \
  test "$(resolve_dir "$CURRENT")" = "$(resolve_dir "$DEPLOY")"
check 'first promote makes previous the same deployment' \
  test "$(resolve_dir "$NORTH_ENFORCEMENT_STATE_ROOT/active/previous")" = "$(resolve_dir "$DEPLOY")"

# --- payload selection --------------------------------------------------------
check 'North hook tree is promoted' \
  test -f "$CURRENT/north/profiles/tom/hooks/agent-spawn-guard.sh"
check 'nested North hook lib is promoted' \
  test -f "$CURRENT/north/profiles/tom/hooks/lib/harness-dial.sh"
check 'non-script hook data is promoted' \
  test -f "$CURRENT/north/profiles/tom/hooks/registry.tsv"
check 'lifecycle runtimes are promoted' \
  test -f "$CURRENT/north/bin/north-on-spawn"
check 'Beagle Codex hooks are promoted under their own provenance' \
  test -f "$CURRENT/beagle/integrations/north/hooks/racket-build-guard.sh"
check 'Beagle target metadata is promoted under the hook-relative root' \
  test -f "$CURRENT/beagle/share/targets.sh"
check 'a cross-repo symlink is not promoted' \
  test ! -e "$CURRENT/north/profiles/tom/hooks/code-upstream-guard.sh"
check_eq 'promoted content is the committed blob' \
  "$(cat "$CURRENT/north/bin/north-on-spawn")" 'spawn v1'

SOURCE_PROJECT="$WORK/beagle-source-project"
BEAGLE_TOOLCHAIN="$WORK/beagle-toolchain"
mkdir -p "$SOURCE_PROJECT" "$BEAGLE_TOOLCHAIN/bin" "$WORK/home" "$WORK/session-state"
touch "$SOURCE_PROJECT/main.bzig"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$BEAGLE_TOOLCHAIN/bin/beagle"
chmod +x "$BEAGLE_TOOLCHAIN/bin/beagle"
check 'extension-only Beagle fixture has no marker directory' \
  test ! -e "$SOURCE_PROJECT/.beagle"
hook_output="$(
  cd "$SOURCE_PROJECT" &&
    env HOME="$WORK/home" \
      BEAGLE_PATH="$BEAGLE_TOOLCHAIN" \
      BEAGLE_SESSION_STATE_DIR="$WORK/session-state" \
      AGENT_NO_AUTHORING_HOOKS=0 \
      bash "$CURRENT/beagle/integrations/north/hooks/beagle-session-start.sh" </dev/null
)"
check_contains 'sealed SessionStart detects an extension-only Beagle project' \
  "$hook_output" 'Beagle authoring is active.'

# --- sealing ------------------------------------------------------------------
unsealed=0
while IFS= read -r file; do
  [ "$(stat -c '%u:%a:%h' "$file")" = "$EUID:444:1" ] || unsealed=$((unsealed + 1))
done < <(find "$DEPLOY" -type f)
check_eq 'every deployed file is sealed read-only, unshared, owner-attested' "$unsealed" 0

open_dirs=0
while IFS= read -r dir; do
  [ "$(stat -c '%a' "$dir")" = 555 ] || open_dirs=$((open_dirs + 1))
done < <(find "$DEPLOY" -type d)
check_eq 'every deployed directory is read-only' "$open_dirs" 0

# --- manifest attests each file ----------------------------------------------
manifest_bad=0
while read -r _ digest relative; do
  [ "$(sha256sum <"$DEPLOY/$relative" | cut -d' ' -f1)" = "$digest" ] ||
    manifest_bad=$((manifest_bad + 1))
done < <(printf '%s\n' "$record" | grep '^FILE ')
check_eq 'record sha256 matches every deployed file' "$manifest_bad" 0
check_eq 'record covers exactly the deployed file set' \
  "$(printf '%s\n' "$record" | grep -c '^FILE ')" \
  "$(find "$DEPLOY" -type f | wc -l)"

# --- idempotent re-promote ----------------------------------------------------
record_again="$(promote "$NORTH_V1" --beagle-rev "$BEAGLE_V1" --why 'same revisions again')"
check_contains 're-promote of the same revisions reuses the deployment' "$record_again" "ID $ID"
check 'reused deployment is still the active one' \
  test "$(resolve_dir "$CURRENT")" = "$(resolve_dir "$DEPLOY")"

# --- second promote retains the previous deployment ---------------------------
printf 'guard v2\n' >"$NORTH/profiles/tom/hooks/agent-spawn-guard.sh"
NORTH_V2="$(commit_all "$NORTH" 'north v2')"
ID2="north-$NORTH_V2.beagle-$BEAGLE_V1"
record2="$(promote "$NORTH_V2" --beagle-rev "$BEAGLE_V1" --why 'ship guard v2')"
check_contains 'second promote records the previous deployment' "$record2" "PREVIOUS $ID"
check_eq 'active content advanced' "$(cat "$CURRENT/north/profiles/tom/hooks/agent-spawn-guard.sh")" 'guard v2'
check_eq 'previous deployment is retained intact' \
  "$(cat "$NORTH_ENFORCEMENT_STATE_ROOT/active/previous/north/profiles/tom/hooks/agent-spawn-guard.sh")" \
  'guard v1'

# --- status -------------------------------------------------------------------
status_out="$("$PROMOTE" status)"
check_contains 'status reports the active deployment' "$status_out" "$ID2"
check_contains 'status prints the promote record' "$status_out" 'FORMAT north-enforcement-promote/v1'

# --- rollback is a promote of the retained previous ---------------------------
rollback_record="$("$PROMOTE" rollback --why 'guard v2 regressed')"
check_contains 'rollback records why' "$rollback_record" 'WHY rollback: guard v2 regressed'
check_contains 'rollback re-pins the previous revision' "$rollback_record" "NORTH_REV $NORTH_V1"
check_eq 'rollback restores the previous payload' \
  "$(cat "$CURRENT/north/profiles/tom/hooks/agent-spawn-guard.sh")" 'guard v1'
check_eq 'rollback retains the rolled-back deployment as previous' \
  "$(cat "$NORTH_ENFORCEMENT_STATE_ROOT/active/previous/north/profiles/tom/hooks/agent-spawn-guard.sh")" \
  'guard v2'
rollback_again="$("$PROMOTE" rollback --why 'undo the undo')"
check_eq 'rollback is itself rollback-able' \
  "$(cat "$CURRENT/north/profiles/tom/hooks/agent-spawn-guard.sh")" 'guard v2'
check_contains 'second rollback is recorded' "$rollback_again" 'WHY rollback: undo the undo'

# --- tamper detection ---------------------------------------------------------
chmod u+w "$DEPLOY" "$DEPLOY/north/bin" "$DEPLOY/north/bin/north-on-spawn"
printf 'tampered\n' >"$DEPLOY/north/bin/north-on-spawn"
chmod 0444 "$DEPLOY/north/bin/north-on-spawn"
chmod 0555 "$DEPLOY/north/bin" "$DEPLOY"
status=0
out="$(promote "$NORTH_V1" --beagle-rev "$BEAGLE_V1" --why 'promote over a tampered tree' 2>&1)" || status=$?
check_eq 'a tampered deployment fails the promote' "$status" 1
check_contains 'tamper is reported as content divergence' "$out" 'differs from its promote manifest'

# --- a payload entry that is not a file is a promote error --------------------
BROKEN="$WORK/broken"
git_init "$BROKEN"
mkdir -p "$BROKEN/integrations/north/hooks"
printf 'session\n' >"$BROKEN/integrations/north/hooks/beagle-session-start.sh"
BROKEN_REV="$(commit_all "$BROKEN" 'missing racket-build-guard')"
status=0
out="$("$PROMOTE" "$NORTH_V1" --beagle-rev "$BROKEN_REV" --north-repo "$NORTH" \
  --beagle-repo "$BROKEN" --why 'incomplete payload' 2>&1)" || status=$?
check_eq 'an absent payload entry fails the promote' "$status" 1
check_contains 'the absent payload entry is named' "$out" 'racket-build-guard.sh'

# --- an unknown revision is a promote error -----------------------------------
status=0
out="$(promote 0000000000000000000000000000000000000000 --why 'nonexistent' 2>&1)" || status=$?
check_eq 'an unknown revision fails the promote' "$status" 1
check_contains 'the unknown revision is named' "$out" 'not a commit'

if [ "$FAILURES" -eq 0 ]; then
  printf 'north-enforcement-promote: %d checks passed\n' "$CASES"
else
  printf 'north-enforcement-promote: %d of %d checks failed\n' "$FAILURES" "$CASES" >&2
  exit 1
fi
