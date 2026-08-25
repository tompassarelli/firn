#!/usr/bin/env bash
# PreToolUse guard — refuses session-killing signal shapes and unmanaged
# background-child launch shapes: broadcast kill (`kill -1`), user-wide process
# sweeps (`pkill -u` with no pattern, `killall -u`), compositor kills
# (pkill/killall niri), login-session teardown (`loginctl terminate-*`/`kill-*`,
# `systemctl --user exit`, stop/kill/restart of `user@*` or the compositor
# unit), and detached agent child processes (`nohup`, `setsid`, `disown`, bare
# background `&`, or direct Bun/Node temporary scripts).
# ============================================================================
# kill(-1, SIG) signals EVERY process the user owns — the compositor, the
# user manager, the login shell, and every other agent — in one syscall. The
# scoped alternatives (a specific PID, a unique -f pattern, a named unit the
# agent itself started) stay allowed. A background child instead uses
# `run-bounded <duration> -- <command>`: its 24h maximum owns a transient
# cgroup plus PID namespace, reaps every descendant, and gives all background
# jobs a shared 48G hard ceiling. Quoted mentions in commit messages and
# heredoc bodies stay allowed: only a command-position invocation is denied.
#
# Kill-switch: persistent `north config agents off session-kill-guard` OR env
# AGENT_NO_AUTHORING_HOOKS (any value but
# 0/false; 0/false forces guards live). Shared impl: lib/authoring-killswitch.sh.
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

