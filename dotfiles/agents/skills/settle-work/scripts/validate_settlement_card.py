#!/usr/bin/env python3
"""Fail-closed validation for owner-issued delegated-work SettlementCards."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
from pathlib import Path
import re
import subprocess
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
    "cleanup",
}
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
SETTLEMENT_FIELDS = {
    "ended_at",
    "outcome",
    "wall_time_actual",
    "agent_time_actual",
    "queue_block_time_actual",
    "verification_time_actual",
}
TIME_FIELDS = {
    "wall_time_actual",
    "agent_time_actual",
    "queue_block_time_actual",
    "verification_time_actual",
    "review_repair_time_actual",
}
DEBT_FIELDS = {"attempt", "path", "invariant", "severity", "owner", "exit_condition"}
LANE_FIELDS = {"repo", "worktree", "branch", "state"}
CLEANUP_FIELDS = {"authorized", "authorized_by", "actions", "reason", "lane_state_after"}
CLEANUP_ACTIONS = {"remove-worktree", "delete-branch"}
CLEANUP_STATES = {"landed", "superseded", "race-loser"}
TERMINAL_LANE_STATES = CLEANUP_STATES | {"preserved", "none"}
VERIFICATION_VERDICTS = {"passed", "failed", "not-run"}
REVIEW_OUTCOMES = {"clean", "findings", "not-run"}
ACTUAL_DURATION = re.compile(r"^(?:\d+(?:\.\d+)?(?:ms|s|m|h|d))+$")
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


def git(worktree: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(worktree), *args],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def validate_cleanup_worktree(
    lane: dict[str, Any], commit: str, actions: list[str], errors: list[str]
) -> None:
    worktree = Path(lane["worktree"]).expanduser().resolve()
    if "worktrees" not in worktree.parts:
        errors.append("cleanup target is not inside a worktrees/ lane")
        return
    if not worktree.is_dir():
        errors.append(f"cleanup worktree is absent: {worktree}")
        return
    status = git(worktree, "status", "--porcelain=v1", "--untracked-files=all")
    if status.returncode != 0:
        errors.append(f"cleanup worktree status failed: {status.stderr.strip()}")
        return
    if status.stdout:
        errors.append("cleanup worktree is not clean")
    branch = git(worktree, "branch", "--show-current")
    if branch.returncode != 0 or branch.stdout.strip() != lane["branch"]:
        errors.append("cleanup worktree branch conflicts with the card")
    head = git(worktree, "rev-parse", "HEAD")
    if head.returncode != 0 or head.stdout.strip() != commit:
        errors.append("cleanup worktree HEAD conflicts with the card commit")
    if "delete-branch" in actions and "remove-worktree" not in actions:
        errors.append("delete-branch cleanup also requires remove-worktree")
    if lane["state"] == "landed":
        main = worktree.parent.parent / "main"
        landed = git(main, "merge-base", "--is-ancestor", commit, "HEAD") if main.is_dir() else None
        if landed is None or landed.returncode != 0:
            errors.append("landed cleanup commit is not reachable from the clean main checkout")


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
    missing_root = sorted(ROOT_FIELDS - set(card))
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
                errors.append("todo record digest is stale or conflicting")

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
    if not nonempty(card.get("overrun_cause")):
        errors.append("overrun_cause must be explicit, including 'none'")

    verification_verdict = card.get("verification_verdict")
    if verification_verdict not in VERIFICATION_VERDICTS:
        errors.append("verification_verdict must be passed, failed, or not-run")
    else:
        evidence("verification", verification_verdict, card.get("verification_evidence"), errors)

    attempt = card.get("attempt")
    source_attempt: dict[str, Any] | None = None
    ended_at: datetime | None = None
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
            if (
                not isinstance(attempt[field], str)
                or ACTUAL_DURATION.fullmatch(attempt[field]) is None
            ):
                errors.append(f"attempt.{field} must be an exact compact duration")
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
            if any(field in source_attempt for field in SETTLEMENT_FIELDS):
                errors.append("owning attempt is already partially or fully settled")
            started_at = timestamp(
                source_attempt.get("started_at"), "owning attempt started_at", errors
            )
            if started_at is not None and ended_at is not None and ended_at < started_at:
                errors.append("attempt.ended_at precedes the owning attempt start")
    if issued_at is not None and ended_at is not None and issued_at < ended_at:
        errors.append("issued_at precedes attempt.ended_at")

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
    if not isinstance(debt, list):
        errors.append("quality_debt must be an explicit array")
    else:
        for index, item in enumerate(debt, 1):
            if not isinstance(item, dict) or set(item) != DEBT_FIELDS:
                errors.append(f"quality_debt {index} must use the todo debt fields exactly")
                continue
            if item.get("attempt") != attempt_id or not all(
                nonempty(value) for value in item.values()
            ):
                errors.append(f"quality_debt {index} is incomplete or names the wrong attempt")

    lane = card.get("lane")
    source_lane: dict[str, Any] | None = None
    if not isinstance(lane, dict):
        errors.append("lane must be one TOML table")
        lane = {}
    elif set(lane) - LANE_FIELDS:
        errors.append(f"unknown lane field: {', '.join(sorted(set(lane) - LANE_FIELDS))}")
    if lane.get("state") not in TERMINAL_LANE_STATES:
        errors.append("lane.state must name an explicit terminal disposition")
    if record is not None:
        lanes = record.get("lane", [])
        if not isinstance(lanes, list):
            lanes = []
        if lane.get("state") == "none":
            if lanes or set(lane) != {"state"}:
                errors.append("lane state none conflicts with the owning record")
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
                source_lane = matches[0]

    cleanup = card.get("cleanup")
    if not isinstance(cleanup, dict):
        errors.append("cleanup must be one TOML table")
        cleanup = {}
    else:
        for field in sorted(set(cleanup) - CLEANUP_FIELDS):
            errors.append(f"unknown cleanup field: {field}")
    cleanup_authorized = cleanup.get("authorized")
    actions = cleanup.get("actions")
    if type(cleanup_authorized) is not bool:
        errors.append("cleanup.authorized must be true or false")
    if (
        not isinstance(actions, list)
        or not all(isinstance(action, str) and action in CLEANUP_ACTIONS for action in actions)
        or len(set(actions)) != len(actions)
    ):
        errors.append("cleanup.actions must be unique remove-worktree/delete-branch actions")
        actions = []
    if cleanup_authorized is False:
        if actions:
            errors.append("cleanup actions are unauthorized")
        if set(cleanup) - {"authorized", "actions"}:
            errors.append("unauthorized cleanup cannot carry authority or disposition fields")
    elif cleanup_authorized is True:
        ready = True
        if not actions:
            errors.append("authorized cleanup needs at least one exact action")
            ready = False
        if cleanup.get("authorized_by") != authorized_by:
            errors.append("cleanup authorized_by must equal the product owner")
            ready = False
        if not nonempty(cleanup.get("reason")):
            errors.append("authorized cleanup needs an explicit reason")
            ready = False
        if lane.get("state") not in CLEANUP_STATES:
            errors.append("cleanup requires a landed, superseded, or race-loser lane")
            ready = False
        if cleanup.get("lane_state_after") != "reaped":
            errors.append("authorized cleanup must explicitly set lane_state_after to reaped")
            ready = False
        if lane.get("state") == "race-loser" and attempt.get(
            "race_outcome"
        ) not in {"lost", "loser"}:
            errors.append("race-loser cleanup conflicts with race_outcome")
            ready = False
        if source_lane is None or not isinstance(commit, str) or COMMIT.fullmatch(commit) is None:
            ready = False
        if ready:
            validate_cleanup_worktree(lane, commit, actions, errors)

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
    print("SettlementCard valid: exact attempt evidence and cleanup authority admitted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
