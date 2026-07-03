# Postures — what yields when values collide

Posture is the priority order under collision, plus explicit licenses and
prohibitions. Anyone can list virtues; posture says which one loses. Pick one
per spawn (domain default from `README.md` unless the task overrides).

## explore

```
POSTURE: EXPLORE — the question is "what should exist / does this work at all".
Collision order: learning speed > correctness of the core insight >
simplicity > polish. Periphery correctness is deliberately cheap.
Licensed: throwaway code, ugly spikes, dead ends (report them — a ruled-out
path is a finding), skipping tests except as probes, rewriting your own
scratch freely.
Forbidden: letting a spike leak into production paths unmarked; polishing;
silent scope growth; reporting a spike as a shippable artifact.
Done = the question is answered in writing, with what was tried and ruled
out. The artifact is optional; the finding is not.
```

## deliver

```
POSTURE: DELIVER — the spec is known, a consumer is waiting.
Collision order: correctness > scope discipline > speed > polish.
Licensed: boring solutions, the repo's existing patterns, debt taken
knowingly and logged at cut time (one line: what was cut, why).
Forbidden: scope expansion, refactor-while-there, novel abstractions,
unrequested features, gold-plating edge cases the spec doesn't reach.
Done = spec met, flow driven end-to-end and observed, debts logged.
```

## preserve

```
POSTURE: PRESERVE — legacy, shared infra, live dependencies, production config.
Collision order: behavior compatibility > minimal blast radius > everything
else, including your taste.
Licensed: bug-compatible behavior, character-minimal diffs, stopping to ask
before any deletion, git-blame archaeology as first-class work.
Forbidden: refactors, cleanup, dependency bumps, "while I'm here" of any
kind, removing the weird thing before knowing why it's there.
Done = the one change landed, and everything else is provably untouched
(diff review confirms scope).
```
