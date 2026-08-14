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
# Hook-spawned workers inherit the environment of whatever git command fired
# them; the explicit repo interface keeps every worker inside the fixture.
export FIRN_REPO="$container"
pidfile="$runtime/firn-prewarm-${UID:-0}.pid"
stampfile="$runtime/firn-prewarm-${UID:-0}.warm"

cat >"$stub_bin/nix" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NIX_ARGS_LOG"
[ -n "${FAKE_NIX_SLEEP:-}" ] && sleep "$FAKE_NIX_SLEEP"
[ -n "${FAKE_NIX_FAIL:-}" ] && exit 1
exit 0
EOF
chmod +x "$stub_bin/nix"

cat >"$stub_bin/firn.rkt" <<'EOF'
#!/usr/bin/env bash
sleep 30
EOF
chmod +x "$stub_bin/firn.rkt"

host="$(hostname 2>/dev/null || uname -n)"
fresh_repo() {
  rm -rf "$container"
  mkdir -p "$container/scripts" "$container/hosts/$host" "$container/dotfiles/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$container/scripts/firn-build"
  chmod +x "$container/scripts/firn-build"
  printf ';; sandbox\n' >"$container/flake.bnix"
  cp "$TARGET" "$container/dotfiles/bin/firn-prewarm"
  git init -q -b main "$container"
  git -C "$container" add -A
  git -C "$container" commit -qm base
  : >"$nix_log"
  rm -f "$pidfile" "$stampfile"
}

install_hooks() { # hook installation reads the repo from cwd
  (cd "$container" && FIRN_REPO="$container" "$TARGET" --install-hook >/dev/null 2>&1)
}
ref_hook="$container/.git/hooks/reference-transaction"

zero_oid=0000000000000000000000000000000000000000

feed_hook() { # feed_hook <hook> <state> <transaction-line>... -> $hook_status $hook_elapsed
  local hook="$1" state="$2" start line
  shift 2
  start="$(date +%s.%N)"
  { for line in "$@"; do printf '%s\n' "$line"; done; } |
    FIRN_REPO="$container" "$hook" "$state" >/dev/null 2>&1
  hook_status=$?
  hook_elapsed="$(awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN { printf "%.3f", b - a }')"
}

armed() { : >"$nix_log"; rm -f "$stampfile"; }
# A worker spends seconds in rebuild_running's /proc scan before it decides, so
# every assertion here waits on content and none infers "did not fire" from a
# wall clock; the marker hook below is what tests the filter deterministically.
fired() { wait_for 20 test -s "$nix_log"; }
settle() { sleep 0.4; }

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

# ── case 1: the script's checkout supplies the on-branch snapshot ─────────
fresh_repo
out="$(env -u FIRN_REPO "$container/dotfiles/bin/firn-prewarm" --foreground 2>&1)"
status=$?
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
"$stub_bin/firn.rkt" rebuild &
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

# ── case 7: hook installation converges on reference-transaction ──────────
fresh_repo
hook="$ref_hook"
stale="$container/.git/hooks/post-commit"
printf '#!/usr/bin/env bash\n# firn-prewarm-hook v1 — generated\nexec /nowhere\n' >"$stale"
chmod +x "$stale"
install_hooks
[ -x "$hook" ] && check "install-hook writes an executable reference-transaction hook" 0 \
  || check "install-hook writes an executable reference-transaction hook" 1
grep -Fq "$container/dotfiles/bin/firn-prewarm" "$hook" 2>/dev/null \
  && check "the hook calls the resolved checkout's firn-prewarm" 0 \
  || check "the hook calls the resolved checkout's firn-prewarm" 1
[ ! -e "$stale" ] \
  && check "install-hook retires the superseded post-commit hook it wrote" 0 \
  || check "install-hook retires the superseded post-commit hook it wrote" 1
before="$(cat "$hook" 2>/dev/null)"
install_hooks
[ "$(cat "$hook" 2>/dev/null)" = "$before" ] \
  && check "install-hook is idempotent" 0 \
  || check "install-hook is idempotent" 1
