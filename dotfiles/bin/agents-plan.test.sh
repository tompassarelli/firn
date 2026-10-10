#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
agents="$repo/dotfiles/bin/agents"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/agents-plan-test.XXXXXX")"
trap 'rm -rf "${scratch:?}"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$scratch/bin"
cat >"$scratch/bin/claude" <<'SH'
#!/usr/bin/env bash
[[ "$*" == "auth status" ]] || exit 97
printf '{"loggedIn": %s}\n' "${FAKE_CLAUDE_IN:-true}"
SH
cat >"$scratch/bin/codex" <<'SH'
#!/usr/bin/env bash
[[ "$*" == "login status" ]] || exit 97
if [[ "${FAKE_CODEX_IN:-true}" == true ]]; then
  printf 'Logged in using ChatGPT\n' >&2
else
  printf 'Not logged in\n' >&2
  exit 1
fi
SH
chmod +x "$scratch/bin/claude" "$scratch/bin/codex"
export AGENTS_CLAUDE_BIN="$scratch/bin/claude" AGENTS_CODEX_BIN="$scratch/bin/codex"

# Tom's live file parses and resolves.
"$agents" plan | grep -q '^  0-' || fail "live orchestration.toml did not resolve"

# Fixture with Tom's 9 Oct table, so editing the live file never breaks this.
fixture() {
  cat <<TOML
mode = "split"
posture = "balanced"
[claude]
${1:-}
[tiers."claude:haiku"]
model = "claude-haiku-5-5"
effort = "high"
agent = "worker-haiku"
role = "mechanical"
start = [0, 0, 0]
[tiers."codex:sol-medium"]
model = "gpt-6.1-sol"
effort = "medium"
role = "middle"
start = [30, 20, 20]
[tiers."codex:sol-high"]
model = "gpt-6.1-sol"
effort = "high"
role = "middle, harder half"
start = [55, 50, 40]
[tiers."claude:opus-medium"]
model = "claude-opus-5-5"
effort = "medium"
agent = "worker"
role = "top"
start = [85, 75, 50]
[tiers."claude:opus-high"]
model = "claude-opus-5-5"
effort = "high"
agent = "worker-high"
role = "planning and architecture"
start = [98, 95, 90]
[on_request."codex:astra"]
model = "gpt-6-astra"
effort = "xhigh"
TOML
}
export AGENTS_ORCHESTRATION="$scratch/orchestration.toml"
fixture >"$AGENTS_ORCHESTRATION"
bands() { grep '^  [0-9]' <<<"$1"; }

# Balanced with both providers is Tom's table.
out="$("$agents" plan)"
expected='  0-20 mechanical: claude-haiku-5-5 high (worker-haiku)
  20-50 middle: gpt-6.1-sol medium
  50-75 middle, harder half: gpt-6.1-sol high
  75-95 top: claude-opus-5-5 medium (worker)
  95-100 planning and architecture: claude-opus-5-5 high (worker-high)'
[[ "$(bands "$out")" == "$expected" ]] || fail "balanced plan: $out"
grep -Fxq 'escalation: claude-haiku-5-5 high (worker-haiku), gpt-6.1-sol medium, gpt-6.1-sol high, claude-opus-5-5 medium (worker), claude-opus-5-5 high (worker-high), then recommend to Tom' <<<"$out" ||
  fail "balanced escalation: $out"

# Performance widens Opus medium down to the 50th percentile.
out="$("$agents" plan --posture performance)"
grep -Fxq '  50-90 top: claude-opus-5-5 medium (worker)' <<<"$out" || fail "performance plan: $out"

# Claude in efficiency gives SOL work up to the 85th; planning stays on Opus high.
fixture 'posture = "efficiency"' >"$AGENTS_ORCHESTRATION"
out="$("$agents" plan)"
grep -Fxq 'mode: split, posture: balanced (claude efficiency)' <<<"$out" || fail "override header: $out"
grep -Fxq '  50-85 middle, harder half: gpt-6.1-sol high' <<<"$out" || fail "claude efficiency: $out"
grep -Fxq '  98-100 planning and architecture: claude-opus-5-5 high (worker-high)' <<<"$out" ||
  fail "claude efficiency planning: $out"
fixture >"$AGENTS_ORCHESTRATION"

# Codex-only: every band is SOL, the dropped ranges say why, and escalation ends at Tom.
out="$("$agents" plan --mode codex-only)"
expected='  0-50 middle: gpt-6.1-sol medium (takes claude:haiku 0-20: provider dropped)
  50-100 middle, harder half: gpt-6.1-sol high (takes claude:opus-medium 75-95, claude:opus-high 95-100: provider dropped)'
[[ "$(bands "$out")" == "$expected" ]] || fail "codex-only plan: $out"
grep -Fxq 'escalation: gpt-6.1-sol medium, gpt-6.1-sol high, then recommend to Tom' <<<"$out" ||
  fail "codex-only escalation: $out"

