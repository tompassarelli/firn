"""Coordinated OS/app-server activation; run outside the shared service cgroup.

Usage: shared-activate.py --preflight|--provider-preflight|--activate /absolute/path/activation.json
The configuration and fsynced receipt stay in the operator's private handoff
directory. `interrupt` contains only checkpointed {id, turn_id} pairs that the
coordinator authorized this helper to finish before stopping the service.
"""
import asyncio
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from websockets.asyncio.client import unix_connect

ROOT = None
CONFIG = {}


def error_detail(exc):
    return f"{type(exc).__name__}: {str(exc).strip() or repr(exc)}"


def record(stage, **details):
    with (ROOT / "activation-receipt.jsonl").open("a") as out:
        out.write(json.dumps({"time": time.time(), "stage": stage, **details}) + "\n")
        out.flush()
        os.fsync(out.fileno())


def command(*args, **kwargs):
    try:
        return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout.strip()
    except subprocess.CalledProcessError as exc:
        record("command-failed", argv=list(args), returncode=exc.returncode,
               stdout=exc.stdout[-16384:], stderr=exc.stderr[-16384:])
        raise RuntimeError(f"{args[0]} exited {exc.returncode}: {exc.stderr.strip()}") from exc


def runtime_root(kind):
    """Return the selected install root for an exact runtime executable."""
    executable_key = "old_runtime" if kind == "old" else kind
    root = Path(CONFIG[f"{executable_key}_root"])
    assert root.is_absolute(), f"{kind} runtime root must be absolute"
    return root


def check_runtime_layout(kind):
    root = runtime_root(kind)
    executable_key = "old_runtime" if kind == "old" else kind
    executable = Path(CONFIG[executable_key]).resolve(strict=True)
    selected = (root / "bin" / "codex").resolve(strict=True)
    assert selected == executable, f"{kind} runtime root does not select its executable"


def check_candidate():
    candidate = Path(CONFIG["candidate"])
    assert candidate.is_absolute() and candidate.resolve(strict=True) == candidate, "candidate must be an exact executable path"
    with candidate.open("rb") as binary:
        digest = hashlib.file_digest(binary, "sha256").hexdigest()
    assert digest == CONFIG["candidate_sha256"], "candidate identity changed"
    assert candidate.is_file() and os.access(candidate, os.X_OK)
    check_runtime_layout("candidate")


def provider_preflight():
    check_candidate()
    canary = Path(__file__).resolve().with_name("provider-canary.py")
    result = subprocess.run([sys.executable, str(canary), "--candidate", CONFIG["candidate"],
                             "--sha256", CONFIG["candidate_sha256"]],
                            text=True, capture_output=True, check=False)
    record("provider-canary-result", returncode=result.returncode,
           stdout=result.stdout[-16384:], stderr=result.stderr[-16384:])
    try:
        receipt = json.loads(result.stdout)
    except (ValueError, TypeError) as exc:
        raise RuntimeError(f"provider canary exited {result.returncode} without a valid receipt; "
                           f"stderr: {result.stderr.strip() or '(empty)'}") from exc
    if result.returncode != 0 or receipt.get("success") is not True:
        raise RuntimeError(f"provider canary failed (exit {result.returncode}): "
                           f"{receipt.get('error') or 'successful provider completion was not established'}")
    assert receipt.get("candidate") == CONFIG["candidate"], "provider canary checked a different candidate"
    assert receipt.get("actual_sha256") == CONFIG["candidate_sha256"], "provider canary checked a different binary"
    check_candidate()
    record("provider-canary-passed", candidate=CONFIG["candidate"],
           candidate_sha256=CONFIG["candidate_sha256"], evidence_directory=receipt.get("state_directory"))


