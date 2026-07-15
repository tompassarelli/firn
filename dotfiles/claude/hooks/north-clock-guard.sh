#!/usr/bin/env bash
# PreToolUse north-clock-guard — HARD-DENY billable client work when no north
# clock OWNED BY THIS CLIENT is running. The forcing function for "never do
# billable work untracked, never mis-attribute it."
# ============================================================================
# Prose in CLAUDE.md demonstrably did not hold: ~22h of MSA client work once
# shipped with ZERO north time logged, then had to be reconstructed by hand for
# an invoice. This makes untracked/mis-attributed billable work mechanically
# impossible instead of merely discouraged.
#
# TWO holes closed vs v1:
#   (1) Bash bypass — v1 only rode Edit|Write|MultiEdit, so a file mutation done
#       through Bash (sed -i, >, git commit, cp/mv/rm …) under a client path
#       slipped past untracked. Now Bash tool calls are gated too, via a
#       conservative mutation heuristic (false-negatives OK, false-positives not:
#       pure reads — git log/diff/status, grep, ls, cat, find, curl GET — never
#       deny).
#   (2) ANY-clock loophole — v1 accepted ANY running clock, so a clock on an
#       unrelated personal thread legalized client edits and poisoned per-ticket
#       billing attribution. Now the gate is CLIENT-SCOPED: it derives <client>
#       from the /code/client/<client>/ path segment and ALLOWS only when at
#       least one OPEN session's session_of thread carries `owner == <client>`.
#
#   Edit/Write/MultiEdit under */code/client/<c>/**                  -> gated
#   Bash mutating a */code/client/<c>/** path (cwd or cmd-referenced) -> gated
#     gated + an open session owned by <c>        -> allow
#     gated + open session(s), none owned by <c>  -> DENY (names the mismatch)
#     gated + no open session at all              -> DENY (clock-in recipe)
#   any non-client path, or a read, or non-Bash/non-edit tool         -> allow
#   log missing/unreadable · python3 absent · killswitch              -> FAIL-OPEN
#
# Open sessions are read by parsing the fram fact log DIRECTLY (env FRAM_LOG),
# the same coupling v1 already had at its ticket-HINT lookup. An open session =
# a subject with session_of + start_time facts and no end_time fact; single-
# valued predicates replace on assert and clear on retract. Tolerates MULTIPLE
# open sessions (per-agent concurrent clocks) — ANY matching owner allows.
# NOTE: default log is facts.log, the real session store. v1's default was
# claims.log, which does not exist on disk — pointing the clock check there
# would make it inert. facts.log is where session_of/start_time/end_time/owner
# facts actually live; FRAM_LOG overrides it (tests point it at a fixture).
#
# Kill-switch: persistent `north config guards off` (state) OR env
# CLAUDE_NO_AUTHORING_HOOKS (any value but 0/false; 0/false forces guards live).
# Shared impl: lib/authoring-killswitch.sh.
# ============================================================================
set -uo pipefail

# Kill-switch: shared semantics in lib/authoring-killswitch.sh.
# shellcheck disable=SC1090,SC1091
. "$(dirname "$0")/lib/authoring-killswitch.sh" 2>/dev/null || true
type authoring_guards_off >/dev/null 2>&1 && authoring_guards_off && exit 0

command -v python3 >/dev/null 2>&1 || exit 0   # no python3 -> fail-open

IN="$(cat 2>/dev/null || true)"

# ---- Stage 1: parse the tool call. Emit "FIRE<TAB>CLIENT<TAB>TARGETDIR" iff
# this call is a billable client mutation; print nothing (allow) otherwise.
#   Edit/Write/MultiEdit -> fires on any file_path under /code/client/<c>/.
#   Bash                 -> fires when a client path is involved (cwd OR a path
#                           in the command) AND the command matches the mutation
#                           heuristic. Pure reads never fire.
PARSE="$(printf '%s' "$IN" | python3 -c '
import sys, json, os, re
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
tool = d.get("tool_name", "")
ti = d.get("tool_input") or {}
topcwd = d.get("cwd") or ""
CRE = re.compile(r"/code/client/([^/\s]+)")
# Mutation heuristic — conservative, one place. Matches a file-writing shell op.
# stdout redirection (> >>, NOT fd-prefixed 2>/dev/null stderr), tee, in-place
# sed/perl, mutating git subcommands, and the usual fs mutators / package writes.
MUT = re.compile(
    r"(?:(?<!\d)>>?\s*[^&\s|])"
    r"|\btee\b"
    r"|\bsed\b[^|;&]*-\w*i"
    r"|\bperl\b[^|;&]*-\w*i"
    r"|\bgit\s+(?:commit|apply|merge|rebase|cherry-pick|stash\s+pop|checkout\s+--|restore|clean)\b"
    r"|\brm\b|\bmv\b|\bcp\b|\btouch\b|\bmkdir\b|\bln\b|\bpatch\b|\brsync\b|\bdd\b|\binstall\b"
    r"|\b(?:npm|pnpm|yarn|bun)\s+(?:install|add|run)\b")
def clientof(s):
    m = CRE.search(s or "")
    return m.group(1) if m else None
if tool in ("Edit", "Write", "MultiEdit"):
    fp = ti.get("file_path") or ""
    if not fp: sys.exit(0)
    if not fp.startswith("/"): fp = os.path.join(topcwd or os.getcwd(), fp)
    c = clientof(fp)
    if not c: sys.exit(0)
    print("1\t%s\t%s" % (c, os.path.dirname(fp))); sys.exit(0)