printf '#!/usr/bin/env bash\n# someone else was here\n' >"$hook"
printf '#!/usr/bin/env bash\n# someone else was here too\n' >"$stale"
foreign="$(cat "$hook")"
foreign_stale="$(cat "$stale")"
install_hooks
[ "$(cat "$hook")" = "$foreign" ] \
  && check "install-hook never clobbers a foreign reference-transaction hook" 0 \
  || check "install-hook never clobbers a foreign reference-transaction hook" 1
[ "$(cat "$stale" 2>/dev/null)" = "$foreign_stale" ] \
  && check "install-hook never deletes a foreign post-commit hook" 0 \
  || check "install-hook never deletes a foreign post-commit hook" 1

# ── case 9: what the reference-transaction hook does and does not act on ──
fresh_repo
install_hooks
head_sha="$(git -C "$container" rev-parse HEAD)"
armed
feed_hook "$hook" committed "$zero_oid $head_sha refs/heads/main"
fired \
  && check "committed refs/heads/main update fires the prewarm" 0 \
  || check "committed refs/heads/main update fires the prewarm" 1
grep -Fq "rev=$head_sha" "$nix_log" \
  && check "the fired prewarm carries the repo's current rev" 0 \
  || { cat "$nix_log" >&2; check "the fired prewarm carries the repo's current rev" 1; }
[ "$hook_status" -eq 0 ] && check "the hook exits 0 when it fires" 0 \
  || check "the hook exits 0 when it fires" 1

# "did not fire" is asserted against a barrier, never against a wall clock: the
# candidate transaction is followed by one that must fire, so a late spawn is a
# second marker line rather than a silently missed one.
marker="$scratch/hook-fired.log"
marker_hook="$scratch/hook-marker"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>%q\n' "$marker" >"$scratch/marker-prewarm"
chmod +x "$scratch/marker-prewarm"
sed "s|^prewarm=.*|prewarm=$scratch/marker-prewarm|" "$hook" >"$marker_hook"
chmod +x "$marker_hook"

nonfire() { # nonfire <description> <state> <line>
  local st fires
  : >"$marker"
  feed_hook "$marker_hook" "$2" "$3"
  st=$hook_status
  feed_hook "$marker_hook" committed "$zero_oid $head_sha refs/heads/main"
  wait_for 5 test -s "$marker"
  settle
  fires="$(wc -l <"$marker")"
  if [ "$fires" -eq 1 ] && [ "$st" -eq 0 ]; then
    check "$1" 0
  else
    printf '  status=%s fires=%s (1 = only the barrier fired)\n' "$st" "$fires" >&2
    check "$1" 1
  fi
}
nonfire "a non-main ref never fires the prewarm" committed "$zero_oid $head_sha refs/heads/lane"
nonfire "the prepared state never fires the prewarm" prepared "$zero_oid $head_sha refs/heads/main"
nonfire "the aborted state never fires the prewarm" aborted "$zero_oid $head_sha refs/heads/main"
nonfire "a refs/heads/main deletion never fires the prewarm" committed "$head_sha $zero_oid refs/heads/main"
nonfire "a no-op refs/heads/main update never fires the prewarm" committed "$head_sha $head_sha refs/heads/main"

# a real transaction carries several lines; only the main one may count
armed
feed_hook "$hook" committed "$zero_oid $head_sha ORIG_HEAD" \
  "$zero_oid $head_sha refs/heads/main" "$zero_oid $zero_oid AUTO_MERGE"
fired \
  && check "a multi-line transaction containing refs/heads/main fires once" 0 \
  || check "a multi-line transaction containing refs/heads/main fires once" 1
[ "$(wc -l <"$nix_log")" -eq 1 ] \
  && check "a multi-line transaction fires exactly one prewarm" 0 \
  || { cat "$nix_log" >&2; check "a multi-line transaction fires exactly one prewarm" 1; }

