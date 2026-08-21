#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
target="$repo/dotfiles/bin/todo-mailbox-status"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/todo-mailbox-status-test.XXXXXX")
trap 'rm -rf "${scratch:?}"' EXIT
mailbox="$scratch/agent-coord.md"

printf '%s\n' \
  '# mailbox fixture' \
  '- [2026-08-21T10:00:00+08:00][C-ONE][alice -> bob][OPEN] first request' \
  '- [2026-08-21T10:01:00+08:00][C-ONE][bob -> alice][ACK] received' \
  '- [2026-08-21T10:02:00+08:00][C-ONE][alice -> bob][UPDATE] checkpoint' \
  '- [2026-08-21T10:03:00+08:00][C-TWO][carol -> dave][OPEN] needs receipt' \
  '- [2026-08-21T10:04:00+08:00][C-ONE][bob -> alice][ACK] repeated receipt' \
  '- [2026-08-21T10:05:00+08:00][C-THREE][erin -> frank][DONE] settled' \
  '- [2026-08-21T10:06:00+08:00][C-BAD][gina -> hank][TRANSFER] rejected verb' \
  '- [2026-08-21T10:07:00+08:00][C-BAD-ROUTE][gina->hank][OPEN] rejected route' \
  '- [2026-08-21T10:08:00+08:00][C-BAD-BODY][gina -> hank][OPEN]' \
  >"$mailbox"

set +e
"$target" "$mailbox" >"$scratch/human"
status=$?
set -e
[ "$status" -eq 1 ]
grep -Fqx 'messages=6 claims=3 malformed=3 open_without_ack=1 without_done=2' "$scratch/human"
grep -Fqx 'CLAIM C-ONE state=acknowledged-awaiting-done last=ACK@6 open=1 ack=2 update=1 done=0' "$scratch/human"
grep -Fqx 'CLAIM C-TWO state=open-unacknowledged last=OPEN@5 open=1 ack=0 update=0 done=0' "$scratch/human"
grep -Fqx 'CLAIM C-THREE state=done last=DONE@7 open=0 ack=0 update=0 done=1' "$scratch/human"
grep -Fqx 'OPEN-WITHOUT-ACK C-TWO' "$scratch/human"
grep -Fqx 'WITHOUT-DONE C-ONE' "$scratch/human"
grep -Fqx 'WITHOUT-DONE C-TWO' "$scratch/human"
grep -Fqx 'MALFORMED line=8 reason=verb must be one of OPEN, ACK, UPDATE, DONE' "$scratch/human"
grep -Fqx 'MALFORMED line=9 reason=route must be sender -> receiver' "$scratch/human"
grep -Fqx 'MALFORMED line=10 reason=missing message body after verb' "$scratch/human"

set +e
"$target" --json "$mailbox" >"$scratch/report.json"
status=$?
set -e
[ "$status" -eq 1 ]
python3 - "$scratch/report.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    report = json.load(source)

assert report["counts"] == {
    "valid_messages": 6,
    "claims": 3,
    "malformed_bracketed_lines": 3,
    "open_without_ack": 1,
    "nonterminal_without_done": 2,
}
assert report["open_without_ack"] == ["C-TWO"]
assert report["nonterminal_without_done"] == ["C-ONE", "C-TWO"]
claims = {claim["claim"]: claim for claim in report["claims"]}
assert claims["C-ONE"]["messages"] == {"OPEN": 1, "ACK": 2, "UPDATE": 1, "DONE": 0}
assert claims["C-TWO"]["open_without_ack"] is True
assert claims["C-THREE"]["state"] == "done"
PY

printf '%s\n' \
  '- [2026-08-21T11:00:00+08:00][C-CLEAN][ivy -> jules][OPEN] request' \
  '- [2026-08-21T11:01:00+08:00][C-CLEAN][jules -> ivy][ACK] accepted' \
  '- [2026-08-21T11:02:00+08:00][C-CLEAN][jules -> ivy][DONE] landed' \
  >"$mailbox"
"$target" "$mailbox" >"$scratch/clean"
grep -Fqx 'messages=3 claims=1 malformed=0 open_without_ack=0 without_done=0' "$scratch/clean"
grep -Fqx 'CLAIM C-CLEAN state=done last=DONE@3 open=1 ack=1 update=0 done=1' "$scratch/clean"

printf 'todo-mailbox-status tests: PASS (strict grammar, per-claim liveness, JSON)\n'
