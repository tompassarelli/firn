import contextlib
import json
import os
import pwd
import re
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


def fetch_main(repo, origin, header=""):
    command(["git", "init", "--quiet", "--bare", str(repo)])
    auth = {"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "http.extraHeader", "GIT_CONFIG_VALUE_0": header} if header else {}
    git = ["git", "-c", "core.hooksPath=/dev/null", "-C", str(repo)]
    command(git + ["fetch", "--force", "--no-tags", origin, "+refs/heads/main:refs/remotes/origin/main"], env={**os.environ, **auth})
    return command(git + ["rev-parse", "refs/remotes/origin/main"]).strip()


def materialize(repo, sha, destination):
    command(["git", "-c", "core.hooksPath=/dev/null", "clone", "--no-hardlinks", "--no-checkout", str(repo), str(destination)])
    command(["git", "-C", str(destination), "checkout", "--detach", sha])


class Service:
    def __init__(self, state, origin, uid, activate):
        self.state, self.origin, self.uid, self.activate = state, origin, uid, activate

    def request(self, uid, sha):
        if uid != self.uid:
            return 77, "refused: requesting uid is not the configured user"
        if not re.fullmatch(r"[0-9a-f]{40}", sha):
            return 64, "refused: expected one full lowercase commit SHA"
        tip = fetch_main(self.state / "repo", self.origin)
        if sha != tip:
            return 65, f"refused: SHA is not current origin/main ({tip})"
        with tempfile.TemporaryDirectory(prefix="request-", dir=self.state) as directory:
            snapshot = Path(directory) / "snapshot"
            materialize(self.state / "repo", sha, snapshot)
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
        with contextlib.suppress(OSError):
            connection.sendall(json.dumps({"status": status, "output": output}).encode() + b"\n")


def client(sha, path=SOCKET):
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.connect(path)
            connection.sendall(sha.encode() + b"\n")
            connection.shutdown(socket.SHUT_WR)
            with connection.makefile("r") as stream:
                result = json.loads(stream.readline())
        print(result["output"])
        return result["status"]
    except (FileNotFoundError, ConnectionRefusedError):
        print(f"firn landed rebuild: no landed-rebuild service listens on {path}; this host does not enable the landed-rebuild module (a host that follows a system flake is deployed with firn host deploy HOST, or by starting its nexus-upgrade.service)", file=sys.stderr)
        return 69
    except (OSError, ValueError) as error:
        print(f"firn landed rebuild: {error}", file=sys.stderr)
        return 70


def serve(username, home, bun, runtime, environment_switch, system_origin, system_header):
    user = pwd.getpwnam(username)
    env = {"HOME": str(STATE), "PATH": os.environ["PATH"],
           "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
           "FIRN_LANDED_HOME": home, "FIRN_LANDED_USER": username,
           "FIRN_LANDED_UID": str(user.pw_uid), "FIRN_LANDED_ENVIRONMENT_SWITCH": environment_switch}

    def activate(snapshot, sha):
        system = {}
        if system_origin != "-":
            header = subprocess.run([system_header], check=True, stdout=subprocess.PIPE, text=True).stdout
            materialize(STATE / "system", fetch_main(STATE / "system", system_origin, header), snapshot.parent / "system")
            system = {"FIRN_SYSTEM_FLAKE": str(snapshot.parent / "system")}
        for directory, dirs, files in os.walk(snapshot.parent):
            os.chmod(directory, 0o755)
            for name in files:
                path = Path(directory) / name
                if not path.is_symlink():
                    os.chmod(path, 0o755 if path.stat().st_mode & 0o111 else 0o644)
        os.chmod(STATE, 0o711)
        return rebuild(snapshot, bun, runtime, {**env, **system, "FIRN_REPO": str(snapshot), "FIRN_SNAPSHOT_DIR": str(snapshot.parent / "validation")})

    service = Service(STATE, ORIGIN, user.pw_uid, activate)
    if os.geteuid() != 0 or os.environ.get("LISTEN_PID") != str(os.getpid()) or os.environ.get("LISTEN_FDS") != "1":
        raise RuntimeError("service requires root and exactly one systemd socket")
    os.environ.update({"HOME": "/root", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"})
    with socket.socket(fileno=3) as listener:
        connection, _ = listener.accept()
        with connection:
            service.handle(connection)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "client":
        sys.exit(client(sys.argv[2]))
    if len(sys.argv) == 9 and sys.argv[1] == "serve":
        serve(*sys.argv[2:])
    else:
        sys.exit("usage: landed-rebuild.py client SHA | serve USER HOME BUN RUNTIME SWITCH SYSTEM_ORIGIN|- SYSTEM_HEADER_COMMAND")
