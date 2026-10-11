#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
if [[ -n "${BEAGLE_PATH:-}" ]]; then
  beagle="$BEAGLE_PATH"
else
  git_common_dir="$(
    timeout --foreground 5 git -C "$repo" rev-parse \
      --path-format=absolute --git-common-dir
  )" || {
    printf 'repo-workflows-native: cannot locate Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
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

json="$beagle/native-core/src/native/json.bjs"
quality="$repo/native/repo_quality.bjs"
workflows="$repo/native/repo_workflows.bjs"
runtime="$repo/native/repo_workflows_runtime.bjs"
mkdir -p "$scratch/modules/node_modules/beagle"
timeout --foreground 90 "$beagle/bin/beagle-build-all" \
  "$json" "$quality" \
  "$workflows" "$runtime" \
  --out "$scratch/modules" \
  >"$scratch/build.out" 2>"$scratch/build.err" || {
    sed -n '1,240p' "$scratch/build.err" >&2
    die "module graph compilation failed"
  }
cp -- "$beagle/beagle-lib/lib/beagle/core.js" \
  "$scratch/modules/node_modules/beagle/core.js"
cp -- "$beagle/beagle-lib/lib/beagle/host.js" \
  "$scratch/modules/node_modules/beagle/host.js"
printf '%s\n' '{"type":"module"}' \
  >"$scratch/modules/node_modules/beagle/package.json"

set +e
FIRN_REPO_WORKFLOW_MODULE="$scratch/modules/firn/repo-workflows-runtime.js" \
  bun "$repo/native/repo_workflows_host.mjs" repo unknown \
  >"$scratch/usage.out" 2>"$scratch/usage.err"
usage_status=$?
set -e
[[ "$usage_status" == "64" ]] || die "invalid argv did not return 64"
[[ ! -s "$scratch/usage.out" ]] || die "invalid argv wrote stdout"

fixture_repo="$scratch/input-skew-repo"
fixture_home="$scratch/input-skew-home"
fixture_beagle="$fixture_home/code/beagle/main"
fixture_bin="$scratch/input-skew-bin"
mkdir -p "$fixture_repo" "$fixture_beagle" "$fixture_bin"

git init --quiet --initial-branch=main "$fixture_beagle"
git -C "$fixture_beagle" config user.name "Firn native test"
git -C "$fixture_beagle" config user.email "firn-native-test@example.invalid"
printf 'base\n' >"$fixture_beagle/README"
git -C "$fixture_beagle" add README
git -C "$fixture_beagle" commit --quiet -m 'base'
pinned_rev="$(git -C "$fixture_beagle" rev-parse HEAD)"
printf 'advance\n' >>"$fixture_beagle/README"
git -C "$fixture_beagle" commit --quiet -am 'advance'
git -C "$fixture_beagle" remote add origin \
  https://github.com/tompassarelli/beagle.git
independent_rev="$(
  printf 'independent\n' | git -C "$fixture_beagle" commit-tree \
    "$(git -C "$fixture_beagle" write-tree)"
)"

write_lock() {
  local revision="$1"
  printf '%s\n' \
    "{\"nodes\":{\"root\":{\"inputs\":{\"beagle\":\"beagle\",\"glide\":\"glide\"}},\"beagle\":{\"locked\":{\"type\":\"github\",\"owner\":\"tompassarelli\",\"repo\":\"beagle\",\"rev\":\"$revision\",\"narHash\":\"sha256-YWJjZA==\"}},\"glide\":{\"locked\":{\"type\":\"github\",\"owner\":\"tompassarelli\",\"repo\":\"glide\",\"rev\":\"$revision\",\"narHash\":\"sha256-YWJjZA==\"}}}}" \
    >"$fixture_repo/flake.lock"
}

run_pin_ancestry() {
  local result="$1"
  set +e
  timeout --foreground 30 env \
    HOME="$fixture_home" \
    FIRN_REPO="$fixture_repo" \
    FIRN_REPO_WORKFLOW_MODULE="$scratch/modules/firn/repo-workflows-runtime.js" \
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
galileo_dir="${FIRN_RUNTIME_BIN:-}"
if [[ ! -x "$galileo_dir/galileo" ]]; then
  galileo_dir="$(dirname "$(command -v galileo)")" \
    || die "galileo is not on PATH or in FIRN_RUNTIME_BIN"
fi
inotify_bin="$(dirname "$(command -v inotifywait 2>/dev/null || true)")"
if [[ "$inotify_bin" == "." ]]; then
  inotify_bin="$(nix build --no-link --print-out-paths nixpkgs#inotify-tools)/bin" \
    || die "cannot provide inotifywait"
fi

gal_repo="$scratch/gal-repo"
mkdir -p "$gal_repo/modules/demo"
git init --quiet --initial-branch=main "$gal_repo"
printf '%s\n' '{"nodes":{"root":{"inputs":{}}}}' >"$gal_repo/flake.lock"
printf '%s\n' 'nix module' '  arguments: config, lib, ...' \
  '  option "myConfig"."modules"."demo"."enable": enable "demo"' \
  >"$gal_repo/modules/demo/default.gal"
(cd "$gal_repo" && "$galileo_dir/galileo" build) >/dev/null \
  || die "fixture galileo build failed"
printf '# stale\n' >>"$gal_repo/modules/demo/default.nix"

run_repo() {
  local result="$1"
  shift
  set +e
  timeout --foreground 60 env \
    PATH="$repo/dotfiles/bin:$inotify_bin:$PATH" \
    FIRN_RUNTIME_BIN="$galileo_dir" \
    FIRN_REPO="$gal_repo" \
    FIRN_REPO_WORKFLOW_MODULE="$scratch/modules/firn/repo-workflows-runtime.js" \
    bun "$repo/native/repo_workflows_host.mjs" repo "$@" \
    >"$result.out" 2>"$result.err"
  printf '%s\n' "$?" >"$result.status"
  set -e
}

doctor="$scratch/doctor-stale"
run_repo "$doctor" doctor
[[ "$(<"$doctor.status")" != 0 ]] || die "doctor passed a stale generated output"
grep -q 'modules/demo/default.nix (committed)' "$doctor.out" "$doctor.err" \
  || die "doctor did not name the stale generated output"

watch="$scratch/watch-gal"
run_repo "$watch" watch &
watch_pid=$!
for _ in $(seq 100); do
  pgrep -f "inotifywait.*$gal_repo" >/dev/null && break
  sleep 0.1
done
printf '\n' >>"$gal_repo/modules/demo/default.gal"
wait "$watch_pid"
grep -q 'galileo check' "$watch.err" \
  || die "watch did not validate after a .gal change"

upgrade="$scratch/upgrade-dry-run"
run_repo "$upgrade" upgrade dry-run
[[ "$(<"$upgrade.status")" == 0 ]] || die "upgrade dry run failed"
printf '%s\n' \
  '>> [dry-run] would run: nix flake update --flake <repo>' \
  '>> [dry-run] would run: galileo schema extract for NixOS' \
  'firn upgrade: dry run complete; no files were changed.' \
  | cmp -s - "$upgrade.out" || die "upgrade dry run changed its phase order"
printf 'PASS repo-workflows-js\n'
