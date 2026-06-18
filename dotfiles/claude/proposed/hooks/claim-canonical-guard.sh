#!/usr/bin/env bash
# PreToolUse guard — the DETERMINISTIC half of "the graph is the editing surface".
# ============================================================================
# THIS IS A PROPOSED ARTIFACT. It is NOT wired into settings.json. Activate it
# DELIBERATELY (see proposed/README in this directory) once a module has actually
# been ADOPTED as claim-canonical. Until then it must NOT exist in the live hooks
# block, because there is currently NO adopted module and it would have nothing to
# guard (and a bug here would block ALL edits).
#
# WHAT IT DOES
#   On Edit | Write | MultiEdit it reads tool_input.file_path from the hook's stdin
#   JSON and asks: is THIS file claim-canonical? If and only if it is, it RETURNS a
#   PreToolUse permissionDecision of "deny" with a reason that redirects the agent to
#   the graph-edit MCP tools. For every other file it returns NOTHING (empty stdout),
#   which Claude Code treats as "no opinion" — ordinary edits sail through untouched.
#
#   PreToolUse is the ONLY hook event that can REFUSE a call: permissionDecision:deny
#   short-circuits the tool before it runs. PostToolUse fires AFTER the write — too
#   late to keep text from becoming a second source of truth. So enforcement lives here.
#
# SCOPING — why this never blocks ordinary edits (the critical requirement)
#   The guard is FAIL-OPEN and CLOSED-LIST. A file is claim-canonical iff it is named
#   in the explicit all\-list resolved by is_claim_canonical() below. The list starts
#   as EXACTLY ONE adopted module. A file that is missing, unreadable, not in the
#   list, or that the check errors on -> the script prints nothing and exits 0, i.e.
#   the edit is ALLOWED. The deny path is reached only on a positive, explicit match.
#   There is no glob like "*.bclj" — adoption is per-file and opt-in, mirroring the
#   move-3 "capability vs adoption" line (code-as-claims/README.md:42).
#
# THE MARKER (defined here — none exists in the repo yet)
#   Adoption is recorded two redundant ways; a file is canonical if EITHER holds:
#     (1) the file's path appears (one absolute path per line, blank/`#` lines
#         ignored) in the registry file $CLAIM_CANONICAL_REGISTRY
#         (default: ~/.config/fram/claim-canonical-files), OR
#     (2) the file's FIRST LINE contains the in-band sentinel  ;; @claim-canonical
#         (a Beagle line comment, so it survives the lossless round-trip as a
#         comment node and recompiles cleanly).
#   (1) is the source of truth for the guard (cheap, no file read needed if absent);
#   (2) lets a file self-declare and travels with the file. Adoption = add the path
#   to the registry (and optionally stamp line 1). De-adoption = remove it. Nothing
#   about the guard is implicit.
# ============================================================================
set -uo pipefail

REGISTRY="${CLAIM_CANONICAL_REGISTRY:-$HOME/.config/fram/claim-canonical-files}"

# Resolve the redirect verbs once (kept in one place so the deny reason stays honest
# about what the agent should call instead of Edit/Write).
read -r -d '' DENY_REASON <<'EOF'
This file is CLAIM-CANONICAL: its source of truth is the Fram claim graph, not its
text. A text Edit/Write would desync the graph and is refused. Author it as a GRAPH
EDIT via the fram MCP tools instead:
  - mcp__fram__add-def     — add a new top-level def (upsert-form, new name)
  - mcp__fram__set-body    — replace a defn's body
  - mcp__fram__rename      — rename a def (O(1), scope-correct via refers_to)
Each is recompile-gated and fail-closed; the regenerated text is a downstream view.
See the claim-canonical-authoring skill. (To edit as text anyway you must first
de-adopt the file from the claim-canonical registry — a deliberate workflow change.)
EOF

# python3 does the JSON I/O (jq is not available in this environment; the existing
# beagle-session-start.sh and the .nix PostToolUse precedent both use python3 the
# same way). The script reads the PreToolUse stdin envelope, extracts file_path,
# tests membership, and emits either the deny decision or nothing.
#
# NOTE: the python source goes in a VARIABLE and is run via `python3 -c "$PY"` — NOT
# `python3 - <<heredoc`. A heredoc would occupy stdin, leaving no channel for the
# hook's JSON envelope (sys.stdin must stay the harness's PreToolUse payload). Args
# carry the registry path + deny reason so no shell interpolation lands inside python.
read -r -d '' PY <<'PYEOF' || true
import sys, json, os

registry_path = sys.argv[1]
deny_reason   = sys.argv[2]

def fail_open():
    # No opinion -> allow. Empty stdout, exit 0.
    sys.exit(0)

try:
    data = json.load(sys.stdin)
except Exception:
    fail_open()

tool_input = data.get("tool_input", {}) or {}
fp = tool_input.get("file_path", "") or ""
if not fp:
    fail_open()
fp = os.path.abspath(fp)

def in_registry(path):
    try:
        with open(registry_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if os.path.abspath(os.path.expanduser(line)) == path:
                    return True
    except FileNotFoundError:
        return False
    except Exception:
        return False
    return False

def self_declared(path):
    # In-band sentinel `;; @claim-canonical` in the file's LEADING comment block.
    # Scanned over the first few lines (not just line 1) because the lossless
    # round-trip's --render emits a `(define-target clj)` header + blank line ahead
    # of the source's leading comments, so a sentinel comment lands ~line 3 after a
    # regenerate. We stop at the first non-comment, non-blank, non-header line so the
    # scan stays cheap and never reads code bodies.
    try:
        with open(path, "r") as f:
            for _ in range(8):
                line = f.readline()
                if line == "":
                    break
                s = line.strip()
                if "@claim-canonical" in s:
                    return True
                # keep scanning through the header / lang line / comments / blanks
                if s == "" or s.startswith(";;") or s.startswith("#lang") or s.startswith("(define-target"):
                    continue
                break  # first real form — sentinel must precede it
    except Exception:
        return False
    return False

canonical = in_registry(fp) or self_declared(fp)

if not canonical:
    fail_open()

# POSITIVE MATCH -> deny this Edit/Write/MultiEdit and redirect to the graph verbs.
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": deny_reason,
    }
}))
sys.exit(0)
PYEOF

exec python3 -c "$PY" "$REGISTRY" "$DENY_REASON"