if tool == "Bash":
    cmd = ti.get("command") or ""
    if not cmd: sys.exit(0)
    cwd = ti.get("cwd") or topcwd or os.getcwd()
    c = clientof(cmd) or clientof(cwd)
    if not c: sys.exit(0)
    if not MUT.search(cmd): sys.exit(0)           # pure read -> allow
    print("1\t%s\t%s" % (c, cwd)); sys.exit(0)
sys.exit(0)
' 2>/dev/null || true)"

[ -z "$PARSE" ] && exit 0                          # not a billable client mutation
IFS=$'\t' read -r FIRE CLIENT TARGETDIR <<<"$PARSE"
[ "$FIRE" = 1 ] || exit 0
[ -n "$CLIENT" ] || exit 0

FRAM_LOG="${FRAM_LOG:-$HOME/.local/state/north/facts.log}"

# ---- Stage 2: decide against open sessions in the fact log. Prints exactly one
# of: ALLOW (matching owner, OR fail-open on a missing/garbled log) ·
# NOCLOCK (no open session) · MISMATCH<TAB><details> (open, none owned by CLIENT).
DECISION="$(CLIENT="$CLIENT" FRAM_LOG="$FRAM_LOG" python3 -c '
import sys, os, re
client = os.environ.get("CLIENT", "")
log = os.environ.get("FRAM_LOG") or os.path.expanduser("~/.local/state/north/facts.log")
try:
    f = open(log, "r", errors="replace")
except Exception:
    print("ALLOW"); sys.exit(0)                    # missing/unreadable -> fail-open
OP = re.compile(r":op \"(\w+)\"")
L  = re.compile(r":l \"([^\"]*)\"")
P  = re.compile(r":p \"([^\"]*)\"")
R  = re.compile(r":r \"([^\"]*)\"")
KEEP = ("session_of", "start_time", "end_time", "owner")
state = {}   # (subject, predicate) -> object ; single-valued: assert replaces, retract clears
try:
    for line in f:
        if ("session_of" not in line and "start_time" not in line
                and "end_time" not in line and "owner" not in line):
            continue
        mp = P.search(line)
        if not mp or mp.group(1) not in KEEP: continue
        mo = OP.search(line); ml = L.search(line)
        if not mo or not ml: continue
        op, subj, pred = mo.group(1), ml.group(1), mp.group(1)
        mr = R.search(line); obj = mr.group(1) if mr else None
        k = (subj, pred)
        if op == "assert":
            state[k] = obj
        elif op == "retract":
            if state.get(k) == obj: state.pop(k, None)
except Exception:
    print("ALLOW"); sys.exit(0)                    # garbled -> fail-open
byS = {}
for (s, p), v in state.items():
    byS.setdefault(s, {})[p] = v
open_sess = []   # (thread_id, owner) for each OPEN session
for s, pd in byS.items():
    if "session_of" in pd and "start_time" in pd and "end_time" not in pd:
        th = pd["session_of"]
        open_sess.append((th, byS.get(th, {}).get("owner")))
for th, ow in open_sess:
    if ow == client:
        print("ALLOW"); sys.exit(0)                # a clock owned by this client is live
if not open_sess:
    print("NOCLOCK"); sys.exit(0)
det = " ; ".join("%s owner=%s" % (t, (o or "none")) for t, o in open_sess)
print("MISMATCH\t" + det)
' 2>/dev/null || true)"

[ -z "$DECISION" ] && exit 0                        # fail-open if stage 2 produced nothing
case "$DECISION" in
  ALLOW*) exit 0 ;;
esac

# ---- DENY. Best-effort friction-kill: derive the Linear ticket from the target
# repo's branch and locate its thread, so recovery is one paste. Same fact-log
# coupling as the clock check (FRAM_LOG).
REPO="$(git -C "${TARGETDIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null || true)"
BRANCH="$(git -C "${REPO:-${TARGETDIR:-$PWD}}" branch --show-current 2>/dev/null || true)"
TICKET="$(printf '%s' "$BRANCH" | grep -oiE 'msa-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]' || true)"

if [ -n "$TICKET" ]; then
  TID="$(sed -n "s/.*:l \"\(@[0-9a-f-]*\)\".*\"linear\".*\"$TICKET\".*/\1/p" "$FRAM_LOG" 2>/dev/null | tail -1)"
  if [ -n "$TID" ]; then
    HINT="Thread for $TICKET exists — clock in:  north clock start ${TID#@}"
  else
    HINT="No thread for $TICKET yet:  north capture \"$TICKET <title>\" $CLIENT   then   north clock start <id>"
  fi
else
  HINT="Find/create the $CLIENT thread:  north ready  (or  north capture \"<title>\" $CLIENT ),  then  north clock start <id>"
fi

case "$DECISION" in
  MISMATCH*)
    DETAILS="${DECISION#MISMATCH$'\t'}"
    REASON="Billable client edit blocked — WRONG clock. This edit is for client '$CLIENT', but the only running clock(s) are owned by someone else:
  ${DETAILS}
A clock on an unrelated thread does NOT legalize this edit — it mis-attributes the time. Stop the wrong clock and start one on a $CLIENT thread, then retry:
  north clock stop
  ${HINT}
Deliberate bypass: north config guards off (persistent, live) — or a session launched with CLAUDE_NO_AUTHORING_HOOKS=1."
    ;;
  *)  # NOCLOCK
    REASON="Billable client edit blocked — no north clock running for client '$CLIENT'. Client work is never done untracked (this gate exists because ~22h of MSA work once shipped with zero logged time and had to be reconstructed for an invoice). Start a clock on the $CLIENT thread, then retry the edit:
  ${HINT}
Deliberate bypass: north config guards off (persistent, live) — or a session launched with CLAUDE_NO_AUTHORING_HOOKS=1."
    ;;
esac

printf '%s' "$REASON" | python3 -c 'import sys,json
r=sys.stdin.read()
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":r}}))'
exit 0