def preflight():
    check_candidate()
    check_runtime_layout("old")
    checkpoint = Path(CONFIG["peer_checkpoint"]).read_bytes()
    assert hashlib.sha256(checkpoint).hexdigest() == CONFIG["peer_checkpoint_sha256"], "peer checkpoint changed"
    assert Path(CONFIG["selector"]).resolve() == Path(CONFIG["previous_selector_root"]), "runtime selector changed"
    pid = int(command("systemctl", "--user", "show", CONFIG["unit"], "--property=MainPID", "--value"))
    assert str(Path(f"/proc/{pid}/exe").resolve()) == CONFIG["old_runtime"], "shared runtime changed"
    own_group = Path("/proc/self/cgroup").read_text().strip()
    shared_group = Path(f"/proc/{pid}/cgroup").read_text().strip()
    assert own_group != shared_group, "activation still lives inside shared server"
    record("preflight-passed", activation_pid=os.getpid(), cgroup=own_group, old_pid=pid)


async def quiesce_threads(interrupt=None):
    if interrupt is None:
        interrupt = CONFIG.get("interrupt", [])
    async with unix_connect(CONFIG["socket"], uri="ws://localhost/", compression=None,
                            user_agent_header=None, proxy=None, max_size=8 * 1024 * 1024) as ws:
        sequence = 0

        async def rpc(method, params):
            nonlocal sequence
            sequence += 1
            await ws.send(json.dumps({"id": sequence, "method": method, "params": params}))
            while True:
                response = json.loads(await asyncio.wait_for(ws.recv(), timeout=30))
                if response.get("id") == sequence:
                    if "error" in response:
                        raise RuntimeError({"method": method, "error": response["error"]})
                    return response["result"]

        await rpc("initialize", {"clientInfo": {"name": "shared_server_activation", "version": "1"},
                                 "capabilities": {"experimentalApi": True}})
        await ws.send(json.dumps({"method": "initialized", "params": {}}))
        deadline = asyncio.get_running_loop().time() + 30
        interrupted = False
        while True:
            active = {}
            cursor = None
            while True:
                page = await rpc("thread/loaded/list", {"cursor": cursor, "limit": 100})
                for thread_id in page["data"]:
                    result = await rpc("thread/read", {"threadId": thread_id, "includeTurns": False})
                    if result["thread"]["status"]["type"] == "active":
                        active[thread_id] = []
                cursor = page["nextCursor"]
                if cursor is None:
                    break
            if not active:
                record("assistant-turns-idle")
                return
            authorized = {thread["id"]: thread["turn_id"] for thread in interrupt}
            assert set(active) <= authorized.keys(), f"uncheckpointed active assistant turns: {active}"
            for thread_id in active:
                result = await rpc("thread/turns/list", {"threadId": thread_id, "limit": 1,
                                   "sortDirection": "desc", "itemsView": "summary"})
                active[thread_id] = [turn["id"] for turn in result["data"] if turn["status"] == "inProgress"]
            assert all(turns == [authorized[thread_id]] for thread_id, turns in active.items()), \
                f"checkpointed turn changed: {active}"
            if not interrupted:
                for thread in interrupt:
                    if thread["id"] in active:
                        await rpc("turn/interrupt", {"threadId": thread["id"], "turnId": thread["turn_id"]})
                        record("checkpointed-turn-interrupted", thread_id=thread["id"], turn_id=thread["turn_id"])
                interrupted = True
            assert asyncio.get_running_loop().time() < deadline, f"assistant turns still active: {active}"
            await asyncio.sleep(0.1)


