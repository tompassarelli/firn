#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-family-runtime-test.XXXXXX")"
cleanup() {
  rm -rf -- "${scratch:?}"
}
trap cleanup EXIT

home="$scratch/home"
beagle_path="$scratch/beagle-alt"
firn_repo="$scratch/firn-alt"
runtime_root="$scratch/runtime"
fake_bin="$scratch/bin"
mkdir -p "$home" "$beagle_path/bin" "$firn_repo/native" "$fake_bin"
printf 'alpha\n' >"$firn_repo/marker"

datum_reader="$beagle_path/native-core/src/beagle/datum_reader.bgl"
native_json="$beagle_path/native-core/src/native/json.bgl"
nix_schema_path="$beagle_path/native-core/src/beagle/nix_schema_path.bgl"
dispatcher_source="$firn_repo/native/firn.bjs"
dispatcher_bridge="$firn_repo/native/firn_host.mjs"
beagle_core="$beagle_path/beagle-lib/lib/beagle/core.js"
beagle_host="$beagle_path/beagle-lib/lib/beagle/host.js"
dispatcher_sources=(
  "$dispatcher_source"
  "$dispatcher_bridge"
  "$beagle_core"
  "$beagle_host"
)
tag_sources=(
  "$datum_reader"
  "$native_json"
  "$firn_repo/native/tag_resolve.bgl"
  "$firn_repo/native/tag_inputs.bgl"
  "$firn_repo/native/tag_resolve_driver.bgl"
  "$firn_repo/native/tag_resolve_native.bgl"
  "$firn_repo/native/tag_commands.bgl"
  "$firn_repo/native/tag_commands_driver.bgl"
  "$firn_repo/native/tag_commands_native.bgl"
  "$firn_repo/native/firn_tag_family.bgl"
)
flake_input_sources=(
  "$datum_reader"
  "$firn_repo/native/flake_input.bgl"
  "$firn_repo/native/flake_input_driver.bgl"
  "$firn_repo/native/flake_input_native.bgl"
)
inventory_sources=(
  "$datum_reader"
  "$native_json"
  "$firn_repo/native/tag_resolve.bgl"
  "$firn_repo/native/tag_inputs.bgl"
  "$firn_repo/native/tag_resolve_driver.bgl"
  "$firn_repo/native/tag_resolve_native.bgl"
  "$firn_repo/native/inventory.bgl"
  "$firn_repo/native/inventory_native.bgl"
)
authoring_sources=(
  "$native_json"
  "$firn_repo/native/authoring.bgl"
  "$firn_repo/native/authoring_native.bgl"
)
views_sources=(
  "$datum_reader"
  "$native_json"
  "$nix_schema_path"
  "$firn_repo/native/firn_views.bgl"
  "$firn_repo/native/firn_views_native.bgl"
)
repo_build_sources=(
  "$datum_reader"
  "$native_json"
  "$firn_repo/native/tag_resolve.bgl"
  "$firn_repo/native/tag_inputs.bgl"
  "$firn_repo/native/tag_resolve_driver.bgl"
  "$firn_repo/native/tag_resolve_native.bgl"
  "$firn_repo/native/flake_input.bgl"
  "$firn_repo/native/flake_input_driver.bgl"
  "$firn_repo/native/flake_input_native.bgl"
  "$firn_repo/native/repo_build.bgl"
  "$firn_repo/native/repo_build_native.bgl"
)
schema_sources=(
  "$native_json"
  "$firn_repo/native/schema_transaction.bgl"
  "$firn_repo/native/schema_transaction_native.bgl"
)
repo_workflow_sources=(
  "$native_json"
  "$firn_repo/native/repo_quality.bgl"
  "$firn_repo/native/repo_workflows.bgl"
  "$firn_repo/native/repo_workflows_native.bgl"
)
rebuild_sources=(
  "$native_json"
  "$firn_repo/native/impact.bgl"
  "$firn_repo/native/rebuild.bgl"
  "$firn_repo/native/rebuild_native.bgl"
  "$firn_repo/native/firn_rebuild_family.bgl"
)
prewarm_sources=(
  "$firn_repo/native/prewarm.bgl"
  "$firn_repo/native/prewarm_native.bgl"
)
all_sources=(
  "${dispatcher_sources[@]}"
  "${tag_sources[@]}"
  "${flake_input_sources[@]}"
  "${inventory_sources[@]}"
  "${authoring_sources[@]}"
  "${views_sources[@]}"
  "${repo_build_sources[@]}"
  "${schema_sources[@]}"
  "${repo_workflow_sources[@]}"
  "${rebuild_sources[@]}"
  "${prewarm_sources[@]}"
)
for source in "${all_sources[@]}"; do
  mkdir -p "$(dirname "$source")"
  case "$source" in
    *.bjs) printf '#lang beagle/js\n' >"$source" ;;
    *.mjs|*.js) printf 'fixture\n' >"$source" ;;
    *) printf '#lang beagle\n' >"$source" ;;
  esac
