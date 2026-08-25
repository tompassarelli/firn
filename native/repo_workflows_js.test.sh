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
timeout --foreground 90 "$beagle/bin/beagle" build \
  "$json" "$quality" "$workflows" "$runtime" \
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

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fixture_bin/beagle"
chmod +x "$fixture_bin/beagle"

run_doctor() {
  local result="$1"
  set +e
  timeout --foreground 30 env \
    HOME="$fixture_home" \
    FIRN_REPO="$fixture_repo" \
    PATH="$fixture_bin:$PATH" \
    FIRN_REPO_WORKFLOW_MODULE="$scratch/modules/firn/repo-workflows-runtime.js" \
    bun "$repo/native/repo_workflows_host.mjs" repo doctor \
    >"$result.out" 2>"$result.err"
  local status=$?
  set -e
  printf '%s\n' "$status" >"$result.status"
}

write_lock "$pinned_rev"
doctor_current="$scratch/doctor-current"
run_doctor "$doctor_current"
[[ "$(<"$doctor_current.status")" == "0" ]] \
  || die "ancestor pin did not pass doctor"
rg -F "pinned $pinned_rev is an ancestor of local beagle/main" \
  "$doctor_current.out" >/dev/null \
  || die "doctor did not report a current first-party input"
rg -F "local checkout $fixture_home/code/glide/main is absent; skipped (portable)" \
  "$doctor_current.out" >/dev/null \
  || die "doctor did not report portable missing local input"
[[ ! -s "$doctor_current.err" ]] \
  || die "current first-party input wrote stderr"

write_lock "$independent_rev"
doctor_skewed="$scratch/doctor-skewed"
run_doctor "$doctor_skewed"
[[ "$(<"$doctor_skewed.status")" == "1" ]] \
  || die "skewed pin did not fail doctor"
rg -F "pinned $independent_rev is not an ancestor of local beagle/main" \
  "$doctor_skewed.err" >/dev/null \
  || die "doctor did not identify first-party input skew"

printf 'PASS repo-workflows-js\n'
