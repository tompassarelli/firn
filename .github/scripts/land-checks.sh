#!/usr/bin/env bash
set -euo pipefail
mode=${1:?native|dotfiles|drift|scripts|flake|host}
gated() { [ "$(north land host-gate --switch 2>/dev/null)" = on ]; }
if [ "$mode" = drift ]; then
  FIRN_REPO="$PWD" dotfiles/bin/firn-check
  if gated; then bash .github/scripts/host-diff.sh offload; else bash .github/scripts/host-diff.sh build; fi
  exit
fi
if [ "$mode" = host ]; then
  if gated; then
    printf 'host check: this host builds its own toplevel in its delivery-liveness floor once the landing queues are empty; a changed toplevel is built by the drift line on a build host\n'
    exit 0
  fi
  exec nix flake check --no-update-lock-file
fi
if [ "$mode" = flake ]; then
  json=$(nix eval --no-update-lock-file --json "path:$PWD#checks.x86_64-linux" --apply builtins.attrNames)
  mapfile -t names < <(jq -r '.[] | select(startswith("host-") | not)' <<<"$json")
  printf 'flake check: building checks %s\n' "${names[*]}"
  exec nix build --no-update-lock-file --no-link "${names[@]/#/path:$PWD#checks.x86_64-linux.}"
fi
if [ "$mode" = scripts ]; then
  git diff --name-only --no-renames -z "${SAFE_PUSH_LAND_BASE:?}" "${SAFE_PUSH_LAND_HEAD:?}" -- modules/ |
    while IFS= read -r -d "" path; do module=${path#modules/}; printf "modules/%s/default.nix\n" "${module%%/*}"; done |
    sort -u | while IFS= read -r module; do
      [ -f "$module" ] && rg -q writeShellApplication "${module%/default.nix}" || continue
      printf "land check: building the shell applications of %s\n" "$module"
      json=$(nix eval --json --impure --expr "import ./.github/scripts/shell-apps.nix { root = \"$PWD\"; module = \"$module\"; }")
      mapfile -t drvs < <(jq -r ".[]" <<<"$json")
      [ "${#drvs[@]}" = 0 ] || nix build --no-link "${drvs[@]/%/^*}"
    done
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
