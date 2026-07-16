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
# Open sessions are read by folding North's canonical corpus DIRECTLY. In the
# split store, thread ownership/Linear links live in coordination.log and clock
# sessions live in telemetry.log; neither file alone can answer the join. An
# open session = a subject with session_of + start_time facts and no end_time
# fact; single-valued predicates replace on assert and clear on exact retract.
# Tolerates MULTIPLE open sessions (per-agent concurrent clocks) — ANY matching
# owner allows. FRAM_LOG + FRAM_TELEMETRY_LOG override the pair for fixtures or
# alternate instances. The pre-split facts.log is fallback only when the split
# corpus is absent.
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
# VERBS (tee / sed -i / mutating git subcommands / fs mutators / package writes)
# fire ONLY in COMMAND POSITION — at string start or right after a command
# separator (; & | ( ` newline), optionally through wrappers (sudo, env VAR=,
# timeout N, nice, xargs). This is the fix for the false-positive class where a
# mutator word buried in a FILENAME segment (ls north-install-commit-guard,
# my-cp-notes.txt, /x/dd/y) tripped a bare \b and DENIED a pure read. stdout
# redirection (> >>) is matched positionally but the (?<!\d) + [^&\s|] clause
# skips fd-dups / fd-prefixed stderr (2>&1, >&2, 2>/dev/null).
CP = (r"(?:^|[;&|(`\n])\s*"
      r"(?:sudo\s+|env\s+(?:\w+=\S*\s+)*|timeout\s+\S+\s+"
      r"|nice\s+(?:-n\s*\S+\s+)?|xargs\s+(?:-\w+\s*\S*\s+)*)*")
MUT = re.compile(
    r"(?:(?<!\d)>>?\s*[^&\s|])"
    "|" + CP + r"tee\b"
    "|" + CP + r"sed\b[^|;&]*\s(?:-\w*i\b|--in-place\b)"
    "|" + CP + r"perl\b[^|;&]*\s-\w*i\b"
    "|" + CP + r"git\s+(?:commit|apply|merge|rebase|cherry-pick|stash\s+pop|checkout\s+--|restore|clean)\b"
    "|" + CP + r"(?:rm|mv|cp|touch|mkdir|ln|patch|rsync|dd|install)\b"
    "|" + CP + r"(?:npm|pnpm|yarn|bun)\s+(?:install|add|run)\b")
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
    # cwd attribution is a FALLBACK for commands acting in the session dir. A
    # command whose first act is "cd <abs non-client path>" (optionally after
    # VAR=val segments) acts THERE, not here — cwd-attributing it billed
    # nixos-config guard maintenance to a client (2026-07-16 false positive).
    # Explicit client paths anywhere in the command still gate regardless.
    mcd = re.match(r"\s*(?:[A-Za-z_]\w*=\S*\s*(?:&&|;)\s*)*cd\s+[\"\x27]?([^\s\"\x27;|&]+)", cmd)
    cdto = mcd.group(1) if mcd else None
    escape = bool(cdto and (cdto.startswith("/") or cdto.startswith("~")) and not CRE.search(cdto))
    # Second escape (2026-07-16 false positive #4): a SINGLE fs-mutator command
    # whose every target is an absolute non-client path acts on those paths,
    # not the session cwd (bare rm of /run/user/... from a client cwd is not
    # client work). Compound commands (any separator) keep cwd attribution —
    # a client mutation could hide after the separator.
    if not escape and not re.search(r"[;&|`]|\$\(", cmd):
        mfs = re.match(r"\s*(?:sudo\s+)?(?:rm|mv|cp|touch|mkdir|ln)\s+(\S.*)$", cmd, re.S)
        if mfs:
            args = [t.strip("\x22\x27") for t in mfs.group(1).split() if not t.startswith("-")]
            escape = bool(args) and all((a.startswith("/") or a.startswith("~")) and not CRE.search(a) for a in args)
    c = clientof(cmd) if escape else (clientof(cmd) or clientof(cwd))
    if not c: sys.exit(0)
    if not MUT.search(cmd): sys.exit(0)           # pure read -> allow
    print("1\t%s\t%s" % (c, cwd)); sys.exit(0)
sys.exit(0)
' 2>/dev/null || true)"

[ -z "$PARSE" ] && exit 0                          # not a billable client mutation
IFS=$'\t' read -r FIRE CLIENT TARGETDIR <<<"$PARSE"
[ "$FIRE" = 1 ] || exit 0
[ -n "$CLIENT" ] || exit 0

