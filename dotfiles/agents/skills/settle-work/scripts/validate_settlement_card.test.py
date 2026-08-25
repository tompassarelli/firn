#!/usr/bin/env python3
"""Focused positive, replay, and fail-closed SettlementCard fixtures."""

from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib


VALIDATOR = Path(__file__).with_name("validate_settlement_card.py")
UPDATER = Path(__file__).with_name("update_calibration_receipt.py")

EXACT_OBSERVATION = (
    'execution_observation = { version = "agent-execution-observation/v1", '
    'coverage = "exact", source = "fixture-producer-join", '
    'turn_unit = "assistant-turn", tool_call_unit = "admitted-tool-call", '
    'evidence = { provider = "fixture", attempt_sha256 = "' + "a" * 64
    + '", session_sha256 = "' + "b" * 64
    + '" }, segments = ['
    '{ mode = "standard", turn_count = 1, tool_call_count = 2, turn_sha256 = ["'
    + "c" * 64
    + '"] }, { mode = "fast", turn_count = 1, tool_call_count = 3, turn_sha256 = ["'
    + "d" * 64
    + '"] }, { mode = "standard", turn_count = 1, tool_call_count = 1, turn_sha256 = ["'
    + "e" * 64
    + '"] }] }'
)
UNKNOWN_OBSERVATION = (
    'execution_observation = { version = "agent-execution-observation/v1", '
    'coverage = "unknown", '
    'source = "codex-missing-initial-settings-and-attempt-session-join", '
    'turn_unit = "unknown", tool_call_unit = "unknown", '
    'evidence = {}, segments = [] }'
)


