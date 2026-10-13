#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-authoring-native.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'authoring-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'authoring-native: %s\n' "$*" >&2
  exit 1
}

if ! command -v galileo >/dev/null 2>&1; then
  export PATH="$PATH:${FIRN_RUNTIME_ROOT:-$HOME/.local/lib/firn/cli}/current/bin"
fi

for command in bash bun cmp find galileo git nix-instantiate rg timeout; do
  command -v "$command" >/dev/null 2>&1 \
    || die "missing command: $command"
done
core="$repo/native/authoring.ts"
pure="$repo/native/authoring_test.ts"
native="$repo/native/authoring_native.ts"
bridge="$repo/native/authoring_host.ts"

cat >"$scratch/authoring-test" <<EOF
#!/usr/bin/env bash
exec env FIRN_AUTHORING_TEST_MODULE='$pure' bun -e \
  'const m = await import(process.env.FIRN_AUTHORING_TEST_MODULE); process.exitCode = m.runScenarios();'
EOF
cat >"$scratch/authoring-native" <<EOF
#!/usr/bin/env bash
exec env FIRN_AUTHORING_MODULE='$native' bun '$bridge' "\$@"
EOF
chmod +x "$scratch/authoring-test" "$scratch/authoring-native"

printf 'authoring-native: argv and name-refusal scenarios\n' >&2
timeout --foreground 30 "$scratch/authoring-test" \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die "pure fixtures failed"
[[ ! -s "$scratch/pure.err" ]] || die "pure fixtures wrote stderr"

fixture="$scratch/repo"
fakebin="$scratch/fake-bin"
mkdir -p "$fixture/.firn-cache" "$fixture/secrets" "$fakebin"

cp "$here"/fixtures/beagle-*-openssh-schema.json "$fixture/.firn-cache/schema.json"
git init -q -b main "$fixture"
git -C "$fixture" config user.name authoring-test
git -C "$fixture" config user.email authoring-test@example.invalid

cat >"$fakebin/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == -d ]]; then
  [[ "$#" == 2 && -f "$2" ]]
  cat "$2"
  printf 'show-note\n' >&2
else
  [[ "$#" == 1 && -f "$1" ]]
  printf 'edited\n' >"$1"
  printf 'edited\n'
  printf 'edit-note\n' >&2
fi
exit "${FIRN_FAKE_SOPS_STATUS:-0}"
EOF
chmod +x "$fakebin/sops"

FIRN_AUTHORING_CORE="$core" FIRN_SCHEMA_CAPTURE="$fixture/.firn-cache/schema.json" bun - <<'JS'
import assert from 'node:assert/strict';
const core = await import(process.env.FIRN_AUTHORING_CORE);
const text = await Bun.file(process.env.FIRN_SCHEMA_CAPTURE).text();
const expected = JSON.parse(text);
const parsed = core.schemaEntriesFromJson(text);
assert.equal(parsed._tag, 'SchemaParsed');
assert.deepEqual(parsed.entries.map(row => [row.name,row.type]), expected.map(row => [row.name,row.t]));
const incomplete = {...expected[0]};
delete incomplete.t;
assert.equal(core.schemaEntriesFromJson(JSON.stringify([incomplete])).entries[0].type, '?');
JS

last_status=0
scenario_count=0
run_cli() {
  local name="$1" log="$2"
  shift 2
  scenario_count=$((scenario_count + 1))
  set +e
  timeout --foreground 30 env \
    PATH="$fakebin:$PATH" \
    FIRN_REPO="$fixture" \
    FIRN_FAKE_LOG="$log" \
    "$@" \
    >"$scratch/$name.out" 2>"$scratch/$name.err"
  last_status=$?
  set -e
  printf '%s\n' "$last_status" >"$scratch/$name.status"
}

expect_status() {
  local name="$1" expected="$2"
  [[ "$(<"$scratch/$name.status")" == "$expected" ]] \
    || die "$name returned $(<"$scratch/$name.status"), expected $expected"
}

