#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
runtime=$here/north-coord-runtime
scratch=$(mktemp -d)
trap 'rm -rf "${scratch:?}"' EXIT

state=$scratch/state
repo=$scratch/fram
package=$scratch/package
log=$scratch/coordination.log
mkdir -p "$repo/bin" "$package/bin"

git -C "$repo" init -q
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name runtime-test

write_daemon() {
  local path=$1 label=$2
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "printf 'label=$label\\n'" \
    "printf 'mode=%s\\n' \"\$NORTH_FRAM_RUNTIME\"" \
    "printf 'source=%s\\n' \"\$FRAM_RUNTIME_SOURCE\"" \
    "printf 'revision=%s\\n' \"\$FRAM_RUNTIME_REV\"" \
    "printf 'home=%s\\n' \"\$FRAM_HOME\"" \
    "printf 'bin=%s\\n' \"\$FRAM_BIN\"" \
    "printf 'args=%s|%s\\n' \"\$1\" \"\$2\"" \
    >"$path"
  chmod +x "$path"
}

write_daemon "$repo/bin/fram-daemon" checkout
printf 'one\n' >"$repo/revision.txt"
git -C "$repo" add bin/fram-daemon revision.txt
git -C "$repo" commit -qm one
revision_one=$(git -C "$repo" rev-parse HEAD)

printf 'two\n' >"$repo/revision.txt"
git -C "$repo" commit -qam two
revision_two=$(git -C "$repo" rev-parse HEAD)

write_daemon "$package/bin/fram-daemon" package
package_revision=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

run_runtime() {
  NORTH_COORD_RUNTIME_STATE=$state \
  NORTH_COORD_FRAM_PACKAGE=$package \
  NORTH_COORD_FRAM_PACKAGE_REV=$package_revision \
  NORTH_COORD_FRAM_CHECKOUT=$repo \
  NORTH_COORD_FRAM_LOG=$log \
    "$runtime" "$@"
}

# A fresh generation initializes the stable selector to its explicit package.
fresh_status=$(run_runtime status)
grep -Fxq 'mode=package' <<<"$fresh_status"
grep -Fxq "source=$package" <<<"$fresh_status"
grep -Fxq "revision=$package_revision" <<<"$fresh_status"
[[ -L "$state/current" ]]
[[ $(readlink -f "$state/current") == "$package" ]]

# Promotion materializes and selects an exact detached revision, never the
# caller's mutable worktree.
run_runtime promote "$repo" "$revision_one" >/dev/null
deployment_one=$state/deployments/$revision_one
[[ -d "$deployment_one" ]]
[[ $(readlink -f "$state/current") == "$deployment_one" ]]
[[ $(git -C "$deployment_one" rev-parse HEAD) == "$revision_one" ]]

checkout_start=$(run_runtime start)
grep -Fxq 'label=checkout' <<<"$checkout_start"
grep -Fxq 'mode=checkout' <<<"$checkout_start"
grep -Fxq "source=$deployment_one" <<<"$checkout_start"
grep -Fxq "revision=$revision_one" <<<"$checkout_start"
grep -Fxq "home=$state/current" <<<"$checkout_start"
grep -Fxq "bin=$state/current/bin" <<<"$checkout_start"
grep -Fxq "args=7977|$log" <<<"$checkout_start"

# A failed promotion cannot move the active selector.
before_failed_promote=$(readlink -f "$state/current")
if run_runtime promote "$repo" does-not-exist >/dev/null 2>&1; then
  printf 'invalid revision was promoted\n' >&2
  exit 1
fi
[[ $(readlink -f "$state/current") == "$before_failed_promote" ]]

# Tracked drift in a deployment is fatal; there is no silent package fallback.
printf 'drift\n' >"$deployment_one/revision.txt"
if run_runtime start >/dev/null 2>&1; then
  printf 'dirty deployment was started\n' >&2
  exit 1
fi
git -C "$deployment_one" restore revision.txt

# The current and previous selectors permit exact, reversible promotion.
run_runtime promote "$repo" "$revision_two" >/dev/null
deployment_two=$state/deployments/$revision_two
[[ $(readlink -f "$state/current") == "$deployment_two" ]]
[[ $(readlink -f "$state/previous") == "$deployment_one" ]]
run_runtime rollback >/dev/null
[[ $(readlink -f "$state/current") == "$deployment_one" ]]
[[ $(readlink -f "$state/previous") == "$deployment_two" ]]

# Package mode is an explicit selection and exports its exact package identity.
run_runtime package >/dev/null
[[ $(readlink -f "$state/current") == "$package" ]]
[[ $(readlink -f "$state/previous") == "$deployment_one" ]]
package_start=$(run_runtime start)
grep -Fxq 'label=package' <<<"$package_start"
grep -Fxq 'mode=package' <<<"$package_start"
grep -Fxq "source=$package" <<<"$package_start"
grep -Fxq "revision=$package_revision" <<<"$package_start"

# Selectors outside the managed package/deployment roots fail closed.
outside=$scratch/outside
mkdir -p "$outside"
unlink "$state/current"
ln -s "$outside" "$state/current"
if run_runtime status >/dev/null 2>&1; then
  printf 'external selector target was accepted\n' >&2
  exit 1
fi

printf 'ok: north-coord runtime promotion is exact, atomic, reversible, identity-bearing, and fail-closed\n'
