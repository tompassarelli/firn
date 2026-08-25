#!/usr/bin/env python3
"""Focused positive, replay, and fail-closed SettlementCard fixtures."""

from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile


VALIDATOR = Path(__file__).with_name("validate_settlement_card.py")


def run(card: Path, todo: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VALIDATOR), str(card), "--todo-root", str(todo)],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="settlement-card-test.") as raw:
        root = Path(raw)
        todo = root / "todo"
        todo.mkdir()
        record = todo / "demo.md"
        record.write_text(
            """+++
id = "demo"
title = "Demo"
shape = "task"
life = "active"
updated_at = "2026-08-24T10:00:00+00:00"
owners = ["codex:/root/worker"]
assigned_to = "codex:/root/worker"
delegated_by = "codex:/root"

[[lane]]
repo = "alpha"
worktree = "/tmp/alpha/worktrees/demo"
branch = "demo"
owner = "codex:/root/worker"
state = "active"

[[attempt]]
id = "A1"
seam = "bounded demo"
class = "fixture"
wall_time_estimate = "1m"
agent_time_estimate = "1m"
calibration_sample_count = 1
started_at = "2026-08-24T10:00:00+00:00"
model = "gpt-5.6-terra"
reasoning = "high"
route = "fixture"
assignment_id = "fixture-a1"
role = "worker"
review_budget = "independent"
race = "race-1"
+++

## Verification

Pending.
""",
            encoding="utf-8",
        )
        unsettled = record.read_text(encoding="utf-8")
        digest = hashlib.sha256(record.read_bytes()).hexdigest()
        base = f'''schema = "agent-settlement-card/v1"
todo_record = "{record}"
todo_record_sha256 = "{digest}"
record_id = "demo"
authorized_by = "codex:/root"
issued_at = "2026-08-24T10:01:10+00:00"
commit = "1111111111111111111111111111111111111111"
overrun_cause = "none"
verification_verdict = "passed"
verification_evidence = ["alpha:tests/demo.test :: PASS"]
review_evidence = ["alpha:review/demo :: findings repaired"]
quality_debt = []

[attempt]
id = "A1"
ended_at = "2026-08-24T10:01:00+00:00"
outcome = "delivered"
wall_time_actual = "1m"
agent_time_actual = "1m"
queue_block_time_actual = "0s"
verification_time_actual = "10s"
verification_summary = "focused demo fixture passed"
review_outcome = "findings"
queue_block_cause = "none"
race_outcome = "won"
reviewed_commit = "1111111111111111111111111111111111111111"
review_summary = "one finding repaired"
reviewer_model = "gpt-5.6-sol"
reviewer_reasoning = "high"
review_repair_time_actual = "5s"

[lane]
repo = "alpha"
worktree = "/tmp/alpha/worktrees/demo"
branch = "demo"
state = "preserved"
'''
        positive = root / "positive.toml"
        positive.write_text(base, encoding="utf-8")
        result = run(positive, todo)
        assert result.returncode == 0, result.stderr
        assert "SettlementCard valid" in result.stdout
        print("positive settlement case: PASS")

        cleanup = root / "cleanup-field-rejected.toml"
        cleanup.write_text(
            base + "\n[cleanup]\nauthorized = false\nactions = []\n",
            encoding="utf-8",
        )
        result = run(cleanup, todo)
        assert result.returncode == 1
        assert "unknown card field: cleanup" in result.stderr
        print("cleanup field rejected case: PASS")

        wrong_attempt = root / "wrong-attempt.toml"
        wrong_attempt.write_text(base.replace('id = "A1"', 'id = "A9"', 1), encoding="utf-8")
        result = run(wrong_attempt, todo)
        assert result.returncode == 1
        assert "does not identify exactly one owning attempt" in result.stderr
        print("wrong attempt case: PASS")

        stale = root / "stale-record.toml"
        stale.write_text(base.replace(digest, "0" * 64), encoding="utf-8")
        result = run(stale, todo)
        assert result.returncode == 1
        assert "todo record digest is stale or conflicting" in result.stderr
        print("stale record case: PASS")

        missing_evidence = root / "missing-evidence.toml"
        missing_evidence.write_text(
            base.replace(
                'verification_evidence = ["alpha:tests/demo.test :: PASS"]',
                "verification_evidence = []",
            ),
            encoding="utf-8",
        )
        result = run(missing_evidence, todo)
        assert result.returncode == 1
        assert "a verdict cannot be invented" in result.stderr
        print("missing evidence case: PASS")

        invalid_review = root / "invalid-review.toml"
        invalid_review.write_text(
            base.replace(
                'review_evidence = ["alpha:review/demo :: findings repaired"]',
                "review_evidence = []",
            ),
            encoding="utf-8",
        )
        result = run(invalid_review, todo)
        assert result.returncode == 1
        assert "findings review needs exact evidence" in result.stderr
        print("invalid review case: PASS")

        wrong_debt = root / "wrong-debt.toml"
        wrong_debt.write_text(
            base.replace(
                "quality_debt = []",
                'quality_debt = [{ attempt = "A9", path = "alpha:file", invariant = "exact", severity = "medium", owner = "codex:/root", exit_condition = "proved" }]',
            ),
            encoding="utf-8",
        )
        result = run(wrong_debt, todo)
        assert result.returncode == 1
        assert "is incomplete or names the wrong attempt" in result.stderr
        print("wrong debt case: PASS")

        wrong_lane = root / "wrong-lane.toml"
        wrong_lane.write_text(
            base.replace('branch = "demo"', 'branch = "elsewhere"'),
            encoding="utf-8",
        )
        result = run(wrong_lane, todo)
        assert result.returncode == 1
        assert "lane does not identify exactly one owning record lane" in result.stderr
        print("wrong lane case: PASS")

        mismatch = root / "wall-duration-mismatch.toml"
        mismatch.write_text(
            base.replace('wall_time_actual = "1m"', 'wall_time_actual = "59s"'),
            encoding="utf-8",
        )
        result = run(mismatch, todo)
        assert result.returncode == 1
        assert "wall_time_actual conflicts with ended_at - started_at" in result.stderr
        print("wall-duration mismatch case: PASS")

        excessive = root / "portion-greater-than-wall.toml"
        excessive.write_text(
            base.replace(
                'verification_time_actual = "10s"',
                'verification_time_actual = "1m1s"',
            ),
            encoding="utf-8",
        )
        result = run(excessive, todo)
        assert result.returncode == 1
        assert "verification_time_actual exceeds wall_time_actual" in result.stderr
        print("portion greater than wall case: PASS")

        terminal = '''ended_at = "2026-08-24T10:01:00+00:00"
outcome = "delivered"
wall_time_actual = "1m"
agent_time_actual = "1m"
queue_block_time_actual = "0s"
verification_time_actual = "10s"
verification_summary = "focused demo fixture passed"
review_outcome = "findings"
queue_block_cause = "none"
race_outcome = "won"
reviewed_commit = "1111111111111111111111111111111111111111"
review_summary = "one finding repaired"
reviewer_model = "gpt-5.6-sol"
reviewer_reasoning = "high"
review_repair_time_actual = "5s"
'''
        partially_settled = unsettled.replace(
            'review_budget = "independent"\nrace = "race-1"\n',
            'review_budget = "independent"\nrace = "race-1"\n'
            'ended_at = "2026-08-24T10:01:00+00:00"\n'
            'outcome = "delivered"\n',
        )
        record.write_text(partially_settled, encoding="utf-8")
        result = run(positive, todo)
        assert result.returncode == 1
        assert "todo record digest is stale or conflicting" in result.stderr
        print("partial todo replacement rejected case: PASS")

        settled = unsettled.replace(
            'review_budget = "independent"\nrace = "race-1"\n',
            'review_budget = "independent"\nrace = "race-1"\n' + terminal,
        ).replace('state = "active"', 'state = "preserved"')
        record.write_text(settled, encoding="utf-8")
        result = run(positive, todo)
        assert result.returncode == 0, result.stderr
        print("exact replay of every terminal field case: PASS")

        conflicting = root / "conflicting-prior-settlement.toml"
        conflicting.write_text(
            base.replace('queue_block_cause = "none"', 'queue_block_cause = "contention"'),
            encoding="utf-8",
        )
        result = run(conflicting, todo)
        assert result.returncode == 1
        assert "conflicting settlement field: queue_block_cause" in result.stderr
        print("conflicting prior settlement case: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
