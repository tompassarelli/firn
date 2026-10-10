#!/usr/bin/env python3
"""Spawn gate: refuse a new local worker once provisioned CPU is used up.

Shared by the Claude PreToolUse(Agent) hook (spawn-capacity-guard.sh) and the
Codex behavior guard's PreToolUse(spawn_agent). A worker idles while its model
thinks and its heavy commands run inside capacity leases, so admission counts
the CPUs batch work commits (machine-capacity `probe`: committedBatchCpus, each
live batch lease at max(reserved, measured) plus unleased heavy load, against
aggregateCpuLimit; native clients count only through the protected-pressure
check, since their 2-CPU charge per desktop and client overstates them) rather than system CPU pressure. It also refuses while the
protected desktop slice is under pressure (protectedCpuSomeAvg10 above 20; skipped in
the unattended profile, as the helper does). A
missing, slow (2 s) or unreadable helper allows. An urgent fix passes with
`CASE=URGENT FACT="..."` at the start of the brief, logged beside the Codex
behavior overrides. The capacity watchdog (a brief carrying
`[routine:watchdog]`) is never refused, since it reports the overload.

Delegation: a Claude Agent spawn is refused when the spawner's delegation
budget is 0. A subagent's budget is the `Delegation: ... budget=N` line of its
own brief (none: worker, 0); a session's is AGENT_DELEGATION_BUDGET, else the
default for AGENT_ROLE, and an unset role is Tom's proxy (3). Priority: a
session whose org node (AGENT_ORG_NAME in ~/.local/state/agents/org.json)
belongs to a project below the first in orchestration.toml's [projects] priority order stops at
(1 - PRIORITY_HEADROOM) of the CPU limit.
"""

import json
import os
import re
import sys
import time
import tomllib
from pathlib import Path

PROTECTED_PRESSURE_LIMIT = 20.0
HELPER_TIMEOUT = 2.0
LOCAL_CLAUDE_TYPES = {"worker", "worker-high", "worker-xhigh", "worker-haiku", "general-purpose", "Explore", "fork"}
ACTIVE_SECONDS = 300
EXEMPT_MARKER = "[routine:watchdog]"
ROLE_BUDGETS = {"proxy": 3, "lead": 2, "sub-lead": 1, "worker": 0}
PRIORITY_HEADROOM = 0.2
DELEGATION = re.compile(r"(?mi)^\W*Delegation:.*?\bbudget\s*=\s*(\d+)")
URGENT = re.compile(r"(?m)^\W*CASE=URGENT\s+FACT=(?:[\"“”]([^\"“”]*)[\"“”]|['‘’]([^'‘’]*)['‘’])", re.IGNORECASE)


def helper_path():
    here = Path(__file__).resolve().parent
    for candidate in (
        here.parent.parent / "skills/machine-capacity/scripts/machine-capacity.mjs",
        Path.home() / ".agents/skills/machine-capacity/scripts/machine-capacity.mjs",
    ):
        if candidate.is_file():
            return candidate
    return None


def capacity_probe():
    """The helper's probe JSON as a dict, or None when it can't be read."""
    fixture = os.environ.get("SPAWN_CAPACITY_STATUS")
    try:
        if fixture is not None:
            raw = Path(fixture).read_text()
        else:
            import shutil
            import subprocess
            helper = helper_path()
            bun = shutil.which("bun") or shutil.which("bun", path=str(Path.home() / ".nix-profile/bin"))
            if helper is None or bun is None:
                return None
            raw = subprocess.run([bun, str(helper), "probe", "--class", "agent"], capture_output=True,
                                 text=True, timeout=HELPER_TIMEOUT, stdin=subprocess.DEVNULL).stdout
        data = json.loads(raw)
    except Exception:  # a missing, slow or broken helper allows
        return None
    return data if isinstance(data, dict) else None


def number(value):
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def capacity():
    """(provisioned CPUs, CPU limit, protected pressure) or None to allow."""
    data = capacity_probe()
    if data is None:
        return None
    provisioned = number(data.get("committedBatchCpus"))
    if provisioned is None:
        provisioned = number(data.get("leasedBatchCpus"))
    limit = number(data.get("aggregateCpuLimit")) or float(os.cpu_count() or 1)
    protected = number(data.get("protectedCpuSomeAvg10"))
    if provisioned is None or protected is None:
        return None
    if data.get("profile") == "unattended":
        protected = 0.0
    return provisioned, limit, protected