expect_empty() {
  local path_to_check="$1" label="$2"
  [[ ! -s "$path_to_check" ]] || die "$label was not empty"
}

assert_file() {
  local actual="$1" expected="$2" label="$3"
  if ! cmp -s "$expected" "$actual"; then
    diff -u "$expected" "$actual" >&2 || true
    die "$label changed"
  fi
}

printf 'authoring-native: controlled authoring effects\n' >&2

module_log="$scratch/module.log"
run_cli module "$module_log" \
  "$scratch/authoring-native" module add sample-tool
expect_status module 0
expect_empty "$scratch/module.err" "module stderr"
git -C "$fixture" ls-files --error-unmatch modules/sample-tool/default.gal >/dev/null
index_before=$(git -C "$fixture" ls-files --stage)

module_hash="$(sha256sum "$fixture/modules/sample-tool/default.gal")"
run_cli module-again "$module_log" \
  "$scratch/authoring-native" module add sample-tool
expect_status module-again 1
expect_empty "$scratch/module-again.out" "repeat module stdout"
[[ "$(sha256sum "$fixture/modules/sample-tool/default.gal")" == \
   "$module_hash" ]] || die "repeat module changed existing bytes"
[[ "$(git -C "$fixture" ls-files --stage)" == "$index_before" ]] \
  || die "repeat module changed the index"

service_log="$scratch/service.log"
run_cli service "$service_log" \
  "$scratch/authoring-native" template service openssh
expect_status service 0
expect_empty "$scratch/service.err" "service stderr"
for template in submodule home; do
  name="sample-$template"
  log="$scratch/$template.log"
  run_cli "$template" "$log" \
    "$scratch/authoring-native" template "$template" "$name"
  expect_status "$template" 0
  expect_empty "$scratch/$template.err" "$template stderr"
  git -C "$fixture" ls-files --error-unmatch "modules/$name/default.gal" >/dev/null
done

host_log="$scratch/host.log"
run_cli host "$host_log" \
  "$scratch/authoring-native" template host sample-host
expect_status host 0
expect_empty "$scratch/host.err" "host stderr"
git -C "$fixture" ls-files --error-unmatch \
  hosts/sample-host/configuration.gal hosts/sample-host/enabled-tags.gal >/dev/null
index_before=$(git -C "$fixture" ls-files --stage)

mkdir -p "$fixture/hosts/collision-host"
printf '%s\n' 'preserve' \
  >"$fixture/hosts/collision-host/enabled-tags.gal"
collision_log="$scratch/collision.log"
run_cli collision "$collision_log" \
  "$scratch/authoring-native" template host collision-host
expect_status collision 1
expect_empty "$scratch/collision.out" "collision stdout"
[[ ! -e "$fixture/hosts/collision-host/configuration.gal" ]] \
  || die "host collision created the earlier target"
[[ "$(git -C "$fixture" ls-files --stage)" == "$index_before" ]] || die "host collision changed the index"
[[ "$(<"$fixture/hosts/collision-host/enabled-tags.gal")" == preserve ]] \
  || die "host collision changed the existing target"

invalid_log="$scratch/invalid-name.log"
run_cli invalid-name "$invalid_log" \
  "$scratch/authoring-native" module add ../escape
expect_status invalid-name 1
expect_empty "$scratch/invalid-name.out" "invalid name stdout"
[[ "$(git -C "$fixture" ls-files --stage)" == "$index_before" ]] || die "invalid name changed the index"
[[ ! -e "$scratch/escape" ]] || die "invalid name escaped the repository"

: >"$fixture/.git/index.lock"
run_cli git-failure "$scratch/git-failure.log" \
  "$scratch/authoring-native" template home git-failure
