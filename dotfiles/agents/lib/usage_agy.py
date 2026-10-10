import hashlib
import json
import math
import os
import re
import selectors
import signal
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


COMMAND = ["agy", "-p", "/usage", "--output-format", "json"]
CONVERSATIONS = Path.home() / ".gemini/antigravity-cli/conversations"
WINDOW_MIN = {"5h": 300, "weekly": 10080}


def utc(value):
    if not value:
        return None
    try:
        stamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if stamp.tzinfo is None:
            return None
        return stamp.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    except (ValueError, TypeError, AttributeError):
        return None


def row(account, name, used, window, reset, source, now):
    return {"provider": "gemini", "account": account, "kind": "window", "name": name,
            "used_pct": used, "window_min": window, "resets_at": reset, "amount": None,
            "source": source, "ts": now}


def usage_rows(data, account, now):
    for group in data.get("groups", []):
        for bucket in group.get("buckets", []):
            remaining = bucket.get("remaining_fraction")
            used = (100 * (1 - remaining) if isinstance(remaining, (int, float))
                    and not isinstance(remaining, bool) and math.isfinite(remaining)
                    and 0 <= remaining <= 1 else None)
            window = bucket["window"]
            yield row(account, f"{group['name']}/{window}", used, WINDOW_MIN.get(window),
                      utc(bucket.get("reset_time")), " ".join(COMMAND), now)


def varint(blob, offset):
    value = 0
    for shift in range(0, 70, 7):
        byte = blob[offset]
        offset += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, offset
    raise ValueError("invalid varint")


def protobuf_fields(blob):
    offset = 0
    while offset < len(blob):
        tag, offset = varint(blob, offset)
        wire = tag & 7
        if wire == 0:
            value, offset = varint(blob, offset)
        elif wire == 2:
            size, offset = varint(blob, offset)
            value = blob[offset:offset + size]
            if len(value) != size:
                raise ValueError("truncated field")
            offset += size
        elif wire in (1, 5):
            offset += 8 if wire == 1 else 4
            continue
        else:
            raise ValueError("invalid wire type")
        yield tag >> 3, value


def event_time(metadata):
    stamp = dict(protobuf_fields(metadata)).get(1)
    fields = dict(protobuf_fields(stamp))
    return datetime.fromtimestamp(fields[1] + fields.get(2, 0) / 1e9, timezone.utc)


def recorded_pro(account, now):
    latest = None
    for path in sorted(CONVERSATIONS.glob("*.db")):
        try:
            with sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=0.1) as db:
                records = db.execute(
                    "SELECT idx, metadata, step_payload FROM steps WHERE step_type = 17 AND status = 3"
                    " AND instr(step_payload, ?) > 0"
                    " AND instr(step_payload, ?) > 0 AND instr(step_payload, ?) > 0",
                    (b"quotaResetTimeStamp", b"gemini-pro-agent", b"429"))
                for idx, metadata, payload in records:
                    text = bytes(payload).decode("utf-8", "ignore")
                    match = re.search(r'quotaResetTimeStamp["\\:\s]*([0-9T:Z.+-]+)', text)
                    reset = utc(match[1]) if match else None
                    if not reset or datetime.fromisoformat(reset) <= datetime.fromisoformat(now):
                        continue
                    event = event_time(bytes(metadata))
                    if event > datetime.fromisoformat(now):
                        continue
                    source = (f"~/.gemini/antigravity-cli/conversations/{path.name}"
                              f" steps[idx={idx}].step_payload+metadata")
                    candidate = (event, source, reset)
                    if latest is None or candidate > latest:
                        latest = candidate
        except (OSError, sqlite3.Error, ValueError, TypeError, KeyError, IndexError, OverflowError):
            continue
    if latest:
        yield row(account, "gemini-pro-agent/recorded-quota", 100, None, latest[2], latest[1], now)


def usage_response(process):
    output = []
    tail = b""
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        selector.register(process.stderr, selectors.EVENT_READ)
        while selector.get_map():
            for key, _ in selector.select():
                chunk = os.read(key.fd, 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                if b"Authentication required." in tail + chunk:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=1)
                    return None
                tail = (tail + chunk)[-64:]
                if key.fileobj is process.stdout:
                    output.append(chunk)
    process.wait(timeout=1)
    return b"".join(output)


def main():
    process = None

    def timeout(signum, frame):
        if process is not None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        os._exit(1)

    signal.signal(signal.SIGALRM, timeout)
    signal.setitimer(signal.ITIMER_REAL, 30)
    try:
        process = subprocess.Popen(COMMAND, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        output = usage_response(process)
        if output is None:
            return 0
        if process.returncode:
            return 1
        response = json.loads(output)
        data = (response.get("command") or {}).get("data") or {}
        if not data.get("groups"):
            return 0
        email = data.get("email")
        account = hashlib.sha256(email.encode()).hexdigest()[:8] if email else "default"
        now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        rows = list(usage_rows(data, account, now)) + list(recorded_pro(account, now))
        for item in rows:
            print(json.dumps(item, allow_nan=False))
        return 0
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        print("agy usage: unavailable usage response", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
