"""Print recently observed model changes from the shared threads database."""

import argparse
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import sqlite3


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, default=7)
    args = parser.parse_args()
    if args.days <= 0:
        parser.error("days must be positive")
    path = Path(os.environ.get("THREADS_DB") or Path.home() / ".local/state/threads/threads.db")
    rows = []
    if path.exists():
        with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as db:
            if db.execute("SELECT 1 FROM sqlite_master WHERE name='model_events'").fetchone():
                cutoff = (datetime.now(timezone.utc) - timedelta(days=args.days)).strftime("%Y-%m-%dT%H:%M:%SZ")
                rows = db.execute("SELECT ts,model,kind,at,p,source,detail FROM model_events WHERE ts>=? ORDER BY ts DESC,rowid DESC", (cutoff,)).fetchall()
    print(f"Model news: last {args.days} days")
    for label, kinds in (("Shipped", ("released",)), ("Expected", ("expected", "market"))):
        print(label + ":")
        selected = [r for r in rows if r[2] in kinds]
        if not selected:
            print("  none")
        for ts, model, kind, at, p, source, raw in selected:
            detail = json.loads(raw)
            when = ("market closes " if kind == "market" else "source date ") + (at or "unknown")
            market = f"; market probability {p:.0%}" if p is not None else ""
            summary = detail.get("digest") or detail.get("title", model)
            print(f"  {model}: {summary}")
            print(f"    {when}{market}; source {source} ({detail.get('url', 'unknown')}); observed {ts}")


if __name__ == "__main__":
    main()