done

cat >"$beagle_path/bin/beagle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'BEAGLE_CALL\0' >>"$FAKE_BEAGLE_LOG"
printf '%s\0' "$BEAGLE_PATH" "$FIRN_REPO" "$@" >>"$FAKE_BEAGLE_LOG"
if [[ "${1:-}" == build ]]; then
  output="$3"
  if [[ -z "${FAKE_BAD_DISPATCHER:-}" ]]; then
    marker="$(sed -n '1p' "$FIRN_REPO/marker")"
    printf '// dispatcher:%s\n' "$marker" >"$output"
    printf '{"version":3}\n' >"$output.map"
  fi
  exit 0
fi
[[ "${1:-}" == native-exe ]]
out=""
artifacts=""
entry=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --artifacts) artifacts="$2"; shift 2 ;;
    --entry) entry="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$out" && -n "$artifacts" && -n "$entry" ]]
marker="$(sed -n '1p' "$FIRN_REPO/marker")"
cat >"$out" <<INNER
#!/usr/bin/env bash
printf 'prepared:%s:%s\n' '$marker' '$entry'
printf 'RUNTIME_CALL\0' >>"\$FAKE_RUNTIME_LOG"
printf '%s\0' '$entry' "\$BEAGLE_PATH" "\$FIRN_REPO" \
  "\$FIRN_RUNTIME_BIN" "\$@" >>"\$FAKE_RUNTIME_LOG"
if [[ -n "\${FAKE_RUNTIME_STDERR:-}" ]]; then
  printf '%s\n' "\$FAKE_RUNTIME_STDERR" >&2
fi
exit "\${FAKE_RUNTIME_STATUS:-0}"
INNER
chmod +x "$out"
if [[ -n "${FAKE_BAD_IDENTITY:-}" ||
      "${FAKE_BAD_IDENTITY_ENTRY:-}" == "$entry" ]]; then
  printf 'source-entry wrong.entry/-main\n' >"$artifacts/report.txt"
else
  source_digit=a
  [[ "$marker" == alpha ]] || source_digit=b
  printf 'source-entry %s\n' "$entry" >"$artifacts/report.txt"
  source_id="$(printf '%064d' 0 | tr 0 "$source_digit")"
  printf 'native-provenance-v0 source sha256:%s\n' "$source_id" \
    >>"$artifacts/report.txt"
fi
printf 'native-exe-entry PASS name=%s symbol=fake return=Int abi=argv\n' \
  "$entry" >"$artifacts/native-exe.report.txt"
EOF
chmod +x "$beagle_path/bin/beagle"

cat >"$fake_bin/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
bridge="$1"
shift
printf 'BUN_CALL\0' >>"$FAKE_BUN_LOG"
printf '%s\0' "$bridge" "$FIRN_RUNTIME_BIN" "$@" >>"$FAKE_BUN_LOG"
case "${1:-}:${2:-}" in
  repo:validate) family=firn-schema ;;
  host:list) family=firn-inventory ;;
  tag:resolve) family=firn-tag ;;
  flake-input:resolve) family=firn-flake-input ;;
  module:add) family=firn-authoring ;;
  platform:list) family=firn-views ;;
  repo:build) family=firn-repo-build ;;
  repo:doctor) family=firn-repo-workflow ;;
  host:rebuild) family=firn-rebuild ;;
  --print-warm-key:) family=firn-prewarm ;;
  *) exit 64 ;;
esac
exec "$FIRN_RUNTIME_BIN/$family" "$@"
EOF
chmod +x "$fake_bin/bun"

cat >"$fake_bin/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
[[ "\${1:-}" == -C && "\${3:-}" == rev-parse && "\${4:-}" == HEAD ]]
case "\$2" in
  "$firn_repo") printf '1111111111111111111111111111111111111111\\n' ;;
  "$beagle_path") printf '2222222222222222222222222222222222222222\\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/git"

for command in nix nix-store beagle python3 bb north; do
  cat >"$fake_bin/$command" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >>"$BOOT_CLOSURE_TRIPWIRE_LOG"
exit 97
EOF
  chmod +x "$fake_bin/$command"
