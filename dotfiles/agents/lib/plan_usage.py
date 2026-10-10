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
    """One account per provider is named by the provider; several (claude a and b) are named provider:account."""
    ids = {}
    for r in rows:
        ids.setdefault(r["provider"], set()).add(r["account"])
    accounts = {}
    for r in sorted(rows, key=lambda r: r["ts"], reverse=True):
        key = r["provider"] if len(ids[r["provider"]]) == 1 else f"{r['provider']}:{r['account']}"
        a = accounts.setdefault(key, {"id": r["account"], "windows": {}, "grants": [], "hasCredits": False,
                                      "extra_usage": False, "spend": False, "age_min": None, "resets": {}})
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
    for name, o in ((n, o) for p, o in (cfg_accounts or {}).items() for n in ctx["accounts"]
                    if n == p or n.split(":", 1)[0] == p):
        acct = ctx["accounts"][name]
        if "state" not in o:
            continue
        until = str(o.get("until") or acct.get("resets", {}).get("week") or "") or None
        if until is None or ctx["now"] >= ts(until):
            notes.append(f"override {name} {o['state']} until {until or 'unset'}: expired, ignored")
            acct["override"] = None
        else:
            acct["override"] = {"state": o["state"], "until": until}
            acct["override_from"] = f"orchestration.toml until {until}"
    for arg, s in cli_states.items():
        names = [n for n in ctx["accounts"] if n == arg or n.split(":", 1)[0] == arg]
        if not names:
            raise ValueError(f"--state {arg}={s}: no usage snapshot for {arg}")
        for name in names:
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


def provider_of_tier(tier):
    return "gemini" if tier.startswith("gemini") else "codex" if tier.startswith("gpt-") else "claude"


def promo_lines(catalog, db, now, days=7):
    """A Needs Tom line for each promotion ending within `days`: does the account earn its full price, i.e. is its
    share of the last 30 days' runs at least its share of the plans' monthly spend at full price."""
    accounts = catalog.get("accounts", {})
    full = {p: a["monthly_price"] * max(len(a.get("machines", {})), 1) for p, a in accounts.items() if "monthly_price" in a}
    out = []
    for p, a in accounts.items():
        end = a.get("promo_end")
        left = end and (datetime.combine(end, datetime.min.time(), timezone.utc) - now).days
        if left is None or not 0 <= left <= days:
            continue
        counts = {}
        for (tier,) in (db.execute("SELECT tier FROM runs WHERE started >= ?",
                                   ((now - timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ"),)) if db else []):
            counts[provider_of_tier(tier or "")] = counts.get(provider_of_tier(tier or ""), 0) + 1
        runs, total = counts.get(p, 0), sum(counts.values())
        run_share, cost_share = (100 * runs / total if total else 0.0), 100 * full.get(p, 0) / (sum(full.values()) or 1)
        verdict = "earned its full price" if run_share >= cost_share else "did not earn its full price"
        out.append(f"Needs Tom: {p} promotion (USD {a['promo_price']}/month) ends {end} ({left} days, "
                   f"{'confirmed' if a.get('promo_end_confirmed') else 'unconfirmed'}); at USD {a['monthly_price']}/month it is "
                   f"{cost_share:.1f}% of plan spend and ran {run_share:.1f}% of runs in 30 days ({runs} of {total}): {verdict}")
    return out


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
            what = b["tier"] and b["tier"] + (f" on {b['account']}" if ":" in b["account"] else "")
            what = what or (f"wait for {b['wait']}" if b["wait"] else "none")
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
