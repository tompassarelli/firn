#!/usr/bin/env bash
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO/dotfiles/bin/firn-prewarm"
REBUILD_RKT="$REPO/scripts/firn-cmds/rebuild.rkt"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/fp-test.XXXXXX")"

export GIT_AUTHOR_NAME=firn-prewarm-test
export GIT_AUTHOR_EMAIL=firn-prewarm-test@example.invalid
export GIT_COMMITTER_NAME=firn-prewarm-test
export GIT_COMMITTER_EMAIL=firn-prewarm-test@example.invalid

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

kill_tracked() { # every pid this suite may have left behind
  local pid
  if [ -f "$runtime/firn-prewarm-${UID:-0}.pid" ]; then
    for pid in $(tr ' ' '\n' <"$runtime/firn-prewarm-${UID:-0}.pid"); do
      case "$pid" in '' | *[!0-9]*) continue ;; esac
      kill -TERM "$pid" 2>/dev/null
    done
  fi
  for pid in ${tracked_pids:-}; do kill -TERM "$pid" 2>/dev/null; done
}
tracked_pids=""
trap 'kill_tracked; rm -rf "${scratch:?}"' EXIT

# ── sandbox ────────────────────────────────────────────────────────────────
# A fake `nix` first on PATH: no evaluation is ever run from this suite.
container="$scratch/repo"
runtime="$scratch/run"
stub_bin="$scratch/bin"
nix_log="$scratch/nix-args.log"
mkdir -p "$runtime" "$stub_bin"
export XDG_RUNTIME_DIR="$runtime"
export NIX_ARGS_LOG="$nix_log"
export PATH="$stub_bin:$PATH"
pidfile="$runtime/firn-prewarm-${UID:-0}.pid"

cat >"$stub_bin/nix" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NIX_ARGS_LOG"
[ -n "${FAKE_NIX_SLEEP:-}" ] && sleep "$FAKE_NIX_SLEEP"
exit 0
EOF
chmod +x "$stub_bin/nix"

cat >"$stub_bin/firn-native" <<'EOF'
#!/usr/bin/env bash
sleep 30
EOF
chmod +x "$stub_bin/firn-native"

host="$(hostname 2>/dev/null || uname -n)"
fresh_repo() {
  rm -rf "$container"
  mkdir -p "$container/scripts" "$container/hosts/$host" "$container/dotfiles/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$container/scripts/firn-build"
  chmod +x "$container/scripts/firn-build"
  printf ';; sandbox\n' >"$container/flake.bnix"
  cp "$TARGET" "$container/dotfiles/bin/firn-prewarm"
  cp "$REPO/dotfiles/bin/world" "$container/dotfiles/bin/world"
  git init -q -b main "$container"
  git -C "$container" add -A
  git -C "$container" commit -qm base
  : >"$nix_log"
  rm -f "$pidfile"
}

run_prewarm() { # run_prewarm [args...] -> sets $out $status
  out="$(FIRN_REPO="$container" "$TARGET" "$@" 2>&1)"
  status=$?
}

wait_for() { # wait_for <seconds> <command...>
  local deadline
  deadline=$(awk -v n="$1" 'BEGIN { printf "%.2f", systime() + n }')
  shift
  while :; do
    "$@" && return 0
    awk -v d="$deadline" 'BEGIN { exit (systime() > d) ? 0 : 1 }' && return 1
    sleep 0.05
  done
}

