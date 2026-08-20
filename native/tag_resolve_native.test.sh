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
    printf 'tag-resolve-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-tag-resolve-native.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT

die() {
  printf 'tag-resolve-native: %s\n' "$*" >&2
  exit 1
}

[[ -x "$beagle/bin/beagle" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

native="${FIRN_TAG_RESOLVE_BIN:-}"
if [[ -z "$native" ]]; then
  native="$scratch/firn-tag-resolve"
  mkdir -p "$scratch/native-artifacts"
  timeout --foreground 620 "$beagle/bin/beagle" native-exe \
    --out "$native" \
    --entry firn.tag-resolve-native/-main \
    --artifacts "$scratch/native-artifacts" \
    "$beagle/native-core/src/beagle/datum_reader.bgl" \
    "$beagle/native-core/src/native/json.bgl" \
    "$repo/native/tag_resolve.bgl" \
    "$repo/native/tag_inputs.bgl" \
    "$repo/native/tag_resolve_driver.bgl" \
    "$repo/native/tag_resolve_native.bgl" \
    >"$scratch/native-build.out" 2>"$scratch/native-build.err" \
    || die "native executable compilation failed"
fi
[[ -x "$native" ]] || die "native executable is not executable: $native"

run_native() {
  local root="$1" emit_mode="$2" result="$3"
  shift 3
  set +e
  case "$emit_mode" in
    absent)
      timeout --foreground 30 env \
        -u FIRN_TAG_EMIT -u FIRN_TRACE_ID -u FIRN_TRACE_PATH \
        FIRN_REPO="$root" \
        "$native" "$@" >"$result.out" 2>"$result.err"
      ;;
    empty)
      timeout --foreground 30 env \
        -u FIRN_TRACE_ID -u FIRN_TRACE_PATH \
        FIRN_REPO="$root" FIRN_TAG_EMIT= \
        "$native" "$@" >"$result.out" 2>"$result.err"
      ;;
    *) die "unknown emit mode: $emit_mode" ;;
  esac
  local status=$?
  set -e
  printf '%s\n' "$status" >"$result.status"
}

assert_file_equal() {
  local label="$1" expected="$2" actual="$3"
  if ! cmp -s "$expected" "$actual"; then
    diff -u "$expected" "$actual" >&2 || true
    die "$label bytes differ"
  fi
}

assert_status() {
  local label="$1" result="$2" expected_status="$3"
  local actual_status
  actual_status="$(<"$result.status")"
  [[ "$actual_status" == "$expected_status" ]] \
    || die "$label returned $actual_status, expected $expected_status"
}

make_emit_repo() {
  local root="$1"
  mkdir -p \
    "$root/scripts" \
    "$root/config" \
    "$root/modules/alpha" \
    "$root/modules/beta" \
    "$root/hosts/fixture"
  : >"$root/scripts/firn-build"
  printf '{}\n' >"$root/flake.bnix"
  printf '[]\n' >"$root/config/darwin-modules.json"
  cat >"$root/modules/alpha/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags [terminal]})
EOF
  cat >"$root/modules/beta/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags [terminal]})
EOF
  cat >"$root/hosts/fixture/enabled-tags.bnix" <<'EOF'
#lang beagle/nix
(ns enabled-tags)
{:platform linux
 :enabled [terminal]
 :disabled []}
EOF
}

make_no_tag_repo() {
  local root="$1"
  mkdir -p "$root/scripts" "$root/hosts/plain"
  : >"$root/scripts/firn-build"
  printf '{}\n' >"$root/flake.bnix"
}

make_metadata_free_repo() {
  local root="$1"
  mkdir -p \
    "$root/scripts" \
    "$root/modules/odd" \
    "$root/hosts/odd" \
    "$root/hosts/plain"
  : >"$root/scripts/firn-build"
  printf '{}\n' >"$root/flake.bnix"
  cat >"$root/modules/odd/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(def nested {:tags [incidental]})
EOF
  cat >"$root/hosts/odd/enabled-tags.bnix" <<'EOF'
#lang beagle/nix
(ns enabled-tags)
{:platform linux
 :enabled []
 :disabled []}
EOF
  cat >"$root/hosts/plain/enabled-tags.bnix" <<'EOF'
#lang beagle/nix
(ns enabled-tags)
EOF
}

native_live="$scratch/native-live"
run_native "$repo" absent "$native_live" tag resolve all
assert_status "live all" "$native_live" 0

