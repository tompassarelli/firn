#!/usr/bin/env bash
set -euo pipefail
mode=${1:?native|dotfiles|drift}
if [ "$mode" = drift ]; then
  FIRN_REPO="$PWD" dotfiles/bin/firn-check
  bash .github/scripts/host-diff.sh build
  exit
fi
if [ "$mode" = native ]; then
  export FIRN_RUNTIME_BIN="${FIRN_RUNTIME_ROOT:-$HOME/.local/lib/firn/cli}/current/bin"
fi
base=${SAFE_PUSH_LAND_BASE:?}
head=${SAFE_PUSH_LAND_HEAD:?}
declare -A seen=() mentions=()
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
      mentions=()
      while IFS= read -r test; do mentions[$test]=1; done < <(rg -lF -- "$name" "${native_tests[@]}")
      for test in "${native_tests[@]}"; do
        if [[ "${test##*/}" == "$stem"*.test.sh ]] || [ -n "${mentions[$test]:-}" ]; then tests+=("$test"); fi
      done
      ;;
    *) continue ;;
  esac
  for test in "${tests[@]}"; do
    [ -f "$test" ] || continue
    [ -z "${seen[$test]:-}" ] || continue
    seen[$test]=1
    printf 'land check: %s\n' "$test"
    bash "$test"
  done
done < <(git diff --name-only --no-renames -z "$base" "$head")