async def resume_threads(started_turns=None):
    if started_turns is None:
        started_turns = []
    async with unix_connect(CONFIG["socket"], uri="ws://localhost/", compression=None,
                            user_agent_header=None, proxy=None, max_size=8 * 1024 * 1024) as ws:
        sequence = 0
        assistant_results = set()
        completed_turns = set()
        errors = {}
        started = set()
        requested = set()
        timeout = CONFIG.get("resume_timeout_seconds", 120)
        deadline = asyncio.get_running_loop().time() + timeout

        def remember(thread_id, turn_id):
            key = (thread_id, turn_id)
            if key not in started:
                started.add(key)
                started_turns.append({"id": thread_id, "turn_id": turn_id})

        def check_errors():
            for key in started & errors.keys():
                raise RuntimeError(f"resumed turn failed {key}: {errors[key]}")

        def is_assistant_result(item):
            return (item.get("type") == "agentMessage" and item.get("text", "").strip()
                    and item.get("phase") in (None, "final_answer"))

        def observe(message):
            params = message.get("params", {})
            method = message.get("method")
            key = (params.get("threadId"), params.get("turnId"))
            if (method == "turn/started" and params.get("threadId") in requested
                    and not any(thread_id == params["threadId"] for thread_id, _ in started)):
                remember(params["threadId"], params["turn"]["id"])
            elif method == "error":
                if key[0] in requested:
                    record("resumed-turn-error", thread_id=key[0], turn_id=key[1],
                           error=params.get("error"), will_retry=params.get("willRetry", False))
                if not params.get("willRetry", False):
                    errors[key] = params.get("error") or "unspecified turn error"
            elif method == "turn/completed":
                turn = params["turn"]
                key = (params.get("threadId"), turn["id"])
                if turn["status"] != "completed":
                    errors[key] = turn.get("error") or f"turn ended with status {turn['status']}"
                else:
                    completed_turns.add(key)
                    if any(is_assistant_result(item) for item in turn.get("items", [])):
                        assistant_results.add(key)
            elif method == "item/completed":
                item = params.get("item", {})
                if is_assistant_result(item):
                    assistant_results.add(key)

        async def receive(context):
            remaining = deadline - asyncio.get_running_loop().time()
            try:
                if remaining <= 0:
                    raise TimeoutError()
                message = json.loads(await asyncio.wait_for(ws.recv(), timeout=remaining))
            except TimeoutError as exc:
                raise TimeoutError(f"listener recovery exceeded {timeout}s while {context}; "
                                   f"awaiting successful assistant completion for "
                                   f"{sorted(started - (assistant_results & completed_turns))}") from exc
            observe(message)
            check_errors()
            return message

        async def rpc(method, params):
            nonlocal sequence
            sequence += 1
            await ws.send(json.dumps({"id": sequence, "method": method, "params": params}))
            while True:
                response = await receive(f"waiting for {method}")
                if response.get("id") == sequence:
                    if "error" in response:
                        raise RuntimeError({"method": method, "error": response["error"]})
                    return response["result"]

        await rpc("initialize", {"clientInfo": {"name": "communication_repair_activation", "version": "1"},
                                 "capabilities": {"experimentalApi": True}})
        await ws.send(json.dumps({"method": "initialized", "params": {}}))
        for thread in CONFIG["resume"]:
            try:
                result = await rpc("thread/resume", {"threadId": thread["id"], "excludeTurns": True})
                assert result["thread"]["id"] == thread["id"]
                requested.add(thread["id"])
                turn = await rpc("turn/start", {"threadId": thread["id"],
                    "input": [{"type": "text", "text": thread["message"]}]})
                remember(thread["id"], turn["turn"]["id"])
                check_errors()
                record("original-thread-start-accepted", thread_id=thread["id"], turn_id=turn["turn"]["id"])
            except Exception as exc:
                record("thread-reactivation-failed", thread_id=thread["id"], error=error_detail(exc))
                raise
        pending = set(started)
        while pending:
            check_errors()
            recovered = assistant_results & completed_turns
            for thread_id, turn_id in pending & recovered:
                record("original-thread-model-activity-observed", thread_id=thread_id,
                       turn_id=turn_id, autonomousReactivation=True, turn_status="completed")
            pending -= recovered
            if pending:
                await receive("waiting for successful assistant turn completion")


