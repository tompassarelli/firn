---
name: clause-authoring-distilled
description: >-
  Write, edit, or debug .clause source in any project through the consuming
  project's immutable Clause compiler pin and its compiler-owned authoring
  card and source checker.
---

# Clause authoring

Use the consumer's compiler, not remembered syntax.

1. Read the consuming project's instructions and resolve its exact immutable
   Clause compiler pin from the dependency or launcher it declares. Never
   substitute Clause `main`, another project's pin, or an arbitrary newer pin.
2. Invoke that pin's `clause-workbench authoring-card`. Its curated compiled
   examples describe the current high-value vocabulary without claiming an
   exhaustive language surface.
3. Keep world and domain semantics in `.clause` source. Make the smallest edit
   that expresses the intended semantics; do not move them into Rust,
   JavaScript, TypeScript, generated data, or another host fallback.
4. Invoke the same pin's `clause-workbench check-source FILE.clause`. This must
   reach the resident reader, elaboration, lowering, and session-open path;
   syntax-only parsing is not acceptance.

Treat the compiled examples and current compiler diagnostics as authority. If
the intended valid construct is absent or rejected, preserve the smallest
executable `.clause` counterexample and route the missing capability to Clause.
Repair and repin the compiler before resuming the consumer; never reshape the
source merely to dodge the gap, weaken the semantics, or introduce a host
implementation.
