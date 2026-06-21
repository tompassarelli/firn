#!/usr/bin/env bash
# SessionStart hook (global, guarded) — AUTO-REGISTER into the agentchat
# multi-agent coordination protocol (~/code/agentchat/CLAUDE.md).
# ============================================================================
# Registration is the protocol's "first act of every session." Skills/CLAUDE.md
# are model-discretion (can be forgotten); this hook is harness-enforced and fires
# once per session, so an agent is registered whether or not it remembers to.
# It stamps an initial heartbeat and uses a conservative stale threshold, so a live
# session is not falsely reaped within a normal lifetime; a crashed handle frees up
# after the threshold. Scoped to the shared/contended ecosystem repos; fast no-op elsewhere.
set -uo pipefail

# Clean-room / experiment kill-switch (opt-OUT), shared with the other authoring
# hooks: CLAUDE_NO_AUTHORING_HOOKS=1 -> no presence written, no context injected,
# so a controlled run keeps a neutral session surface across arms.
[ -n "${CLAUDE_NO_AUTHORING_HOOKS:-}" ] && exit 0

# Protocol must be installed on this machine.
AGENTCHAT="${AGENTCHAT_DIR:-$HOME/code/agentchat}"
[ -d "$AGENTCHAT" ] || exit 0

# Stable project basename (git toplevel if available, else the project dir).
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || true
[ -n "${top:-}" ] && dir="$top"
base="$(basename "$dir")"

# SCOPE — only the shared codebases with concurrent agents register (+ worktrees).
# Extend this list as the ecosystem grows; everything else is a fast no-op.
case "$base" in
  fram|fram-*|beagle|beagle-*|gjoa|gjoa-*|eddy|eddy-*) ;;
  *) exit 0 ;;
esac

# Heavy lifting + context injection in python so stdin stays the harness payload
# (session_id is read from it); shellcheck only lints this thin wrapper.
read -r -d '' PY <<'PYEOF' || true
import sys, os, json, time, calendar, binascii, re

agentchat, base, projdir = sys.argv[1], sys.argv[2], sys.argv[3]
presence = os.path.join(agentchat, "presence")
reaped   = os.path.join(presence, "reaped")
try:
    os.makedirs(reaped, exist_ok=True)
except Exception:
    sys.exit(0)

try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
sid = str(data.get("session_id") or "")
now = time.strftime("%Y%m%d-%H%M%S", time.gmtime())
STALE = 4 * 3600  # s; conservative - a live session is rarely reaped within its lifetime

def age(path):
    try:
        with open(path) as f:
            for line in f:
                if line.startswith("heartbeat:"):
                    t = time.strptime(line.split(":", 1)[1].strip(), "%Y%m%d-%H%M%S")
                    return time.time() - calendar.timegm(t)
    except Exception:
        return None
    return None

def field(content, key, default=""):
    m = re.search(r"(?m)^" + re.escape(key) + r":\s*(.*)$", content)
    return m.group(1).strip() if m else default

def body(handle, token, task):
    return ("# presence: %s\n"
            "token: %s\n"
            "session_id: %s\n"
            "dir: %s\n"
            "task: %s\n"
            "heartbeat: %s\n" % (handle, token, sid, projdir, task, now))

handle = token = None

# 1. Resume: a presence file already holding our session_id -> reuse + bump heartbeat.
if sid:
    for fn in sorted(os.listdir(presence)):
        if not fn.endswith(".md"):
            continue
        p = os.path.join(presence, fn)
        try:
            c = open(p).read()
        except Exception:
            continue
        if ("session_id: " + sid) in c:
            handle = fn[:-3]
            token = field(c, "token") or binascii.hexlify(os.urandom(3)).decode()
            task = field(c, "task", "(task TBD)")
            try:
                with open(p + ".tmp", "w") as f:
                    f.write(body(handle, token, task))
                os.replace(p + ".tmp", p)
            except Exception:
                pass
            break

# 2. Allocate the lowest free <base>-<n> via atomic O_EXCL create (first-writer-wins,
#    safe under concurrent session starts). Reap a stale holder first.
if handle is None:
    token = binascii.hexlify(os.urandom(3)).decode()
    n = 1
    while n < 1000:
        handle = "%s-%d" % (base, n)
        p = os.path.join(presence, handle + ".md")
        if os.path.exists(p):
            a = age(p)
            if a is not None and a > STALE:
                try:
                    os.replace(p, os.path.join(reaped, "%s.%s.md" % (handle, now)))
                except Exception:
                    pass
        try:
            fd = os.open(p, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        except FileExistsError:
            n += 1
            continue
        except Exception:
            handle = None
            break
        with os.fdopen(fd, "w") as f:
            f.write(body(handle, token, "(task TBD - agent: set this line)"))
        break
    else:
        handle = None

if not handle:
    sys.exit(0)

ctx = (
    "Multi-agent coordination is ACTIVE (shared codebase). You are auto-registered as "
    "**{h}** (presence/{h}.md, token {tok}). Your initial heartbeat is stamped; on a long "
    "session you may bump the `heartbeat:` line of presence/{h}.md (YYYYMMDD-HHMMSS UTC) so "
    "you are not reaped as stale. Protocol: ~/code/agentchat/CLAUDE.md.\n"
    "First steps: (1) CHECK INBOX - list ~/code/agentchat/mbox/ (skip done/) for filenames "
    "containing `-to-{h}`, `-to-all`, or `-to-{b}-`; ack a direct message by moving it to "
    "mbox/done/, a to-all by adding mbox/acks/<msg>-ack-{h}.md. (2) SET your `task:` line in "
    "presence/{h}.md to what you are actually doing. (3) CLAIM before editing shared code "
    "another agent might touch (esp. a Beagle subsystem): add a narrow claim in "
    "~/code/agentchat/claims/ (e.g. beagle-cljs-emit-{h}.md) after checking claims/ for a "
    "conflict. (4) SHARED TREE: if another agent shares this working tree, git is shared "
    "too - commit ONLY files you changed (`git add <files>`, never -A). NEVER run a "
    "tree-wide op (git stash / reset / clean / checkout-branch / restore) - each hits "
    "ALL agents' files, not yours; the build-window freeze primitive is a scoped COMMIT, "
    "never stash. Before any build / preflight / whole-tree import drop "
    "claims/BUILD-LOCK-{h}.md + wait for all agents clean (see the Shared-working-tree "
    "section of the protocol). Prefer a per-agent `git worktree` when launched in one. "
    "(5) CROSS-PROJECT PIN: if you build against a SIBLING repo at a pinned ref (e.g. "
    "gjoa compiles ../beagle at configs/beagle.ref), build from a DEDICATED WORKTREE "
    "(`git -C ../B worktree add ../B-pin <ref>`) - NEVER `cd ../B && git checkout <pin>` "
    "the sibling's shared tree: it detaches an actively-developing agent's HEAD + stashes "
    "their in-flight work (check ../B presence/ + claims/ first; active = off-limits)."
).format(h=handle, tok=token, b=base)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}))
PYEOF
python3 -c "$PY" "$AGENTCHAT" "$base" "$dir" || exit 0
exit 0
