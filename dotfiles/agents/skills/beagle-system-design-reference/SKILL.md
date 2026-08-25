---
name: beagle-system-design-reference
description: >-
  Detailed identity, provenance, degraded-visibility, incremental-path, and
  proposal-checklist reference for beagle-system-design-distilled. Load only
  when that skill routes here through `agents path beagle-system-design-reference`;
  this is not the trigger or minimum workflow for Beagle system design.
---

# Beagle system design reference

The distilled skill owns the workflow and constraints. Use this reference to
resolve a design detail without creating a second rule source.

## Identity and provenance distinctions

A useful identity is local to semantic content and actual dependencies. Whole
root identity answers completeness or drift questions; it is too broad to
explain which closure may be reused or which dependent must be invalidated.

Keep these fact classes distinguishable even when one typed model represents
them:

- declared inputs;
- derived conclusions;
- observations;
- intents and authorizations;
- attempts and effect receipts;
- observations made after an effect.

Two values being equal says nothing by itself about truth, trust,
authorization, or completion. Likewise, logical unity does not erase process,
transaction, Store-space, trust-domain, secret-store, failure-domain, or
external-system boundaries.

## Visibility under persistence failure

A read-only operator surface can retain a validated live observation when its
persistence step fails. The display should identify its source, freshness, and
unpersisted status and produce an explicit degraded verdict. The authoritative
automation path has a different question: whether an admitted persisted form
exists. This separation supports two complementary checks:

1. persistence failure does not erase honest operator visibility; and
2. the same observation cannot influence routing, admission, scheduling,
   effects, caches, projections, or fallback decisions.

## Interrogate proposed machinery

For a cache, daemon, wrapper, sidecar, timestamp, global hash, compatibility
layer, or bespoke row schema, write down:

| Question | Design evidence |
| --- | --- |
| What decision is missing? | One query or decision the current model cannot express |
| What semantic element is absent? | Fact, identity, dependency, provenance edge, or query |
| Who owns it? | Module or selected closure |
| What makes it equal? | Smallest semantic equality contract |
| What boundary is crossed? | Authorization, process, transaction, trust, secret, failure, or external system |
| What remains physical? | A derived projection or executor keyed by the semantic model |

File layout, timestamps, process lifetime, and opaque hosted state are poor
proxies for answers in this table.

## Trace the complete path

Trace the same identity from compiler derivation through build, test, watch,
package, deployment, and downstream orchestration. For each stage, record its
query or derivation, actual dependencies, typed artifact, and whether it remains
pure or crosses an effect boundary. A physical executor may carry out a typed
plan; it should not reconstruct a semantic decision from filesystem or process
state.

For incremental behavior, compare clean and warm runs over the same declared
world. Inspect semantic results, typed artifacts, and effect plans, then change
one identity and observe its dependent and independent closures. The
`verification` skill selects the concrete instrument; this reference does not
prescribe a cache, daemon, timing target, or test apparatus.

## Proposal record

A complete design record includes:

- authoritative facts and their owner;
- semantic identity and equality boundary;
- derivation or query;
- actual dependency edges;
- physical and authorization boundaries;
- intent, authorization, attempt, receipt, and later-observation handling for
  effects;
- clean-versus-warm equality and invalidation acceptance statements.
