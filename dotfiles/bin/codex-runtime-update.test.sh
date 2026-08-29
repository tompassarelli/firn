#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
updater="$repo/dotfiles/bin/codex-runtime-update"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/codex-runtime-update-test.XXXXXX")"
trap 'rm -rf -- "${scratch:?}"' EXIT

real_bun="$(command -v bun)"
test_home="$scratch/home"
test_bin="$scratch/bin"
call_log="$scratch/bun-calls"
node_called="$scratch/node-called"
npm_called="$scratch/npm-called"
mkdir -p "$test_home" "$test_bin"

case "$(uname -s):$(uname -m)" in
  Linux:x86_64)
    platform_package="codex-linux-x64"
    platform_version_suffix="linux-x64"
    target="x86_64-unknown-linux-musl"
    ;;
  Linux:aarch64|Linux:arm64)
    platform_package="codex-linux-arm64"
    platform_version_suffix="linux-arm64"
    target="aarch64-unknown-linux-musl"
    ;;
  *)
    printf 'codex-runtime-update tests: unsupported fixture platform\n' >&2
    exit 1
    ;;
esac

cat >"$test_bin/bun" <<'MOCK_BUN'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = -e ]; then
  exec "$CODEX_TEST_REAL_BUN" "$@"
fi
[ "${1:-}" = install ] || {
  printf 'unexpected Bun invocation: %s\n' "$*" >&2
  exit 1
}
printf '%s\n' "$*" >>"$CODEX_TEST_CALL_LOG"

cwd=""
spec=""
shift
while [ "$#" -gt 0 ]; do
  case "$1" in
    --cwd)
      shift
      cwd="${1:-}"
      ;;
    --cwd=*) cwd="${1#--cwd=}" ;;
    @openai/codex@*) spec="$1" ;;
  esac
  shift
done
[ -n "$cwd" ] && [ -n "$spec" ] || {
  echo 'mock Bun did not receive cwd and Codex package' >&2
  exit 1
}
version="${spec#@openai/codex@}"
package_root="$cwd/node_modules/@openai/codex"
platform_root="$cwd/node_modules/@openai/$CODEX_TEST_PLATFORM_PACKAGE"
native="$platform_root/vendor/$CODEX_TEST_TARGET/bin/codex"
mkdir -p "$package_root" "$(dirname "$native")"
printf '{"name":"@openai/codex","version":"%s"}\n' "$version" \
  >"$package_root/package.json"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  "printf '%s\\n' 'codex-cli $version'" \
  >"$native"
chmod +x "$native"
cat >"$cwd/bun.lock" <<LOCK
{
  "lockfileVersion": 1,
  "packages": {
    "@openai/codex": ["@openai/codex@$version", "", {}, "sha512-cGFja2FnZQ=="],
    "@openai/$CODEX_TEST_PLATFORM_PACKAGE": ["@openai/codex@$version-$CODEX_TEST_PLATFORM_VERSION_SUFFIX", "", {}, "sha512-cGxhdGZvcm0="],
  },
}
LOCK
MOCK_BUN

cat >"$test_bin/node" <<'NO_NODE'
#!/usr/bin/env bash
touch "$CODEX_TEST_NODE_CALLED"
exit 97
NO_NODE
cat >"$test_bin/npm" <<'NO_NPM'
#!/usr/bin/env bash
touch "$CODEX_TEST_NPM_CALLED"
exit 98
NO_NPM
chmod +x "$test_bin/bun" "$test_bin/node" "$test_bin/npm"

export CODEX_TEST_REAL_BUN="$real_bun"
export CODEX_TEST_CALL_LOG="$call_log"
export CODEX_TEST_NODE_CALLED="$node_called"
export CODEX_TEST_NPM_CALLED="$npm_called"
export CODEX_TEST_PLATFORM_PACKAGE="$platform_package"
export CODEX_TEST_PLATFORM_VERSION_SUFFIX="$platform_version_suffix"
export CODEX_TEST_TARGET="$target"

run_update() {
  HOME="$test_home" PATH="$test_bin:$PATH" "$updater" "$1"
}

bash -n "$updater"

output="$(run_update 0.151.0)"
root="$test_home/.local/lib/codex"
runtime_151="$root/versions/0.151.0"
[ "$(readlink "$root/current")" = 'versions/0.151.0' ]
[ "$($root/current/bin/codex --version)" = 'codex-cli 0.151.0' ]
grep -Fqx 'package=npm:@openai/codex@0.151.0' "$runtime_151/provenance"
grep -Fqx 'package_integrity=sha512-cGFja2FnZQ==' "$runtime_151/provenance"
grep -Fqx 'platform_package=npm:@openai/codex@0.151.0-'"$platform_version_suffix" \
  "$runtime_151/provenance"
grep -Fqx 'platform_integrity=sha512-cGxhdGZvcm0=' "$runtime_151/provenance"
grep -Fqx "binary_sha256=$(sha256sum "$runtime_151/bin/codex" | cut -d' ' -f1)" \
  "$runtime_151/provenance"
case "$output" in
  *'codex runtime active: codex-cli 0.151.0'*) ;;
  *) echo 'updater did not report the selected exact version' >&2; exit 1 ;;
esac

grep -Fq -- '--backend=copyfile' "$call_log"
grep -Fq -- '--exact' "$call_log"
grep -Fq -- '--ignore-scripts' "$call_log"
grep -Fq -- '--linker=hoisted' "$call_log"
grep -Fq -- '--save-text-lockfile' "$call_log"
grep -Fq -- '@openai/codex@0.151.0' "$call_log"

run_update 0.150.0 >/dev/null
[ "$(readlink "$root/current")" = 'versions/0.150.0' ]
[ -x "$runtime_151/bin/codex" ]
[ -x "$root/versions/0.150.0/bin/codex" ]

printf '%s\n' \
  '#!/usr/bin/env bash' \
  "printf '%s\\n' 'codex-cli 0.151.0'" \
  '# retained runtime tamper' \
  >"$runtime_151/node_modules/@openai/$platform_package/vendor/$target/bin/codex"
chmod +x "$runtime_151/bin/codex"
status=0
failure="$(run_update 0.151.0 2>&1)" || status=$?
[ "$status" -eq 1 ]
case "$failure" in
  *'existing runtime hash mismatch'*) ;;
  *) echo 'tampered retained runtime was not diagnosed by hash' >&2; exit 1 ;;
esac
[ "$(readlink "$root/current")" = 'versions/0.150.0' ]
[ -z "$(find "$root" -maxdepth 1 -name '.stage.*' -print -quit)" ]
[ ! -e "$node_called" ]
[ ! -e "$npm_called" ]

printf 'codex-runtime-update tests: PASS (Bun-only install, provenance, retention, rollback, atomic hash refusal)\n'
