#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
lint="$repo/dotfiles/bin/todo-lint"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/todo-lint-test.XXXXXX")
trap 'rm -rf "${scratch:?}"' EXIT

home="$scratch/home"
code="$home/code"
todo="$scratch/todo"
mkdir -p "$code/alpha" "$todo" "$todo/nested"

git init -q -b main "$code/alpha/main"
git -C "$code/alpha/main" config user.name 'todo-lint test'
git -C "$code/alpha/main" config user.email todo-lint@example.invalid
printf 'base\n' >"$code/alpha/main/base"
git -C "$code/alpha/main" add base
git -C "$code/alpha/main" commit -qm base
git -C "$code/alpha/main" worktree add -q -b lane "$code/alpha/worktrees/lane" main
git -C "$code/alpha/main" worktree add -q --detach "$code/alpha/worktrees/detached" main
git -C "$code/alpha/main" branch reaped-branch
mkdir -p "$code/alpha/worktrees/reaped"
printf 'not Markdown\n' >"$todo/runtime.log"

record() {
  local path="$1"
  shift
  printf '%s\n' "$@" >"$todo/$path"
}

record good.md \
  '+++' \
  'id = "good"' \
  'title = "Good"' \
  'shape = "thread"' \
  'life = "inactive"' \
  'updated_at = "2026-01-01T00:00:00+00:00"' \
  'owners = ["test"]' \
  '+++' \
  '' \
  'Body.'
record duplicate.md \
  '+++' \
  'id = "good"' \
  'title = "Duplicate"' \
  'shape = "thread"' \
  'life = "inactive"' \
  'updated_at = "2026-01-01T00:00:00+00:00"' \
  'owners = ["test"]' \
  '+++'
record active.md \
  '+++' \
  'id = "active"' \
  'title = "Active"' \
  'shape = "thread"' \
  'life = "active"' \
  'updated_at = "2026-01-01T00:00:00+00:00"' \
  'owners = ["test"]' \
  '+++'
record expired.md \
  '+++' \
  'id = "expired"' \
  'title = "Expired"' \
  'shape = "thread"' \
  'life = "active"' \
  'updated_at = "2026-01-01T00:00:00+00:00"' \
  'expires_at = "2026-01-02T00:00:00+00:00"' \
  'owners = ["test"]' \
  '+++'
record refs.md \
  '+++' \
  'id = "refs"' \
  'title = "Refs"' \
  'shape = "task"' \
  'life = "inactive"' \
  'updated_at = "2026-01-01T00:00:00+00:00"' \
  'owners = ["test"]' \
  'realizes = "missing-realizes"' \
  'plan = "missing-plan"' \
  'depends_on = ["missing-dependency", "external:outside"]' \
  'supports = ["missing-support"]' \
  'relates_to = ["missing-relation"]' \
  '+++'
record live.md \
  '+++' \
  'id = "live"' \
  'title = "Live lane"' \
  'shape = "project"' \
  'life = "inactive"' \
  'updated_at = "2026-01-01T00:00:00+00:00"' \
  'owners = ["test"]' \
  '[[lane]]' \
  'repo = "alpha"' \
  "worktree = \"$code/alpha/worktrees/lane\"" \
  'branch = "lane"' \
  'owner = "test"' \
  'state = "live"' \
  '+++'
record branch-mismatch.md \
  '+++' \
  'id = "branch-mismatch"' \
  'title = "Wrong branch"' \
  'shape = "project"' \
  'life = "inactive"' \
  'updated_at = "2026-01-01T00:00:00+00:00"' \
  'owners = ["test"]' \
  '[[lane]]' \
  'repo = "alpha"' \
  "worktree = \"$code/alpha/worktrees/lane\"" \
  'branch = "wrong"' \
  'owner = "test"' \
  'state = "active"' \
  '+++'
record missing-lane.md \
  '+++' \
  'id = "missing-lane"' \
  'title = "Missing lane"' \
  'shape = "project"' \
  'life = "inactive"' \
  'updated_at = "2026-01-01T00:00:00+00:00"' \
  'owners = ["test"]' \
  '[[lane]]' \
  'repo = "alpha"' \
  "worktree = \"$code/alpha/worktrees/missing\"" \
  'branch = "missing"' \
  'owner = "test"' \
  'state = "live"' \
  '+++'
