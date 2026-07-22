#!/usr/bin/env bash
# PreToolUse guard — the DETERMINISTIC half of "the graph is the editing surface".
# ============================================================================
# STATUS: LIVE. Wired into settings.json (PreToolUse, Edit|Write|MultiEdit) and
# ACTIVE as of 2026-06-20. Adopted graph-upstream modules are guarded right now:
# fram/src/fram/schema.bclj is the first adopted module (in the registry below).
# To run a clean-room/experiment session WITHOUT this guard, engage the
# kill-switch below — persistent `north config guards off`, or launch with
# CLAUDE_NO_AUTHORING_HOOKS set to any value but 0/false — do NOT un-wire it.
# (History: this began as a proposed/un-wired artifact; it was armed in
# nixos-config b1bd624 once schema.bclj was adopted.)
#
# WHAT IT DOES
#   On Edit | Write | MultiEdit it reads tool_input.file_path from the hook's stdin
#   JSON and asks: is THIS file graph-upstream? If and only if it is, it RETURNS a
#   PreToolUse permissionDecision of "deny" with a reason that redirects the agent to
#   the graph-edit MCP tools. For every other file it returns NOTHING (empty stdout),
#   which Claude Code treats as "no opinion" — ordinary edits sail through untouched.
#
#   PreToolUse is the ONLY hook event that can REFUSE a call: permissionDecision:deny
#   short-circuits the tool before it runs. PostToolUse fires AFTER the write — too
#   late to keep text from becoming a second source of truth. So enforcement lives here.
#
# SCOPING — why this never blocks ordinary edits (the critical requirement)
#   The guard is FAIL-OPEN and CLOSED-LIST. A file is graph-upstream iff it is named
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
#         ignored) in the registry file $GRAPH_UPSTREAM_REGISTRY
#         (default: ~/.config/fram/graph-upstream-files). A row is matched by
#         REALPATH identity (so a symlink alias to an adopted file cannot bypass)
#         OR by shared Git provenance from a TRUSTED git (same `--git-common-dir`
#         + repo-relative path), so a row naming only the primary checkout also
#         covers an edit of the same file reached through a durable linked
#         worktree — no per-worktree paths are enumerated, and a missing/hostile
#         git can never let a direct or aliased edit of an adopted file through, OR
#     (2) the file's LEADING COMMENT BLOCK carries the in-band directive
#         ;; @upstream:graph  (the canonical marker in code-as-facts SKILL.md;
#         the legacy `;; @upstream-is-graph` / `;; @claim-canonical` spellings
#         stay recognized for compatibility). It is a Beagle line comment, so it
#         survives the lossless round-trip as a comment node and recompiles
#         cleanly. Only a leading `;;` comment whose payload IS the marker (with
#         optional suffix prose) counts — an explanatory MENTION of the marker,
#         or marker-like text in a string or code body, never self-adopts.
#   (1) is the source of truth for the guard (cheap, no file read needed if absent);
#   (2) lets a file self-declare and travels with the file. Adoption = add the path
#   to the registry (and optionally stamp the sentinel). De-adoption = remove it.
#   Nothing about the guard is implicit.
# ============================================================================
set -uo pipefail

