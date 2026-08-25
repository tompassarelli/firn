#!/usr/bin/env bash
# Tests for launch-critical-worktree-guard.sh.
#
# The two properties that matter, in order:
#   1. It denies writes to the PRIMARY checkout of a launch-critical repo.
#   2. It never denies anything else — a guard that blocks ordinary work gets
#      switched off, and then it protects nothing. The worktree cases and the
#      ~/code/north-data sibling are the ones that would regress in practice.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/launch-critical-worktree-guard.sh"
pass=0 fail=0

# Guards are OFF in harness.conf on this machine, so every case forces them live
# with AGENT_NO_AUTHORING_HOOKS=0. That is the force-live value, not the
# disable value — see lib/authoring-killswitch.sh.
decide() {
  printf '{"tool_input":{"file_path":"%s"}}' "$1" \
    | AGENT_NO_AUTHORING_HOOKS=0 LAUNCH_CRITICAL_CODE_ROOT="${ROOT:-}" "$HOOK" 2>/dev/null
}

bash_decide() { # bash_decide <command> <cwd>
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$2" \
    | AGENT_NO_AUTHORING_HOOKS=0 LAUNCH_CRITICAL_CODE_ROOT="${ROOT:-}" "$HOOK" 2>/dev/null
}

apply_decide() { # apply_decide <envelope-with-\n> <cwd>
  printf '{"tool_name":"apply_patch","tool_input":{"input":"%s"},"cwd":"%s"}' "$1" "$2" \
    | AGENT_NO_AUTHORING_HOOKS=0 LAUNCH_CRITICAL_CODE_ROOT="${ROOT:-}" "$HOOK" 2>/dev/null
}

check() { # check <expect deny|allow> <path> <why>
  local want=$1 path=$2 why=$3 out got
  out="$(decide "$path")"
  case "$out" in
    *'"permissionDecision": "deny"'*|*'"permissionDecision":"deny"'*) got=deny ;;
    "") got=allow ;;
    *) got="malformed:$out" ;;
  esac
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  want=%s got=%s  %s\n      %s\n' "$want" "$got" "$path" "$why" >&2
  fi
}

# --- 1. primaries are denied -------------------------------------------------
check deny "$HOME/code/north/main/cli/dashboard-cli.clj" "north primary"
check deny "$HOME/code/beagle/main/bin/beagle-build"     "beagle primary"
check deny "$HOME/code/nixos-config/main/flake.nix"      "nixos-config primary"
check deny "$HOME/code/beagle/main"                      "the checkout root itself, not only files under it"

# --- 2. the sanctioned destinations are NOT denied ---------------------------
check allow "$HOME/code/beagle/worktrees/topic/server.rkt"     "a lane is where agents are TOLD to work"
check allow "/tmp/north-lane-abc123/cli/x.clj"                 "managed lane worktree"
check allow "/tmp/beagle-store-indexed-show-lane/bin/beagle-store-cli.clj"    "ad-hoc lane worktree"

# T4 — the pre-filter gate. This payload contains NO literal `main` and names no
# launch-critical container, so without `*pins*` in the cheap bash pre-filter the
# guard exits 0 with empty stdout and the harness reads that as "no opinion":
# silent, error-free non-enforcement of the entire pin rule. It must run WITHOUT
# a fixture code root — the fixture root skips the pre-filter entirely, so a
# fixture-only pin case proves nothing about production.
check deny "$HOME/code/gjoa/pins/0123456789abcdef0123456789abcdef01234567/index.html" \
  "a pin write with no 'main' in the payload must still reach the decision"

# --- 2b. gitignored paths are exempt ----------------------------------------
# A gitignored file can never make the tree tracked-dirty, so it cannot cause
# either failure this guard prevents (a runtime reading a dirty Beagle Store checkout,
# or a rebuild publishing only committed state). Blocking them bought
# nothing and stopped agents writing docs/private/ notes — which is exactly
# where policy says internal notes belong.
check allow "$HOME/code/north/main/docs/private/overnight-notes.md" \
  "docs/private is gitignored: cannot dirty the tree, and policy REQUIRES notes there"
check allow "$HOME/code/beagle/main/docs/private/scratch.md" \
  "same exemption in beagle"

# ...but a TRACKED file in the same repo is still denied.
check deny "$HOME/code/north/main/cli/trace-cli.clj" \
  "tracked source in a launch-critical primary stays denied"

