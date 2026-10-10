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
- Put Item, Category, goal, files, Done when and ETA in each brief, plus the four facet lines `Spec: exact|measured|judged`, `Scope: one-file|module|cross-module|cross-repo`, `Surface: ts|lua|nix|shell|workflow|docs|assets` and `Verify: none|local-test|farm|native|visual`; give adversarial reviewers a `Lens:` line and have them report `Accepted flaws: N`.
- Put `Follows: <earlier agent id and tier>` plus the failed evidence in a fresh worker for retries, escalations and continuations; never revive a finished or idle worker by message, because its expired cache makes the message re-read its whole context.
- Require reports beginning `Done:`, `Not done:` or `Blocked:`; every Not done or handoff names `Stop: landing|capacity|client|leash|reasoning|decision`.
- Choose Category from mechanical, docs-policy, tooling, feature, bug-known-cause, debugging-unknown-cause, netcode-determinism, performance, balance-tuning, native-check or research.
- Claim/release shared-resource work through `threads`; treat a running brief as its worker's claim.
- Choose the tier with `worker-ledger --recommend '<Category and facet lines>'`: it names the cheapest tier at 80% closed without escalation and landed in the finest cell with 5 runs, backs off Surface, Verify, Scope, then Spec, and changes a cell's pick only on a 15-point lead.
- Alternate each feature or native-check that Opus medium left unfinished between escalation to Opus high and the cheaper fix (split the feature into smaller boxes; fix the native-check's client, capacity or host cause), and compare closures on those leftovers only; Opus high's overall rates (feature 6/25, native-check 0/8) come from escalated hard cases and do not rank tiers.
- Treat these ledger-derived rules as experiments: recheck `worker-ledger --summary` after every 10 new closures in a category and change the rule when the numbers move.
- Send mechanical work and lane mechanics (rebase, regenerate, conflicts, box ticks) to Haiku first; never judged art, bisects or native checks.
- Send every other tooling, balance-tuning and bug-known-cause item with a named file and a measured Done when to worker-haiku with `Arm: haiku-trial`, until the finest facet cell with 5 runs has 5 Haiku closures or 2 Haiku failures; a failure goes to Opus medium with `Follows:`, and the ledger's haiku rows decide the category's default (Haiku 29/32 mechanical at a 1-minute median, 2026-10-10).
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
- Use Fable only when Tom asks by name; use Astra xhigh as the second-opinion reviewer below (Tom, 2026-10-10).
- Staff `planner` (Opus xhigh) for a plan, not code, when an issue gets its second Not done, a category's last 10 runs fall below 40% closed, or the change is architectural (netcode, engine boundary, release shape); cheaper tiers execute its boxes.
- Pass `effort: max` to `planner` for a decision that is expensive to reverse (Tom's standing approval, 2026-10-10).
- Before staffing a max planner's design, have one reviewer from another model family try to break it (Codex `gpt-6-astra` xhigh while Codex usage remains, else `gpt-6.1-sol` high, else Opus at a different tier) (a failing scenario, a cheaper alternative, a wrong assumption) and revise once; Tom asked for adversarial review at the points where a wrong call is expensive (2026-10-10).
- Give each adversarial reviewer one lens and a different lens per reviewer when running two or more: desync or determinism hunter, frame-time profiler, new player at their first match, Warcraft engine limits, maintainer six months later, cheapest alternative, or attacker of the measurement itself; record the lens that found each accepted flaw so the ledger keeps the useful ones.
- Before closing an issue, have worker-haiku rerun each Done when check against origin/main and quote the numbers; close only when every box reproduces.
- Before landing a `Spec: judged` cross-module or cross-repo lane, have a reviewer from another model family or tier (same order as above) review the diff for wrong behaviour and weakened tests, and fix what it shows before `safe-push`.
- Compare Haiku/Opus token cost at 1:40; price Haiku prompts above 100k tokens at 5 times its normal rate.
- Send every code-only Smashcraft/Wisp item to `cloud-workers` first (4 cores/run, no run cap); staff a local worker only for real-game clients, private game assets, the LAN pool or unpushed local state, and move a code-only local worker to the cloud when found.
- Route compute (agreed with Tom 2026-10-10): cloud runs cost only the same plan usage a local worker would, with the machine included; parallel batch work (balance/CPU fields, suites, soaks) goes to GitHub runners through `github-actions` first and to vast.ai through `vast-job` when the farm queue delays a result; always-on Warcraft clients, the offline LAN pool and GPU work go to the Hetzner box once it exists and to the vast.ai VM until then, with signed-in Definitive clients staying local unless moved deliberately; rent no other CPU provider (DigitalOcean and similar cost several times vast.ai for the same cores).
- Start every leash or heartbeat tick with `threads unowned`: before any other work, give each priority:now UNOWNED row a worker (cloud first when code-only) or `threads block <repo#N> <reason>`; only the spawn gate caps this staffing, and every status-file line carries its `priority:now unowned=N blocked=M owned=K` summary.
- Keep `worker-sweep --wait` active while workers run, and run `worker-sweep` once at every leash or heartbeat check; act on every STALLED, OVERTIME, HANDOFF or PARKED row (nudge once, then replace with a Follows: brief) and never judge a worker by recent activity alone; act on each `WAIT` line (landing queue, Actions queue, serial debugging, GPU) with its named move.
- Create recurring jobs (session crons, timers, cloud routines) only from a `dotfiles/agents/routines/` entry, scheduling a session cron with its pointer prompt from `agents routines pointer <name>`; `agents routines` lists every job and flags unregistered ones.
- As a lead with a goal, schedule the `regrounding` routine every 20 minutes; it rebuilds the DAG from the goal's GitHub issues and main CI, staffs every unblocked node up to the spawn gate, recycles workers per the recycle rule and closes passed issues, so Tom never has to prompt a regrounding.
- Stop the parent's monitors/background shells when their work ends.
- Close finished Codex workers as soon as their report arrives.
- Ask a worker idle 10 minutes without a report for one, then archive it; never park a worker to wait on a farm run, a client or another worker.
- In an Autoland repository a worker ends once `safe-push --to main` has pushed its `claude/land-*` branch, reporting `Done: queued <branch>`; Autoland lands it and a Haiku worker ticks its boxes after landing. Elsewhere the worker runs `safe-push` in the foreground with a 10-minute timeout and, when the landing outlasts that, reports its exact lane for the parent to land in the background.
- Recycle a worker at 45 minutes or 350k context, before 500k auto-compaction (the worker-handoff hook nudges between tool calls; the worker-wait-guard hook keeps workers out of foreground waits so messages arrive at once): it queues what passes, then it writes a complete handoff at a natural checkpoint and a fresh worker continues from it; check the fresh worker 5 minutes later for rediscovery.
- Keep workers out of wait loops; messages reach a worker only between its commands.
- Put the state checked at spawn time in every brief (main SHA and CI, lane SHAs, what landed) so workers never act on a stale report.
- Check `threads list` and open issues before filing or staffing; never duplicate an item someone holds.
- Before starting an issue, check `lane-gc --unlanded` for an existing branch referencing it and continue that instead of starting over; an owner who abandons a lane deletes it in the same turn.
- While main is red, staff its fix first and keep queuing lanes behind it; never cancel an Autoland run, because a cancelled bisect half strands its lanes.
- Before a playtest's last blocker lands, prebuild its map with the fix applied and run the frame-cost compare, so the build cannot fail at playtest time.
- Promote a process idea to policy only after it produced a measured result; file unproven ideas as issues.
- After an hour with no closure, start nothing new until an open box closes.
- Write the status file in plain sentences, one line per item, with spaces between words, each line ending with the `threads unowned` summary counts.
- Use `orchestrating-codex` for a Claude session's Codex work.
- Use `agents --help`, `threads --help` and `worker-ledger --help` for command detail.
