# Self-reports — how these were generated

Each file is a model's introspective account of its own engineering process,
elicited with the same exercise: "describe your process at software
architecture and engineering — behavior/style, what you prioritize, what you
don't, context-specific thinking — as training material another model could
read." These are the SUBTRACTION BASE for the compiled payloads in
`~/code/nixos-config/dotfiles/claude/docs/praxis/deltas/` — a delta is built
by removing everything the consumer already self-reports, then phrasing what
remains in the consumer's own vocabulary (method: `fable.md` §12).

- **fable.md** — written by Fable 5 in an interactive session (2026-07-03).
  Also carries the design rationale: §1–10 the process itself, §11 the
  consumer-blind generic payload (kept as trial baseline), §12 the
  compilation method + trial predictions.
- **opus.md** — written by Opus in a sibling session, same exercise, before
  reading fable.md. Notably framed itself as a "compiler" lowering implicit
  parallel capability into explicit serial procedure for a smaller disciple.
- **sonnet.md** — elicited from a Sonnet 5 tern spawn (sonnet-medium,
  2026-07-03) under a strict contamination guard: no reading of sibling
  praxis docs, CLAUDE.md files, or any repo files — pure introspection, one
  Write only. The guard matters: the value of a self-report is what the model
  holds NATIVELY, uncontaminated by the other tiers' vocabulary.

Caveat all three share (Sonnet said it best): self-report ≠ behavior — these
are what each model believes it does. The deltas treat them as maps of what
needs no teaching, and separately arm enforcers for known know-but-skip gaps.
