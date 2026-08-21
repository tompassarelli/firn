#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
generator="$repo/dotfiles/bin/todo-frontmatter-generator"
lint="$repo/dotfiles/bin/todo-lint"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/todo-frontmatter-generator.XXXXXX")
trap 'rm -rf "${scratch:?}"' EXIT

todo="$scratch/todo"
mkdir "$todo"
printf '%s\n' '# A genuine record' '' 'body' >"$todo/genuine-record.md"
printf '%s\n' '+++' 'id = "existing-record"' 'title = "Existing"' '+++' '' 'body' >"$todo/existing-record.md"
printf '%s\n' '# Reserved' >"$todo/AGENTS.md"
printf '%s\n' '# Board' >"$todo/agent-coord.md"
printf '%s\n' '# Commander' >"$todo/COMMANDER-RESUME.md"
printf '%s\n' '# Ledger' >"$todo/model-assignment-ledger.md"
printf '\n' >"$todo/empty.md"

before_existing=$(sha256sum "$todo/existing-record.md" | cut -d' ' -f1)
before_reserved=$(sha256sum "$todo/AGENTS.md" | cut -d' ' -f1)
before_body=$(sha256sum "$todo/genuine-record.md" | cut -d' ' -f1)
output=$("$generator" --dry-run "$todo")
grep -Fq '"stamped": 1' <<<"$output"
test "$(sha256sum "$todo/genuine-record.md" | cut -d' ' -f1)" = "$before_body"
output=$("$generator" "$todo")
grep -Fq '"stamped": 1' <<<"$output"
test "$(sha256sum "$todo/existing-record.md" | cut -d' ' -f1)" = "$before_existing"
test "$(sha256sum "$todo/AGENTS.md" | cut -d' ' -f1)" = "$before_reserved"
grep -Fqx 'id = "genuine-record"' <(sed -n '2p' "$todo/genuine-record.md")
printf '%s\n' '# A genuine record' '' 'body' | cmp - <(tail -n +9 "$todo/genuine-record.md")
output=$("$generator" "$todo")
grep -Fq '"stamped": 0' <<<"$output"
set +e
"$lint" --strict --mtime-drift-seconds 999999999 "$todo" >/dev/null
status=$?
set -e
test "$status" -eq 1

printf 'todo-frontmatter-generator tests: PASS\n'
