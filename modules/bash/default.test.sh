#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
source_file="$repo/modules/bash/default.bnix"
generated_file="$repo/modules/bash/default.nix"
myfunctions_file="$repo/dotfiles/bin/myfunctions"

grep -Fq '{:source (s flakeRoot "/dotfiles/bin")}' "$source_file"
# These assertions intentionally match literal interpolation syntax.
# shellcheck disable=SC2016
grep -Fq 'home.file.".local/bin".source = "${flakeRoot}/dotfiles/bin";' "$generated_file"
# shellcheck disable=SC2016
grep -Fq 'bindir="$HOME/.local/bin"' "$myfunctions_file"
if rg -n 'mkOutOfStoreSymlink.*dotfiles/bin|code/nixos-config/dotfiles/bin' \
  "$source_file" "$generated_file" "$myfunctions_file"; then
  printf 'launcher directory still uses a mutable checkout source\n' >&2
  exit 1
fi

if [ -n "${LOCAL_BIN_SOURCE:-}" ]; then
  local_bin_source="$LOCAL_BIN_SOURCE"
else
  local_bin_source="$(
    nix eval --raw \
      "$repo#nixosConfigurations.whiterabbit.config.home-manager.users.tom.home.file.\".local/bin\".source"
  )"
fi
local_bin_source="$(readlink -f "$local_bin_source")"
case "$local_bin_source" in
  /nix/store/*) ;;
  *)
    printf 'launcher directory is not store-backed: %s\n' "$local_bin_source" >&2
    exit 1
    ;;
esac
source_launcher_count="$(find "$repo/dotfiles/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | wc -l)"
active_launcher_count="$(find "$local_bin_source" -mindepth 1 -maxdepth 1 -printf '%f\n' | wc -l)"
if [ "$source_launcher_count" -ne 37 ] || [ "$active_launcher_count" -ne 37 ]; then
  printf 'launcher count mismatch: source=%s active=%s expected=37\n' \
    "$source_launcher_count" "$active_launcher_count" >&2
  exit 1
fi
cmp -s \
  <(find "$repo/dotfiles/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort) \
  <(find "$local_bin_source" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)
while IFS= read -r name; do
  if [ -x "$repo/dotfiles/bin/$name" ]; then
    test -x "$local_bin_source/$name"
  else
    test ! -x "$local_bin_source/$name"
  fi
done < <(find "$repo/dotfiles/bin" -mindepth 1 -maxdepth 1 -printf '%f\n')
"$local_bin_source/safe-push" --help | grep -Fq -- '--to BRANCH'

test_home="$(mktemp -d)"
trap 'rm -rf -- "${test_home:?}"' EXIT
mkdir -p "$test_home/.local"
ln -s "$local_bin_source" "$test_home/.local/bin"
myfunctions_output="$(HOME="$test_home" "$local_bin_source/myfunctions")"
grep -Fxq "Commands ($test_home/.local/bin):" <<<"$myfunctions_output"
expected_commands="$(
  while IFS= read -r name; do
    candidate="$local_bin_source/$name"
    [ -f "$candidate" ] && [ -x "$candidate" ] || continue
    case "$name" in __*|myfunctions) continue ;; esac
    printf '%s\n' "$name"
  done < <(find "$local_bin_source" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)
)"
actual_commands="$(
  awk '
    /^Commands \(/ { in_commands = 1; next }
    in_commands && /^$/ { exit }
    in_commands { print $1 }
  ' <<<"$myfunctions_output" | sort
)"
if [ "$actual_commands" != "$expected_commands" ]; then
  printf 'myfunctions did not enumerate the active launcher surface\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_commands" "$actual_commands" >&2
  exit 1
fi

if [ -n "${BASH_LOGOUT_SOURCE:-}" ]; then
  logout_source=$BASH_LOGOUT_SOURCE
else
  etc_output=$(
    nix build \
      "$repo#nixosConfigurations.whiterabbit.config.system.build.etc" \
      --no-link \
      --print-out-paths
  )
  logout_source=$(readlink -f "$etc_output/etc/bash_logout")
fi

if [ ! -f "$logout_source" ]; then
  printf 'generated bash_logout is missing: %s\n' "$logout_source" >&2
  exit 1
fi

live_logout=$(readlink -f /etc/bash_logout)
login_bash=/run/current-system/sw/bin/bash
bwrap_bin=$(command -v bwrap)

run_login_exit() {
  local expected=$1
  local output
  local observed

  set +e
  output=$(
    "$bwrap_bin" \
      --ro-bind / / \
      --dev-bind /dev /dev \
      --proc /proc \
      --ro-bind "$logout_source" "$live_logout" \
      "$login_bash" -lc "set -u; unset __ETC_BASHLOGOUT_SOURCED NOSYSBASHLOGOUT; exit $expected" \
      2>&1
  )
  observed=$?
  set -e

  if [ "$observed" -ne "$expected" ]; then
    printf 'login shell exit mismatch: expected %s, observed %s\n%s\n' \
      "$expected" "$observed" "$output" >&2
    exit 1
  fi
  if grep -Fq 'unbound variable' <<<"$output"; then
    printf 'login shell emitted a nounset failure:\n%s\n' "$output" >&2
    exit 1
  fi
}

run_login_exit 0
run_login_exit 37

marker=$(printf '\033]0;\a')
# $1 is expanded by the nested Bash process.
# shellcheck disable=SC2016
repeat_output=$(
  "$login_bash" --noprofile --norc -c \
    'set -u; unset __ETC_BASHLOGOUT_SOURCED NOSYSBASHLOGOUT; . "$1"; . "$1"' \
    bash "$logout_source"
)
if [ "$repeat_output" != "$marker" ]; then
  printf 'logout body did not run exactly once; output was %q\n' "$repeat_output" >&2
  exit 1
fi

# $1 is expanded by the nested Bash process.
# shellcheck disable=SC2016
disabled_output=$(
  "$login_bash" --noprofile --norc -c \
    'set -u; unset __ETC_BASHLOGOUT_SOURCED; NOSYSBASHLOGOUT=1; . "$1"' \
    bash "$logout_source"
)
if [ -n "$disabled_output" ]; then
  printf 'NOSYSBASHLOGOUT did not suppress the logout body; output was %q\n' \
    "$disabled_output" >&2
  exit 1
fi

printf 'ok: generated bash_logout is nounset-safe, idempotent, and exit-status preserving\n'
printf 'ok: ~/.local/bin preserves all 37 launchers + executable bits in a generation-retained store path; safe-push exposes --to\n'
printf 'ok: myfunctions enumerates the active ~/.local/bin launcher surface\n'
