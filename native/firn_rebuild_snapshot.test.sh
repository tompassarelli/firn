#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-snapshot-test.XXXXXX")"
trap 'rm -rf -- "${scratch:?}"' EXIT
mkdir -p "$scratch/repo/dotfiles/bin" "$scratch/bin" "$scratch/tmp" "$scratch/run"
printf '#!/usr/bin/env bash\n[[ "${FAKE_REVIEW:-}" != sleep ]] || sleep 3\n' >"$scratch/repo/dotfiles/bin/firn-check"
git -C "$scratch/repo" init -q
git -C "$scratch/repo" config user.name Firn
git -C "$scratch/repo" config user.email firn@example.invalid
git -C "$scratch/repo" add dotfiles/bin/firn-check
git -C "$scratch/repo" commit -qm baseline
git -C "$scratch/repo" tag gen-fixture-41
fake() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$scratch/bin/$1"; chmod +x "$scratch/bin/$1"; }
fake readlink 'if [[ "$1" == /nix/var/nix/profiles/system ]]; then echo system-41-link; else exec /run/current-system/sw/bin/readlink "$@"; fi'
fake firn 'case "${FAKE_VALIDATE:-ok}" in fail) exit 1;; sleep) sleep 3;; esac'
fake uname 'echo Linux'
fake systemctl 'echo not-found'
fake nix 'if [[ "$1" == build ]]; then echo /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-system; else echo false; fi'
fake sudo 'exit 0'
fake nixos-rebuild 'echo "42 current True"'
fake systemd-run 'exit 0'
fake login-shell 'exit 0'
rebuild() {
  exec env PATH="$scratch/bin:$PATH" TMPDIR="$scratch/tmp" XDG_RUNTIME_DIR="$scratch/run" FIRN_REPO="$scratch/repo" FIRN_HOST=fixture \
    FIRN_SYSTEM_PROFILE="$scratch/profile" FIRN_SYSTEM_FLAKE="$scratch/no-system" FIRN_TOOL_CHECK_SHELL="$scratch/bin/login-shell" \
    bun "$here/firn_rebuild_host.mjs" host rebuild fixture
}
clean() {
  local worktrees
  worktrees="$(git -C "$scratch/repo" worktree list --porcelain | rg -c '^worktree ')"
  [[ "$worktrees" == 1 && -z "$(ls -A "$scratch/run")" ]] || { git -C "$scratch/repo" worktree list >&2; cat "$scratch/$1.out" >&2; printf '%s left a snapshot worktree\n' "$1" >&2; exit 1; }
}
expect() {
  local status=0
  "${@:3}" >"$scratch/$1.out" 2>&1 || status=$?
  [[ "$status" == "$2" ]] || { cat "$scratch/$1.out" >&2; printf '%s exited %s, not %s\n' "$1" "$status" "$2" >&2; exit 1; }
  clean "$1"
}
expect success 0 bash -c "$(declare -p scratch here); $(declare -f rebuild); rebuild"
git -C "$scratch/repo" rev-parse -q --verify gen-fixture-42 >/dev/null
expect validation-failure 1 env FAKE_VALIDATE=fail bash -c "$(declare -p scratch here); $(declare -f rebuild); rebuild"
terminate() {
  set -m
  env "$2" bash -c "$(declare -p scratch here); $(declare -f rebuild); rebuild" >"$scratch/$1.out" 2>&1 &
  local pid=$! status=0
  set +m
  for _ in $(seq 50); do
    [[ -n "$(ls -A "$scratch/$4")" ]] && break
    sleep 0.1
  done
  if [[ "$3" == group ]]; then kill -TERM -- "-$pid"; else kill -TERM "$pid"; fi
  wait "$pid" || status=$?
  [[ "$status" == 143 ]] || { cat "$scratch/$1.out" >&2; printf '%s exited %s after SIGTERM, not 143\n' "$1" "$status" >&2; exit 1; }
  clean "$1"
}
terminate validation-sigterm-group FAKE_VALIDATE=sleep group run
terminate validation-sigterm-process FAKE_VALIDATE=sleep process run
terminate review-sigterm-process FAKE_REVIEW=sleep process tmp
[[ -z "$(ls -A "$scratch/tmp" | rg -v '^firn-review-' || true)" ]]
printf 'ok: firn rebuild retires its rebuild and review snapshot worktrees after success, validation failure and SIGTERM\n'