def local_workers():
    """Claude subagent transcripts and Codex rollouts written in the last five minutes."""
    home = Path(os.environ.get("SPAWN_CAPACITY_HOME", Path.home()))
    cutoff = time.time() - ACTIVE_SECONDS
    count = 0
    patterns = [
        (home / ".claude" / "projects", "*/*/subagents/*.jsonl"),
        (home / ".codex" / "sessions", time.strftime("%Y/%m/%d") + "/*.jsonl"),
    ]
    for root, pattern in patterns:
        try:
            for path in root.glob(pattern):
                try:
                    if path.stat().st_mtime >= cutoff:
                        count += 1
                except OSError:
                    pass
        except OSError:
            pass
    return count


def state_root():
    return Path(
        os.environ.get(
            "CODEX_BEHAVIOR_STATE",
            Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "codex-behavior",
        )
    )


def log_override(event, fact):
    try:
        root = state_root()
        root.mkdir(parents=True, exist_ok=True)
        with open(root / "verify-overrides.jsonl", "a") as log:
            log.write(json.dumps({
                "at": time.time(), "session": event.get("session_id"), "agent": event.get("agent_id"),
                "gate": "spawn-capacity", "case": "URGENT", "cwd": event.get("cwd"), "fact": fact[:300],
            }) + "\n")
    except OSError:
        pass


def is_local(event):
    tool = str(event.get("tool_name") or "")
    tool_input = event.get("tool_input") or {}
    if tool.endswith("spawn_agent"):
        return True
    if tool != "Agent" or not isinstance(tool_input, dict):
        return False
    if tool_input.get("isolation") == "remote":
        return False
    return (tool_input.get("subagent_type") or "general-purpose") in LOCAL_CLAUDE_TYPES


def brief_texts(tool_input):
    """Every string in the spawn input; Codex may send it as serialized JSON."""
    if isinstance(tool_input, str):
        try:
            parsed = json.loads(tool_input)
        except ValueError:
            return [tool_input]
        return [tool_input] if isinstance(parsed, str) else brief_texts(parsed)
    if isinstance(tool_input, dict):
        return [t for value in tool_input.values() for t in brief_texts(value)]
    if isinstance(tool_input, list):
        return [t for value in tool_input for t in brief_texts(value)]
    return []


def log_denial(event):
    try:
        path = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "agents/spawn-gate-denials.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        texts = brief_texts(event.get("tool_input") or {})
        with path.open("a") as f:
            f.write(json.dumps({"tool": event.get("tool_name"), "input_type": type(event.get("tool_input")).__name__,
                                "heads": [t[:160] for t in texts[:4]]}) + "\n")
    except OSError:
        pass


def urgent_file_fact(texts):
    """Codex encrypts spawn briefs, so its override names the agent in
    spawn-urgent.tsv (epoch<TAB>agent-name<TAB>fact), written within 15 minutes."""
    path = Path(os.environ.get("SPAWN_CAPACITY_HOME", Path.home())) / ".local/state/agents/spawn-urgent.tsv"
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return None
    names = {t.strip() for t in texts if len(t) <= 80}
    now = time.time()
    for line in reversed(lines):
        parts = line.split("\t", 2)
        if len(parts) == 3 and parts[0].isdigit() and now - int(parts[0]) <= 900 \
                and parts[1] in names and len(parts[2].strip()) >= 15:
            return parts[2].strip()
    return None


