#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [[ -n "${BEAGLE_PATH:-}" ]]; then
  beagle="$BEAGLE_PATH"
else
  git_common_dir="$({
    timeout --foreground 5 git -C "$repo" rev-parse \
      --path-format=absolute --git-common-dir
  })" || {
    printf 'rebuild-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-rebuild-native.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'rebuild-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'rebuild-native: %s\n' "$*" >&2
  exit 1
}

[[ -x "$beagle/bin/beagle" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

modules="$scratch/modules"
json="$beagle/native-core/src/native/json.bjs"
timeout --foreground 120 "$beagle/bin/beagle" build \
  "$json" \
  "$repo/native/impact.bjs" \
  "$repo/native/impact_test.bjs" \
  "$repo/native/rebuild.bjs" \
  "$repo/native/rebuild_test.bjs" \
  "$repo/native/rebuild_native.bjs" \
  "$repo/native/firn_rebuild_family.bjs" \
  --out "$modules" \
  >"$scratch/rebuild.build.out" 2>"$scratch/rebuild.build.err" \
  || {
    sed -n '1,240p' "$scratch/rebuild.build.err" >&2
    die "rebuild module compilation failed"
  }

bun="${FIRN_BUN:-$(command -v bun || true)}"
[[ -n "$bun" && -x "$bun" ]] || die "Bun runtime is unavailable"

timeout --foreground 30 env \
  FIRN_IMPACT_TEST_MODULE="$modules/firn/impact-test.js" \
  FIRN_REBUILD_TEST_MODULE="$modules/firn/rebuild-test.js" \
  "$bun" "$repo/native/firn_rebuild_test_host.mjs" \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die "pure rebuild fixtures failed"
[[ ! -s "$scratch/pure.out" ]] || die "pure fixtures wrote stdout"
[[ ! -s "$scratch/pure.err" ]] || die "pure fixtures wrote stderr"

fakebin="$scratch/fakebin"
fixture="$scratch/repo"
snapshot="$scratch/snapshot"
mkdir -p "$fakebin" "$fixture/scripts" "$snapshot/scripts"

cat >"$fakebin/command-stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
name=${0##*/}
{
  printf '%s' "$name"
  for argument in "$@"; do
    printf '\t%s' "$argument"
  done
  printf '\n'
} >>"${FIRN_COMMAND_LOG:?}"

case "$name" in
  git)
    if [[ " $* " == *" rev-parse HEAD "* ]]; then
      printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    elif [[ " $* " == *" branch --show-current "* ]]; then
      printf '%s\n' 'native-rebuild-workflow'
    fi
    ;;
  uname)
    printf '%s\n' "${CASE_PLATFORM:?}"
    ;;
  nix)
    if [[ "${BUILD_FAIL:-0}" == 1 ]]; then
      printf 'controlled build failure\n' >&2
      exit 23
    fi
    printf '%s\n' '/nix/store/controlled-system'
    ;;
  nixos-rebuild)
    printf '%s\n' \
      '40 2026-08-19 11:00:00' \
      '42 2026-08-20 10:00:00 True'
    ;;
  darwin-rebuild)
    printf '%s\n' \
      '6 2026-08-19' \
      '7 2026-08-20 current'
    ;;
  readlink)
    if [[ "${1:-}" == -e \
        && "${2:-}" == /nix/var/nix/profiles/system ]]; then
      printf '%s\n' "${PROFILE_TARGET:-/nix/store/controlled-system}"
    elif [[ "${1:-}" == -e \
        && "${2:-}" == /nix/var/nix/profiles/system-40-link ]]; then
      printf '%s\n' '/nix/store/controlled-rollback-system'
    else
      printf 'unresolved generation link: %s\n' "${2:-missing}" >&2
      exit 1
    fi
    ;;
  test)
    if [[ "${1:-}" != -x \
        || ( "${2:-}" != /nix/store/controlled-system/bin/switch-to-configuration \
          && "${2:-}" != /nix/store/controlled-rollback-system/bin/switch-to-configuration ) ]]; then
      printf 'invalid closure check: %s %s\n' \
        "${1:-missing}" "${2:-missing}" >&2
      exit 1
    fi
    ;;
  firn)
    if [[ "${VALIDATE_FAIL:-0}" == 1 ]]; then
      printf 'controlled validation failure\n' >&2
      exit 17
    fi
    ;;
  sudo)
    if [[ "${EXACT_SWITCH_FAIL:-0}" == 1 \
        && "${1:-}" == /nix/store/controlled-system/bin/switch-to-configuration ]]; then
      printf 'controlled exact activation failure\n' >&2
      exit 29
    elif [[ "${ROLLBACK_SWITCH_FAIL:-0}" == 1 \
        && "${1:-}" == */bin/switch-to-configuration ]]; then
      printf 'controlled rollback activation failure\n' >&2
      exit 29
    fi
    ;;
  systemd-run)
    ;;
  *)
    printf 'unexpected fake command: %s\n' "$name" >&2
    exit 97
    ;;
