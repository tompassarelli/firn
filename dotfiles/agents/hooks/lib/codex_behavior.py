"""Decisions for codex-behavior-guard.sh, one per Codex hook event.

Codex optimizes for never being wrong. These checks make it optimize for
closing issues instead: wasteful moves are refused and the score it sees is
issues closed. Every decision prints one JSON object or nothing, and a
malformed event allows.

- UserPromptSubmit records the prompt, shows the session scoreboard, and adds
  the correction, close-it-now or stop-now rule when the prompt calls for it;
  after a stop request, every fifth command says to reply ready.
- PreToolUse(update_plan) refuses process steps Tom didn't ask for, and a
  first plan without its checklist: the goal quoted from the request, the
  profile, Done-when, extra checks, workers and an ETA.
- PreToolUse(Bash) refuses worker jobs (checks, native sessions, log digging)
  in a session that has spawned workers, a check rerun on unchanged code, a
  second run of a check (farm runs included) on a commit where any agent
  already passed it, `gh run rerun` of a passing run, a new issue that can't
  close, and a new issue while the session has opened more than it closed.
  Edits to existing issues pass. One timing check may confirm once under an
  exclusive capacity lease.
- PreToolUse(spawn_agent) refuses a measure-only brief, and PreToolUse of a
  patch or shell write refuses a new manifest, provenance, attestation,
  inventory or checksum file in a prototype repo unless a prompt asked.
- PostToolUse(Bash) says to close an issue whose boxes are all ticked.
- PostToolUse(Bash) records passing checks and issue opens and closes, and
  says once when the work passes twice its ETA or after a long run of
  read-only commands with no change; an apply_patch ends that run.
- A commander's message left in relay-<session>.txt reaches a root session
  once, as context after its next tool call or as the reason its turn can't
  end yet.
- Stop refuses one ending per turn that lands work without accounting for its
  issue box, escalates without having tried, asks
  permission, narrates, hands the check to someone else, lists what isn't
  proven, or says nearly done.
"""

import fcntl
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

TOOLING_REPOS = {"nixos-config", "north", "fram", "clause", "beagle"}
PROFILES = {"prototype", "tooling", "client"}
CODE_ROOT = Path(os.environ.get("CODEX_BEHAVIOR_CODE_ROOT", Path.home() / "code"))
STATE_ROOT = Path(
    os.environ.get(
        "CODEX_BEHAVIOR_STATE",
        Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "codex-behavior",
    )
)
PROMPTS_KEPT = 20
PEER_LINE = (
    "A real doubt goes in one PEER line in "
    "~/.local/state/agents/handoffs/codex-lead-peer.md, not another run."
)
ONE_RUN = (
    "Tom's rule: every check gets one run. It passes, ship; a failure gets fixed and run "
    "once more. The sim is deterministic, so a second run on the same code shows nothing new."
)
JUSTIFY_PREFIX = re.compile(r"^\s*CASE=([A-Za-z])\s+FACT=(\"([^\"]*)\"|'([^']*)')\s*")
JUSTIFY_NOOP = re.compile(r"^\s*:\s+justify\s+([\w-]+)\s+([A-Za-z])\s+(\"([^\"]*)\"|'([^']*)')\s*$")
FACT_BANNED = re.compile(
    r"confiden|\bsure\b|\bagain\b|double[- ]?check|sanity|verif|flaky|just in case|safety",
    re.IGNORECASE,
)


def parse_case(command):
    """`CASE=X FACT="..." cmd` -> (X, fact, cmd); no prefix -> (None, None, cmd)."""
    match = JUSTIFY_PREFIX.match(command)
    if not match:
        return None, None, command
    fact = match.group(3) if match.group(3) is not None else match.group(4)
    return match.group(1).upper(), fact.strip(), command[match.end():]


def fact_problem(fact):
    if len(fact or "") < 15:
        return "FACT must name the new fact in 15 or more characters."
    banned = FACT_BANNED.search(fact)
    if banned:
        return f"FACT can't rest on \"{banned.group(0)}\": name what this run shows that the last one didn't."
    return None


def log_override(event, gate, case, fact):
    try:
        STATE_ROOT.mkdir(parents=True, exist_ok=True)
        with open(STATE_ROOT / "verify-overrides.jsonl", "a") as log:
            log.write(json.dumps({
                "at": time.time(), "session": event.get("session_id"), "agent": event.get("agent_id"),
                "gate": gate, "case": case, "cwd": event.get("cwd"), "fact": (fact or "")[:300],
            }) + "\n")
    except OSError:
        pass


MAX_BOXES = 5

STANDING = (
    "Score: issues closed. Being wrong is cheap here; the compiler, tests and "
    "debugger catch it. Being slow is the failure."
)

CORRECTION = re.compile(
    r"\b(fuck\w*|shit\w*|wtf|ffs|jesus|stop (asking|doing|with|adding|it)|"
    r"(i|i've) (already )?(told|asked) you|you keep|again\?|why (are|do|did) you|"
    r"for the (second|third|fourth) time|not what i asked|too much (process|ceremony)|"
    r"over-?engineer\w*)\b",
    re.IGNORECASE,
)
CLOSE_REQUEST = re.compile(
    r"\b(not (done|closed|finished|landed) yet|(isn't|is not|still not) (done|closed|finished|landed)|"
    r"still open|close (it|this|that|the issue|#?\d+)|land (it|this|the plane))\b",
    re.IGNORECASE,
)

STOP_REQUEST = re.compile(
    r"\b(wrap (it |this |everything )?up|stop (now|everything|all work|the workers|working)|"
    r"pause (everything|the workers|all work|work)|stand down|"
    r"restart(s|ing)? (in|now|shortly|soon)|reply (with the word )?ready)\b",
    re.IGNORECASE,
)
STOP_CALL_LIMIT = 5
WORKER_JOB = re.compile(r"\bgh run (view|watch)\b.*--log|\b(rg|grep|tail|less|cat)\b[^|;&]*\.log\b|\bwisp (lan|pad|native|capture|soak)\b")
LANDED = re.compile(r"\b(landed|pushed|merged)\b", re.IGNORECASE)
BOX_ACCOUNTED = re.compile(
    r"\b(closed|closing|close[sd]? #|ticked|checked off|box(es)?|remains? open|still open)\b|\b\d+/\d+\b",
    re.IGNORECASE,
)

