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

build_native() {
  local name="$1" entry="$2"
  shift 2
  local output="$scratch/$name"
  mkdir -p "$scratch/$name-artifacts"
  timeout --foreground 620 "$beagle/bin/beagle" native-exe \
    --out "$output" \
    --entry "$entry" \
    --artifacts "$scratch/$name-artifacts" \
    "$@" >"$scratch/$name.build.out" 2>"$scratch/$name.build.err" \
    || {
      sed -n '1,240p' "$scratch/$name.build.err" >&2
      die "$name compilation failed"
    }
  [[ -x "$output" ]] || die "$name is not executable"
}

json="$beagle/native-core/src/native/json.bgl"
core="$repo/native/rebuild.bgl"
native="$repo/native/rebuild_native.bgl"

build_native rebuild-test firn.rebuild-test/-main \
  "$core" "$repo/native/rebuild_test.bgl"
build_native rebuild-native firn.rebuild-native/-main \
  "$json" "$core" "$native"

timeout --foreground 30 "$scratch/rebuild-test" \
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
  firn)
    if [[ "${VALIDATE_FAIL:-0}" == 1 ]]; then
      printf 'controlled validation failure\n' >&2
      exit 17
    fi
    ;;
  sudo|systemd-run)
    ;;
  *)
    printf 'unexpected fake command: %s\n' "$name" >&2
    exit 97
    ;;
esac
EOF
chmod +x "$fakebin/command-stub"
for command in git uname nix nixos-rebuild darwin-rebuild firn sudo systemd-run; do
  ln -s command-stub "$fakebin/$command"
done

run_case() {
  local name="$1" platform="$2"
  shift 2
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
    "$@" "$scratch/rebuild-native" host rebuild whiterabbit \
    >"$scratch/$name.out" 2>"$scratch/$name.err"
  local status=$?
  set -e
  printf '%s\n' "$status" >"$scratch/$name.status"
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
sudo
git
firn
git
nix
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

if ldd "$scratch/rebuild-native" \
    | rg -qi 'racket|clojure|babashka|java'; then
  die "hosted runtime leaked into native executable"
fi

printf 'ok: native rebuild core stops on first failure and selects exact activation\n'