esac
EOF
chmod +x "$fakebin/command-stub"
for command in git uname nix nixos-rebuild darwin-rebuild readlink test firn sudo systemd-run; do
  ln -s command-stub "$fakebin/$command"
done

run_host_case() {
  local name="$1" platform="$2" edge="$3" target="$4"
  shift 4
  : >"$scratch/$name.commands"
  rm -f "$scratch/$name.trace"
  set +e
  timeout --foreground 30 env \
    PATH="$fakebin:$PATH" \
    FIRN_REPO="$fixture" \
    FIRN_SNAPSHOT_DIR="$snapshot" \
    FIRN_TRACE_PATH="$scratch/$name.trace" \
    FIRN_TRACE_ID="$name" \
    FIRN_COMMAND_LOG="$scratch/$name.commands" \
    CASE_PLATFORM="$platform" \
    FIRN_REBUILD_MODULE="$modules/firn/rebuild-family.js" \
    "$@" "$bun" "$repo/native/firn_rebuild_host.mjs" \
    host "$edge" "$target" \
    >"$scratch/$name.out" 2>"$scratch/$name.err"
  local status=$?
  set -e
  printf '%s\n' "$status" >"$scratch/$name.status"
}

run_case() {
  local name="$1" platform="$2"
  shift 2
  run_host_case "$name" "$platform" rebuild whiterabbit "$@"
}

run_case linux Linux env
[[ "$(<"$scratch/linux.status")" == 0 ]] \
  || die "Linux controlled run failed"
cut -f1 "$scratch/linux.commands" >"$scratch/linux.names"
cat >"$scratch/linux.expected-names" <<'EOF'
git
git
uname
git
git
firn
git
nix
sudo
sudo
sudo
nixos-rebuild
git
systemd-run
EOF
cmp -s "$scratch/linux.expected-names" "$scratch/linux.names" \
  || {
    diff -u "$scratch/linux.expected-names" "$scratch/linux.names" >&2 || true
    die "Linux phase order changed"
  }
rg -Fq $'nix\tbuild\t--no-link\t--print-out-paths\tgit+file://' \
  "$scratch/linux.commands" || die "Linux build did not use the snapshot URI"
rg -Fq $'sudo\tnix-env\t--profile\t/nix/var/nix/profiles/system' \
  "$scratch/linux.commands" || die "Linux profile activation changed"
rg -Fq $'git\t-C\t'"$fixture"$'\ttag\t-f\tgen-42' \
  "$scratch/linux.commands" || die "Linux generation was not tagged"
[[ "$(rg -c 'span_start' "$scratch/linux.trace")" == 14 ]] \
  || die "Linux trace start count changed"
[[ "$(rg -c 'span_end' "$scratch/linux.trace")" == 14 ]] \
  || die "Linux trace end count changed"

run_host_case prepare Linux prepare whiterabbit env
[[ "$(<"$scratch/prepare.status")" == 0 ]] \
  || die "controlled preparation failed"
rg -Fq $'nix\tbuild\t--no-link\t--print-out-paths\tgit+file://' \
  "$scratch/prepare.commands" \
  || die "preparation did not build the exact snapshot"
if rg -q 'sudo|nix-env|switch-to-configuration|nixos-rebuild|darwin-rebuild' \
    "$scratch/prepare.commands"; then
  die "activation leaked into preparation"
fi
rg -Fq \
  'firn prepare: prepared aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa /nix/store/controlled-system' \
  "$scratch/prepare.out" || die "preparation receipt is missing"

run_host_case activate Linux activate /nix/store/controlled-system env
[[ "$(<"$scratch/activate.status")" == 0 ]] \
  || die "controlled exact activation failed"
