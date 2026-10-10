"""Claude Code usage rows: `claude -p /usage` (0 turns, $0) refreshes ~/.claude.json's cachedUsageUtilization,
which this prints as one JSON row per window, billing flag and unnamed bucket (contract: firn#12 plan §6)."""

import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

KNOWN = {"five_hour", "seven_day", "limits", "extra_usage", "spend"}
WINDOW_MIN = {"session": 300, "weekly": 10080}
# Claude Code sessions refresh this cache themselves; a /usage call is only needed when it is older.
FRESH_S = 300


def utc(ts):
    return datetime.fromisoformat(ts).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if ts else None


def rows(cache, now):
    usage = cache.get("utilization") or {}
    account = hashlib.sha256(cache.get("accountUuid", "").encode()).hexdigest()[:8]
    base = {"provider": "claude", "account": account, "source": "claude -p /usage; ~/.claude.json cachedUsageUtilization",
            "ts": utc(datetime.fromtimestamp(cache.get("fetchedAtMs", 0) / 1000, timezone.utc).isoformat()) or now}
    for limit in usage.get("limits") or []:
        scope = ((limit.get("scope") or {}).get("model") or {}).get("display_name")
        yield {**base, "kind": "window", "name": limit["kind"] + (f"/{scope}" if scope else ""),
               "used_pct": limit.get("percent"), "window_min": WINDOW_MIN.get(limit.get("group")),
               "resets_at": utc(limit.get("resets_at")), "amount": None}
    extra = usage.get("extra_usage") or {}
    yield {**base, "kind": "billing", "name": "extra_usage", "used_pct": extra.get("utilization"), "window_min": None,
           "resets_at": None, "amount": 1 if extra.get("is_enabled") else 0}
    spend = usage.get("spend") or {}
    if spend:
        yield {**base, "kind": "billing", "name": "spend", "used_pct": spend.get("percent"), "window_min": None,
               "resets_at": None, "amount": 1 if spend.get("enabled") or spend.get("auto_reload") else 0}
        if spend.get("balance") is not None:
            yield {**base, "kind": "billing", "name": "credits", "used_pct": None, "window_min": None,
                   "resets_at": None, "amount": spend["balance"]}
    for name, bucket in usage.items():
        if name not in KNOWN and isinstance(bucket, dict) and "utilization" in bucket:
            yield {**base, "kind": "grant", "name": name, "used_pct": bucket.get("utilization"), "window_min": None,
                   "resets_at": utc(bucket.get("resets_at")), "amount": None, "raw": bucket}


def main(argv):
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    path = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~"), ".claude.json")
    try:
        fetched = (json.load(open(path)).get("cachedUsageUtilization") or {}).get("fetchedAtMs", 0) / 1000
    except (OSError, ValueError):
        fetched = 0
    if "--no-refresh" not in argv and datetime.now(timezone.utc).timestamp() - fetched > FRESH_S:
        try:
            subprocess.run(["claude", "-p", "/usage", "--output-format", "json"], capture_output=True, timeout=30, check=False)
        except (OSError, subprocess.TimeoutExpired):
            pass
    try:
        cache = json.load(open(path)).get("cachedUsageUtilization")
    except (OSError, ValueError):
        return 0
    for row in rows(cache or {}, now) if cache else []:
        print(json.dumps(row))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
