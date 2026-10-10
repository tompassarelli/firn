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
        "SELECT * FROM usage u WHERE rowid = (SELECT rowid FROM usage WHERE provider = u.provider AND account = u.account"
        " AND kind = u.kind AND name = u.name ORDER BY ts DESC, rowid DESC LIMIT 1)"
        " ORDER BY provider, account, kind DESC, window_min, name")]


def age_min(ts, now):
    return (now - datetime.fromisoformat(ts.replace("Z", "+00:00"))).total_seconds() / 60 if ts else None


def until(ts, now):
    if not ts:
        return "-"
    minutes = int((datetime.fromisoformat(ts.replace("Z", "+00:00")) - now).total_seconds() // 60)
    return f"{minutes // 1440}d{minutes % 1440 // 60}h" if minutes >= 1440 else f"{minutes // 60}h{minutes % 60:02d}m"


def gate_path():
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "agents/usage-gate.json"


def refusal(db, provider, cfg, catalog, now):
    """Why a new worker on this provider's account could bill money (or its usage is unknown), else None.
    routing.py decides; this only feeds it."""
    import math
    import plan_usage
    import routing
    rows = [r for r in latest(db) if r["provider"] == provider]
    ctx = plan_usage.live_ctx(cfg, catalog, rows, db, now, cfg.get("tiers", {}))
    plan_usage.apply_overrides(ctx, cfg.get("accounts"), {})
    acct = ctx["accounts"].get(provider)
    if acct is not None and routing.price(ctx, provider) != math.inf:
        return None
    if acct is None:
        why = f"no usage snapshot for {provider} could be read (`agents usage --refresh` shows why)"
    elif routing.stale(acct, ctx["usage"]):
        why = f"{provider}'s usage snapshot is {acct['age_min']:.0f} minutes old even after a refresh"
    elif routing.billing(ctx, provider, "standard") != "plan":
        why = f"the catalog bills {provider}'s standard usage as {routing.billing(ctx, provider, 'standard')}"
    else:
        live = [f for f in ("hasCredits", "extra_usage", "spend") if acct.get(f)]
        why = (f"{provider} is at {routing.used(acct):.0f}% of a plan window (ceiling {ctx['usage']['money_ceiling']}%) "
               f"and {', '.join(live) or 'its overflow'} would bill money past it")
    return (f"No: a new {provider} worker could spend money: {why}. Unknown or money-billed usage is never chosen "
            "automatically (firn#12). Use another provider's tier from `agents plan`, wait for the window to reset, or "
            "bring Tom one Needs Tom line.")


def write_gate(db, providers):
    """Record each provider's refusal (or null) in usage-gate.json, which the spawn hook reads without a subprocess."""
    import tomllib
    sys.path.insert(0, str(HERE))
    root = HERE.parent
    cfg = tomllib.load(open(os.environ.get("AGENTS_ORCHESTRATION") or root / "orchestration.toml", "rb"))
    catalog = tomllib.load(open(root / "model-catalog.toml", "rb"))
    now = datetime.now(timezone.utc)
    path = gate_path()
    try:
        verdicts = json.loads(path.read_text())
    except (OSError, ValueError):
        verdicts = {}
    for provider in providers:
        verdicts[provider] = {"ts": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "epoch": now.timestamp(), "stale_min": cfg["usage"]["stale_min"],
                              "refusal": refusal(db, provider, cfg, catalog, now)}
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(verdicts))
    tmp.replace(path)
    return verdicts


def gate(db, provider):
    """Exit 3 with the refusal when a spawn on this provider's account could bill money, 0 otherwise; refreshes the
    provider's usage first so the verdict is current."""
    record(db, [r for r in read_all() if r.get("provider") == provider])
    reason = write_gate(db, [provider])[provider]["refusal"]
    if reason:
        print(reason)
        return 3
    return 0


def fast(db, provider, domain):
    """Exit 0 printing "on" when routing turns plan-billed fast on for a new lead on this provider (burn, or an
    urgent project that is not conserving); exit 1 printing "off" otherwise. Refreshes the provider's usage first."""
    import tomllib
    sys.path.insert(0, str(HERE))
    import plan_usage
    import routing
    record(db, [r for r in read_all() if r.get("provider") == provider])
    root = HERE.parent
    cfg = tomllib.load(open(os.environ.get("AGENTS_ORCHESTRATION") or root / "orchestration.toml", "rb"))
    catalog = tomllib.load(open(root / "model-catalog.toml", "rb"))
    rows = [r for r in latest(db) if r["provider"] == provider]
    ctx = plan_usage.live_ctx(cfg, catalog, rows, db, datetime.now(timezone.utc), cfg.get("tiers", {}))
    plan_usage.apply_overrides(ctx, cfg.get("accounts"), {})
    on = routing.fast(ctx, provider, ctx["projects"].get(domain or "", {}).get("u", 1.0))
    print("on" if on else "off")
    return 0 if on else 1


def main(argv):
    db = sqlite3.connect(DB, timeout=10)
    if "--gate" in argv:
        return gate(db, argv[argv.index("--gate") + 1])
    if "--fast" in argv:
        return fast(db, argv[argv.index("--fast") + 1], argv[argv.index("--domain") + 1] if "--domain" in argv else None)
    if "--refresh" in argv:
        record(db, read_all())
        write_gate(db, sorted({r["provider"] for r in latest(db)}))
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
