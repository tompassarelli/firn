"""Decisions for codex-behavior-guard.sh, one per Codex hook event.

UserPromptSubmit remembers Tom's prompts for the session and, when a prompt
reads as a correction, adds the correction rule as context. PreToolUse on
update_plan rejects a plan that adds process from the recorded Codex failure
list, or a first plan without the rule-citing checklist. Stop rejects one
ending per turn that asks permission, narrates the next step, or lists what a
result doesn't prove. Every decision prints one JSON object or nothing.
"""

import json
import os
import re
import sys
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

CORRECTION = re.compile(
    r"\b(fuck\w*|shit\w*|wtf|ffs|jesus|stop (asking|doing|with|adding|it)|"
    r"(i|i've) (already )?(told|asked) you|you keep|again\?|why (are|do|did) you|"
    r"for the (second|third|fourth) time|not what i asked|too much (process|ceremony))\b",
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
    r"continuing with|i(?:'ll| will) (continue|proceed|start|keep))\b",
    re.IGNORECASE,
)
STOP_DISCLAIMERS = re.compile(
    r"\b(does not|doesn't|do not|don't) (prove|establish|demonstrate)\b|"
    r"\bremains? (unproven|unobserved|unestablished)\b|\bnot yet (established|proven)\b",
    re.IGNORECASE,
)
STOP_NEARLY = re.compile(r"\b(nearly|almost) (done|there|finished|complete)\b", re.IGNORECASE)


NEGATION = re.compile(r"\b(no|not|don't|dont|stop|without|never|skip|drop|enough)\b[^.!?\n]{0,30}$")


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


def normalize(text):
    return " ".join(re.sub(r"[^\w\s]", " ", text.lower()).split())


def state_file(session):
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", str(session or "unknown"))
    return STATE_ROOT / f"{safe}.json"


def load_prompts(session):
    try:
        return json.loads(state_file(session).read_text())
    except (OSError, ValueError):
        return []


def save_prompt(session, prompt):
    prompts = (load_prompts(session) + [prompt])[-PROMPTS_KEPT:]
    try:
        STATE_ROOT.mkdir(parents=True, exist_ok=True)
        path = state_file(session)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(prompts))
        tmp.replace(path)
    except OSError:
        pass


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


def user_prompt_submit(event):
    prompt = event.get("prompt") or ""
    save_prompt(event.get("session_id"), prompt)
    if not CORRECTION.search(prompt):
        return None
    return {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": (
                "Tom is correcting you. Drop exactly what he named and keep going. "
                "Don't answer with a new review, verifier, audit, rule, policy or "
                "skill edit. If he asked a question, answer it in your first line."
            ),
        }
    }


def deny(reason):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }


CHECKLIST = (
    "End the plan's explanation with this checklist, citing each rule:\n"
    "profile: <prototype|tooling|client>  (bootstrap Profile table)\n"
    "done-when: <the pass/fail checks>  (bootstrap Finish)\n"
    "extra checks: none | <check> catches <new failure>  (Codex: ship it)\n"
    "workers: none | <n>, one per <issue or area>  (bootstrap Workers)"
)


def asked_for(text, prompts):
    quotes = re.findall(r"asked:\s*\"([^\"]{4,})\"", text, re.IGNORECASE)
    joined = normalize(" ".join(prompts))
    return [q for q in quotes if normalize(q) and normalize(q) in joined]


def update_plan(event):
    tool_input = event.get("tool_input") or {}
    if isinstance(tool_input, str):
        try:
            tool_input = json.loads(tool_input)
        except ValueError:
            return None
    steps = [s for s in tool_input.get("plan") or [] if isinstance(s, dict)]
    explanation = tool_input.get("explanation") or ""
    prompts = load_prompts(event.get("session_id"))
    quoted = asked_for(explanation, prompts)

    for index, step in enumerate(steps, 1):
        if step.get("status") == "completed":
            continue
        text = str(step.get("step", ""))
        for pattern, label, keywords in PLAN_PROCESS:
            if not re.search(pattern, text, re.IGNORECASE) or quoted:
                continue
            if not asked_keyword(keywords, prompts[-3:]):
                return deny(
                    f'Step {index} ("{text[:80]}") adds {label}, which Tom\'s history shows '
                    "turns short tasks into long ones. Remove the step and resubmit the plan. "
                    "If Tom explicitly asked for it, keep it and add asked: \"<his exact words>\" "
                    "to the explanation."
                )

    if not steps or any(s.get("status") == "completed" for s in steps):
        return None

    lines = {
        key: value.strip()
        for key, value in re.findall(
            r"^\s*(profile|done-when|extra checks|workers):\s*(.+)$", explanation, re.IGNORECASE | re.MULTILINE
        )
    }
    lines = {key.lower(): value for key, value in lines.items()}
    missing = [k for k in ("profile", "done-when", "extra checks", "workers") if not lines.get(k)]
    if missing:
        return deny(f"First plan is missing: {', '.join(missing)}. {CHECKLIST}")

    cited = lines["profile"].split()[0].strip("`*.,").lower()
    expected = expected_profile(event.get("cwd"))
    if cited != expected:
        return deny(
            f"You cited profile {cited!r}, but the bootstrap Profile table gives "
            f"{expected!r} for {event.get('cwd')}. Re-read it, fix the profile line, "
            "and size the plan to that profile."
        )
    extra = lines["extra checks"].lower()
    if not extra.startswith("none") and "catches" not in extra:
        return deny(
            "Each extra check needs the new failure it would catch: "
            "`extra checks: <check> catches <failure>`. If you can't name one, write `none` "
            "and drop the check."
        )
    return None


def block(reason):
    return {"decision": "block", "reason": reason}


def stop(event):
    if event.get("stop_hook_active"):
        return None
    message = (event.get("last_assistant_message") or "").strip()
    if not message:
        return None
    final = last_sentence(message[-600:])
    if "needs you:" in message.lower():
        final = ""
    if STOP_ASKING.search(final):
        return block(
            "Your turn ended by asking permission. Tom has given you authority over everything "
            "reversible (bootstrap Act), so do it now and report the result. If it truly needs him "
            "(money, accounts, sending as Tom, deleting data you didn't create, or a product fork), "
            "end with `Needs you: <action>` and your recommendation."
        )
    if STOP_NARRATING.search(final):
        return block(
            "Your turn ended on a progress update. A progress update is not an ending "
            "(bootstrap Act). Do the next step now and end only when the goal is done or "
            "blocked."
        )
    if STOP_DISCLAIMERS.search(message):
        return block(
            "Rewrite the report without listing what the result doesn't prove. Give the result, "
            "the numbers, and one line of remaining risk (bootstrap Report)."
        )
    if STOP_NEARLY.search(message) and not re.search(r"\d+ (of|/) ?\d+|\d+ (left|remaining)", message):
        return block("You said nearly done. Replace it with a count of what's left (bootstrap Report).")
    return None


def decide(event):
    name = event.get("hook_event_name")
    if name == "UserPromptSubmit":
        return user_prompt_submit(event)
    if name == "PreToolUse" and event.get("tool_name") == "update_plan":
        return update_plan(event)
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
