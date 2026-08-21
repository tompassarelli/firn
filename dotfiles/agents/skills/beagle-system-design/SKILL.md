---
name: beagle-system-design
description: >-
  Design or review Beagle architecture and system changes across the compiler,
  Store identity and provenance, incremental builds, test/watch/package/deploy
  planning, effects, and downstream orchestration. Use especially before adding
  caches, daemons, wrappers, hosted sidecars, timestamps, global compiler
  hashes, compatibility layers, or opaque row schemas to solve a Beagle problem.
---

# Beagle system design

Follow Beagle's thesis to its coherent endpoint. Start from the missing semantic
boundary, not from conventional host machinery.

## Preserve one semantic architecture

- Keep normal and warm semantics in native typed Beagle over canonical Store
  Triples. Limit host code to cold bootstrap and irreducible OS or foreign
  edges that execute typed plans without becoming a second authority.
- Give modules, definitions, and selected closures identities local to their
  semantic content and actual dependencies. Use whole-root identity to audit
  completeness or drift, never as the causal key for reuse or invalidation.
- Use one identity and provenance model while distinguishing declared inputs,
  derived conclusions, observations, intents, authorizations, attempts, effect
  receipts, and later observations. Equality never implies truth, trust,
  authorization, or effect completion.
- Preserve logical unity without erasing physical or effect boundaries.
  Processes, transactions, Store spaces, trust domains, secret stores, failure
  domains, and external systems remain explicit even when one typed fact model
  explains them.

## Separate visibility from authority

- Model observation availability, persistence confirmation, and eligibility
  for automated decisions or effects as independent properties. Never collapse
  them into one health flag.
- A read-only operator surface may retain a validated live observation when
  persistence fails. Label its source, freshness, and unpersisted status, and
  return an explicit degraded verdict rather than discarding useful evidence.
- Routing, admission, scheduling, and effects consume only the admitted
  authoritative form and fail closed when it is absent. Unpersisted operator
  evidence must not enter caches, projections, or fallback paths that can
  influence automation.
- Prove both sides of the boundary: persistence failure preserves honest
  visibility, while the same observation remains ineligible for automation.

## Find the missing fact

Before proposing a file cache, daemon, wrapper, hosted sidecar, timestamp,
global hash, broad compatibility layer, or bespoke row schema, identify:

1. the decision or query the system cannot currently express;
2. the missing fact, semantic identity, dependency, provenance edge, or query;
3. the module or closure that owns it and the smallest equality contract it
   needs; and
4. any authorization or physical boundary crossed by consuming it.

Fix that semantic boundary first. Conventional machinery may remain as a
derived physical projection or executor only after its key and invalidation
rules are stated in those terms. Use `fact-normal-form` to design or admit the
Triples; do not invent a parallel fact discipline here.

## Design the whole path

Make compiler, build, test, watch, package, deployment, and downstream
orchestration stages query or derive from the same typed identities and
provenance. Do not let an integration reconstruct semantic decisions from file
layout, timestamps, process lifetime, or opaque hosted state. Keep planning
pure; cross into effects only through explicit intent, authorization, attempt,
and receipt boundaries.

Require this acceptance shape for incremental work:

- clean and warm execution produce equal semantic results, typed artifacts,
  and effect plans for the same declared world; and
- a changed identity invalidates its actual dependents while independent work
  remains reusable.

Use `verification` to choose the concrete equality and invalidation evidence.
Do not prescribe cache, daemon, timing, or test mechanics in this skill.

## Complete the design

A coherent proposal names the authoritative facts, identity/equality boundary,
derivation or query, actual dependency edges, effect boundary, and the clean
versus warm acceptance statement. If any is missing, keep designing before
adding infrastructure.
