#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch:?}"' EXIT

beagle="$scratch/beagle"
bin_dir="$scratch/bin"
share_dir="$scratch/share"
mkdir -p "$beagle/bin" "$beagle/beagle-lib" "$bin_dir" "$share_dir"

cat >"$beagle/fake-racket" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = --version ]; then
  printf 'Welcome to Racket v9.1 [test].\n'
  exit 0
fi
source_file="$1"
shift
printf 'source=%s\n' "$(<"$source_file")"
SH
chmod +x "$beagle/fake-racket"

cat >"$beagle/fake-raco" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  'make scripts/firn.rkt')
    compiled_root="${PLTCOMPILEDROOTS%%:*}"
    printf '%s\n' "$compiled_root" >>"$BUILD_LOG"
    printf '%s\n' "${PLTCOMPILEDROOTS:-}" >>"$COMPILED_ROOT_LOG"
    marker="$BUILD_STARTED_DIR/$(basename "$(dirname "$compiled_root")")"
    : >"$marker"
    while [ "$(find "$BUILD_STARTED_DIR" -type f | wc -l)" -lt "$EXPECTED_CONCURRENT_BUILDS" ]; do
      sleep 0.05
    done
    sleep 1
    ;;
  *)
    printf 'unexpected fake raco invocation: %s\n' "$*" >&2
    exit 97
    ;;
esac
SH
chmod +x "$beagle/fake-raco"

cat >"$beagle/bin/_beagle-racket" <<SH
RACKET='$beagle/fake-racket'
RACO='$beagle/fake-raco'
SH
printf '{}\n' >"$beagle/flake.nix"
printf '{}\n' >"$beagle/flake.lock"

make_repo() {
  local repo="$1" identity="$2"
  mkdir -p "$repo/scripts/firn-cmds" "$repo/dotfiles/bin"
  cp "$HERE/firn-build-bin" "$repo/scripts/firn-build-bin"
  cp "$HERE/firn-source-hash" "$repo/scripts/firn-source-hash"
  printf '%s\n' "$identity" >"$repo/scripts/firn.rkt"
  printf '#lang racket/base\n' >"$repo/scripts/firn-cmds/util.rkt"
}

repo_a="$scratch/repo-a"
repo_b="$scratch/repo-b"
make_repo "$repo_a" source-a
make_repo "$repo_b" source-b
build_log="$scratch/build.log"
compiled_root_log="$scratch/compiled-roots.log"
build_started_dir="$scratch/build-started"
trace_log="$scratch/trace.jsonl"
mkdir -p "$build_started_dir"
: >"$build_log"
: >"$compiled_root_log"
: >"$trace_log"

run_build() {
  local repo="$1"
  FIRN_REPO="$repo" BEAGLE_PATH="$beagle" BIN_DIR="$bin_dir" \
    SHARE_DIR="$share_dir" BUILD_LOG="$build_log" \
    COMPILED_ROOT_LOG="$compiled_root_log" \
    BUILD_STARTED_DIR="$build_started_dir" EXPECTED_CONCURRENT_BUILDS=3 \
    FIRN_TRACE_ID=build-bin-test FIRN_TRACE_PATH="$trace_log" \
    "$repo/scripts/firn-build-bin" >/dev/null
}

# An existing valid launcher must remain readable while two worktrees publish.
printf '#!/usr/bin/env bash\nexit 0\n' >"$bin_dir/firn"
chmod +x "$bin_dir/firn"
stop_watch="$scratch/stop-watch"
watch_failed="$scratch/watch-failed"
(
  while [ ! -e "$stop_watch" ]; do
    bash -n "$bin_dir/firn" || {
      : >"$watch_failed"
      exit
    }
  done
) &
watch_pid=$!

run_build "$repo_a" &
pid_a1=$!
run_build "$repo_a" &
pid_a2=$!
run_build "$repo_b" &
pid_b=$!
wait "$pid_a1"
wait "$pid_a2"
wait "$pid_b"
: >"$stop_watch"
wait "$watch_pid"
[ ! -e "$watch_failed" ]

