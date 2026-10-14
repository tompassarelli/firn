#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-repo-workflows-js.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'repo-workflows-js: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'repo-workflows-js: %s\n' "$*" >&2
  exit 1
}

runtime="${FIRN_REPO_WORKFLOW_MODULE:-$repo/native/repo_workflows_runtime.ts}"

set +e
FIRN_REPO_WORKFLOW_MODULE="$runtime" \
  bun "$repo/native/repo_workflows_host.mjs" repo unknown \
  >"$scratch/usage.out" 2>"$scratch/usage.err"
usage_status=$?
set -e
[[ "$usage_status" == "64" ]] || die "invalid argv did not return 64"
[[ ! -s "$scratch/usage.out" ]] || die "invalid argv wrote stdout"

fixture_repo="$scratch/input-skew-repo"
fixture_home="$scratch/input-skew-home"
fixture_tool="$fixture_home/code/fixture-tool/main"
fixture_bin="$scratch/input-skew-bin"
mkdir -p "$fixture_repo" "$fixture_tool" "$fixture_bin"

git init --quiet --initial-branch=main "$fixture_tool"
git -C "$fixture_tool" config user.name "Firn native test"
git -C "$fixture_tool" config user.email "firn-native-test@example.invalid"
printf 'base\n' >"$fixture_tool/README"
git -C "$fixture_tool" add README
git -C "$fixture_tool" commit --quiet -m 'base'
pinned_rev="$(git -C "$fixture_tool" rev-parse HEAD)"
printf 'advance\n' >>"$fixture_tool/README"
git -C "$fixture_tool" commit --quiet -am 'advance'
git -C "$fixture_tool" remote add origin \
  https://github.com/tompassarelli/fixture-tool.git
independent_rev="$(
  printf 'independent\n' | git -C "$fixture_tool" commit-tree \
    "$(git -C "$fixture_tool" write-tree)"
)"

write_lock() {
  local revision="$1"
  printf '%s\n' \
    "{\"nodes\":{\"root\":{\"inputs\":{\"fixture-tool\":\"fixture-tool\",\"glide\":\"glide\"}},\"fixture-tool\":{\"locked\":{\"type\":\"github\",\"owner\":\"tompassarelli\",\"repo\":\"fixture-tool\",\"rev\":\"$revision\",\"narHash\":\"sha256-YWJjZA==\"}},\"glide\":{\"locked\":{\"type\":\"github\",\"owner\":\"tompassarelli\",\"repo\":\"glide\",\"rev\":\"$revision\",\"narHash\":\"sha256-YWJjZA==\"}}}}" \
    >"$fixture_repo/flake.lock"
}

run_pin_ancestry() {
  local result="$1"
  set +e
  timeout --foreground 30 env \
    HOME="$fixture_home" \
    FIRN_REPO="$fixture_repo" \
    FIRN_REPO_WORKFLOW_MODULE="$runtime" \
    bun "$repo/native/repo_workflows_host.mjs" repo pin-ancestry \
    >"$result.out" 2>"$result.err"
  local status=$?
  set -e
  printf '%s\n' "$status" >"$result.status"
}

write_lock "$pinned_rev"
pin_current="$scratch/pin-current"
run_pin_ancestry "$pin_current"
[[ "$(<"$pin_current.status")" == "0" ]] \
  || die "ancestor pin did not pass the narrow action"

write_lock "$independent_rev"
pin_skewed="$scratch/pin-skewed"
run_pin_ancestry "$pin_skewed"
[[ "$(<"$pin_skewed.status")" == 1 ]] \
  || die "non-ancestor pin was accepted"
inotify_bin="$(dirname "$(command -v inotifywait 2>/dev/null || true)")"
if [[ "$inotify_bin" == "." ]]; then
  inotify_bin="$(nix build --no-link --print-out-paths nixpkgs#inotify-tools)/bin" \
    || die "cannot provide inotifywait"
fi
fixture_nix="$scratch/nix-repo"
mkdir -p "$fixture_nix/modules/demo" "$fixture_nix/dotfiles/bin"
git init --quiet --initial-branch=main "$fixture_nix"
printf '%s\n' '{"version":7,"root":"root","nodes":{"root":{"inputs":{}}}}' >"$fixture_nix/flake.lock"
printf '{ enabled = false; }\n' >"$fixture_nix/modules/demo/default.nix"
cat >"$fixture_nix/flake.nix" <<'NIX'
{
  outputs = _: {
    nixosConfigurations.fixture.config.system.build.toplevel =
      assert (import ./modules/demo/default.nix).enabled;
      builtins.derivation { name = "fixture"; system = "x86_64-linux"; builder = "/bin/sh"; };
  };
}
NIX
cp "$repo/dotfiles/bin/firn-check" "$fixture_nix/dotfiles/bin/firn-check"
git -C "$fixture_nix" add flake.nix modules/demo/default.nix dotfiles/bin/firn-check

run_repo() {
  local result="$1"
  shift
  set +e
  timeout --foreground 60 env \
    PATH="$repo/dotfiles/bin:$inotify_bin:$PATH" \
    FIRN_REPO="$fixture_nix" \
    FIRN_REPO_WORKFLOW_MODULE="$runtime" \
    bun "$repo/native/repo_workflows_host.mjs" repo "$@" \
    >"$result.out" 2>"$result.err"
  printf '%s\n' "$?" >"$result.status"
  set -e
}

doctor="$scratch/doctor-assertion"
run_repo "$doctor" doctor
[[ "$(<"$doctor.status")" != 0 ]] || die "doctor passed an invalid Nix assertion"
grep -q 'assertion' "$doctor.out" "$doctor.err" \
  || die "doctor did not report the invalid assertion"

watch="$scratch/watch-nix"
run_repo "$watch" watch &
watch_pid=$!
for _ in $(seq 100); do
  pgrep -f "inotifywait.*$fixture_nix" >/dev/null && break
  sleep 0.1
done
printf '\n' >>"$fixture_nix/modules/demo/default.nix"
wait "$watch_pid"
grep -q 'firn check' "$watch.out" "$watch.err" \
  || die "watch did not validate after a .nix change"

upgrade="$scratch/upgrade-dry-run"
run_repo "$upgrade" upgrade dry-run
[[ "$(<"$upgrade.status")" == 0 ]] || die "upgrade dry run failed"
printf '%s\n' \
  '>> [dry-run] would run: nix flake update --flake <repo>' \
  '>> [dry-run] would run: firn schema extract for NixOS' \
  'firn upgrade: dry run complete; no files were changed.' \
  | cmp -s - "$upgrade.out" || die "upgrade dry run changed its phase order"
printf 'PASS repo-workflows-js\n'