cut -f1 "$scratch/activate.commands" >"$scratch/activate.names"
cat >"$scratch/activate.expected-names" <<'EOF'
test
sudo
sudo
readlink
sudo
EOF
cmp -s "$scratch/activate.expected-names" "$scratch/activate.names" \
  || {
    diff -u "$scratch/activate.expected-names" \
      "$scratch/activate.names" >&2 || true
    die "exact activation did not persist before switching"
  }
if rg -q $'^git\t|^nix\t|^firn\t|worktree|darwin-rebuild' \
    "$scratch/activate.commands"; then
  die "preparation or evaluation leaked into exact activation"
fi
rg -Fq \
  $'test\t-x\t/nix/store/controlled-system/bin/switch-to-configuration' \
  "$scratch/activate.commands" \
  || die "exact activation did not validate the selected toplevel"
rg -Fq \
  $'sudo\tnix-env\t--profile\t/nix/var/nix/profiles/system\t--set\t/nix/store/controlled-system' \
  "$scratch/activate.commands" \
  || die "exact activation did not select the exact system profile"
rg -Fq $'readlink\t-e\t/nix/var/nix/profiles/system' \
  "$scratch/activate.commands" \
  || die "exact activation did not verify the persistent system profile"
rg -Fq 'firn activate: activated /nix/store/controlled-system' \
  "$scratch/activate.out" || die "exact activation receipt is missing"

run_host_case activate-profile-mismatch Linux activate \
  /nix/store/controlled-system env PROFILE_TARGET=/nix/store/other-system
[[ "$(<"$scratch/activate-profile-mismatch.status")" == 65 ]] \
  || die "mismatched persistent profile was accepted"
if rg -q $'^sudo\t.*/bin/switch-to-configuration' \
    "$scratch/activate-profile-mismatch.commands"; then
  die "configuration switched before the persistent profile was verified"
fi
rg -Fq \
  'persistent system profile resolved to /nix/store/other-system instead of /nix/store/controlled-system; no configuration switch was attempted' \
  "$scratch/activate-profile-mismatch.err" \
  || die "persistent profile mismatch recovery is not actionable"

run_host_case activate-switch-failure Linux activate \
  /nix/store/controlled-system env EXACT_SWITCH_FAIL=1
[[ "$(<"$scratch/activate-switch-failure.status")" == 29 ]] \
  || die "exact switch failure status was not preserved"
rg -Fq \
  'persistent system profile is /nix/store/controlled-system, but configuration switching failed (status 29); running and boot state may be incomplete' \
  "$scratch/activate-switch-failure.err" \
  || die "exact switch failure did not report the verified recovery boundary"

run_host_case activate-invalid Linux activate relative-system env
[[ "$(<"$scratch/activate-invalid.status")" == 64 ]] \
  || die "relative activation target was accepted"
[[ ! -s "$scratch/activate-invalid.commands" ]] \
  || die "invalid activation target executed an effect"

run_case darwin Darwin env
[[ "$(<"$scratch/darwin.status")" == 0 ]] \
  || die "Darwin controlled run failed"
rg -Fq $'sudo\tdarwin-rebuild\tswitch\t--flake\tgit+file://' \
  "$scratch/darwin.commands" || die "Darwin activation was not selected"
rg -Fq $'darwin-rebuild\t--list-generations' \
  "$scratch/darwin.commands" || die "Darwin generation query changed"
rg -Fq $'\ttag\t-f\tgen-7\t' "$scratch/darwin.commands" \
  || die "Darwin generation was not tagged"
if rg -q 'nix-env|switch-to-configuration|systemd-run' \
    "$scratch/darwin.commands"; then
  die "Linux activation leaked into the Darwin plan"
fi

run_case build-failure Linux env BUILD_FAIL=1
[[ "$(<"$scratch/build-failure.status")" == 23 ]] \
  || die "build failure status was not preserved"
if rg -q 'nix-env|switch-to-configuration|nixos-rebuild|darwin-rebuild|tag|systemd-run' \
    "$scratch/build-failure.commands"; then
  die "activation or tagging ran after a failed build"
fi
rg -Fq '"name":"build committed snapshot","status":"error"' \
  "$scratch/build-failure.trace" \
  || die "failed build trace event is missing"

run_case validation-failure Linux env VALIDATE_FAIL=1
[[ "$(<"$scratch/validation-failure.status")" == 17 ]] \
  || die "validation failure status was not preserved"
if rg -q $'^nix\t|worktree\tremove|nix-env|switch-to-configuration' \
    "$scratch/validation-failure.commands"; then
  die "a later phase ran after failed validation"
fi