done

export HOME="$home"
export PATH="$fake_bin:$PATH"
export BEAGLE_PATH="$beagle_path"
export FIRN_REPO="$firn_repo"
export FIRN_RUNTIME_ROOT="$runtime_root"
export FAKE_BEAGLE_LOG="$scratch/beagle.log"
export FAKE_BUN_LOG="$scratch/bun.log"
export FAKE_RUNTIME_LOG="$scratch/runtime.log"
export BOOT_CLOSURE_TRIPWIRE_LOG="$scratch/boot-closure.log"

repo_runtime_root="$scratch/repo-runtime"
FIRN_RUNTIME_ROOT="$repo_runtime_root" \
  "$here/firn-runtime-update" repo >"$scratch/update-repo.stdout"
repo_target="$(readlink "$repo_runtime_root/current")"
repo_destination="$repo_runtime_root/$repo_target"
grep -Fxq 'scope=repo' "$repo_destination/manifest"
for component in repo-build schema; do
  grep -Fq "component=$component " "$repo_destination/manifest"
done
for component in tag flake-input inventory authoring views repo-workflow \
  rebuild prewarm; do
  ! grep -Fq "component=$component " "$repo_destination/manifest"
done
for artifact in dispatcher dispatcher-map bridge beagle-core beagle-host \
  beagle-package; do
  grep -Fq "artifact=$artifact " "$repo_destination/manifest"
done
[[ "$(FIRN_RUNTIME_ROOT="$repo_runtime_root" "$here/firn" repo build all)" == \
  prepared:alpha:firn.repo-build-native/-main ]]
[[ "$(FIRN_RUNTIME_ROOT="$repo_runtime_root" "$here/firn" repo validate)" == \
  prepared:alpha:firn.schema-transaction-native/-main ]]

printf 'beta\n' >"$firn_repo/marker"
set +e
FAKE_BAD_IDENTITY_ENTRY=firn.schema-transaction-native/-main \
  FIRN_RUNTIME_ROOT="$repo_runtime_root" \
  "$here/firn-runtime-update" repo \
  >"$scratch/invalid-repo.stdout" 2>"$scratch/invalid-repo.stderr"
invalid_repo_status=$?
set -e
[[ "$invalid_repo_status" -ne 0 ]]
grep -Fxq \
  'firn-runtime-update: materializer producer identity is invalid: schema' \
  "$scratch/invalid-repo.stderr"
[[ "$(readlink "$repo_runtime_root/current")" == "$repo_target" ]]
[[ "$(FIRN_RUNTIME_ROOT="$repo_runtime_root" "$here/firn" repo validate)" == \
  prepared:alpha:firn.schema-transaction-native/-main ]]

printf 'alpha\n' >"$firn_repo/marker"
"$here/firn-runtime-update" >"$scratch/update-alpha.stdout"
expected_entries=(
  firn.schema-transaction-native/-main
  firn.inventory-native/-main
  firn.tag-family/-main
  firn.flake-input-native/-main
  firn.authoring-native/-main
  firn.views-native/-main
  firn.repo-build-native/-main
  firn.repo-workflows-native/-main
  firn.rebuild-family/-main
  firn.prewarm-native/-main
)
expected_commands=(
  'repo validate'
  'host list all'
  'tag resolve whiterabbit'
  'flake-input resolve emit'
  'module add example'
  'platform list linux'
  'repo build all'
  'repo doctor all'
  'host rebuild whiterabbit'
  '--print-warm-key'
)
for index in "${!expected_commands[@]}"; do
  read -r -a args <<<"${expected_commands[index]}"
  expected="prepared:alpha:${expected_entries[index]}"
  [[ "$("$here/firn" "${args[@]}")" == "$expected" ]]
done
set +e
FAKE_BUN_LOG=/dev/null FAKE_RUNTIME_LOG=/dev/null \
  FAKE_RUNTIME_STDERR=owned-stderr FAKE_RUNTIME_STATUS=23 \
  "$here/firn" repo validate \
  >"$scratch/status.stdout" 2>"$scratch/status.stderr"
runtime_status=$?
set -e
[[ "$runtime_status" -eq 23 ]]
grep -Fxq 'prepared:alpha:firn.schema-transaction-native/-main' \
  "$scratch/status.stdout"
grep -Fxq 'owned-stderr' "$scratch/status.stderr"

