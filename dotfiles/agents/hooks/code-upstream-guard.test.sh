#!/usr/bin/env bash
# Hermetic transport tests for code-upstream-guard.sh — the deterministic half
# of "the graph is the editing surface". Covers canonical + legacy in-band
# sentinels, registry-only adoption of the primary checkout, the SAME adoption
# reaching an edit through a durable Git worktree (via shared common-dir +
# repo-relative provenance, no per-worktree paths), false-positive guards, and
# that a denial redirects to the FRAM graph-edit tools.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/code-upstream-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/code-upstream-guard-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

REGISTRY="$SCRATCH/registry"
STATE="$SCRATCH/harness.conf"   # no `guards=off` line -> guards stay LIVE
: >"$STATE"
: >"$REGISTRY"
mkdir -p "$SCRATCH/home"

# --- a primary checkout + a linked durable worktree over the same repo --------
PRIMARY="$SCRATCH/primary"
mkdir -p "$PRIMARY/mod"
git init -q "$PRIMARY"
git -C "$PRIMARY" config user.email test@example.invalid
git -C "$PRIMARY" config user.name test
# schema.bclj carries NO sentinel: its adoption must come purely from the
# registry so the worktree-provenance path is what is under test.
printf '%s\n' '#lang beagle/clj' '(define-target clj)' '(defn f [] 1)' >"$PRIMARY/mod/schema.bclj"
printf '%s\n' '#lang beagle/clj' '(defn g [] 2)' >"$PRIMARY/mod/plain.bclj"
git -C "$PRIMARY" add -A
git -C "$PRIMARY" commit -qm init
WORKTREE="$SCRATCH/worktree"
git -C "$PRIMARY" worktree add -q -b feature "$WORKTREE" >/dev/null 2>&1

# --- ordinary non-git scratch files ------------------------------------------
ORDINARY="$SCRATCH/ordinary.bclj"
printf '%s\n' '#lang beagle/clj' '(defn h [] 3)' >"$ORDINARY"

SENTINEL_CANON="$SCRATCH/canon.bclj"
printf '%s\n' ';; @upstream:graph' '#lang beagle/clj' '(defn a [] 1)' >"$SENTINEL_CANON"

SENTINEL_HEADER="$SCRATCH/header.bclj"    # sentinel after a regenerated header
printf '%s\n' '(define-target clj)' '' ';; @upstream:graph' '(defn a [] 1)' >"$SENTINEL_HEADER"

SENTINEL_LEGACY1="$SCRATCH/legacy1.bclj"
printf '%s\n' ';; @upstream-is-graph' '(defn a [] 1)' >"$SENTINEL_LEGACY1"

SENTINEL_LEGACY2="$SCRATCH/legacy2.bclj"
printf '%s\n' ';; @claim-canonical' '(defn a [] 1)' >"$SENTINEL_LEGACY2"

# marker text present, but only inside the FIRST REAL FORM (a string body) —
# it must NOT self-adopt an ordinary file.
DECOY_BODY="$SCRATCH/decoy-body.bclj"
printf '%s\n' '(def note "see @upstream:graph in the docs")' >"$DECOY_BODY"

# marker text in a comment that trails the first real form (outside the leading
# comment block) — must NOT self-adopt.
DECOY_TRAILING="$SCRATCH/decoy-trailing.bclj"
printf '%s\n' '(defn a [] 1)' ';; @upstream:graph' >"$DECOY_TRAILING"

# ---- harness ----------------------------------------------------------------
event() { # tool_name file_path
  python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"file_path":sys.argv[2]}}))' "$1" "$2"
}

run_hook() { # guards_env payload
  env GRAPH_UPSTREAM_REGISTRY="$REGISTRY" \
    AGENT_NO_AUTHORING_HOOKS="$1" \
    NORTH_HARNESS_STATE="$STATE" \
    HOME="$SCRATCH/home" \
    "$HOOK" >"$SCRATCH/out" 2>"$SCRATCH/err" <<<"$2"
  RUN_STATUS=$?
  RUN_OUT="$(<"$SCRATCH/out")"
}

