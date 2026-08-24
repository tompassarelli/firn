---
name: settle-work
description: >-
  Mechanically settle terminal delegated work from a product-owner-issued
  SettlementCard. Use when a worker result reaches a terminal boundary and its
  todo attempt, estimate receipt, lane state, or explicitly authorized lane
  cleanup must be applied without transferring integration, review, verdict,
  publication, or cleanup judgment.
---

# Settle work

Apply one owner's terminal decisions without making new product decisions. The
product owner retains integration, verification, review, publication, verdict,
and cleanup authority; this skill owns only bounded bookkeeping.

## Admit the card

1. Start from fresh context. Load this skill, the card, its exact owning todo
   record, the `todo` field contract, and the estimate-calibration ledger. Load
   `repo-safety` only when the card authorizes lane cleanup.
2. Run this skill's bundled `scripts/validate_settlement_card.py` against the
   card before editing anything. The `todo` skill owns the SettlementCard and
   receipt schema; do not reconstruct or extend it here.
3. Stop on a stale record digest, wrong record or attempt, conflicting evidence,
   missing value, or invalid cleanup authority. Return the validator's narrow
   diagnostic. Never repair the card, select a more favorable verdict, estimate
   a missing duration, or infer that a lane is disposable.

Use no product history beyond the card and named authoritative files. A full
conversation fork is not settlement input.

## Apply the exact bookkeeping

Preserve the attempt's forecast and staffing fields. Copy only the card's
terminal attempt fields into that same attempt, add its exact quality-debt
entries, update the named lane to the card's target state, and refresh the todo
record's current state and Verification section from the supplied evidence.
Do not turn an evidence reference into a stronger claim.

Replace the attempt's in-flight estimate pointer with one terminal calibration
receipt. Copy the shared fields from the owning attempt, the card's overrun
cause, and only exact review, race, debt, and provider actuals already present
in the card or authoritative record. The `todo` and `estimate` skills remain
the field authorities.

Re-read both changed records and verify that the named attempt and lane are the
only live-work facts changed. If either authoritative file moved after card
validation, stop and request a replacement card instead of reconciling it.

## Perform only authorized cleanup

An empty cleanup action list means no cleanup. For a non-empty list, require the
validator's clean-worktree proof and exact owner authorization, then perform
only the listed worktree and branch actions through the repository's sanctioned
`repo-safety` path. Record the card's explicit post-cleanup lane state only
after every authorized action succeeds. On any failure, preserve the lane and
report the exact remaining action.

Never integrate, review product code, publish, activate, rewrite history,
remove unlisted files, clean a different lane, or broaden the task. A cleanup
denial changes the cleanup path; it does not authorize bypassing a guard.

## Acknowledge tersely

Return one line naming the record and attempt, exact commit, final lane state,
cleanup disposition, and whether the calibration receipt was updated. Report
`UNSETTLED` instead when any requested fact or action remains unapplied.
