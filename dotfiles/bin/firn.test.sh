#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-runtime-launcher-test.XXXXXX")"
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

sources=(
  "$beagle_path/native-core/src/beagle/datum_reader.bgl"
  "$beagle_path/native-core/src/native/json.bgl"
  "$beagle_path/native-core/src/beagle/nix_schema_path.bgl"
  "$firn_repo/native/tag_resolve.bgl"
  "$firn_repo/native/tag_inputs.bgl"
  "$firn_repo/native/tag_resolve_driver.bgl"
  "$firn_repo/native/tag_resolve_native.bgl"
  "$firn_repo/native/inventory.bgl"
  "$firn_repo/native/inventory_native.bgl"
  "$firn_repo/native/authoring.bgl"
  "$firn_repo/native/authoring_native.bgl"
  "$firn_repo/native/flake_input.bgl"
  "$firn_repo/native/flake_input_driver.bgl"
  "$firn_repo/native/flake_input_native.bgl"
  "$firn_repo/native/tag_commands.bgl"
  "$firn_repo/native/tag_commands_driver.bgl"
  "$firn_repo/native/tag_commands_native.bgl"
  "$firn_repo/native/firn_views.bgl"
  "$firn_repo/native/firn_views_native.bgl"
  "$firn_repo/native/schema_transaction.bgl"
  "$firn_repo/native/schema_transaction_native.bgl"
  "$firn_repo/native/repo_quality.bgl"
  "$firn_repo/native/repo_workflows.bgl"
  "$firn_repo/native/repo_workflows_native.bgl"
  "$firn_repo/native/impact.bgl"
  "$firn_repo/native/rebuild.bgl"
  "$firn_repo/native/rebuild_native.bgl"
  "$firn_repo/native/repo_build.bgl"
  "$firn_repo/native/repo_build_native.bgl"
  "$firn_repo/native/prewarm.bgl"
  "$firn_repo/native/prewarm_native.bgl"
  "$firn_repo/native/system_policy.bgl"
  "$firn_repo/native/firn.bgl"
)
for source in "${sources[@]}"; do
  mkdir -p "$(dirname "$source")"
  printf '#lang beagle\n' >"$source"
done

cat >"$beagle_path/bin/beagle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'BEAGLE_CALL\0' >>"$FAKE_BEAGLE_LOG"
printf '%s\0' "$BEAGLE_PATH" "$FIRN_REPO" "$@" >>"$FAKE_BEAGLE_LOG"
[[ "${1:-}" == native-exe ]]
out=""
artifacts=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --artifacts) artifacts="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$out" && -n "$artifacts" ]]
marker="$(sed -n '1p' "$FIRN_REPO/marker")"
cat >"$out" <<INNER
#!/usr/bin/env bash
printf 'prepared:%s\\n' '$marker'
printf 'RUNTIME_CALL\\0' >>"\$FAKE_RUNTIME_LOG"
printf '%s\\0' "\$BEAGLE_PATH" "\$FIRN_REPO" "\$@" >>"\$FAKE_RUNTIME_LOG"
INNER
chmod +x "$out"
if [[ -n "${FAKE_BAD_IDENTITY:-}" ]]; then
  printf 'source-entry wrong.entry/-main\n' >"$artifacts/report.txt"
else
  source_digit=a
  [[ "$marker" == alpha ]] || source_digit=b
  printf 'source-entry firn.main/-main\n' >"$artifacts/report.txt"
  source_id="$(printf '%064d' 0 | tr 0 "$source_digit")"
  printf 'native-provenance-v0 source sha256:%s\n' "$source_id" \
    >>"$artifacts/report.txt"
fi
printf 'native-exe-entry PASS name=firn.main/-main symbol=fake return=Int abi=argv\n' \
  >"$artifacts/native-exe.report.txt"
EOF
chmod +x "$beagle_path/bin/beagle"

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
export FAKE_RUNTIME_LOG="$scratch/runtime.log"
export BOOT_CLOSURE_TRIPWIRE_LOG="$scratch/boot-closure.log"

