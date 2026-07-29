---
name: beagle-authoring
description: >-
  Use WHENEVER writing, editing, or debugging Beagle source in ANY project —
  files ending .bclj/.bcljs/.bjs/.bnix/.bgl, starting with `#lang beagle`, or
  anything under ~/code/beagle. Establishes the repair loop is online and
  functionally working BEFORE coding; the compiler is the loop's oracle and
  the source of truth, never a static cheat sheet. NOT for relational queries
  over a Beagle tree — that's codegraph.
---

# Beagle authoring

Beagle is a typed authoring IR — **Clojure plus types**, compiled `parse →
check → emit` to Nix / Clj / CLJS / JS / Odin. The reason to author in Beagle
at all is the **repair loop**: pointed, structured errors and machine-applicable
repairs fed back fast. If that loop is offline or silently degraded, you are
writing Beagle blind. So the loop comes first.

## 0. Handshake — run this BEFORE writing any Beagle

```
beagle doctor --deep
```

- **"Repair loop: ok"** → proceed.
- **"Repair loop: DEGRADED" (exit 1)** → the feedback you'd rely on is not
  trustworthy. Do **not** start coding on silent green. Fix it:
  - daemon down → `beagle doctor --revive`  (or `beagle daemon start --watch .`)
  - no per-edit hook in this project → `beagle init --hooks` to scaffold the
    portable PostToolUse syntax/type-check hook, then re-run the doctor.
  - re-run `beagle doctor --deep` until green.

`beagle doctor` is a **functional** check, not a liveness check: it round-trips
known-bad **and** known-good inputs through syntax / type-check / suggestion→patch,
so it catches a checker stuck "always-pass" or "always-fail" — exactly the silent
degradation a process-exists check misses.

## 0.5 Greenfield bootstrap — start graph-native before substantive code

Starting a **wholly new** Beagle program/module (no existing file to edit)?
Per `~/code/nixos-config/dotfiles/agents/AGENTS.md` "New code": greenfield
**must start graph-native at inception**. First establish the compiler repair
loop in section 0, then run this bootstrap sequence:

1. **Seed only** — create the minimal seed/header, nothing more: the file's
   leading comment block carrying the `;; @upstream:graph` sentinel (or its
   path pre-registered in `$GRAPH_UPSTREAM_REGISTRY`, whose default is
   `~/.config/fram/graph-upstream-files`) plus whatever the
   `(define-target …)` header requires to exist on disk. No substantive form,
   definition, or body (`def`, `defn`, `defrecord`, and so on) gets
   text-authored here — the seed exists only to give the graph something to
   adopt.
2. **Flip the full repo** — run
   `fram:bin/fram-code-on ~/code/<repo>` to ingest the source, write the
   project wiring for both harnesses, and warm the coordinator.
3. **Confirm flip level 3** —
   `fram:bin/fram-code-status ~/code/<repo>` must report `level=3`
   (warm coordinator alive, not just L2 flipped-but-cold). L2/L1 mean the
   graph-edit loop is not live yet: re-run
   `fram:bin/fram-code-on ~/code/<repo>`, then start or restart a
   **trusted-project Claude Code or Codex session** in `~/code/<repo>` so its
   SessionStart/project config can load the MCP server. Verify that the
   `mcp__fram__*` graph-edit verbs are present before authoring.
4. **Hand off** — all substantive authoring past the seed goes through the
   **code-as-facts** skill
   (`~/code/nixos-config/dotfiles/agents/skills/code-as-facts/SKILL.md`) via
   the `mcp__fram__*` graph-edit verbs. Do not scaffold the module with
   ordinary Edit/Write "temporarily" then adopt later — the seed-only step
   above is the entire text-authored surface, permanently.

If `mcp__fram__*` is unavailable or flip level won't reach 3, that is a
**loop-repair problem** (revive the coordinator, restart the session), never
license to fall back to text Edit/Write on a greenfield graph-native module.

This skill (beagle-authoring, plain-text Edit/Write + the compiler loop) is for
**brownfield/text-upstream** Beagle files — an existing file not yet
graph-adopted, or one where the human chose text-upstream Beagle. Before any
brownfield migration, surface exactly these three choices: (1) keep the current
upstream/language for this bounded task, (2) migrate to text-upstream Beagle, or
(3) migrate directly to graph-upstream Beagle. Wait for the human's pick; never
start a migration side project automatically. If the decision is deferred,
record the candidate in a separate migration inventory. If you're unsure
whether the surface is greenfield or brownfield, that uncertainty itself is the
three-choice moment — surface it, don't default silently.

## 1. Heartbeat — keep it alive while coding

- The **PostToolUse hook** (installed by `beagle init --hooks`) is the only
  *harness-enforced* feedback — it fires on every Edit/Write. **Trust its
  output.** Fix syntax errors before type errors. Never hand-count parens —
  `beagle syntax` already counted them.
- If feedback ever goes **silent** mid-session, the loop degraded — re-run
  `beagle doctor --revive --quiet`.
- Optional background watchdog (this session): `/loop 10m beagle doctor --revive --quiet`
  — silent while healthy, loud + self-revives on degradation.

