#!/usr/bin/env bash
# PreToolUse guard — refuses an unscoped content sweep of the agent-transcript
# corpus (~/code/north-data, and ~/.local/state/north which is a SYMLINK to it).
# ============================================================================
# The corpus is ~99 GB on disk, 77 GiB of it JSONL, and it grows ~9.5 GiB/day.
# One `rg -l --hidden` rooted there measured 3.5 GB RSS and a quarter of a
# 24-core machine; `convo` answers the same question in 0.3-0.4 s at ~31 MB
# because it keeps an FTS index instead of re-reading the corpus. AGENTS.md and
# the `convo` skill say so; this hook is the layer that cannot be forgotten.
#
# WHAT IS REFUSED is only the shape that walks the whole tree: a recursive
# search whose ROOT is the corpus root, the symlink, or one of the interior
# containers that still holds tens of gigabytes (accounts/, a provider, an
# account, its sessions/ or projects/, a sessions YEAR or MONTH, archives/).
#
# WHAT STAYS ALLOWED, because a guard with no compliant move is a trap:
#   · one known transcript file (`rg pat .../rollout-....jsonl`)
#   · a single day directory or a single Claude project directory, and deeper
#   · any non-corpus subtree of north-data (threads/, scratch-*/, ...)
#   · `find <root> -maxdepth N` (N<=3) and `rg --max-depth N` (N<=3)
#   · non-recursive `grep` (no -r/-R): it never walks anything
#   · `ls`, `stat`, `cat`, `head`, `wc`, `convo` — not search tools at all
#   · a PATTERN or commit message that merely mentions the corpus path: the
#     command word must be unquoted and at command position for anything to
#     match, and the first non-option operand of a grep-like is the pattern.
#
# Kill-switch: persistent `north config agents off corpus-scan-guard` OR env
# AGENT_NO_AUTHORING_HOOKS (any value but 0/false;
# 0/false forces guards live). Shared impl: lib/authoring-killswitch.sh.
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

# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0
[ "$payload_oversized" -eq 0 ] || exit 0

# Fast-path: nothing here has an opinion unless the corpus is named. The
# envelope carries `cwd`, so a bare `rg foo` launched from inside the corpus
# still reaches python.
case "$payload" in
  *north-data*|*state/north*) ;;
  *) exit 0 ;;
esac

read -r -d '' PY <<'PYEOF' || true
import sys, json, os, re

def allow():
    sys.exit(0)

try:
    data = json.load(sys.stdin)
except Exception:
    allow()

if data.get("tool_name", "") != "Bash":
    allow()

cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""
if not cmd:
    allow()

HOME = os.path.expanduser("~")
cwd = data.get("cwd") or os.getcwd()

# --- shell-ish tokenizer -----------------------------------------------------
# Quoted segments are kept (a path operand is routinely quoted) but flagged, so
# a command WORD can be required to be unquoted. That is what keeps
# `echo 'rg ~/code/north-data'` and a commit message quoting the phrase out of
# the match: they are quoted words in argument position of some other command.
SEPS = {";", "&", "|", "\n", "(", ")", "{", "}", "`"}


def tokenize(s):
    """-> list of ('word', text, quoted) and ('sep', text, False)."""
    out = []
    buf = []
    quoted = False
    i, n = 0, len(s)

    def flush():
        nonlocal buf, quoted
        if buf:
            out.append(("word", "".join(buf), quoted))
        buf = []
        quoted = False

    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            buf.append(s[i + 1])
            i += 2
            continue
        if c == "'":
            j = s.find("'", i + 1)
            end = n if j == -1 else j
            buf.append(s[i + 1:end])
            quoted = True
            i = end + 1
            continue
        if c == '"':
            j = i + 1
            piece = []
            while j < n:
                if s[j] == "\\" and j + 1 < n:
                    piece.append(s[j + 1])
                    j += 2
                    continue
                if s[j] == '"':
                    break
                piece.append(s[j])
                j += 1
            buf.append("".join(piece))
            quoted = True
            i = j + 1
            continue
        if c in SEPS:
            flush()
            out.append(("sep", c, False))
            i += 1
            continue
        if c in " \t":
            flush()
            i += 1
            continue
        buf.append(c)
        i += 1
    flush()
    return out


# Heredoc bodies are documentation, never commands. Blank them before
# tokenizing so a body quoting `rg ~/code/north-data` is inert.
_HEREDOC_START = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")


def strip_heredocs(s):
    out, i, n = [], 0, len(s)
    while i < n:
        m = _HEREDOC_START.search(s, i)
        if not m:
            out.append(s[i:])
            break
        out.append(s[i:m.end()])
        line_end = s.find("\n", m.end())
        if line_end == -1:
            out.append(s[m.end():])
            break
        out.append(s[m.end():line_end + 1])
        delim = m.group(2)
        term = re.compile(r"^[ \t]*" + re.escape(delim) + r"[ \t]*$", re.M)
        tm = term.search(s, line_end + 1)
        end = tm.start() if tm else n
        out.append("".join(c if c == "\n" else " " for c in s[line_end + 1:end]))
        i = end
    return "".join(out)


