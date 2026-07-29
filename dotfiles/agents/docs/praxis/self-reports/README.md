# Self-reports

The opus and sonnet self-reports (and the deltas compiled from them) moved
to the orchestration plugin — canonical copies: `north:orchestration/docs/self-reports/`
and `north:orchestration/docs/deltas/`. Generation method (elicitation exercise,
contamination guard, elicit → subtract → compile): `north:orchestration/docs/method.md`
and the orchestration `elicit` skill.

Only `fable.md` stays here — written by Fable 5 in an interactive session
(2026-07-03), personal tier, no shipped delta. It also carries the design
rationale: §1–10 the process itself, §11 the consumer-blind generic payload
(trial baseline), §12 the compilation method and trial predictions.

Shared caveat (Sonnet said it best): self-report ≠ behavior — these are
what each model believes it does. Deltas treat them as maps of what needs
no teaching, plus enforcers for known know-but-skip gaps.
