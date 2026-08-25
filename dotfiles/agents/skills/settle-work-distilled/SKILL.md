---
name: settle-work-distilled
description: >-
  Mechanically settle terminal delegated work from a product-owner-issued
  SettlementCard. Use when a worker result reaches a terminal boundary and its
  exact todo attempt fields, estimate receipt, and lane state must be applied
  without transferring integration, review, verdict, or publication judgment.
---

# Settle work, distilled

Apply one immutable owner-issued SettlementCard as bounded bookkeeping. The
product owner retains every product verdict and disposition decision.

## Hard boundaries

- Use one fresh minimal-context clerk per card, supervised and reaped by the
  owner. Load only this skill pair, the card, exact todo record, `todo` field
  contract, and estimate-calibration ledger.
- Validate with bundled `scripts/validate_settlement_card.py` before mutation.
  Stop `UNSETTLED` on any stale/conflicting/missing fact unless the complete
  todo target is already exact and only its receipt remains.
- Never repair or infer card fields, inspect product history for answers, choose
  a verdict, integrate, review, publish, activate, rewrite history, operate on
  lanes/branches, or broaden the task.
- Preserve forecast/staffing fields. Apply terminal attempt fields, exact debt,
  and named lane state as one complete atomic todo-record replacement; never
  expose or reconcile a subset.
- Only after that replacement succeeds, run bundled
  `scripts/update_calibration_receipt.py` for one atomic deterministic keyed
  receipt update. An existing identical receipt is success; a conflict stops.

## Minimum workflow

1. Validate the card against its named authoritative files.
2. Construct the entire revised todo record in memory and atomically replace it.
3. Update or confirm the keyed calibration receipt with the bundled script.
4. Re-read both targets and confirm only the authorized attempt fields, debt,
   lane state, and receipt changed.
5. Return one line naming record/attempt, exact commit, final lane state, and
   whether the receipt was updated or already exact; otherwise return
   `UNSETTLED` with the narrow validator diagnostic.

The acknowledgement closes the clerk; never settle the settlement clerk.

For validator admission detail, interruption/replay states, atomicity checks,
and acknowledgement examples, run `agents path settle-work-reference` and read
the returned skill completely before executing a settlement.