# ── case 10: a broken prewarm can never abort a git operation ─────────────
missing_hook="$scratch/hook-missing"
hang_hook="$scratch/hook-hang"
mkdir -p "$scratch/hang"
printf '#!/usr/bin/env bash\nsleep 30\n' >"$scratch/hang/firn-prewarm"
chmod +x "$scratch/hang/firn-prewarm"
sed "s|^prewarm=.*|prewarm=$scratch/nowhere/firn-prewarm|" "$hook" >"$missing_hook"
sed "s|^prewarm=.*|prewarm=$scratch/hang/firn-prewarm|" "$hook" >"$hang_hook"
chmod +x "$missing_hook" "$hang_hook"
for broken in "$missing_hook" "$hang_hook"; do
  what="missing"; [ "$broken" = "$hang_hook" ] && what="hanging"
  feed_hook "$broken" committed "$zero_oid $head_sha refs/heads/main"
  [ "$hook_status" -eq 0 ] \
    && check "a $what prewarm still leaves the hook exiting 0" 0 \
    || check "a $what prewarm still leaves the hook exiting 0" 1
  awk -v e="$hook_elapsed" 'BEGIN { exit (e < 1.0) ? 0 : 1 }' \
    && check "a $what prewarm still returns the hook in under 1s (${hook_elapsed}s)" 0 \
    || check "a $what prewarm still returns the hook in under 1s (${hook_elapsed}s)" 1
done
pkill -f -- "$scratch/hang/firn-prewarm" 2>/dev/null

# ── case 11: the landings that post-commit never saw ──────────────────────
fresh_repo
install_hooks
lane="$scratch/lane"
rm -rf "$lane"
git -C "$container" worktree add -q "$lane" -b lane
armed
pre_merge="$(git -C "$container" rev-parse HEAD)"
printf 'lane work\n' >"$lane/x"
git -C "$lane" add -A
git -C "$lane" commit -qm lane-one          # refs/heads/lane: must not fire
git -C "$container" merge --ff-only -q lane # refs/heads/main: does fire
fired && check "git merge --ff-only into main fires the prewarm" 0 \
  || check "git merge --ff-only into main fires the prewarm" 1
settle
# only a lane-triggered prewarm could ever carry the pre-merge rev
! grep -Fq "rev=$pre_merge" "$nix_log" \
  && check "a commit on a lane branch does not prewarm main's snapshot" 0 \
  || { cat "$nix_log" >&2; check "a commit on a lane branch does not prewarm main's snapshot" 1; }
head_sha="$(git -C "$container" rev-parse HEAD)"
grep -Fq "rev=$head_sha" "$nix_log" \
  && check "the ff-merge prewarm carries the newly landed rev" 0 \
  || { printf '  want rev=%s\n  got:  %s\n' "$head_sha" "$(cat "$nix_log")" >&2
       check "the ff-merge prewarm carries the newly landed rev" 1; }

# plain `fetch <src> <b>:refs/heads/main` is refused while main is checked out,
# so the landing that reaches a live checkout carries --update-head-ok.
printf 'more lane work\n' >"$lane/y"
git -C "$lane" add -A
git -C "$lane" commit -qm lane-two
armed
git -C "$container" fetch -q --update-head-ok "$lane" lane:refs/heads/main
fired && check "git fetch into refs/heads/main fires the prewarm" 0 \
  || check "git fetch into refs/heads/main fires the prewarm" 1
head_sha="$(git -C "$container" rev-parse HEAD)"
grep -Fq "rev=$head_sha" "$nix_log" \
  && check "the fetch prewarm carries the newly landed rev" 0 \
  || { printf '  want rev=%s\n  got:  %s\n' "$head_sha" "$(cat "$nix_log")" >&2
       check "the fetch prewarm carries the newly landed rev" 1; }

# and the same landing survives a hook whose prewarm is gone
cp "$missing_hook" "$hook"
printf 'still more\n' >"$lane/z"
git -C "$lane" add -A
git -C "$lane" commit -qm lane-three
git -C "$container" fetch -q --update-head-ok "$lane" lane:refs/heads/main
status=$?
[ "$status" -eq 0 ] && [ "$(git -C "$container" rev-parse refs/heads/main)" = "$(git -C "$lane" rev-parse lane)" ] \
  && check "a broken prewarm cannot abort the git operation that triggered it" 0 \
  || check "a broken prewarm cannot abort the git operation that triggered it" 1
