#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO/dotfiles/bin/opacity"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/opacity-test.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT

export GIT_AUTHOR_NAME=opacity-test
export GIT_AUTHOR_EMAIL=opacity-test@example.invalid
export GIT_COMMITTER_NAME=opacity-test
export GIT_COMMITTER_EMAIL=opacity-test@example.invalid

pass=0
fail_count=0

check() { # check <description> <0|1 truth>
  if [ "$2" -eq 0 ]; then
    printf 'PASS: %s\n' "$1"
    pass=$((pass + 1))
  else
    printf 'FAIL: %s\n' "$1" >&2
    fail_count=$((fail_count + 1))
  fi
}

# never touch the real repo or ~/.config: point the `world` resolver at a
# sandbox container and at a manifest path that cannot exist.
manifest="$scratch/no-such-manifest.env"
container="$scratch/repo"

commit_count() { git -C "$container" log --oneline | wc -l | tr -d ' '; }

fresh_repo() { # rebuild the sandbox container with a realistic niri config
  rm -rf "$container"
  mkdir -p "$container/dotfiles/niri"
  git init -q -b main "$container"
  cat >"$container/dotfiles/niri/config.kdl" <<'EOF'
layout {
    focus-ring {
        width 2
    }
}

// opacity 0.50
window-rule {
    match app-id="foo"
    opacity 0.88
}
EOF
  printf 'sample readme\n' >"$container/README.md"
  git -C "$container" add -A
  git -C "$container" commit -qm base
}

# config file with no opacity line at all (guard case 7)
no_opacity_line_repo() {
  rm -rf "$container"
  mkdir -p "$container/dotfiles/niri"
  git init -q -b main "$container"
  cat >"$container/dotfiles/niri/config.kdl" <<'EOF'
layout {
    focus-ring {
        width 2
    }
}
EOF
  git -C "$container" add -A
  git -C "$container" commit -qm base
}

run_opacity() { # run_opacity [args...] -> sets $out $status
  set +e
  out="$(WORLD_MANIFEST_PATH="$manifest" WORLD_REPO_NIXOS_CONFIG="$container" "$TARGET" "$@" 2>&1)"
  status=$?
  set -e
}

cfg() { printf '%s/dotfiles/niri/config.kdl' "$container"; }

# --- case 1: no-arg read prints current value and changes nothing ----------
fresh_repo
before_count=$(commit_count)
before_sha=$(sha256sum "$(cfg)" | cut -d' ' -f1)
run_opacity
[ "$status" -eq 0 ] && check "no-arg read exits 0" 0 || check "no-arg read exits 0" 1
if grep -Fq 'Opacity: 0.88' <<<"$out"; then
  check "no-arg read prints the current value" 0
else
  printf '%s\n' "$out" >&2
  check "no-arg read prints the current value" 1
fi
after_sha=$(sha256sum "$(cfg)" | cut -d' ' -f1)
[ "$before_sha" = "$after_sha" ] \
  && check "no-arg read leaves the config file byte-identical" 0 \
  || check "no-arg read leaves the config file byte-identical" 1
[ "$(commit_count)" -eq "$before_count" ] \
  && check "no-arg read creates no commit" 0 \
  || check "no-arg read creates no commit" 1

# --- case 2: set on a clean repo ---------------------------------------------
fresh_repo
before_count=$(commit_count)
run_opacity 0.75
[ "$status" -eq 0 ] && check "clean set exits 0" 0 || check "clean set exits 0" 1
grep -Fq 'opacity 0.75' "$(cfg)" \
  && check "clean set updates the config file" 0 \
  || check "clean set updates the config file" 1
[ "$(commit_count)" -eq $((before_count + 1)) ] \
  && check "clean set creates exactly one new commit" 0 \
  || check "clean set creates exactly one new commit" 1
subject=$(git -C "$container" log -1 --format=%s)
[ "$subject" = "niri: opacity 0.75" ] \
  && check "clean set commit subject is niri: opacity 0.75" 0 \
  || check "clean set commit subject is niri: opacity 0.75" 1
[ -z "$(git -C "$container" status --porcelain)" ] \
  && check "clean set leaves working tree clean" 0 \
  || check "clean set leaves working tree clean" 1

# --- case 3: two consecutive sets amend, and readme survives ----------------
fresh_repo
before_count=$(commit_count)
run_opacity 0.60
first_after_count=$(commit_count)
run_opacity 0.50
final_count=$(commit_count)
[ "$final_count" -eq $((before_count + 1)) ] \
  && check "two consecutive sets amend into one new commit total" 0 \
  || check "two consecutive sets amend into one new commit total" 1
