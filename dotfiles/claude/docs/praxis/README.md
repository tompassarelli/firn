# Praxis — composable spawn payloads

The coordinator re-derives procedure and policy for every spawn; this
directory caches it. Instead of brute-forcing instructions each time, compose
from orthogonal axes and paste into the spawn prompt. Goals: cheaper spawns,
less decision fatigue, consistent house style. Constraint: the assembled
payload stays **≤ ~60 lines** — the cache must not become a context tax.

## Assembly (three questions, then paste)

1. **Domain?** — sets the DEFAULTS (table below). Usually answered by cwd.
2. **Shape?** — execute / implement / integrate / design / invent →
   role block from `roles.md`, model + effort per
   `~/code/nixos-config/dotfiles/claude/docs/model-selection.md` (dials 1–2).
3. **Posture?** — explore / deliver / preserve → block from `postures.md`.
   Take the domain default unless the task says otherwise.

Paste: role block + posture block + model delta (`deltas/opus.md` or
`deltas/sonnet.md`) + the task itself. Most spawns = confirm domain defaults
and go; deliberation only when the task contradicts its domain.

## Domain bootstrap (defaults by entry point)

| Domain | Path signal | Default posture | Notes |
|---|---|---|---|
| Client delivery | `~/code/client/*` | deliver (preserve on existing code) | Deadline-real. Ladder hard: glue minimized. Confidential — no cross-references out. |
| Novel core / research | `~/code/beagle`, tern core, new primitives | explore → deliver once shaped | Priors law ACTIVE: distrust fluent defaults, derive and verify. Core inversion: hand-build the deliverable. |
| Infrastructure / config | `~/code/nixos-config`, dotfiles, CI | deliver, preserve-leaning | Reproducibility rules; blast radius = every future rebuild. |
| Others' code | `~/code/reference/*` | read-only | Never edit; license check before leveraging. |

Domain sets defaults, task shape can override a default, and the escape
hatch overrides everything.

## Escape hatch — presets are compression, not law

Misfit signals: the task spans domains; the posture contradicts the evidence
in front of you; the agent keeps hitting its authority wall; the work IS this
taxonomy. On any signal: **drop the preset, write one line naming what was
dropped and why, operate from first principles.** A logged drop is the
cache-miss path working, not a failure. Hyper-fit structure that can't be
exited is worse than no structure.

## Change policy — the freeze rule

Edit this structure only after a real spawn hit a misfit **twice**. Never
speculatively — no new roles, postures, domains, or deltas ahead of demand.
Rationale for the whole design, compilation method for new model deltas
(elicit self-report → subtract → compile in consumer's vocabulary):
`~/code/nixos-config/dotfiles/claude/docs/fable-praxis.md` §12.
