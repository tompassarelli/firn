import json
import os
import pwd
import re
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

SOCKET = "/run/firn-landed-rebuild.sock"
ORIGIN = "https://github.com/tompassarelli/firn.git"
STATE = Path("/var/lib/firn-landed-rebuild")


def command(argv, **kwargs):
    return subprocess.run(argv, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, **kwargs).stdout


def rebuild(snapshot, bun, runtime, env):
    result = subprocess.run([bun, runtime], cwd=snapshot, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, umask=0o022)
    return result.returncode, result.stdout


class Service:
    def __init__(self, state, origin, uid, activate):
        self.state, self.origin, self.uid, self.activate = state, origin, uid, activate

    def request(self, uid, sha):
        if uid != self.uid:
            return 77, "refused: requesting uid is not the configured user"
        if not re.fullmatch(r"[0-9a-f]{40}", sha):
            return 64, "refused: expected one full lowercase commit SHA"
        repo = self.state / "repo"
        if not repo.exists():
            command(["git", "init", "--bare", str(repo)])
        git = ["git", "-c", "core.hooksPath=/dev/null", "-C", str(repo)]
        command(git + ["fetch", "--force", "--no-tags", self.origin,
                       "+refs/heads/main:refs/remotes/origin/main"])
        tip = command(git + ["rev-parse", "refs/remotes/origin/main"]).strip()
        if sha != tip:
            return 65, f"refused: SHA is not current origin/main ({tip})"
        with tempfile.TemporaryDirectory(prefix="request-", dir=self.state) as directory:
            snapshot = Path(directory) / "snapshot"
            command(["git", "-c", "core.hooksPath=/dev/null", "clone", "--no-hardlinks",
                     "--no-checkout", str(repo), str(snapshot)])
            command(["git", "-C", str(snapshot), "checkout", "--detach", sha])
            status, output = self.activate(snapshot, sha)
            if status == 0:
                return 0, output.rstrip() + f"\nfirn activated snapshot {sha}"
            return status, output.rstrip() + f"\nfirn activation failed for snapshot {sha} (exit {status})"

    def handle(self, connection):
        _, uid, _ = struct.unpack("3i", connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
        sha = ""
        try:
            connection.settimeout(10)
            raw = b""
            while len(raw) <= 41 and not raw.endswith(b"\n"):
                chunk = connection.recv(42 - len(raw))
                if not chunk:
                    break
                raw += chunk
            sha = raw.decode("ascii", errors="replace").removesuffix("\n")
            print(f"request uid={uid} sha={json.dumps(sha)}", flush=True)
            status, output = self.request(uid, sha)
        except Exception as error:
            status, output = 70, f"refused: service failure: {error}"
        print(f"result uid={uid} sha={json.dumps(sha)} status={status} {output}", flush=True)
        connection.settimeout(None)
        connection.sendall(json.dumps({"status": status, "output": output}).encode() + b"\n")


def client(sha):
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.connect(SOCKET)
            connection.sendall(sha.encode() + b"\n")
            connection.shutdown(socket.SHUT_WR)
            with connection.makefile("r") as stream:
                result = json.loads(stream.readline())
        print(result["output"])
        return result["status"]
    except (OSError, ValueError) as error:
        print(f"firn landed rebuild: {error}", file=sys.stderr)
        return 70


def serve(username, home, bun, runtime, environment_switch, system_source):
    user = pwd.getpwnam(username)
    env = {"HOME": str(STATE), "PATH": os.environ["PATH"],
           "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
           "FIRN_LANDED_HOME": home, "FIRN_LANDED_USER": username,
           "FIRN_LANDED_UID": str(user.pw_uid), "FIRN_LANDED_ENVIRONMENT_SWITCH": environment_switch}

    def activate(snapshot, sha):
        if not system_source.startswith("/nix/store/") or not Path(system_source, "flake.nix").is_file():
            return 78, "refused: immutable installed system flake is not configured"
        system = snapshot.parent / "system"
        shutil.copytree(system_source, system, symlinks=True)
        command(["git", "-C", str(system), "init"])
        command(["git", "-C", str(system), "add", "."])
        command(["git", "-C", str(system), "-c", "user.name=Firn service",
                 "-c", "user.email=firn@example.invalid", "commit", "-m", "Installed system source"])
        for directory, dirs, files in os.walk(snapshot.parent):
            os.chmod(directory, 0o755)
            for name in files:
                path = Path(directory) / name
                if not path.is_symlink():
                    os.chmod(path, 0o755 if path.stat().st_mode & 0o111 else 0o644)
        os.chmod(STATE, 0o711)
        fixed_env = {**env, "FIRN_REPO": str(snapshot), "FIRN_SYSTEM_FLAKE": str(system),
                     "FIRN_SNAPSHOT_DIR": str(snapshot.parent / "validation")}
        return rebuild(snapshot, bun, runtime, fixed_env)

    service = Service(STATE, ORIGIN, user.pw_uid, activate)
    if os.geteuid() != 0 or os.environ.get("LISTEN_PID") != str(os.getpid()) or os.environ.get("LISTEN_FDS") != "1":
        raise RuntimeError("service requires root and exactly one systemd socket")
    os.environ.update({"HOME": "/root", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"})
    with socket.socket(fileno=3) as listener:
        while True:
            connection, _ = listener.accept()
            with connection:
                service.handle(connection)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "client":
        sys.exit(client(sys.argv[2]))
    if len(sys.argv) == 8 and sys.argv[1] == "serve":
        serve(*sys.argv[2:])
    else:
        sys.exit("usage: landed-rebuild.py client SHA | serve USER HOME")
