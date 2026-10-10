"""agents usage: run every usage_<provider>.py adapter beside this file in parallel (30 s each, 0 model turns),
record their rows in threads.db's usage table, and print the latest row per account window."""

import json
import os
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
DB = os.environ.get("THREADS_DB") or os.path.expanduser("~/.local/state/threads/threads.db")
STALE_MIN = 30
COLUMNS = ("ts", "provider", "account", "kind", "name", "used_pct", "window_min", "resets_at", "amount", "source")


def read_all():
    procs = {p.stem.removeprefix("usage_"): subprocess.Popen([sys.executable, "-I", str(p)], stdout=subprocess.PIPE,
                                                            stderr=subprocess.DEVNULL, text=True)
             for p in sorted(HERE.glob("usage_*.py"))}
    rows = []
    for name, proc in procs.items():
        try:
            out, _ = proc.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            proc.kill()
            print(f"agents usage: {name} adapter timed out after 30 s", file=sys.stderr)
            continue
        for line in out.splitlines():
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue
    return rows


def record(db, rows):
    db.execute(f"CREATE TABLE IF NOT EXISTS usage({', '.join(c + (' REAL' if c in ('used_pct', 'amount') else ' INTEGER' if c == 'window_min' else ' TEXT') for c in COLUMNS)}) STRICT")
    db.execute("CREATE INDEX IF NOT EXISTS usage_latest ON usage(provider, account, kind, name, ts)")
    db.executemany(f"INSERT INTO usage({', '.join(COLUMNS)}) VALUES ({', '.join('?' * len(COLUMNS))})",
                   [tuple(r.get(c) for c in COLUMNS) for r in rows])
    db.commit()


def latest(db):
    if not db.execute("SELECT 1 FROM sqlite_master WHERE name = 'usage'").fetchone():
        return []
    db.row_factory = sqlite3.Row
    return [dict(r) for r in db.execute(
        "SELECT * FROM usage u WHERE ts = (SELECT max(ts) FROM usage WHERE provider = u.provider AND account = u.account"
        " AND kind = u.kind AND name = u.name) ORDER BY provider, account, kind DESC, window_min, name")]


def age_min(ts, now):
    return (now - datetime.fromisoformat(ts.replace("Z", "+00:00"))).total_seconds() / 60 if ts else None


def until(ts, now):
    if not ts:
        return "-"
    minutes = int((datetime.fromisoformat(ts.replace("Z", "+00:00")) - now).total_seconds() // 60)
    return f"{minutes // 1440}d{minutes % 1440 // 60}h" if minutes >= 1440 else f"{minutes // 60}h{minutes % 60:02d}m"


def main(argv):
    db = sqlite3.connect(DB, timeout=10)
    if "--refresh" in argv:
        record(db, read_all())
    now = datetime.now(timezone.utc)
    rows = latest(db)
    for r in rows:
        r["stale"] = (age_min(r["ts"], now) or STALE_MIN + 1) > STALE_MIN
    if "--json" in argv:
        print(json.dumps(rows))
        return 0
    if not rows:
        print("agents usage: no snapshot yet; run `agents usage --refresh`")
        return 1
    for (provider, account), group in sorted({(r["provider"], r["account"]): None for r in rows}.items()):
        mine = [r for r in rows if (r["provider"], r["account"]) == (provider, account)]
        age = min(age_min(r["ts"], now) for r in mine)
        windows = [f"{r['name']} {r['used_pct']:.0f}% used, resets in {until(r['resets_at'], now)}"
                   for r in mine if r["kind"] == "window" and r["used_pct"] is not None]
        billing = [f"{r['name']}={r['amount']:g}" for r in mine if r["kind"] in ("billing", "grant") and r["amount"] is not None]
        print(f"{provider} {account} ({age:.0f} min ago{', STALE' if age > STALE_MIN else ''}): "
              + "; ".join(windows) + (f" | {', '.join(billing)}" if billing else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