"$here/firn-runtime-update" >"$scratch/update-alpha.stdout"
[[ "$("$here/firn" repo validate)" == prepared:alpha ]]
[[ "$("$here/firn" repo validate all)" == prepared:alpha ]]
[[ "$("$here/firn" repo validate hosts/whiterabbit/configuration.bnix)" == prepared:alpha ]]
[[ "$("$here/firn" repo validate tag enable terminal)" == prepared:alpha ]]

printf 'beta\n' >"$firn_repo/marker"
[[ "$("$here/firn" host list all)" == prepared:alpha ]]
alpha_target="$(readlink "$runtime_root/current")"
alpha_destination="$runtime_root/$alpha_target"
[[ -x "$alpha_destination/bin/firn" ]]
grep -Fxq 'format=firn-cli-runtime/v1' "$alpha_destination/provenance"
grep -Fxq 'entry=firn.main/-main' "$alpha_destination/provenance"
grep -Fxq 'firn_revision=1111111111111111111111111111111111111111' \
  "$alpha_destination/provenance"
grep -Fxq 'beagle_revision=2222222222222222222222222222222222222222' \
  "$alpha_destination/provenance"

"$here/firn-runtime-update" >"$scratch/update-beta.stdout"
[[ "$("$here/firn" host list all)" == prepared:beta ]]
beta_target="$(readlink "$runtime_root/current")"
beta_destination="$runtime_root/$beta_target"
[[ "$beta_target" != "$alpha_target" ]]
[[ -x "$alpha_destination/bin/firn" ]]
[[ -x "$beta_destination/bin/firn" ]]

set +e
FAKE_BAD_IDENTITY=1 "$here/firn-runtime-update" \
  >"$scratch/invalid.stdout" 2>"$scratch/invalid.stderr"
invalid_status=$?
set -e
[[ "$invalid_status" -ne 0 ]]
grep -Fxq 'firn-runtime-update: materializer producer identity is invalid' \
  "$scratch/invalid.stderr"
[[ "$(readlink "$runtime_root/current")" == "$beta_target" ]]

mapfile -d '' -t beagle_fields <"$FAKE_BEAGLE_LOG"
cursor=0
for call in 1 2 3; do
  [[ "${beagle_fields[cursor++]}" == BEAGLE_CALL ]]
  [[ "${beagle_fields[cursor++]}" == "$beagle_path" ]]
  [[ "${beagle_fields[cursor++]}" == "$firn_repo" ]]
  [[ "${beagle_fields[cursor++]}" == native-exe ]]
  [[ "${beagle_fields[cursor++]}" == --out ]]
  out="${beagle_fields[cursor++]}"
  stage="${out%/bin/firn}"
  [[ "$stage" == "$runtime_root"/.stage.* ]]
  [[ "${beagle_fields[cursor++]}" == --artifacts ]]
  [[ "${beagle_fields[cursor++]}" == "$stage/artifacts" ]]
  [[ "${beagle_fields[cursor++]}" == --entry ]]
  [[ "${beagle_fields[cursor++]}" == firn.main/-main ]]
  for source in "${sources[@]}"; do
    [[ "${beagle_fields[cursor++]}" == "$source" ]]
  done
done
[[ "$cursor" -eq "${#beagle_fields[@]}" ]]

mapfile -d '' -t runtime_fields <"$FAKE_RUNTIME_LOG"
cursor=0
expected_commands=(
  'repo validate'
  'repo validate all'
  'repo validate hosts/whiterabbit/configuration.bnix'
  'repo validate tag enable terminal'
  'host list all'
  'host list all'
)
for command in "${expected_commands[@]}"; do
  [[ "${runtime_fields[cursor++]}" == RUNTIME_CALL ]]
  [[ "${runtime_fields[cursor++]}" == "$beagle_path" ]]
  [[ "${runtime_fields[cursor++]}" == "$firn_repo" ]]
  read -r -a args <<<"$command"
  for arg in "${args[@]}"; do
    [[ "${runtime_fields[cursor++]}" == "$arg" ]]
  done
done
[[ "$cursor" -eq "${#runtime_fields[@]}" ]]
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

printf 'firn-runtime-launcher: PASS\n'
