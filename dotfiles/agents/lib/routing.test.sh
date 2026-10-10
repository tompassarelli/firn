#!/usr/bin/env bash
# Money property over the catalog's tiers, then the four §4 scenarios and two Claude accounts (firn#12).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0

python3 -I - "$HERE" <<'PY' || fail=1
import itertools, math, sys, tomllib
from datetime import datetime
sys.path.insert(0, sys.argv[1])
import routing

agents = sys.argv[1].rsplit("/lib", 1)[0]
catalog = tomllib.load(open(f"{agents}/model-catalog.toml", "rb"))["models"]
bands = tomllib.load(open(f"{agents}/orchestration.toml", "rb"))["tiers"]
tiers = [{"key": k, "model": v["model"], "effort": v["effort"], "rank": i,
          "start": bands.get(k, {}).get("start", [100, 100, 100]), "runs": 5 if i % 3 == 0 else 50}
         for i, (k, v) in enumerate(catalog.items()) if "model" in v]
accounts = sorted({routing.account_of(t) for t in tiers})
usage = {"burn_slack": 15, "conserve_slack": -5, "horizon_h": 36, "money_ceiling": 95, "fast_floor": 10,
         "stale_min": 30, "urgent": 1.2, "shift": 15, "late": 1.5}
now = datetime.fromisoformat("2026-10-11T12:00Z")
MODES = ("standard", "fast", "ultrafast", "overflow")
VALUES = ("plan", "money", "blocked", None)
OVERRIDES = (None, "burn", "even", "conserve", "expired")
projects = {f"{bar}-{u}": {"bar": bar, "u": u} for bar in ("prototype", "solid", "critical") for u in (1.0, 1.6)}
shapes = (("public", 10, "any"), ("private", 60, "band"), ("client", 95, "band"), ("public", 40, "band"))
boxes = [{"id": f"{p}-{i}", "project": p, "category": shapes[(i + j) % 4][2], "difficulty": shapes[(i + j) % 4][1],
          "sensitivity": shapes[(i + j) % 4][0]} for j, p in enumerate(projects) for i in (0, 2)]
success = {f"{t['key']}|any": 100 for t in tiers}

def money(ctx, name, mode):
    a, b = ctx["accounts"][name], ctx["billing"][name]
    if a["age_min"] > usage["stale_min"] or b.get(mode) != "plan":
        return True
    used = max(100 - w["headroom"] for w in a["windows"].values())
    overflow_free = b.get("overflow") in ("plan", "blocked") and not (a["hasCredits"] or a["extra_usage"] or a["spend"])
    return used >= usage["money_ceiling"] and not overflow_free

states = decisions = picks = fasts = 0
for bill in itertools.product(("plan", "money", None), ("plan", "money", None), ("plan", None), VALUES):
    for credits, extra, stale, pct, ov in itertools.product((False, True), (False,), (False, True), (0, 94, 95, 100), (None, "burn", "conserve", "expired")):
        acct = {"windows": {"5h": {"headroom": 100 - pct, "reset_in": 2, "beta": 1}, "week": {"headroom": 100 - pct, "reset_in": 20, "beta": 0.5}},
                "grants": [], "hasCredits": credits, "extra_usage": extra, "spend": False, "age_min": 45 if stale else 5,
                "override": None if ov is None else {"state": "burn" if ov == "expired" else ov,
                                                     "until": "2026-10-11T00:00Z" if ov == "expired" else "2026-10-12T00:00Z"}}
        billing = {m: v for m, v in zip(MODES, bill) if v is not None}
        ctx = {"now": now, "usage": usage, "tiers": tiers, "success": success, "lease": True, "projects": projects,
               "accounts": {n: acct for n in accounts}, "billing": {n: billing for n in accounts}}
        states += 1
        for box in boxes:
            for slot in (False, True) if projects[box["project"]]["bar"] != "critical" else (False,):
                decisions += 1
                t = routing.choose(ctx, box, slot)["tier"]
                if t is None:
                    continue
                picks += 1
                name = routing.account_of(t)
                if money(ctx, name, "standard"):
                    print(f"FAIL choose picked money: {t['key']} box {box['id']} billing {billing} credits {credits} extra {extra} stale {stale} used {pct} override {ov}")
                    sys.exit(1)
                if routing.fast(ctx, name, projects[box["project"]]["u"]):
                    fasts += 1
                    if money(ctx, name, "fast"):
                        print(f"FAIL fast on money: {name} billing {billing} credits {credits} extra {extra} stale {stale} used {pct} override {ov}")
                        sys.exit(1)
print(f"PASS money property: {states} account states x {len(tiers)} catalog tiers x {len(boxes)} boxes with and without an explore slot; "
      f"{decisions} decisions, {picks} picks, {fasts} fast-on, 0 money")
PY

for s in burn conserve new-model deadline two-claude; do
  if out="$(python3 -I "$HERE/routing.py" scenario "$HERE/routing-scenarios/$s.json" 2>&1)"; then
    echo "PASS scenario $s"
  else
    echo "FAIL scenario $s"; echo "$out"; fail=1
  fi
done
exit "$fail"
