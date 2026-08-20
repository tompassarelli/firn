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
    printf 'tag-commands-native: cannot locate the Firn Git common directory\n' >&2
    exit 1
  }
  code_root="$(cd "$(dirname "$git_common_dir")/../.." && pwd)"
  beagle="$code_root/beagle/main"
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-tag-commands-native.XXXXXX")"

cleanup() {
  local status=$?
  trap - EXIT
  if ((status == 0)); then
    rm -rf "${scratch:?}"
  else
    printf 'tag-commands-native: retained failure artifacts at %s\n' \
      "$scratch" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

die() {
  printf 'tag-commands-native: %s\n' "$*" >&2
  exit 1
}

[[ -f "$beagle/bin/_beagle-racket" ]] \
  || die "authoritative Beagle checkout is missing: $beagle"

# shellcheck disable=SC1091
source "$beagle/bin/_beagle-racket"

build_native() {
  local name="$1" entry="$2"
  shift 2
  local output="$scratch/$name"
  printf 'tag-commands-native: building %s\n' "$name" >&2
  mkdir -p "$scratch/$name-artifacts"
  timeout --foreground 620 "$beagle/bin/beagle" native-exe \
    --out "$output" \
    --entry "$entry" \
    --artifacts "$scratch/$name-artifacts" \
    "$@" >"$scratch/$name.build.out" 2>"$scratch/$name.build.err" \
    || {
      sed -n '1,240p' "$scratch/$name.build.err" >&2
      die "$name compilation failed"
    }
  [[ -x "$output" ]] || die "$name is not executable"
}

run_once() {
  local result="$1"
  shift
  set +e
  timeout --foreground 30 "$@" >"$result.out" 2>"$result.err"
  local status=$?
  set -e
  printf '%s\n' "$status" >"$result.status"
}

assert_status() {
  local result="$1" expected="$2" label="$3"
  [[ "$(<"$result.status")" == "$expected" ]] \
    || die "$label returned $(<"$result.status"), expected $expected"
}

assert_empty() {
  local file="$1" label="$2"
  [[ ! -s "$file" ]] || die "$label was not empty"
}

assert_same() {
  local expected="$1" actual="$2" label="$3"
  cmp -s "$expected" "$actual" || {
    diff -u "$expected" "$actual" >&2 || true
    die "$label changed"
  }
}

datum="$beagle/native-core/src/beagle/datum_reader.bgl"
json="$beagle/native-core/src/native/json.bgl"
resolve="$repo/native/tag_resolve.bgl"
inputs="$repo/native/tag_inputs.bgl"
resolve_driver="$repo/native/tag_resolve_driver.bgl"
resolve_native="$repo/native/tag_resolve_native.bgl"
commands="$repo/native/tag_commands.bgl"
commands_driver="$repo/native/tag_commands_driver.bgl"

build_native tag-commands-test firn.tag-commands-test/-main \
  "$datum" "$json" "$resolve" "$inputs" "$commands" \
  "$commands_driver" "$repo/native/tag_commands_test.bgl"
build_native tag-commands-native firn.tag-commands-native/-main \
  "$datum" "$json" "$resolve" "$inputs" "$resolve_driver" \
  "$resolve_native" "$commands" "$commands_driver" \
  "$repo/native/tag_commands_native.bgl"

printf 'tag-commands-native: running pure render/index checks\n' >&2
run_once "$scratch/pure" "$scratch/tag-commands-test"
assert_status "$scratch/pure" 0 "pure command tests"
assert_empty "$scratch/pure.err" "pure command test stderr"
[[ "$(rg -c '^PASS ' "$scratch/pure.out")" == "7" ]] \
  || die "pure render/index cases did not all pass"
[[ "$(rg -c '^FAIL ' "$scratch/pure.out" || true)" == "0" ]] \
  || die "pure render/index cases reported a failure"

make_fixture() {
  local root="$1" host="${2:-fixture}"
  mkdir -p \
    "$root/scripts" \
    "$root/modules/alpha" \
    "$root/modules/beta" \
    "$root/modules/delta" \
    "$root/modules/epsilon" \
    "$root/modules/gamma" \
    "$root/modules/plain" \
    "$root/hosts/$host"
  : >"$root/scripts/firn-build"
  cat >"$root/flake.bnix" <<'EOF'
#lang beagle/nix
(ns flake)
{}
EOF
  cat >"$root/modules/alpha/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags [desktop terminal]})
EOF
  cat >"$root/modules/beta/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags [desktop]})
EOF
  cat >"$root/modules/delta/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags-opt-in [desktop]})
EOF
  cat >"$root/modules/epsilon/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags [creative]
   :tags-opt-in [desktop]})