record detached.md \
  '+++' \
  'id = "detached"' \
  'title = "Detached lane"' \
  'shape = "project"' \
  'life = "inactive"' \
  'updated_at = "2026-01-01T00:00:00+00:00"' \
  'owners = ["test"]' \
  '[[lane]]' \
  'repo = "alpha"' \
  "worktree = \"$code/alpha/worktrees/detached\"" \
  'branch = "detached"' \
  'owner = "test"' \
  'state = "live"' \
  '+++'
record reaped.md \
  '+++' \
  'id = "reaped"' \
  'title = "Reaped lane"' \
  'shape = "project"' \
  'life = "inactive"' \
  'updated_at = "2026-01-01T00:00:00+00:00"' \
  'owners = ["test"]' \
  '[[lane]]' \
  'repo = "alpha"' \
  "worktree = \"$code/alpha/worktrees/reaped\"" \
  'branch = "reaped-branch"' \
  'owner = "test"' \
  'state = "reaped"' \
  '+++'
record future.md \
  '+++' \
  'id = "future"' \
  'title = "Future"' \
  'shape = "thread"' \
  'life = "inactive"' \
  'updated_at = "2027-01-01T00:00:00+00:00"' \
  'owners = ["test"]' \
  '+++'
record no-frontmatter.md 'not a record'
record invalid-toml.md '+++' 'id = [' '+++'

set +e
CODE_ROOT="$code" HOME="$home" "$lint" --now 2026-02-01T00:00:00+00:00 \
  --mtime-drift-seconds 999999999 "$todo" >"$scratch/text"
status=$?
set -e
[ "$status" -eq 0 ]

for code_name in \
  TOP_LEVEL_NON_MARKDOWN TOP_LEVEL_SUBDIRECTORY FRONT_MATTER_MISSING FRONT_MATTER_INVALID \
  DUPLICATE_ID ID_FILENAME_MISMATCH ACTIVE_EXPIRES_AT_MISSING ACTIVE_EXPIRES_AT_OVERDUE \
  REFERENCE_UNRESOLVED LANE_BRANCH_MISMATCH LANE_WORKTREE_MISSING LANE_WORKTREE_UNREGISTERED \
  LANE_BRANCH_MISSING LANE_REAPED_WORKTREE_PRESENT LANE_REAPED_BRANCH_PRESENT TIMESTAMP_FUTURE; do
  grep -Fq "$code_name" "$scratch/text"
done
grep -Fq 'REFERENCE_UNRESOLVED' "$scratch/text"
[ "$(grep -c 'REFERENCE_UNRESOLVED' "$scratch/text")" -eq 5 ]

set +e
CODE_ROOT="$code" HOME="$home" "$lint" --strict --format json --now 2026-02-01T00:00:00+00:00 \
  --mtime-drift-seconds 999999999 "$todo" >"$scratch/json"
status=$?
set -e
[ "$status" -eq 1 ]
python3 - "$scratch/json" <<'PY'
import json
import sys

report = json.load(open(sys.argv[1]))
assert report["summary"]["findings"] > 0
assert report["summary"]["errors"] > 0
assert any(item["code"] == "ACTIVE_EXPIRES_AT_MISSING" and item["severity"] == "warning" for item in report["findings"])
PY

clean="$scratch/clean"
mkdir "$clean"
record_clean() {
  printf '%s\n' \
    '+++' \
    'id = "clean"' \
    'title = "Clean"' \
    'shape = "thread"' \
    'life = "inactive"' \
    'updated_at = "2026-01-01T00:00:00+00:00"' \
    'owners = ["test"]' \
    '+++' >"$clean/clean.md"
}
record_clean
CODE_ROOT="$code" HOME="$home" "$lint" --strict --now 2026-02-01T00:00:00+00:00 \
  --mtime-drift-seconds 999999999 "$clean" >"$scratch/clean-out"
grep -Fxq 'todo-lint: clean' "$scratch/clean-out"
CODE_ROOT="$code" HOME="$home" "$lint" --now 2026-02-01T00:00:00+00:00 \
  --mtime-drift-seconds 0 "$clean" >"$scratch/drift-out"
grep -Fq 'TIMESTAMP_MTIME_DRIFT' "$scratch/drift-out"
set +e
"$lint" --now 2026-02-01T00:00:00 "$clean" >/dev/null 2>"$scratch/invalid-now"
status=$?
set -e
[ "$status" -eq 2 ]
grep -Fq 'must include a UTC offset' "$scratch/invalid-now"

printf 'todo-lint tests: PASS (report-only baseline, strict ratchet, JSON, records, references, lanes, timestamps)\n'
