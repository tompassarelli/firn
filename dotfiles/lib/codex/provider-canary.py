"""Check a pinned Codex candidate against the account provider in isolated state.

This is an OS/app-server protocol boundary used by coordinated activation.
It never changes the shared service, runtime selector, or account configuration.
"""
import argparse
import asyncio
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

from websockets.asyncio.client import unix_connect


def digest(path):
    with path.open("rb") as binary:
        return hashlib.file_digest(binary, "sha256").hexdigest()


def bounded_error(error):
    text = str(error)
    text = re.sub(r"gAAAA[A-Za-z0-9_=-]+", "[opaque content]", text)
    text = re.sub(r"(?i)bearer\s+\S+", "Bearer [redacted]", text)
    return text[:2048] or type(error).__name__


async def exchange(socket, root, receipt):
    async with unix_connect(str(socket), uri="ws://localhost/", compression=None,
                            user_agent_header=None, proxy=None,
                            max_size=8 * 1024 * 1024) as ws:
        sequence = 0
        completed = {}
        child_finals = {}
        calls = []
        root_id = None

        def observe(event):
            method = event.get("method")
            params = event.get("params", {})
            thread_id = params.get("threadId")
            item = params.get("item", {})
            if method == "error":
                error = params.get("error", params)
                raise RuntimeError("provider error: " + bounded_error(error))
            if method == "rawResponseItem/completed" and item.get("type") == "function_call":
                if len(calls) >= 32:
                    raise RuntimeError("probe exceeded 32 function calls")
                arguments = item.get("arguments", "")
                entry = {"thread_id": thread_id, "namespace": item.get("namespace"),
                         "name": item.get("name"),
                         "encrypted_function_args": item.get("encrypted_function_args", "absent"),
                         "arguments_bytes": len(arguments.encode()),
                         "arguments_sha256": hashlib.sha256(arguments.encode()).hexdigest()}
                if item.get("namespace") == "collaboration":
                    args = json.loads(arguments)
                    if item.get("name") == "spawn_agent":
                        entry["fork_turns"] = args.get("fork_turns")
                        entry["task_name"] = args.get("task_name")
                calls.append(entry)
                receipt["calls"] = calls
            if method == "item/completed" and item.get("type") == "agentMessage":
                if thread_id != root_id and item.get("phase") == "final_answer":
                    text = item.get("text", "")
                    child_finals.setdefault(thread_id, []).append(text)
                    if len(child_finals[thread_id]) > 4:
                        raise RuntimeError("probe exceeded expected child final messages")
                    if text not in (receipt["send_token"], receipt["followup_token"]):
                        raise RuntimeError("child returned an unexpected or unreadable message")
            if method == "turn/completed":
                turn = params["turn"]
                completed[thread_id] = turn["status"]
                receipt["completed_threads"] = completed
                if turn["status"] != "completed":
                    raise RuntimeError("turn " + turn["status"] + ": " + bounded_error(turn.get("error")))

        async def rpc(method, params):
            nonlocal sequence
            sequence += 1
            await ws.send(json.dumps({"id": sequence, "method": method, "params": params}))
            while True:
                event = json.loads(await ws.recv())
                if event.get("id") == sequence:
                    if "error" in event:
                        raise RuntimeError(method + ": " + bounded_error(event["error"]))
                    return event["result"]
                observe(event)

        await rpc("initialize", {"clientInfo": {"name": "provider_candidate_canary", "version": "1"},
                                 "capabilities": {"experimentalApi": True}})
        await ws.send(json.dumps({"method": "initialized", "params": {}}))
        started = await rpc("thread/start", {
            "cwd": str(root), "model": "gpt-6-astra", "historyMode": "paginated",
            "experimentalRawEvents": True,
            "baseInstructions": "You are a bounded synthetic collaboration test fixture. Follow the user instructions exactly. Do not inspect files, run commands, or perform unrelated work. Child agents are test fixtures only.",
            "developerInstructions": "Use only native collaboration tools and clock if needed. Never use files or shell tools. Do not read global skills. All test messages are synthetic.",
            "config": {"model_reasoning_effort": "low"}})
        root_id = started["thread"]["id"]
        receipt["parent_thread_id"] = root_id
        prompt = (
            "Run this exact bounded native collaboration test. Spawn exactly one agent with "
            "task_name='echo_probe', fork_turns='none', model='gpt-6-astra', reasoning_effort='low'. "
            "Its initial task must say: 'You are an echo fixture. Wait up to 45 seconds using "
            "clock.sleep for a separate message from /root. When that message arrives, reply with "
            "its token verbatim in your final answer. If any message is unreadable, reply "
            "UNREADABLE_MESSAGE without quoting or decoding it. Do not delegate or use filesystem/shell tools.' "
            "Do not include either token in the spawn task. Immediately call native "
            "collaboration.send_message to echo_probe with this token: " + receipt["send_token"] + ". "
            "Wait for the child's final result with collaboration.wait_agent. Then call native "
            "collaboration.followup_task on this same idle child with: 'Reply with this exact token: "
            + receipt["followup_token"] + "'. Wait for its second final result. Report both child results "
            "verbatim and whether they matched. Do not claim success without returned child results. "
            "If any call fails report the error and stop.")
        turn = await rpc("turn/start", {"threadId": root_id,
            "input": [{"type": "text", "text": prompt}]})
        receipt["parent_turn_id"] = turn["turn"]["id"]
        while root_id not in completed:
            observe(json.loads(await ws.recv()))
        expected = [receipt["send_token"], receipt["followup_token"]]
        matches = [thread for thread, texts in child_finals.items() if texts == expected]
        parent_calls = [call for call in calls if call["thread_id"] == root_id
                        and call["namespace"] == "collaboration"]
        spawn_calls = [call for call in parent_calls if call["name"] == "spawn_agent"]
        required = {"spawn_agent", "send_message", "followup_task"}
        if len(matches) != 1 or len(child_finals) != 1 or completed.get(matches[0]) != "completed":
            raise RuntimeError("both exact tokens were not returned by the same completed child")
        if not required <= {call["name"] for call in parent_calls}:
            raise RuntimeError("required native collaboration calls were not observed")
        if len(spawn_calls) != 1 or spawn_calls[0].get("fork_turns") != "none":
            raise RuntimeError("probe did not use exactly one child with no inherited history")
        receipt.update(parent_completed=True, child_thread_id=matches[0],
                       child_send_echo_matched=True, child_followup_echo_matched=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--sha256", required=True)
    args = parser.parse_args()
    receipt = {"version": 1, "success": False, "candidate": str(args.candidate),
               "expected_sha256": args.sha256, "started_at": time.time()}
    process = None
    root = None
    try:
        if not args.candidate.is_absolute() or not args.candidate.is_file() or not os.access(args.candidate, os.X_OK):
            raise RuntimeError("candidate must be an absolute executable file")
        candidate = args.candidate.resolve()
        receipt["candidate"] = str(candidate)
        receipt["actual_sha256"] = digest(candidate)
        if receipt["actual_sha256"] != args.sha256:
            raise RuntimeError("candidate SHA256 mismatch")
        root = Path(tempfile.mkdtemp(prefix="codex-provider-canary-"))
        receipt["state_directory"] = str(root)
        receipt["send_token"] = "SEND_" + os.urandom(12).hex()
        receipt["followup_token"] = "FOLLOWUP_" + os.urandom(12).hex()
        socket = root / "app-server.sock"
        env = dict(os.environ)
        env.update(CODEX_RUNTIME=str(candidate), NORTH_CODEX_CONVERSATION_HOME=str(root),
                   NORTH_CODEX_CONVERSATION_SQLITE_HOME=str(root / "sqlite"), NORTH_NO_SLICE="1")
        launcher = Path(__file__).resolve().parents[2] / "bin" / "codex"
        process = subprocess.Popen([str(launcher), "app-server", "--listen", "unix://" + str(socket),
            "--enable", "multi_agent_v2"], env=env, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        deadline = time.monotonic() + 30
        while not socket.is_socket():
            if process.poll() is not None:
                raise RuntimeError("isolated app-server exited during startup")
            if time.monotonic() >= deadline:
                raise TimeoutError("isolated app-server startup timed out")
            time.sleep(.1)
        if Path(f"/proc/{process.pid}/exe").resolve() != candidate:
            raise RuntimeError("isolated app-server executable differs from candidate")
        asyncio.run(asyncio.wait_for(exchange(socket, root, receipt), timeout=360))
        if digest(candidate) != args.sha256:
            raise RuntimeError("candidate identity changed during probe")
        receipt["success"] = True
    except Exception as error:
        receipt["error"] = {"type": type(error).__name__, "message": bounded_error(error)}
    finally:
        if process is not None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            receipt["server_exit"] = process.returncode
        receipt["finished_at"] = time.time()
        if root is not None:
            (root / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt))
    return 0 if receipt["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
