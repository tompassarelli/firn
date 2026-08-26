---
name: beagle-system-design-distilled
description: >-
  Design or review Beagle architecture and system changes across the compiler,
  Store identity and provenance, incremental builds, test/watch/package/deploy
  planning, effects, and downstream orchestration. Use especially before adding
  caches, daemons, wrappers, hosted sidecars, timestamps, global compiler
  hashes, compatibility layers, or opaque row schemas to solve a Beagle problem.
---

# Beagle system design

Name the unexpressed decision, missing fact or query, owner, equality contract,
dependencies, and authorization or physical boundaries. Fix that semantic
boundary before infrastructure; use `fact-modeling-distilled` for Store Triples.

Keep native typed Beagle and canonical Store Triples authoritative. Host code
may bootstrap or execute irreducible edges, never become a second authority.
Key reuse and invalidation by local content and dependencies, not a whole-root
hash. Identity does not imply truth, trust, authorization, or completion.

Separate visibility, persistence, and automation eligibility. Unpersisted
evidence may be labeled for operators, but automation fails closed without its
admitted form. Keep effects behind intent, authorization, attempt, and receipt.

Complete only with those facts and clean/warm acceptance: equal semantic
results and plans for one world, with changes invalidating only dependents.
Route unresolved detail to the reference skill only for an explicit request or
a named unresolved question; use `verification-distilled` for evidence.
