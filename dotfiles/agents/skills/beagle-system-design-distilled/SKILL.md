---
name: beagle-system-design-distilled
description: >-
  Design Beagle compiler, Store, incremental-build, effect, or orchestration boundaries before adding infrastructure to compensate for missing semantics.
---

# Beagle system design

Identify the missing decision or query, authoritative facts, semantic owner,
equality contract, dependencies, and physical or authorization boundary.
Repair that boundary before adding a cache, daemon, wrapper, or opaque schema.

Keep typed Beagle and canonical Store Triples authoritative. Host code is for
bootstrap and irreducible foreign execution. Key reuse and invalidation by
local semantic content and dependencies, not a whole-root hash.
Use `fact-modeling-distilled` for Store modeling.

Equality establishes neither truth nor trust, authorization, or completion.
Separate operator visibility, persistence, and automation eligibility; effects
require intent, authorization, attempt, and receipt.

For affected incremental behavior, compare clean and warm results and plans
for the same world, then verify only dependents invalidate. Use
`verification-distilled` for the check. For identity and effect design detail,
use `agents path beagle-system-design-reference`.