# --- corpus geometry ---------------------------------------------------------
def _roots():
    out = []
    for p in (os.path.join(HOME, "code", "north-data"),
              os.path.join(HOME, ".local", "state", "north")):
        for q in (p, os.path.realpath(p)):
            if q not in out:
                out.append(q)
    return out


ROOTS = _roots()
GLOB = re.compile(r"[*?\[]")


def resolve(tok, base=None):
    t = tok
    if t == "~":
        t = HOME
    elif t.startswith("~/"):
        t = HOME + t[1:]
    t = t.replace("${HOME}", HOME).replace("$HOME", HOME)
    if not t.startswith("/"):
        t = os.path.join(base or cwd, t)
    t = os.path.normpath(t)
    return t


def corpus_rel(path):
    """Segments of `path` under a corpus root, or None if it is outside."""
    cands = [path]
    if not GLOB.search(path):
        rp = os.path.realpath(path)
        if rp != path:
            cands.append(rp)
    for p in cands:
        for r in ROOTS:
            if p == r:
                return []
            if p.startswith(r + "/"):
                return [s for s in p[len(r) + 1:].split("/") if s]
    return None


class Wild:
    def __eq__(self, other):
        return True

    def __hash__(self):
        return 0


WILD = Wild()


def norm_segs(segs):
    return [WILD if GLOB.search(s) else s for s in segs]


def is_expensive_root(segs):
    """True when a recursive walk from here is a corpus-scale sweep.

    The tree is accounts/<provider>/<account>/{sessions/<Y>/<M>/<D>,projects/<slug>}
    and archives/<name>. A day directory, a project directory, a single file,
    and every non-transcript subtree are all cheap and stay allowed.
    """
    s = norm_segs(segs)
    if not s:
        return True
    if s[0] == "archives":
        return len(s) == 1
    if s[0] == "accounts":
        if len(s) <= 3:
            return True
        container, rest = s[3], s[4:]
        if container == "projects":
            return not rest
        if container == "sessions":
            return len(rest) <= 2
        return False
    return False


# --- per-tool option shapes --------------------------------------------------
GREPLIKE = {"grep", "egrep", "fgrep", "rgrep", "zgrep", "zegrep", "zfgrep"}
RGLIKE = {"rg", "ripgrep", "ag", "ack", "ack-grep", "fd", "fdfind"}
SEARCH = GREPLIKE | RGLIKE | {"find"}

# Options that consume the following token, so their VALUE is never mistaken
# for a search root.
VALUED = {
    "-e", "--regexp", "-f", "--file", "-m", "--max-count", "-A", "--after-context",
    "-B", "--before-context", "-C", "--context", "-d", "--directories",
    "-D", "--devices", "--include", "--exclude", "--exclude-dir", "--exclude-from",
    "--binary-files", "--color", "--colour", "--label", "--group-separator",
    "-g", "--glob", "--iglob", "-t", "--type", "-T", "--type-not", "-r", "--replace",
    "--max-depth", "--maxdepth", "--max-filesize", "--sort", "--sortr", "-j",
    "--threads", "--pre", "--ignore-file", "-E", "--encoding", "--path-separator",
}
# `-r` is --replace for rg but --recursive for grep: never eat the next token.
GREP_NOT_VALUED = {"-r", "-R", "-E", "-d", "-D"}

WRAPPERS = {"sudo", "doas", "env", "nice", "ionice", "time", "nohup", "command",
            "builtin", "xargs", "timeout", "stdbuf", "setsid"}
WRAPPER_VALUED = {"-n", "-u", "-c", "-e", "-I", "-P", "-L", "--max-procs",
                  "--replace", "--adjustment", "-k", "-s"}

DEPTH_OPTS = {"--max-depth", "--maxdepth", "-maxdepth", "--depth", "-d"}
CHEAP_DEPTH = 3


def depth_limit(argv):
    """Smallest explicit depth bound in argv, or None."""
    best = None
    for i, t in enumerate(argv):
        name, val = t, None
        if "=" in t and t.startswith("-"):
            name, val = t.split("=", 1)
        elif i + 1 < len(argv):
            val = argv[i + 1]
        if name in DEPTH_OPTS and val is not None:
            try:
                v = int(val)
            except (TypeError, ValueError):
                continue
            best = v if best is None else min(best, v)
    return best


def grep_recursive(argv):
    for t in argv:
        if t in ("-r", "-R", "--recursive", "--dereference-recursive"):
            return True
        if re.fullmatch(r"-[A-Za-z]+", t) and ("r" in t[1:] or "R" in t[1:]):
            return True
    return False


