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
cat "$1"
SH
chmod +x "$beagle/fake-racket"

cat >"$beagle/fake-raco" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  'pkg show')
    printf ' beagle test-link\n'
    ;;
  'help demod')
    ;;
  'demod -o')
    out="$3"
    printf '%s\n' "$out" >>"$BUILD_LOG"
    printf 'source=%s\n' "$(<scripts/firn.rkt)" >"$out"
    sleep 1
    printf 'complete=yes\n' >>"$out"
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
: >"$build_log"

run_build() {
  local repo="$1"
  FIRN_REPO="$repo" BEAGLE_PATH="$beagle" BIN_DIR="$bin_dir" \
    SHARE_DIR="$share_dir" BUILD_LOG="$build_log" \
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
pid_a=$!
run_build "$repo_b" &
pid_b=$!
wait "$pid_a"
wait "$pid_b"
: >"$stop_watch"
wait "$watch_pid"
[ ! -e "$watch_failed" ]

racket_bin="$(readlink -f "$beagle/fake-racket")"
racket_hash="$(printf '%s' "$racket_bin" | sha1sum | cut -c1-12)"
hash_a="$(FIRN_REPO="$repo_a" BEAGLE_PATH="$beagle" "$repo_a/scripts/firn-source-hash")"
hash_b="$(FIRN_REPO="$repo_b" BEAGLE_PATH="$beagle" "$repo_b/scripts/firn-source-hash")"
[ "$hash_a" != "$hash_b" ]
zo_a="$share_dir/$racket_hash/$hash_a/firn.zo"
zo_b="$share_dir/$racket_hash/$hash_b/firn.zo"
grep -Fxq 'source=source-a' "$zo_a"
grep -Fxq 'source=source-b' "$zo_b"
grep -Fxq 'complete=yes' "$zo_a"
grep -Fxq 'complete=yes' "$zo_b"
[ "$(wc -l <"$build_log")" -eq 2 ]
bash -n "$bin_dir/firn"

# Switching worktree identity selects the matching immutable image without a
# rebuild or mutation of the other worktree's cache entry.
output_a="$(FIRN_REPO="$repo_a" BEAGLE_PATH="$beagle" BUILD_LOG="$build_log" "$bin_dir/firn")"
output_b="$(FIRN_REPO="$repo_b" BEAGLE_PATH="$beagle" BUILD_LOG="$build_log" "$bin_dir/firn")"
grep -Fxq 'source=source-a' <<<"$output_a"
grep -Fxq 'source=source-b' <<<"$output_b"
[ "$(wc -l <"$build_log")" -eq 2 ]

# The default wrapper target is the source tree, never the live Nix-managed
# ~/.local/bin projection.
FIRN_REPO="$repo_a" BEAGLE_PATH="$beagle" SHARE_DIR="$share_dir" \
  BUILD_LOG="$build_log" "$repo_a/scripts/firn-build-bin" >/dev/null
[ -x "$repo_a/dotfiles/bin/firn" ]
bash -n "$repo_a/dotfiles/bin/firn"
[ "$(wc -l <"$build_log")" -eq 2 ]

if find "$share_dir" "$bin_dir" -type f -name '*.tmp' -o -name '.firn.*' | grep -q .; then
  printf 'transactional Firn publication left a temporary file behind\n' >&2
  exit 1
fi

printf 'ok: Firn bytecode cache is source-isolated and atomically published\n'