PLAN_PROCESS = [
    (r"\b(independent|second|separate|fresh)[- ]?(review|reviewer|opinion|audit)\b", "an extra review", ("review", "audit")),
    (r"\b(reviewer|verifier|auditor)s?\b", "a reviewer or verifier", ("review", "verif", "audit")),
    (r"\battest(ation|ed|s)?\b|\bprovenance\b|\bsbom\b", "attestation or provenance", ("attest", "provenance", "sbom")),
    (r"\bcanary\b|\bsoak\b", "a canary or soak", ("canary", "soak")),
    (r"\b(re-?run|repeat)\b.{0,40}\b(passing|passed|for confidence)\b", "re-running a passing check", ("rerun", "re run", "again")),
    (r"\bfor confidence\b|\bto be (safe|sure)\b|\bdouble[- ]check\b", "a confidence check", ("double check", "make sure")),
    (r"\bcompat(ibility)? (shim|layer|bridge|path)\b|\bbackwards? compat\w*|\blegacy (client|caller|user)s?\b", "compatibility for users who don't exist", ("compat", "legacy")),
    (r"\brollback (plan|path|copy|target)\b|\bmigration (plan|path)\b", "a rollback or migration plan", ("rollback", "migration")),
    (r"\b(agents\.md|claude\.md|bootstrap|skill\.md)\b|\b(update|edit|amend|add|write)\b.{0,30}\b(skill|agent polic(y|ies))\b", "a policy or skill edit", ("agents md", "skill", "polic", "bootstrap", "harness", "hook")),
]

STOP_ASKING = re.compile(
    r"^(should i|shall i|may i|do you want me to|want me to|would you like me to|"
    r"let me know if you(?:'d| would) like|if you(?:'d| would) like,? i can)\b",
    re.IGNORECASE,
)
STOP_NARRATING = re.compile(
    r"^(next,? i(?:'ll| will)|i(?:'ll| will) now|now i(?:'ll| will)|i(?:'m| am) (now )?going to|"
    r"continuing with|i(?:'ll| will) (continue|proceed|start|keep)|"
    r"i(?:'m| am) (doing|fixing|running|handling|on) (that|this|it) now|"
    r"(assigning|redirecting|dispatching|handing)\b[^.]*\b(owner|worker|team|agent))\b",
    re.IGNORECASE,
)
STOP_DISCLAIMERS = re.compile(
    r"\b(does not|doesn't|do not|don't) (prove|establish|demonstrate)\b|"
    r"\bremains? (unproven|unobserved|unestablished)\b|\bnot yet (established|proven)\b",
    re.IGNORECASE,
)
STOP_NEARLY = re.compile(r"\b(nearly|almost) (done|there|finished|complete)\b", re.IGNORECASE)
STOP_MISSING_TOOL = re.compile(
    r"\b(tools?|send_message|followup_task|spawn_agent|wait_agent)\b[^.\n]{0,60}"
    r"\b(missing|unavailable|not available|restored?|gone)\b|"
    r"\b(lacks?|missing|restore)\b[^.\n]{0,40}\btools?\b",
    re.IGNORECASE,
)
ESCALATION = re.compile(r"(^|\n)\W*(blocked|needs you)\b", re.IGNORECASE)
NEEDS_NOTHING = re.compile(r"needs you\W*\s*nothing", re.IGNORECASE)
ATTEMPT_EVIDENCE = re.compile(
    r"\b(error|errors|failed|failure|fails|exit code|exited|returned|denied|refused|not found|"
    r"timed out|timeout|traceback|panic|panicked|http \d{3}|\d{3} (status|response))\b",
    re.IGNORECASE,
)
REAL_ASK = re.compile(
    r"\b(money|pay|paid|billing|purchase|price|subscription|account|sign[- ]?in|log[- ]?in|password|"
    r"credential|2fa|mfa|email|send (it|this|that|an? \w+) to|publish|post publicly|delete|"
    r"choose|pick (one|between)|which (option|direction|one)|product (choice|decision|direction))\b|\$\d",
    re.IGNORECASE,
)
READ_ONLY_WORDS = {
    "rg", "grep", "egrep", "cat", "head", "tail", "less", "ls", "find", "fd", "tree", "wc",
    "jq", "file", "stat", "du", "diff", "cut", "sort", "uniq", "convo", "pwd", "which", "realpath",
}
READ_ONLY_GIT = {"log", "show", "diff", "status", "blame", "grep", "ls-files", "rev-parse", "branch", "remote"}
STREAK_LIMIT = 20

NEGATION = re.compile(r"\b(no|not|don't|dont|stop|without|never|skip|drop|enough)\b[^.!?\n]{0,30}$")

RUNNERS = {
    "bun", "bunx", "cargo", "npm", "pnpm", "yarn", "npx", "pytest", "go", "make", "just",
    "nix", "firn", "deno", "uv", "python", "python3", "bash", "sh", "zig", "dotnet", "gradle",
}
CHECK_WORDS = re.compile(
    r"\b(test|tests|check|lint|typecheck|tsc|clippy|validate|verify|soak|parity|bench|perf|smoke|build|farm|sweep)\b"
)
EXIT_CODE = re.compile(r"(?:Exit code:|Process exited with code)\s*(-?\d+)")
GUARANTEE = re.compile(
    r"\b(every|never|always|guarantee[sd]?|full fidelity|bit[- ]exact|no (recurring|unexplained))\b",
    re.IGNORECASE,
)


# --- state -----------------------------------------------------------------

def normalize(text):
    return " ".join(re.sub(r"[^\w\s]", " ", text.lower()).split())


def state_path(session):
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", str(session or "unknown"))
    return STATE_ROOT / f"{safe}.json"


class State:
    """One session's record, read and written under an exclusive lock."""

    def __init__(self, session):
        self.path = state_path(session)
        self.lock = None
        self.data = {}

    def __enter__(self):
        try:
            STATE_ROOT.mkdir(parents=True, exist_ok=True)
            self.lock = open(self.path.with_suffix(".lock"), "w")
            fcntl.flock(self.lock, fcntl.LOCK_EX)
            raw = json.loads(self.path.read_text())
        except (OSError, ValueError):
            raw = {}
        self.data = {"prompts": raw} if isinstance(raw, list) else raw
        self.data.setdefault("prompts", [])
        self.data.setdefault("started", time.time())
        self.data.setdefault("opened", 0)
        self.data.setdefault("closed", 0)
        self.data.setdefault("passed", {})
        return self.data

    def __exit__(self, *exc):
        try:
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self.data))
            tmp.replace(self.path)
        except OSError:
            pass
        if self.lock:
            self.lock.close()