# --- 3. near-miss paths must not be swept in ---------------------------------
# north-data is a SIBLING of north; a naive prefix test without a separator
# check denies it and breaks all runtime-state writes.
check allow "$HOME/code/north-data/threads/x.md"   "north-data is runtime state, not the north repo"
check allow "$HOME/code/unrelated-project/x.clj"   "an unrelated project stays writable"
check allow "$HOME/code/gjoa/x.clj"                "unrelated project"
check allow "/tmp/scratch.txt"                     "outside ~/code entirely"

check deny "$HOME/code/nixos-config/main/modules/x.nix" "nixos-config primary, the 2026-07-30 near-miss"

# --- 3b. every container's main, on a fixture layout -------------------------
# Dynamic detection: a project this guard has never heard of, its client-nested
# sibling, and the near-misses that must stay writable. The container's three
# slots are all present, because the whole rule is positional.
FIXTURE="$(mktemp -d)"
ROOT="$FIXTURE/code"
PIN_OID=0123456789abcdef0123456789abcdef01234567
NEXT_PIN_OID=89abcdef0123456789abcdef0123456789abcdef
PIN_SIDECAR="$ROOT/proj/pins/$PIN_OID.pin"
mkdir -p "$ROOT/proj/main/.git" "$ROOT/proj/worktrees/x" "$ROOT/proj/worktrees/main" \
         "$ROOT/proj/pins/$PIN_OID" \
         "$ROOT/client/msa/app/main/.git" "$ROOT/resources/upstream/main/.git" \
         "$ROOT/runtime-data/.git"
printf 'The vendored upstream checkout. Consumers: gjoa:.envrc, the docs build.\n' \
  > "$PIN_SIDECAR"
# A real repo inside the pin: `git check-ignore` needs one for the T6 case, and
# both live pins are exactly this shape — full of ignored build artifacts.
git init -q "$ROOT/proj/pins/$PIN_OID" 2>/dev/null
printf 'build/\n' > "$ROOT/proj/pins/$PIN_OID/.gitignore"
mkdir -p "$ROOT/proj/pins/$PIN_OID/build"

check deny  "$ROOT/proj/main/src/x.py"                "an unheard-of project's main"
check deny  "$ROOT/client/msa/app/main/src/x.py"      "a client project's nested main"
check allow "$ROOT/proj/worktrees/x/src/x.py"         "a lane is the destination (T1)"
check allow "$ROOT/proj/worktrees/main/x.py"          "a lane whose slug is literally 'main' is still a lane (T8)"
check allow "$ROOT/proj/scratch.txt"                  "the container root is not a checkout"
check allow "$ROOT/proj/worktrees"                    "the worktrees/ root itself must stay writable (T5)"
check allow "$ROOT/proj/pins"                         "the pins/ root itself must stay writable (T5)"
check deny  "$ROOT/proj/pins/$PIN_OID/index.html"     "a content-addressed pin is externally consumed (T3)"
check allow "$ROOT/proj/pins/$PIN_OID.pin"            "the manifest is agent-writable metadata (T7, AMB-6 as amended)"
check deny  "$ROOT/proj/pins/$PIN_OID/nested.pin"     "a .pin path inside the checkout is content, still denied"
check deny  "$ROOT/proj/pins/$PIN_OID/build/out.js"   "gitignore does NOT exempt a pin (T6)"
check allow "$ROOT/runtime-data/state.json"           "bare .git, no main/: runtime state stays writable"
check allow "$ROOT/resources/upstream/main/README.md" "resource checkouts are read-only context"

# The pin deny names the manifest and the immutable replacement route. The new
# worktree is cut from main, never from the pin being protected.
pin_out="$(decide "$ROOT/proj/pins/$PIN_OID/index.html")"
case "$pin_out" in
  *"pins/$PIN_OID.pin"*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  the pin deny must name the same-hash .pin sidecar" >&2 ;;
esac
case "$pin_out" in
  *"the docs build"*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  the pin deny must name the manifest's consumers" >&2 ;;
esac
case "$pin_out" in
  *"worktree add --detach"*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  the pin deny must name new hash-pin creation" >&2 ;;
esac
case "$pin_out" in
  *"pin-retire"*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  the pin deny must name verified orphan retirement" >&2 ;;
esac
case "$pin_out" in
  *"checkout REF"*) fail=$((fail + 1)); echo "FAIL  a pin deny must not sanction in-place checkout" >&2 ;;
  *) pass=$((pass + 1)) ;;
