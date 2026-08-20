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
    printf 'repo-workflows-native: cannot locate Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-repo-workflows.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'repo-workflows-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'repo-workflows-native: %s\n' "$*" >&2
  exit 1
}

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

datum="$beagle/native-core/src/beagle/datum_reader.bgl"
quality="$repo/native/repo_quality.bgl"
workflows="$repo/native/repo_workflows.bgl"

build_native repo-workflows-test firn.repo-workflows-test/-main \
  "$datum" "$quality" "$workflows" \
  "$repo/native/repo_workflows_test.bgl"
build_native repo-workflows-native firn.repo-workflows-native/-main \
  "$datum" "$quality" "$workflows" \
  "$repo/native/repo_workflows_native.bgl"

"$scratch/repo-workflows-test" >"$scratch/pure.out"
[[ "$(rg -c '^PASS ' "$scratch/pure.out")" == "4" ]] \
  || die "focused pure cases did not all pass"

set +e
"$scratch/repo-workflows-native" repo unknown \
  >"$scratch/usage.out" 2>"$scratch/usage.err"
usage_status=$?
set -e
[[ "$usage_status" == "64" ]] || die "invalid argv did not return 64"
[[ ! -s "$scratch/usage.out" ]] || die "invalid argv wrote stdout"

if ldd "$scratch/repo-workflows-native" \
    | rg -qi 'racket|clojure|babashka|java'; then
  die "hosted runtime leaked into native executable"
fi

printf 'PASS repo-workflows-native\n'
