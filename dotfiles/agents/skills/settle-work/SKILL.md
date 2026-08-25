---
name: settle-work
description: >-
  Mechanically settle terminal delegated work from a product-owner-issued
  SettlementCard. Use when a worker result reaches a terminal boundary and its
  exact todo attempt fields, estimate receipt, and lane state must be applied
  without transferring integration, review, verdict, or publication judgment.
---

# Settle work

Apply one owner's terminal decisions without making new product decisions. The
product owner retains integration, verification, review, publication, and
verdict authority; this skill owns only bounded bookkeeping.

## Admit the card

1. Start from fresh context. Load this skill, the card, its exact owning todo
   record, the `todo` field contract, and the estimate-calibration ledger.
2. Run this skill's bundled `scripts/validate_settlement_card.py` against the
   card before editing anything. The `todo` skill owns the SettlementCard and
   receipt schema; do not reconstruct or extend it here.
3. Stop on a stale record that still needs mutation, wrong record or attempt,
   conflicting prior field, conflicting evidence, or missing value. Return the
   validator's narrow diagnostic. Never repair the card, select a more favorable
   verdict, estimate a missing duration, or infer a lane disposition.

Use no product history beyond the card and named authoritative files. A full
conversation fork is not settlement input.

## Apply the exact bookkeeping

Preserve the attempt's forecast and staffing fields. Copy only the card's
terminal attempt fields into that same attempt, add its exact quality-debt
entries, and set the named lane to the card's exact state. Leave an already
equal field or debt entry unchanged; reject any conflicting or unlisted prior
terminal field. Do not edit Markdown sections or turn an evidence reference
into a stronger claim.

Replace the attempt's in-flight estimate pointer with the one deterministic
terminal calibration receipt defined by `estimate`. Derive it only from the
validated card and owning attempt, use the stable `<record_id>/<attempt_id>`
key, and leave an already identical receipt unchanged. Never paraphrase or add
a field. The `todo` and `estimate` skills remain the field authorities.

Re-read both changed records and verify that only the named attempt, its exact
debt entries, the named lane state, and the keyed receipt changed. If a target
moved after card validation and is not already exact, stop and request a
replacement card instead of reconciling it. Never integrate, review product
code, publish, activate, rewrite history, remove files, or broaden the task.

## Acknowledge tersely

Return one line naming the record and attempt, exact commit, final lane state,
and whether the calibration receipt was updated or already exact. Report
`UNSETTLED` instead when any requested fact remains unapplied.
