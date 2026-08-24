#!/usr/bin/env python3
"""Focused positive and fail-closed SettlementCard fixtures."""

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
review_budget = "owner"
+++

## Verification

Pending.
""",
            encoding="utf-8",
        )
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
review_evidence = []
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
review_outcome = "not-run"

[lane]
repo = "alpha"
worktree = "/tmp/alpha/worktrees/demo"
branch = "demo"
state = "preserved"

[cleanup]
authorized = false
actions = []
'''
        positive = root / "positive.toml"
        positive.write_text(base, encoding="utf-8")
        result = run(positive, todo)
        assert result.returncode == 0, result.stderr
        assert "SettlementCard valid" in result.stdout
        print("positive settlement case: PASS")

        wrong_attempt = root / "wrong-attempt.toml"
        wrong_attempt.write_text(base.replace('id = "A1"', 'id = "A9"', 1), encoding="utf-8")
        result = run(wrong_attempt, todo)
        assert result.returncode == 1
        assert "does not identify exactly one owning attempt" in result.stderr
        print("wrong attempt case: PASS")

        invented = root / "invented-verdict-cleanup.toml"
        invented.write_text(
            base.replace(
                'verification_evidence = ["alpha:tests/demo.test :: PASS"]',
                "verification_evidence = []",
            ).replace(
                "[cleanup]\nauthorized = false\nactions = []",
                '''[cleanup]
authorized = true
authorized_by = "codex:/root/settler"
actions = ["remove-worktree"]
reason = "assumed disposable"
lane_state_after = "reaped"''',
            ),
            encoding="utf-8",
        )
        result = run(invented, todo)
        assert result.returncode == 1
        assert "a verdict cannot be invented" in result.stderr
        assert "cleanup authorized_by must equal the product owner" in result.stderr
        assert "cleanup requires a landed, superseded, or race-loser lane" in result.stderr
        print("negative invented-verdict/cleanup case: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
