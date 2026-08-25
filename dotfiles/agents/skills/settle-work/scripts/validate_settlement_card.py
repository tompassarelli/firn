#!/usr/bin/env python3
"""Fail-closed validation for owner-issued delegated-work SettlementCards."""

from __future__ import annotations

import argparse
from datetime import datetime
from decimal import Decimal, InvalidOperation, ROUND_HALF_EVEN
import hashlib
from pathlib import Path
import re
import sys
import tomllib
from typing import Any


SCHEMA = "agent-settlement-card/v1"
ROOT_FIELDS = {
    "schema",
    "todo_record",
    "todo_record_sha256",
    "record_id",
    "authorized_by",
    "issued_at",
    "commit",
    "overrun_cause",
    "verification_verdict",
    "verification_evidence",
    "review_evidence",
    "quality_debt",
    "attempt",
    "lane",
}
ROOT_REQUIRED = ROOT_FIELDS - {"overrun_cause"}
ATTEMPT_REQUIRED = {
    "id",
    "ended_at",
    "outcome",
    "wall_time_actual",
    "agent_time_actual",
    "queue_block_time_actual",
    "verification_time_actual",
    "verification_summary",
    "review_outcome",
}
ATTEMPT_OPTIONAL = {
    "queue_block_cause",
    "race_outcome",
    "reviewed_commit",
    "review_summary",
    "reviewer_model",
    "reviewer_reasoning",
    "review_repair_time_actual",
}
ATTEMPT_ALLOWED = ATTEMPT_REQUIRED | ATTEMPT_OPTIONAL
SETTLEMENT_FIELDS = ATTEMPT_ALLOWED - {"id"}
TIME_FIELDS = {
    "wall_time_actual",
    "agent_time_actual",
    "queue_block_time_actual",
    "verification_time_actual",
    "review_repair_time_actual",
}
DEBT_FIELDS = {"attempt", "path", "invariant", "severity", "owner", "exit_condition"}
LANE_FIELDS = {"repo", "worktree", "branch", "state"}
VERIFICATION_VERDICTS = {"passed", "failed", "not-run"}
REVIEW_OUTCOMES = {"clean", "findings", "not-run"}
ACTUAL_DURATION = re.compile(r"^(?:\d+(?:\.\d+)?(?:ms|s|m|h|d))+$")
DURATION_COMPONENT = re.compile(r"(\d+(?:\.\d+)?)(ms|s|m|h|d)")
DURATION_SCALE = {
    "ms": Decimal("0.001"),
    "s": Decimal(1),
    "m": Decimal(60),
    "h": Decimal(3600),
    "d": Decimal(86400),
}
DURATION_BASE_PRECISION = Decimal("0.001")
DIGEST = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")


def nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def string_list(value: Any) -> bool:
    return isinstance(value, list) and all(nonempty(item) for item in value)


def timestamp(value: Any, label: str, errors: list[str]) -> datetime | None:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value)
        except ValueError:
            errors.append(f"{label} must be an ISO 8601 timestamp")
            return None
    else:
        errors.append(f"{label} must be an ISO 8601 timestamp")
        return None
    if parsed.tzinfo is None:
        errors.append(f"{label} must include a UTC offset")
        return None
    return parsed


def duration(value: Any, label: str, errors: list[str]) -> tuple[Decimal, Decimal] | None:
    if not isinstance(value, str) or ACTUAL_DURATION.fullmatch(value) is None:
        errors.append(f"{label} must be an exact compact duration")
        return None
    total = Decimal(0)
    precision = DURATION_BASE_PRECISION
    try:
        for raw_number, unit in DURATION_COMPONENT.findall(value):
            number = Decimal(raw_number)
            scale = DURATION_SCALE[unit]
            total += number * scale
            lexical_precision = Decimal(1).scaleb(number.as_tuple().exponent) * scale
            precision = min(precision, lexical_precision)
    except (InvalidOperation, OverflowError):
        errors.append(f"{label} must be an exact compact duration")
        return None
    return total, precision


def elapsed_seconds(started_at: datetime, ended_at: datetime) -> Decimal:
    elapsed = ended_at - started_at
    return (
        Decimal(elapsed.days) * DURATION_SCALE["d"]
        + Decimal(elapsed.seconds)
        + Decimal(elapsed.microseconds) / Decimal(1_000_000)
    )


