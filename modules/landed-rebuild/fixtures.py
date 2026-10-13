import importlib.util
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

spec = importlib.util.spec_from_file_location("landed", Path(__file__).with_name("landed-rebuild.py"))
landed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(landed)


def git(repo, *args):
    return landed.command(["git", "-C", str(repo), *args]).strip()


def request(service, sha):
    client, server = socket.socketpair()
    def handle():
        with server:
            service.handle(server)
    thread = threading.Thread(target=handle)
    thread.start()
    with client:
        client.sendall(sha.encode() + b"\n")
        client.shutdown(socket.SHUT_WR)
        with client.makefile("r") as stream:
            result = json.loads(stream.readline())
    thread.join()
    return result


with tempfile.TemporaryDirectory(prefix="firn-landed-fixture-") as directory:
    root = Path(directory)
    origin = root / "origin"
    origin.mkdir()
    git(origin, "init", "-b", "main")
    git(origin, "config", "user.name", "Fixture")
    git(origin, "config", "user.email", "fixture@example.invalid")
    (origin / "value").write_text("old")
    git(origin, "add", "value")
    git(origin, "commit", "-m", "old")
    old = git(origin, "rev-parse", "HEAD")
    git(origin, "checkout", "-b", "branch")
    (origin / "value").write_text("branch")
    git(origin, "commit", "-am", "branch")
    branch = git(origin, "rev-parse", "HEAD")
    git(origin, "checkout", "main")
    (origin / "value").write_text("tip")
    git(origin, "commit", "-am", "tip")
    tip = git(origin, "rev-parse", "HEAD")
    state = root / "state"
    state.mkdir()
    activations = []
    runtime = root / "runtime.py"
    runtime.write_text('''import os, stat, subprocess
from pathlib import Path
validation = Path.cwd().parent / "validation"
subprocess.run(["git", "worktree", "add", "--detach", str(validation), "HEAD"], check=True, capture_output=True)
assert stat.S_IMODE(validation.stat().st_mode) == 0o755
assert stat.S_IMODE((validation / "value").stat().st_mode) == 0o644
print((validation / "value").read_text())
subprocess.run(["git", "worktree", "remove", str(validation)], check=True, capture_output=True)
''')
    def activate(snapshot, sha):
        git(origin, "symbolic-ref", "HEAD", "refs/heads/branch")
        actual = git(snapshot, "rev-parse", "HEAD")
        assert actual == sha
        activations.append(actual)
        previous_umask = os.umask(0o077)
        try:
            return landed.rebuild(snapshot, sys.executable, str(runtime), os.environ.copy())
        finally:
            os.umask(previous_umask)
    service = landed.Service(state, str(origin), os.getuid(), activate)
    (origin / "value").write_text("requester dirty working tree")
    accepted = request(service, tip)
    assert accepted["status"] == 0, accepted
    assert tip in accepted["output"], accepted
    assert accepted["output"].startswith("tip\n"), accepted
    for sha in [old, branch, "main", tip + " --extra", "f" * 39]:
        refused = request(service, sha)
        assert refused["status"] != 0 and "refused:" in refused["output"], refused
    wrong_uid = landed.Service(state, str(origin), os.getuid() + 1, activate)
    refused = request(wrong_uid, tip)
    assert refused["status"] == 77, refused
    assert activations == [tip], activations
    assert not list(state.glob("request-*"))
    print("ok: real Git and socket peer acceptance; older main, branch, malformed and wrong uid refused; dirty requester tree excluded")