# Resolve the canonical pair before the fold. An explicit coordination.log
# infers its sibling telemetry.log, matching ~/code/north/bin/north. An explicit
# arbitrary FRAM_LOG remains a single-file fixture unless FRAM_TELEMETRY_LOG is
# also set. A present-but-unreadable split fails open; it never falls back to a
# stale legacy monolith.
LOGS=()
if [ -n "${FRAM_LOG:-}" ]; then
  LOGS+=("$FRAM_LOG")
  if [ -n "${FRAM_TELEMETRY_LOG:-}" ]; then
    LOGS+=("$FRAM_TELEMETRY_LOG")
  elif [ "$(basename "$FRAM_LOG")" = coordination.log ] && [ -e "$(dirname "$FRAM_LOG")/telemetry.log" ]; then
    LOGS+=("$(dirname "$FRAM_LOG")/telemetry.log")
  fi
elif [ -e "$HOME/.local/state/north/coordination.log" ]; then
  LOGS+=("$HOME/.local/state/north/coordination.log")
  [ -e "$HOME/.local/state/north/telemetry.log" ] && LOGS+=("$HOME/.local/state/north/telemetry.log")
elif [ -e "$HOME/.local/state/north/facts.log" ]; then
  LOGS+=("$HOME/.local/state/north/facts.log")
fi
[ "${#LOGS[@]}" -gt 0 ] || exit 0
for log in "${LOGS[@]}"; do [ -r "$log" ] || exit 0; done

# Resolve the branch ticket before the fold so the clock verdict and recovery
# hint come from the same transaction-ordered current-state pass.
REPO="$(git -C "${TARGETDIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null || true)"
BRANCH="$(git -C "${REPO:-${TARGETDIR:-$PWD}}" branch --show-current 2>/dev/null || true)"
TICKET="$(printf '%s' "$BRANCH" | grep -oiE "${CLIENT}-[0-9]+" | head -1 | tr '[:lower:]' '[:upper:]' || true)"

# ---- Stage 2: decide against open sessions in the merged corpus. Prints one
# of: ALLOW (matching owner, OR fail-open on a missing/garbled log) ·
# NOCLOCK<TAB><ticket-thread> (no open session) ·
# MISMATCH<TAB><ticket-thread><TAB><details> (open, none owned by CLIENT).
DECISION="$(python3 - "$CLIENT" "$TICKET" "${LOGS[@]}" <<'PY' 2>/dev/null || true
import sys, re
client, ticket, *logs = sys.argv[1:]
TX = re.compile(r":tx\s+(\d+)")
OP = re.compile(r":op \"(\w+)\"")
L  = re.compile(r":l \"([^\"]*)\"")
P  = re.compile(r":p \"([^\"]*)\"")
R  = re.compile(r":r \"([^\"]*)\"")
KEEP = {"session_of", "start_time", "end_time", "owner", "linear"}
events = []
try:
    for path in logs:
        with open(path, "r", errors="replace") as f:
            for line in f:
                if not any(p in line for p in KEEP): continue
                mt, mo, ml, mp = TX.search(line), OP.search(line), L.search(line), P.search(line)
                if not mt or not mo or not ml or not mp or mp.group(1) not in KEEP: continue
                mr = R.search(line)
                events.append((int(mt.group(1)), ml.group(1), mp.group(1),
                               mo.group(1), mr.group(1) if mr else None))
except Exception:
    print("ALLOW"); sys.exit(0)                    # garbled -> fail-open
# Apply exact Fram singleton semantics in global tx order: assert supersedes;
# retract clears only when it names the currently-live object.
state = {}   # (subject, predicate) -> (object, assert-tx)
for tx, subj, pred, op, obj in sorted(events, key=lambda e: e[0]):
    k = (subj, pred)
    if op == "assert": state[k] = (obj, tx)
    elif op == "retract" and state.get(k, (None,))[0] == obj: state.pop(k, None)
byS = {}
for (s, p), (v, _tx) in state.items():
    byS.setdefault(s, {})[p] = v
open_sess = []   # (thread_id, owner) for each OPEN session
for s, pd in byS.items():
    if "session_of" in pd and "start_time" in pd and "end_time" not in pd:
        th = pd["session_of"]
        open_sess.append((th, byS.get(th, {}).get("owner")))
for th, ow in open_sess:
    if ow == client:
        print("ALLOW"); sys.exit(0)                # a clock owned by this client is live
linked = [(tx, s) for (s, p), (v, tx) in state.items()
          if p == "linear" and v == ticket]
linked.sort(reverse=True)
tid = linked[0][1] if linked else ""
if not open_sess:
    print("NOCLOCK\t" + tid); sys.exit(0)
det = " ; ".join("%s owner=%s" % (t, (o or "none")) for t, o in open_sess)
print("MISMATCH\t%s\t%s" % (tid, det))
PY
)"

[ -z "$DECISION" ] && exit 0                        # fail-open if stage 2 produced nothing
case "$DECISION" in
  ALLOW*) exit 0 ;;
esac

# ---- DENY. The ticket/thread hint was resolved by the same folded read.
TID="$(printf '%s' "$DECISION" | cut -f2)"

if [ -n "$TICKET" ]; then
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
    DETAILS="$(printf '%s' "$DECISION" | cut -f3-)"
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