def parse_frontmatter(raw: bytes, errors: list[str]) -> dict[str, Any] | None:
    try:
        lines = raw.decode("utf-8").splitlines()
    except UnicodeError as exc:
        errors.append(f"todo record is not UTF-8: {exc}")
        return None
    if not lines or lines[0] != "+++":
        errors.append("todo record has no TOML front matter")
        return None
    try:
        end = lines.index("+++", 1)
        value = tomllib.loads("\n".join(lines[1:end]))
    except (ValueError, tomllib.TOMLDecodeError) as exc:
        errors.append(f"todo record has invalid TOML front matter: {exc}")
        return None
    return value if isinstance(value, dict) else None


def evidence(label: str, verdict: str, values: Any, errors: list[str]) -> None:
    if not string_list(values):
        errors.append(f"{label}_evidence must be an array of exact non-empty references")
        return
    if any(" :: " not in item for item in values):
        errors.append(f"{label}_evidence entries must use 'source :: observed result'")
    if verdict == "not-run" and values:
        errors.append(f"{label} marked not-run cannot carry evidence")
    if verdict != "not-run" and not values:
        errors.append(f"{verdict} {label} needs exact evidence; a verdict cannot be invented")


def validate(card_path: Path, todo_root: Path) -> list[str]:
    errors: list[str] = []
    try:
        card = tomllib.loads(card_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, tomllib.TOMLDecodeError) as exc:
        return [f"card is unreadable or invalid TOML: {exc}"]
    if not isinstance(card, dict):
        return ["card must decode to one TOML table"]
    for field in sorted(set(card) - ROOT_FIELDS):
        errors.append(f"unknown card field: {field}")
    missing_root = sorted(ROOT_REQUIRED - set(card))
    if missing_root:
        errors.append(f"card is missing: {', '.join(missing_root)}")
    if card.get("schema") != SCHEMA:
        errors.append(f"schema must be {SCHEMA}")

    record_value = card.get("todo_record")
    record_path: Path | None = None
    if nonempty(record_value):
        record_path = Path(record_value).expanduser()
        if not record_path.is_absolute():
            record_path = todo_root / record_path
        record_path = record_path.resolve()
        try:
            record_path.relative_to(todo_root)
        except ValueError:
            errors.append("todo_record escapes the admitted todo root")
            record_path = None
    else:
        errors.append("todo_record must be an exact path")

    record: dict[str, Any] | None = None
    record_digest_stale = False
    if record_path is not None:
        try:
            record_bytes = record_path.read_bytes()
        except OSError as exc:
            errors.append(f"todo record is unreadable: {exc}")
            record_bytes = b""
        record = parse_frontmatter(record_bytes, errors) if record_bytes else None
        expected_digest = card.get("todo_record_sha256")
        if not isinstance(expected_digest, str) or not DIGEST.fullmatch(expected_digest):
            errors.append("todo_record_sha256 must be one lowercase SHA-256 digest")
        else:
            actual_digest = hashlib.sha256(record_bytes).hexdigest()
            if actual_digest != expected_digest:
                record_digest_stale = True

    record_id = card.get("record_id")
    if not nonempty(record_id):
        errors.append("record_id must be non-empty")
    if record is not None:
        if record.get("id") != record_id:
            errors.append("record_id conflicts with the todo record")
        if record_path is not None and record_path.stem != record_id:
            errors.append("record_id conflicts with the todo filename")
    authorized_by = card.get("authorized_by")
    if not nonempty(authorized_by):
        errors.append("authorized_by must name the product owner")
    elif record is not None:
        delegated_by = record.get("delegated_by")
        if record.get("shape") == "task":
            if not nonempty(delegated_by):
                errors.append("task todo record has no delegated_by product authority")
            elif authorized_by != delegated_by:
                errors.append("task SettlementCard must be authorized by delegated_by")
        elif record.get("shape") == "project":
            authorities = (
                set(record.get("owners", []))
                if string_list(record.get("owners"))
                else set()
            )
            if authorized_by not in authorities:
                errors.append("SettlementCard must be authorized by an owning product owner")
        else:
            errors.append("SettlementCard record must be a task or project")

    issued_at = timestamp(card.get("issued_at"), "issued_at", errors)
    commit = card.get("commit")
    if not isinstance(commit, str) or COMMIT.fullmatch(commit) is None:
        errors.append("commit must be one full lowercase Git object ID")
    if "overrun_cause" in card and not nonempty(card.get("overrun_cause")):
        errors.append("overrun_cause must be explicit, including 'none'")

    verification_verdict = card.get("verification_verdict")
    if verification_verdict not in VERIFICATION_VERDICTS:
        errors.append("verification_verdict must be passed, failed, or not-run")
    else:
        evidence("verification", verification_verdict, card.get("verification_evidence"), errors)

    attempt = card.get("attempt")
    source_attempt: dict[str, Any] | None = None
    ended_at: datetime | None = None
    attempt_replay_exact = False
    parsed_durations: dict[str, tuple[Decimal, Decimal]] = {}
    if not isinstance(attempt, dict):
        errors.append("attempt must be one TOML table")
        attempt = {}
    else:
        for field in sorted(set(attempt) - ATTEMPT_ALLOWED):
            errors.append(f"unknown attempt field: {field}")
        missing = sorted(ATTEMPT_REQUIRED - set(attempt))
        if missing:
            errors.append(f"attempt is missing: {', '.join(missing)}")
        for field in sorted(TIME_FIELDS & set(attempt)):
            parsed = duration(attempt[field], f"attempt.{field}", errors)
            if parsed is not None:
                parsed_durations[field] = parsed
        for field in sorted((ATTEMPT_ALLOWED - TIME_FIELDS - {"id", "ended_at"}) & set(attempt)):
            if not nonempty(attempt[field]):
                errors.append(f"attempt.{field} must be non-empty")
        ended_at = timestamp(attempt.get("ended_at"), "attempt.ended_at", errors)

    attempt_id = attempt.get("id")
    if record is not None:
        attempts = record.get("attempt", [])
        matches = (
            [
                item
                for item in attempts
                if isinstance(item, dict) and item.get("id") == attempt_id
            ]
            if isinstance(attempts, list)
            else []
        )
        if len(matches) != 1:
            errors.append(f"attempt id {attempt_id!r} does not identify exactly one owning attempt")
        else:
            source_attempt = matches[0]
            card_terminal = {
                field: attempt[field]
                for field in SETTLEMENT_FIELDS & set(attempt)
            }
            source_terminal = {
                field: source_attempt[field]
                for field in SETTLEMENT_FIELDS & set(source_attempt)
            }
            attempt_replay_exact = source_terminal == card_terminal
            for field in sorted(set(source_terminal) - set(card_terminal)):
                errors.append(f"owning attempt has unlisted settlement field: {field}")
            for field in sorted(set(card_terminal) & set(source_terminal)):
                if source_attempt[field] != attempt[field]:
                    errors.append(f"owning attempt has conflicting settlement field: {field}")
            started_at = timestamp(
                source_attempt.get("started_at"), "owning attempt started_at", errors
            )
            if started_at is not None and ended_at is not None and ended_at < started_at:
                errors.append("attempt.ended_at precedes the owning attempt start")
            wall = parsed_durations.get("wall_time_actual")
            if started_at is not None and ended_at is not None and wall is not None:
                wall_seconds, precision = wall
                elapsed = elapsed_seconds(started_at, ended_at)
                elapsed_at_precision = (
                    (elapsed / precision).to_integral_value(rounding=ROUND_HALF_EVEN)
                    * precision
                )
                if elapsed_at_precision != wall_seconds:
                    errors.append(
                        "attempt.wall_time_actual conflicts with ended_at - started_at"
                    )
    if issued_at is not None and ended_at is not None and issued_at < ended_at:
        errors.append("issued_at precedes attempt.ended_at")

    wall = parsed_durations.get("wall_time_actual")
    if wall is not None:
        wall_seconds = wall[0]
        for field in (
            "queue_block_time_actual",
            "verification_time_actual",
            "review_repair_time_actual",
        ):
            parsed = parsed_durations.get(field)
            if parsed is not None and parsed[0] > wall_seconds:
                errors.append(f"attempt.{field} exceeds wall_time_actual")

    if verification_verdict in VERIFICATION_VERDICTS and not nonempty(
        attempt.get("verification_summary")
    ):
        errors.append(
            "attempt.verification_summary must state the owner's exact verification result"
        )

    review_outcome = attempt.get("review_outcome")
    if review_outcome not in REVIEW_OUTCOMES:
        errors.append("attempt.review_outcome must be clean, findings, or not-run")
    else:
        evidence("review", review_outcome, card.get("review_evidence"), errors)
        review_fields = {
            "reviewed_commit",
            "review_summary",
            "reviewer_model",
            "reviewer_reasoning",
            "review_repair_time_actual",
        }
        present_review_fields = review_fields & set(attempt)
        if review_outcome == "not-run" and present_review_fields:
            errors.append("not-run review cannot carry review result fields")
        if review_outcome in {"clean", "findings"}:
            if attempt.get("reviewed_commit") != commit:
                errors.append("reviewed_commit must equal the card commit")
            if not nonempty(attempt.get("review_summary")):
                errors.append("a completed review needs review_summary")
            if source_attempt is not None and source_attempt.get("review_budget") == "independent":
                if not all(
                    nonempty(attempt.get(field))
                    for field in ("reviewer_model", "reviewer_reasoning")
                ):
                    errors.append("independent review needs reviewer_model and reviewer_reasoning")
            paired = [field in attempt for field in ("reviewer_model", "reviewer_reasoning")]
            if any(paired) and not all(paired):
                errors.append("reviewer_model and reviewer_reasoning must appear together")
        if "review_repair_time_actual" in attempt and review_outcome != "findings":
            errors.append("review repair time requires findings")

    has_race = source_attempt is not None and nonempty(source_attempt.get("race"))
    if has_race and not nonempty(attempt.get("race_outcome")):
        errors.append("a raced attempt needs an explicit race_outcome")
    if not has_race and "race_outcome" in attempt:
        errors.append("race_outcome cannot be added to a non-race attempt")

    debt = card.get("quality_debt")
    debt_replay_exact = False
    if not isinstance(debt, list):
        errors.append("quality_debt must be an explicit array")
    else:
        prior_debt = record.get("quality_debt", []) if record is not None else []
        prior_attempt_debt = (
            [
                item
                for item in prior_debt
                if isinstance(item, dict) and item.get("attempt") == attempt_id
            ]
            if isinstance(prior_debt, list)
            else []
        )
        debt_replay_exact = prior_attempt_debt == debt
        if prior_attempt_debt and not debt_replay_exact:
            errors.append("quality_debt conflicts with the owning record")
        for index, item in enumerate(debt, 1):
            if not isinstance(item, dict) or set(item) != DEBT_FIELDS:
                errors.append(f"quality_debt {index} must use the todo debt fields exactly")
                continue
            if item.get("attempt") != attempt_id or not all(
                nonempty(value) for value in item.values()
            ):
                errors.append(f"quality_debt {index} is incomplete or names the wrong attempt")
            if record is not None:
                matches = [
                    prior
                    for prior in prior_debt
                    if isinstance(prior, dict)
                    and prior.get("attempt") == item.get("attempt")
                    and prior.get("path") == item.get("path")
                ] if isinstance(prior_debt, list) else []
                if matches and any(prior != item for prior in matches):
                    errors.append(f"quality_debt {index} conflicts with the owning record")

    lane = card.get("lane")
    lane_replay_exact = False
    if not isinstance(lane, dict):
        errors.append("lane must be one TOML table")
        lane = {}
    elif set(lane) - LANE_FIELDS:
        errors.append(f"unknown lane field: {', '.join(sorted(set(lane) - LANE_FIELDS))}")
    if not nonempty(lane.get("state")):
        errors.append("lane.state must be an exact owner-supplied state")
    if record is not None:
        lanes = record.get("lane", [])
        if not isinstance(lanes, list):
            lanes = []
        if lane.get("state") == "none":
            if lanes or set(lane) != {"state"}:
                errors.append("lane state none conflicts with the owning record")
            else:
                lane_replay_exact = True
        else:
            if not all(nonempty(lane.get(field)) for field in ("repo", "worktree", "branch")):
                errors.append("lane must name repo, worktree, and branch")
            matches = [
                item for item in lanes if isinstance(item, dict)
                and all(
                    item.get(field) == lane.get(field)
                    for field in ("repo", "worktree", "branch")
                )
            ]
            if len(matches) != 1:
                errors.append("lane does not identify exactly one owning record lane")
            else:
                lane_replay_exact = matches[0].get("state") == lane.get("state")

    if record_digest_stale and not (
        attempt_replay_exact and debt_replay_exact and lane_replay_exact
    ):
        errors.append("todo record digest is stale or conflicting")

    return sorted(set(errors))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="validate one delegated-work SettlementCard")
    parser.add_argument("card", type=Path)
    parser.add_argument(
        "--todo-root",
        type=Path,
        default=Path.home() / "code" / "todo",
        help="admitted flat todo root (default: ~/code/todo)",
    )
    args = parser.parse_args(argv)
    errors = validate(args.card.resolve(), args.todo_root.expanduser().resolve())
    if errors:
        for error in errors:
            print(f"SettlementCard invalid: {error}", file=sys.stderr)
        return 1
    print("SettlementCard valid: exact terminal fields and lane identity admitted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
