import base64
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import socket
import struct
import subprocess
import sys
from datetime import datetime, timezone


SOURCE = "account/rateLimits/read"


def utc(value):
    if value is None:
        return None
    if isinstance(value, str):
        value = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        value = datetime.fromtimestamp(value, timezone.utc)
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def number(value):
    if value is None:
        return None
    value = float(value)
    if not math.isfinite(value):
        raise ValueError("non-finite usage value")
    return int(value) if value.is_integer() else value


def usage_rows(usage, account, ts):
    rows = []

    def add(kind, name, used_pct=None, window_min=None, resets_at=None, amount=None):
        rows.append({"provider": "codex", "account": account, "kind": kind,
                     "name": name, "used_pct": used_pct, "window_min": window_min,
                     "resets_at": utc(resets_at), "amount": number(amount),
                     "source": SOURCE, "ts": ts})

    buckets = dict(usage.get("rateLimitsByLimitId") or {})
    default = usage.get("rateLimits")
    if default:
        buckets.setdefault(default.get("limitId") or "codex", default)
    for limit_id, bucket in buckets.items():
        prefix = "" if limit_id == "codex" else limit_id + ":"
        for window in bucket.values():
            if not isinstance(window, dict) or "windowDurationMins" not in window:
                continue
            minutes = window["windowDurationMins"]
            if minutes is not None:
                minutes = int(minutes)
            name = {300: "5h", 10080: "week"}.get(minutes, f"{minutes}m" if minutes is not None else "unknown")
            used = number(window.get("usedPercent"))
            if used is not None:
                used = max(0, min(100, used))
            add("window", prefix + name, used, minutes, window.get("resetsAt"))
        credits = bucket.get("credits")
        if credits is not None:
            add("billing", prefix + "credits", amount=credits.get("balance"))
            if "hasCredits" in credits:
                add("billing", prefix + "hasCredits", amount=credits["hasCredits"])
            for name in ("spendControlReached", "ordinaryUsageAllowed"):
                if name in credits:
                    add("billing", prefix + name, amount=credits[name])
        for name in ("spendControlReached", "ordinaryUsageAllowed"):
            if name in bucket:
                add("billing", prefix + name, amount=bucket[name])
    for name in ("spendControlReached", "ordinaryUsageAllowed"):
        if name in usage:
            add("billing", name, amount=usage[name])
    credits = usage.get("credits")
    if credits is not None:
        add("billing", "credits", amount=credits.get("balance"))
        if "hasCredits" in credits:
            add("billing", "hasCredits", amount=credits["hasCredits"])
        for name in ("spendControlReached", "ordinaryUsageAllowed"):
            if name in credits:
                add("billing", name, amount=credits[name])
    resets = usage.get("rateLimitResetCredits")
    if resets is not None:
        add("billing", "rateLimitResetCredits", amount=resets.get("availableCount"))
        for credit in resets.get("credits") or []:
            status = credit.get("status")
            amount = None if status is None else int(status == "available")
            add("grant", credit.get("resetType") or "rateLimitResetCredit",
                resets_at=credit.get("expiresAt"), amount=amount)
    return rows


def read_exact(peer, length):
    data = bytearray()
    while len(data) < length:
        part = peer.recv(length - len(data))
        if not part:
            raise ConnectionError("shared app-server closed the connection")
        data.extend(part)
    return bytes(data)


def send_frame(peer, data, opcode=1):
    mask = os.urandom(4)
    length = len(data)
    if length < 126:
        header = bytes([0x80 | opcode, 0x80 | length])
    elif length < 65536:
        header = bytes([0x80 | opcode, 0xFE]) + struct.pack("!H", length)
    else:
        header = bytes([0x80 | opcode, 0xFF]) + struct.pack("!Q", length)
    peer.sendall(header + mask + bytes(value ^ mask[i % 4] for i, value in enumerate(data)))


def rpc(peer, request_id, method, params):
    send_frame(peer, json.dumps({"id": request_id, "method": method, "params": params}).encode())
    data = bytearray()
    while True:
        head = read_exact(peer, 2)
        opcode = head[0] & 15
        length = head[1] & 127
        if length == 126:
            length = struct.unpack("!H", read_exact(peer, 2))[0]
        elif length == 127:
            length = struct.unpack("!Q", read_exact(peer, 8))[0]
        mask = read_exact(peer, 4) if head[1] & 128 else None
        payload = read_exact(peer, length)
        if mask:
            payload = bytes(value ^ mask[i % 4] for i, value in enumerate(payload))
        if opcode == 8:
            raise ConnectionError("shared app-server closed the connection")
        if opcode == 9:
            send_frame(peer, payload, 10)
            continue
        if opcode == 10:
            continue
        if opcode not in (0, 1):
            raise ValueError("unexpected shared app-server frame")
        data.extend(payload)
        if not head[0] & 128:
            continue
        message = json.loads(data)
        data.clear()
        if message.get("id") != request_id:
            continue
        if "error" in message:
            raise RuntimeError(f"{method} failed (RPC code {message['error'].get('code')})")
        return message["result"]


def main():
    pooled = Path(os.environ.get("NORTH_CODEX_POOLED_HOME", Path.home() / ".local/state/north/codex-pooled"))
    path = pooled / "app-server-control/app-server-control.sock"
    if not path.is_socket():
        listeners = subprocess.run(["ss", "-xlH"], capture_output=True, text=True, check=True, timeout=5).stdout
        match = re.search(rf"/tmp/codex-daemon-{os.getuid()}/[0-9a-f]+\b", listeners)
        if not match:
            raise ConnectionError("no shared Codex app-server is listening")
        path = Path(match[0])
    with socket.socket(socket.AF_UNIX) as peer:
        peer.settimeout(30)
        peer.connect(str(path))
        key = base64.b64encode(os.urandom(16)).decode()
        peer.sendall(("GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
                      "Connection: Upgrade\r\nSec-WebSocket-Key: " + key +
                      "\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        header = bytearray()
        while not header.endswith(b"\r\n\r\n"):
            header.extend(read_exact(peer, 1))
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        fields = {name.lower(): value.strip() for name, value in
                  (line.split(b":", 1) for line in bytes(header).split(b"\r\n")[1:] if b":" in line)}
        if not header.startswith(b"HTTP/1.1 101 ") or fields.get(b"sec-websocket-accept") != accept:
            raise ConnectionError("shared app-server WebSocket upgrade failed")
        rpc(peer, 1, "initialize", {"clientInfo": {"name": "usage-codex", "version": "1"},
                                    "capabilities": {"experimentalApi": True}})
        send_frame(peer, b'{"method":"initialized","params":{}}')
        identity = rpc(peer, 2, "account/read", {"refreshToken": False})
        if identity.get("account") is None:
            return
        usage = rpc(peer, 3, SOURCE, {})
        ts = utc(datetime.now(timezone.utc).timestamp())
        account_id = ((identity.get("workspaceRouting") or {}).get("chatgptAccountId")
                      or identity["account"].get("accountId") or usage.get("accountId"))
        if not account_id:
            raise ValueError("shared app-server did not report an account id")
        account = hashlib.sha256(account_id.encode()).hexdigest()[:8]
        rows = usage_rows(usage, account, ts)
    for row in rows:
        print(json.dumps(row, separators=(",", ":")))


def timed_out(*_):
    raise TimeoutError("shared app-server read exceeded 30 seconds")


if __name__ == "__main__":
    signal.signal(signal.SIGALRM, timed_out)
    signal.alarm(30)
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"usage_codex: {error}", file=sys.stderr)
        sys.exit(1)
    finally:
        signal.alarm(0)
