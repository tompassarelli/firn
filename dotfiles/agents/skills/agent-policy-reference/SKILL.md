---
name: agent-policy-reference
description: >-
  Full policy notes for loading layers, catalog authority, registration, and activation evidence.
---

# Agent policy: full notes

## One owner, several surfaces

A source declaration owns a rule; a catalog identifies it; a generation resolves
its activity; provider surfaces project it. Copies and symlinks are delivery
mechanisms, not new authorities. Start with live evidence:

```text
agents status
agents inspect <id>
agents path <id>
```

Correlate the reported owner with its actual source catalog and operator
overlay. Do not hardcode a catalog path or repository topology from an older
North version. The Firn client delegates resolution and projection to North;
it is not a second catalog/resolver.

## Choose the loading layer

| Need | Owner |
| --- | --- |
| Boundary governing every matching action | nearest applicable AGENTS.md |
| Coherent reliably triggered workflow | one skill |
| Several registered units enabled together | module |
| Deterministic provider-event enforcement | hook |

Instruction/template distributions attach to catalogued units; they are not
extra unit kinds. Modules compose existing identities, never hidden members.

## Distilled and full notes

Discovery descriptions state the trigger cheaply. The distilled guide contains
the complete normal decision path and essential boundaries. Full notes retain
reasoning, exact protocols, examples, counterexamples, alternatives, and
explicitly labeled open questions for future re-distillation.

Do not force a model to read both layers for routine work. Split a long reference
where different questions select different topics; retain a short index with
read conditions. Avoid one file per heading when several sections are always
used together. Do not turn exploratory reasoning into adopted requirements.

## Registration and enforcement

Use skill-creator for frontmatter, matching IDs, useful resources, and metadata/
link validation. Register the exact owner once. Shape validation does not prove
the rule selects the right action.

A hook's catalog support relations and provider event wiring belong outside
skill prose. A lifecycle wrapper keeps its actual event and consumes resolved
activity; it does not recompute module closure or pretend to be PreToolUse.
Follow guard-authoring for changes to executable enforcement.

## Permission, activity, and activation

Stored permission says a unit may run; resolved activity also incorporates
active parents or supported claimants. North resolves provenance once, writes
a private generation, and atomically advances the current selector.

After required owner/catalog commits land and clean source checkouts are
current, use `agents sync`. Change permission with `agents on <id>` only
when enablement is requested or required by the authorized workflow; editing
a reference does not authorize enabling it.

Inspect status, owner, activity, generation/digest, and provider activation
paths from the live client. Resolve paths to landed authority, not a lane or
hand-edited projection. Stop on ambiguous identity or unlanded source.
Skill-only out-of-store activation does not require a NixOS rebuild.