missing_host="__firn_native_missing_host__"
native_missing="$scratch/native-missing"
run_native "$repo" absent "$native_missing" tag resolve "$missing_host"
assert_status "unknown host" "$native_missing" 1
[[ ! -s "$native_missing.out" ]] || die "unknown host wrote stdout"

native_emit_root="$scratch/native-emit-repo"
make_emit_repo "$native_emit_root"

native_first="$scratch/native-first-emit"
run_native "$native_emit_root" absent "$native_first" tag resolve fixture+emit
assert_status "first emit" "$native_first" 0

expected_first="$scratch/expected-first.out"
printf '%s\n' \
  'tag-resolve: wrote hosts/fixture/_generated-enables.bnix (2 modules)' \
  >"$expected_first"
assert_file_equal "first emit message" "$expected_first" "$native_first.out"
[[ ! -s "$native_first.err" ]] || die "first emit wrote stderr"

expected_generated="$scratch/expected-generated.bnix"
cat >"$expected_generated" <<'EOF'
#lang beagle/nix

;; Auto-generated by `firn tag resolve fixture --emit`.
;; Do not edit by hand. Source of truth:
;;   modules/*/default.bnix  (:tags, :tags-opt-in, :tag-overrides)
;;   hosts/fixture/enabled-tags.bnix

(ns _generated-enables)

(nix/module [config lib pkgs ...]
  {:myConfig.modules.alpha.enable (lib.mkDefault true)
   :myConfig.modules.beta.enable (lib.mkDefault true)})
EOF
native_generated="$native_emit_root/hosts/fixture/_generated-enables.bnix"
[[ -f "$native_generated" ]] || die "native command did not write generated source"
assert_file_equal "native generated source" "$expected_generated" "$native_generated"

native_second="$scratch/native-second-emit"
run_native "$native_emit_root" absent "$native_second" tag resolve fixture+emit
assert_status "up-to-date emit" "$native_second" 0
expected_second="$scratch/expected-second.out"
printf '%s\n' \
  'tag-resolve: hosts/fixture/_generated-enables.bnix is up to date (2 modules)' \
  >"$expected_second"
assert_file_equal "up-to-date message" "$expected_second" "$native_second.out"
assert_file_equal "stable generated source" "$expected_generated" "$native_generated"

native_empty_env="$scratch/native-empty-env"
run_native "$native_emit_root" empty "$native_empty_env" tag resolve fixture
assert_status "empty-present FIRN_TAG_EMIT" "$native_empty_env" 0
assert_file_equal "empty-present emit message" "$expected_second" "$native_empty_env.out"

native_invalid="$scratch/native-invalid"
run_native "$repo" absent "$native_invalid" tag resolve all extra
[[ "$(<"$native_invalid.status")" == 64 ]] \
  || die "invalid grammar returned $(<"$native_invalid.status"), expected 64"
[[ ! -s "$native_invalid.out" ]] || die "invalid grammar wrote stdout"
expected_usage="$scratch/expected-usage.err"
printf '%s\n' 'Usage: firn tag resolve [<host>|all][+emit]' >"$expected_usage"
assert_file_equal "invalid grammar usage" "$expected_usage" "$native_invalid.err"

native_no_tag_root="$scratch/native-no-tag-repo"
make_no_tag_repo "$native_no_tag_root"
native_no_tag="$scratch/native-no-tag"
run_native "$native_no_tag_root" absent "$native_no_tag" tag resolve all+emit
assert_status "all+emit without tag sources" "$native_no_tag" 0
[[ ! -s "$native_no_tag.out" ]] || die "tagless all+emit wrote stdout"
[[ ! -s "$native_no_tag.err" ]] || die "tagless all+emit wrote stderr"
[[ ! -e "$native_no_tag_root/hosts/plain/_generated-enables.bnix" ]] \
  || die "tagless all+emit wrote generated source"

native_metadata_root="$scratch/native-metadata-free"
make_metadata_free_repo "$native_metadata_root"
for metadata_host in odd plain; do
  native_metadata="$scratch/native-metadata-$metadata_host"
  run_native "$native_metadata_root" absent "$native_metadata" \
    tag resolve "$metadata_host"
  assert_status "metadata-free $metadata_host" "$native_metadata" 0
done

printf 'ok: native tag resolution passes native filesystem and CLI contracts\n'
