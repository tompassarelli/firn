"""north-bridge — Nix-owned Hermes controller adapter for North/Orchestration.

Hermes is a *controller host* over the North MCP, not a new North provider.
This plugin is the standalone bridge that makes Hermes' own tool surface obey
the same provider-neutral authoring guards Claude Code and Codex already run,
and routes session/tool lifecycle through the SAME North hook scripts every
other provider uses — never a Hermes-specific fork.

Guard chains (provider-neutral ~/.agents/hooks, run in order; ANY deny denies):

    write_file / patch  -> no repository-specific guard
    terminal / process  -> tripwire-guard.sh
    delegate_task       -> DENY unconditionally (native delegation is disabled;
                           the `delegation` toolset is off and delegation is a
                           North lifecycle op). A blocked NATIVE delegate_task is
                           NEVER marked delegated — only a real North MCP spawn/
                           dispatch is (see post_tool_call below).

Every guard is a real subprocess fed the Claude/Codex-shaped hook JSON on
stdin. A guard may signal a denial two ways, BOTH honoured:

  * a non-zero exit code (tripwire's deny path), or
  * exit 0 with ``{"hookSpecificOutput":{"permissionDecision":"deny"}}`` on
    stdout (firn deny path).

Fail-closed contract — enforcement can never be skipped by breaking plumbing:
a missing/non-executable script, a spawn error, a timeout, a malformed JSON
response, an unexpected exception, or ANY non-zero exit DENIES the tool. A
startup self-check (``selfcheck``) proves every chain member + the shared
killswitch lib resolve; if it fails ``_ENFORCEMENT_STATE`` latches degraded and
authoring/terminal deny outright.

Hermes is a CONTROLLER HOST over the North MCP, not a North provider — so the
lifecycle scripts run with the provider env UNSET (never ``AGENT_PROVIDER=hermes``),
letting North record the provider ``unobserved`` honestly. The exact WRAPPED North
hook scripts (``inputs.north.packages.<system>.default/bin``, via
``NORTH_HERMES_LIFECYCLE_DIR``) are driven — never a fork, never a fabricated
``north hermes-lifecycle`` command:

    on_session_start -> north-on-spawn
    post_tool_call   -> north-on-tooluse   (+ north-mark-delegated ONLY when a
                        real mcp__north__spawn / mcp__north__dispatch succeeds)
    pre_verify       -> north-on-stop      (its {"decision":"block","reason":…}
                        keep-going block is mapped to a pre_verify continue)
    on_session_end   -> north-on-stop      (session-lifecycle side effects)

The bounded ``additionalContext`` north-on-tooluse (and north-on-spawn) surface
is preserved: captured keyed by ``tool_call_id`` and injected into the model turn
through Hermes' ``transform_tool_result`` (same tool_call_id) and, for anything
still pending, ``pre_llm_call``.

The policy core (``evaluate_tool``) and lifecycle translator are pure over
injected runners, so the whole contract is exercised by the sibling tests
without a running Hermes.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
from collections import OrderedDict
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Tool classification + provider-neutral guard chains
# ---------------------------------------------------------------------------

AUTHORING_TOOLS = frozenset({"write_file", "patch"})
TERMINAL_TOOLS = frozenset({"terminal", "process"})
# Native subagent spawner — always refused (delegation flows through North).
DELEGATION_TOOLS = frozenset({"delegate_task"})
# The ONLY tools whose SUCCESS marks this session as having delegated work:
# a real North MCP spawn/dispatch. A blocked native delegate_task never counts.
DELEGATION_MARK_TOOLS = frozenset({"mcp__north__spawn", "mcp__north__dispatch"})

# Ordered guard chains. Terminal commands run the provider-neutral tripwire.
AUTHORING_CHAIN = ()
TERMINAL_CHAIN = ("tripwire-guard.sh",)

# Everything the enforcement surface stands on. Absence of ANY means the guard
# plumbing is not wired and authoring/terminal must fail closed.
REQUIRED_GUARDS = (
    "tripwire-guard.sh",
)
# Every guard sources the shared killswitch.
REQUIRED_GUARD_SUPPORT = ("lib/authoring-killswitch.sh",)

# North lifecycle hook scripts — the SAME scripts Claude/Codex drive, run with
# the provider env UNSET (Hermes is a controller host, not a North provider).
# Never a fabricated `north hermes-lifecycle`.
LIFECYCLE_SCRIPTS = {
    "session_start": "north-on-spawn",
    "tool_use": "north-on-tooluse",
    "session_end": "north-on-stop",
    "delegated": "north-mark-delegated",
}

# ---------------------------------------------------------------------------
# Configuration (env-overridable; defaults match the firn materialisation)
# ---------------------------------------------------------------------------


def _guard_dir() -> Path:
    override = os.environ.get("NORTH_HERMES_GUARD_DIR")
    if override:
        return Path(override).expanduser()
    return Path(os.environ.get("HOME", "~")).expanduser() / ".agents" / "hooks"


def _lifecycle_dir() -> Optional[Path]:
    """Directory holding north-on-spawn/tooluse/stop and north-mark-delegated.

    The firn Hermes module points ``NORTH_HERMES_LIFECYCLE_DIR`` at the pinned
    North PACKAGE's ``bin`` (``inputs.north.packages.<system>.default/bin``) —
    the real WRAPPED lifecycle scripts, never the raw source checkout. Absent,
    lifecycle is a best-effort no-op — a broken North must never break a Hermes
    session.
    """
    override = os.environ.get("NORTH_HERMES_LIFECYCLE_DIR")
    if override:
        return Path(override).expanduser()
    home = os.environ.get("NORTH_HOME")
    if home:
        return Path(home).expanduser() / "bin"
    return None


def _north_bin() -> str:
    return os.environ.get("NORTH_BIN", "north")


def _bash_bin() -> str:
    return os.environ.get("NORTH_HERMES_BASH", "bash")


def _switchboard_active(kind: str, name: str) -> bool:
    """Read one derived switchboard activity row.

    A missing projection preserves installations that do not use the personal
    switchboard. Once present, an absent or inactive row is off.
    """
    configured = os.environ.get("AGENTS_ACTIVITY_FILE")
    home = Path(os.environ.get("HOME", "~")).expanduser()
    path = (
        Path(configured).expanduser()
        if configured
        else home / ".config" / "agents" / "activity.conf"
    )
    try:
        rows = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return True
    except OSError:
        return False
    for row in rows:
        fields = row.split()
        if len(fields) >= 3 and fields[0] == kind and fields[1] == name:
            return fields[2] == "on"
    return False


def _guard_timeout() -> float:
    try:
        return float(os.environ.get("NORTH_HERMES_GUARD_TIMEOUT", "15"))
    except (TypeError, ValueError):
        return 15.0


# ---------------------------------------------------------------------------
# Startup / anti-rot self-check
# ---------------------------------------------------------------------------


def selfcheck(
    guard_dir: Optional[Path] = None,
    north_bin: Optional[str] = None,
) -> Tuple[bool, List[str]]:
    """Prove the enforcement surface resolves.

    ``ok`` is True only when every chain member + support file exists and is
    readable and ``north`` is resolvable. Callers treat ``ok is False`` as
    "enforcement degraded" and deny authoring/terminal.
    """
    gdir = guard_dir if guard_dir is not None else _guard_dir()
    nbin = north_bin if north_bin is not None else _north_bin()
    problems: List[str] = []

    for name in REQUIRED_GUARDS + REQUIRED_GUARD_SUPPORT:
        path = gdir / name
        if not path.exists():
            problems.append(f"missing shared guard: {path}")
            continue
        if not os.access(path, os.R_OK):
            problems.append(f"shared guard not readable: {path}")

    if shutil.which(nbin) is None and not os.path.isabs(nbin):
        problems.append(f"north binary not on PATH: {nbin}")
    elif os.path.isabs(nbin) and not os.access(nbin, os.X_OK):
        problems.append(f"north binary not executable: {nbin}")

    return (not problems, problems)


class _EnforcementState:
    """Module-global latch: enforcement is degraded (fail-closed) until proven."""

    def __init__(self) -> None:
        self.ok = False
        self.problems: List[str] = ["self-check has not run yet"]

    def refresh(self) -> bool:
        self.ok, self.problems = selfcheck()
        if not self.ok:
            logger.error(
                "north-bridge enforcement DEGRADED — authoring/terminal will "
                "fail closed: %s",
                "; ".join(self.problems),
            )
        return self.ok


_ENFORCEMENT_STATE = _EnforcementState()


# ---------------------------------------------------------------------------
# Guard invocation
# ---------------------------------------------------------------------------

# A guard runner returns (exit_status, stdout, available). ``available`` is
# False when the guard could not be executed at all (missing/spawn/timeout);
# ``exit_status``/``stdout`` are meaningful only when ``available`` is True.
GuardRunner = Callable[[str, Dict[str, Any]], Tuple[int, str, bool]]


def _real_guard_runner(script: str, payload: Dict[str, Any]) -> Tuple[int, str, bool]:
    """Execute a shared guard with the provider-neutral hook JSON on stdin."""
    path = _guard_dir() / script
    if not path.exists() or not os.access(path, os.R_OK):
        return (0, "", False)
    try:
        proc = subprocess.run(
            [_bash_bin(), str(path)],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            timeout=_guard_timeout(),
        )
        return (proc.returncode, proc.stdout or "", True)
    except Exception as exc:  # noqa: BLE001 — spawn/timeout/OS error == unavailable
        logger.warning("north-bridge guard %s could not run: %s", script, exc)
        return (0, "", False)


def _stdout_denies(stdout: str) -> Optional[bool]:
    """Interpret a guard's stdout.

    Returns True (deny), False (allow), or None (malformed → caller fails
    closed). An allowing guard emits empty stdout; a denying guard emits a
    ``hookSpecificOutput.permissionDecision == "deny"`` envelope even on exit 0.
    """
    text = (stdout or "").strip()
    if not text:
        return False
    try:
        data = json.loads(text)
    except (ValueError, TypeError):
        return None  # non-empty, non-JSON → malformed → fail closed
    if not isinstance(data, dict):
        return None
    hso = data.get("hookSpecificOutput")
    if isinstance(hso, dict):
        decision = hso.get("permissionDecision")
        if isinstance(decision, str) and decision.strip().lower() == "deny":
            return True
    # Some guards echo the Claude Stop shape at the top level.
    if str(data.get("permissionDecision", "")).strip().lower() == "deny":
        return True
    return False


def _guard_member_denies(status: int, stdout: str, available: bool) -> bool:
    """One guard's verdict. Fail-closed on anything but a clean allow."""
    if not available:
        return True  # missing / spawn / timeout
    parsed = _stdout_denies(stdout)
    if parsed is None:
        return True  # malformed response
    if parsed:
        return True  # explicit permissionDecision deny on stdout
    return status != 0  # any non-zero exit denies (deny code or guard error)


