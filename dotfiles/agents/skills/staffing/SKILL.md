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
Always set the model and effort. Use only these choices. There is no Sonnet
tier (Tom, 8 Oct): Haiku 5.5 covers mechanical work and Opus 5.5 the rest.

| Tier | Claude Code | Codex | Start here when |
| --- | --- | --- | --- |
| haiku | worker-haiku (Haiku 5.5 medium) | gpt-6.1-sol medium | Mechanical, fully specified, small: exact edits, ticking and closing issues, running a named check or prepared script and reporting its numbers, summaries, lookups. |
| medium | worker (Opus 5.5) | gpt-6.1-sol medium | Default: features, fixes with a known cause, tooling, docs and skills, setup. Codex floor. |
| high | worker-high | gpt-6.1-sol high | Multi-step or ambiguous work: unknown-cause debugging, netcode, engine, performance, cross-module work, native checks, research. |
| xhigh | worker-xhigh | gpt-6-astra xhigh | Escalation from a failed or unfinished high attempt. |
| max | worker-max | gpt-6-astra max | Last resort for reasoning-heavy work (unknown cause, design, research) after xhigh failed. |

The ladder is haiku, medium, high, xhigh, max. A failed or unfinished
attempt starts one tier above the earlier worker, even after rewording the
brief or reopening the issue, and its brief carries Follows and the failed
report's evidence. The history rule outranks the default. A coding fix that
failed at xhigh doesn't go to max: bring one recommendation instead. A running
worker's effort cannot change. Never use Opus low; never use Fable unless Tom
asks.

## Priors, then our evidence

Anthropic's launch charts (Opus 5.5, 22 Sep 2026; Haiku 5.5, 7 Oct 2026) set
the starting tier only while a category has fewer than five closed issues at
that tier:

- Mergeable code changes peak at Opus medium (FrontierCode: medium 54.6%,
  high 54%, xhigh 51%, max 54% at seven times medium's cost).
- Multi-step terminal work and ambiguous multi-file tasks gain from medium to
  high (Terminal-Bench 57 to 64%, CursorBench 52 to 56%) and little above:
  xhigh adds 2 points at twice the cost, and max is no better.
- Knowledge work and long data collection keep gaining through xhigh and max
  (GDPval 1690 to 1820 to 1846 Elo, WANDR 67 to 71 to 72%), so research and
  design gain most from escalation.
- Haiku 5.5 suits narrow work. Its max effort costs about what Opus medium
  does and scores no higher (GDPval 1620 against 1575 at about $0.90 a task;
  Terminal-Bench 39% against Opus low's 38%), so Haiku stays at medium and a
  failed haiku attempt goes to Opus medium. Prompts over 100k tokens cost it
  five times as much: keep its briefs to one file or one check.
- Opus 5.5 medium matches GPT-6 Astra's best coding scores at 20 to 40% of
  the cost. The charts don't include SOL 6.1.

With five or more closed issues for a category at a tier, the ledger decides:

- Start at the cheapest tier that closed at least four of its last five
  issues without escalation.
- Start one tier higher when a third or more of the category's last five
  issues escalated.
- While the tier below the current start has fewer than five closed issues in
  a mechanical, docs-policy, tooling or balance-tuning category, send every
  other item there; a failure costs one escalation. Stop the trial at five
  closures or two failures.
- Compare cost as tokens_per_closed within one model. Across models, weigh by
  list price: Haiku 5.5's tokens cost about a fortieth of Opus 5.5's ($0.10
  and $0.50 against $4 and $20 per million input and output tokens).
- Compare Claude and Codex rows in the same category the same way before
  preferring either.

The ledger only scores what briefs and reports record. Every brief carries
Item and Category, Follows on every retry or escalation (on 8 Oct 6 of 147
runs named one, so escalations were invisible), and asks for a report that
starts with "Done:", "Not done:" or "Blocked:" (70 of 139 earlier Claude runs
scored unclear because the report started otherwise).

ETA is the category's median actual minutes (`actual_med`) in the summary;
prefer the chosen tier's row when available. Briefed ETAs on 8 Oct ran 1.5 to
6 times the actual time, so take the number from the ledger, not judgement.
Say when evidence comes from another tier or model. With no category samples,
label the ETA uncalibrated. Report at twice the ETA. `worker-ledger` records
finished runs and the summary compares actual time with ETA; do not create
another ledger.
