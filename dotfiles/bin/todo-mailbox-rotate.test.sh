#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
target="$repo/dotfiles/bin/todo-mailbox-rotate"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/todo-mailbox-rotate-test.XXXXXX")
trap 'rm -rf "${scratch:?}"' EXIT
mailbox="$scratch/agent-coord.md"
archive="$scratch/archive"

printf '%s\n' \
  '# preserved board heading' \
  '- [2026-08-21T10:00:00+08:00][C-SET][alice -> bob][OPEN] request' \
  '- [2026-08-21T10:01:00+08:00][C-SET][bob -> alice][ACK] accepted' \
  '- [2026-08-21T10:02:00+08:00][C-SET][alice -> bob][UPDATE] checkpoint' \
  '- [2026-08-21T10:03:00+08:00][C-SET][bob -> alice][DONE] landed' \
  '- [2026-08-21T10:04:00+08:00][C-LIVE][carol -> dave][OPEN] awaiting receipt' \
  '- [2026-08-21T10:05:00+08:00][C-MALFORMED][erin -> frank][OPEN] keep this' \
  '- [2026-08-21T10:06:00+08:00][C-MALFORMED][erin -> frank][TRANSFER] keep this too' \
  '- [2026-08-21T10:07:00+08:00][C-NO-ACK][gina -> hank][OPEN] request' \
  '- [2026-08-21T10:08:00+08:00][C-NO-ACK][hank -> gina][DONE] unsafe terminal' \
  '- [2026-08-21T10:09:00+08:00][C-UNKNOWN] malformed but preserved' \
  >"$mailbox"
cp "$mailbox" "$scratch/original"

"$target" --json "$mailbox" "$archive" >"$scratch/receipt.json"
python3 - "$scratch/original" "$mailbox" "$archive" "$scratch/receipt.json" <<'PY'
import hashlib
import json
import pathlib
import sys

original = pathlib.Path(sys.argv[1]).read_bytes()
mailbox = pathlib.Path(sys.argv[2])
archive = pathlib.Path(sys.argv[3])
receipt = json.loads(pathlib.Path(sys.argv[4]).read_text())
selected = b"".join(line for line in original.splitlines(keepends=True) if b"[C-SET]" in line)
active = original.replace(selected, b"")
digest = hashlib.sha256(selected).hexdigest()

assert mailbox.read_bytes() == active
assert (archive / "claims" / f"{digest}.md").read_bytes() == selected
assert receipt["source_sha256"] == hashlib.sha256(original).hexdigest()
assert receipt["active_sha256"] == hashlib.sha256(active).hexdigest()
assert receipt["archived"] == [{
    "claim": "C-SET",
    "sha256": digest,
    "bytes": len(selected),
    "lines": [2, 3, 4, 5],
    "path": f"claims/{digest}.md",
}]
assert {entry["claim"] for entry in receipt["preserved"]} == {"C-LIVE", "C-MALFORMED", "C-NO-ACK", "C-UNKNOWN"}
assert len(receipt["malformed"]) == 2
receipt_path = pathlib.Path(receipt["receipt"]["path"])
assert receipt_path.exists()
assert receipt_path.name == f"{receipt['receipt']['sha256']}.json"
PY

cp "$mailbox" "$scratch/after-first"
"$target" --json "$mailbox" "$archive" >"$scratch/second.json"
cmp "$mailbox" "$scratch/after-first"
python3 - "$scratch/second.json" <<'PY'
import json
import pathlib
import sys

receipt = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert receipt["archived"] == []
PY

collision_mailbox="$scratch/collision.md"
collision_archive="$scratch/collision-archive"
printf '%s\n' \
  '- [2026-08-21T12:00:00+08:00][C-COLLIDE][ivy -> jules][OPEN] request' \
  '- [2026-08-21T12:01:00+08:00][C-COLLIDE][jules -> ivy][ACK] accepted' \
  '- [2026-08-21T12:02:00+08:00][C-COLLIDE][jules -> ivy][DONE] result' \
  >"$collision_mailbox"
cp "$collision_mailbox" "$scratch/collision-original"
mkdir -p "$collision_archive/claims"
digest=$(sha256sum "$collision_mailbox" | awk '{print $1}')
printf 'different bytes\n' >"$collision_archive/claims/$digest.md"
set +e
"$target" "$collision_mailbox" "$collision_archive" >"$scratch/collision.out" 2>"$scratch/collision.err"
status=$?
set -e
[ "$status" -eq 2 ]
grep -Fq 'content-address collision' "$scratch/collision.err"
cmp "$collision_mailbox" "$scratch/collision-original"

printf 'todo-mailbox-rotate tests: PASS (strict settlement, byte preservation, atomic receipts)\n'