# Fast-path: only Bash commands naming a process-lifecycle verb, temporary
# interpreter launch, or background operator are candidates.
case "$payload" in
  *kill*|*loginctl*|*systemctl*|*nohup*|*setsid*|*disown*|*run-bounded*|\
  *bun*|*node*|*/tmp/*|*'&'*) ;;
  *) exit 0 ;;
esac

read -r -d '' PY <<'PYEOF' || true
import sys, json, re, shlex

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

# --- Strip heredoc bodies, then quoted segments, so prose that merely
# mentions a trigger phrase is never treated as an invocation. Blanking (not
# deleting) preserves newline structure for the command-position anchors. ---

_HEREDOC_START = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")

def _blank(text):
    return "".join(c if c == "\n" else " " for c in text)

def strip_heredocs(s):
    out = []
    i, n = 0, len(s)
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
        body_start = line_end + 1
        delim = m.group(2)
        term = re.compile(r"^[ \t]*" + re.escape(delim) + r"[ \t]*$", re.M)
        tm = term.search(s, body_start)
        if tm:
            out.append(_blank(s[body_start:tm.start()]))
            i = tm.start()
        else:
            out.append(_blank(s[body_start:]))
            i = n
    return "".join(out)

def strip_quotes(s):
    out = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == "'":
            j = s.find("'", i + 1)
            end = n if j == -1 else j + 1
            out.append(_blank(s[i:end]))
            i = end
            continue
        if c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\" and j + 1 < n:
                    j += 2
                    continue
                if s[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(_blank(s[i:j]))
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)

cleaned = strip_quotes(strip_heredocs(cmd))

SEP = r"(?:^|[\n;&|({`])"
WRAP = r"(?:(?:sudo|doas|command|exec|nohup|setsid)\s+)*"
ARG_SPAN = r"[^\n;&|)}`]*"

CMD_RE = re.compile(
    SEP + r"\s*" + WRAP + r"(kill|pkill|killall|loginctl|systemctl)\s+("
    + ARG_SPAN + r")")

# The compositor and its session units: killing these IS killing the session.
SESSION_PROCS = {"niri", "niri-session"}
SESSION_UNITS = {"niri", "niri.service", "graphical-session.target"}

SIG_FLAG = re.compile(r"^-(?:[0-9]+|[A-Za-z]+)$")

def kill_hit(tokens):
    # Separate signal-spec tokens from PID operands; the broadcast shape is
    # `-1` in OPERAND position (`kill -9 -1`, `kill -- -1`). `kill -1 <pid>`
    # is SIGHUP to a pid and stays allowed.
    operands = []
    i, n = 0, len(tokens)
    seen_ddash = False
    while i < n:
        t = tokens[i]
        if not seen_ddash:
            if t == "--":
                seen_ddash = True
                i += 1
                continue
            if t in ("-l", "-L"):
                return None
            if t in ("-s", "-n", "--signal") and i + 1 < n:
                i += 2
                continue
            if i == 0 and SIG_FLAG.match(t) and (t != "-1" or n > 1):
                i += 1
                continue
        operands.append(t)
        i += 1
    if "-1" in operands:
        return "broadcast kill -1"
    return None

VALUE_FLAGS = {"-u", "-U", "--uid", "--euid", "-g", "-G", "--group",
               "-s", "--signal", "-P", "--parent", "-t", "--terminal",
               "-F", "--pidfile", "-d", "--delay", "-o", "-n"}

def pkill_hit(tokens):
    has_user = False
    operands = []
    skip = False
    for t in tokens:
        if skip:
            skip = False
            continue
        if t in ("-u", "-U") or t.startswith(("--uid", "--euid")):
            has_user = True
            if t in VALUE_FLAGS:
                skip = True
            continue
        if t in VALUE_FLAGS:
            skip = True
            continue
        if t.startswith("-"):
            continue
        operands.append(t)
    if has_user and not operands:
        return "user-wide pkill sweep"
    if any(o in SESSION_PROCS for o in operands):
        return "compositor kill"
    return None

def killall_hit(tokens):
    if any(t in ("-u", "--user") for t in tokens):
        return "user-wide killall sweep"
    if any(t in SESSION_PROCS for t in tokens):
        return "compositor kill"
    return None

LOGINCTL_VERBS = {"terminate-user", "kill-user", "terminate-session",
                  "kill-session", "terminate-seat"}

def loginctl_hit(tokens):
    for t in tokens:
        if t.startswith("-"):
            continue
        if t in LOGINCTL_VERBS:
            return "login-session teardown"
        return None
    return None

def systemctl_hit(tokens):
    user_mode = "--user" in tokens
    verb = None
    args = []
    for t in tokens:
        if t.startswith("-"):
            continue
        if verb is None:
            verb = t
            continue
        args.append(t)
    if verb is None:
        return None
    if user_mode and verb == "exit":
        return "user-manager exit"
    if verb == "isolate" and any(a.startswith("exit") for a in args):
        return "user-manager exit"
    if verb in ("stop", "kill", "restart"):
        if any(a.startswith("user@") for a in args):
            return "user-manager teardown"
        if user_mode and any(a in SESSION_UNITS for a in args):
            return "compositor teardown"
    return None

# The same command-position boundary covers process detachment. This is a
# deliberately small shell pass: it recognizes command lists, not arbitrary
# runtime-built shell source. Heredoc bodies are blanked; quoted prose remains
# an argument to its leading command and cannot become an invocation.
CONTROL = {";", "&&", "||", "|", "|&", "&", "\n", "(", ")"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$", re.S)
REDIRECTION = re.compile(r"^\d*(?:<>|>>|<<|>|<).*$", re.S)
WRAPPERS = {"command", "exec", "env", "sudo", "doas"}

def command_base(token):
    return token.rstrip("/").rsplit("/", 1)[-1]

def command_word(segment):
    index = 0
    while index < len(segment) and (ASSIGNMENT.fullmatch(segment[index]) or REDIRECTION.fullmatch(segment[index])):
        index += 1
    while index < len(segment):
        word = command_base(segment[index])
        if word not in WRAPPERS:
            return word, segment[index + 1:]
        index += 1
        while index < len(segment) and (segment[index].startswith("-") or ASSIGNMENT.fullmatch(segment[index])):
            index += 1
    return None, []

def temporary_script(args):
    return any(re.fullmatch(r"/tmp/[^\s]*\.(?:js|mjs|cjs|ts)", arg) for arg in args)

def background_shape(segment, background=False):
    word, args = command_word(segment)
    if word in {"nohup", "setsid", "disown"}:
        return word
    if word in {"bun", "node"} and temporary_script(args):
        return "direct %s /tmp script" % word
    if background and word != "run-bounded":
        return "unmanaged background job"
    return None

def unmanaged_background_hit(command):
    try:
        lexer = shlex.shlex(strip_heredocs(command), posix=True, punctuation_chars=";&|()\n")
        lexer.whitespace_split = True
        lexer.commenters = ""
        lexer.whitespace = " \t\r"
        tokens = list(lexer)
    except (TypeError, ValueError):
        return None
    segment = []
    for index, token in enumerate(tokens):
        # shlex splits fd redirects such as 2>&1 and &>file; those ampersands
        # are redirections, not background operators.
        redirect_amp = token == "&" and ((segment and segment[-1].endswith(">"))
            or (index + 1 < len(tokens) and tokens[index + 1].startswith(">")))
        if token == "&" and not redirect_amp:
            hit = background_shape(segment, background=True)
            if hit:
                return hit
            segment = []
        elif token in CONTROL:
            hit = background_shape(segment)
            if hit:
                return hit
            segment = []
        else:
            segment.append(token)
    return background_shape(segment)

hit = None
for m in CMD_RE.finditer(cleaned):
    name = m.group(1)
    tokens = m.group(2).split()
    if name == "kill":
        hit = kill_hit(tokens)
    elif name == "pkill":
        hit = pkill_hit(tokens)
    elif name == "killall":
        hit = killall_hit(tokens)
    elif name == "loginctl":
        hit = loginctl_hit(tokens)
    elif name == "systemctl":
        hit = systemctl_hit(tokens)
    if hit:
        break

background_hit = unmanaged_background_hit(cmd)

if hit is None and background_hit is None:
    allow()

if hit is not None:
    reason = (
        "BLOCKED: session-killing shape refused (%s) — this signals the whole "
        "desktop session (compositor, user manager, every agent), not just your "
        "target. Signal only processes YOU started, by specific PID (`kill <pid>`)"
        " or a unique pattern (`pkill -f '<unique-pattern>'`); manage your own "
        "units by exact name. Session/compositor teardown is the operator's call. "
        "Prose that mentions these phrases is unaffected — only a command-position "
        "invocation is denied. Rare explicit override: "
        "`north config agents off session-kill-guard` "
        "(persistent, live), or a session LAUNCHED with AGENT_NO_AUTHORING_HOOKS=1."
    ) % hit
else:
    reason = (
        "BLOCKED: %s would detach an agent child from its owner. Use "
        "`run-bounded <duration> -- <command>`; the wrapper has a 24h maximum, "
        "owns a transient cgroup plus PID namespace, reaps every descendant when "
        "the owner ends, and gives all background jobs a shared 48G hard ceiling."
    ) % background_hit

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