def _authoring_payload(tool_name: str, args: Dict[str, Any]) -> Dict[str, Any]:
    """Build the Claude/Codex-shaped Edit/Write hook payload the guards read."""
    args = args or {}
    file_path = args.get("path") or args.get("file_path") or args.get("filePath") or ""
    content = (
        args.get("content")
        or args.get("new_string")
        or args.get("patch")
        or args.get("file_content")
        or ""
    )
    return {
        "tool_name": "Write" if tool_name == "write_file" else "Edit",
        "tool_input": {"file_path": file_path, "content": content},
        "cwd": os.environ.get("PWD", os.getcwd()),
        "session_id": os.environ.get("HERMES_SESSION_ID", "hermes"),
        "_hermes_tool": tool_name,
    }


def _terminal_payload(tool_name: str, args: Dict[str, Any]) -> Dict[str, Any]:
    """Build the Bash hook payload tripwire-guard reads."""
    args = args or {}
    command = args.get("command") or args.get("cmd") or ""
    return {
        "tool_name": "Bash",
        "tool_input": {"command": command},
        "cwd": os.environ.get("PWD", os.getcwd()),
        "session_id": os.environ.get("HERMES_SESSION_ID", "hermes"),
        "_hermes_tool": tool_name,
    }


def _deny(message: str) -> Dict[str, str]:
    return {"action": "block", "message": message}


