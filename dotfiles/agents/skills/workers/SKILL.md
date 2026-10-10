---
name: workers
description: Assign independent work, choose provider tiers and ETAs, and run workers from Codex or Claude.
grounded: 2026-10-10
written: 2026-10-10
---

# Workers

**The rule that matters most: throughput is lost in serialized long waits (farm runs, soaks, renders, landings), not in thinking.** Each tick, name the critical path's longest wait and attack it: batch ready lanes into one landing, run unknown-cause bugs as 2–3 parallel workers with one hypothesis and one discriminating experiment each (`Done: ruled out` with evidence closes a run), have art or judged work render 2–4 variants per pass and judge once, and send code-only work to cloud workers before local capacity. Never confirm one guess before starting the next when the guesses are independent.

- Run `agents plan` before staffing and choose a difficulty band from its signed-in providers and escalation order.
- Read `worker-ledger --summary` for category success, closed issues, actual median time and cost.
- Pick ready work with `threads ready` and read its GitHub Done when through `threads show repo#N`.
- Put Item, Category, goal, files, Done when and ETA in each brief.
- Put `Follows: <earlier agent id and tier>` plus the failed evidence in a fresh worker for retries, escalations and continuations; never revive a finished or idle worker by message, because its expired cache makes the message re-read its whole context.
- Require reports beginning `Done:`, `Not done:` or `Blocked:`; every Not done or handoff names `Stop: landing|capacity|client|leash|reasoning|decision`.
- Choose Category from mechanical, docs-policy, tooling, feature, bug-known-cause, debugging-unknown-cause, netcode-determinism, performance, balance-tuning, native-check or research.
- Claim/release shared-resource work through `threads`; treat a running brief as its worker's claim.
- Start at the cheapest tier with 4 of its last 5 issues closed without escalation.
- Send mechanical work and lane mechanics (rebase, regenerate, conflicts, box ticks) to Haiku first; never judged art, bisects or native checks.
- Use provider benchmarks only before 5 closed category issues at that tier.
- Size each brief to one box with an ETA of 20 minutes or less, splitting larger work before staffing; set ETA to the category/tier's actual median and label missing evidence uncalibrated.
- Expect a report at 45 minutes or twice ETA, whichever comes first.
- Run a job longer than the 45-minute leash (renders, long captures) yourself under a capacity lease, then staff a short worker to use its output.
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
- Start every Opus-range item at Opus medium; escalate to the next tier printed by `agents plan` only after `Stop: reasoning` (wrong cause or two failed fixes), and restaff every other stop at the same tier.
- Use no Codex low/max, Sonnet or Opus low.
- Use Astra xhigh or Fable only when Tom asks by name.
- Compare Haiku/Opus token cost at 1:40; price Haiku prompts above 100k tokens at 5 times its normal rate.
- Send every code-only Smashcraft/Wisp item to `cloud-workers` first (4 cores/run, no run cap); staff a local worker only for real-game clients, private game assets, the LAN pool or unpushed local state, and move a code-only local worker to the cloud when found. Run farm sweeps through `github-actions`.
- Keep `worker-sweep --wait` active for the 10-minute idle/handoff signal while workers run; act on each `WAIT` line (landing queue, Actions queue, serial debugging, GPU) with its named move.
- As a lead with a goal, schedule a recurring CronCreate every 20 minutes that rebuilds the DAG from the goal's GitHub issues and main CI, staffs every unblocked node up to the spawn gate, recycles workers per the recycle rule and closes passed issues, so Tom never has to prompt a regrounding.
- Stop the parent's monitors/background shells when their work ends.
- Close finished Codex workers as soon as their report arrives.
- Ask a worker idle 10 minutes without a report for one, then archive it; never park a worker to wait on a farm run, a client or another worker.
- In an Autoland repository a worker ends once `safe-push --to main` has pushed its `claude/land-*` branch, reporting `Done: queued <branch>`; Autoland lands it and a Haiku worker ticks its boxes after landing. Elsewhere the worker runs `safe-push` in the foreground with a 10-minute timeout and, when the landing outlasts that, reports its exact lane for the parent to land in the background.
- Recycle a worker at 45 minutes or 350k context, before 500k auto-compaction (the worker-handoff hook enforces both): it queues what passes, then it writes a complete handoff at a natural checkpoint and a fresh worker continues from it; check the fresh worker 5 minutes later for rediscovery.
- Keep workers out of wait loops; messages reach a worker only between its commands.
- Put the state checked at spawn time in every brief (main SHA and CI, lane SHAs, what landed) so workers never act on a stale report.
- Check `threads list` and open issues before filing or staffing; never duplicate an item someone holds.
- While main is red, staff its fix first and keep queuing lanes behind it; never cancel an Autoland run, because a cancelled bisect half strands its lanes.
- Before a playtest's last blocker lands, prebuild its map with the fix applied and run the frame-cost compare, so the build cannot fail at playtest time.
- Promote a process idea to policy only after it produced a measured result; file unproven ideas as issues.
- After an hour with no closure, start nothing new until an open box closes.
- Write the status file in plain sentences, one line per item, with spaces between words.
- Use `orchestrating-codex` for a Claude session's Codex work.
- Use `agents --help`, `threads --help` and `worker-ledger --help` for command detail.
