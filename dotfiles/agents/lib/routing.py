#!/usr/bin/env python3
import json
import math
import sys
from datetime import datetime

BAR = {"prototype": 60, "solid": 80, "critical": 90}
COLUMN = {"prototype": 0, "solid": 1, "critical": 2}
STATE_PRICE = {"burn": 0, "even": 1, "conserve": 3}
STATE_SHIFT = {"burn": -1, "even": 0, "conserve": 1}
# Codex fast draws included limits at 2.5x the standard rate (learn.chatgpt.com/docs/agent-configuration/speed).
FAST_RATE = 2.5


def provider(tier):
    return tier["key"].split(":", 1)[0]


def account_of(tier):
    return tier.get("account", provider(tier))


def stale(acct, usage):
    age = acct.get("age_min")
    return age is None or age > usage["stale_min"]


def used(acct):
    return max((100 - w["headroom"] for w in acct["windows"].values()), default=100)


def billing(ctx, name, mode):
    acct = ctx["accounts"].get(name)
    value = ctx["billing"].get(name, {}).get(mode)
    if acct is None or stale(acct, ctx["usage"]) or value not in ("plan", "money", "blocked"):
        return "money"
    return value


def overflow_money(ctx, name):
    acct = ctx["accounts"][name]
    live = acct.get("hasCredits") or acct.get("extra_usage") or acct.get("spend")
    return bool(live) or billing(ctx, name, "overflow") == "money"


def slack(acct):
    terms = []
    for w in acct["windows"].values():
        lapsing = sum(g["points"] for g in acct.get("grants", []) if g["expires_in"] < w["reset_in"])
        terms.append(w["headroom"] - w["beta"] * w["reset_in"] + lapsing)
    return min(terms, default=-math.inf)


def state(acct, usage, now):
    o = acct.get("override")
    if o and now < datetime.fromisoformat(o["until"]):
        return o["state"]
    s = slack(acct)
    windows = acct["windows"]
    week = windows.get("week")
    short = windows.get("5h")
    if (s >= usage["burn_slack"] and week is not None and week["reset_in"] <= usage["horizon_h"]
            and (short is None or short["headroom"] > usage["burn_slack"])):
        return "burn"
    if s <= usage["conserve_slack"] or any(w["headroom"] <= usage["fast_floor"] for w in windows.values()):
        return "conserve"
    return "even"


def price(ctx, name):
    usage = ctx["usage"]
    acct = ctx["accounts"].get(name)
    if billing(ctx, name, "standard") != "plan":
        return math.inf
    if used(acct) >= usage["money_ceiling"] and overflow_money(ctx, name):
        return math.inf
    return STATE_PRICE[state(acct, usage, ctx["now"])]


def account_state(ctx, name):
    acct = ctx["accounts"].get(name)
    return None if acct is None else state(acct, ctx["usage"], ctx["now"])


def eligible(tier, box):
    return provider(tier) != "gemini" or box["sensitivity"] == "public"


def bands(ctx, project):
    usage = ctx["usage"]
    col = COLUMN[project["bar"]]
    urgent = project["u"] >= usage["urgent"]
    starts, floor = [], -math.inf
    for t in sorted(ctx["tiers"], key=lambda t: t["rank"]):
        base = t["start"][col]
        if base >= 100:
            continue
        shift = STATE_SHIFT.get(account_state(ctx, account_of(t)), 0) * usage["shift"]
        floor = max(base + shift - (usage["shift"] if urgent else 0), floor)
        starts.append((t["key"], floor))
    return {k: (-math.inf if i == 0 else lo, starts[i + 1][1] if i + 1 < len(starts) else math.inf)
            for i, (k, lo) in enumerate(starts)}


def admit(ctx, tier, box, project, band=None):
    if not eligible(tier, box):
        return False
    rate = ctx.get("success", {}).get(f"{tier['key']}|{box['category']}")
    if rate is not None:
        return rate >= BAR[project["bar"]]
    lo, hi = (bands(ctx, project) if band is None else band).get(tier["key"], (math.inf, math.inf))
    return lo <= box["difficulty"] < hi


def successor_soon(tier):
    s = tier.get("successor")
    return bool(s) and s["eta_days"] <= 7 and s["p"] >= 0.6


def explorable(ctx, tier, box, project):
    return (project["bar"] != "critical" and tier.get("runs", math.inf) < 10 and not successor_soon(tier)
            and eligible(tier, box) and account_state(ctx, account_of(tier)) != "conserve")


