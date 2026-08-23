#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "${test_root:?}"' EXIT

mkdir -p "$test_root/code/nixos-config"
ln -s "$repo" "$test_root/code/nixos-config/main"

ag() {
  HOME=$test_root \
    AGENTS_MODULES=$repo/dotfiles/agents/modules.d \
    "$repo/dotfiles/bin/agents" "$@"
}

ag on estimate >/dev/null
test -L "$test_root/.config/agents/skills/estimate"
test -L "$test_root/.codex/skills/estimate"
test -r "$test_root/.codex/skills/estimate/agents/openai.yaml"
test "$(ag path estimate)" = "$test_root/code/nixos-config/main/dotfiles/agents/skills/estimate/SKILL.md"

ag off estimate >/dev/null
test ! -e "$test_root/.config/agents/skills/estimate"
test ! -e "$test_root/.codex/skills/estimate"

todo_skill="$repo/dotfiles/agents/skills/todo/SKILL.md"
delegate_skill="$repo/dotfiles/agents/skills/delegating-agents/SKILL.md"
grep -Fq '## Attempt, review, and debt receipt' "$todo_skill"
grep -Fq 'wall_time_estimate' "$todo_skill"
grep -Fq 'agent_time_actual' "$todo_skill"
grep -Fq '[[quality_debt]]' "$todo_skill"
grep -Fq 'same-class, same-model agent actuals' "$repo/dotfiles/agents/skills/estimate/SKILL.md"
grep -Fq '## Budget review without losing deferred work' "$delegate_skill"

python3 - <<'PY'
import tomllib

record = tomllib.loads('''
id = "forward-test"
title = "Luna/Terra race with Sol review"
shape = "task"
life = "active"
updated_at = "2026-08-23T16:15:34+08:00"
owners = ["test"]

[[attempt]]
id = "A1"
seam = "bounded repair"
class = "repair"
wall_time_estimate = "8m"
agent_time_estimate = "8m"
calibration_sample_count = 3
started_at = "2026-08-23T16:15:34+08:00"
model = "gpt-5.6-luna"
reasoning = "medium"
route = "economy/medium"
assignment_id = "luna-1"
role = "worker"
review_budget = "independent"
race = "R1"
ended_at = "2026-08-23T16:21:34+08:00"
outcome = "lost"
wall_time_actual = "6m"
agent_time_actual = "6m"
queue_block_time_actual = "0m"
verification_time_actual = "1m"
race_outcome = "lost"

[[attempt]]
id = "A2"
seam = "bounded repair"
class = "repair"
wall_time_estimate = "8m"
agent_time_estimate = "8m"
calibration_sample_count = 3
started_at = "2026-08-23T16:15:34+08:00"
model = "gpt-5.6-terra"
reasoning = "high"
route = "standard/high"
assignment_id = "terra-1"
role = "worker"
review_budget = "independent"
race = "R1"
ended_at = "2026-08-23T16:20:34+08:00"
outcome = "landed"
wall_time_actual = "5m"
agent_time_actual = "5m"
queue_block_time_actual = "0m"
verification_time_actual = "1m"
race_outcome = "winner"
reviewed_commit = "0123456789abcdef"
review_outcome = "findings"
review_summary = "one bounded defect required repair"
reviewer_model = "gpt-5.6-sol"
reviewer_reasoning = "xhigh"
review_repair_time_actual = "2m"

[[quality_debt]]
attempt = "A2"
path = "repo:src/example"
invariant = "explicit deferred boundary"
severity = "P2"
owner = "test"
exit_condition = "focused proof passes"
''')

assert len(record["attempt"]) == 2
assert {item["model"] for item in record["attempt"]} == {"gpt-5.6-luna", "gpt-5.6-terra"}
winner = next(item for item in record["attempt"] if item["race_outcome"] == "winner")
assert winner["reviewer_model"] == "gpt-5.6-sol"
assert record["quality_debt"][0]["attempt"] == winner["id"]
PY

printf 'ok: estimate skill activates and the Luna/Terra/Sol attempt-review receipt is representable\n'