EOF
  cat >"$root/modules/gamma/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags [terminal]})
EOF
  cat >"$root/modules/plain/default.bnix" <<'EOF'
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:config {}})
EOF
  cat >"$root/hosts/$host/enabled-tags.bnix" <<'EOF'
#lang beagle/nix

(ns enabled-tags)

{:platform linux
 :enabled
  [[desktop -beta +delta]
   terminal]
 :disabled [gamma]
}
EOF
}

write_expected_files() {
  cat >"$scratch/enable-creative.bnix" <<'EOF'
#lang beagle/nix

(ns enabled-tags)

{:platform linux
 :enabled
  [[desktop -beta +delta]
   terminal
   creative]
 :disabled [gamma]
}
EOF
  cat >"$scratch/disable-terminal.bnix" <<'EOF'
#lang beagle/nix

(ns enabled-tags)

{:platform linux
 :enabled
  [[desktop -beta +delta]]
 :disabled [gamma]
}
EOF
  cat >"$scratch/opt-in-epsilon.bnix" <<'EOF'
#lang beagle/nix

(ns enabled-tags)

{:platform linux
 :enabled
  [[desktop -beta +delta +epsilon]
   terminal]
 :disabled [gamma]
}
EOF
  cat >"$scratch/opt-out-alpha.bnix" <<'EOF'
#lang beagle/nix

(ns enabled-tags)

{:platform linux
 :enabled
  [[desktop -beta +delta]
   [terminal -alpha]]
 :disabled [gamma]
}
EOF
  cat >"$scratch/module-disable-alpha.bnix" <<'EOF'
#lang beagle/nix

(ns enabled-tags)

{:platform linux
 :enabled
  [[desktop -beta +delta]
   terminal]
 :disabled [alpha gamma]
}
EOF
  cat >"$scratch/module-enable-gamma.bnix" <<'EOF'
#lang beagle/nix

(ns enabled-tags)

{:platform linux
 :enabled
  [[desktop -beta +delta]
   terminal]
}
EOF

  cat >"$scratch/status-base.expected" <<'EOF'
Host: fixture
Platform: linux
Source: hosts/fixture/enabled-tags.bnix

:enabled (2):
  [desktop -beta +delta]
  terminal

:disabled (1):
  gamma

Resolved active modules (2):
  alpha
  delta
EOF
  cat >"$scratch/status-enable-creative.out" <<'EOF'
Host: fixture
Platform: linux
Source: hosts/fixture/enabled-tags.bnix

:enabled (3):
  [desktop -beta +delta]
  terminal
  creative

:disabled (1):
  gamma

Resolved active modules (3):
  alpha
  delta
  epsilon
EOF
  cat >"$scratch/status-disable-terminal.out" <<'EOF'
Host: fixture
Platform: linux
Source: hosts/fixture/enabled-tags.bnix

:enabled (1):
  [desktop -beta +delta]

:disabled (1):
  gamma

Resolved active modules (2):
  alpha
  delta
EOF
  cat >"$scratch/status-opt-in-epsilon.out" <<'EOF'
Host: fixture
Platform: linux
Source: hosts/fixture/enabled-tags.bnix

:enabled (2):
  [desktop -beta +delta +epsilon]
  terminal

:disabled (1):
  gamma

Resolved active modules (3):
  alpha
  delta
  epsilon
EOF
  cat >"$scratch/status-opt-out-alpha.out" <<'EOF'
Host: fixture
Platform: linux
Source: hosts/fixture/enabled-tags.bnix

:enabled (2):
  [desktop -beta +delta]
  [terminal -alpha]

:disabled (1):
  gamma

Resolved active modules (2):
  alpha
  delta
EOF
  cat >"$scratch/status-module-disable-alpha.out" <<'EOF'
Host: fixture
Platform: linux
Source: hosts/fixture/enabled-tags.bnix

:enabled (2):
  [desktop -beta +delta]
  terminal

:disabled (2):
  alpha
  gamma

Resolved active modules (1):
  delta
EOF
  cat >"$scratch/status-module-enable-gamma.out" <<'EOF'
Host: fixture
Platform: linux
Source: hosts/fixture/enabled-tags.bnix

:enabled (2):
  [desktop -beta +delta]
  terminal

:disabled (0):
  (none)

Resolved active modules (3):
  alpha
  delta
  gamma
EOF
  cat >"$scratch/module-enable-gamma-second.expected" <<'EOF'
firn module enable: no module-level force-on in tag-driven hosts.

  gamma is not currently blacklisted in :disabled, so there is
  nothing to un-blacklist. To activate it on this host:

    - opt in via a tag:    firn tag opt-in <tag>+gamma
      (where <tag> is one the module lists in :tags-opt-in)
    - or enable a tag the module already lists in :tags:
                            firn tag enable <tag>
    - or, only as a last resort, add :tags fixture-only to the module
      and enable that tag here.
EOF
}