# ---------------------------------------------------------------------------
# Policy core — PURE over the injected runner + enforcement flag
# ---------------------------------------------------------------------------


def evaluate_tool(
    tool_name: str,
    args: Optional[Dict[str, Any]],
    guard_runner: GuardRunner,
    enforcement_ok: bool,
) -> Optional[Dict[str, str]]:
    """Decide allow (None) / deny (block dict) for one tool call.

    Pure: all side-effecting enforcement is behind ``guard_runner`` and the
    startup proof is passed in as ``enforcement_ok``. Runs the FULL guard chain
    for the tool class; the first member to deny (non-zero, stdout deny, or
    unavailable/malformed/raise) denies the tool.
    """
    args = args or {}

    if tool_name in DELEGATION_TOOLS:
        return _deny(
            "north-bridge: native delegate_task is disabled. Delegation is a "
            "North lifecycle operation — dispatch through the North MCP "
            "(north dispatch / capture), not Hermes' own subagent spawner."
        )

    is_authoring = tool_name in AUTHORING_TOOLS
    is_terminal = tool_name in TERMINAL_TOOLS
    if not (is_authoring or is_terminal):
        return None  # not a guarded surface

    if not enforcement_ok:
        return _deny(
            f"north-bridge: enforcement is DEGRADED, refusing {tool_name}. The "
            "shared authoring guards did not resolve at startup; restore "
            "~/.agents/hooks (firn build) before authoring."
        )

    chain = AUTHORING_CHAIN if is_authoring else TERMINAL_CHAIN
    payload = (
        _authoring_payload(tool_name, args)
        if is_authoring
        else _terminal_payload(tool_name, args)
    )

    for script in chain:
        try:
            status, stdout, available = guard_runner(script, payload)
        except Exception as exc:  # noqa: BLE001 — an errored guard is a denied tool
            logger.warning("north-bridge: %s raised for %s: %s", script, tool_name, exc)
            return _deny(
                f"north-bridge: the {script} guard raised while checking "
                f"{tool_name}; denying (fail closed)."
            )
        if _guard_member_denies(status, stdout, available):
            return _deny(
                f"north-bridge: {script} denied {tool_name} (fail-closed guard "
                f"chain: exit={status}, available={available})."
            )

    return None  # every chain member allowed


