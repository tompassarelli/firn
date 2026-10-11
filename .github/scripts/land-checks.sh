#!/usr/bin/env bash
set -euo pipefail
mode=${1:?native|dotfiles|drift}
if [ "$mode" = drift ]; then
  compiler_inputs() {
    {
      git ls-tree -r "$1" | awk -F '\t' '$2 ~ /\.(bnix|clause|nix)$/ || $2 ~ /^native\// ||
        $2 == "dotfiles/bin/firn" || $2 == "config/clause-revision"'
      readlink -f "${FIRN_RUNTIME_ROOT:-$HOME/.local/lib/firn/cli}/current"
      git -C "${BEAGLE_PATH:-$HOME/code/beagle/main}" rev-parse HEAD
    } | sha256sum | cut -d' ' -f1
  }
  drift_cache=${XDG_CACHE_HOME:-$HOME/.cache}/firn/compiler-drift
  drift_key=$(compiler_inputs HEAD)
  if [ -n "$(git status --porcelain --untracked-files=no)" ] || [ ! -e "$drift_cache/$drift_key" ]; then
    FIRN_REPO="$PWD" dotfiles/bin/firn repo build
    git diff --exit-code
    mkdir -p "$drift_cache"
    touch "$drift_cache/$drift_key"
  else
    printf 'land check: compiler drift reused for input hash %s\n' "$drift_key"
  fi
  nix build --no-link .#checks.x86_64-linux.nix-syntax
  bash .github/scripts/host-diff.sh build
  exit
fi
base=${SAFE_PUSH_LAND_BASE:?}
head=${SAFE_PUSH_LAND_HEAD:?}
declare -A seen=()
mapfile -t native_tests < <(git ls-files -- 'native/*.test.sh')
while IFS= read -r -d '' path; do
  tests=()
  case "$mode:$path" in
    native:.github/scripts/host-diff.sh)
      tests+=(native/host_diff.test.sh)
      ;;
    dotfiles:dotfiles/bin/*)
      stem=${path%.test.sh}
      tests+=("$stem.test.sh")
      case "$stem" in dotfiles/bin/firn) tests+=(dotfiles/bin/firn-launcher.test.sh) ;; esac
      ;;
    native:native/*)
      name=${path##*/}
      stem=${name%%.*}
      stem=${stem%_host}; stem=${stem%_test}; stem=${stem%_driver}; stem=${stem%_family}; stem=${stem%_native}
      for test in "${native_tests[@]}"; do
        if [[ "${test##*/}" == "$stem"*.test.sh ]] || rg -Fq -- "$name" "$test"; then tests+=("$test"); fi
      done
      ;;
    *) continue ;;
  esac
  for test in "${tests[@]}"; do
    [ -f "$test" ] || continue
    [ -z "${seen[$test]:-}" ] || continue
    seen[$test]=1
    printf 'land check: %s\n' "$test"
    BEAGLE_PATH="${BEAGLE_PATH:-$HOME/code/beagle/main}" bash "$test"
  done
done < <(git diff --name-only --no-renames -z "$base" "$head")