write_expected_files

run_native() {
  local result="$1" root="$2" host="$3"
  shift 3
  run_once "$result" env FIRN_REPO="$root" FIRN_HOST="$host" \
    "$scratch/tag-commands-native" "$@"
}

printf 'tag-commands-native: checking exact inventory/status output\n' >&2
inventory_root="$scratch/inventory-repo"
make_fixture "$inventory_root"

cat >"$scratch/list.expected" <<'EOF'
Tags (3):
  creative            (1 default)
  desktop             (2 default, 2 opt-in)
  terminal            (2 default)

Coverage: 5 / 6 modules carry at least one tag.
EOF
run_native "$scratch/list" "$inventory_root" fixture tag list
assert_status "$scratch/list" 0 "tag list"
assert_same "$scratch/list.expected" "$scratch/list.out" "tag list stdout"
assert_empty "$scratch/list.err" "tag list stderr"

cat >"$scratch/show.expected" <<'EOF'
module: epsilon
:tags         creative
:tags-opt-in  desktop
EOF
run_native "$scratch/show" "$inventory_root" fixture tag show epsilon
assert_status "$scratch/show" 0 "tag show"
assert_same "$scratch/show.expected" "$scratch/show.out" "tag show stdout"
assert_empty "$scratch/show.err" "tag show stderr"

cat >"$scratch/filter.expected" <<'EOF'
modules tagged 'desktop' (4):
  alpha  (default)
  beta  (default)
  delta  (opt-in)
  epsilon  (opt-in)
EOF
run_native "$scratch/filter" "$inventory_root" fixture tag filter desktop
assert_status "$scratch/filter" 0 "tag filter"
assert_same "$scratch/filter.expected" "$scratch/filter.out" \
  "tag filter stdout"
assert_empty "$scratch/filter.err" "tag filter stderr"

cat >"$scratch/index.expected" <<'EOF'
{"name":"alpha","tags":["desktop","terminal"],"tags_opt_in":[]}
{"name":"beta","tags":["desktop"],"tags_opt_in":[]}
{"name":"delta","tags":[],"tags_opt_in":["desktop"]}
{"name":"epsilon","tags":["creative"],"tags_opt_in":["desktop"]}
{"name":"gamma","tags":["terminal"],"tags_opt_in":[]}
{"name":"plain","tags":[],"tags_opt_in":[]}
EOF
run_native "$scratch/index-stdout" "$inventory_root" fixture tag index stdout
assert_status "$scratch/index-stdout" 0 "tag index stdout"
assert_same "$scratch/index.expected" "$scratch/index-stdout.out" \
  "tag index stdout bytes"
assert_empty "$scratch/index-stdout.err" "tag index stdout stderr"

run_native "$scratch/index-repo" "$inventory_root" fixture tag index
assert_status "$scratch/index-repo" 0 "tag index repo"
printf 'firn tag index: wrote 6 entries → .beagle-cache/tags.jsonl\n' \
  >"$scratch/index-repo.expected"
assert_same "$scratch/index-repo.expected" "$scratch/index-repo.out" \
  "tag index repo diagnostic"
assert_empty "$scratch/index-repo.err" "tag index repo stderr"
assert_same "$scratch/index.expected" \
  "$inventory_root/.beagle-cache/tags.jsonl" "tag index repo bytes"

run_native "$scratch/status-base" "$inventory_root" fixture tag status fixture
assert_status "$scratch/status-base" 0 "tag status"
assert_same "$scratch/status-base.expected" "$scratch/status-base.out" \
  "tag status output"
assert_empty "$scratch/status-base.err" "tag status stderr"

