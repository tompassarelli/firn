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

printf 'ok: agents plan derives bands from tier starts, posture and sign-ins\n'
