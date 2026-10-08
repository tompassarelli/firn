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

# Tom's live file parses and resolves every band.
live="$("$agents" plan)" || fail "live orchestration.toml did not resolve"
[[ "$(grep -c '; then ' <<<"$live")" -ge 1 ]] || fail "live plan printed no bands"

# Fixture with Tom's 9 Oct bands, so editing the live file never breaks this.
export AGENTS_ORCHESTRATION="$scratch/orchestration.toml"
cat >"$AGENTS_ORCHESTRATION" <<'TOML'
mode = "split"
[tiers.claude]
haiku = { model = "claude-haiku-5-5", effort = "high", agent = "worker-haiku" }
medium = { model = "claude-opus-5-5", effort = "medium", agent = "worker" }
high = { model = "claude-opus-5-5", effort = "high", agent = "worker-high" }
[tiers.codex]
medium = { model = "gpt-6.1-sol", effort = "medium" }
high = { model = "gpt-6.1-sol", effort = "high" }
[on_request.codex]
astra = { model = "gpt-6-astra", effort = "xhigh" }
[[band]]
name = "mechanical"
tiers = ["claude:haiku"]
[[band]]
name = "middle"
tiers = ["codex:medium", "codex:high"]
[[band]]
name = "top"
tiers = ["claude:medium"]
[[band]]
name = "planning"
tiers = ["claude:high"]
TOML

bands() { grep -E '^(mechanical|middle|top|planning)' <<<"$1"; }

# Split with both providers: each band keeps its own tiers, escalating upward.
out="$("$agents" plan)"
expected='mechanical: claude-haiku-5-5 high (worker-haiku); then middle
middle: gpt-6.1-sol medium, gpt-6.1-sol high; then top
top: claude-opus-5-5 medium (worker); then planning
planning: claude-opus-5-5 high (worker-high); then recommend to Tom'
[[ "$(bands "$out")" == "$expected" ]] || fail "split plan: $out"

# Codex-only: Claude bands move to SOL, and the ladder ends at Tom.
out="$("$agents" plan --mode codex-only)"
expected='mechanical (moved to middle, claude dropped: mode is codex-only): gpt-6.1-sol medium, gpt-6.1-sol high; then recommend to Tom
middle: gpt-6.1-sol medium, gpt-6.1-sol high; then recommend to Tom
top (moved to middle, claude dropped: mode is codex-only): gpt-6.1-sol medium, gpt-6.1-sol high; then recommend to Tom
planning (moved to middle, claude dropped: mode is codex-only): gpt-6.1-sol medium, gpt-6.1-sol high; then recommend to Tom'
[[ "$(bands "$out")" == "$expected" ]] || fail "codex-only plan: $out"
! grep -q claude- <<<"$out" || fail "codex-only plan names a Claude tier"

# Claude-only: the middle band moves up to Opus medium.
out="$("$agents" plan --mode claude-only)"
grep -Fxq 'middle (moved to top, codex dropped: mode is claude-only): claude-opus-5-5 medium (worker); then planning' <<<"$out" ||
  fail "claude-only plan: $out"

# Split with Codex signed out behaves as Claude-only and says why.
out="$(FAKE_CODEX_IN=false "$agents" plan)"
grep -Fxq 'codex: dropped, not signed in (codex login status)' <<<"$out" || fail "signed-out codex: $out"
grep -Fxq 'middle (moved to top, codex dropped: not signed in (codex login status)): claude-opus-5-5 medium (worker); then planning' <<<"$out" ||
  fail "signed-out codex: $out"

# Neither provider usable: only Tom is left.
if out="$(FAKE_CODEX_IN=false FAKE_CLAUDE_IN=false "$agents" plan)"; then
  fail "plan succeeded with no provider"
fi
grep -Fq 'recommend to Tom' <<<"$out" || fail "no-provider plan: $out"

# On-request tiers never appear in any plan.
for mode in split codex-only claude-only; do
  ! "$agents" plan --mode "$mode" | grep -q astra || fail "$mode plan names Astra"
done

printf 'ok: agents plan resolves bands from orchestration.toml and sign-ins\n'