alpha_target="$(readlink "$runtime_root/current")"
alpha_destination="$runtime_root/$alpha_target"
[[ -f "$alpha_destination/bin/firn-host.mjs" ]]
[[ -f "$alpha_destination/lib/firn-dispatcher.js" ]]
grep -Fxq 'format=firn-cli-runtime/v2' "$alpha_destination/manifest"
grep -Fxq 'scope=full' "$alpha_destination/manifest"
grep -Fxq 'firn_revision=1111111111111111111111111111111111111111' \
  "$alpha_destination/manifest"
grep -Fxq 'beagle_revision=2222222222222222222222222222222222222222' \
  "$alpha_destination/manifest"
for component in tag flake-input inventory authoring views repo-build \
  schema repo-workflow rebuild prewarm; do
  grep -Fq "component=$component " "$alpha_destination/manifest"
done
for artifact in dispatcher dispatcher-map bridge beagle-core beagle-host \
  beagle-package; do
  grep -Fq "artifact=$artifact " "$alpha_destination/manifest"
done

printf 'beta\n' >"$firn_repo/marker"
[[ "$("$here/firn" repo validate)" == \
  prepared:alpha:firn.schema-transaction-native/-main ]]
"$here/firn-runtime-update" >"$scratch/update-beta.stdout"
[[ "$("$here/firn" repo validate)" == \
  prepared:beta:firn.schema-transaction-native/-main ]]
beta_target="$(readlink "$runtime_root/current")"
beta_destination="$runtime_root/$beta_target"
[[ "$beta_target" != "$alpha_target" ]]
[[ -f "$alpha_destination/bin/firn-host.mjs" ]]
[[ -f "$beta_destination/bin/firn-host.mjs" ]]

set +e
FAKE_BAD_DISPATCHER=1 "$here/firn-runtime-update" \
  >"$scratch/invalid.stdout" 2>"$scratch/invalid.stderr"
invalid_status=$?
set -e
[[ "$invalid_status" -ne 0 ]]
grep -Fxq \
  'firn-runtime-update: materializer produced no JS dispatcher' \
  "$scratch/invalid.stderr"
[[ "$(readlink "$runtime_root/current")" == "$beta_target" ]]

mapfile -d '' -t beagle_fields <"$FAKE_BEAGLE_LOG"
cursor=0
assert_stage_root="$runtime_root"
assert_dispatcher_call() {
  [[ "${beagle_fields[cursor++]}" == BEAGLE_CALL ]]
  [[ "${beagle_fields[cursor++]}" == "$beagle_path" ]]
  [[ "${beagle_fields[cursor++]}" == "$firn_repo" ]]
  [[ "${beagle_fields[cursor++]}" == build ]]
  [[ "${beagle_fields[cursor++]}" == "$dispatcher_source" ]]
  out="${beagle_fields[cursor++]}"
  stage="${out%/lib/firn-dispatcher.js}"
  [[ "$out" == "$stage/lib/firn-dispatcher.js" ]]
  [[ "$stage" == "$assert_stage_root"/.stage.* ]]
}
assert_call() {
  local binary="$1"
  local entry="$2"
  shift 2
  [[ "${beagle_fields[cursor++]}" == BEAGLE_CALL ]]
  [[ "${beagle_fields[cursor++]}" == "$beagle_path" ]]
  [[ "${beagle_fields[cursor++]}" == "$firn_repo" ]]
  [[ "${beagle_fields[cursor++]}" == native-exe ]]
  [[ "${beagle_fields[cursor++]}" == --out ]]
  out="${beagle_fields[cursor++]}"
  stage="${out%/bin/$binary}"
  [[ "$stage" == "$assert_stage_root"/.stage.* ]]
  [[ "${beagle_fields[cursor++]}" == --artifacts ]]
  [[ "${beagle_fields[cursor++]}" == "$stage/artifacts/${binary#firn-}" ]]
  [[ "${beagle_fields[cursor++]}" == --entry ]]
  [[ "${beagle_fields[cursor++]}" == "$entry" ]]
  for source in "$@"; do
    [[ "${beagle_fields[cursor++]}" == "$source" ]]
  done
}
assert_bundle_calls() {
  assert_dispatcher_call
  assert_call firn-tag firn.tag-family/-main "${tag_sources[@]}"
  assert_call firn-flake-input firn.flake-input-native/-main \
    "${flake_input_sources[@]}"
  assert_call firn-inventory firn.inventory-native/-main \
    "${inventory_sources[@]}"
  assert_call firn-authoring firn.authoring-native/-main \
    "${authoring_sources[@]}"
  assert_call firn-views firn.views-native/-main "${views_sources[@]}"
  assert_call firn-repo-build firn.repo-build-native/-main \
    "${repo_build_sources[@]}"
  assert_call firn-schema firn.schema-transaction-native/-main \
    "${schema_sources[@]}"
  assert_call firn-repo-workflow firn.repo-workflows-native/-main \
    "${repo_workflow_sources[@]}"
  assert_call firn-rebuild firn.rebuild-family/-main \
    "${rebuild_sources[@]}"
  assert_call firn-prewarm firn.prewarm-native/-main \
    "${prewarm_sources[@]}"
}
assert_stage_root="$repo_runtime_root"
assert_dispatcher_call
assert_call firn-repo-build firn.repo-build-native/-main \
  "${repo_build_sources[@]}"
