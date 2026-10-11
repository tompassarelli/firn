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
    printf 'authoring-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
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

for command in bash bun cmp find galileo git nix-instantiate rg timeout; do
  command -v "$command" >/dev/null 2>&1 \
    || die "missing command: $command"
done
[[ -x "$beagle/bin/beagle-build-all" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

json="$beagle/native-core/src/native/json.bjs"
core="$repo/native/authoring.bjs"
pure="$repo/native/authoring_test.bjs"
native="$repo/native/authoring_native.bjs"
bridge="$repo/native/authoring_host.mjs"

printf 'authoring-js: building one closed typed family graph\n' >&2
mkdir -p "$scratch/build"
timeout --foreground 120 "$beagle/bin/beagle-build-all" \
  "$json" "$core" "$pure" "$native" --out "$scratch/build" \
  >"$scratch/build.out" 2>"$scratch/build.err" \
  || {
    sed -n '1,240p' "$scratch/build.err" >&2
    die "closed JS family build failed"
  }
pure_js="$(find "$scratch/build" -name authoring-test.js -print -quit)"
native_js="$(find "$scratch/build" -name authoring-native.js -print -quit)"
[[ -n "$pure_js" && -f "$pure_js" ]] || die "pure test module was not emitted"
[[ -n "$native_js" && -f "$native_js" ]] || die "authoring module was not emitted"
mkdir -p "$scratch/build/node_modules/beagle"
cp -- "$beagle/beagle-lib/lib/beagle/core.js" \
  "$scratch/build/node_modules/beagle/core.js"
printf '%s\n' '{"name":"beagle","type":"module"}' \
  >"$scratch/build/node_modules/beagle/package.json"

cat >"$scratch/authoring-test" <<EOF
#!/usr/bin/env bash
exec env FIRN_AUTHORING_TEST_MODULE='$pure_js' bun -e \
  'const m = await import(process.env.FIRN_AUTHORING_TEST_MODULE); process.exitCode = m["run-tests"]();'
EOF
cat >"$scratch/authoring-native" <<EOF
#!/usr/bin/env bash
exec env FIRN_AUTHORING_MODULE='$native_js' bun '$bridge' "\$@"
EOF
chmod +x "$scratch/authoring-test" "$scratch/authoring-native"

printf 'authoring-native: pure renderer, schema, argv, and refusal fixtures\n' >&2
timeout --foreground 30 "$scratch/authoring-test" \
  >"$scratch/pure.out" 2>"$scratch/pure.err" \
  || die "pure fixtures failed"
[[ ! -s "$scratch/pure.err" ]] || die "pure fixtures wrote stderr"

fixture="$scratch/repo"
fakebin="$scratch/fake-bin"
mkdir -p "$fixture/.beagle-cache" "$fixture/secrets" "$fakebin"

cat >"$fixture/.beagle-cache/schema.json" <<'EOF'
[
  {"name":"services.openssh.generateHostKeys","t":"bool"},
  {"name":"services.openssh.enable","t":"bool"},
  {"name":"services.openssh.authorizedKeysInHomedir","t":"bool"},
  {"name":"services.openssh.nested.value","t":"str"},
  {"name":"services.openssh.allowSFTP","t":"bool"},
  {"name":"services.openssh.package","t":"package"},
  {"name":"services.openssh.authorizedKeysCommandUser","t":"str"},
  {"name":"services.openssh.extraConfig","t":"separatedString"},
  {"name":"services.openssh.authorizedKeysFiles","t":"listOf"},
  {"name":"services.openssh.enableRecommendedAlgorithms","t":"bool"},
  {"name":"services.openssh.authorizedKeysCommand","t":"str"},
  {"inner":{"t":"submodule"},"name":"services.openssh.settings","t":"attrsOf"},
  {"p":"services.openssh.stale","name":"services.openssh.z-last","t":"str"}
]
EOF

cat >"$fakebin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'git'
  for argument in "$@"; do
    printf '\t<%s>' "$argument"
  done
  printf '\n'
} >>"${FIRN_FAKE_LOG:?}"
exit "${FIRN_FAKE_GIT_STATUS:-0}"
EOF

cat >"$fakebin/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'sops'
  for argument in "$@"; do
    printf '\t<%s>' "$argument"
  done
  printf '\n'
} >>"${FIRN_FAKE_LOG:?}"
if [[ "${1:-}" == "-d" ]]; then
  printf 'shown\n'
  printf 'show-note\n' >&2