racket_bin="$(readlink -f "$beagle/fake-racket")"
racket_hash="$(printf '%s' "$racket_bin" | sha1sum | cut -c1-12)"
hash_a="$(FIRN_REPO="$repo_a" BEAGLE_PATH="$beagle" "$repo_a/scripts/firn-source-hash")"
hash_b="$(FIRN_REPO="$repo_b" BEAGLE_PATH="$beagle" "$repo_b/scripts/firn-source-hash")"
[ "$hash_a" != "$hash_b" ]
runtime_a="$share_dir/$racket_hash/$hash_a/runtime"
runtime_b="$share_dir/$racket_hash/$hash_b/runtime"
[ -L "$runtime_a" ]
[ -L "$runtime_b" ]
[ -f "$runtime_a/.complete" ]
[ -f "$runtime_b/.complete" ]
[ "$(wc -l <"$build_log")" -eq 3 ]
[ "$(wc -l <"$compiled_root_log")" -eq 3 ]
[ "$(jq -s '[.[] | select(.event == "span_start" and .name == "firn revision cache build")] | length' "$trace_log")" -eq 3 ]
[ "$(jq -s '[.[] | select(.event == "span_end" and .name == "firn revision cache build" and .status == "ok" and .cache == "miss" and .duration_ms >= 0)] | length' "$trace_log")" -eq 3 ]
[ "$(sort -u "$compiled_root_log" | wc -l)" -eq 3 ]
while IFS= read -r roots; do
  grep -Fq '/generation.' <<<"$roots"
  ! grep -Eq '(^|:)same(:|$)' <<<"$roots"
done <"$compiled_root_log"
bash -n "$bin_dir/firn"

# Switching worktree identity selects the matching immutable image without a
# rebuild or mutation of the other worktree's cache entry.
output_a="$(FIRN_RUNTIME_SHARE_DIR="$share_dir" FIRN_REPO="$repo_a" \
  BEAGLE_PATH="$beagle" BUILD_LOG="$build_log" "$bin_dir/firn")"
output_b="$(FIRN_RUNTIME_SHARE_DIR="$share_dir" FIRN_REPO="$repo_b" \
  BEAGLE_PATH="$beagle" BUILD_LOG="$build_log" "$bin_dir/firn")"
grep -Fxq 'source=source-a' <<<"$output_a"
grep -Fxq 'source=source-b' <<<"$output_b"
[ "$(wc -l <"$build_log")" -eq 3 ]

# The default wrapper target is the source tree, never the live Nix-managed
# ~/.local/bin projection.
FIRN_REPO="$repo_a" BEAGLE_PATH="$beagle" SHARE_DIR="$share_dir" \
  BUILD_LOG="$build_log" "$repo_a/scripts/firn-build-bin" >/dev/null
[ -x "$repo_a/dotfiles/bin/firn" ]
bash -n "$repo_a/dotfiles/bin/firn"
[ "$(wc -l <"$build_log")" -eq 3 ]

if find "$share_dir" "$bin_dir" \( -name '*.tmp' -o -name '.firn.*' \) | grep -q .; then
  printf 'transactional Firn publication left a temporary file behind\n' >&2
  exit 1
fi

# Reproduce the production failure with the real pinned Racket: list.rkt's
# bytecode imports `resolve`, while a newer adjacent tag-resolve bytecode omits
# it even though the restored source exports it. Ordinary loading trusts the
# ignored adjacent bytecode and dies with instantiate-linklet. Both Firn build
# surfaces must ignore that poisoned sidecar tree and compile current sources.
if [ -z "${BEAGLE_PATH:-}" ]; then
  for _bp in "$HOME/code/beagle/main" "$HOME/code/beagle" "$(cd "$HERE/../.." && pwd)/beagle"; do
    if [ -f "$_bp/bin/_beagle-racket" ]; then real_beagle="$_bp"; break; fi
  done
  unset _bp
fi
real_beagle="${BEAGLE_PATH:-${real_beagle:-$(cd "$HERE/../.." && pwd)/beagle}}"
# shellcheck disable=SC1091
source "$real_beagle/bin/_beagle-racket"
real_repo="$scratch/real-repro"
real_bin="$scratch/real-bin"
real_share="$scratch/real-share"
mkdir -p "$real_repo/scripts/firn-cmds" "$real_repo/dotfiles/bin" \
  "$real_repo/hosts/test" "$real_bin" "$real_share"