expect_status git-failure 128
expect_empty "$scratch/git-failure.out" "failed git success output"
[[ -f "$fixture/modules/git-failure/default.gal" ]] || die "git failure lost authored file"
[[ "$(git -C "$fixture" ls-files --stage)" == "$index_before" ]] || die "failed staging changed the index"
rm "$fixture/.git/index.lock"

printf 'authoring-native: Galileo check/build and intended Nix semantics\n' >&2
(
  cd "$fixture"
  galileo check modules hosts/sample-host >"$scratch/galileo-check.out" 2>"$scratch/galileo-check.err"
  galileo build --check --layout idiomatic modules hosts/sample-host >"$scratch/galileo-build.out" 2>"$scratch/galileo-build.err"
) || die "authored Galileo source or generated Nix failed"
for module_kind in sample-tool openssh sample-submodule sample-home; do
  [[ -f "$fixture/modules/$module_kind/default.nix" ]] \
    || die "$module_kind did not generate Nix"
done
[[ -f "$fixture/hosts/sample-host/configuration.nix" ]] \
  || die "host did not generate Nix"
[[ ! -e "$fixture/hosts/sample-host/enabled-tags.nix" ]] \
  || die "host facts generated an unintended Nix file"

check_nix() {
  local relative="$1" enabled="$2" expected="$3"
  local expression
  expression="$(cat <<EOF
let
  actual = import $fixture/$relative {
    config.myConfig.modules = {
      sample-tool.enable = $enabled;
      openssh.enable = $enabled;
      sample-submodule.enable = $enabled;
      sample-home.enable = $enabled;
      users.username = "tester";
    };
    lib = {
      mkEnableOption = description: { inherit description; };
      mkOption = value: value;
      mkIf = condition: value: if condition then value else {};
      types.lines = "lines";
    };
    pkgs = {
      sample-tool = "sample-tool-package";
      sample-submodule = "sample-submodule-package";
    };
  };
in actual.config == ($expected)
EOF
)"
  [[ "$(nix-instantiate --eval --strict --expr "$expression")" == true ]] \
    || die "$relative emitted unexpected Nix for enable=$enabled"
}

for enabled in true false; do
  package_config='{}'
  submodule_config='{}'
  service_config='{}'
  home_config='{}'
  if [[ "$enabled" == true ]]; then
    package_config='{environment.systemPackages = ["sample-tool-package"];}'
    submodule_config='{environment.systemPackages = ["sample-submodule-package"];}'
    service_config='{services.openssh.enable = true;}'
    home_config='{home-manager.users.tester.programs.sample-home.enable = true;}'
  fi
  check_nix modules/sample-tool/default.nix "$enabled" "$package_config"
  check_nix modules/openssh/default.nix "$enabled" "$service_config"
  check_nix modules/sample-submodule/default.nix "$enabled" "$submodule_config"
  check_nix modules/sample-home/default.nix "$enabled" "$home_config"
done
(
  cd "$fixture"
  galileo query modules hosts/sample-host 'all ?m where ?m is enabled on sample-host' --json
) >"$scratch/host-enabled.json" || die "host enabled query failed"
for module_name in boot networking users; do
  rg -q "\"$module_name\"" "$scratch/host-enabled.json" || die "sample-host does not enable $module_name"
done
[[ "$(rg -c 'modules\.(boot|networking|users)\.enable = true;' "$fixture/hosts/sample-host/configuration.nix")" == 3 ]] \
  || die "host configuration does not set its three direct enables"
check_nix hosts/sample-host/configuration.nix true \
  '{myConfig.modules = {system.stateVersion = "25.11"; users.username = "you"; users.enable = true; boot.enable = true; networking.enable = true;};}'
[[ "$(nix-instantiate --eval --strict --expr "let m = import $fixture/hosts/sample-host/configuration.nix {config = {}; lib = {}; pkgs = {};}; in map toString m.imports")" == \
   "[ \"$fixture/hosts/sample-host/_generated-enables.nix\" ]" ]] \
  || die "host imports changed"