else
  printf 'edited\n'
  printf 'edit-note\n' >&2
fi
exit "${FIRN_FAKE_SOPS_STATUS:-0}"
EOF
chmod +x "$fakebin/git" "$fakebin/sops"

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
printf 'git\t<-C>\t<%s>\t<add>\t<-->\t<%s>\n' \
  "$fixture" "$fixture/modules/sample-tool/default.gal" \
  >"$scratch/module.expected.log"
assert_file "$module_log" "$scratch/module.expected.log" "module git argv"

module_hash="$(sha256sum "$fixture/modules/sample-tool/default.gal")"
module_log_bytes="$(wc -c <"$module_log")"
run_cli module-again "$module_log" \
  "$scratch/authoring-native" module add sample-tool
expect_status module-again 1
expect_empty "$scratch/module-again.out" "repeat module stdout"
[[ "$(sha256sum "$fixture/modules/sample-tool/default.gal")" == \
   "$module_hash" ]] || die "repeat module changed existing bytes"
[[ "$(wc -c <"$module_log")" == "$module_log_bytes" ]] \
  || die "repeat module invoked git"

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
  rg -Fx "$name is a Module" "$fixture/modules/$name/default.gal" >/dev/null \
    || die "$template did not emit its module fact"
done
rg -F 'sample-submodule configuration' \
  "$fixture/modules/sample-submodule/default.gal" >/dev/null \
  || die "submodule kept a literal formatter placeholder"
if rg -F '~a' "$fixture/modules/sample-submodule/default.gal" >/dev/null; then
  die "submodule emitted a literal formatter placeholder"
fi

host_log="$scratch/host.log"
run_cli host "$host_log" \
  "$scratch/authoring-native" template host sample-host
expect_status host 0
expect_empty "$scratch/host.err" "host stderr"
printf 'git\t<-C>\t<%s>\t<add>\t<-->\t<%s>\t<%s>\n' \
  "$fixture" \
  "$fixture/hosts/sample-host/configuration.gal" \
  "$fixture/hosts/sample-host/enabled-tags.gal" \
  >"$scratch/host.expected.log"
assert_file "$host_log" "$scratch/host.expected.log" "host git argv"

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
[[ ! -e "$collision_log" ]] || die "host collision invoked git"
[[ "$(<"$fixture/hosts/collision-host/enabled-tags.gal")" == preserve ]] \
  || die "host collision changed the existing target"

invalid_log="$scratch/invalid-name.log"
run_cli invalid-name "$invalid_log" \
  "$scratch/authoring-native" module add ../escape
expect_status invalid-name 1
expect_empty "$scratch/invalid-name.out" "invalid name stdout"
[[ ! -e "$invalid_log" ]] || die "invalid authoring name invoked git"

git_failure_log="$scratch/git-failure.log"
run_cli git-failure "$git_failure_log" \
  env FIRN_FAKE_GIT_STATUS=29 \
  "$scratch/authoring-native" template home git-failure
expect_status git-failure 29
expect_empty "$scratch/git-failure.out" "failed git success output"
expect_empty "$scratch/git-failure.err" "failed git stderr"
[[ -f "$fixture/modules/git-failure/default.gal" ]] \
  || die "git failure lost the complete authored file"
printf 'git\t<-C>\t<%s>\t<add>\t<-->\t<%s>\n' \
  "$fixture" "$fixture/modules/git-failure/default.gal" \
  >"$scratch/git-failure.expected.log"
assert_file "$git_failure_log" "$scratch/git-failure.expected.log" \
  "failed git argv"