# ── expected URI, derived mechanically from rebuild.rkt ────────────────────
# Pull the format templates out of `snapshot-ref` itself, so a change to the
# pipeline's URI shape fails this test instead of silently costing every
# rebuild a cold evaluation.
snapshot_ref_region() {
  awk '/\(define \(snapshot-ref\)/ { grab = 5 }
       grab > 0 { print; grab-- }' "$REBUILD_RKT"
}
attr_region() {
  grep -o '"nixosConfigurations\.[^"]*"' "$REBUILD_RKT" | head -1 | sed 's/^"//; s/"$//'
}
uri_template="$(snapshot_ref_region | grep -o '"git+file://[^"]*"' | head -1 | sed 's/^"//; s/"$//')"
ref_template="$(snapshot_ref_region | grep -o '"&ref=[^"]*"' | head -1 | sed 's/^"//; s/"$//')"
attr_template="$(attr_region)"

subst() { # subst <racket-format-template> <arg>... — fills ~a placeholders in order
  local template="$1" rest out="" arg
  shift
  rest="$template"
  for arg in "$@"; do
    out="$out${rest%%'~a'*}$arg"
    rest="${rest#*'~a'}"
  done
  printf '%s%s\n' "$out" "$rest"
}

expected_uri() { # expected_uri <repo> <head> <branch>
  local refpart=""
  [ -n "$3" ] && refpart="$(subst "$ref_template" "$3")"
  subst "$uri_template" "$1" "$2" "$refpart"
}

[ -n "$uri_template" ] && [ -n "$ref_template" ] && [ -n "$attr_template" ] \
  && check "rebuild.rkt still exposes the snapshot-ref and attr templates" 0 \
  || check "rebuild.rkt still exposes the snapshot-ref and attr templates" 1

# ── case 1: URI on a branch matches rebuild.rkt byte for byte ─────────────
fresh_repo
run_prewarm --foreground
if grep -Fq 'skipped' <<<"$out"; then
  printf '%s\n' "$out" >&2
  check "no ambient firn rebuild is interfering with this suite" 1
else
  check "no ambient firn rebuild is interfering with this suite" 0
fi
head_sha="$(git -C "$container" rev-parse HEAD)"
want="$(expected_uri "$container" "$head_sha" main)#$(subst "$attr_template" "$host")"
got="$(sed -n '1s/^build --no-link --print-out-paths //p' "$nix_log")"
[ "$got" = "$want" ] \
  && check "on-branch URI+attr matches rebuild.rkt's snapshot-ref" 0 \
  || { printf '  want: %s\n  got:  %s\n' "$want" "$got" >&2
       check "on-branch URI+attr matches rebuild.rkt's snapshot-ref" 1; }
[ "$(wc -l <"$nix_log")" -eq 1 ] \
  && check "foreground prewarm invokes nix exactly once" 0 \
  || check "foreground prewarm invokes nix exactly once" 1
grep -Fq -- "--no-link" "$nix_log" \
  && check "prewarm builds with --no-link" 0 \
  || check "prewarm builds with --no-link" 1
[ "$status" -eq 0 ] && check "foreground prewarm exits 0" 0 || check "foreground prewarm exits 0" 1

# ── case 2: detached HEAD drops the &ref, exactly as rebuild.rkt does ─────
fresh_repo
git -C "$container" checkout -q --detach HEAD
run_prewarm --foreground
head_sha="$(git -C "$container" rev-parse HEAD)"
want="$(expected_uri "$container" "$head_sha" "")#$(subst "$attr_template" "$host")"
got="$(sed -n '1s/^build --no-link --print-out-paths //p' "$nix_log")"
[ "$got" = "$want" ] \
  && check "detached-HEAD URI omits &ref like rebuild.rkt" 0 \
  || { printf '  want: %s\n  got:  %s\n' "$want" "$got" >&2
       check "detached-HEAD URI omits &ref like rebuild.rkt" 1; }

# ── case 3: an inherited GIT_DIR never redirects the snapshot ─────────────
fresh_repo
other="$scratch/other"
rm -rf "$other"
mkdir -p "$other"
git init -q -b main "$other"
printf 'x\n' >"$other/f"
git -C "$other" add -A
git -C "$other" commit -qm other
GIT_DIR="$other/.git" GIT_WORK_TREE="$other" FIRN_REPO="$container" "$TARGET" --foreground >/dev/null 2>&1
head_sha="$(git -C "$container" rev-parse HEAD)"
grep -Fq "rev=$head_sha" "$nix_log" \
  && check "inherited GIT_DIR does not hijack the snapshot rev" 0 \
  || check "inherited GIT_DIR does not hijack the snapshot rev" 1

# ── case 4: detached mode returns immediately and says nothing ────────────
fresh_repo
start="$(date +%s.%N)"
out="$(FIRN_REPO="$container" FAKE_NIX_SLEEP=10 "$TARGET" 2>/dev/null)"
status=$?
elapsed="$(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN { printf "%.3f", b - a }')"
awk -v e="$elapsed" 'BEGIN { exit (e < 1.0) ? 0 : 1 }' \
  && check "detached invocation returns in under 1s (${elapsed}s)" 0 \
  || check "detached invocation returns in under 1s (${elapsed}s)" 1
[ "$status" -eq 0 ] && check "detached invocation exits 0" 0 || check "detached invocation exits 0" 1
[ -z "$out" ] && check "detached invocation prints nothing to stdout" 0 \
  || check "detached invocation prints nothing to stdout" 1
wait_for 5 test -s "$pidfile" \
  && check "detached invocation records a pidfile" 0 \
  || check "detached invocation records a pidfile" 1

# ── case 5: a second invocation supersedes the first ──────────────────────
read -r first_shell first_nix <"$pidfile"
tracked_pids="$first_shell $first_nix"
FIRN_REPO="$container" FAKE_NIX_SLEEP=10 "$TARGET" >/dev/null 2>&1
wait_for 5 bash -c '! kill -0 '"$first_nix"' 2>/dev/null' \
  && check "supersede kills the previous prewarm's nix process" 0 \
  || check "supersede kills the previous prewarm's nix process" 1
wait_for 5 bash -c 'read -r s _ <"'"$pidfile"'"; [ "$s" != "'"$first_shell"'" ]' \
  && check "supersede leaves the newest prewarm owning the pidfile" 0 \
  || check "supersede leaves the newest prewarm owning the pidfile" 1
read -r second_shell second_nix <"$pidfile"
tracked_pids="$tracked_pids $second_shell $second_nix"
kill -TERM "$second_nix" 2>/dev/null
kill -TERM "$second_shell" 2>/dev/null
sleep 0.2

# ── case 6: skip while a firn rebuild is already evaluating ───────────────
fresh_repo
"$stub_bin/firn-native" rebuild &
fake_rebuild=$!
tracked_pids="$tracked_pids $fake_rebuild"
wait_for 5 bash -c '[ -r /proc/'"$fake_rebuild"'/cmdline ]' >/dev/null
run_prewarm --foreground
[ ! -s "$nix_log" ] \
  && check "no nix evaluation is started while a firn rebuild runs" 0 \
  || { cat "$nix_log" >&2; check "no nix evaluation is started while a firn rebuild runs" 1; }
grep -Fq 'skipped' <<<"$out" \
  && check "skip is reported, not silently swallowed" 0 \
  || { printf '%s\n' "$out" >&2; check "skip is reported, not silently swallowed" 1; }
[ "$status" -eq 0 ] && check "skip exits 0" 0 || check "skip exits 0" 1
kill -TERM "$fake_rebuild" 2>/dev/null
wait "$fake_rebuild" 2>/dev/null
sleep 0.2
run_prewarm --foreground
[ -s "$nix_log" ] \
  && check "prewarm resumes once the rebuild is gone" 0 \
  || check "prewarm resumes once the rebuild is gone" 1

# ── case 7: hook installation ─────────────────────────────────────────────
fresh_repo
hook="$container/.git/hooks/post-commit"
(cd "$container" && FIRN_REPO="$container" "$TARGET" --install-hook >/dev/null 2>&1)
[ -x "$hook" ] && check "install-hook writes an executable post-commit hook" 0 \
  || check "install-hook writes an executable post-commit hook" 1
grep -Fq "$container/dotfiles/bin/firn-prewarm" "$hook" 2>/dev/null \
  && check "the hook calls the resolved checkout's firn-prewarm" 0 \
  || check "the hook calls the resolved checkout's firn-prewarm" 1
before="$(cat "$hook" 2>/dev/null)"
(cd "$container" && FIRN_REPO="$container" "$TARGET" --install-hook >/dev/null 2>&1)
[ "$(cat "$hook" 2>/dev/null)" = "$before" ] \
  && check "install-hook is idempotent" 0 \
  || check "install-hook is idempotent" 1
printf '#!/usr/bin/env bash\n# someone else was here\n' >"$hook"
foreign="$(cat "$hook")"
(cd "$container" && FIRN_REPO="$container" "$TARGET" --install-hook >/dev/null 2>&1)
[ "$(cat "$hook")" = "$foreign" ] \
  && check "install-hook never clobbers a foreign post-commit hook" 0 \
  || check "install-hook never clobbers a foreign post-commit hook" 1

# ── case 8: an unusable environment is never a caller's problem ───────────
out="$(FIRN_REPO="$scratch/not-a-repo" WORLD_MANIFEST_PATH="$scratch/none.env" \
       WORLD_REPO_NIXOS_CONFIG="$scratch/not-a-repo" "$TARGET" --foreground 2>&1)"
status=$?
[ "$status" -eq 0 ] \
  && check "an unresolvable repo exits 0 instead of disturbing the caller" 0 \
  || check "an unresolvable repo exits 0 instead of disturbing the caller" 1
"$TARGET" --nonsense >/dev/null 2>&1
status=$?
[ "$status" -eq 0 ] && check "an unknown flag exits 0" 0 || check "an unknown flag exits 0" 1

if [ "$fail_count" -eq 0 ]; then
  printf 'firn-prewarm tests: PASS (%d checks)\n' "$pass"
else
  printf 'firn-prewarm tests: FAIL (%d passed, %d failed)\n' "$pass" "$fail_count" >&2
  exit 1
fi