def activate(mode):
    if mode == "--provider-preflight":
        provider_preflight()
        return
    preflight()
    if mode == "--preflight":
        return
    assert mode == "--activate", "explicit mode required"
    assert not CONFIG.get("preflight_only", True), "activation configuration is not admitted"
    assert CONFIG["candidate"] != CONFIG["old_runtime"], "repair candidate is not configured"
    assert CONFIG["resume"], "original listeners must be resumed"
    provider_preflight()
    preflight()
    next_selector = Path(CONFIG["selector"] + ".communication-next")
    assert not next_selector.exists() and not next_selector.is_symlink()
    asyncio.run(quiesce_threads())
    next_selector.symlink_to(runtime_root("candidate"))
    env = dict(os.environ)
    env.update({"CODEX_RUNTIME": CONFIG["candidate"],
                "NORTH_CODEX_CONVERSATION_HOME": CONFIG["conversation_home"],
                "NORTH_CODEX_CONVERSATION_SQLITE_HOME": CONFIG["sqlite_home"]})
    started_turns = []
    try:
        record("restart-starting")
        command("systemctl", "--user", "stop", CONFIG["unit"])
        os.replace(next_selector, CONFIG["selector"])
        endpoint = command(CONFIG["launcher"], env=env)
        assert endpoint == "unix://" + CONFIG["socket"]
        pid = int(command("systemctl", "--user", "show", CONFIG["unit"], "--property=MainPID", "--value"))
        assert str(Path(f"/proc/{pid}/exe").resolve()) == CONFIG["candidate"], "unexpected restarted runtime"
        record("candidate-active", pid=pid, executable=CONFIG["candidate"])
        asyncio.run(resume_threads(started_turns))
    except Exception as exc:
        failure = error_detail(exc)
        record("candidate-activation-failed", error=failure)
        try:
            pid = int(command("systemctl", "--user", "show", CONFIG["unit"], "--property=MainPID", "--value"))
            if pid:
                active = str(Path(f"/proc/{pid}/exe").resolve())
                assert active in (CONFIG["candidate"], CONFIG["old_runtime"]), "unowned replacement server"
                if active == CONFIG["candidate"]:
                    # These exact turns are owned by this activation, including partial recovery.
                    asyncio.run(quiesce_threads(started_turns))
                    command("systemctl", "--user", "stop", CONFIG["unit"])
            if next_selector.is_symlink():
                next_selector.unlink()
            next_selector.symlink_to(Path(CONFIG["previous_selector_root"]))
            os.replace(next_selector, CONFIG["selector"])
            env["CODEX_RUNTIME"] = CONFIG["old_runtime"]
            endpoint = command(CONFIG["launcher"], env=env)
            assert endpoint == "unix://" + CONFIG["socket"]
            pid = int(command("systemctl", "--user", "show", CONFIG["unit"], "--property=MainPID", "--value"))
            assert str(Path(f"/proc/{pid}/exe").resolve()) == CONFIG["old_runtime"], "previous runtime not restored"
            record("previous-runtime-restored", incident_closed=False)
            asyncio.run(resume_threads())
        except Exception as rollback_exc:
            detail = error_detail(rollback_exc)
            record("activation-restoration-failed", candidate_error=failure, error=detail, incident_closed=False)
            raise RuntimeError(f"candidate failed ({failure}); restoration incomplete ({detail})") from rollback_exc
        record("activation-handoff-complete", outcome="previous-runtime-restored", incident_closed=False)
        raise RuntimeError(f"candidate activation failed ({failure}); previous runtime restored and listeners resumed") from exc
    record("activation-handoff-complete", outcome="candidate-active")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("--preflight", "--provider-preflight", "--activate"):
        raise SystemExit(__doc__)
    config_path = Path(sys.argv[2]).resolve(strict=True)
    ROOT = config_path.parent
    CONFIG = json.loads(config_path.read_text())
    try:
        activate(sys.argv[1])
    except Exception as exc:
        record("activation-failed", error=error_detail(exc))
        raise
