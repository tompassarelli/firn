---
name: code-as-facts
description: >-
  Use when editing a Beagle source file whose UPSTREAM is the fact GRAPH (code-as-facts) — one listed in the
  graph-upstream registry or whose leading comment block carries
  `;; @upstream:graph`. Its text is a regenerable view of the Fram fact
  graph: author by GRAPH EDIT via the mcp__fram__* tools, never
  Edit/Write/MultiEdit (a PreToolUse guard refuses text edits). NOT for
  ordinary Beagle files or non-adopted modules.
---

# Graph-native authoring — the graph is the editing surface

Most Beagle files are text-canonical: you Edit/Write the text and the compiler
reads it. A **graph-upstream** file is the inverse (the move-3 flip): its source
of truth is the **Fram fact graph**, and the on-disk `.bclj` is a *regenerated
downstream view* — like a file that a formatter owns. Editing such a file as text
desyncs the graph from the bytes, so the deterministic **PreToolUse guard refuses
Edit/Write/MultiEdit** on it. This skill is the model half: for these files you
author by **graph edit**.

## 0. Is this file graph-upstream? (when this skill applies)

A file is graph-upstream iff EITHER:
- its absolute path is listed in `$GRAPH_UPSTREAM_REGISTRY`
  (default `~/.config/fram/graph-upstream-files`) — the authoritative marker, OR
- its **leading comment block** contains the sentinel `;; @upstream:graph`
  (the in-band, travels-with-the-file marker; it survives the lossless round-trip,
  landing just after the regenerated `(define-target clj)` header).

If neither holds, this skill does NOT apply — use the **beagle-authoring** skill
and ordinary Edit/Write. (Adoption of a **brownfield/text-upstream** file is
per-file and opt-in — there is no blanket "all .bclj" rule; **greenfield** new
Beagle work defaults graph-native at inception per
`nixos-config:dotfiles/agents/AGENTS.md` "New code", so opt-in language
does not apply there. The honest line: code *can* be graph-upstream — see
`beagle:bin/test/code-as-facts/README.md` "Capability vs adoption".)

## 1. The graph-edit verbs (use these instead of Edit/Write)

The authoring engine is `fram:resolve.clj` (modes
`upsert-form` / `set-body` / `rename` / `delete`), exposed AI-facing over the fram
MCP server. Each is a genuine fact operation on the lossless AST projection,
**recompile-gated and fail-closed** — an edit that the engine refuses, or that
does not recompile, writes no tree.

| Intent | Tool | Notes |
|---|---|---|
| Add a new top-level def | `mcp__fram__add-def` | `upsert-form` with a new name; appends a wrapper `fN` edge |
| Replace a def by name | `mcp__fram__add-def` | `upsert-form` with an existing name; supersedes its `fN` edge |
| Replace a defn's body | `mcp__fram__set-body` | supersedes the post-params `fN` edges |
| Rename a def | `mcp__fram__rename-def` | O(1), scope-correct via `refers_to`, shadow-safe |
| Insert a form after an anchor | `mcp__fram__insert-after` | ordered placement |
| Delete a def | _(engine verb `delete` exists; MCP tool not yet exposed)_ | fail-closed on orphaned references |

The new form/body is **structured data you emit** (an EDN datum, the structured
edit spec — e.g. `(defn add-two [x :- Int] :- Int (base (+ x 2)))`), not a text
splice. It is minted into the same Fram store as `kind`/`v`/`fN` facts, and any
reference in it resolves via the same lexical walk — so it is scope-correct for
free (a later rename of a callee propagates into the code you just authored).

> If the guard denies and the `mcp__fram__*` verbs are somehow absent, surface
> the gap — never fall back to text Edit on a guarded file. (Server entry:
> `fram:bin/fram-mcp`.)

## 2. The loop (what each verb does under the hood)

```
.bclj  --emit-edn-->  lossless AST facts  --(resolve.clj <verb>)-->  edited facts
       <--render-- (byte-stable regenerated .bclj, recompile-gated) <--
```

The CLI form the MCP tools wrap (for grounding / manual runs):

```sh
# project the module to lossless AST-facts EDN
racket beagle:beagle-lib/private/facts-roundtrip.rkt --emit-edn <file.bclj> > a.edn
# apply the graph edit (writes the rendered projection to $RESOLVE_OUT)
bb -cp fram:out fram:resolve.clj set-body <name> <scope> <body.edn> a.edn
# regenerate byte-stable text + recompile-gate (committed only if it builds)
racket beagle:beagle-lib/private/facts-roundtrip.rkt --render "$RESOLVE_OUT/resolved-<file>.edn"
```

The CI gate that proves all of this is GREEN:
`beagle:bin/test/code-as-facts/authoring-verbs.sh`.

## 3. If you genuinely must edit text

Adoption is reversible and deliberate. To edit a graph-upstream file as text you
must first **de-adopt** it (remove its path from `$GRAPH_UPSTREAM_REGISTRY` and
drop the `;; @upstream:graph` sentinel). That is a workflow decision, not a
per-edit escape hatch — make it explicitly, then the guard allows text edits again.

The family: Beagle text edits → beagle-authoring · graph-upstream files
(graph edit channel) → code-as-facts · relational code queries
(blast zone / who-calls) → codegraph · building apps on the engine →
fact-modeling. Loop vocabulary: `beagle:docs/authoring-loops.md`.
