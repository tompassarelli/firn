#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)

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