def agent_key(event):
    """Workers share their root session's id; each agent keeps its own record."""
    session = event.get("session_id") or "unknown"
    agent = event.get("agent_id")
    return f"{session}--{agent}" if agent else session


def tree_counts(event, state):
    """Opened and closed across the root session and every worker under it.

    The orchestrator assigns and workers close, so the root's own record alone
    reads zero while issues close all around it."""
    opened, closed = state["opened"], state["closed"]
    own = state_path(agent_key(event))
    root = state_path(event.get("session_id") or "unknown")
    for path in [root, *STATE_ROOT.glob(f"{root.stem}--*.json")]:
        if path == own:
            continue
        try:
            other = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        if isinstance(other, dict):
            opened += int(other.get("opened", 0))
            closed += int(other.get("closed", 0))
    return opened, closed


def minutes(seconds):
    total = int(seconds // 60)
    return f"{total // 60}h {total % 60:02d}m" if total >= 60 else f"{total} min"


# --- shared helpers ----------------------------------------------------------

def last_sentence(text):
    parts = [p.strip() for p in re.split(r"(?<=[.!?])\s+|\n+", text) if p.strip()]
    return parts[-1] if parts else ""


def asked_keyword(keywords, prompts):
    for prompt in prompts:
        if CORRECTION.search(prompt):
            continue
        text = normalize(prompt)
        for keyword in keywords:
            for match in re.finditer(re.escape(keyword), text):
                if not NEGATION.search(text[: match.start()]):
                    return True
    return False


def quoted_in(quote, prompts):
    needle = normalize(quote)
    return len(needle.split()) >= 3 and needle in normalize(" ".join(prompts))


def expected_profile(cwd):
    path = Path(cwd or ".").resolve()
    for directory in [path, *path.parents]:
        agents = directory / "AGENTS.md"
        if agents.is_file():
            match = re.search(r"^profile:\s*(\w+)", agents.read_text(errors="ignore"), re.MULTILINE)
            if match and match.group(1) in PROFILES:
                return match.group(1)
        if directory == CODE_ROOT:
            break
    try:
        parts = path.relative_to(CODE_ROOT).parts
    except ValueError:
        return "prototype"
    if parts and parts[0] == "clients":
        return "client"
    if parts and parts[0] in TOOLING_REPOS:
        return "tooling"
    return "prototype"


def deny(reason):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }


def context(event_name, text):
    return {"hookSpecificOutput": {"hookEventName": event_name, "additionalContext": text}}


# --- UserPromptSubmit ----------------------------------------------------------

def user_prompt_submit(event):
    prompt = event.get("prompt") or ""
    if prompt.lstrip().startswith("<codex_internal_context"):
        # Goal mode re-prompts on its own; that is not Tom speaking.
        with State(agent_key(event)) as state:
            if state.get("stop_request"):
                return context(
                    "UserPromptSubmit",
                    "Tom told you to stop, and that outranks the goal. Pause the goal, "
                    "reply ready and end the turn.",
                )
        return None
    with State(agent_key(event)) as state:
        state["prompts"] = (state["prompts"] + [prompt])[-PROMPTS_KEPT:]
        elapsed = time.time() - state["started"]
        opened, closed = tree_counts(event, state)
        lines = [
            f"Scoreboard: {minutes(elapsed)} in, {closed} issues closed, "
            f"{opened} opened. {STANDING}"
        ]
    if CORRECTION.search(prompt):
        lines.append(
            "Tom is correcting you. Drop exactly what he named and keep going. "
            "Don't answer with a new review, verifier, audit, rule, policy or skill "
            "edit. If he asked a question, answer it in your first line."
        )
    with State(agent_key(event)) as state:
        if STOP_REQUEST.search(prompt):
            state["stop_request"] = {"at": time.time(), "calls": 0}
            lines.append(
                "Tom asked you to stop. Send each worker one message to stop, pause the "
                "active goal, then reply ready. Don't verify, re-read issues or wait for "
                "confirmations: work in worktrees survives a restart."
            )
        else:
            state.pop("stop_request", None)
    if CLOSE_REQUEST.search(prompt):
        lines.append(
            "Tom wants this closed. Read the issue's unchecked Done-when box and run "
            "that check yourself in this turn; don't assign it or describe a plan. "
            "If it needs a quiet machine, take an `exclusive` capacity lease. Then "
            "close the issue, or report the measured miss and fix it now."
        )
    return context("UserPromptSubmit", " ".join(lines))


# --- PreToolUse(update_plan) ----------------------------------------------------

CHECKLIST = (
    "End the plan's explanation with this checklist:\n"
    'goal: "<Tom\'s exact words from the request>"\n'
    "profile: <prototype|tooling|client>\n"
    "done-when: <the pass/fail checks>\n"
    "extra checks: none | <check> catches <new failure>\n"
    "workers: none | <n>, one per <issue or area>\n"
    "eta: <minutes> min"
)
CHECKLIST_KEYS = ("goal", "profile", "done-when", "extra checks", "workers", "eta")