cp "$HERE/firn-build-bin" "$real_repo/scripts/firn-build-bin"
cp "$HERE/firn-source-hash" "$real_repo/scripts/firn-source-hash"
cp "$HERE/firn-build" "$real_repo/scripts/firn-build"
cat >"$real_repo/scripts/firn.rkt" <<'RKT'
#lang racket/base
(require "firn-cmds/list.rkt")
(displayln (run))
RKT
cat >"$real_repo/scripts/firn-cmds/tag-resolve.rkt" <<'RKT'
#lang racket/base
(provide resolve)
(define (resolve) 'fresh-source)
RKT
cat >"$real_repo/scripts/firn-cmds/list.rkt" <<'RKT'
#lang racket/base
(require "tag-resolve.rkt")
(provide run)
(define (run) (resolve))
RKT
(
  cd "$real_repo"
  "$RACO" make scripts/firn.rkt
  cat >scripts/firn-cmds/tag-resolve.rkt <<'RKT'
#lang racket/base
(provide obsolete)
(define (obsolete) 'poisoned-bytecode)
RKT
  "$RACO" make scripts/firn-cmds/tag-resolve.rkt
  cat >scripts/firn-cmds/tag-resolve.rkt <<'RKT'
#lang racket/base
(provide resolve)
(define (resolve) 'fresh-source)
RKT
  touch -d '2000-01-01 00:00:00 UTC' scripts/firn-cmds/tag-resolve.rkt
)
set +e
poisoned_output="$(cd "$real_repo" && "$RACKET" scripts/firn.rkt 2>&1)"
poisoned_rc=$?
set -e
[ "$poisoned_rc" -ne 0 ]
grep -Fq 'not exported' <<<"$poisoned_output"

FIRN_REPO="$real_repo" BEAGLE_PATH="$real_beagle" BIN_DIR="$real_bin" \
  SHARE_DIR="$real_share" "$real_repo/scripts/firn-build-bin" >/dev/null
fresh_output="$(FIRN_RUNTIME_SHARE_DIR="$real_share" \
  FIRN_REPO="$real_repo" BEAGLE_PATH="$real_beagle" \
  "$real_bin/firn")"
grep -Fxq 'fresh-source' <<<"$fresh_output"

# The installed pre-change wrapper resumes at firn.zo after invoking the new
# recipe. The compatibility shim must hand that invocation to the new wrapper.
FIRN_REPO="$real_repo" BEAGLE_PATH="$real_beagle" \
  SHARE_DIR="$real_share" "$real_repo/scripts/firn-build-bin" >/dev/null
real_hash="$(
  FIRN_REPO="$real_repo" BEAGLE_PATH="$real_beagle" \
    "$real_repo/scripts/firn-source-hash"
)"
real_racket_bin="$(readlink -f "$(command -v "$RACKET")")"
real_racket_hash="$(printf '%s' "$real_racket_bin" | sha1sum | cut -c1-12)"
compat_zo="$real_share/$real_racket_hash/$real_hash/firn.zo"
[ -s "$compat_zo" ]
adoption_output="$(
  FIRN_RUNTIME_SHARE_DIR="$real_share" \
    FIRN_REPO="$real_repo" BEAGLE_PATH="$real_beagle" \
    "$RACKET" "$compat_zo"
)"
grep -Fxq 'fresh-source' <<<"$adoption_output"

printf ':enabled [test]\n' >"$real_repo/hosts/test/enabled-tags.bnix"
FIRN_RUNTIME_SHARE_DIR="$real_share" \
  FIRN_REPO="$real_repo" BEAGLE_PATH="$real_beagle" \
  FIRN_CLI="$real_bin/firn" FIRN_SKIP_FLAKE_INPUTS=1 \
  "$real_repo/scripts/firn-build" >/dev/null

printf 'ok: Firn bytecode cache isolates transitive dependencies and publishes atomically\n'
