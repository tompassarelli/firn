---
name: settle-work-reference
description: >-
  Detailed settlement reference for card admission, validator diagnostics,
  atomic todo and receipt updates, replay-safe interruption states, final
  comparison, and acknowledgement shape. Use after settle-work-distilled
  routes here.
---

# Settle work reference

`settle-work-distilled` owns authority and stop conditions. This unit provides
the exact execution and replay procedure.

## Admission inputs

Start the clerk with only:

- the immutable SettlementCard;
- its exact owning todo record;
- the `todo` SettlementCard/attempt/receipt schema;
- `~/code/todo/estimate-calibration.md`;
- the bundled validator and receipt updater.

Run:

```text
scripts/validate_settlement_card.py CARD
```

The validator checks the record digest and identities, authorizer, chronology,
evidence/verdict agreement, review and debt, lane identity, duration relations,
terminal execution observation, comparable units, hashed joins, safe counts,
and coalesced segments. Return its narrow diagnostic for a mismatch.

## Atomic todo replacement

Copy only the card's terminal attempt fields into the named existing attempt,
preserving ordered execution-observation segments. Add exactly its quality-debt
entries and set exactly its named existing lane state. Leave already equal
fields and debt unchanged. Any conflicting or unlisted terminal field is a card
conflict.

Construct and validate the complete file before one replacement. Do not edit
the Markdown sections or strengthen evidence wording. If the mutation surface
cannot perform one replacement, stop before writing.

## Receipt update and replay

After the todo replacement, run:

```text
scripts/update_calibration_receipt.py CARD ~/code/todo/estimate-calibration.md
```

The updater revalidates the card, renders canonical JSON without reordering
segment arrays, and atomically updates the `<record_id>/<attempt_id>` key. It
accepts an identical receipt and rejects a different value at that key.

An interruption may expose only three valid boundaries:

1. original todo record and original ledger;
2. complete todo replacement with receipt pending;
3. complete todo replacement and exact receipt.

A stale record digest is replayable only in state 2 or 3. Partial terminal
fields, debt, or lane mutation are invalid and are not reconciled.

## Final comparison and acknowledgement

Re-read both files and compare against the card. If either target moved after
validation and is not already exact, request a replacement card. Otherwise
return exactly one compact line, for example:

```text
SETTLED <record-id>/<attempt-id> commit=<sha> lane=<state> receipt=<updated|already-exact>
```

If anything remains unapplied, return `UNSETTLED` plus the single narrow reason.
