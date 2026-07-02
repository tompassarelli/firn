---
name: codegraph
description: >-
  Use when you need RELATIONAL code-intelligence over a BEAGLE source tree
  (.bjs/.bclj/.bnix) — scope-correct "who calls THIS x", transitive blast
  radius / leverage, the real call graph. The codegraph module (chartroom/)
  projects the AST into a Fram claim graph; Datalog derives the answer.
  Formerly named code-as-claims. NOT for arbitrary-language repos, plain
  string search, or a single-file lookup (grep wins there).
---

# Codegraph — relational code-intelligence over Beagle source

The ecosystem: **Beagle** is the language; **Fram** is the claim engine (a
subject-predicate-object graph + a stratified Datalog); the **codegraph module**
(`fram/chartroom/` — directory rename pending) is the glue that projects Beagle
source *into* Fram so you can ask relational questions the way Tern asks them
about work. Same graph substrate, pointed at code. This is the **blast zone**
faculty: edit diagnostics consulted BEFORE proposing a change.

## When to reach for the graph (and when not to)

Grep / `beagle callers` (bare-symbol, one-hop) is **scope-blind and one-hop**.
On the live gjoa corpus the Fram graph beat it decisively (RESULTS.md):

- **Scope-correct callers** — "who calls *this* `red`?" when `red` is a distinct
  `defn` in two modules. Graph precision **1.00**; bare-symbol **0.33–0.67**
  (it merges the two). A call binds the defn in its OWN module; the graph knows
  lexical scope, text match doesn't.
- **Transitive blast radius / leverage** — the full closure of "what breaks if I
  change Y". A one-hop tool **structurally cannot** compute this; Fram's Datalog
  does (real call-graph transitive closure).

So reach for it when the question is **relational** (callers-in-scope,
dependents, transitive impact, call graph) on **Beagle source**. Do NOT spin it
up for "find the string `foo`" or a single-file read — grep wins on cost there.

## The pipeline

```
*.bjs/.bclj/.bnix ──beagle-claims──▶ [subj "pred" obj] ──fold──▶ Fram store ──Datalog──▶ callers / leverage
   (AST, any #lang)                  EDN triples            (interned graph)   (transitive closure)
```

```sh
# 1. project a source tree → claim triples  (chartroom uses beagle's bin/beagle-claims)
cd ~/code/fram/chartroom          # chartroom folded INTO fram (ADR 0001); was ~/code/chartroom
bin/emit-corpus  ~/code/<proj>/src ~/code/<proj>/tools  build/<proj>.claims
# 2. fold into Fram + derive the namespace-correct call graph / leverage
bb -cp ~/code/fram/out  src/chartroom.clj  build/<proj>.claims
```

For ad-hoc relational queries beyond chartroom's built-in benchmarks, query the
Fram store directly — Fram exposes an **AI-native surface** (a generated tool
catalog + a structured/validated Datalog query, served over MCP) so you ask for
tuples (joins, transitive closure) and the boundary rejects malformed/unsafe
queries rather than running them.

## Honest scope + status

- **Beagle source only.** `beagle-claims` reflects `.bjs`/`.bclj`/`.bnix` ASTs
  (ignoring each file's `#lang`). It is NOT a general multi-language indexer.
- **It's validated glue, not a turnkey IDE.** Headline gates hold (1100/1100
  forms, 97/97 files; leverage axis validated on gjoa). But it needs **fram**
  checked out (build `fram/out`; **chartroom now lives at `fram/chartroom`**, folded
  per ADR 0001 — no longer a standalone repo) and **beagle** (provides
  `bin/beagle-claims`), plus `bb` on PATH.
- **Two projections, two jobs:** the *query* projection (`beagle-claims`, ~18
  triples/form) is compact + great for leverage but lossy (drops types/params);
  the *truth* projection (`beagle-roundtrip`, ~238/form) round-trips the program
  losslessly (the graph as source of truth, text as a regenerable view). Use the
  query projection for code-intelligence; the truth projection for graph-native
  edits/rename.

The bet (shared with Tern): a flat text-and-grep view rots and can't compute
relational questions; the graph is always current and answers them for free.

The family: Beagle text edits → beagle-authoring · claim-canonical files
(graph edit channel) → claim-canonical-authoring · relational code queries
(blast zone / who-calls) → codegraph · building apps on the engine →
claim-modeling (or `~/code/fram/bin/fram-primer` for the live cheatsheet).
Loop vocabulary: `~/code/beagle/docs/authoring-loops.md`.