def subagent_brief(event):
    """The first prompt of the subagent making this call, or None."""
    transcript, agent = event.get("transcript_path"), event.get("agent_id")
    if not (isinstance(transcript, str) and isinstance(agent, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,128}", agent)):
        return None
    path = Path(transcript).with_suffix("") / "subagents" / f"agent-{agent}.jsonl"
    try:
        with path.open(encoding="utf-8") as f:
            for raw in f:
                entry = json.loads(raw)
                if entry.get("type") == "user":
                    content = (entry.get("message") or {}).get("content")
                    if isinstance(content, list):
                        content = "\n".join(c.get("text", "") for c in content if isinstance(c, dict))
                    return content if isinstance(content, str) else None
    except (OSError, ValueError):
        return None
    return None


def delegation_budget(event):
    """(budget, where it came from) for the agent making this spawn."""
    if event.get("agent_id"):
        match = DELEGATION.search(subagent_brief(event) or "")
        if match:
            return int(match.group(1)), "the Delegation line of your brief"
        return 0, "your brief, which has no Delegation line, so you are a worker"
    raw = os.environ.get("AGENT_DELEGATION_BUDGET", "")
    if raw.isdigit():
        return int(raw), "AGENT_DELEGATION_BUDGET"
    role = os.environ.get("AGENT_ROLE") or "proxy"
    return ROLE_BUDGETS.get(role, 0), f"the default for role {role}"


def org_domain_rank():
    """(domain, rank in the priority order, first domain) for this session's org node, or None."""
    name = os.environ.get("AGENT_ORG_NAME")
    if not name:
        return None
    path = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "agents/org.json"
    try:
        org = json.loads(Path(os.environ.get("AGENTS_ORG_FILE", path)).read_text())
        domain = next(n["domain"] for n in org["nodes"] if n["id"] == name).lower()
        config = os.environ.get("AGENTS_ORCHESTRATION") or Path(__file__).resolve().parents[2] / "orchestration.toml"
        with open(config, "rb") as f:
            projects = tomllib.load(f).get("projects", {})
        order = [d.lower() for d in sorted(projects, key=lambda d: projects[d].get("priority", float("inf")))]
    except (OSError, ValueError, KeyError, TypeError, StopIteration, AttributeError):
        return None
    if domain not in order:
        return None
    return domain, order.index(domain), order[0]


def money_gate(event):
    """The refusal `agents usage` recorded for this provider when a new worker could bill money (firn#12): a fresh
    usage-gate.json verdict answers at once, a stale or missing one runs `agents usage --gate`; no command allows."""
    import shutil
    import subprocess
    provider = "claude" if event.get("tool_name") == "Agent" else "codex"
    home = os.environ.get("SPAWN_CAPACITY_HOME")
    state = Path(home) / ".local/state" if home else Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    try:
        verdict = json.loads((state / "agents/usage-gate.json").read_text())[provider]
        if time.time() - verdict["epoch"] < verdict["stale_min"] * 60:
            return verdict["refusal"]
    except (OSError, ValueError, KeyError, TypeError):
        pass
    agents = shutil.which("agents") or os.path.expanduser("~/.local/bin/agents")
    try:
        result = subprocess.run([agents, "usage", "--gate", provider], capture_output=True, text=True, timeout=45)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 3 and result.stdout.strip() else None


def check(event):
    """The refusal text for this spawn, or None to allow it."""
    texts = brief_texts(event.get("tool_input") or {})
    if any(EXEMPT_MARKER in t for t in texts):
        return None
    money = money_gate(event)
    if money:
        return money
    if event.get("tool_name") == "Agent":
        budget, source = delegation_budget(event)
        if budget <= 0:
            return (
                f"Your delegation budget is 0 ({source}). Do this work directly yourself: don't spawn, "
                "fork or delegate it. If it is more than you can finish, land what passes and report the rest "
                "to whoever briefed you."
            )
    if not is_local(event):
        return None
    reading = capacity()
    if reading is None:
        return None
    provisioned, limit, protected = reading
    rank = org_domain_rank()
    ceiling = limit * (1 - PRIORITY_HEADROOM) if rank and rank[1] > 0 else limit
    if provisioned < ceiling and protected <= PROTECTED_PRESSURE_LIMIT:
        return None
    fact = urgent_file_fact(texts)
    if fact:
        log_override(event, fact)
        return None
    urgent = next((m for m in map(URGENT.search, texts) if m), None)
    if urgent:
        fact = urgent.group(1) if urgent.group(1) is not None else urgent.group(2)
        if len(fact.strip()) >= 15:
            log_override(event, fact.strip())
            return None
    log_denial(event)
    if provisioned < limit and protected <= PROTECTED_PRESSURE_LIMIT:
        return (
            f"Domain {rank[0]} ranks below {rank[2]} in Tom's priority order (agents org show), so its local "
            f"spawns stop at {ceiling:g} of the {limit:g} CPUs; {provisioned:g} are committed. Move code-only work "
            "to a cloud worker (cloud-workers skill) or queue it until a lease ends. Take a real conflict to the "
            "proxy, not Tom."
        )
    return (
        f"Capacity leases and unleased heavy load commit {provisioned:g} of the {limit:g} CPUs the machine can hand out, "
        f"protected desktop pressure is {protected:g}% (limit {PROTECTED_PRESSURE_LIMIT:g}%), and "
        f"{local_workers()} local workers are running. Queue this worker until a lease ends, "
        "send heavy checks to the farm, or use a cloud worker for code-only work "
        "(cloud-workers skill). Workers already running are unaffected. For an urgent fix, "
        "start the brief with CASE=URGENT FACT=\"<why it can't wait>\". Codex, whose briefs are encrypted, appends \"<epoch>\\t<agent name>\\t<fact>\" to ~/.local/state/agents/spawn-urgent.tsv first."
    )


def main():
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return 65
    reason = check(event) if isinstance(event, dict) else None
    if reason:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