esac
# ...and a main deny must name the NEW lane destination.
case "$(decide "$ROOT/proj/main/src/x.py")" in
  *"worktrees/SLUG"*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  a main deny must name <container>/worktrees/SLUG" >&2 ;;
esac

# Bash entrance on the same fixture: WIP destruction vs the landing flow.
case "$(bash_decide "git -C $ROOT/proj/main reset --hard HEAD~1" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  reset --hard in a container main must be denied" >&2 ;;
esac
case "$(bash_decide "git stash" "$ROOT/proj/main")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  stash in a container main must be denied" >&2 ;;
esac
case "$(bash_decide "git -C $ROOT/proj/worktrees/x reset --hard HEAD~1" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  reset --hard in a lane must be allowed" >&2 ;;
esac
# T15 — pin HEAD is immutable; advance by creating a different hash path.
case "$(bash_decide "git -C $ROOT/proj/pins/$PIN_OID checkout 3e942ba2" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  checkout must not change pin HEAD (T15)" >&2 ;;
esac
case "$(bash_decide "git -C \\\"$ROOT/proj/pins/$PIN_OID\\\" checkout 3e942ba2" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  a quoted -C path must not hide pin checkout" >&2 ;;
esac
case "$(bash_decide "git -C '$ROOT/proj/pins/$PIN_OID' switch --detach 3e942ba2" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  a quoted -C path must not hide pin switch" >&2 ;;
esac
case "$(bash_decide "(git -C $ROOT/proj/pins/$PIN_OID checkout deadbeef)" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  a subshell must not hide pin checkout" >&2 ;;
esac
case "$(bash_decide "echo \$(git -C $ROOT/proj/pins/$PIN_OID checkout deadbeef)" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  command substitution must not hide pin checkout" >&2 ;;
esac
case "$(bash_decide "sh -c 'git -C $ROOT/proj/pins/$PIN_OID checkout deadbeef'" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  sh -c must not hide pin checkout" >&2 ;;
esac
case "$(bash_decide "bash -lc 'git -C $ROOT/proj/pins/$PIN_OID checkout deadbeef'" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  bash -lc must not hide pin checkout" >&2 ;;
esac
case "$(bash_decide "bash -ec 'git -C $ROOT/proj/pins/$PIN_OID checkout deadbeef'" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  bash -ec must not hide pin checkout" >&2 ;;
esac
case "$(bash_decide "sh -c -- 'git -C $ROOT/proj/pins/$PIN_OID checkout deadbeef'" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  sh -c -- must not hide pin checkout" >&2 ;;
esac
case "$(bash_decide "echo sh -c 'git -C $ROOT/proj/pins/$PIN_OID checkout deadbeef'" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  sh passed to echo must remain data" >&2 ;;
esac
case "$(bash_decide "git -C $ROOT/proj/pins/$PIN_OID switch --detach 3e942ba2" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  switch must not change pin HEAD" >&2 ;;
esac
case "$(bash_decide "git -C $ROOT/proj/pins/$PIN_OID checkout -- ." "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  a working-tree checkout in a pin must deny" >&2 ;;
esac
case "$(bash_decide "git -C $ROOT/proj/pins/$PIN_OID commit -am x" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  committing in a pin must be denied" >&2 ;;
esac
case "$(bash_decide "rm $PIN_SIDECAR" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  raw rm must not erase a live pin sidecar" >&2 ;;
esac
case "$(bash_decide "unlink $PIN_SIDECAR" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  raw unlink must not erase a live pin sidecar" >&2 ;;
esac
case "$(bash_decide "mv $PIN_SIDECAR $PIN_SIDECAR.bak" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  raw mv must not rename a live pin sidecar" >&2 ;;
esac
case "$(bash_decide "pin-retire --consumer-main $ROOT/proj/main -- $ROOT/proj/pins/$PIN_OID" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  direct pin-retire must be allowed" >&2 ;;
esac
case "$(bash_decide "pin-retire --consumer-main $ROOT/proj/main -- \$(git -C $ROOT/proj/pins/$PIN_OID checkout deadbeef)" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  pin-retire must not hide command-substitution pin mutation" >&2 ;;
esac
case "$(bash_decide "pin-retire --consumer-main $ROOT/proj/main -- $ROOT/proj/pins/$PIN_OID; git -C $ROOT/proj/pins/$PIN_OID checkout deadbeef" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  pin-retire must not shield a later pin mutation" >&2 ;;
esac
case "$(bash_decide "git -C $ROOT/proj/main worktree add --detach $ROOT/proj/pins/$NEXT_PIN_OID $NEXT_PIN_OID" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  creating a replacement hash-named pin from main must pass" >&2 ;;
esac
case "$(bash_decide "git -C '$ROOT/proj/pins/$PIN_OID' worktree add --detach $ROOT/proj/pins/$NEXT_PIN_OID $NEXT_PIN_OID" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  an existing pin cannot source worktree creation" >&2 ;;
esac
case "$(bash_decide "git -C $ROOT/proj/worktrees/x commit -am x ; git -C '$ROOT/proj/pins/$PIN_OID' checkout deadbeef" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  a lane mutation must not hide later pin checkout" >&2 ;;
esac
case "$(bash_decide "git -C $ROOT/proj/worktrees/x commit -am x ; git -C $ROOT/proj/main worktree remove $ROOT/proj/pins/$PIN_OID" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  a lane mutation must not hide later pin removal" >&2 ;;
esac
case "$(bash_decide "echo 'example; git -C $ROOT/proj/pins/$PIN_OID checkout deadbeef' >> /tmp/pin-notes" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  a semicolon inside quoted prose must stay prose" >&2 ;;
esac
case "$(bash_decide "echo 'example && git -C $ROOT/proj/pins/$PIN_OID checkout deadbeef' >> /tmp/pin-notes" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  an and-list inside quoted prose must stay prose" >&2 ;;
esac
case "$(bash_decide "git -C $ROOT/proj/main worktree remove $ROOT/proj/pins/$PIN_OID" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  worktree remove must not delete a pin" >&2 ;;
esac
case "$(bash_decide "git -C $ROOT/proj/main worktree move $ROOT/proj/pins/$PIN_OID $ROOT/proj/pins/$NEXT_PIN_OID" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  worktree move must not rename a pin" >&2 ;;
esac
case "$(bash_decide "git -C $ROOT/proj/main worktree move $ROOT/proj/worktrees/x $ROOT/proj/worktrees/y" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  worktree move must remain available for a lane" >&2 ;;
esac
case "$(bash_decide "git -C $ROOT/proj/main merge --ff-only slug && git -C $ROOT/proj/main branch -d slug && git -C $ROOT/proj/main worktree prune && safe-push --to main" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  the landing flow must run from main" >&2 ;;
esac
# The canonical lane-creation sequence the deny message itself prints (T14).
case "$(bash_decide "mkdir -p $ROOT/proj/worktrees && git -C $ROOT/proj/main worktree add $ROOT/proj/worktrees/slug -b slug" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  the advised lane-creation sequence must be allowed (T14)" >&2 ;;
esac
# wt-rescue is the sanctioned remediation the deny message points at.
case "$(bash_decide "wt-rescue $ROOT/proj/main" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  wt-rescue must be allowed against a main" >&2 ;;
esac
case "$(bash_decide "git -C $ROOT/proj/main checkout -- ." "$HOME")" in
  *wt-rescue*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  checkout -- in a main must deny and name wt-rescue" >&2 ;;