# ---------------------------------------------------------------------------
# North lifecycle translation — the exact WRAPPED scripts, provider UNSET
# ---------------------------------------------------------------------------

# A lifecycle runner takes the resolved script NAME, the stdin payload, and the
# env overlay, and best-effort runs it. Returns (ran_clean, stdout): stdout is
# captured so callers can read north-on-tooluse/north-on-spawn additionalContext
# and north-on-stop's decision block. Injected for testability so the tests
# assert exact script + env (proving AGENT_PROVIDER is never set) without a real
# North.
LifecycleRunner = Callable[[str, Dict[str, Any], Dict[str, str]], Tuple[bool, str]]


def _lifecycle_env() -> Dict[str, str]:
    """Env overlay for a lifecycle emit.

    Hermes is a controller HOST, not a North provider — so we deliberately do
    NOT set ``AGENT_PROVIDER``. North then records the provider ``unobserved``
    honestly instead of a fabricated ``hermes`` provider.
    """
    return {}


def _real_lifecycle_runner(
    script: str, payload: Dict[str, Any], env: Dict[str, str]
) -> Tuple[bool, str]:
    """Best-effort North lifecycle run. Never raises; never blocks a session."""
    ldir = _lifecycle_dir()
    if ldir is None:
        logger.debug("north-bridge: no lifecycle dir, dropping %s", script)
        return (False, "")
    target = ldir / script
    if not target.exists():
        logger.debug("north-bridge: lifecycle script absent: %s", target)
        return (False, "")
    run_env = dict(os.environ)
    # Never claim a provider: strip any inherited AGENT_PROVIDER, then apply the
    # (deliberately provider-free) overlay.
    run_env.pop("AGENT_PROVIDER", None)
    run_env.update(env)
    run_env["NORTH_HOME"] = str(ldir.parent)
    try:
        proc = subprocess.run(
            [_bash_bin(), str(target)],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            timeout=_guard_timeout(),
            env=run_env,
            check=False,
        )
        return (proc.returncode == 0, proc.stdout or "")
    except Exception as exc:  # noqa: BLE001 — lifecycle is best-effort
        logger.debug("north-bridge: lifecycle run failed (%s): %s", script, exc)
        return (False, "")


