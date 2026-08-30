#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
launcher="$repo/modules/north-store/north-store-launch"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/north-store-launch-test.XXXXXX")
trap 'rm -rf "${scratch:?}"' EXIT

release="$scratch/release"
artifact="$scratch/artifact"
selection="$scratch/beagle-store.env.next"
invoked="$scratch/invoked"
mkdir -p "$release/bin" "$artifact/bin"

cat >"$release/bin/beagle-store-server" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${NORTH_STORE_TEST_INVOKED:?}"
EOF
chmod +x "$release/bin/beagle-store-server"
printf 'sealed native server\n' >"$artifact/bin/beagle-store-server-native"
chmod +x "$artifact/bin/beagle-store-server-native"

closure=$(printf 'a%.0s' {1..64})
server_sha256=$(sha256sum "$artifact/bin/beagle-store-server-native")
server_sha256=${server_sha256%% *}
printf 'beagle-store-native-build/v1 %s\n' "$closure" >"$artifact/READY"

write_receipt() {
  local format=${1:-north-store-release/v2}
  local protocol=${2:-STORERPC/2.0}
  local created=${3-2026-08-23T00:00:00Z}
  {
    printf 'format=%s\n' "$format"
    printf 'protocol=%s\n' "$protocol"
    printf 'source=%s\n' "$repo"
    printf 'revision=%s\n' "$(printf 'b%.0s' {1..40})"
    printf 'tree=%s\n' "$(printf 'c%.0s' {1..40})"
    printf 'native_artifact_dir=%s\n' "$artifact"
    printf 'native_closure_sha256=%s\n' "$closure"
    printf 'server_artifact_sha256=%s\n' "$server_sha256"
    printf 'created=%s\n' "$created"
  } >"$release/RELEASE"
}

write_selection() {
  local selected_artifact=${1:-$artifact}
  local omitted_key=${2-}
  local selected_closure=${3:-$closure}
  local selected_server_sha256=${4:-$server_sha256}
  write_selection_value() {
    local key=$1
    local value=$2
    [ "$key" = "$omitted_key" ] || printf "export %s='%s'\n" "$key" "$value"
  }
  {
    write_selection_value BEAGLE_STORE_HOME "$release"
    write_selection_value BEAGLE_STORE_SERVER_RUNTIME native
    write_selection_value BEAGLE_STORE_NATIVE_ARTIFACT_DIR "$selected_artifact"
    write_selection_value BEAGLE_STORE_NATIVE_CLOSURE_SHA256 "$selected_closure"
    write_selection_value BEAGLE_STORE_SERVER_ARTIFACT "$selected_artifact/bin/beagle-store-server-native"
    write_selection_value BEAGLE_STORE_SERVER_ARTIFACT_SHA256 "$selected_server_sha256"
    write_selection_value BEAGLE_STORE_SERVER_PORT 7977
    write_selection_value BEAGLE_STORE_SPACE_ID north-coordination
    write_selection_value BEAGLE_STORE_LOG "$scratch/coordination.storelog"
    write_selection_value NORTH_STORE_TEST_INVOKED "$invoked"
  } >"$selection"
}

expect_refused() {
  if bash "$launcher" --validate-only "$selection" >"$scratch/stdout" 2>"$scratch/stderr"; then
    echo "north-store launcher accepted an incompatible selection" >&2
    exit 1
  fi
  [ ! -e "$invoked" ]
}

write_receipt
write_selection
bash -n "$launcher"
bash "$launcher" --validate-only "$selection" | grep -Fq 'compatible STORERPC/2.0 selection'
[ ! -e "$invoked" ]

NORTH_STORE_SELECTION="$selection" bash "$launcher"
[ "$(<"$invoked")" = 7977 ]
rm "$invoked"

# The currently selected producer still emits v1, so this barrier must remain
# inactive until the producer and consumer cut over together.
write_receipt north-store-release/v1 STORERPC/2.0
expect_refused
write_receipt north-store-release/v2 FRAMRPC/2.0
expect_refused
write_receipt north-store-release/v2 STORERPC/2.0 ''
expect_refused

write_receipt
printf 'extra=value\n' >>"$release/RELEASE"
expect_refused

write_receipt
write_selection "$scratch/other-artifact"
expect_refused

write_selection
export BEAGLE_STORE_LOG="$scratch/inherited.storelog"
write_selection "$artifact" BEAGLE_STORE_LOG
expect_refused
unset BEAGLE_STORE_LOG

write_selection "$artifact" "" "$(printf 'd%.0s' {1..64})"
expect_refused

write_selection "$artifact" "" "$closure" "$(printf 'e%.0s' {1..64})"
expect_refused

write_selection
printf 'malformed READY\n' >"$artifact/READY"
expect_refused

printf 'beagle-store-native-build/v1 %s\n' "$closure" >"$artifact/READY"
rm "$artifact/READY"
expect_refused

printf 'beagle-store-native-build/v1 %s\n' "$closure" >"$artifact/READY"
chmod -x "$artifact/bin/beagle-store-server-native"
expect_refused

chmod +x "$artifact/bin/beagle-store-server-native"
printf 'tampered\n' >>"$artifact/bin/beagle-store-server-native"
expect_refused

printf 'north-store launch protocol barrier: PASS\n'