def run(card: Path, todo: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VALIDATOR), str(card), "--todo-root", str(todo)],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def update(card: Path, todo: Path, ledger: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(UPDATER),
            str(card),
            str(ledger),
            "--todo-root",
            str(todo),
        ],
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
{EXACT_OBSERVATION}

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

        unavailable = root / "unknown-observation.toml"
        unavailable.write_text(
            base.replace(EXACT_OBSERVATION, UNKNOWN_OBSERVATION),
            encoding="utf-8",
        )
        result = run(unavailable, todo)
        assert result.returncode == 0, result.stderr
        print("explicit unknown observation case: PASS")

        rendered = subprocess.run(
            [
                sys.executable,
                str(VALIDATOR),
                str(positive),
                "--todo-root",
                str(todo),
                "--render-receipt",
            ],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert rendered.returncode == 0, rendered.stderr
        assert 'execution observation: {"coverage":"exact"' in rendered.stdout
        assert rendered.stdout.index('"mode":"standard"') < rendered.stdout.index('"mode":"fast"')
        assert "turn count total" not in rendered.stdout
        assert "tool call count total" not in rendered.stdout
        observation = tomllib.loads(base)["attempt"]["execution_observation"]
        assert sum(segment["turn_count"] for segment in observation["segments"]) == 3
        assert sum(segment["tool_call_count"] for segment in observation["segments"]) == 6
        assert not {"turn_count_total", "tool_call_count_total"}.intersection(observation)
        print("deterministic ordered receipt rendering case: PASS")

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

        adjacent = root / "adjacent-equal-modes.toml"
        adjacent.write_text(
            base.replace(
                '{ mode = "fast", turn_count = 1, tool_call_count = 3',
                '{ mode = "standard", turn_count = 1, tool_call_count = 3',
            ),
            encoding="utf-8",
        )
        result = run(adjacent, todo)
        assert result.returncode == 1
        assert "repeats the preceding mode instead of coalescing" in result.stderr
        print("adjacent equal mode rejected case: PASS")

        fabricated_unknown = root / "fabricated-unknown.toml"
        fabricated_unknown.write_text(
            base.replace('coverage = "exact"', 'coverage = "unknown"', 1),
            encoding="utf-8",
        )
        result = run(fabricated_unknown, todo)
        assert result.returncode == 1
        assert "unknown coverage cannot carry segments" in result.stderr
        print("unknown observation cannot fabricate zero/default case: PASS")

        raw_session = root / "raw-session-id.toml"
        raw_session.write_text(
            base.replace('session_sha256 = "' + "b" * 64 + '"', 'session_sha256 = "raw-session-id"'),
            encoding="utf-8",
        )
        result = run(raw_session, todo)
        assert result.returncode == 1
        assert "session_sha256 must be lowercase SHA-256" in result.stderr
        print("raw provider session identity rejected case: PASS")

        repeated_turn = root / "repeated-turn-across-segments.toml"
        repeated_turn.write_text(
            base.replace('"' + "e" * 64 + '"] }] }', '"' + "c" * 64 + '"] }] }'),
            encoding="utf-8",
        )
        result = run(repeated_turn, todo)
        assert result.returncode == 1
        assert "repeats an earlier segment turn" in result.stderr
        print("cross-segment duplicate turn evidence rejected case: PASS")

        unsafe_segment_counts = root / "unsafe-segment-counts.toml"
        unsafe_segment_counts.write_text(
            base.replace(
                "turn_count = 1, tool_call_count = 2",
                "turn_count = 9007199254740992, tool_call_count = 9007199254740992",
                1,
            ),
            encoding="utf-8",
        )
        result = run(unsafe_segment_counts, todo)
        assert result.returncode == 1
        assert "turn_count must be a positive safe integer" in result.stderr
        assert "tool_call_count must be a non-negative safe integer" in result.stderr
        print("unsafe individual segment counts rejected case: PASS")

        unsafe_derived_totals = root / "unsafe-derived-totals.toml"
        unsafe_derived_totals.write_text(
            base.replace(
                "turn_count = 1, tool_call_count = 2",
                "turn_count = 9007199254740991, tool_call_count = 9007199254740991",
                1,
            ),
            encoding="utf-8",
        )
        result = run(unsafe_derived_totals, todo)
        assert result.returncode == 1
        assert "derived turn_count total exceeds the safe-integer maximum" in result.stderr
        assert "derived tool_call_count total exceeds the safe-integer maximum" in result.stderr
        print("unsafe derived count totals rejected case: PASS")

        line_ledger = todo / "estimate-calibration.md"
        line_ledger.write_text("## Receipts\n", encoding="utf-8")
        multiline_card = root / "multiline-receipt-field.toml"
        multiline_card.write_text(
            base.replace('overrun_cause = "none"', 'overrun_cause = "none\\ncontinued"'),
            encoding="utf-8",
        )
        first_multiline = update(multiline_card, todo, line_ledger)
        second_multiline = update(multiline_card, todo, line_ledger)
        assert first_multiline.returncode == second_multiline.returncode == 1
        assert first_multiline.stderr == second_multiline.stderr
        assert "overrun_cause cannot contain CR or LF" in first_multiline.stderr
        assert line_ledger.read_text(encoding="utf-8") == "## Receipts\n"

        carriage_return_card = root / "carriage-return-receipt-field.toml"
        carriage_return_card.write_text(
            base.replace(
                'review_summary = "one finding repaired"',
                'review_summary = "one finding\\rrepaired"',
            ),
            encoding="utf-8",
        )
        result = run(carriage_return_card, todo)
        assert result.returncode == 1
        assert "attempt.review_summary cannot contain CR or LF" in result.stderr

        for label, escaped_separator in (("lf", "\\n"), ("cr", "\\r")):
            timestamp_card = root / f"ended-at-{label}.toml"
            timestamp_card.write_text(
                base.replace(
                    'ended_at = "2026-08-24T10:01:00+00:00"',
                    f'ended_at = "2026-08-24{escaped_separator}10:01:00+00:00"',
                ),
                encoding="utf-8",
            )
            first_timestamp = update(timestamp_card, todo, line_ledger)
            second_timestamp = update(timestamp_card, todo, line_ledger)
            assert first_timestamp.returncode == second_timestamp.returncode == 1
            assert first_timestamp.stderr == second_timestamp.stderr
            assert "attempt.ended_at cannot contain CR or LF" in first_timestamp.stderr
            assert line_ledger.read_text(encoding="utf-8") == "## Receipts\n"

        multiline_record = unsettled.replace(
            'seam = "bounded demo"', 'seam = """bounded\ndemo"""'
        )
        record.write_text(multiline_record, encoding="utf-8")
        multiline_digest = hashlib.sha256(record.read_bytes()).hexdigest()
        multiline_source_card = root / "multiline-source-field.toml"
        multiline_source_card.write_text(
            base.replace(digest, multiline_digest), encoding="utf-8"
        )
        result = run(multiline_source_card, todo)
        assert result.returncode == 1
        assert "owning attempt seam cannot contain CR or LF" in result.stderr
        record.write_text(unsettled, encoding="utf-8")
        print("receipt CR/LF rejection and identical multiline replay cases: PASS")

        terminal = f'''ended_at = "2026-08-24T10:01:00+00:00"
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
{EXACT_OBSERVATION}
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

        ledger = todo / "estimate-calibration.md"
        ledger.write_text("## Receipts\n", encoding="utf-8")
        result = update(positive, todo, ledger)
        assert result.returncode == 0, result.stderr
        assert "updated: demo/A1" in result.stdout
        first_receipt = ledger.read_text(encoding="utf-8")
        assert first_receipt.count("`demo/A1`") == 1
        result = update(positive, todo, ledger)
        assert result.returncode == 0, result.stderr
        assert "already exact: demo/A1" in result.stdout
        assert ledger.read_text(encoding="utf-8") == first_receipt
        reordered = root / "reordered-segments.toml"
        reordered.write_text(
            base.replace(
                'segments = [{ mode = "standard", turn_count = 1, tool_call_count = 2, turn_sha256 = ["'
                + "c" * 64
                + '"] }, { mode = "fast", turn_count = 1, tool_call_count = 3, turn_sha256 = ["'
                + "d" * 64
                + '"] }, { mode = "standard", turn_count = 1, tool_call_count = 1, turn_sha256 = ["'
                + "e" * 64
                + '"] }]',
                'segments = [{ mode = "standard", turn_count = 1, tool_call_count = 1, turn_sha256 = ["'
                + "e" * 64
                + '"] }, { mode = "fast", turn_count = 1, tool_call_count = 3, turn_sha256 = ["'
                + "d" * 64
                + '"] }, { mode = "standard", turn_count = 1, tool_call_count = 2, turn_sha256 = ["'
                + "c" * 64
                + '"] }]',
            ),
            encoding="utf-8",
        )
        result = run(reordered, todo)
        assert result.returncode == 1
        assert "conflicting settlement field: execution_observation" in result.stderr
        assert ledger.read_text(encoding="utf-8") == first_receipt
        conflicting_receipt = first_receipt.replace("outcome: delivered", "outcome: altered")
        ledger.write_text(conflicting_receipt, encoding="utf-8")
        result = update(positive, todo, ledger)
        assert result.returncode == 1
        assert "calibration receipt conflicts for key: demo/A1" in result.stderr
        assert ledger.read_text(encoding="utf-8") == conflicting_receipt
        print("atomic keyed receipt insert/replay/conflict and segment-reorder cases: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
