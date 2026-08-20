#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
beagle="${BEAGLE_PATH:?BEAGLE_PATH must name the Beagle checkout}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-repo-build-native.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'repo-build-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'repo-build-native: %s\n' "$*" >&2
  exit 1
}

[[ -x "$beagle/bin/beagle" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

build_native() {
  local name="$1" entry="$2"
  shift 2
  local output="$scratch/$name"
  mkdir -p "$scratch/$name-artifacts"
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

core="$repo/native/repo_build.bgl"
build_native repo-build-test firn.repo-build-test/-main \
  "$core" "$repo/native/repo_build_test.bgl"

timeout --foreground 30 "$scratch/repo-build-test" \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die "pure repository-build fixtures failed"
[[ ! -s "$scratch/pure.out" ]] || die "pure fixtures wrote stdout"
[[ ! -s "$scratch/pure.err" ]] || die "pure fixtures wrote stderr"

datum="$beagle/native-core/src/beagle/datum_reader.bgl"
json="$beagle/native-core/src/native/json.bgl"
tag_resolve="$repo/native/tag_resolve.bgl"
tag_inputs="$repo/native/tag_inputs.bgl"
tag_driver="$repo/native/tag_resolve_driver.bgl"
tag_native="$repo/native/tag_resolve_native.bgl"
flake_input="$repo/native/flake_input.bgl"
flake_driver="$repo/native/flake_input_driver.bgl"
flake_native="$repo/native/flake_input_native.bgl"

build_native repo-build-native firn.repo-build-native/-main \
  "$datum" "$json" "$tag_resolve" "$tag_inputs" \
  "$tag_driver" "$tag_native" "$flake_input" "$flake_driver" \
  "$flake_native" "$core" "$repo/native/repo_build_native.bgl"

fixture="$scratch/repo"
fake_beagle="$scratch/beagle"
compiler_log="$scratch/compiler.log"
mkdir -p \
  "$fixture/modules/alpha" \
  "$fixture/scripts" \
  "$fixture/tests" \
  "$fixture/docs/fixtures" \
  "$fixture/hosts/test" \
  "$fake_beagle/bin"

cat >"$fixture/flake.bnix" <<'EOF'
#lang beagle/nix
(ns flake)
{:inputs
  {;; --- GENERATED MODULE INPUTS (do not edit) ---
   ;; --- END GENERATED MODULE INPUTS ---
   }
 :outputs
  (nix/module
    [self
     ;; --- GENERATED MODULE ARGS (do not edit) ---
     ;; --- END GENERATED MODULE ARGS ---
     ...]
    {:linux
      {:inputs
        {;; --- GENERATED MODULE SPECIALARGS (do not edit) ---
         ;; --- END GENERATED MODULE SPECIALARGS ---
         }}
     :home
      {:inputs
        {;; --- GENERATED HM SPECIALARGS (do not edit) ---
         ;; --- END GENERATED HM SPECIALARGS ---
         }}
     :darwin
      {:inputs
        {;; --- GENERATED DARWIN SPECIALARGS (do not edit) ---
         ;; --- END GENERATED DARWIN SPECIALARGS ---
         }}
     :darwin-home
      {:inputs
        {;; --- GENERATED DARWIN HM SPECIALARGS (do not edit) ---
         ;; --- END GENERATED DARWIN HM SPECIALARGS ---
         }}})}
EOF

cat >"$fixture/modules/alpha/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:config {:example true}})
EOF
printf 'excluded\n' >"$fixture/scripts/excluded.bnix"
printf 'excluded\n' >"$fixture/tests/excluded.bnix"
printf 'excluded\n' >"$fixture/docs/fixtures/excluded.bnix"
printf 'obsolete\n' >"$fixture/hosts/test/enabled-tags.nix"
printf 'cached flake output\n' >"$fixture/flake.nix"

cat >"$fake_beagle/bin/beagle-build" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source_path="$1"
output_path="$2"
printf '%s|%s\n' "$source_path" "$output_path" >>"$COMPILER_LOG"
if [[ "${FAKE_COMPILER_FAIL:-0}" == 1 ]]; then
  printf 'partial output\n' >"$output_path"
  printf 'fake compiler failure\n' >&2
  exit 7
fi
cat >"$output_path" <<'NIX'
{
  tags = [ desktop terminal ];
  tags-opt-in = [ optional ];
  tag-overrides = {
    desktop = {
      enable = [ alpha ];
    };
  };
  flake-inputs = { demo = { url = "github:demo/project"; }; };
  tags-extra = [ keep ];
  config = { example = true; };
}
NIX
EOF
chmod +x "$fake_beagle/bin/beagle-build"

touch -d '2026-08-20 00:00:00 UTC' "$fixture/flake.bnix"
touch -d '2026-08-20 00:00:02 UTC' "$fixture/flake.nix"
touch -d '2026-08-20 00:00:02 UTC' \
  "$fixture/modules/alpha/default.bnix"
: >"$compiler_log"

run_native() {
  local name="$1"
  shift
  set +e
  timeout --foreground 30 env \
    FIRN_REPO="$fixture" \
    BEAGLE_PATH="$fake_beagle" \
    COMPILER_LOG="$compiler_log" \
    "$@" "$scratch/repo-build-native" repo build \
    >"$scratch/$name.out" 2>"$scratch/$name.err"
  local status=$?
  set -e
  printf '%s\n' "$status" >"$scratch/$name.status"
}

run_native first env
[[ "$(<"$scratch/first.status")" == 0 ]] \
  || die "first native build returned $(<"$scratch/first.status")"
[[ -f "$fixture/modules/alpha/default.nix" ]] \
  || die "compiled output was not published"
[[ ! -e "$fixture/hosts/test/enabled-tags.nix" ]] \
  || die "obsolete enabled-tags output survived cleanup"
[[ "$(wc -l <"$compiler_log")" == 1 ]] \
  || die "compiler did not run exactly once"

IFS='|' read -r compiled_source compiled_temporary <"$compiler_log"
[[ "$compiled_source" == "$fixture/modules/alpha/default.bnix" ]] \
  || die "compiler source argv changed"
[[ "$(dirname "$compiled_temporary")" == \
    "$fixture/modules/alpha" ]] \
  || die "temporary output was not a destination sibling"
[[ ! -e "$compiled_temporary" ]] \
  || die "temporary output survived publication"
if rg -q '^[[:space:]]*(tags|tags-opt-in|tag-overrides|flake-inputs)[[:space:]]*=' \
    "$fixture/modules/alpha/default.nix"; then
  die "authoring-only attributes survived publication"
fi
rg -Fq 'tags-extra = [ keep ];' "$fixture/modules/alpha/default.nix" \
  || die "cleanup removed a non-authoring attribute"
rg -Fq 'config = { example = true; };' \
  "$fixture/modules/alpha/default.nix" \
  || die "cleanup changed generated configuration"
[[ ! -s "$scratch/first.err" ]] || die "successful build wrote stderr"

: >"$compiler_log"
printf 'obsolete again\n' >"$fixture/hosts/test/enabled-tags.nix"
run_native cached env
[[ "$(<"$scratch/cached.status")" == 0 ]] \
  || die "cached native build returned $(<"$scratch/cached.status")"
[[ ! -s "$compiler_log" ]] || die "valid cache reran the compiler"
[[ ! -e "$fixture/hosts/test/enabled-tags.nix" ]] \
  || die "cached build skipped obsolete-output cleanup"
rg -Fxq 'firn-build: nothing to rebuild.' "$scratch/cached.out" \
  || die "cached diagnostic changed"
[[ ! -s "$scratch/cached.err" ]] || die "cached build wrote stderr"

printf 'previous complete output\n' >"$fixture/modules/alpha/default.nix"
touch -d '2026-08-20 00:00:01 UTC' \
  "$fixture/modules/alpha/default.nix"
touch -d '2026-08-20 00:00:03 UTC' \
  "$fixture/modules/alpha/default.bnix"
: >"$compiler_log"
run_native failed env FAKE_COMPILER_FAIL=1
[[ "$(<"$scratch/failed.status")" == 1 ]] \
  || die "failed compiler did not produce command status 1"
[[ "$(<"$fixture/modules/alpha/default.nix")" == \
    'previous complete output' ]] \
  || die "failed compiler replaced the complete output"
[[ "$(wc -l <"$compiler_log")" == 1 ]] \
  || die "failed compiler did not run exactly once"
IFS='|' read -r failed_source failed_temporary <"$compiler_log"
[[ ! -e "$failed_temporary" ]] \
  || die "failed compiler left a temporary sibling"
cat >"$scratch/failed.expected.err" <<'EOF'
fake compiler failure
firn-build: compiler failed for 'modules/alpha/default.bnix' with status 7
firn repo build: failed.
EOF
cmp -s "$scratch/failed.expected.err" "$scratch/failed.err" \
  || {
    diff -u "$scratch/failed.expected.err" "$scratch/failed.err" >&2 || true
    die "compiler failure diagnostic changed"
  }

if ldd "$scratch/repo-build-native" \
    | rg -qi 'racket|clojure|babashka|java'; then
  die "hosted runtime leaked into native executable"
fi

printf 'ok: native repository build preserves cache and atomic publication contracts\n'
