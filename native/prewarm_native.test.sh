#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [[ -n "${BEAGLE_PATH:-}" ]]; then
  beagle="$BEAGLE_PATH"
else
  git_common_dir="$(
    timeout --foreground 5 git -C "$repo" rev-parse \
      --path-format=absolute --git-common-dir
  )" || {
    printf 'prewarm-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-prewarm-native.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'prewarm-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'prewarm-native: %s\n' "$*" >&2
  exit 1
}

[[ -x "$beagle/bin/beagle" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

build_native() {
  local name="$1" entry="$2"
  shift 2
  local output="$scratch/$name"
  mkdir -p "$scratch/$name-artifacts"
  printf 'prewarm-native: building %s\n' "$name" >&2
  timeout --foreground 180 "$beagle/bin/beagle" native-exe \
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

build_native prewarm-test firn.prewarm-test/-main \
  "$repo/native/prewarm.bgl" \
  "$repo/native/prewarm_test.bgl"

printf 'prewarm-native: running pure policy fixtures\n' >&2
timeout --foreground 30 "$scratch/prewarm-test" \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die "pure prewarm policy fixtures failed"
[[ ! -s "$scratch/pure.out" ]] || die "pure fixtures wrote stdout"
[[ ! -s "$scratch/pure.err" ]] || die "pure fixtures wrote stderr"

build_native prewarm-native firn.prewarm-native/-main \
  "$repo/native/prewarm.bgl" \
  "$repo/native/prewarm_native.bgl"

container="$scratch/container"
main="$container/main"
lane="$container/worktrees/slug"
runtime="$scratch/runtime"
host="$(hostname)"
mkdir -p "$main/native" "$main/hosts/$host" "$container/worktrees" "$runtime"
printf '#lang beagle\n(ns firn.main)\n' >"$main/native/firn.bgl"
printf '#lang beagle/nix\n(ns flake)\n' >"$main/flake.bnix"
printf 'fixture\n' >"$main/hosts/$host/marker"
git init -q -b main "$main"
git -C "$main" add -- native/firn.bgl flake.bnix "hosts/$host/marker"
git -C "$main" \
  -c user.name=prewarm-test \
  -c user.email=prewarm-test@example.invalid \
  commit -qm base
git -C "$main" worktree add -q -b slug "$lane"

head_sha="$(git -C "$main" rev-parse HEAD)"
case "$(uname -s)" in
  Darwin) attr="darwinConfigurations.$host.system" ;;
  *) attr="nixosConfigurations.$host.config.system.build.toplevel" ;;
esac
expected_key="git+file://$main?rev=$head_sha&ref=main#$attr"

printf 'prewarm-native: resolving the container-main warm key\n' >&2
actual_key="$(
  FIRN_REPO="$lane" XDG_RUNTIME_DIR="$runtime" \
    timeout --foreground 30 "$scratch/prewarm-native" --print-warm-key
)"
[[ "$actual_key" == "$expected_key" ]] || {
  printf 'want: %s\ngot:  %s\n' "$expected_key" "$actual_key" >&2
  die "container-main warm key changed"
}

FIRN_REPO="$lane" XDG_RUNTIME_DIR="$runtime" \
  timeout --foreground 30 "$scratch/prewarm-native" \
    --plan-detached "$scratch/prewarm-native" \
    >"$scratch/detached.plan"
cat >"$scratch/detached.expected" <<EOF
setsid
-f
nice
-n
19
ionice
-c
3
$scratch/prewarm-native
--worker
$scratch/prewarm-native
$main
$expected_key
EOF
cmp -s "$scratch/detached.expected" "$scratch/detached.plan" \
  || {
    diff -u "$scratch/detached.expected" "$scratch/detached.plan" >&2 || true
    die "detached low-priority argv plan changed"
  }

zero=0000000000000000000000000000000000000000
line="$zero $head_sha refs/heads/main"
FIRN_REPO="$lane" XDG_RUNTIME_DIR="$runtime" \
  timeout --foreground 30 "$scratch/prewarm-native" \
    --plan-reference-transaction "$scratch/prewarm-native" prepared "$line" \
    >"$scratch/prepared.plan"
[[ ! -s "$scratch/prepared.plan" ]] \
  || die "prepared reference transaction planned a launch"

FIRN_REPO="$lane" XDG_RUNTIME_DIR="$runtime" \
  timeout --foreground 30 "$scratch/prewarm-native" \
    --plan-reference-transaction "$scratch/prewarm-native" committed \
    "$zero $head_sha refs/heads/lane" "$line" \
    >"$scratch/committed.plan"
cmp -s "$scratch/detached.expected" "$scratch/committed.plan" \
  || die "committed main update did not plan exactly one detached worker"

[[ ! -e "$runtime/firn-prewarm.lease" ]] \
  || die "planning unexpectedly acquired the live prewarm lease"
[[ ! -e "$main/.git/hooks/reference-transaction" ]] \
  || die "controlled test unexpectedly installed a Git hook"

if ldd "$scratch/prewarm-native" \
    | rg -qi 'racket|clojure|babashka|java'; then
  die "hosted runtime leaked into native executable"
fi

printf 'ok: native Firn prewarm policy and controlled plans pass\n'