pass=0
fail=0
ok()     { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
not_ok() { fail=$((fail + 1)); printf 'FAIL  %s\n' "$1" >&2; }

assert_deny() { # label
  if [ "$RUN_STATUS" -ne 0 ]; then not_ok "$1 (status=$RUN_STATUS)"; return; fi
  if printf '%s' "$RUN_OUT" | python3 -c '
import json,sys
h = json.load(sys.stdin)["hookSpecificOutput"]
assert h["hookEventName"] == "PreToolUse"
assert h["permissionDecision"] == "deny"
assert "mcp__fram__" in h["permissionDecisionReason"]
' 2>/dev/null; then ok "$1"; else not_ok "$1 (got: $RUN_OUT)"; fi
}

assert_allow() { # label
  if [ "$RUN_STATUS" -eq 0 ] && [ -z "$RUN_OUT" ]; then ok "$1"
  else not_ok "$1 (status=$RUN_STATUS out: $RUN_OUT)"; fi
}

# ---- sentinel adoption (empty registry) -------------------------------------
: >"$REGISTRY"
run_hook 0 "$(event Edit "$SENTINEL_CANON")";    assert_deny  'canonical ;; @upstream:graph sentinel denies Edit'
run_hook 0 "$(event Write "$SENTINEL_CANON")";   assert_deny  'canonical sentinel denies Write'
run_hook 0 "$(event MultiEdit "$SENTINEL_CANON")"; assert_deny 'canonical sentinel denies MultiEdit'
run_hook 0 "$(event Edit "$SENTINEL_HEADER")";   assert_deny  'canonical sentinel after regenerated header denies Edit'
run_hook 0 "$(event Edit "$SENTINEL_LEGACY1")";  assert_deny  'legacy @upstream-is-graph sentinel still denies (compat)'
run_hook 0 "$(event Edit "$SENTINEL_LEGACY2")";  assert_deny  'legacy @claim-canonical sentinel still denies (compat)'

# denial guidance names the FRAM graph-edit verbs explicitly.
run_hook 0 "$(event Edit "$SENTINEL_CANON")"
if [[ "$RUN_OUT" == *'mcp__fram__set-body'* && "$RUN_OUT" == *'mcp__fram__rename-def'* ]]; then
  ok 'denial reason redirects to FRAM graph-edit tools'
else
  not_ok "denial reason redirects to FRAM graph-edit tools (got: $RUN_OUT)"
fi

# ---- false positives (empty registry) ---------------------------------------
run_hook 0 "$(event Edit "$ORDINARY")";         assert_allow 'ordinary non-adopted Beagle file is allowed'
run_hook 0 "$(event Edit "$DECOY_BODY")";       assert_allow 'marker text inside a string body does not self-adopt'
run_hook 0 "$(event Edit "$DECOY_TRAILING")";   assert_allow 'marker in a comment after the first form does not self-adopt'
run_hook 0 "$(event Read "$SENTINEL_CANON")";   assert_allow 'Read of an adopted file is never denied'
run_hook 1 "$(event Edit "$SENTINEL_CANON")";   assert_allow 'killswitch (AGENT_NO_AUTHORING_HOOKS=1) no-ops the guard'

# ---- registry-only adoption of the primary checkout -------------------------
printf '%s\n' "$PRIMARY/mod/schema.bclj" >"$REGISTRY"
run_hook 0 "$(event Edit "$PRIMARY/mod/schema.bclj")";  assert_deny  'registry-only primary path denies (exact match)'
run_hook 0 "$(event Edit "$PRIMARY/mod/plain.bclj")";   assert_allow 'unrelated primary Beagle file remains allowed'

# ---- durable-worktree adoption via shared Git provenance --------------------
# The registry names ONLY the primary checkout; editing the SAME repo-relative
# file inside the linked worktree must still be denied — no worktree path listed.
run_hook 0 "$(event Edit "$WORKTREE/mod/schema.bclj")"; assert_deny  'durable-worktree edit of the adopted file denies via provenance'
run_hook 0 "$(event Edit "$WORKTREE/mod/plain.bclj")";  assert_allow 'unrelated worktree file (different repo-relative path) remains allowed'

# a registry row naming a path in an UNRELATED repo must not leak by provenance.
OTHER="$SCRATCH/other"
mkdir -p "$OTHER/mod"
git init -q "$OTHER"
git -C "$OTHER" config user.email test@example.invalid
git -C "$OTHER" config user.name test
printf 'x\n' >"$OTHER/mod/schema.bclj"
git -C "$OTHER" add -A && git -C "$OTHER" commit -qm init
printf '%s\n' "$OTHER/mod/schema.bclj" >"$REGISTRY"
run_hook 0 "$(event Edit "$WORKTREE/mod/schema.bclj")"; assert_allow 'same repo-relative path in a different repo does not match'

printf '\n%d/%d passed\n' "$pass" "$((pass + fail))"
[ "$fail" -eq 0 ]