assert_call firn-schema firn.schema-transaction-native/-main \
  "${schema_sources[@]}"
assert_dispatcher_call
assert_call firn-repo-build firn.repo-build-native/-main \
  "${repo_build_sources[@]}"
assert_call firn-schema firn.schema-transaction-native/-main \
  "${schema_sources[@]}"
assert_stage_root="$runtime_root"
assert_bundle_calls
assert_bundle_calls
assert_dispatcher_call
[[ "$cursor" -eq "${#beagle_fields[@]}" ]]

mapfile -d '' -t runtime_fields <"$FAKE_RUNTIME_LOG"
mapfile -d '' -t bun_fields <"$FAKE_BUN_LOG"
cursor=0
bun_cursor=0
runtime_invocations=('repo build all' 'repo validate' 'repo validate'
  "${expected_commands[@]}" 'repo validate' 'repo validate')
runtime_entries=(firn.repo-build-native/-main
  firn.schema-transaction-native/-main
  firn.schema-transaction-native/-main
  "${expected_entries[@]}"
  firn.schema-transaction-native/-main
  firn.schema-transaction-native/-main)
runtime_roots=("$repo_runtime_root" "$repo_runtime_root" "$repo_runtime_root")
for _ in "${expected_commands[@]}" 'repo validate' 'repo validate'; do
  runtime_roots+=("$runtime_root")
done
for index in "${!runtime_invocations[@]}"; do
  [[ "${bun_fields[bun_cursor++]}" == BUN_CALL ]]
  [[ "${bun_fields[bun_cursor++]}" == \
    "${runtime_roots[index]}/current/bin/firn-host.mjs" ]]
  [[ "${bun_fields[bun_cursor++]}" == \
    "${runtime_roots[index]}/current/bin" ]]
  [[ "${runtime_fields[cursor++]}" == RUNTIME_CALL ]]
  [[ "${runtime_fields[cursor++]}" == "${runtime_entries[index]}" ]]
  [[ "${runtime_fields[cursor++]}" == "$beagle_path" ]]
  [[ "${runtime_fields[cursor++]}" == "$firn_repo" ]]
  [[ "${runtime_fields[cursor++]}" == "${runtime_roots[index]}/current/bin" ]]
  read -r -a args <<<"${runtime_invocations[index]}"
  for arg in "${args[@]}"; do
    [[ "${bun_fields[bun_cursor++]}" == "$arg" ]]
    [[ "${runtime_fields[cursor++]}" == "$arg" ]]
  done
done
[[ "$cursor" -eq "${#runtime_fields[@]}" ]]
[[ "$bun_cursor" -eq "${#bun_fields[@]}" ]]
[[ ! -e "$BOOT_CLOSURE_TRIPWIRE_LOG" ]]

missing_root="$scratch/missing-runtime"
set +e
FIRN_RUNTIME_ROOT="$missing_root" "$here/firn" repo validate \
  >"$scratch/missing.stdout" 2>"$scratch/missing.stderr"
missing_status=$?
set -e
[[ "$missing_status" -eq 127 ]]
grep -Fxq 'firn: user runtime is not installed; run firn-runtime-update' \
  "$scratch/missing.stderr"
[[ ! -s "$scratch/missing.stdout" ]]

BEAGLE_PATH="$beagle_path" FAKE_BEAGLE_LOG="$scratch/beagle-command.log" \
  FIRN_REPO="$firn_repo" "$here/beagle" check sentinel.bgl >/dev/null
mapfile -d '' -t command_fields <"$scratch/beagle-command.log"
[[ "${command_fields[0]}" == BEAGLE_CALL ]]
[[ "${command_fields[1]}" == "$beagle_path" ]]
[[ "${command_fields[2]}" == "$firn_repo" ]]
[[ "${command_fields[3]}" == check ]]
[[ "${command_fields[4]}" == sentinel.bgl ]]

printf 'firn-family-runtime: PASS\n'