check_mutation() {
  local name="$1" expected_file="$2" expected_status="$3" second_mode="$4"
  shift 4
  local root="$scratch/mutation-$name"
  local host_file="$root/hosts/fixture/enabled-tags.bnix"
  local -a command=("$@")

  make_fixture "$root"
  cp "$host_file" "$scratch/$name.before.bnix"
  run_native "$scratch/$name.first" "$root" fixture "${command[@]}"
  assert_status "$scratch/$name.first" 0 "$name first mutation"
  printf 'updated hosts/fixture/enabled-tags.bnix\n' \
    >"$scratch/$name.first.expected"
  assert_same "$scratch/$name.first.expected" "$scratch/$name.first.out" \
    "$name first stdout"
  assert_empty "$scratch/$name.first.err" "$name first stderr"
  cmp -s "$scratch/$name.before.bnix" "$host_file" \
    && die "$name reported an update without changing bytes"
  assert_same "$expected_file" "$host_file" "$name mutated source"
  cp "$host_file" "$scratch/$name.after-first.bnix"

  run_native "$scratch/$name.second" "$root" fixture "${command[@]}"
  if [[ "$second_mode" == "noop" ]]; then
    assert_status "$scratch/$name.second" 0 "$name idempotent mutation"
    printf 'no change to hosts/fixture/enabled-tags.bnix\n' \
      >"$scratch/$name.second.expected"
    assert_same "$scratch/$name.second.expected" "$scratch/$name.second.out" \
      "$name idempotent stdout"
    assert_empty "$scratch/$name.second.err" "$name idempotent stderr"
  elif [[ "$second_mode" == "module-enable-refusal" ]]; then
    assert_status "$scratch/$name.second" 1 \
      "$name post-enable hosted refusal"
    assert_empty "$scratch/$name.second.out" \
      "$name post-enable refusal stdout"
    assert_same "$scratch/module-enable-gamma-second.expected" \
      "$scratch/$name.second.err" "$name post-enable refusal stderr"
  else
    die "$name has unknown second-run mode $second_mode"
  fi
  assert_same "$scratch/$name.after-first.bnix" "$host_file" \
    "$name idempotent bytes"

  run_native "$scratch/$name.status" "$root" fixture tag status fixture
  assert_status "$scratch/$name.status" 0 "$name resolver status"
  assert_same "$expected_status" "$scratch/$name.status.out" \
    "$name resolver result"
  assert_empty "$scratch/$name.status.err" "$name resolver stderr"
  [[ "$(find "$root/hosts/fixture" -mindepth 1 -maxdepth 1 -type f | wc -l)" \
      == "1" ]] || die "$name left an atomic-write side file"
}

printf 'tag-commands-native: checking six mutations and re-resolution\n' >&2
check_mutation enable-creative \
  "$scratch/enable-creative.bnix" "$scratch/status-enable-creative.out" \
  noop tag enable creative
check_mutation disable-terminal \
  "$scratch/disable-terminal.bnix" "$scratch/status-disable-terminal.out" \
  noop tag disable terminal
check_mutation opt-in-epsilon \
  "$scratch/opt-in-epsilon.bnix" "$scratch/status-opt-in-epsilon.out" \
  noop tag opt-in desktop+epsilon
check_mutation opt-out-alpha \
  "$scratch/opt-out-alpha.bnix" "$scratch/status-opt-out-alpha.out" \
  noop tag opt-out terminal+alpha
check_mutation module-disable-alpha \
  "$scratch/module-disable-alpha.bnix" \
  "$scratch/status-module-disable-alpha.out" noop module disable alpha
check_mutation module-enable-gamma \
  "$scratch/module-enable-gamma.bnix" \
  "$scratch/status-module-enable-gamma.out" module-enable-refusal \
  module enable gamma

printf 'tag-commands-native: checking refusal paths\n' >&2
refusal_root="$scratch/refusal-repo"
make_fixture "$refusal_root"
cp "$refusal_root/hosts/fixture/enabled-tags.bnix" \
  "$scratch/refusal.before.bnix"
run_native "$scratch/module-refusal" "$refusal_root" fixture module enable beta
assert_status "$scratch/module-refusal" 1 "module enable refusal"
assert_empty "$scratch/module-refusal.out" "module enable refusal stdout"
cat >"$scratch/module-refusal.expected" <<'EOF'
firn module enable: no module-level force-on in tag-driven hosts.

  beta is not currently blacklisted in :disabled, so there is
  nothing to un-blacklist. To activate it on this host:

    - opt in via a tag:    firn tag opt-in <tag>+beta
      (where <tag> is one the module lists in :tags-opt-in)
    - or enable a tag the module already lists in :tags:
                            firn tag enable <tag>
    - or, only as a last resort, add :tags fixture-only to the module
      and enable that tag here.
