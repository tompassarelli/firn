---
name: estimate-reference
description: >-
  Calibration receipt, canonical observation, comparability, and idempotency
  reference for estimate-distilled. Load only when that skill routes here
  through `agents path estimate-reference`; this is not the trigger or minimum
  workflow for giving an agent ETA.
---

# Estimate reference

The distilled skill owns forecast formation, execution bounds, and the minimum
close-the-loop workflow. `todo-distilled` owns shared attempt and terminal
record contracts.

## Forecast evidence

The calibration file is concise Markdown with TOML front matter. An in-flight
entry is only a pointer to the owning live attempt, never a second work tracker.
Same-class model-specific samples support the point when enough exist;
otherwise use a clearly labeled same-class cross-model sample. The reported
sample count includes only comparable completed observations.

## Terminal settlement

At a terminal worker boundary, the product owner fixes the terminal facts and
updates any independently required durable record directly. North separately
settles process, delivery, driver, and parent/child run state through
`agent-run-lifecycle-distilled`.

Replace the in-flight pointer with one completed receipt keyed by
`<record_id>/<attempt_id>` using the canonical field order below. Apply it as an
atomic keyed update after the complete terminal todo-record replacement.

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

## Comparability and key behavior

Calibration cohorts require the same observation source and the same
`assistant-turn` and `admitted-tool-call` units. Observations with `coverage =
"unknown"` remain visible but do not enter count- or mode-based cohorts.
Provider-turn and provider-tool-item facts are different units and cannot be
merged into these cohorts; unknown coverage cannot establish a zero or standard
mode sample.

A stable receipt key appears once. An identical receipt is an idempotent replay;
a different receipt at the same key is a conflict. Settlement does not rewrite
another receipt or add calibration prose.