[ "$first_after_count" -eq "$final_count" ] \
  && check "second set did not add a further commit" 0 \
  || check "second set did not add a further commit" 1
subject=$(git -C "$container" log -1 --format=%s)
[ "$subject" = "niri: opacity 0.50" ] \
  && check "amended commit subject carries the second value" 0 \
  || check "amended commit subject carries the second value" 1
grep -Fq 'opacity 0.50' "$(cfg)" \
  && check "amended commit's file holds the second value" 0 \
  || check "amended commit's file holds the second value" 1
# case 8: the amend must not drop the other file that rode along in that commit
if git -C "$container" show HEAD:README.md 2>/dev/null | grep -Fq 'sample readme'; then
  check "amend preserves the previous commit's other tracked files" 0
else
  check "amend preserves the previous commit's other tracked files" 1
fi

# --- case 4: amend safety once the commit is published (ancestor of origin) --
fresh_repo
run_opacity 0.60
published_count=$(commit_count)
remote_dir="$scratch/origin.git"
rm -rf "$remote_dir"
git clone --bare -q "$container" "$remote_dir"
git -C "$container" remote add origin "$remote_dir"
git -C "$container" fetch -q origin
run_opacity 0.55
[ "$(commit_count)" -eq $((published_count + 1)) ] \
  && check "set after publish creates a new commit instead of amending" 0 \
  || check "set after publish creates a new commit instead of amending" 1
newest=$(git -C "$container" log -1 --format=%s)
previous=$(git -C "$container" log -1 --format=%s --skip=1)
[ "$newest" = "niri: opacity 0.55" ] \
  && check "new commit's subject carries the latest value" 0 \
  || check "new commit's subject carries the latest value" 1
[ "$previous" = "niri: opacity 0.60" ] \
  && check "the published commit was left intact rather than amended" 0 \
  || check "the published commit was left intact rather than amended" 1
grep -Fq 'opacity 0.55' "$(cfg)" \
  && check "post-publish set's file holds the newest value" 0 \
  || check "post-publish set's file holds the newest value" 1

# --- case 5: unrelated dirty path present ------------------------------------
fresh_repo
before_count=$(commit_count)
printf 'unrelated local edit\n' >>"$container/README.md"
run_opacity 0.66
[ "$status" -eq 0 ] && check "set with unrelated dirty path exits 0" 0 || check "set with unrelated dirty path exits 0" 1
grep -Fq 'opacity 0.66' "$(cfg)" \
  && check "set with unrelated dirty path still applies the value" 0 \
  || check "set with unrelated dirty path still applies the value" 1
[ "$(commit_count)" -eq "$before_count" ] \
  && check "set with unrelated dirty path commits nothing" 0 \
  || check "set with unrelated dirty path commits nothing" 1
if grep -Fq 'other uncommitted changes' <<<"$out"; then
  check "message mentions other uncommitted changes" 0
else
  printf '%s\n' "$out" >&2
  check "message mentions other uncommitted changes" 1
fi
dirty_lines=$(git -C "$container" status --porcelain | wc -l | tr -d ' ')
[ "$dirty_lines" -eq 2 ] \
  && check "both the unrelated edit and the opacity edit remain uncommitted" 0 \
  || check "both the unrelated edit and the opacity edit remain uncommitted" 1

# --- case 6: guard — missing config file -------------------------------------
fresh_repo
rm "$(cfg)"
run_opacity
[ "$status" -ne 0 ] && check "missing config file exits nonzero" 0 || check "missing config file exits nonzero" 1
if grep -Fq 'missing' <<<"$out"; then
  check "missing config file message is clear" 0
else
  printf '%s\n' "$out" >&2
  check "missing config file message is clear" 1
fi

# --- case 7: guard — config present but no opacity line ---------------------
no_opacity_line_repo
run_opacity 0.70
[ "$status" -ne 0 ] && check "no opacity line exits nonzero on set" 0 || check "no opacity line exits nonzero on set" 1
if grep -Fq 'no opacity line found' <<<"$out"; then
  check "no opacity line message is clear" 0
else
  printf '%s\n' "$out" >&2
  check "no opacity line message is clear" 1
fi

if [ "$fail_count" -eq 0 ]; then
  printf 'opacity tests: PASS (%d checks)\n' "$pass"
else
  printf 'opacity tests: FAIL (%d passed, %d failed)\n' "$pass" "$fail_count" >&2
  exit 1
fi