def run_lifecycle(
    event: str,
    payload: Optional[Dict[str, Any]] = None,
    runner: Optional[LifecycleRunner] = None,
) -> Tuple[bool, str]:
    """Run the exact North hook script for a lifecycle event; capture stdout.

    ``event`` is one of ``LIFECYCLE_SCRIPTS``' keys. Applies the provider-free
    env overlay (never ``AGENT_PROVIDER=hermes``). Pure over ``runner``; never
    raises. Tolerates a legacy bool-only runner return.
    """
    script = LIFECYCLE_SCRIPTS.get(event)
    if script is None:
        return (False, "")
    if runner is None and not _switchboard_active("hook", "north-session-lifecycle"):
        return (True, "")
    run = runner if runner is not None else _real_lifecycle_runner
    try:
        result = run(script, dict(payload or {}), _lifecycle_env())
    except Exception as exc:  # noqa: BLE001 — lifecycle must not break a session
        logger.debug("north-bridge: lifecycle %s dropped: %s", event, exc)
        return (False, "")
    if isinstance(result, tuple) and len(result) == 2:
        ok, out = result
        return (bool(ok), out if isinstance(out, str) else "")
    return (bool(result), "")


def emit_lifecycle(
    event: str,
    payload: Optional[Dict[str, Any]] = None,
    runner: Optional[LifecycleRunner] = None,
) -> bool:
    """Fire-and-forget lifecycle emit; returns whether the script ran clean."""
    ok, _ = run_lifecycle(event, payload, runner)
    return ok


# ---------------------------------------------------------------------------
# Bounded additionalContext preservation
# ---------------------------------------------------------------------------

# north-on-tooluse / north-on-spawn surface bounded peer-mail + coordination
# guidance via hookSpecificOutput.additionalContext. Hermes has no native slot
# for it, so we stash it keyed by tool_call_id and re-inject it into the model
# turn (transform_tool_result for the same call; pre_llm_call for the rest).
_MAX_CONTEXT_CHARS = 8192
_MAX_PENDING_ENTRIES = 64
_pending_context: "OrderedDict[str, str]" = OrderedDict()


def _remember_context(key: str, context: str) -> None:
    text = (context or "").strip()
    if not text:
        return
    _pending_context[key] = text[:_MAX_CONTEXT_CHARS]
    while len(_pending_context) > _MAX_PENDING_ENTRIES:
        _pending_context.popitem(last=False)  # drop oldest


def _take_context(key: str) -> Optional[str]:
    return _pending_context.pop(key, None)


def _drain_context() -> Optional[str]:
    if not _pending_context:
        return None
    parts: List[str] = []
    while _pending_context:
        _, value = _pending_context.popitem(last=False)
        parts.append(value)
    return "\n\n".join(parts)


def _parse_additional_context(stdout: str) -> Optional[str]:
    """Extract hookSpecificOutput.additionalContext from a hook's stdout."""
    text = (stdout or "").strip()
    if not text:
        return None
    try:
        data = json.loads(text)
    except (ValueError, TypeError):
        return None
    if not isinstance(data, dict):
        return None
    hso = data.get("hookSpecificOutput")
    if isinstance(hso, dict):
        ctx = hso.get("additionalContext")
        if isinstance(ctx, str) and ctx.strip():
            return ctx[:_MAX_CONTEXT_CHARS]
    return None


def _parse_stop_decision(stdout: str) -> Optional[Dict[str, str]]:
    """Extract north-on-stop's exact {"decision":"block","reason":…} block."""
    text = (stdout or "").strip()
    if not text:
        return None
    try:
        data = json.loads(text)
    except (ValueError, TypeError):
        return None
    if not isinstance(data, dict):
        return None
    if str(data.get("decision", "")).strip().lower() == "block":
        reason = data.get("reason")
        if isinstance(reason, str) and reason.strip():
            return {"decision": "block", "reason": reason}
    return None


def _tooluse_payload(tool_name: str, session_id: str, tool_call_id: str, result: Any) -> Dict[str, Any]:
    response: Any = result
    if not isinstance(response, (str, dict, list)):
        response = "" if response is None else str(response)
    return {
        "hook_event_name": "PostToolUse",
        "tool_name": tool_name,
        "tool_response": response,
        "session_id": session_id,
        "tool_call_id": tool_call_id,
        "cwd": os.environ.get("PWD", os.getcwd()),
    }


# ---------------------------------------------------------------------------
# Hermes hook adapters (thin wrappers binding the real runners)
# ---------------------------------------------------------------------------


def _session_id(kwargs: Dict[str, Any]) -> str:
    return str(kwargs.get("session_id") or os.environ.get("HERMES_SESSION_ID", "hermes"))