def update_plan(event):
    tool_input = event.get("tool_input") or {}
    if isinstance(tool_input, str):
        try:
            tool_input = json.loads(tool_input)
        except ValueError:
            return None
    steps = [s for s in tool_input.get("plan") or [] if isinstance(s, dict)]
    explanation = tool_input.get("explanation") or ""

    with State(agent_key(event)) as state:
        prompts = state["prompts"][-3:]
        quotes = re.findall(r"asked:\s*\"([^\"]{4,})\"", explanation, re.IGNORECASE)
        quoted = any(quoted_in(q, state["prompts"]) for q in quotes)

        for index, step in enumerate(steps, 1):
            if step.get("status") == "completed":
                continue
            text = str(step.get("step", ""))
            for pattern, label, keywords in PLAN_PROCESS:
                if not re.search(pattern, text, re.IGNORECASE) or quoted:
                    continue
                if not asked_keyword(keywords, prompts):
                    return deny(
                        f'No. Step {index} ("{text[:80]}") adds {label}. Nobody asked for '
                        "it, and it's the move that turns ten-minute tasks into five-hour "
                        "ones. Delete the step and resubmit. If Tom literally asked for it, "
                        'add asked: "<his exact words>" to the explanation.'
                    )

        if not steps or any(s.get("status") == "completed" for s in steps):
            return None

        lines = {
            key.lower(): value.strip()
            for key, value in re.findall(
                r"^\s*(goal|profile|done-when|extra checks|workers|eta):\s*(.+)$",
                explanation,
                re.IGNORECASE | re.MULTILINE,
            )
        }
        missing = [key for key in CHECKLIST_KEYS if not lines.get(key)]
        if missing:
            return deny(f"No. The plan is missing: {', '.join(missing)}. {CHECKLIST}")

        goal = lines["goal"].strip().strip('"“”')
        if state["prompts"] and not quoted_in(goal, state["prompts"]):
            return deny(
                "No. The goal line must quote the request word for word, at least three "
                "words. Work nobody asked for is not the job. Re-read the request and "
                "plan only that."
            )
        cited = lines["profile"].split()[0].strip("`*.,").lower()
        expected = expected_profile(event.get("cwd"))
        if cited != expected:
            return deny(
                f"No. The profile here is {expected!r}, not {cited!r} (bootstrap Profile "
                "table). Fix the line and size the plan to that profile."
            )
        extra = lines["extra checks"].lower()
        if not extra.startswith("none") and "catches" not in extra:
            return deny(
                "No. Each extra check names the new failure it would catch: "
                "`extra checks: <check> catches <failure>`. Can't name one? Write `none` "
                "and drop the check."
            )
        eta = re.match(r"(\d+)", lines["eta"])
        if not eta or int(eta.group(1)) <= 0:
            return deny("No. `eta:` must be a number of minutes, like `eta: 25 min`.")
        state["eta"] = {"minutes": int(eta.group(1)), "set_at": time.time(), "warned": False}
    return None


# --- PreToolUse/PostToolUse(Bash) ------------------------------------------------

def segments(command):
    for part in re.split(r"&&|\|\||;|\||\n", command):
        words = part.strip().split()
        while words and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]):
            words = words[1:]
        if words and words[0] in ("env", "time", "nice", "exec"):
            words = words[1:]
        if words:
            yield words


def is_check(command):
    for words in segments(command):
        runner = os.path.basename(words[0])
        rest = " ".join(words[1:])
        if runner in RUNNERS and CHECK_WORDS.search(rest):
            return True
        if (runner.endswith((".sh", ".test.sh")) or runner.startswith("./")) and CHECK_WORDS.search(" ".join(words)):
            return True
    return False


def strip_token(command):
    return parse_case(command)[2]


def check_key(cwd, command):
    command = strip_token(command)
    return hashlib.sha256(f"{cwd}\0{' '.join(command.split())}".encode()).hexdigest()[:24]


def check_name(command):
    """The check a command runs, without where it runs or how it waits."""
    command = re.sub(r"^\s*cd\s+\S+\s*&&\s*", "", strip_token(command))
    command = re.sub(r"\bmachine-capacity\S*\s+run\b.*?\s--\s+", "", command)
    command = re.sub(r"\s--(wait|exit-status)\b|\s--out(=|\s+)\S+", "", command)
    return " ".join(command.split())


def head_commit(cwd):
    """HEAD of a clean checkout, or None when the tree has changes."""
    try:
        run = lambda *args: subprocess.run(
            ["git", "-C", str(cwd), *args], capture_output=True, timeout=5, check=True, text=True
        ).stdout
        if run("status", "--porcelain=v1", "-uno").strip():
            return None
        return run("rev-parse", "HEAD").strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


class SharedRuns:
    """Passing checks by commit, shared by every agent on the machine."""

    def __enter__(self):
        self.path = STATE_ROOT / "passed-by-commit.json"
        try:
            STATE_ROOT.mkdir(parents=True, exist_ok=True)
            self.lock = open(self.path.with_suffix(".lock"), "w")
            fcntl.flock(self.lock, fcntl.LOCK_EX)
            self.data = json.loads(self.path.read_text())
        except (OSError, ValueError):
            self.data = {}
        return self.data

    def __exit__(self, *exc):
        try:
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self.data))
            tmp.replace(self.path)
        except (OSError, AttributeError):
            pass
        if getattr(self, "lock", None):
            self.lock.close()