def choose(ctx, box, explore_slot=False):
    project = ctx["projects"][box["project"]]
    if box.get("local") and not ctx.get("lease"):
        return {"tier": None, "wait": "capacity lease"}
    prices = {n: price(ctx, n) for n in {account_of(t) for t in ctx["tiers"]}}
    priced = [(prices[account_of(t)], t["rank"], t) for t in ctx["tiers"]]
    if explore_slot:
        pool = [(p, r, t) for p, r, t in priced if p != math.inf and explorable(ctx, t, box, project)]
        if pool:
            return {"tier": min(pool, key=lambda x: x[1])[2], "explore": True}
    band = bands(ctx, project)
    admitted = [(p, r, t) for p, r, t in priced if admit(ctx, t, box, project, band)]
    open_ = [x for x in admitted if x[0] != math.inf]
    if not open_:
        return {"tier": None, "needs": f"Needs Tom: no plan-billed tier admits {box['id']} ({box['project']}, {box['category']} d{box['difficulty']} {project['bar']})"}
    tier = min(open_, key=lambda x: (x[0], x[1]))[2]
    out = {"tier": tier}
    name = account_of(tier)
    if (len(admitted) == 1 and project["u"] >= ctx["usage"]["late"]
            and billing(ctx, name, "fast") != "plan"):
        out["needs"] = (f"Needs Tom: {project.get('name', box['project'])} misses {project.get('target', 'its target')} at current pace; "
                        f"{provider(tier).capitalize()} fast would bill usage credits")
    return out


def fast(ctx, name, u):
    usage = ctx["usage"]
    acct = ctx["accounts"].get(name)
    if acct is None or billing(ctx, name, "fast") != "plan" or price(ctx, name) == math.inf:
        return False
    s = state(acct, usage, ctx["now"])
    if not (s == "burn" or (u >= usage["urgent"] and s != "conserve")):
        return False
    return min(w["headroom"] - FAST_RATE * w["beta"] * w["reset_in"] for w in acct["windows"].values()) >= usage["fast_floor"]


def plan(ctx):
    ctx = dict(ctx, now=datetime.fromisoformat(ctx["now"]) if isinstance(ctx["now"], str) else ctx["now"])
    accounts = {n: {"state": state(a, ctx["usage"], ctx["now"]), "slack": slack(a), "price": price(ctx, n)}
                for n, a in ctx["accounts"].items()}
    boxes, needs, slot = {}, [], 0
    for box in ctx["boxes"]:
        project = ctx["projects"][box["project"]]
        explore_slot = False
        if project["bar"] != "critical":
            explore_slot = slot % 5 == 0
            slot += 1
        r = choose(ctx, box, explore_slot)
        t = r["tier"]
        boxes[box["id"]] = {"tier": t and t["key"], "explore": r.get("explore", False), "wait": r.get("wait"),
                            "fast": bool(t) and fast(ctx, account_of(t), project["u"])}
        if r.get("needs"):
            needs.append(r["needs"])
    explore = [t["key"] for t in ctx["tiers"] if t.get("runs", math.inf) < 10 and not successor_soon(t)]
    held = [t["key"] for t in ctx["tiers"] if successor_soon(t)]
    return {"accounts": accounts, "boxes": boxes, "explore": explore, "held": held, "needs": needs}


def render(ctx, result):
    lines = []
    for n, a in result["accounts"].items():
        p = "inf" if a["price"] == math.inf else str(a["price"])
        lines.append(f"account {n}: state {a['state']}, slack {a['slack']:+.1f}, price {p}")
    for box in ctx["boxes"]:
        b = result["boxes"][box["id"]]
        what = b["tier"] or (f"wait for {b['wait']}" if b["wait"] else "none")
        tag = " (explore)" if b["explore"] else ""
        lines.append(f"box {box['id']} ({box['project']} {box['category']} d{box['difficulty']}): {what}{tag}, fast {'on' if b['fast'] else 'off'}")
    if result["explore"]:
        lines.append("explore: " + ", ".join(result["explore"]))
    for k in result["held"]:
        lines.append(f"no explore and no new lead: {k} (successor due)")
    lines.extend(result["needs"])
    return "\n".join(lines)


def divergence(result, expect):
    for n, s in expect.get("states", {}).items():
        if result["accounts"][n]["state"] != s:
            return f"account {n}: state {result['accounts'][n]['state']}, expected {s}"
    for b, t in expect.get("tiers", {}).items():
        if result["boxes"][b]["tier"] != t:
            return f"box {b}: tier {result['boxes'][b]['tier']}, expected {t}"
    for b, f in expect.get("fast", {}).items():
        if result["boxes"][b]["fast"] != f:
            return f"box {b}: fast {result['boxes'][b]['fast']}, expected {f}"
    for k in ("explore", "held", "needs"):
        if k in expect and result[k] != expect[k]:
            return f"{k}: {result[k]}, expected {expect[k]}"
    return None


def main(argv):
    if len(argv) != 3 or argv[1] != "scenario":
        print("usage: routing.py scenario FILE.json", file=sys.stderr)
        return 2
    with open(argv[2]) as f:
        ctx = json.load(f)
    result = plan(ctx)
    print(render(ctx, result))
    bad = "expect" in ctx and divergence(result, ctx["expect"])
    if bad:
        print(f"MISMATCH {bad}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
