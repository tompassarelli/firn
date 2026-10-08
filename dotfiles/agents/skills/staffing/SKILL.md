---
name: staffing
description: Pick ready work, write worker briefs, and choose effort and ETA from work history.
---

# Staffing

Pick work with `threads ready`; read the item with `threads show repo#N`.
GitHub owns the title, Done when, state and blocked-by links. `threads` owns
holders, handoffs and runs. Close an issue with `gh issue close`, citing the
last run's outcome.

A worker brief names the goal, files, Done when and ETA, plus these lines:

```text
Item: repo#N
Category: docs-policy
Follows: <earlier agent id>
```

Use Follows when continuing an earlier attempt. Name that attempt's tier.
Category is one of: mechanical, docs-policy, tooling, feature,
bug-known-cause, debugging-unknown-cause, netcode-determinism, performance,
balance-tuning, native-check, research.

A running brief is the claim: its worker holds the issue until it finishes.
Use `threads claim` and `threads release --to` for people and shared-resource
workers. `threads need` and `threads unneed` change blocked-by links on GitHub.
`threads list` shows holders and time held against ETA.

Read `worker-ledger --summary` before choosing a tier. Compare the category's
success rate, completed runs and actual time by tier. Missing categories and
unclear outcomes are missing evidence, not proof that a tier failed.
Always set the model and effort. Use only these choices:

| Effort | Claude Code (Opus) | Codex | Start here when |
| --- | --- | --- | --- |
| medium | worker | gpt-6.1-sol medium | Default and floor; ordinary work, clear fixes, docs, setup, mechanical work. |
| high | worker-high | gpt-6.1-sol high | Known-hard: unknown-cause debugging, netcode, engine, performance, cross-module work, native checks. |
| xhigh | worker-xhigh | gpt-6-astra xhigh | Escalation from a failed or unfinished high attempt. |
| max | worker-max | gpt-6-astra max | Last resort after an important xhigh attempt failed or was unfinished. |

Trial: `worker-haiku` (Claude Haiku 5.5, `claude-haiku-5-5`) takes mechanical,
fully specified Claude work so the ledger can compare its `haiku` row with
`medium`. Escalate a failed haiku attempt to `worker`.

A failed or unfinished attempt starts one tier above the earlier worker,
even after rewording the brief or reopening the issue. The history rule
outranks the default. A running worker's effort cannot change. Never use low;
never use Fable unless Tom asks.

ETA is the category's median actual minutes (`actual_med`) in the summary;
prefer the chosen tier's row when available. Say when evidence comes from
another tier or model. With no category samples, label the ETA uncalibrated.
Report at twice the ETA. `worker-ledger` records finished runs and the summary
compares actual time with ETA; do not create another ledger.
