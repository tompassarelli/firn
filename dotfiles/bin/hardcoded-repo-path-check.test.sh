#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO/dotfiles/bin/hardcoded-repo-path-check"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/hrpc-test.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT

export GIT_AUTHOR_NAME=hrpc-test
export GIT_AUTHOR_EMAIL=hrpc-test@example.invalid
export GIT_COMMITTER_NAME=hrpc-test
export GIT_COMMITTER_EMAIL=hrpc-test@example.invalid

pass=0
fail_count=0

check() { # check <description> <0|1 truth>
  if [ "$2" -eq 0 ]; then
    printf 'PASS: %s\n' "$1"
    pass=$((pass + 1))
  else
    printf 'FAIL: %s\n' "$1" >&2
    fail_count=$((fail_count + 1))
  fi
}

# --- fixture ---------------------------------------------------------------
# Two containers, each holding a checkout that owns its own allowlist. The
# allowlist key is <container>/<path>, so separate containers keep the two
# fixtures distinguishable.
#
# The installed entry point symlinks into the FIRST checkout, mirroring
# the installed entry point under ~/.local/bin, which links into the
# repository's own checkout.
#
# The regression: the tool resolved its root from the script's own location,
# so invoking that symlink from the second checkout scanned and rewrote the
# FIRST checkout's allowlist while reporting success for the caller.

make_checkout() { # make_checkout <container-name> -> echoes the checkout path
  local name="$1" root="$scratch/$1/main" i
  mkdir -p "$root/config" "$root/dotfiles/bin" "$root/filler"
  cp "$TARGET" "$root/dotfiles/bin/hardcoded-repo-path-check"
  printf '%s\n' 'ref="$HOME/code/north-v2/main"' >"$root/dotfiles/bin/sample" # hardcoded-repo-path:allow
  # The scan refuses to run on fewer than 100 files, so it cannot silently
  # match nothing. Pad past that floor.
  for i in $(seq 1 120); do printf 'x\n' >"$root/filler/f$i.txt"; done
  {
    printf '# fixture allowlist\n'
    printf '%s/dotfiles/bin/sample\t1\n' "$name"
  } >"$root/config/hardcoded-repo-paths.tsv"
  git -C "$root" init -q .
  git -C "$root" add config dotfiles filler
  git -C "$root" commit -qm fixture
  printf '%s\n' "$root"
}

alpha="$(make_checkout alpha)"
beta="$(make_checkout beta)"

mkdir -p "$scratch/bin"
ln -s "$alpha/dotfiles/bin/hardcoded-repo-path-check" "$scratch/bin/hardcoded-repo-path-check"
installed="$scratch/bin/hardcoded-repo-path-check"

run_from() { # run_from <cwd> <scan-root> [args...]
  local cwd="$1" scan="$2"; shift 2
  ( cd "$cwd" && HARDCODED_REPO_PATH_CHECK_ROOTS="$scan" "$installed" "$@" )
}

# --- the regression --------------------------------------------------------
# Corrupt ONLY beta's declared count. A tool that reads the caller's checkout
# must fail; one that reads the script's own checkout passes blind.

sed -i 's/\t1$/\t999/' "$beta/config/hardcoded-repo-paths.tsv"

if run_from "$beta" "$beta" >/dev/null 2>&1; then
  check "installed entry point catches the caller checkout's bad count" 1
else
  check "installed entry point catches the caller checkout's bad count" 0
fi

if run_from "$alpha" "$alpha" >/dev/null 2>&1; then
  check "the untouched checkout still passes" 0
else
  check "the untouched checkout still passes" 1
fi

sed -i 's/\t999$/\t1/' "$beta/config/hardcoded-repo-paths.tsv"

# --- --write-allow targets the caller's checkout ---------------------------

printf '%s\n' 'other="$HOME/code/beagle/main"' >>"$beta/dotfiles/bin/sample" # hardcoded-repo-path:allow
git -C "$beta" commit -qm drift dotfiles/bin/sample
alpha_before="$(cat "$alpha/config/hardcoded-repo-paths.tsv")"

run_from "$beta" "$beta" --write-allow >/dev/null 2>&1 || true

if grep -qP 'beta/dotfiles/bin/sample\t2' "$beta/config/hardcoded-repo-paths.tsv"; then
  check "--write-allow refreshed the caller's allowlist" 0
else
  check "--write-allow refreshed the caller's allowlist" 1
fi

if [ "$alpha_before" = "$(cat "$alpha/config/hardcoded-repo-paths.tsv")" ]; then
  check "--write-allow left the script's own checkout untouched" 0
else
  check "--write-allow left the script's own checkout untouched" 1
fi

if run_from "$beta" "$beta" >/dev/null 2>&1; then
  check "the refreshed checkout passes its own check" 0
else
  check "the refreshed checkout passes its own check" 1
fi

# --- fallback: caller owns no allowlist ------------------------------------
# Outside any checkout the tool must still resolve, via the script location.

outside="$scratch/outside"
mkdir -p "$outside"
if run_from "$outside" "$alpha" >/dev/null 2>&1; then
  check "falls back to the script's checkout when the caller owns none" 0
else
  check "falls back to the script's checkout when the caller owns none" 1
fi

# --- explicit override -----------------------------------------------------

sed -i 's/\t1$/\t999/' "$alpha/config/hardcoded-repo-paths.tsv"
if ( cd "$beta" && HARDCODED_REPO_PATH_CHECK_ROOT="$alpha" \
     HARDCODED_REPO_PATH_CHECK_ROOTS="$alpha" "$installed" >/dev/null 2>&1 ); then
  check "HARDCODED_REPO_PATH_CHECK_ROOT overrides the caller's checkout" 1
else
  check "HARDCODED_REPO_PATH_CHECK_ROOT overrides the caller's checkout" 0
fi

if [ "$fail_count" -eq 0 ]; then
  printf 'hardcoded-repo-path-check tests: PASS (%d checks)\n' "$pass"
else
  printf 'hardcoded-repo-path-check tests: FAIL (%d passed, %d failed)\n' "$pass" "$fail_count" >&2
  exit 1
fi
