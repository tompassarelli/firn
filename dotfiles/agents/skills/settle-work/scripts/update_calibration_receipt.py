#!/usr/bin/env python3
"""Atomically insert or confirm one deterministic keyed calibration receipt."""

from __future__ import annotations

import argparse
import fcntl
import os
from pathlib import Path
import sys
import tempfile

from validate_settlement_card import receipt_from_valid_card, validate


def _update_receipt_locked(ledger: Path, key: str, receipt: str) -> str:
    raw = ledger.read_text(encoding="utf-8")
    prefix = f"- `{key}` — "
    matches = [line for line in raw.splitlines() if line.startswith(prefix)]
    if len(matches) > 1:
        raise ValueError(f"calibration receipt key occurs more than once: {key}")
    if matches:
        if matches[0] != receipt:
            raise ValueError(f"calibration receipt conflicts for key: {key}")
        return "already exact"

    lines = raw.splitlines(keepends=True)
    headings = [index for index, line in enumerate(lines) if line.rstrip("\r\n") == "## Receipts"]
    if len(headings) != 1:
        raise ValueError("calibration ledger must contain one exact ## Receipts heading")
    newline = "\r\n" if "\r\n" in raw else "\n"
    insertion = headings[0] + 1
    block = [newline, receipt + newline]
    updated = "".join(lines[:insertion] + block + lines[insertion:])

    mode = ledger.stat().st_mode
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=ledger.parent,
        prefix=f".{ledger.name}.",
        delete=False,
    ) as handle:
        temporary = Path(handle.name)
        try:
            handle.write(updated)
            handle.flush()
            os.fsync(handle.fileno())
            os.chmod(temporary, mode)
            os.replace(temporary, ledger)
        finally:
            if temporary.exists():
                temporary.unlink()
    return "updated"


def update_receipt(ledger: Path, key: str, receipt: str) -> str:
    directory = os.open(ledger.parent, os.O_RDONLY)
    try:
        fcntl.flock(directory, fcntl.LOCK_EX)
        return _update_receipt_locked(ledger, key, receipt)
    finally:
        os.close(directory)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="atomically update one deterministic calibration receipt"
    )
    parser.add_argument("card", type=Path)
    parser.add_argument("ledger", type=Path)
    parser.add_argument(
        "--todo-root",
        type=Path,
        default=Path.home() / "code" / "todo",
        help="admitted flat todo root (default: ~/code/todo)",
    )
    args = parser.parse_args(argv)
    card = args.card.resolve()
    todo_root = args.todo_root.expanduser().resolve()
    ledger = args.ledger.expanduser().resolve()
    if ledger != todo_root / "estimate-calibration.md":
        print(
            "calibration receipt not updated: ledger must be the admitted estimate-calibration.md",
            file=sys.stderr,
        )
        return 1
    errors = validate(card, todo_root)
    if errors:
        for error in errors:
            print(f"SettlementCard invalid: {error}", file=sys.stderr)
        return 1
    key, receipt = receipt_from_valid_card(card, todo_root)
    try:
        outcome = update_receipt(ledger, key, receipt)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"calibration receipt not updated: {error}", file=sys.stderr)
        return 1
    print(f"calibration receipt {outcome}: {key}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
