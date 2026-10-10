"""Account and project lines for `agents plan`: build routing.py's ctx from orchestration.toml, the catalog's
[accounts.*] billing and the live usage snapshot (or a scenario file), then let routing.py decide."""

import math
import sqlite3
from datetime import datetime, timedelta, timezone

import routing

MODES = ("standard", "fast", "ultrafast", "overflow")
FAR = "9999-12-31T00:00Z"


def ts(s):
    d = datetime.fromisoformat(s.replace("Z", "+00:00"))
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def window_key(r):
    if r["window_min"] == 300:
        return "5h"
    if r["name"] in ("week", "weekly_all"):
        return "week"
    return None if "/" in r["name"] else r["name"]


def beta(db, r, now):
    start = ts(r["resets_at"]) - timedelta(minutes=r["window_min"])
    since = max(start, now - timedelta(hours=24))
    if since == start:
        hours = (ts(r["ts"]) - start).total_seconds() / 3600
        return r["used_pct"] / hours if hours > 0 else 0.0
    old = db and db.execute(
        "SELECT ts, used_pct FROM usage WHERE provider = ? AND account = ? AND name = ? AND resets_at = ? AND ts >= ?"
        " ORDER BY ts LIMIT 1", (r["provider"], r["account"], r["name"], r["resets_at"],
                                 since.strftime("%Y-%m-%dT%H:%M:%SZ"))).fetchone()
    hours = old and (ts(r["ts"]) - ts(old[0])).total_seconds() / 3600
    if not old or hours < 1:
        hours = (ts(r["ts"]) - start).total_seconds() / 3600
        return r["used_pct"] / hours if hours > 0 else 0.0
    return max(r["used_pct"] - old[1], 0.0) / hours


def accounts_from(rows, db, now):
    accounts = {}
    for r in sorted(rows, key=lambda r: r["ts"], reverse=True):
        a = accounts.setdefault(r["provider"], {"id": r["account"], "windows": {}, "grants": [], "hasCredits": False,
                                                "extra_usage": False, "spend": False, "age_min": None, "resets": {}})
        if a["id"] != r["account"]:
            continue
        age = (now - ts(r["ts"])).total_seconds() / 60
        a["age_min"] = age if a["age_min"] is None else max(a["age_min"], age)
        if r["kind"] == "window" and r["used_pct"] is not None and r["resets_at"]:
            k = window_key(r)
            if k and k not in a["windows"]:
                a["windows"][k] = {"headroom": 100 - r["used_pct"], "beta": beta(db, r, now),
                                   "reset_in": max((ts(r["resets_at"]) - now).total_seconds() / 3600, 0.0)}
                a["resets"][k] = r["resets_at"]
        elif r["kind"] == "billing" and r["name"] in ("hasCredits", "extra_usage", "spend"):
            a[r["name"]] = bool(r["amount"])
    return accounts


def apply_overrides(ctx, cfg_accounts, cli_states):
    notes = []
    for name, o in (cfg_accounts or {}).items():
        acct = ctx["accounts"].get(name)
        if acct is None or "state" not in o:
            continue
        until = str(o.get("until") or acct.get("resets", {}).get("week") or "") or None
        if until is None or ctx["now"] >= ts(until):
            notes.append(f"override {name} {o['state']} until {until or 'unset'}: expired, ignored")
            acct["override"] = None
        else:
            acct["override"] = {"state": o["state"], "until": until}
            acct["override_from"] = f"orchestration.toml until {until}"
    for name, s in cli_states.items():
        if name not in ctx["accounts"]:
            raise ValueError(f"--state {name}={s}: no usage snapshot for {name}")
        ctx["accounts"][name]["override"] = {"state": s, "until": FAR}
        ctx["accounts"][name]["override_from"] = "--state"
    return notes


def live_ctx(cfg, catalog, rows, db, now, tiers):
    billing = {n: {m: v for m, v in a.items() if m in MODES} for n, a in catalog.get("accounts", {}).items()}
    projects = {}
    for name, p in cfg.get("projects", {}).items():
        projects[name] = {**p, "bar": p.get("bar", "solid"), "u": 1.0, "unmeasured": "target" in p}
    ts_tiers = [{"key": k, "model": t["model"], "effort": t["effort"], "rank": i, "start": t["start"]}
                for i, (k, t) in enumerate(tiers.items())]
    return {"now": now, "usage": cfg["usage"], "tiers": ts_tiers, "billing": billing, "lease": False,
            "accounts": accounts_from(rows, db, now), "projects": projects, "boxes": []}


def until(hours):
    m = int(hours * 60)
    return f"{m // 1440}d{m % 1440 // 60}h" if m >= 1440 else f"{m // 60}h{m % 60:02d}m"


def account_line(ctx, name):
    acct, usage = ctx["accounts"][name], ctx["usage"]
    s = routing.state(acct, usage, ctx["now"])
    terms = {k: w["headroom"] - w["beta"] * w["reset_in"] for k, w in acct["windows"].items()}
    bind = min(terms, key=terms.get) if terms else None
    reset = f"{bind} resets in {until(acct['windows'][bind]['reset_in'])}" if bind else "no window"
    src = acct.get("override_from") if acct.get("override") and ctx["now"] < ts(acct["override"]["until"]) else None
    money = [m for m in MODES if routing.billing(ctx, name, m) == "money"]
    money += [f for f in ("hasCredits", "extra_usage", "spend") if acct.get(f)]
    stale = " STALE" if routing.stale(acct, usage) else ""
    p = routing.price(ctx, name)
    return (f"account {name}{stale}: state {s}" + (f" ({src})" if src else "")
            + f", slack {routing.slack(acct):+.1f}, {reset}, fast {'on' if routing.fast(ctx, name, 1.0) else 'off'}, "
            + f"price {'money' if p == math.inf else p}, money: {', '.join(money) or 'none'}")


def project_line(name, p):
    target = p.get("target")
    if target is None:
        urgency = "no target"
    elif "u" in p and not p.get("unmeasured"):
        urgency = f"target {target}, urgency {p['u']:.2f}"
    else:
        urgency = f"target {target}, urgency unmeasured"
    share = f", share {p['share']}%" if "share" in p else ""
    return f"project {name}: priority {p.get('priority', '-')}, bar {p['bar']}{share}, {urgency}"


def lines(ctx, result=None):
    out = [account_line(ctx, n) for n in sorted(ctx["accounts"])]
    projects = sorted(ctx["projects"].items(), key=lambda kv: kv[1].get("priority", math.inf))
    out += [project_line(n, p) for n, p in projects]
    if result:
        for box in ctx["boxes"]:
            b = result["boxes"][box["id"]]
            what = b["tier"] or (f"wait for {b['wait']}" if b["wait"] else "none")
            tag = " (explore)" if b["explore"] else ""
            out.append(f"box {box['id']} ({box['project']} {box['category']} d{box['difficulty']}): {what}{tag}, "
                       f"fast {'on' if b['fast'] else 'off'}")
        out += ["explore: " + ", ".join(result["explore"])] if result["explore"] else []
        out += [f"no explore and no new lead: {k} (successor due)" for k in result["held"]]
        out += result["needs"]
    return out


def replay(ctx, cli_states):
    ctx = dict(ctx, now=ts(ctx["now"]))
    for name, a in ctx["accounts"].items():
        if a.get("override"):
            a["override_from"] = "scenario"
    apply_overrides(ctx, {}, cli_states)
    result = routing.plan(ctx)
    return lines(ctx, result), routing.divergence(result, ctx.get("expect", {})) if not cli_states else None


def open_db(path):
    try:
        return sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)
    except sqlite3.Error:
        return None