printf 'authoring-native: Galileo check/build and intended Nix semantics\n' >&2
(
  cd "$fixture"
  galileo check modules hosts/sample-host >"$scratch/galileo-check.out" 2>"$scratch/galileo-check.err"
  galileo build --check modules hosts/sample-host >"$scratch/galileo-build.out" 2>"$scratch/galileo-build.err"
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
in builtins.removeAttrs actual ["imports"] == ($expected)
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
  check_nix modules/sample-tool/default.nix "$enabled" \
    "{options.myConfig.modules.sample-tool.enable.description = \"Enable sample-tool\"; config = $package_config;}"
  check_nix modules/openssh/default.nix "$enabled" \
    "{options.myConfig.modules.openssh.enable.description = \"openssh service\"; config = $service_config;}"
  check_nix modules/sample-submodule/default.nix "$enabled" \
    "{options.myConfig.modules.sample-submodule = {enable.description = \"sample-submodule configuration\"; extraConfig = {type = \"lines\"; default = \"\"; description = \"Extra config text.\";};}; config = $submodule_config;}"
  check_nix modules/sample-home/default.nix "$enabled" \
    "{options.myConfig.modules.sample-home.enable.description = \"sample-home (home-manager)\"; config = $home_config;}"
done
check_nix hosts/sample-host/configuration.nix true \
  '{config.myConfig.modules = {system.stateVersion = "25.11"; users.username = "you"; users.enable = true; boot.enable = true; networking.enable = true;};}'
[[ "$(nix-instantiate --eval --strict --expr "let m = import $fixture/hosts/sample-host/configuration.nix {config = {}; lib = {}; pkgs = {};}; in map toString m.imports")" == \
   "[ \"$fixture/hosts/sample-host/_generated-enables.nix\" ]" ]] \
  || die "host imports changed"

printf 'authoring-native: controlled inherited secret effects\n' >&2

: >"$fixture/secrets/alpha.yaml"
: >"$fixture/secrets/zeta.yaml"
: >"$fixture/secrets/.yaml"
: >"$fixture/secrets/...yaml"
: >"$fixture/secrets/note.txt"
mkdir -p "$fixture/secrets/nested.yaml"
ln -s alpha.yaml "$fixture/secrets/linked.yaml"

list_log="$scratch/secret-list.log"
run_cli secret-list "$list_log" \
  "$scratch/authoring-native" secret list
expect_status secret-list 0
printf '%s\n' alpha zeta >"$scratch/secret-list.expected.out"
assert_file "$scratch/secret-list.out" "$scratch/secret-list.expected.out" \
  "secret list stdout"
expect_empty "$scratch/secret-list.err" "secret list stderr"
[[ ! -e "$list_log" ]] || die "secret list spawned a child"

show_log="$scratch/show.log"
run_cli show "$show_log" \
  "$scratch/authoring-native" secret show alpha
expect_status show 0
printf '%s\n' shown >"$scratch/show.expected.out"
printf '%s\n' show-note >"$scratch/show.expected.err"
assert_file "$scratch/show.out" "$scratch/show.expected.out" \
  "secret show inherited stdout"
assert_file "$scratch/show.err" "$scratch/show.expected.err" \
  "secret show inherited stderr"
printf 'sops\t<-d>\t<%s>\n' "$fixture/secrets/alpha.yaml" \
  >"$scratch/show.expected.log"
assert_file "$show_log" "$scratch/show.expected.log" "secret show argv"

show_failure_log="$scratch/show-failure.log"
run_cli show-failure "$show_failure_log" \
  env FIRN_FAKE_SOPS_STATUS=23 \
  "$scratch/authoring-native" secret show alpha
expect_status show-failure 23
assert_file "$scratch/show-failure.out" "$scratch/show.expected.out" \
  "failed show inherited stdout"
assert_file "$scratch/show-failure.err" "$scratch/show.expected.err" \
  "failed show inherited stderr"
assert_file "$show_failure_log" "$scratch/show.expected.log" \
  "failed show argv"

edit_log="$scratch/edit.log"
run_cli edit "$edit_log" \
  "$scratch/authoring-native" secret edit alpha
expect_status edit 0
printf '%s\n' edited 'secrets/alpha.yaml (git added)' \
  >"$scratch/edit.expected.out"
printf '%s\n' edit-note >"$scratch/edit.expected.err"
assert_file "$scratch/edit.out" "$scratch/edit.expected.out" \
  "secret edit stdout"
assert_file "$scratch/edit.err" "$scratch/edit.expected.err" \
  "secret edit stderr"
{
  printf 'sops\t<%s>\n' "$fixture/secrets/alpha.yaml"
  printf 'git\t<-C>\t<%s>\t<add>\t<-->\t<%s>\n' \
    "$fixture" "$fixture/secrets/alpha.yaml"
} >"$scratch/edit.expected.log"
assert_file "$edit_log" "$scratch/edit.expected.log" "secret edit argv"

edit_sops_failure_log="$scratch/edit-sops-failure.log"
run_cli edit-sops-failure "$edit_sops_failure_log" \
  env FIRN_FAKE_SOPS_STATUS=37 \
  "$scratch/authoring-native" secret edit alpha
expect_status edit-sops-failure 37
printf '%s\n' edited >"$scratch/edit-sops-failure.expected.out"
assert_file "$scratch/edit-sops-failure.out" \
  "$scratch/edit-sops-failure.expected.out" \
  "failed edit inherited stdout"
assert_file "$scratch/edit-sops-failure.err" "$scratch/edit.expected.err" \
  "failed edit inherited stderr"
printf 'sops\t<%s>\n' "$fixture/secrets/alpha.yaml" \
  >"$scratch/edit-sops-failure.expected.log"
assert_file "$edit_sops_failure_log" \
  "$scratch/edit-sops-failure.expected.log" \
  "failed edit spawned git"

edit_git_failure_log="$scratch/edit-git-failure.log"
run_cli edit-git-failure "$edit_git_failure_log" \
  env FIRN_FAKE_GIT_STATUS=29 \
  "$scratch/authoring-native" secret edit alpha
expect_status edit-git-failure 29
assert_file "$scratch/edit-git-failure.out" \
  "$scratch/edit-sops-failure.expected.out" \
  "git-failed edit success output"
assert_file "$scratch/edit-git-failure.err" "$scratch/edit.expected.err" \
  "git-failed edit inherited stderr"
assert_file "$edit_git_failure_log" "$scratch/edit.expected.log" \
  "git-failed edit argv"

for secret_case in missing nested linked; do
  case "$secret_case" in
    missing) secret_name=missing ;;
    nested) secret_name=nested ;;
    linked) secret_name=linked ;;
  esac
  secret_log="$scratch/$secret_case.log"
  run_cli "$secret_case" "$secret_log" \
    "$scratch/authoring-native" secret show "$secret_name"
  expect_status "$secret_case" 1
  expect_empty "$scratch/$secret_case.out" "$secret_case stdout"
  [[ ! -e "$secret_log" ]] || die "$secret_case spawned a child"
done

invalid_secret_log="$scratch/invalid-secret.log"
run_cli invalid-secret "$invalid_secret_log" \
  "$scratch/authoring-native" secret edit ../alpha
expect_status invalid-secret 1
expect_empty "$scratch/invalid-secret.out" "invalid secret stdout"
[[ ! -e "$invalid_secret_log" ]] \
  || die "invalid secret name spawned a child"

usage_log="$scratch/usage.log"
run_cli usage "$usage_log" \
  "$scratch/authoring-native" host gen whiterabbit
expect_status usage 64
expect_empty "$scratch/usage.out" "usage stdout"
[[ ! -e "$usage_log" ]] || die "usage error spawned a child"

printf 'ok: authoring effect scenarios=%s and Galileo/Nix semantic checks pass\n' "$scenario_count"