esac
case "$(apply_decide "*** Begin Patch\n*** Update File: $ROOT/proj/main/src/x.py\n@@\n-a\n+b\n*** End Patch" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  apply_patch into a container main must be denied" >&2 ;;
esac
case "$(apply_decide "*** Begin Patch\n*** Update File: $ROOT/proj/worktrees/x/src/x.py\n@@\n-a\n+b\n*** End Patch" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  apply_patch into a lane must be allowed" >&2 ;;
esac
case "$(apply_decide "*** Begin Patch\n*** Update File: $ROOT/proj/pins/$PIN_OID/x.py\n@@\n-a\n+b\n*** End Patch" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  apply_patch into a pin must be denied" >&2 ;;
esac
case "$(apply_decide "*** Begin Patch\n*** Delete File: $PIN_SIDECAR\n*** End Patch" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  apply_patch Delete File must not erase a live pin sidecar" >&2 ;;
esac
case "$(apply_decide "*** Begin Patch\n*** Update File: $PIN_SIDECAR\n*** Move to: $PIN_SIDECAR.bak\n@@\n-old\n+new\n*** End Patch" "$HOME")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  apply_patch Move to must not rename a live pin sidecar" >&2 ;;
esac
case "$(apply_decide "*** Begin Patch\n*** Update File: $PIN_SIDECAR\n@@\n-old\n+new\n*** End Patch" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  apply_patch may update live pin consumer metadata" >&2 ;;
esac
case "$(apply_decide "*** Begin Patch\n*** Update File: $PIN_SIDECAR\n@@\n-old\n+new\n*** Update File: $ROOT/proj/worktrees/actual/move-me\n*** Move to: $ROOT/proj/worktrees/actual/moved\n@@\n-old\n+new\n*** End Patch" "$HOME")" in
  "") pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  an unrelated move must not turn a sidecar update into a removal" >&2 ;;