printf 'authoring-native: inherited sops streams and real staging\n' >&2
printf 'shown\n' >"$fixture/secrets/alpha.yaml"
: >"$fixture/secrets/zeta.yaml"
: >"$fixture/secrets/.yaml"
: >"$fixture/secrets/...yaml"
: >"$fixture/secrets/note.txt"
mkdir -p "$fixture/secrets/nested.yaml"
ln -s alpha.yaml "$fixture/secrets/linked.yaml"
git -C "$fixture" add -- secrets/alpha.yaml
git -C "$fixture" commit -qm 'authoring fixture'

run_cli secret-list "$scratch/list.log" "$scratch/authoring-native" secret list
expect_status secret-list 0
printf '%s\n' alpha zeta >"$scratch/secret-list.expected.out"
assert_file "$scratch/secret-list.out" "$scratch/secret-list.expected.out" "secret names"
expect_empty "$scratch/secret-list.err" "secret list stderr"

run_cli show "$scratch/show.log" "$scratch/authoring-native" secret show alpha
expect_status show 0
assert_file "$scratch/show.out" "$fixture/secrets/alpha.yaml" "decrypted stream"
printf 'show-note\n' >"$scratch/show.expected.err"
assert_file "$scratch/show.err" "$scratch/show.expected.err" "inherited stderr"
run_cli show-failure "$scratch/show-failure.log" env FIRN_FAKE_SOPS_STATUS=23 \
  "$scratch/authoring-native" secret show alpha
expect_status show-failure 23
assert_file "$scratch/show-failure.out" "$scratch/show.out" "failed show stdout"
assert_file "$scratch/show-failure.err" "$scratch/show.err" "failed show stderr"

run_cli edit "$scratch/edit.log" "$scratch/authoring-native" secret edit alpha
expect_status edit 0
[[ "$(git -C "$fixture" show :secrets/alpha.yaml)" == edited ]] || die "edited secret was not staged"
printf 'edit-note\n' >"$scratch/edit.expected.err"
assert_file "$scratch/edit.err" "$scratch/edit.expected.err" "edit inherited stderr"
git -C "$fixture" reset -q -- secrets/alpha.yaml
git -C "$fixture" checkout -- secrets/alpha.yaml
run_cli edit-sops-failure "$scratch/edit-failure.log" env FIRN_FAKE_SOPS_STATUS=37 \
  "$scratch/authoring-native" secret edit alpha
expect_status edit-sops-failure 37
[[ -z "$(git -C "$fixture" diff --cached --name-only)" ]] || die "failed sops edit was staged"
assert_file "$scratch/edit-sops-failure.out" "$fixture/secrets/alpha.yaml" "failed edit stdout"
assert_file "$scratch/edit-sops-failure.err" "$scratch/edit.err" "failed edit stderr"
: >"$fixture/.git/index.lock"
run_cli edit-git-failure "$scratch/edit-git-failure.log" "$scratch/authoring-native" secret edit alpha
expect_status edit-git-failure 128
[[ -z "$(git -C "$fixture" diff --cached --name-only)" ]] || die "failed git edit changed index"
assert_file "$scratch/edit-git-failure.out" "$fixture/secrets/alpha.yaml" "git-failed edit stdout"
rm "$fixture/.git/index.lock"

for secret_case in missing nested linked ../alpha; do
  run_cli refusal "$scratch/refusal.log" "$scratch/authoring-native" secret edit "$secret_case"
  expect_status refusal 1
  expect_empty "$scratch/refusal.out" "refused secret stdout"
done
[[ "$(git -C "$fixture" show HEAD:secrets/alpha.yaml)" == shown ]] || die "secret refusal changed committed data"
run_cli usage "$scratch/usage.log" "$scratch/authoring-native" host gen whiterabbit
expect_status usage 64
expect_empty "$scratch/usage.out" "usage stdout"

printf 'ok: authoring scenarios=%s with real Git and Galileo/Nix checks\n' "$scenario_count"