install_hooks

# ── case 12: an already-warm URI is never re-evaluated ────────────────────
fresh_repo
run_prewarm --foreground
[ "$(wc -l <"$nix_log")" -eq 1 ] \
  && check "the first prewarm of a rev evaluates it" 0 \
  || check "the first prewarm of a rev evaluates it" 1
run_prewarm --foreground
[ "$(wc -l <"$nix_log")" -eq 1 ] \
  && check "a second prewarm of an unchanged HEAD invokes no nix" 0 \
  || { cat "$nix_log" >&2; check "a second prewarm of an unchanged HEAD invokes no nix" 1; }
grep -Fq 'already warm' <<<"$out" \
  && check "the skip says the snapshot is already warm" 0 \
  || { printf '%s\n' "$out" >&2; check "the skip says the snapshot is already warm" 1; }
printf 'change\n' >"$container/changed"
git -C "$container" add -A
git -C "$container" commit -qm changed
run_prewarm --foreground
[ "$(wc -l <"$nix_log")" -eq 2 ] \
  && check "a moved HEAD evaluates again" 0 \
  || { cat "$nix_log" >&2; check "a moved HEAD evaluates again" 1; }
fresh_repo
out="$(FIRN_REPO="$container" FAKE_NIX_FAIL=1 "$TARGET" --foreground 2>&1)"
run_prewarm --foreground
[ "$(wc -l <"$nix_log")" -eq 2 ] \
  && check "a failed evaluation is not stamped warm" 0 \
  || { cat "$nix_log" >&2; check "a failed evaluation is not stamped warm" 1; }

# git reports old=000… for a real no-op update, so the ref filter cannot see it:
# the stamp is what stops the re-evaluation. Barrier: the empty commit after it.
install_hooks
: >"$nix_log"
warm_sha="$(git -C "$container" rev-parse HEAD)"
git -C "$container" update-ref refs/heads/main HEAD
git -C "$container" commit -q --allow-empty -m barrier
fired && settle
! grep -Fq "rev=$warm_sha" "$nix_log" \
  && check "a real no-op ref update re-evaluates nothing" 0 \
  || { cat "$nix_log" >&2; check "a real no-op ref update re-evaluates nothing" 1; }
grep -Fq "rev=$(git -C "$container" rev-parse HEAD)" "$nix_log" \
  && check "the barrier commit after a no-op does evaluate its new rev" 0 \
  || { cat "$nix_log" >&2; check "the barrier commit after a no-op does evaluate its new rev" 1; }

# ── case 13: a ref storm leaves at most one evaluation running ────────────
fresh_repo
install_hooks
armed
head_sha="$(git -C "$container" rev-parse HEAD)"
live_evals() { pgrep -f -- "print-out-paths git.file://$container" 2>/dev/null | wc -l; }
one_eval_at_most() { [ "$(live_evals)" -le 1 ]; }
for _ in 1 2 3 4 5 6; do
  printf '%s\n' "$zero_oid $head_sha refs/heads/main" |
    FIRN_REPO="$container" FAKE_NIX_SLEEP=10 "$hook" committed >/dev/null 2>&1
  rm -f "$stampfile"
done
fired && check "a ref storm does start an evaluation" 0 \
  || check "a ref storm does start an evaluation" 1
wait_for 8 one_eval_at_most \
  && check "a ref storm leaves at most one evaluation running" 0 \
  || { pgrep -af -- "print-out-paths git.file://$container" >&2
       check "a ref storm leaves at most one evaluation running" 1; }
pkill -f -- "print-out-paths git.file://$container" 2>/dev/null
kill_tracked

# ── case 8: an unusable environment is never a caller's problem ───────────
out="$(FIRN_REPO="$scratch/not-a-repo" "$TARGET" --foreground 2>&1)"
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
