---
name: staffing
description: Pick ready work, write worker briefs, and choose a worker tier and ETA from work history.
---

# Staffing

Pick work with `threads ready`; read the item with `threads show repo#N`.
GitHub owns the title, Done when, state and blocked-by links. `threads` owns
holders, handoffs and runs. Close an issue with `gh issue close`, citing the
last run's outcome.

A worker brief names the goal, files, Done when and ETA, asks for a final
report whose first word is "Done:", "Not done:" or "Blocked:", and carries
these lines:

```text
Item: repo#N
Category: docs-policy
Follows: <earlier agent id>
```

Use Follows on every retry, escalation or continuation, naming that
attempt's tier. Category is one of: mechanical, docs-policy, tooling,
feature, bug-known-cause, debugging-unknown-cause, netcode-determinism,
performance, balance-tuning, native-check, research. The ledger scores a run
only from its report's first word and links attempts only through Follows:
on 8 Oct, 70 of 139 Claude runs scored unclear and 6 of 147 runs named
Follows.

A running brief is the claim: its worker holds the issue until it finishes.
Use `threads claim` and `threads release --to` for people and shared-resource
workers. `threads need` and `threads unneed` change blocked-by links on GitHub.
`threads list` shows holders and time held against ETA.

## Band and tier

Run `agents plan` at session start. It reads Tom's
`nixos-config:dotfiles/agents/orchestration.toml` and the providers signed
in now, and prints each difficulty band (mechanical, middle, top, planning),
the tiers it uses and the band a failed box goes to next. Pick each item's
band from its difficulty and start at that band's first tier. Your
provider's workers skill says how to spawn each tier: `claude-workers` in
Claude Code, `codex-workers` in Codex. Always set the model and effort.

A failed or unfinished attempt starts at the next tier in its band, then at
the next band's first tier, even after rewording the brief or reopening the
issue, and its brief carries the failed report's evidence. The history rule
outranks the default. When the plan says "recommend to Tom", bring Tom one
recommendation. A running worker's effort cannot change.

Read `worker-ledger --summary` before choosing. Compare the category's
success rate, completed runs and actual time by tier. Missing categories and
unclear outcomes are missing evidence, not proof that a tier failed. A
provider's benchmarks set a category's starting tier only while it has fewer
than five closed issues at that tier. Then the ledger decides:

- Start at the cheapest band and tier that closed at least four of its last
  five issues without escalation.
- Start one step higher when a third or more of the category's last five
  issues escalated.
- While the tier below the current start has fewer than five closed issues in
  a mechanical, docs-policy, tooling or balance-tuning category, send every
  other item there; a failure costs one escalation. Stop the trial at five
  closures or two failures.
- Compare cost as tokens_per_closed within one model; the workers skill gives
  the price ratio between its models.

## ETA

ETA is the category's median actual minutes (`actual_med`) in the summary;
prefer the chosen tier's row when available. Briefed ETAs on 8 Oct ran 1.5 to
6 times the actual time, so take the number from the ledger, not judgement.
Say when evidence comes from another tier or model. With no category samples,
label the ETA uncalibrated. Report at twice the ETA. `worker-ledger` records
finished runs and the summary compares actual time with ETA; do not create
another ledger.