run_rollback_case() {
  local name="$1" platform="$2" generation="$3"
  shift 3
  : >"$scratch/$name.commands"
  rm -f "$scratch/$name.trace"
  set +e
  timeout --foreground 30 env \
    PATH="$fakebin:$PATH" \
    FIRN_TRACE_PATH="$scratch/$name.trace" \
    FIRN_TRACE_ID="$name" \
    FIRN_COMMAND_LOG="$scratch/$name.commands" \
    CASE_PLATFORM="$platform" \
    "$@" "$scratch/rebuild-native" host rollback "$generation" \
    >"$scratch/$name.out" 2>"$scratch/$name.err"
  local status=$?
  set -e
  printf '%s\n' "$status" >"$scratch/$name.status"
}

run_rollback_case rollback-invalid Linux latest env
[[ "$(<"$scratch/rollback-invalid.status")" == 64 ]] \
  || die "non-generation rollback target was accepted"
[[ ! -s "$scratch/rollback-invalid.commands" ]] \
  || die "invalid rollback target executed an effect"
rg -Fq 'target must be an exact positive decimal generation' \
  "$scratch/rollback-invalid.err" \
  || die "invalid rollback target did not explain the required form"

run_rollback_case rollback-missing Linux 41 env
[[ "$(<"$scratch/rollback-missing.status")" == 65 ]] \
  || die "missing rollback generation was accepted"
if rg -q 'readlink|test|sudo|switch-generation|switch-to-configuration' \
    "$scratch/rollback-missing.commands"; then
  die "missing rollback generation reached resolution or activation"
fi
rg -Fq 'generation 41 is not present in the system profile' \
  "$scratch/rollback-missing.err" \
  || die "missing rollback generation was not actionable"

run_rollback_case rollback-success Linux 40 env
[[ "$(<"$scratch/rollback-success.status")" == 0 ]] \
  || die "controlled rollback failed"
cut -f1 "$scratch/rollback-success.commands" \
  >"$scratch/rollback-success.names"
cat >"$scratch/rollback-success.expected-names" <<'EOF'
uname
nixos-rebuild
readlink
test
sudo
sudo
sudo
EOF
cmp -s "$scratch/rollback-success.expected-names" \
  "$scratch/rollback-success.names" \
  || {
    diff -u "$scratch/rollback-success.expected-names" \
      "$scratch/rollback-success.names" >&2 || true
    die "rollback effect order changed"
  }
rg -Fq $'readlink\t-e\t/nix/var/nix/profiles/system-40-link' \
  "$scratch/rollback-success.commands" \
  || die "rollback did not resolve the exact generation link"
rg -Fq $'sudo\tnix-env\t--profile\t/nix/var/nix/profiles/system\t--switch-generation\t40' \
  "$scratch/rollback-success.commands" \
  || die "rollback did not select the exact profile generation"
rg -Fq $'sudo\t/nix/store/controlled-rollback-system/bin/switch-to-configuration\tswitch' \
  "$scratch/rollback-success.commands" \
  || die "rollback did not activate the resolved closure"
rg -Fq 'firn rollback: activated generation 40 (/nix/store/controlled-rollback-system)' \
  "$scratch/rollback-success.out" \
  || die "rollback success receipt is missing"
[[ "$(rg -c 'span_start' "$scratch/rollback-success.trace")" == 7 ]] \
  || die "rollback trace start count changed"
[[ "$(rg -c 'span_end' "$scratch/rollback-success.trace")" == 7 ]] \
  || die "rollback trace end count changed"

run_rollback_case rollback-failure Linux 40 env ROLLBACK_SWITCH_FAIL=1
[[ "$(<"$scratch/rollback-failure.status")" == 29 ]] \
  || die "rollback activation failure status was not preserved"
if rg -q 'firn rollback: activated generation' \
    "$scratch/rollback-failure.out"; then
  die "failed rollback emitted a success receipt"
fi
rg -Fq 'verify the active generation before retrying' \
  "$scratch/rollback-failure.err" \
  || die "rollback failure did not report the uncertain active state"
rg -Fq '"name":"activate verified closure","status":"error"' \
  "$scratch/rollback-failure.trace" \
  || die "rollback failure trace event is missing"

if ldd "$scratch/rebuild-native" \
    | rg -qi 'racket|clojure|babashka|java'; then
  die "hosted runtime leaked into native executable"
fi

printf 'ok: native rebuild core stops on first failure and selects exact activation\n'