esac
case "$(apply_decide "*** Begin Patch\n*** Nonsense\n*** End Patch" "$ROOT/proj/main")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  malformed apply_patch must fail closed" >&2 ;;
esac

rm -rf "${FIXTURE:?}"
unset ROOT FIXTURE pin_out

case "$(apply_decide "*** Begin Patch\n*** Update File: code/north/main/cli/x.clj\n@@\n-a\n+b\n*** End Patch" "/home/tom")" in
  *'"deny"'*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); echo "FAIL  relative apply_patch must bypass the cheap pre-filter" >&2 ;;
esac

# --- 4. fail-open ------------------------------------------------------------
check allow "" "empty file_path"
printf 'not json at all' | AGENT_NO_AUTHORING_HOOKS=0 "$HOOK" >/dev/null 2>&1 \
  && pass=$((pass + 1)) \
  || { fail=$((fail + 1)); echo "FAIL  malformed payload must exit 0" >&2; }

# --- 5. kill-switch ----------------------------------------------------------
# The path must be one the guard WOULD deny, or the case passes for the wrong
# reason: `~/code/beagle/x.rkt` is the container root and is not protected.
out="$(printf '{"tool_input":{"file_path":"%s"}}' "$HOME/code/beagle/main/x.rkt" \
       | AGENT_NO_AUTHORING_HOOKS=1 "$HOOK" 2>/dev/null)"
if [ -z "$out" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL  AGENT_NO_AUTHORING_HOOKS=1 must disable the guard" >&2
fi

# --- 6. cost -----------------------------------------------------------------
# This fires on EVERY Edit/Write. An unconditional python3 start measured 4.6ms
# per call; the bash pre-filter must keep the common path well under that.
start=$(date +%s%N)
for _ in $(seq 50); do
  printf '{"tool_input":{"file_path":"/tmp/x.txt"}}' \
    | AGENT_NO_AUTHORING_HOOKS=0 "$HOOK" >/dev/null 2>&1
done
per_ms=$(( ( $(date +%s%N) - start ) / 50 / 1000000 ))
if [ "$per_ms" -le 25 ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL  allow path ${per_ms}ms/call — too slow for PreToolUse" >&2
fi

# A path under ~/code with no `main` component cannot be protected either, so
# the second pre-filter stage must keep it off python3 as well.
start=$(date +%s%N)
for _ in $(seq 50); do
  printf '{"tool_input":{"file_path":"%s/code/gjoa/docs/x.md"}}' "$HOME" \
    | AGENT_NO_AUTHORING_HOOKS=0 "$HOOK" >/dev/null 2>&1
done
per_ms=$(( ( $(date +%s%N) - start ) / 50 / 1000000 ))
if [ "$per_ms" -le 25 ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL  ~/code non-main path ${per_ms}ms/call — pre-filter regressed" >&2
fi

# T24 — the cost of widening the pre-filter with `*pins*`. A pin payload is a
# DENY, so it pays the python3 decision by design; the 25ms allow-path budget
# above was never the deny budget. What must hold is that the pin rule costs no
# MORE than the main rule already does — measured against a main deny in the
# same run, on the same machine, so the comparison is not a wall-clock guess.
deny_ms() { # deny_ms <path>
  local start
  start=$(date +%s%N)
  for _ in $(seq 20); do
    printf '{"tool_input":{"file_path":"%s"}}' "$1" \
      | AGENT_NO_AUTHORING_HOOKS=0 "$HOOK" >/dev/null 2>&1
  done
  echo $(( ( $(date +%s%N) - start ) / 20 / 1000000 ))
}
main_ms="$(deny_ms "$HOME/code/north/main/cli/x.clj")"
pins_ms="$(deny_ms "$HOME/code/gjoa/pins/0123456789abcdef0123456789abcdef01234567/index.html")"
if [ "$pins_ms" -le $((main_ms + 20)) ]; then pass=$((pass + 1)); else
  fail=$((fail + 1))
  echo "FAIL  pin deny ${pins_ms}ms/call vs main deny ${main_ms}ms/call — the pin path costs more than the rule it mirrors" >&2
fi

printf '%s\n' "launch-critical-worktree-guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
