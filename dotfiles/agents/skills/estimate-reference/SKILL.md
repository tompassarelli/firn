---
name: estimate-reference
description: >-
  Full estimate notes for comparable forecasts, uncertainty, and optional durable calibration receipts.
---

# Estimates: full notes

## Forecast from work, not model mythology

Separate active execution from queueing, external waits, downloads, and
verification. Use comparable completed observations when available; otherwise
label the estimate uncertain and use the current work's measurable parts.
Do not derive machine time from an invented human-time multiplier.

An estimate predicts completion. A checkpoint selects when to inspect progress.
A hard limit bounds resource use or authority. Confusing them causes premature
cancellation and repeated setup. At an unexpected delay, inspect the existing
run; elapsed time alone does not establish a stall.

## Comparable samples

Use same-class model-specific samples when enough exist; otherwise label
same-class cross-model evidence. Count only comparable completed observations.
Version, workload, cache, hardware, and observation units may explain a sample
difference; do not attribute it to model capability without evidence.

## Durable calibration when independently needed

An ordinary ETA does not require a Todo task or calibration program.
When an existing resumable attempt uses calibration, keep its Markdown/TOML
in-flight entry as a pointer, not a second tracker. At terminal work the product
owner fixes the facts; the run host separately settles process and delivery.

Replace the pointer with one completed receipt keyed by
`<record_id>/<attempt_id>`, after the complete terminal Todo replacement.
Preserve observed facts and unknowns; do not guess model identity.

## Receipt schema

Render fields in this order:

1. ended-at;
2. seam and class;
3. wall estimate and actual;
4. agent estimate and actual;
5. queue/block actual and verification actual;
6. model, reasoning, route, role, and assignment ID;
7. outcome, overrun cause, and race outcome;
8. reviewed commit, outcome, and summary;
9. reviewer model and reasoning, then review repair actual;
10. canonical execution-observation JSON;
11. exact quality-debt entries.

Preserve execution-segment array order while sorting object keys in canonical
JSON. Render an absent optional value as `none`, including an absent optional
overrun cause. Reject carriage returns or line feeds in direct text fields;
structured values rely on canonical JSON escaping. Do not add provider actuals,
paraphrase supplied values, or serialize the derivable wall-time ratio.

## Comparability and idempotency

Calibration cohorts require the same observation source and the same
`assistant-turn` and `admitted-tool-call` units. Observations with `coverage =
"unknown"` remain visible but do not enter count- or mode-based cohorts.
Provider-turn and provider-tool-item facts are different units and cannot be
merged into these cohorts; unknown coverage cannot establish a zero or standard
mode sample.

A stable receipt key appears once. An identical receipt is an idempotent replay;
a different receipt at the same key is a conflict. Settlement does not rewrite
another receipt or add calibration prose.