EOF
assert_same "$scratch/module-refusal.expected" "$scratch/module-refusal.err" \
  "module enable refusal diagnostic"
assert_same "$scratch/refusal.before.bnix" \
  "$refusal_root/hosts/fixture/enabled-tags.bnix" \
  "module enable refusal source"

run_native "$scratch/malformed" "$refusal_root" fixture \
  tag opt-in desktop-epsilon
assert_status "$scratch/malformed" 1 "malformed tag opt-in"
assert_empty "$scratch/malformed.out" "malformed tag opt-in stdout"
printf "firn: expected '<tag>+<module>', got 'desktop-epsilon'\n" \
  >"$scratch/malformed.expected"
assert_same "$scratch/malformed.expected" "$scratch/malformed.err" \
  "malformed tag opt-in diagnostic"
assert_same "$scratch/refusal.before.bnix" \
  "$refusal_root/hosts/fixture/enabled-tags.bnix" \
  "malformed tag opt-in source"

run_native "$scratch/malformed-missing" "$refusal_root" missing \
  tag opt-out desktop-epsilon
assert_status "$scratch/malformed-missing" 1 \
  "malformed tag opt-out on missing host"
assert_empty "$scratch/malformed-missing.out" \
  "malformed missing-host tag opt-out stdout"
assert_same "$scratch/malformed.expected" "$scratch/malformed-missing.err" \
  "malformed leaf refusal precedence"
[[ ! -e "$refusal_root/hosts/missing" ]] \
  || die "malformed leaf refusal created a host directory"

run_native "$scratch/missing-host" "$refusal_root" missing tag enable creative
assert_status "$scratch/missing-host" 1 "missing host mutation"
assert_empty "$scratch/missing-host.out" "missing host mutation stdout"
cat >"$scratch/missing-host.expected" <<'EOF'
firn: no such file hosts/missing/enabled-tags.bnix
  (create the host directory and an empty enabled-tags.bnix first)
EOF
assert_same "$scratch/missing-host.expected" "$scratch/missing-host.err" \
  "missing host mutation diagnostic"
[[ ! -e "$refusal_root/hosts/missing" ]] \
  || die "missing host mutation created a host directory"

run_native "$scratch/missing-module" "$refusal_root" fixture tag show absent
assert_status "$scratch/missing-module" 1 "missing module show"
assert_empty "$scratch/missing-module.out" "missing module show stdout"
printf "firn tag show: no module named 'absent'\n" \
  >"$scratch/missing-module.expected"
assert_same "$scratch/missing-module.expected" "$scratch/missing-module.err" \
  "missing module show diagnostic"

if ldd "$scratch/tag-commands-native" \
  | rg -qi 'racket|clojure|babashka|java'; then
  die "hosted runtime leaked into native executable"
fi

# The acceptance oracle's sole hosted-Racket command comes last. Native checks
# cannot spend it, and it exercises the order-sensitive rewrite boundary.
printf 'tag-commands-native: checking one pinned hosted rewrite oracle\n' >&2
oracle_host="$(timeout --foreground 5 hostname)"
[[ "$oracle_host" =~ ^[A-Za-z0-9._-]+$ ]] \
  || die "hostname cannot safely name the oracle fixture"
oracle_root="$scratch/oracle-repo"
native_oracle_root="$scratch/native-oracle-repo"
make_fixture "$oracle_root" "$oracle_host"
make_fixture "$native_oracle_root" "$oracle_host"
run_native "$scratch/native-oracle" "$native_oracle_root" "$oracle_host" \
  tag opt-in desktop+epsilon
assert_status "$scratch/native-oracle" 0 "native oracle candidate"
run_once "$scratch/hosted-oracle" \
  env FIRN_REPO="$oracle_root" \
    "$RACKET" "$repo/scripts/firn.rkt" tag opt-in desktop+epsilon
assert_status "$scratch/hosted-oracle" 0 "hosted rewrite oracle"
assert_same "$scratch/hosted-oracle.out" "$scratch/native-oracle.out" \
  "hosted rewrite stdout parity"
assert_same "$scratch/hosted-oracle.err" "$scratch/native-oracle.err" \
  "hosted rewrite stderr parity"
assert_same "$oracle_root/hosts/$oracle_host/enabled-tags.bnix" \
  "$native_oracle_root/hosts/$oracle_host/enabled-tags.bnix" \
  "hosted rewrite byte parity"

printf 'ok: Native tag inventory and all six mutations match hosted semantics\n'