def run_conclusion(run_id):
    try:
        out = subprocess.run(
            ["gh", "run", "view", run_id, "--json", "conclusion", "-q", ".conclusion"],
            capture_output=True, timeout=6, text=True,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.strip()


def tree_state(cwd):
    try:
        run = lambda *args: subprocess.run(
            ["git", "-C", str(cwd), *args], capture_output=True, timeout=5, check=True
        ).stdout
        head = run("rev-parse", "HEAD")
        status = run("status", "--porcelain=v1", "-uall")
        diff = run("diff", "HEAD", "--no-ext-diff")
    except (OSError, subprocess.SubprocessError):
        return None
    return hashlib.sha256(head + b"\0" + status + b"\0" + diff).hexdigest()


def gh_issue_action(command):
    for words in segments(command):
        if len(words) >= 3 and os.path.basename(words[0]) == "gh" and words[1] == "issue":
            return words[2], words
    return None, None


def issue_body(command, cwd):
    try:
        tokens = shlex.split(command)
    except ValueError:
        return command
    for index, token in enumerate(tokens[:-1]):
        if token in ("--body", "-b"):
            return tokens[index + 1]
        if token in ("--body-file", "-F"):
            path = Path(tokens[index + 1])
            path = path if path.is_absolute() else Path(cwd or ".") / path
            try:
                return path.read_text(errors="ignore")
            except OSError:
                return command
    for token in tokens:
        if token.startswith("--body="):
            return token[len("--body="):]
    return command


def issue_shape_problem(body, creating):
    boxes = re.findall(r"^\s*[-*] \[[ xX]\] (.+)$", body, re.MULTILINE)
    if creating and not re.search(r"done when", body, re.IGNORECASE):
        return "it has no Done when list"
    if creating and not re.search(r"not required", body, re.IGNORECASE):
        return "it has no Not required list, so scope will grow"
    if len(boxes) > MAX_BOXES:
        return f"it has {len(boxes)} boxes; at most {MAX_BOXES}, each a pass/fail check"
    for box in boxes:
        match = GUARANTEE.search(box)
        if match:
            return (
                f'box "{box[:70]}" promises "{match.group(0)}", which no finite test '
                'can close. Make it a measured check, like "500 inputs, 0 lost"'
            )
    return None


HEAVY_SUITE = re.compile(r"\b(scripts/lua-tests\.ts|scripts/cpuTiers\.ts|scripts/cpuField\.ts)\b")
PROCESS_TOOLS = re.compile(r"\b(pkill|pgrep|kill|ps|grep|rg|cat|sed)\b")


def running_copy(cwd, suite):
    """A live process already running `suite` in the same worktree subtree."""
    if not cwd:
        return None
    here = os.path.realpath(cwd)
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            cmdline = Path(f"/proc/{entry}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
            if suite not in cmdline:
                continue
            there = os.path.realpath(os.readlink(f"/proc/{entry}/cwd"))
            started = os.stat(f"/proc/{entry}").st_mtime
        except OSError:
            continue
        if there.startswith(here) or here.startswith(there):
            return int(entry), started
    return None


def pre_bash(event):
    command = (event.get("tool_input") or {}).get("command") or ""
    if isinstance(command, list):
        command = " ".join(command)
    cwd = event.get("cwd")

    suite = HEAVY_SUITE.search(command)
    if suite and not PROCESS_TOOLS.search(command):
        copy = running_copy(cwd, suite.group(1))
        if copy:
            pid, started = copy
            return deny(
                f"No. `{suite.group(1)}` is already running in this worktree (pid {pid}, "
                f"{minutes(time.time() - started)}). Wait for it or stop it; one copy at a time. "
                "Full suites belong on GitHub's runners: `bun wisp farm`."
            )

    action, _ = gh_issue_action(command)
    if action == "create":
        # Only new issues are shaped here: an existing issue's boxes predate
        # these rules, and its Done-when list must not be rewritten mid-flight.
        problem = issue_shape_problem(issue_body(command, cwd), True)
        if problem:
            return deny(f"No. This issue can't close: {problem}. Rewrite it and retry.")
        with State(agent_key(event)) as state:
            prompts = state["prompts"][-3:]
            opened, closed = tree_counts(event, state)
            if opened > closed and not asked_keyword(("issue", "ticket"), prompts):
                return deny(
                    f"No. This session opened {opened} issues and closed "
                    f"{closed}. Close one before opening another. A problem "
                    "that blocks nothing goes in your report as one line."
                )
        return None

    with State(agent_key(event)) as state:
        spawned = state.get("spawned", 0)
    if spawned and (is_check(command) or WORKER_JOB.search(command)):
        if not re.search(r"\bORCH_RUNS_BECAUSE=(\"[^\"]{8,}\"|'[^']{8,}'|\S{8,})", command):
            return deny(
                f"No. You're orchestrating {spawned} workers, so this is a worker's job: "
                "tests, builds, native sessions and log digging. Hand it to a worker and "
                "go back to assigning, merging and closing. If no worker can run it, prefix "
                'the command with ORCH_RUNS_BECAUSE="<why>".'
            )
    case, fact, bare = parse_case(command)
    noop = JUSTIFY_NOOP.match(command)
    if noop:
        return pre_justify(event, noop)
    rerun = re.search(r"\bgh run rerun\s+(\d+)", bare)
    if rerun and run_conclusion(rerun.group(1)) == "success":
        return rerun_gate(event, f"run {rerun.group(1)}", "an earlier run", f"gh-run\0{rerun.group(1)}",
                          case, fact, command)
    if is_measure(bare):
        decision = measure_gate(event, case, fact, command)
        if decision:
            return decision
    if not is_check(bare):
        return None
    name = check_name(bare)
    commit = head_commit(cwd)
    if commit:
        with SharedRuns() as shared:
            record = shared.get(f"{commit}\0{name}")
        if record:
            at = time.strftime("%H:%M", time.localtime(record.get("at", 0)))
            return rerun_gate(event, name, at, f"{commit}\0{name}", case, fact, command)
    with State(agent_key(event)) as state:
        record = state["passed"].get(check_key(cwd, bare))
    if not record:
        return None
    tree = tree_state(cwd)
    if tree != record.get("tree"):
        return None
    at = time.strftime("%H:%M", time.localtime(record.get("at", 0)))
    return rerun_gate(event, name, at, f"{tree}\0{name}", case, fact, command)


RERUN_CASES = (
    "Which case is it?\n"
    "A. It reads something outside the worktree that changed since {at} (a rebuilt map, a new "
    "client build): proceed, and name it in FACT.\n"
    "B. Tom asked for a rerun: proceed; the hook checks his last 3 prompts.\n"
    "C. A rerun for confidence before landing: stop and land with safe-push. On 8 Oct #244's "
    "worker spent 95 min and 31.9M tokens on five more CI runs after its boxes passed, and four "
    "tuning workers ran the same balance baseline on febfa549 within six minutes.\n"
    "D. The last pass looked flaky: stop and report it in one line. Never rerun until it passes.\n"
    "E. You lost the output: rerun once, with `| tee FILE`.\n"
    "F. A frame-cost or latency check confirming once on a quiet machine, under an exclusive "
    "capacity lease: proceed, and name the load difference in FACT.\n"
    "To proceed, prefix the command with CASE=<letter> FACT=\"<the one new fact this run shows>\". "
    "One justification per check and code state. "
)
TIMING_CHECK = re.compile(r"\b(perf|bench\w*|frame[- ]?cost|latency|timing)\b", re.IGNORECASE)
RERUN_ASKED = ("rerun", "re run", "again", "retry", "run it once more")


def rerun_gate(event, name, at, fingerprint, case, fact, command):
    lead = f"`{name[:80]}` already passed on this code at {at}. {ONE_RUN}\n"
    if not case:
        return deny(lead + RERUN_CASES.format(at=at) + PEER_LINE)
    problem = None
    with State(agent_key(event)) as state:
        prompts = state["prompts"][-3:]
    if case in ("C", "D"):
        problem = {
            "C": "Case C stops here: land it with `safe-push --to main` and tick the box.",
            "D": "Case D stops here: report the flaky result in one line; don't rerun it until it passes.",
        }[case]
    elif case == "B":
        if not asked_keyword(RERUN_ASKED, prompts):
            problem = "Case B needs Tom's ask: none of his last 3 prompts asks for a rerun."
    elif case == "E" and not re.search(r"\|\s*tee\b", command):
        problem = "Case E reruns only with `| tee FILE`, so the output survives this time."
    elif case == "F" and not (TIMING_CHECK.search(name) and "exclusive" in command):
        problem = "Case F is only for a frame-cost or latency check run under an exclusive capacity lease."
    elif case not in "ABEF":
        problem = f"There is no case {case}."
    if not problem and case != "B":
        problem = fact_problem(fact)
    if not problem:
        with SharedRuns() as shared:
            used = shared.setdefault("justified", {})
            key = hashlib.sha256(fingerprint.encode()).hexdigest()[:24]
            if used.get(key):
                problem = "This check already used its one justification on this code."
            else:
                used[key] = case
    if problem:
        return deny(lead + problem + " " + PEER_LINE)
    log_override(event, "rerun", case, fact)
    return None


MEASURE_CMD = re.compile(
    r"\b(bench\w*|perf|soak|profil\w*|hyperfine)\b|(^|[;&|]\s*)time\s|"
    r"\b(for|while)\b[^;]*;\s*do\b",
    re.IGNORECASE,
)
MEASURE_LIMIT = 2


def is_measure(command):
    return bool(MEASURE_CMD.search(command))


def measure_gate(event, case, fact, command):
    with State(agent_key(event)) as state:
        count = state.get("measures", 0)
        baseline = state.get("fix_baseline")
        if count < MEASURE_LIMIT and not baseline:
            return None
        lead = (
            f"You've run {count} measurements since your last change. Tom's rule: a measurement "
            "ends in a fix you land, or a PEER line.\n"
        )
        if baseline:
            return deny(lead + "You took a fix: baseline already. Make the fix first; the next "
                        "measurement needs a patch in between. " + PEER_LINE)
        if not case:
            return deny(
                lead + "Which case is it?\n"
                "A. A box asks for this number: proceed; FACT starts `box:` and quotes the box.\n"
                "B. A baseline for a fix you're about to make: proceed; FACT starts `fix:` and "
                "names the fix. The next measurement needs a patch first.\n"
                "C. To understand the problem better: stop and change the likeliest cause. On "
                "8 Oct perf_phases_168 spent 6.0M tokens on a phase table, wrote \"No "
                "optimization was made\", and #168 stayed at 18.26 ms against 10 ms.\n"
                "D. To confirm the earlier number: stop and report it.\n"
                "To proceed, prefix the command with CASE=<letter> FACT=\"box: ...\" or "
                "FACT=\"fix: ...\". " + PEER_LINE
            )
        problem = None
        if case in ("C", "D"):
            problem = {"C": "Case C stops here: change the likeliest cause now.",
                       "D": "Case D stops here: report the number you have."}[case]
        elif case == "A" and not (fact or "").lower().startswith("box:"):
            problem = "Case A's FACT starts `box:` and quotes the box that asks for this number."
        elif case == "B" and not (fact or "").lower().startswith("fix:"):
            problem = "Case B's FACT starts `fix:` and names the fix you're about to make."
        elif case not in "AB":
            problem = f"There is no case {case}."
        problem = problem or fact_problem(fact)
        if problem:
            return deny(lead + problem + " " + PEER_LINE)
        state["measures"] = 0
        if case == "B":
            state["fix_baseline"] = True
    log_override(event, "measure", case, fact)
    return None


def pre_justify(event, match):
    """`: justify <gate> <case> "<fact>"` arms one patch for the scaffold gate."""
    gate, case = match.group(1), match.group(2).upper()
    fact = match.group(4) if match.group(4) is not None else match.group(5)
    problem = None
    if gate != "scaffold":
        problem = "Only the scaffold gate takes `: justify`; other gates take a CASE= FACT= prefix."
    elif case == "C":
        problem = "Case C stops here: drop the traceability or later-readiness part."
    elif case == "A":
        problem = "Case A is checked by the hook from Tom's prompts; just retry the patch if he asked."
    elif case not in "BD":
        problem = f"There is no case {case}."
    problem = problem or fact_problem(fact)
    if problem:
        return deny(problem + " " + PEER_LINE)
    with State(agent_key(event)) as state:
        state["scaffold_ok"] = {"case": case, "fact": fact, "at": time.time()}
    log_override(event, "scaffold", case, fact)
    return None


MEASURE_ONLY = re.compile(
    r"\b(measure|measurement|profil\w*|diagnos\w*|investigat\w*|research)[- ]only\b|"
    r"\bno (fix|optimi[sz]ation|code change)s? (in|for) (this|that) task\b|"
    r"\b(do not|don'?t) (fix|change|optimi[sz]e)\b|\bwithout (landing |making )?(a |any )?fix\b",
    re.IGNORECASE,
)
MEASURE_OUTCOME = re.compile(r"\bPEER\b|\bland(s|ing)? (a |the |its |one )?fix\b|\bfix it lands\b", re.IGNORECASE)


def pre_spawn(event):
    tool_input = event.get("tool_input") or {}
    brief = json.dumps(tool_input) if not isinstance(tool_input, str) else tool_input
    if MEASURE_ONLY.search(brief) and not MEASURE_OUTCOME.search(brief):
        return deny(
            "This brief only measures. Tom's rule: a measurement worker ends with a fix it "
            "lands, or a PEER line naming what the numbers point to. On 8 Oct "
            "perf_phases_168 spent 6.0M tokens on a measure-only brief and #168 moved no "
            "number. To retry, add one line to the brief: \"End with a fix you land, or a "
            "PEER line.\""
        )
    return None


SCAFFOLD_WORDS = (
    "manifest", "provenance", "attest", "sbom", "checksum", "schema_version", "migration",
    "compat", "changelog", "release", "inventory", "sha256",
)
SCAFFOLD_FILE = re.compile(
    r"(^|[/_.-])(" + "|".join(SCAFFOLD_WORDS) + r")\w*([._-][^/]*)?$|\.(sha256|sha256sum|sha512)$",
    re.IGNORECASE,
)


def new_files(event):
    tool = event.get("tool_name")
    tool_input = event.get("tool_input") or {}
    text = tool_input.get("command") if isinstance(tool_input, dict) else str(tool_input)
    if isinstance(text, list):
        text = " ".join(text)
    text = text or ""
    if tool == "Bash":
        return re.findall(r"(?:>>?|\btee(?:\s+-a)?|\btouch)\s+['\"]?([^\s'\";|&<>]+)", text)
    if tool == "Write" and isinstance(tool_input, dict) and tool_input.get("file_path"):
        return [tool_input["file_path"]]
    return re.findall(r"^\*\*\* Add File:\s*(\S+)", text, re.MULTILINE)


def pre_scaffold(event):
    cwd = event.get("cwd")
    paths = [p for p in new_files(event) if SCAFFOLD_FILE.search(p)]
    if not paths:
        return None
    root = CODE_ROOT.resolve()
    inside = []
    for name in paths:
        path = Path(name) if Path(name).is_absolute() else Path(cwd or ".") / name
        resolved = path.resolve()
        if resolved.is_relative_to(root) and not resolved.exists() \
                and expected_profile(resolved.parent if resolved.parent.exists() else cwd) == "prototype":
            inside.append(name)
    if not inside:
        return None
    word = SCAFFOLD_FILE.search(inside[0]).group(2) or "sha256"
    with State(agent_key(event)) as state:
        prompts = state["prompts"][-3:]
        armed = state.pop("scaffold_ok", None)
    if asked_keyword((word.lower(),), prompts) or armed:
        return None
    return deny(
        f"`{inside[0]}` adds a {word} file to a prototype repo, and none of Tom's last 3 "
        "prompts asks for one. Tom is the only user. Which case is it?\n"
        "A. Tom asked for it: the hook checks his prompts, so this isn't A.\n"
        "B. The build or run fails without it: name the command and its error.\n"
        "C. Traceability, safety or readiness for later: stop and drop that part. On 8 Oct "
        "the #168 worker committed tapes.sha256, a generator SHA256 and 384 KB of samples, "
        "and 20 of 180 Smashcraft commits only added such records (evidence/ is 391 MB).\n"
        "D. Another tool requires this format: treat it as B.\n"
        "To proceed with B or D, run `: justify scaffold B \"<command and its error>\"`, then "
        "retry the patch. Otherwise put the result in the issue comment. " + PEER_LINE
    )


def read_only(command):
    parts = list(segments(command))
    if not parts:
        return False
    for words in parts:
        head = os.path.basename(words[0])
        if head == "cd":
            continue
        if head == "sed" and "-n" in words and "-i" not in words:
            continue
        if head == "git" and len(words) > 1 and words[1] in READ_ONLY_GIT:
            continue
        if head == "gh" and len(words) > 2 and words[2] in ("view", "list") or (
            head == "gh" and len(words) > 1 and words[1] == "api" and "-X" not in words and "--method" not in words
        ):
            continue
        if head not in READ_ONLY_WORDS:
            return False
    return True


def exit_code(response):
    text = response if isinstance(response, str) else json.dumps(response)
    match = EXIT_CODE.search(text)
    return int(match.group(1)) if match else None


def post_bash(event):
    command = (event.get("tool_input") or {}).get("command") or ""
    if isinstance(command, list):
        command = " ".join(command)
    cwd = event.get("cwd")
    command = strip_token(command)
    code = exit_code(event.get("tool_response"))
    notes = []
    with State(agent_key(event)) as state:
        overrun = stop_overrun(state)
        if overrun:
            notes.append(overrun)
        if read_only(command):
            state["streak"] = state.get("streak", 0) + 1
            if state["streak"] == STREAK_LIMIT:
                notes.append(
                    f"You've run {STREAK_LIMIT} read-only commands since your last change or "
                    "run. Stop reading. Make the change you think is right and let the build "
                    "or test tell you if it's wrong."
                )
        else:
            state["streak"] = 0
        action, words = gh_issue_action(command)
        if code == 0 and action == "create":
            state["opened"] += 1
        if code == 0 and action == "close":
            numbers = [w for w in words[3:] if re.fullmatch(r"#?\d+|https?://\S+/issues/\d+", w)]
            state["closed"] += max(1, len(numbers))
            state["last_close"] = time.time()
        if is_check(command) and code is not None:
            key = check_key(cwd, command)
            if code == 0:
                tree = tree_state(cwd)
                if tree:
                    state["passed"][key] = {"tree": tree, "at": time.time()}
                commit = head_commit(cwd)
                if commit:
                    with SharedRuns() as shared:
                        shared.setdefault(f"{commit}\0{check_name(command)}", {"at": time.time()})
                if LAND_CHECK.search(command) and unlanded(cwd):
                    state["last_pass"] = {"cwd": cwd, "tree": tree, "at": time.time()}
                    state["land_wait"] = 0
                    notes.append(
                        "That check passed. Land it now: commit, `safe-push --to main`, then "
                        "tick the box. No more checks first."
                    )
            else:
                state["passed"].pop(key, None)
        elif LANDING.search(command) and code == 0:
            state.pop("land_wait", None)
        elif state.get("land_wait") is not None:
            state["land_wait"] += 1
            if state["land_wait"] >= LAND_NUDGE:
                state.pop("land_wait", None)
                notes.append(
                    f"{LAND_NUDGE} commands since a passing check and still nothing landed. "
                    "Land now, or say in one line which box is still failing."
                )
        if is_measure(command) and code is not None:
            state["measures"] = state.get("measures", 0) + 1
        if action in ("edit", "view", "comment") and code == 0:
            text = issue_body(command, cwd) if action == "edit" else str(event.get("tool_response") or "")
            ticked = re.findall(r"^\s*[-*] \[[xX]\] ", text, re.MULTILINE)
            open_box = re.search(r"^\s*[-*] \[ \] ", text, re.MULTILINE)
            closed = re.search(r"\bstate:\s*closed\b|\"state\":\s*\"CLOSED\"", text, re.IGNORECASE)
            if ticked and not open_box and not closed:
                number = next((w for w in words[3:] if re.fullmatch(r"#?\d+", w)), "it")
                notes.append(
                    f"Every box on issue {number} is ticked. Close it now: `gh issue close "
                    f"{number} --comment \"<run and commit>\"`. Don't run anything else first. "
                    + PEER_LINE
                )
        eta = state.get("eta")
        if eta and not eta.get("warned"):
            spent = time.time() - eta["set_at"]
            if spent > 2 * eta["minutes"] * 60:
                eta["warned"] = True
                notes.append(
                    f"You're at {minutes(spent)} on a {eta['minutes']} min ETA, more than "
                    "twice over. Stop expanding. Land what passes now, close what's done, "
                    "and report the rest with a new ETA and the reason."
                )
    return context("PostToolUse", " ".join(notes)) if notes else None


LAND_CHECK = re.compile(r"\b(test|tests|check|typecheck|farm|sweep|parity|verify|validate)\b")
LANDING = re.compile(r"\b(git commit|safe-push|git push)\b")
LAND_NUDGE = 3


def unlanded(cwd):
    """True when the worktree has uncommitted changes or commits not on origin/main."""
    try:
        run = lambda *args: subprocess.run(
            ["git", "-C", str(cwd), *args], capture_output=True, timeout=5, text=True
        )
        if run("status", "--porcelain=v1", "-uno").stdout.strip():
            return True
        ahead = run("rev-list", "--count", "origin/main..HEAD")
        return ahead.returncode == 0 and ahead.stdout.strip() not in ("", "0")
    except (OSError, subprocess.SubprocessError):
        return False


def stop_overrun(state):
    request = state.get("stop_request")
    if not request:
        return None
    request["calls"] += 1
    if request["calls"] < STOP_CALL_LIMIT or request["calls"] % STOP_CALL_LIMIT:
        return None
    return (
        f"Tom told you to stop {request['calls']} commands ago "
        f"({minutes(time.time() - request['at'])}). Reply ready now."
    )


def post_spawn(event):
    with State(agent_key(event)) as state:
        state["spawned"] = state.get("spawned", 0) + 1
    return None


def post_patch(event):
    with State(agent_key(event)) as state:
        state["streak"] = 0
        state["measures"] = 0
        state.pop("fix_baseline", None)
        overrun = stop_overrun(state)
    return context("PostToolUse", overrun) if overrun else None


# --- Stop ------------------------------------------------------------------------

def block(reason):
    return {"decision": "block", "reason": reason}


def stop(event):
    if event.get("stop_hook_active"):
        return None
    message = (event.get("last_assistant_message") or "").strip()
    if not message:
        return None
    if not re.match(r"\W*(not done|blocked):", message, re.IGNORECASE):
        with State(agent_key(event)) as state:
            last = state.get("last_pass")
        if last and tree_state(last["cwd"]) == last["tree"] and unlanded(last["cwd"]):
            return block(
                "Your last check passed on code that isn't landed. Land it now with "
                "`safe-push --to main` and close the box, then send a 3-line report starting "
                "\"Done:\". If something blocks landing, start with \"Blocked:\" and the exact "
                "error. Don't add checks."
            )
    if STOP_MISSING_TOOL.search(message) and not re.search(r"\berror\b|\bfailed with\b", message, re.IGNORECASE):
        return block(
            "No. You say a tool is missing, but you never got an error from calling it. "
            "Call it directly first. spawn_agent, send_message, followup_task, list_agents "
            "and wait_agent are direct collaboration tools; exec's ALL_TOOLS lists only "
            "scripting tools. Report a missing tool only with the error its call returned."
        )
    if (
        ESCALATION.search(message)
        and not NEEDS_NOTHING.search(message)
        and not ATTEMPT_EVIDENCE.search(message)
        and not REAL_ASK.search(message)
    ):
        return block(
            "No. You're escalating without having tried. Try it, and come back only with the "
            "error it returned. Tom decides only money, accounts, sending as him, deleting "
            "data you didn't create, and product choices."
        )
    final = last_sentence(message[-600:])
    if "needs you:" in message.lower():
        final = ""
    if STOP_ASKING.search(final):
        return block(
            "No. You ended by asking permission. Tom gave you authority over everything "
            "reversible: do it now and report the result. If it truly needs him (money, "
            "accounts, sending as Tom, deleting data you didn't create, a product fork), "
            "end with `Needs you: <action>` and your recommendation."
        )
    if STOP_NARRATING.search(final):
        return block(
            "No. You ended on a plan or a hand-off. That's not an ending. Do the next step "
            "yourself, now, and stop only when it's done or blocked."
        )
    if LANDED.search(message) and not BOX_ACCOUNTED.search(message):
        return block(
            "No. You landed it but closed nothing. Tick the issue box it satisfies or close "
            "the issue now, then end. If it ticks no box yet, say which box remains."
        )
    if STOP_DISCLAIMERS.search(message):
        return block(
            "No. Delete the list of what the result doesn't prove. Give the result, the "
            "numbers and one line of remaining risk."
        )
    if STOP_NEARLY.search(message) and not re.search(r"\d+ (of|/) ?\d+|\d+ (left|remaining)", message):
        return block("No. 'Nearly done' means nothing. Give a count of what's left.")
    return None


def take_relay(event):
    """A commander's message for a root session, delivered once and removed."""
    if event.get("agent_id"):
        return None
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", str(event.get("session_id") or ""))
    path = STATE_ROOT / f"relay-{safe}.txt"
    try:
        text = path.read_text().strip()
        path.unlink()
    except OSError:
        return None
    return f"Message from Tom's commander: {text}" if text else None


def with_relay(event, decision):
    relay = take_relay(event)
    if not relay:
        return decision
    name = event.get("hook_event_name")
    if name == "Stop":
        if decision and decision.get("decision") == "block":
            decision["reason"] = relay + " " + decision["reason"]
            return decision
        return block(relay)
    if decision and decision.get("hookSpecificOutput", {}).get("permissionDecision") == "deny":
        return decision
    extra = (decision or {}).get("hookSpecificOutput", {}).get("additionalContext")
    return context(name, relay + (" " + extra if extra else ""))


def decide(event):
    name = event.get("hook_event_name")
    if name in ("PostToolUse", "Stop") and not event.get("stop_hook_active"):
        return with_relay(event, decide_event(event))
    return decide_event(event)


def decide_event(event):
    name = event.get("hook_event_name")
    tool = event.get("tool_name")
    if name == "UserPromptSubmit":
        return user_prompt_submit(event)
    if name == "PreToolUse" and tool == "update_plan":
        return update_plan(event)
    if name == "PreToolUse" and str(tool).endswith("spawn_agent"):
        return pre_spawn(event)
    if name == "PreToolUse" and tool in ("Bash", "apply_patch", "Write", "Edit"):
        decision = pre_scaffold(event)
        if decision or tool != "Bash":
            return decision
        return pre_bash(event)
    if name == "PostToolUse" and tool == "Bash":
        return post_bash(event)
    if name == "PostToolUse" and tool == "apply_patch":
        return post_patch(event)
    if name == "PostToolUse" and str(tool).endswith("spawn_agent"):
        return post_spawn(event)
    if name == "Stop":
        return stop(event)
    return None


def main():
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return 0
    decision = decide(event) if isinstance(event, dict) else None
    if decision:
        print(json.dumps(decision))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