def operands(tool, argv):
    """Path operands, with the leading PATTERN of a grep-like removed."""
    valued = VALUED - (GREP_NOT_VALUED if tool in GREPLIKE else set())
    words, skip = [], False
    for i, t in enumerate(argv):
        if skip:
            skip = False
            continue
        if t == "--":
            words.extend(x for x in argv[i + 1:])
            break
        if t.startswith("-") and t != "-":
            if "=" not in t and t in valued:
                skip = True
            continue
        words.append(t)
    if tool == "find":
        # find [path...] EXPRESSION — the expression starts at the first
        # predicate, and predicates were already dropped as options above.
        out = []
        for t in argv:
            if t.startswith("-") or t in ("(", "!"):
                break
            out.append(t)
        return out
    if tool in GREPLIKE or tool in ("rg", "ripgrep", "ag", "ack", "ack-grep",
                                    "fd", "fdfind"):
        has_explicit_pattern = any(
            t in ("-e", "--regexp", "-f", "--file") or
            t.startswith("--regexp=") or t.startswith("--file=")
            for t in argv)
        if words and not has_explicit_pattern:
            words = words[1:]
    return words


def commands(tokens):
    """Split the token stream into (tool, argv, cwd) at command position.

    A leading `cd <dir>` moves the cwd the later stages of the same command
    line run in, which is how `cd ~/code/north-data && rg -l foo .` is the
    same sweep as naming the root outright.
    """
    out = []
    at_cmd = True
    cur_tool = None
    cur_args = []
    here = cwd
    pending_cd = False
    pending_skip = False
    for kind, text, quoted in tokens:
        if kind == "sep":
            if cur_tool:
                out.append((cur_tool, cur_args, here))
            cur_tool, cur_args = None, []
            at_cmd = True
            pending_cd = pending_skip = False
            continue
        if pending_skip:
            pending_skip = False
            continue
        if pending_cd:
            here = resolve(text, here)
            pending_cd = False
            at_cmd = False
            continue
        if at_cmd:
            if "=" in text and not text.startswith("-") and \
                    re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", text):
                continue  # VAR=value prefix
            base = os.path.basename(text)
            if base in WRAPPERS and not quoted:
                continue  # sudo / nice / xargs ... — the real command follows
            if text in WRAPPER_VALUED:
                pending_skip = True  # `nice -n 15 rg ...` — 15 is not a command
                continue
            if text.startswith("-"):
                continue  # an option belonging to a wrapper we skipped
            if re.fullmatch(r"[0-9]+[smhd]?", text):
                continue  # `timeout 30 rg ...`
            if base == "cd" and not quoted:
                pending_cd = True
                continue
            if base in SEARCH and not quoted:
                cur_tool, cur_args = base, []
                at_cmd = False
            else:
                at_cmd = False  # some other command; its args are not ours
            continue
        if cur_tool:
            cur_args.append(text)
    if cur_tool:
        out.append((cur_tool, cur_args, here))
    return out


hit_root = None
hit_tool = None
doubled = False
seen_real = {}

for tool, argv, here in commands(tokenize(strip_heredocs(cmd))):
    if tool in GREPLIKE and not grep_recursive(argv):
        continue  # a non-recursive grep walks nothing
    d = depth_limit(argv)
    if d is not None and d <= CHEAP_DEPTH:
        continue
    paths = operands(tool, argv)
    if not paths:
        paths = ["."]  # rg/find/recursive-grep with no operand search cwd
    for p in paths:
        r = resolve(p, here)
        segs = corpus_rel(r)
        if segs is None:
            continue
        if not GLOB.search(r):
            real = os.path.realpath(r)
            if os.path.isfile(real):
                continue  # one named transcript is the compliant shape
            if real in seen_real and seen_real[real] != p:
                doubled = True
            seen_real[real] = p
        if is_expensive_root(segs) and hit_root is None:
            hit_root, hit_tool = r, tool

if hit_root is None:
    allow()

reason = (
    "BLOCKED: `%s` rooted at %s is an unscoped sweep of the agent-transcript "
    "corpus — ~99 GB on disk, 77 GiB of JSONL, growing ~9.5 GiB/day. One such "
    "sweep measured 3.5 GB RSS and a quarter of a 24-core machine. "
    "%s"
    "Use the index instead:\n"
    "  convo <terms>            full-text across every provider and account\n"
    "  convo -x '<literal>'     exact phrase, ids, error strings\n"
    "  convo session <uuid>     locate one session's transcripts\n"
    "Same lookups in 0.3-0.4s at ~31 MB, and the index refreshes at query time "
    "so it is never stale. Raw search is still allowed once convo names the "
    "file: one transcript path, a single day or project directory and deeper, "
    "any non-transcript subtree of north-data, `find <root> -maxdepth 2`, "
    "`rg --max-depth 2`, or a non-recursive grep. "
    "Rare explicit override: `north config agents off corpus-scan-guard` "
    "(persistent, live), or "
    "a session LAUNCHED with AGENT_NO_AUTHORING_HOOKS=1."
) % (
    hit_tool,
    hit_root,
    ("You also named the same tree twice: ~/.local/state/north is a SYMLINK to "
     "~/code/north-data, so that scans every byte a second time. " if doubled else ""),
)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }
}))
sys.exit(0)
PYEOF

printf '%s' "$payload" | python3 -c "$PY"