# Drain before every decision, including the kill-switch. Keep active-path input
# memory-bounded; an oversized envelope follows the existing malformed fail-open.
capture_hook_stdin() {
  local chunk status keep
  local LC_ALL=C
  payload=""
  payload_oversized=0
  while :; do
    chunk=""
    IFS= read -r -N 65536 chunk
    status=$?
    if [ -n "$chunk" ]; then
      keep=$((1048576 - ${#payload}))
      [ "$keep" -le 0 ] || payload+="${chunk:0:$keep}"
      [ "${#chunk}" -le "$keep" ] || payload_oversized=1
    fi
    [ "$status" -eq 0 ] || break
  done
}
capture_hook_stdin

# Clean-room / experiment kill-switch (opt-OUT). When guards are OFF this guard
# no-ops (exit 0 = allow the edit), letting a controlled run — e.g. the
# concurrent-authoring experiment — pin a hook-free, confound-free session
# surface WITHOUT editing settings.json. Engaged two ways: persistent
# `north config guards off` (state, live), or env CLAUDE_NO_AUTHORING_HOOKS
# (any value but 0/false; 0/false forces guards live). Neither = guard active.
# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0
[ "$payload_oversized" -eq 0 ] || exit 0

REGISTRY="${GRAPH_UPSTREAM_REGISTRY:-$HOME/.config/fram/graph-upstream-files}"

# Resolve the redirect verbs once (kept in one place so the deny reason stays honest
# about what the agent should call instead of Edit/Write).
read -r -d '' DENY_REASON <<'EOF' || true
This file's UPSTREAM is the GRAPH: the code lives in the Fram fact graph; this
text is GENERATED output. A text Edit/Write would desync the graph and is refused. Author it as a GRAPH
EDIT via the fram MCP tools instead:
  - mcp__fram__add-def     — add a new top-level def (upsert-form, new name)
  - mcp__fram__set-body    — replace a defn's body
  - mcp__fram__rename-def  — rename a def (O(1), scope-correct via refers_to)
Each is recompile-gated and fail-closed; the regenerated text is a downstream view.
See the code-as-facts skill. (To edit as text anyway you must first
de-adopt the file from the graph-upstream registry — a deliberate workflow change.)
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
import sys, json, os, re, subprocess, shutil, getpass, pwd

registry_path = sys.argv[1]
deny_reason   = sys.argv[2]

def fail_open():
    # No opinion -> allow. Empty stdout, exit 0.
    sys.exit(0)

def _trusted_git():
    # Resolve `git` from a fixed allow-list of MANAGED bin dirs, never the
    # ambient inherited PATH. A per-session PATH entry or a `./git` planted in a
    # repo working directory therefore cannot impersonate git and lie about
    # provenance (hostile-Git). The real home comes from the uid via pwd, not the
    # $HOME env (which a caller — or our own tests — may override), so the trusted
    # location holds regardless of a spoofed HOME. Returns None when no managed
    # git is found, so provenance fails OPEN rather than trusting an untrusted one.
    try:
        real_home = pwd.getpwuid(os.geteuid()).pw_dir
    except Exception:
        real_home = os.path.expanduser("~")
    try:
        user = getpass.getuser()
    except Exception:
        user = ""
    candidates = [
        "/run/wrappers/bin",
        "/run/current-system/sw/bin",
        os.path.join(real_home, ".nix-profile/bin"),
        ("/etc/profiles/per-user/%s/bin" % user) if user else "",
        "/nix/var/nix/profiles/default/bin",
        "/usr/bin",
        "/bin",
    ]
    trusted = os.pathsep.join(d for d in candidates if d and os.path.isdir(d))
    return shutil.which("git", path=trusted) if trusted else None

_GIT = _trusted_git()
# Clean environment for git: strips any hostile GIT_DIR/GIT_COMMON_DIR/GIT_WORK_TREE
# and the ambient PATH so discovery is driven only by `-C <dir>`.
_GIT_ENV = {
    "PATH": os.path.dirname(_GIT) if _GIT else "/bin",
    "HOME": os.environ.get("HOME", ""),
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_TERMINAL_PROMPT": "0",
}

def git_provenance(path):
    # Identity a registry row and a target file share when they name the SAME
    # logical file, even across a durable Git worktree: (shared common git dir,
    # repo-relative path). `--git-common-dir` is shared by the primary checkout
    # and every linked worktree, so a registry row that names only the primary
    # checkout still matches an edit of the same file inside a worktree — with no
    # per-worktree path enumeration. realpath() resolves symlink aliases so an
    # alias to an adopted file shares provenance with its target. Returns None
    # when git is untrusted/absent or the path is not inside a Git repo, so a bad
    # probe fails OPEN, never denies (no false adoption outside Git).
    if _GIT is None:
        return None
    rp = os.path.realpath(path)
    d = os.path.dirname(rp) or "."
    if not os.path.isdir(d):
        return None
    def git(args):
        try:
            r = subprocess.run([_GIT, "-C", d] + args,
                               capture_output=True, text=True, timeout=5,
                               env=_GIT_ENV)
        except Exception:
            return None
        if r.returncode != 0:
            return None
        return r.stdout.strip()
    common = git(["rev-parse", "--git-common-dir"])
    if not common:
        return None
    common = os.path.realpath(os.path.join(d, common))
    prefix = git(["rev-parse", "--show-prefix"])  # dir relative to toplevel
    if prefix is None:
        return None
    rel = os.path.normpath(os.path.join(prefix, os.path.basename(rp)))
    return (common, rel)

try:
    data = json.load(sys.stdin)
except Exception:
    fail_open()

# Only guard the text-mutation tools. A Read/Bash/Grep carrying this file_path must
# never be denied (it can't desync the graph). settings.json scopes the matcher too,
# but gate here as well so the script is correct when driven directly.
if data.get("tool_name") not in ("Edit", "Write", "MultiEdit"):
    fail_open()

tool_input = data.get("tool_input", {}) or {}
fp = tool_input.get("file_path", "") or ""
if not fp:
    fail_open()
fp = os.path.abspath(fp)

def in_registry(path):
    # Compare by realpath so a symlink alias to an adopted file (or an adopted
    # path reached through a symlinked directory) resolves to the SAME identity
    # and cannot silently bypass the guard. This match needs no git, so a missing
    # or hostile git can never let a direct/aliased edit of an adopted file through.
    target_real = os.path.realpath(path)
    fp_prov = "unset"  # git provenance, computed lazily only when realpath misses
    try:
        with open(registry_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                entry = os.path.expanduser(line)
                if os.path.realpath(entry) == target_real:
                    return True
                # realpath miss -> the registry row may still name the same
                # logical file reached through a durable worktree. Compare Git
                # provenance (shared common-dir + repo-relative path).
                if fp_prov == "unset":
                    fp_prov = git_provenance(path)
                if fp_prov is not None and git_provenance(entry) == fp_prov:
                    return True
    except FileNotFoundError:
        return False
    except Exception:
        return False
    return False

# Canonical marker (code-as-facts SKILL.md) is `;; @upstream:graph`; the two
# legacy spellings stay recognized for deliberate backward compatibility.
_MARKERS = ("@upstream:graph", "@upstream-is-graph", "@claim-canonical")
# An adoption directive is a leading comment whose payload IS one of the markers,
# optionally followed by whitespace + suffix prose (`;; @upstream:graph (managed
# by fram)`). The marker must be anchored at the start of the comment payload and
# be a whole token (followed by whitespace or end of line): an explanatory MENTION
# (`;; see @upstream:graph for why`) is not a directive, and `@upstream:graphics`
# does not match.
_DIRECTIVE_RE = re.compile(
    r';+\s*(?:' + '|'.join(re.escape(m) for m in _MARKERS) + r')(?:\s|$)')
# Only EXACT standalone generated headers precede the leading comment block: a
# `#lang <token>` line or a `(define-target <token>)` form (what the lossless
# round-trip's --render emits). A prefix match here would wrongly treat real code
# like `(define-target-registry ...)` as a header, skip it, and then honor a
# marker that trails actual code — so match the whole line exactly.
_HEADER_RE = re.compile(r'(?:#lang\s+\S+|\(define-target\s+\S+\))\Z')

# Bytes of leading text scanned for the sentinel before giving up. A real leading
# comment/license block can run well past the old 8 PHYSICAL-line cap, so scan to
# the first actual form under a sane byte ceiling instead of a fixed line count.
_SCAN_BYTE_CAP = 65536

def self_declared(path):
    # In-band sentinel in the file's LEADING comment block. The marker only counts
    # on a leading COMMENT line (`;;`) that precedes the first real form: we stop at
    # that form BEFORE testing, so marker-like text in a string literal, in code, or
    # in a comment trailing real code cannot self-adopt a file.
    try:
        # errors="replace": a non-UTF-8 byte in a license preamble must not raise
        # (that would fail OPEN and let an adopted file through).
        with open(path, "r", errors="replace") as f:
            scanned = 0
            while scanned < _SCAN_BYTE_CAP:
                line = f.readline()
                if line == "":
                    break
                scanned += len(line)
                s = line.strip()
                # blanks + exact generated headers precede the comment block — skip.
                if s == "" or _HEADER_RE.match(s):
                    continue
                if s.startswith(";;"):
                    if _DIRECTIVE_RE.match(s):
                        return True
                    continue  # ordinary leading comment — keep scanning
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

printf '%s' "$payload" | python3 -c "$PY" "$REGISTRY" "$DENY_REASON"
