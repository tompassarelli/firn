#!/usr/bin/env bash
set -euo pipefail
mode=${1:?native|dotfiles|drift}
if [ "$mode" = drift ]; then
  FIRN_REPO="$PWD" dotfiles/bin/firn repo build
  git diff --exit-code
  exit
fi
base=${SAFE_PUSH_LAND_BASE:?}
head=${SAFE_PUSH_LAND_HEAD:?}
declare -A seen=()
mapfile -t native_tests < <(git ls-files -- 'native/*.test.sh')
while IFS= read -r -d '' path; do
  tests=()
  case "$mode:$path" in
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
