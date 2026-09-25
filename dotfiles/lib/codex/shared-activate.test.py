"""Isolated systemd regression: CODEX_TEST_RUNTIME must name an installed Codex binary.

Uses private empty conversation data, never the live user's shared unit. Provider
events are injected to prove lifecycle handling; they do not prove compatibility.
"""
import asyncio
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from unittest.mock import AsyncMock, patch

SOURCE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("activation", SOURCE / "shared-activate.py")
activation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(activation)
runtime = Path(os.environ["CODEX_TEST_RUNTIME"]).resolve(strict=True)
launcher = SOURCE.parent.parent / "bin/codex-shared-server"


def command(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout.strip()


def wait_inactive(unit):
    deadline = time.monotonic() + 10
    while command("systemctl", "--user", "show", unit, "-p", "ActiveState", "--value") not in ("inactive", "failed"):
        assert time.monotonic() < deadline, "isolated service did not stop"
        time.sleep(0.05)


class ActiveThreadApi:
    def __init__(self):
        self.active = True
        self.requests = []

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        pass

    async def send(self, message):
        self.request = json.loads(message)
        self.requests.append(self.request)

    async def recv(self):
        method = self.request["method"]
        result = {}
        if method == "thread/loaded/list":
            result = {"data": ["checkpointed"], "nextCursor": None}
        elif method == "thread/read":
            result = {"thread": {"status": {"type": "active" if self.active else "idle"}}}
        elif method == "thread/turns/list":
            result = {"data": [{"id": "current-turn", "status": "inProgress"}]}
        elif method == "turn/interrupt":
            assert self.request["params"] == {"threadId": "checkpointed", "turnId": "current-turn"}
            self.active = False
        return json.dumps({"id": self.request["id"], "result": result})


class ResumeApi:
    def __init__(self, outcome):
        self.outcome = outcome
        self.messages = asyncio.Queue()
        self.started = []
        self.commentary_seen = []
        self.completed_seen = []

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        pass

    async def send(self, message):
        request = json.loads(message)
        if "id" not in request:
            return
        result = {}
        if request["method"] == "thread/resume":
            result = {"thread": {"id": request["params"]["threadId"]}}
        elif request["method"] == "turn/start":
            thread_id = request["params"]["threadId"]
            self.started.append(thread_id)
            result = {"turn": {"id": "resumed-turn"}}
            params = {"threadId": thread_id, "turnId": "resumed-turn"}
            self.messages.put_nowait({"method": "turn/started", "params": {
                "threadId": thread_id, "turn": {"id": "resumed-turn"}}})
            self.messages.put_nowait({"method": "item/started", "params": {
                **params, "item": {"type": "reasoning"}}})
            if self.outcome == "provider400":
                self.messages.put_nowait({"method": "error", "params": {
                    **params, "willRetry": False,
                    "error": {"message": "HTTP 400: reserved collaboration.followup_task schema mismatch"}}})
            elif self.outcome == "failed-turn":
                self.messages.put_nowait({"method": "turn/completed", "params": {
                    "threadId": thread_id, "turn": {"id": "resumed-turn", "status": "failed",
                    "error": {"message": "injected terminal provider failure"}}}})
            elif self.outcome in ("late-provider400", "late-failed-turn", "commentary-completed"):
                self.messages.put_nowait({"method": "item/completed", "params": {
                    **params, "item": {"type": "agentMessage", "phase": "commentary",
                                       "text": "Continuing the task."}}})
                if self.outcome == "commentary-completed":
                    self.messages.put_nowait({"method": "turn/completed", "params": {
                        "threadId": thread_id, "turn": {"id": "resumed-turn", "status": "completed"}}})
            elif self.outcome in ("success", "message-only"):
                item = {"type": "agentMessage", "phase": "final_answer", "text": "Listener resumed."}
                if len(self.started) == 1 or self.outcome == "message-only":
                    self.messages.put_nowait({"method": "item/completed", "params": {**params, "item": item}})
                    items = []
                else:
                    items = [item]
                if self.outcome == "success":
                    self.messages.put_nowait({"method": "turn/completed", "params": {
                        "threadId": thread_id, "turn": {"id": "resumed-turn", "status": "completed", "items": items}}})
        self.messages.put_nowait({"id": request["id"], "result": result})
        if request["method"] == "turn/start":
            if self.outcome == "success" and len(self.started) == 1:
                self.messages.put_nowait({"method": "turn/started", "params": {
                    "threadId": thread_id, "turn": {"id": "subsequent-unowned-turn"}}})
                self.messages.put_nowait({"method": "error", "params": {
                    "threadId": thread_id, "turnId": "subsequent-unowned-turn", "willRetry": False,
                    "error": {"message": "unrelated later turn"}}})
            if self.outcome in ("late-provider400", "late-failed-turn") and len(self.started) == 2:
                self.messages.put_nowait({"method": "turn/completed", "params": {
                    "threadId": self.started[0], "turn": {"id": "resumed-turn", "status": "completed",
                        "items": [{"type": "agentMessage", "phase": "final_answer", "text": "Listener resumed."}]}}})
                if self.outcome == "late-provider400":
                    self.messages.put_nowait({"method": "error", "params": {
                        **params, "willRetry": False, "error": {"message": "HTTP 400: late provider failure"}}})
                self.messages.put_nowait({"method": "turn/completed", "params": {
                    "threadId": thread_id, "turn": {"id": "resumed-turn", "status": "failed",
                        "error": {"message": "injected late terminal provider failure"}}}})

    async def recv(self):
        message = await self.messages.get()
        params = message.get("params", {})
        if message.get("method") == "item/completed" and params["item"].get("phase") == "commentary":
            self.commentary_seen.append(params["threadId"])
        if message.get("method") == "turn/completed" and params["turn"]["status"] == "completed":
            self.completed_seen.append(params["threadId"])
        return json.dumps(message)


with tempfile.TemporaryDirectory(prefix="codex-shared-recovery-") as temporary:
    root = Path(temporary)
    pool = root / "pool"
    pool.mkdir()
    sqlite = pool / "sqlite"
    env = dict(os.environ, NORTH_CODEX_CONVERSATION_HOME=str(pool),
               NORTH_CODEX_CONVERSATION_SQLITE_HOME=str(sqlite), CODEX_RUNTIME=str(runtime))
    home_key = hashlib.sha256(f"{pool}\n{sqlite}".encode()).hexdigest()[:16]
    directory = Path(os.environ["XDG_RUNTIME_DIR"]) / f"codex-shared-{home_key}"
    endpoint = "unix://" + str(directory / "app-server.sock")
    unit = f"codex-shared-{home_key}.service"
    assert unit != "codex-shared-a29cde0b1fc2a000.service"
    try:
        assert command(str(launcher), env=env) == endpoint
        command("systemctl", "--user", "kill", "--kill-whom=main", "--signal=SIGKILL", unit)
        wait_inactive(unit)
        assert not directory.exists(), "systemd did not remove killed owner's socket directory"
        assert command(str(launcher), env=env) == endpoint
        command("systemctl", "--user", "stop", unit)
        wait_inactive(unit)
        directory.mkdir(mode=0o700)
        with socket.socket(socket.AF_UNIX) as stale:
            stale.bind(str(directory / "app-server.sock"))
        assert command(str(launcher), env=env) == endpoint
        print("PASS: SIGKILL cleanup, same-endpoint restart, and legacy dead-socket recovery")

        async def check_turn_summary_api():
            async with activation.unix_connect(str(directory / "app-server.sock"), uri="ws://localhost/",
                    compression=None, user_agent_header=None, proxy=None) as ws:
                async def rpc(sequence, method, params, expected_error=None):
                    await ws.send(json.dumps({"id": sequence, "method": method, "params": params}))
                    while True:
                        response = json.loads(await asyncio.wait_for(ws.recv(), 15))
                        if response.get("id") == sequence:
                            if expected_error is not None:
                                assert response == {"id": sequence, "error": expected_error}, response
                                return
                            assert "error" not in response, response
                            return response["result"]
                await rpc(1, "initialize", {"clientInfo": {"name": "activation_regression", "version": "1"},
                                          "capabilities": {"experimentalApi": True}})
                await ws.send(json.dumps({"method": "initialized", "params": {}}))
                thread = await rpc(2, "thread/start", {"cwd": str(root)})
                thread_id = thread["thread"]["id"]
                await rpc(3, "thread/turns/list", {"threadId": thread_id,
                          "limit": 1, "sortDirection": "desc", "itemsView": "summary"},
                          expected_error={"code": -32600, "message": f"thread {thread_id} is not materialized yet; "
                                          "thread/turns/list is unavailable before first user message"})
        asyncio.run(check_turn_summary_api())
        print("PASS: installed old runtime recognizes bounded current-turn query and rejects unmaterialized threads")

        bad_root = root / "bad"
        candidate = bad_root / "node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex"
        candidate.parent.mkdir(parents=True)
        (bad_root / "bin").mkdir()
        (bad_root / "bin/codex").symlink_to(candidate)
        candidate.write_text("#!/usr/bin/env bash\necho 'injected candidate startup failure' >&2\nexit 42\n")
        candidate.chmod(0o700)
        selector = root / "current"
        previous_selector_root = root / "previous-selected"
        (previous_selector_root / "bin").mkdir(parents=True)
        (previous_selector_root / "bin/codex").symlink_to(candidate)
        selector.symlink_to(previous_selector_root)
        checkpoint = root / "checkpoint"
        checkpoint.write_text("isolated service has no model turns\n")
        activation.ROOT = root
        activation.CONFIG = {
            "candidate": str(candidate), "candidate_sha256": hashlib.sha256(candidate.read_bytes()).hexdigest(),
            "old_runtime": str(runtime), "old_runtime_root": str(runtime.parent.parent),
            "candidate_root": str(bad_root), "previous_selector_root": str(previous_selector_root),
            "selector": str(selector), "unit": unit,
            "socket": str(directory / "app-server.sock"), "launcher": str(launcher),
            "conversation_home": str(pool), "sqlite_home": str(sqlite),
            "peer_checkpoint": str(checkpoint), "peer_checkpoint_sha256": hashlib.sha256(checkpoint.read_bytes()).hexdigest(),
            "resume": [{"id": "isolated-continuation-boundary", "message": "no model call"}],
            "preflight_only": False,
        }
        api = ActiveThreadApi()
        with patch.object(activation, "unix_connect", return_value=api):
            try:
                asyncio.run(activation.quiesce_threads())
            except AssertionError as error:
                assert "uncheckpointed active assistant turns" in str(error)
            else:
                raise AssertionError("unknown active turn was admitted")
            assert all(request["method"] != "turn/interrupt" for request in api.requests)
            activation.CONFIG["interrupt"] = [{"id": "checkpointed", "turn_id": "stale-turn"}]
            try:
                asyncio.run(activation.quiesce_threads())
            except AssertionError as error:
                assert "checkpointed turn changed" in str(error)
            else:
                raise AssertionError("stale checkpoint was admitted")
            assert all(request["method"] != "turn/interrupt" for request in api.requests)
            activation.CONFIG["interrupt"] = [{"id": "checkpointed", "turn_id": "current-turn"}]
            asyncio.run(activation.quiesce_threads())
            assert not api.active
        activation.CONFIG.pop("interrupt")
        print("PASS: uncheckpointed active turns remain untouched; exact authorized turn is interrupted and becomes idle")
        original_pid = command("systemctl", "--user", "show", unit, "-p", "MainPID", "--value")
        try:
            activation.activate("--activate")
        except RuntimeError as error:
            assert "isolated app-server exited during startup" in str(error), str(error)
        else:
            raise AssertionError("broken executable passed the real isolated preflight launcher")
        assert command("systemctl", "--user", "show", unit, "-p", "MainPID", "--value") == original_pid
        assert selector.resolve() == previous_selector_root
        run_process = subprocess.run
        canary_calls = []

        def reject_canary(*args, **kwargs):
            if isinstance(args[0], list) and args[0][1] == str(SOURCE / "provider-canary.py"):
                assert args[0] == [sys.executable, str(SOURCE / "provider-canary.py"),
                    "--candidate", str(candidate), "--sha256", activation.CONFIG["candidate_sha256"]]
                canary_calls.append(args[0])
                return subprocess.CompletedProcess(args[0], 1, json.dumps({"success": False,
                    "error": {"message": "HTTP 400: rejected canary"}}), "")
            return run_process(*args, **kwargs)

        with patch.object(activation.subprocess, "run", side_effect=reject_canary), \
                patch.object(activation, "quiesce_threads", new_callable=AsyncMock) as quiesce:
            try:
                activation.activate("--activate")
            except RuntimeError as error:
                assert "rejected canary" in str(error)
            else:
                raise AssertionError("rejected canary was admitted")
            quiesce.assert_not_awaited()
        assert len(canary_calls) == 1
        assert command("systemctl", "--user", "show", unit, "-p", "MainPID", "--value") == original_pid
        assert selector.resolve() == previous_selector_root
        assert not Path(str(selector) + ".communication-next").is_symlink()
        print("PASS: provider preflight rejection leaves PID, selector, and listener turns untouched")
        with patch.object(activation, "provider_preflight"), \
                patch.object(activation, "resume_threads", new_callable=AsyncMock) as resume:
            try:
                activation.activate("--activate")
            except RuntimeError as error:
                assert "previous runtime restored and listeners resumed" in str(error), str(error)
            else:
                raise AssertionError("failed candidate reported success")
            resume.assert_awaited_once()
        assert selector.resolve() == previous_selector_root
        asyncio.run(activation.quiesce_threads())
        receipts = [json.loads(line) for line in (root / "activation-receipt.jsonl").read_text().splitlines()]
        failures = [entry for entry in receipts if entry["stage"] == "command-failed"]
        assert len(failures) == 1, failures
        assert "shared server exited before becoming ready" in failures[0]["stderr"], failures
        assert any(entry["stage"] == "previous-runtime-restored" for entry in receipts)
        print("PASS: failed candidate restores selector, running old executable, and API availability; receipt preserves launcher stderr")

        candidate_root = root / "candidate"
        candidate = candidate_root / "node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex"
        candidate.parent.mkdir(parents=True)
        (candidate_root / "bin").mkdir()
        (candidate_root / "bin/codex").symlink_to(candidate)
        shutil.copy2(runtime, candidate)
        activation.CONFIG.update(candidate=str(candidate),
            candidate_root=str(candidate_root),
            candidate_sha256=hashlib.sha256(candidate.read_bytes()).hexdigest(), resume_timeout_seconds=0.15,
            resume=[{"id": name, "message": "no model call"} for name in ("listener-one", "listener-two")])
        original_resume = activation.resume_threads
        for outcome, diagnostic in (("provider400", "HTTP 400"), ("timeout", "listener recovery exceeded"),
                                    ("failed-turn", "injected terminal provider failure"),
                                    ("late-provider400", "HTTP 400: late provider failure"),
                                    ("late-failed-turn", "injected late terminal provider failure"),
                                    ("message-only", "listener recovery exceeded"),
                                    ("commentary-completed", "listener recovery exceeded")):
            observed = []
            apis = []
            receipt_start = len((root / "activation-receipt.jsonl").read_text().splitlines())

            async def injected_resume(started_turns=None):
                current = str(Path(f"/proc/{command('systemctl', '--user', 'show', unit, '-p', 'MainPID', '--value')}/exe").resolve())
                observed.append(current)
                api = ResumeApi(outcome if current == str(candidate) else "success")
                apis.append(api)
                owned_turns = started_turns if started_turns is not None else []
                with patch.object(activation, "unix_connect", return_value=api):
                    await original_resume(owned_turns)
                assert owned_turns == [{"id": name, "turn_id": "resumed-turn"}
                                       for name in ("listener-one", "listener-two")], owned_turns

            with patch.object(activation, "provider_preflight"), \
                    patch.object(activation, "resume_threads", side_effect=injected_resume):
                try:
                    activation.activate("--activate")
                except RuntimeError as error:
                    assert diagnostic in str(error), str(error)
                    assert "previous runtime restored and listeners resumed" in str(error), str(error)
                else:
                    raise AssertionError(f"{outcome} activation incorrectly succeeded")
            assert observed == [str(candidate), str(runtime)], observed
            assert selector.resolve() == previous_selector_root
            if outcome.startswith("late-"):
                assert apis[0].commentary_seen == ["listener-one", "listener-two"]
            assert apis[1].completed_seen == ["listener-one", "listener-two"]
            receipts = [json.loads(line) for line in
                        (root / "activation-receipt.jsonl").read_text().splitlines()[receipt_start:]]
            restored = next(index for index, entry in enumerate(receipts)
                            if entry["stage"] == "previous-runtime-restored")
            recovered = [entry for entry in receipts[restored + 1:]
                         if entry["stage"] == "original-thread-model-activity-observed"]
            assert {entry["thread_id"] for entry in recovered} == {"listener-one", "listener-two"}
            assert all(entry["turn_id"] == "resumed-turn" and entry["turn_status"] == "completed"
                       for entry in recovered)
            assert receipts[-1]["outcome"] == "previous-runtime-restored"
            asyncio.run(activation.quiesce_threads())
            print(f"PASS: {outcome} after candidate startup restores actual old executable and both completed listener responses")
    finally:
        subprocess.run(["systemctl", "--user", "stop", unit], capture_output=True)
        lock = Path(os.environ["XDG_RUNTIME_DIR"]) / f"codex-shared-{home_key}.lock"
        lock.unlink(missing_ok=True)
