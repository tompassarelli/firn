#!/usr/bin/env bash
# Behavioural tests for dotfiles/bin/north-session-resolve. Runs against a
# synthetic HOME, so no real account home is read or resolved.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVE="$ROOT/dotfiles/bin/north-session-resolve"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture:?}"' EXIT

export HOME="$fixture"
fail() { printf 'north-session-resolve.test.sh:%s: %s\n' "${BASH_LINENO[0]}" "$1" >&2; exit 1; }

ASID=11111111-aaaa-bbbb-cccc-222222222222
OSID=33333333-dddd-eeee-ffff-444444444444
base="$HOME/.local/state/north/accounts"
adir="$base/anthropic/acct/projects/-home-tom-code-demo"
odir="$base/openai/acct/sessions/2026/08/12"
mkdir -p "$adir" "$odir"

atrans="$adir/$ASID.jsonl"
otrans="$odir/rollout-2026-08-12T09-00-00-$OSID.jsonl"
printf '{"type":"user","sessionId":"%s","message":{"role":"user","content":"hello"}}\n' \
  "$ASID" >"$atrans"
printf '{"type":"session_meta","payload":{"id":"%s","cwd":"/synthetic/demo"}}\n' \
  "$OSID" >"$otrans"
# padding, so the archive is not resolved out of a single tiny frame by luck
for _ in $(seq 200); do
  printf '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"padding padding padding"}]}}\n' >>"$otrans"
done

expect_home() { # <provider> <sid> <expected home>
  local out
  out="$("$RESOLVE" "$1" "$2")" || fail "$1 $2 did not resolve"
  [ "$(cut -f5 <<<"$out")" = "$3" ] ||
    fail "$1 $2 resolved to $(cut -f5 <<<"$out"), wanted $3"
}

# ---- plain transcripts resolve -------------------------------------------
expect_home anthropic "$ASID" "$base/anthropic/acct"
expect_home openai "$OSID" "$base/openai/acct"

# ---- an archived transcript resolves identically --------------------------
# `convo compress` rewrites a closed transcript as .jsonl.zst; a session must
# stay locatable afterwards, or archiving would strand it.
zstd -q --long=27 --rm "$atrans" "$otrans"
[ -f "$atrans.zst" ] && [ ! -f "$atrans" ] || fail "fixture was not archived"
expect_home anthropic "$ASID" "$base/anthropic/acct"
expect_home openai "$OSID" "$base/openai/acct"

# ---- an unknown id is still unknown --------------------------------------
if "$RESOLVE" openai 99999999-9999-9999-9999-999999999999 >/dev/null 2>&1; then
  fail "resolved a session that does not exist"
fi

# ---- an archive whose first record is not session_meta is not a match -----
mkdir -p "$base/openai/other/sessions/2026/08/12"
decoy="$base/openai/other/sessions/2026/08/12/rollout-2026-08-12T10-00-00-$OSID.jsonl"
printf '{"type":"response_item","payload":{"type":"message"}}\n' >"$decoy"
zstd -q --long=27 --rm "$decoy"
expect_home openai "$OSID" "$base/openai/acct"

echo "north-session-resolve.test.sh: all assertions passed"