def _on_pre_tool_call(tool_name: str = "", args: Any = None, **kwargs: Any):
    # Pure guard/delegation decision only. A blocked native delegate_task is
    # NEVER marked delegated — that would falsely arm the Stop listener for work
    # that never spawned. Only a SUCCESSFUL North MCP spawn/dispatch marks
    # delegation (see _on_post_tool_call).
    if not isinstance(args, dict):
        args = {}
    return evaluate_tool(tool_name, args, _real_guard_runner, _ENFORCEMENT_STATE.ok)


def _on_post_tool_call(
    tool_name: str = "",
    args: Any = None,
    result: Any = None,
    status: Any = None,
    tool_call_id: Any = None,
    **kwargs: Any,
):
    sid = _session_id(kwargs)
    tcid = str(tool_call_id or "")

    # 1. north-on-tooluse mail heartbeat — capture its bounded additionalContext
    #    keyed by tool_call_id for re-injection into the model turn.
    ok, stdout = run_lifecycle("tool_use", _tooluse_payload(tool_name, sid, tcid, result))
    if ok:
        ctx = _parse_additional_context(stdout)
        if ctx:
            _remember_context(tcid, ctx)

    # 2. Mark delegation ONLY when a real North MCP spawn/dispatch SUCCEEDED.
    if str(status) == "ok" and tool_name in DELEGATION_MARK_TOOLS:
        emit_lifecycle(
            "delegated",
            {"session_id": sid, "tool_name": tool_name, "tool_call_id": tcid, "cwd": os.environ.get("PWD", os.getcwd())},
        )
    return None


def _on_transform_tool_result(
    tool_name: str = "",
    result: Any = None,
    tool_call_id: Any = None,
    **kwargs: Any,
):
    # Inject the north-on-tooluse additionalContext captured for THIS tool call.
    ctx = _take_context(str(tool_call_id or ""))
    if not ctx:
        return None
    base = result if isinstance(result, str) else ("" if result is None else str(result))
    return f"{base}\n\n[north] {ctx}"


def _on_pre_llm_call(**kwargs: Any):
    # Poll for any additionalContext not consumed by a transform (e.g. session-
    # start guidance, or tool calls whose transform never ran). Injected into the
    # user message, never the system prompt (preserves the prompt cache prefix).
    ctx = _drain_context()
    if not ctx:
        return None
    return {"context": ctx}


def _on_pre_verify(session_id: str = "", **kwargs: Any):
    # Map north-on-stop's exact keep-going decision onto Hermes' verify gate: a
    # {"decision":"block","reason":…} block == "don't stop yet". pre_verify
    # accepts that Claude Stop shape directly.
    sid = str(session_id or os.environ.get("HERMES_SESSION_ID", "hermes"))
    ok, stdout = run_lifecycle("session_end", {"session_id": sid, "hook_event_name": "Stop"})
    if not ok:
        return None
    return _parse_stop_decision(stdout)


def _on_session_start(**kwargs: Any):
    _ENFORCEMENT_STATE.refresh()
    sid = _session_id(kwargs)
    ok, stdout = run_lifecycle(
        "session_start", {"session_id": sid, "hook_event_name": "SessionStart"}
    )
    if ok:
        ctx = _parse_additional_context(stdout)
        if ctx:
            _remember_context(f"session_start:{sid}", ctx)
    return None


def _on_session_end(**kwargs: Any):
    # Invoke the real session lifecycle (north-on-stop) for its bookkeeping side
    # effects — decision ignored here (the keep-going decision is honored at the
    # pre_verify seam). Never fabricates a command.
    emit_lifecycle("session_end", {"session_id": _session_id(kwargs), "hook_event_name": "Stop"})
    return None


def register(ctx) -> None:
    # Prove enforcement at load. Degraded state fails authoring/terminal closed.
    _ENFORCEMENT_STATE.refresh()
    ctx.register_hook("pre_tool_call", _on_pre_tool_call)
    ctx.register_hook("post_tool_call", _on_post_tool_call)
    ctx.register_hook("transform_tool_result", _on_transform_tool_result)
    ctx.register_hook("pre_llm_call", _on_pre_llm_call)
    ctx.register_hook("pre_verify", _on_pre_verify)
    ctx.register_hook("on_session_start", _on_session_start)
    ctx.register_hook("on_session_end", _on_session_end)
