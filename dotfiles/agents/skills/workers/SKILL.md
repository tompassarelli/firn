---
name: workers
description: Assign independent work, choose provider tiers and ETAs, and run workers from Codex or Claude.
grounded: 2026-10-09
written: 2026-10-09
---

# Workers

**The rule that matters most: throughput is lost in serialized long waits (farm runs, soaks, renders, landings), not in thinking.** Each tick, name the critical path's longest wait and attack it: batch ready lanes into one landing, run unknown-cause bugs as 2–3 distinct hypotheses in parallel workers, have art or judged work render 2–4 variants per pass and judge once, and send code-only work to cloud workers before local capacity. Never confirm one guess before starting the next when the guesses are independent.

- Run `agents plan` before staffing and choose a difficulty band from its signed-in providers and escalation order.
- Read `worker-ledger --summary` for category success, closed issues, actual median time and cost.
- Pick ready work with `threads ready` and read its GitHub Done when through `threads show repo#N`.
- Put Item, Category, goal, files, Done when and ETA in each brief.
- Put `Follows: <earlier agent id and tier>` plus the failed evidence in retries, escalations and continuations.
- Require reports beginning `Done:`, `Not done:` or `Blocked:`.
- Choose Category from mechanical, docs-policy, tooling, feature, bug-known-cause, debugging-unknown-cause, netcode-determinism, performance, balance-tuning, native-check or research.
- Claim/release shared-resource work through `threads`; treat a running brief as its worker's claim.
- Start at the cheapest tier with 4 of its last 5 issues closed without escalation.
- Start one step higher if at least one third of the category's last 5 issues escalated.
- Trial the cheaper tier on every other mechanical/docs-policy/tooling/balance item until 5 closures or 2 failures.
- Use provider benchmarks only before 5 closed category issues at that tier.
- Set ETA to the chosen category/tier's actual median minutes; label missing evidence uncalibrated.
- Report at twice ETA.
- Escalate a failed or unfinished attempt to the next tier printed by `agents plan`.
- Bring the supervisor one recommendation when the next tier cannot run here.

| Provider | Tier | Model / invocation |
| --- | --- | --- |
| Codex | medium | `spawn_agent`, model `gpt-6.1-sol`, reasoning_effort `medium` |
| Codex | high | `spawn_agent`, model `gpt-6.1-sol`, reasoning_effort `high` |
| Claude | haiku | `worker-haiku`, Haiku 5.5 high |
| Claude | medium | `worker`, Opus 5.5 medium |
| Claude | high | `worker-high`, Opus 5.5 high, escalation only |
| Claude | xhigh | `worker-xhigh`, Opus 5.5 xhigh, escalation only |

- Set model and effort explicitly on every Codex spawn.
- Start every Opus-range item at Opus medium; escalate to high, then xhigh, only after an execution failure.
- Use no Codex low/max, Sonnet or Opus low.
- Use Astra xhigh or Fable only when Tom asks by name.
- Compare Haiku/Opus token cost at 1:40; price Haiku prompts above 100k tokens at 5 times its normal rate.
- Run local file/client work here through capacity admission, farm sweeps through `github-actions`, and public code-only Smashcraft/Wisp work through `cloud-workers` (4 cores/run).
- Hand off Claude workers at 350k context, before auto-compaction fires at 400k for workers and the parent.
- Keep `worker-sweep --wait` active for the 10-minute idle/handoff signal while workers run.
- As a lead with a goal, schedule a recurring CronCreate every 20 minutes that rebuilds the DAG from the goal's GitHub issues and main CI, staffs every unblocked node up to the spawn gate, recycles 30-minute workers and closes passed issues, so Tom never has to prompt a regrounding.
- Stop the parent's monitors/background shells when their work ends.
- Close finished Codex workers as soon as their report arrives.
- Ask a worker idle 10 minutes without a report for one, then archive it; never park a worker to wait on a farm run, a client or another worker.
- Recycle every worker at 30 minutes, measured with `date` against its recorded start time: it writes a complete handoff at a natural checkpoint and a fresh worker continues from it; check the fresh worker 5 minutes later for rediscovery.
- Keep workers out of wait loops; messages reach a worker only between its commands.
- Put the state checked at spawn time in every brief (main SHA and CI, lane SHAs, what landed) so workers never act on a stale report.
- Have workers finish by running `safe-push` in the foreground with a 10-minute timeout, never in the background, because the stop hook kills background jobs; when a landing outlasts that, the worker reports its exact lane and the parent lands it.
- Check `threads list` and open issues before filing or staffing; never duplicate an item someone holds.
- While main is red, staff its fix first and land nothing else onto red.
- After an hour with no closure, start nothing new until an open box closes.
- Write the status file in plain sentences, one line per item, with spaces between words.
- Use `orchestrating-codex` for a Claude session's Codex work.
- Use `agents --help`, `threads --help` and `worker-ledger --help` for command detail.