> Reliability note: a skill (this file) and CLAUDE.md are *model-discretion* —
> they can be forgotten. The **hook** is the deterministic layer. The handshake
> above exists to bootstrap that deterministic layer when you start.

## 2. The compiler is the source of truth — never trust a static list

There is **no** static reference for the **form set, type list, or stdlib** —
the surface churns daily; any cheat sheet of it is stale within a day. To learn
the *current* surface, **query the compiler**:

| question | tool |
|---|---|
| does this file parse? where? | `beagle syntax FILE` (`--ledger`, `--repair --emit-patch`) |
| does this file type-check? | `beagle check --agent FILE` |
| signature of X? | `beagle sig X FILE...` |
| fields of record R? | `beagle fields R FILE...` |
| who calls X? | `beagle callers X FILE...` |
| what does FILE export? | `beagle provides FILE` |
| change-impact of X? | `beagle impact X FILE...` |
| macro expansion? | `beagle expand FILE` |
| run tests | `beagle test` (active tier; `BEAGLE_ALL_TARGETS=1` for dormant) |
| compile | `beagle build FILE [OUT]` |
| is the repair loop healthy? | `beagle doctor [--deep]` |
| auto-repair | `beagle repair --emit-patch` (also `beagle-trace`, `beagle-blame`, `beagle-cascade`, `beagle-specfix`) |

For forms/types/stdlib themselves, **read the source** — never restate it:
`parse.rkt` (forms), `types.rkt` (types), `stdlib-*.rkt` (externs),
`extensions.rkt` (ext→target). The authoritative living anchor is
**`beagle:CLAUDE.md`** — read it when you start Beagle work in a session;
if the surface looks different than you expect, `git log` it.

> To *query* a Beagle codebase relationally (scope-correct callers, transitive
> blast radius / leverage, the call graph) rather than write it, see the
> **codegraph** skill — it projects the source into a Fram fact graph
> (Chartroom) and answers with Datalog, which beats grep/bare-symbol on exactly
> the relational questions text search can't compute.

## 3. Stable operating model (this does not churn)

- **Beagle is Clojure + types, nothing else.** Every divergence from Clojure
  must be load-bearing for the type system or a backend, or it gets removed.
- **Surface lock:** typed Clojure with inline `:-` annotations only —
  `(def x :- T v)`, `(defn f [p :- T ...] :- R body)`, `(defonce …)`,
  `(defrecord N [field :- T …])`. Interiors are inferred. `:` (Rust-style) and
  `(fact …)` are **hard-rejected**.
- **Zero external users → hard removal.** When a form/keyword is wrong, REMOVE
  it (pointed error naming the replacement) — never deprecate or alias.
- **Prefix where meaning diverges from Clojure:** `nix/assert`, `nix/with`,
  `nix/with-cfg` (bare `assert`/`with`/`with-cfg` are rejected). Bare names are
  reserved for forms that behave as their Clojure namesake.
- **Apply-and-report.** The spec is generative: run a form through the three
  rules (Clojure+types / load-bearing divergence / idiomatic-per-target) and one
  answer falls out. Fix the code and report what was measured — don't surface
  option menus for questions the spec already settles.

| extension | target |
|---|---|
| `.bclj` | clj |
| `.bcljs` | cljs |
| `.bjs` | js |
| `.bnix` | nix |
| `.bgl` | target-neutral |

(Dormant: `.bsql`/`.bpy`/`.bzig`; `.bodin` → odin. `extensions.rkt` is
authoritative.)

## 4. `Any` is opting OUT of the type system — don't reach for it (POLICY)

`Any` = unchecked; an `Any`-heavy `.bclj` gains nothing over `.clj`.

**Policy — whenever you write or edit Beagle:**
- **Express the real type first.** Define the record/shape — what a `Claim`, a
  `Tenant`, a `Request`, a node is. A typed `(defrecord …)` or a concrete
  `(Vec String)` / `(Map …)` / `[A -> B]` is the line where the checker catches a
  wrong value. `Any` is not that line.
- **`Any` is a justified exception, never a default.** If you write `:- Any`, you
  must be able to say *why* this value is genuinely un-typeable here. "It was
  faster" / "the data's a bit dynamic" is not a why.
- **The smell test:** if your `.bclj` is `Any`-heavy, you've gained nothing over
  Clojure. Stop. Either write the real type, or leave the code in `.clj` honestly
  (don't ship `Any`-Beagle that masquerades as a typed core).
- **When Beagle genuinely can't express the shape without `Any`, that's a GAP-LIST
  finding** — write it down ("Beagle can't express X") so it feeds the language's
  growth, instead of silently absorbing it as `Any`. The gap list is a deliverable.

**The falsifiable probe:** replace the `Any` with a real type and run
`beagle check`. It compiles → safety gained. Beagle fights you → a real,
recordable gap. Either outcome beats shipping `Any`. ("Does interop compile?" is
the *wrong* probe — that passes trivially. "Can I even *say* this type, or am I
forced back to `Any`?" is the real one.)

---

The family: Beagle text edits → beagle-authoring · graph-upstream files
(graph edit channel) → code-as-facts · relational code queries
(blast zone / who-calls) → codegraph · building apps on the engine →
fact-modeling. Loop vocabulary: `beagle:docs/authoring-loops.md`.
