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
  in a session that has spawned workers, a check rerun on unchanged code, a new issue that
  can't close, and a new issue while the session has opened more than it
  closed. Edits to existing issues pass.
- PostToolUse(Bash) records passing checks and issue opens and closes, and
  says once when the work passes twice its ETA or after a long run of
  read-only commands with no change; an apply_patch ends that run.
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
    r"\b(test|tests|check|lint|typecheck|tsc|clippy|validate|verify|soak|parity|bench|perf|smoke|build)\b"
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
        with State(event.get("session_id")) as state:
            if state.get("stop_request"):
                return context(
                    "UserPromptSubmit",
                    "Tom told you to stop, and that outranks the goal. Pause the goal, "
                    "reply ready and end the turn.",
                )
        return None
    with State(event.get("session_id")) as state:
        state["prompts"] = (state["prompts"] + [prompt])[-PROMPTS_KEPT:]
        elapsed = time.time() - state["started"]
        lines = [
            f"Scoreboard: {minutes(elapsed)} in, {state['closed']} issues closed, "
            f"{state['opened']} opened. {STANDING}"
        ]
    if CORRECTION.search(prompt):
        lines.append(
            "Tom is correcting you. Drop exactly what he named and keep going. "
            "Don't answer with a new review, verifier, audit, rule, policy or skill "
            "edit. If he asked a question, answer it in your first line."
        )
    with State(event.get("session_id")) as state:
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

    with State(event.get("session_id")) as state:
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


def rerun_reason(command):
    match = re.search(r"\bRERUN_BECAUSE=(\"[^\"]*\"|'[^']*'|\S+)", command)
    if not match:
        return ""
    return match.group(1).strip("\"'")


def check_key(cwd, command):
    command = re.sub(r"\bRERUN_BECAUSE=(\"[^\"]*\"|'[^']*'|\S+)\s*", "", command)
    return hashlib.sha256(f"{cwd}\0{' '.join(command.split())}".encode()).hexdigest()[:24]


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


def pre_bash(event):
    command = (event.get("tool_input") or {}).get("command") or ""
    if isinstance(command, list):
        command = " ".join(command)
    cwd = event.get("cwd")

    action, _ = gh_issue_action(command)
    if action == "create":
        # Only new issues are shaped here: an existing issue's boxes predate
        # these rules, and its Done-when list must not be rewritten mid-flight.
        problem = issue_shape_problem(issue_body(command, cwd), True)
        if problem:
            return deny(f"No. This issue can't close: {problem}. Rewrite it and retry.")
        with State(event.get("session_id")) as state:
            prompts = state["prompts"][-3:]
            if state["opened"] > state["closed"] and not asked_keyword(("issue", "ticket"), prompts):
                return deny(
                    f"No. This session opened {state['opened']} issues and closed "
                    f"{state['closed']}. Close one before opening another. A problem "
                    "that blocks nothing goes in your report as one line."
                )
        return None

    with State(event.get("session_id")) as state:
        spawned = state.get("spawned", 0)
    if spawned and (is_check(command) or WORKER_JOB.search(command)):
        if not re.search(r"\bORCH_RUNS_BECAUSE=(\"[^\"]{8,}\"|'[^']{8,}'|\S{8,})", command):
            return deny(
                f"No. You're orchestrating {spawned} workers, so this is a worker's job: "
                "tests, builds, native sessions and log digging. Hand it to a worker and "
                "go back to assigning, merging and closing. If no worker can run it, prefix "
                'the command with ORCH_RUNS_BECAUSE="<why>".'
            )
    if not is_check(command):
        return None
    if len(rerun_reason(command)) >= 8:
        return None
    with State(event.get("session_id")) as state:
        record = state["passed"].get(check_key(cwd, command))
    if not record:
        return None
    if tree_state(cwd) != record.get("tree"):
        return None
    at = time.strftime("%H:%M", time.localtime(record.get("at", 0)))
    return deny(
        f"No. This exact check passed at {at} and the code hasn't changed since. "
        "Running it again proves nothing new. Land it and close the box. If a rerun "
        'really can catch a new failure, prefix the command with RERUN_BECAUSE="<that failure>".'
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
    code = exit_code(event.get("tool_response"))
    notes = []
    with State(event.get("session_id")) as state:
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
            else:
                state["passed"].pop(key, None)
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
    with State(event.get("session_id")) as state:
        state["spawned"] = state.get("spawned", 0) + 1
    return None


def post_patch(event):
    with State(event.get("session_id")) as state:
        state["streak"] = 0
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


def decide(event):
    name = event.get("hook_event_name")
    tool = event.get("tool_name")
    if name == "UserPromptSubmit":
        return user_prompt_submit(event)
    if name == "PreToolUse" and tool == "update_plan":
        return update_plan(event)
    if name == "PreToolUse" and tool == "Bash":
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
