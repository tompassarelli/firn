---
name: beagle-authoring
description: >-
  Use WHENEVER writing, editing, or debugging Beagle source in ANY project —
  files ending .bclj/.bcljs/.bjs/.bnix/.bgl or starting with `#lang beagle`,
  or anything under ~/code/beagle. Establishes that the repair-compiler loop
  is online AND functionally working before coding, keeps it from silently
  degrading, points at the compiler as the source of truth (never a static
  cheat sheet), and carries the stable tool/operating-mode reference.
---

# Beagle authoring

Beagle is a typed authoring IR — **Clojure plus types**, compiled `parse →
check → emit` to Nix / Clj / CLJS / JS / Odin. The reason to author in Beagle
at all is the **repair loop**: pointed, structured errors and machine-applicable
repairs fed back fast. If that loop is offline or silently degraded, you are
writing Beagle blind. So the loop comes first.

## 0. Handshake — run this BEFORE writing any Beagle

```
beagle-doctor --deep
```

- **"Repair loop: ok"** → proceed.
- **"Repair loop: DEGRADED" (exit 1)** → the feedback you'd rely on is not
  trustworthy. Do **not** start coding on silent green. Fix it:
  - daemon down → `beagle-doctor --revive`  (or `beagle-daemon start --watch .`)
  - no per-edit hook in this project → `beagle-init --hooks` to scaffold the
    portable PostToolUse syntax/type-check hook, then re-run the doctor.
  - re-run `beagle-doctor --deep` until green.

`beagle-doctor` is a **functional** check, not a liveness check: it round-trips
known-bad **and** known-good inputs through syntax / type-check / suggestion→patch,
so it catches a checker stuck "always-pass" or "always-fail" — exactly the silent
degradation a process-exists check misses.

## 1. Heartbeat — keep it alive while coding

- The **PostToolUse hook** (installed by `beagle-init --hooks`) is the only
  *harness-enforced* feedback — it fires on every Edit/Write. **Trust its
  output.** Fix syntax errors before type errors. Never hand-count parens —
  `beagle-syntax` already counted them.
- If feedback ever goes **silent** mid-session, the loop degraded — re-run
  `beagle-doctor --revive --quiet`.
- Optional background watchdog (this session): `/loop 10m beagle-doctor --revive --quiet`
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
| does this file parse? where? | `beagle-syntax FILE` (`--ledger`, `--repair --emit-patch`) |
| does this file type-check? | `beagle-check --agent FILE` |
| signature of X? | `beagle-sig X FILE...` |
| fields of record R? | `beagle-fields R FILE...` |
| who calls X? | `beagle-callers X FILE...` |
| what does FILE export? | `beagle-provides FILE` |
| change-impact of X? | `beagle-impact X FILE...` |
| macro expansion? | `beagle-expand FILE` |
| run tests | `beagle-test` (active tier; `BEAGLE_ALL_TARGETS=1` for dormant) |
| compile | `beagle-build FILE [OUT]` |
| is the repair loop healthy? | `beagle-doctor [--deep]` |
| auto-repair | `beagle-repair --emit-patch` (also `beagle-trace`, `beagle-blame`, `beagle-cascade`, `beagle-specfix`) |

For forms/types/stdlib themselves, **read the source** — never restate it:
`parse.rkt` (forms), `types.rkt` (types), `stdlib-*.rkt` (externs),
`extensions.rkt` (ext→target). The authoritative living anchor is
**`~/code/beagle/CLAUDE.md`** — read it when you start Beagle work in a session;
if the surface looks different than you expect, `git log` it.

## 3. Stable operating model (this does not churn)

- **Beagle is Clojure + types, nothing else.** Every divergence from Clojure
  must be load-bearing for the type system or a backend, or it gets removed.
- **Surface lock:** typed Clojure with inline `:-` annotations only —
  `(def x :- T v)`, `(defn f [p :- T ...] :- R body)`, `(defonce …)`,
  `(defrecord N [field :- T …])`. Interiors are inferred. `:` (Rust-style) and
  `(claim …)` are **hard-rejected**.
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