# Claude-only resolves, and a signed-out Codex gives the same bands.
out="$("$agents" plan --mode claude-only)"
grep -Fxq '  0-20 mechanical: claude-haiku-5-5 high (worker-haiku)' <<<"$out" || fail "claude-only keeps Haiku at mechanical: $out"
grep -Fq '  20-95 top: claude-opus-5-5 medium (worker)' <<<"$out" || fail "claude-only gives SOL's middle to Opus medium, not Haiku: $out"
! grep -q gpt- <<<"$out" || fail "claude-only plan names a SOL tier"
signed_out="$(FAKE_CODEX_IN=false "$agents" plan)"
grep -Fxq 'codex: dropped, not signed in (codex login status)' <<<"$signed_out" || fail "signed-out codex: $signed_out"
[[ "$(bands "$signed_out")" == "$(bands "$out")" ]] || fail "signed-out codex differs from claude-only"

# Neither provider usable: only Tom is left.
if out="$(FAKE_CODEX_IN=false FAKE_CLAUDE_IN=false "$agents" plan)"; then
  fail "plan succeeded with no provider"
fi
grep -Fq 'recommend to Tom' <<<"$out" || fail "no-provider plan: $out"

# On-request tiers never appear.
for args in "" "--posture performance" "--posture efficiency" "--mode codex-only"; do
  # shellcheck disable=SC2086
  ! "$agents" plan $args | grep -q astra || fail "plan $args names Astra"
done

# The four §4 scenarios replay through --at with routing.test.sh's expected states, tiers and fast flags.
scenarios="$repo/dotfiles/agents/lib/routing-scenarios"
for s in burn conserve new-model deadline; do
  out="$("$agents" plan --at "$scenarios/$s.json" 2>&1)" || fail "replay $s: $out"
done
out="$("$agents" plan --at "$scenarios/burn.json")"
grep -Fq 'account codex: state burn, slack +36.0, week resets in 4h00m, fast on' <<<"$out" || fail "burn replay account: $out"
grep -Fxq 'box b1 (muove feature d70): codex:sol-high, fast on' <<<"$out" || fail "burn replay box: $out"
grep -Fxq 'project muove: priority 1, bar solid, target 14 Oct, urgency 1.00' <<<"$out" || fail "burn replay project: $out"
out="$("$agents" plan --at "$scenarios/burn.json" --state codex=conserve)"
grep -Fq 'account codex: state conserve (--state)' <<<"$out" || fail "--state on replay: $out"

# Live: an expired override prints as expired and is ignored; --state overrides one account for one run.
export THREADS_DB="$scratch/threads.db"
python3 -I - "$THREADS_DB" <<'PY'
import sqlite3, sys
from datetime import datetime, timedelta, timezone
now = datetime.now(timezone.utc)
iso = lambda d: d.strftime("%Y-%m-%dT%H:%M:%SZ")
db = sqlite3.connect(sys.argv[1])
db.execute("CREATE TABLE usage(ts TEXT, provider TEXT, account TEXT, kind TEXT, name TEXT, used_pct REAL, window_min INTEGER, resets_at TEXT, amount REAL, source TEXT)")
rows = [("claude", "c1", "window", "session", 10.0, 300, iso(now + timedelta(hours=4)), None),
        ("claude", "c1", "window", "weekly_all", 30.0, 10080, iso(now + timedelta(days=4)), None),
        ("codex", "x1", "window", "week", 30.0, 10080, iso(now + timedelta(days=4)), None),
        ("codex", "x1", "billing", "hasCredits", None, None, None, 0.0)]
db.executemany("INSERT INTO usage VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'fixture')", [(iso(now), *r) for r in rows])
db.commit()
PY
cat >"$AGENTS_ORCHESTRATION" <<'TOML'
mode = "split"
posture = "balanced"
usage = { burn_slack = 15, conserve_slack = -5, horizon_h = 36, money_ceiling = 95, fast_floor = 10, stale_min = 30, urgent = 1.2, shift = 15, late = 1.5 }
[projects.muove]
priority = 1
bar = "critical"
[accounts.codex]
state = "burn"
until = "2026-01-01T00:00Z"
[tiers."claude:haiku"]
model = "claude-haiku-5-5"
effort = "high"
start = [0, 0, 0]
[tiers."codex:sol-medium"]
model = "gpt-6.1-sol"
effort = "medium"
start = [30, 20, 20]
TOML
out="$("$agents" plan)"
grep -Fxq 'override codex burn until 2026-01-01T00:00Z: expired, ignored' <<<"$out" || fail "expired override: $out"
grep -Eq '^account codex: state (even|conserve), ' <<<"$out" || fail "expired override applied: $out"
grep -Fxq 'project muove: priority 1, bar critical, no target' <<<"$out" || fail "project line: $out"
base_claude="$(grep '^account claude:' <<<"$out")"
out="$("$agents" plan --state codex=burn)"
grep -Fq 'account codex: state burn (--state), ' <<<"$out" || fail "--state codex=burn: $out"
[[ "$(grep '^account claude:' <<<"$out")" == "$base_claude" ]] || fail "--state codex changed claude: $out"

printf 'ok: agents plan derives bands from tier starts, posture and sign-ins; account states from usage and overrides; scenarios replay\n'
