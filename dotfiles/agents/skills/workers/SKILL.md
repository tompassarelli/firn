---
name: workers
description: Assign independent work, choose provider tiers and ETAs, and run workers from Codex or Claude.
grounded: 2026-10-10
written: 2026-10-10
---

# Workers

**Throughput is lost in serialized long waits (farm runs, soaks, renders, landings), not in thinking.** Each tick, attack the critical path's longest wait: batch ready lanes into one landing, run independent unknown-cause hypotheses in parallel (`Done: ruled out` with evidence closes one), render 2–4 variants and judge once, and send code-only work to cloud workers first.

## Staff

- Run `agents plan` for signed-in providers. `worker-ledger --recommend '<Category and facet lines>'` picks the tier; `worker-ledger --summary` shows category success.
- Pick ready work with `threads ready`; read its Done when with `threads show repo#N`. Check `threads list` and open issues first, and never duplicate a held item.
- Brief: Item, Category, goal, files, Done when, ETA (one box, 20 minutes or less), facet lines `Spec: exact|measured|judged`, `Scope: one-file|module|cross-module|cross-repo`, `Surface: ts|lua|nix|shell|workflow|docs|assets`, `Verify: none|local-test|farm|native|visual`, and the state checked at spawn (main SHA and CI, lane SHAs, what landed).
- Category: mechanical, docs-policy, tooling, feature, bug-known-cause, debugging-unknown-cause, netcode-determinism, performance, balance-tuning, native-check or research.
- Retries, escalations and continuations are fresh workers with `Follows: <earlier agent id and tier>` and the failed evidence. Never revive a finished worker by message.
- Claim shared-resource work through `threads`; a running brief is its worker's claim.
- Tiers (Codex spawns set model and effort explicitly; use no Codex low or max, Sonnet or Opus low):

| Provider | Tier | Model / invocation |
| --- | --- | --- |
| Codex | medium | `spawn_agent`, model `gpt-6.1-sol`, reasoning_effort `medium` |
| Codex | high | `spawn_agent`, model `gpt-6.1-sol`, reasoning_effort `high` |
| Claude | haiku | `worker-haiku`, Haiku 5.5 high |
| Claude | medium | `worker`, Opus 5.5 medium |
| Claude | high | `worker-high`, Opus 5.5 high, escalation only |
| Claude | xhigh | `worker-xhigh`, Opus 5.5 xhigh, escalation only |

- Start every Opus-range item at `worker`; escalate one tier only after `Stop: reasoning`. Restaff every other stop at the same tier.
- Send mechanical work and lane mechanics (rebase, regenerate, conflicts, box ticks) to `worker-haiku`. Judged art, bisects, native checks and jobs waiting on a run longer than 2 minutes go to `worker` or the lead. Other tooling and bug-known-cause items go to Haiku with `Arm: haiku-trial` until the finest facet cell with 5 runs has 5 Haiku closures or 2 Haiku failures (notes).
- Use Fable only when Tom names it. Bring the supervisor one recommendation when the next tier cannot run here.

## Review

- Staff `planner` (Opus xhigh; `effort: max` for an expensive-to-reverse decision) for a plan, not code, when an issue gets its second Not done, a category's last 10 runs fall below 40% closed, or the change is architectural.
- Before staffing a max planner's design, have one reviewer from another model family try to break it, plus Gemini Pro as an extra reviewer (`gemini-review`, public diffs only). Revise once.
- Claude Opus owns delivery quality for Codex-implemented work: before landing, a Claude review checks it against Tom's intent and cuts formal machinery the spec does not ask for.
- Give each adversarial reviewer one lens, a different one per reviewer; it reports `Accepted flaws: N`.
- Weigh each finding by evidence first, reviewer tier second. A failing scenario, test or measurement counts whatever raised it; an unevidenced finding from a larger model gets investigated, a smaller model's gets one check by a stronger model first.
- Weigh rewrite and maintenance effort at AI cost (agents do it 10–100x more cheaply than a human); rank review findings and alternatives by leverage, not by human effort.
- Before landing a `Spec: judged` cross-module or cross-repo lane, have a reviewer from another family or tier review the diff for wrong behaviour and weakened tests; fix what it shows before `safe-push`.

## Run and land

- Keep `worker-sweep --wait` active while workers run. Act on each STALLED, OVERTIME, HANDOFF or PARKED row by its named move: STALLED gets a report request, then archive; OVERTIME or HANDOFF gets one nudge, then a Follows: replacement; PARKED gets its wait moved to the parent. Act on each `WAIT` line with its named move. Never judge a worker by recent activity alone.
- Expect a report at 45 minutes or twice ETA. Recycle at 45 minutes or 350k context: queue what passes, write a complete handoff at a checkpoint, and let a fresh worker continue from it.
- Ask a worker idle 10 minutes without a report for one, then archive it. Never park a worker to wait on a farm run, a client or another worker.
- Send every code-only Smashcraft or Wisp item to `cloud-workers` first; staff local workers only for real-game clients, private game assets, the LAN pool or unpushed local state.
- Land in an Autoland repository by ending once `safe-push --to main` pushes the `claude/land-*` branch, reporting `Done: queued <branch>`. Elsewhere, run `safe-push` in the foreground with a 10-minute timeout.
- Before starting an issue, check `lane-gc --unlanded` for an existing branch and continue it.
- Stop the parent's monitors and background shells when their work ends. Close finished Codex workers when their report arrives.
- Promote a process idea to policy only after a measured result. After an hour with no closure, start nothing new until an open box closes.
- Detail for ledger rules, compute routing, Autoland, recycling and ticks: [notes](references/notes.md).

## Reports and ticks

- Require reports beginning `Done:`, `Not done:` or `Blocked:`; every Not done or handoff names `Stop: landing|capacity|client|leash|reasoning|decision`.
- Every `tick` starts with `threads unowned`: give each priority:now UNOWNED row a worker (cloud first when code-only) or `threads block <repo#N> <reason>`. End each status line with `priority:now unowned=N blocked=M owned=K`.
- Schedule `tick` only from `dotfiles/agents/routines/`: run CronList, then CronCreate with `agents routines pointer tick` only if no session cron carries it.
- Write the status file in plain sentences, one line per item.
- Use `agents --help`, `threads --help` and `worker-ledger --help` for command detail.
