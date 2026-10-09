---
name: workers
description: Assign independent work, choose provider tiers and ETAs, and run workers from Codex or Claude.
---

# Workers

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
| Claude | high | `worker-high`, Opus 5.5 high |

- Set model and effort explicitly on every Codex spawn.
- Use no Codex low/max, Sonnet or Opus low/above high.
- Use Astra xhigh or Fable only when Tom asks by name.
- Compare Haiku/Opus token cost at 1:40; price Haiku prompts above 100k tokens at 5 times its normal rate.
- Run local file/client work here through capacity admission, farm sweeps through `github-actions`, and public code-only Smashcraft/Wisp work through `cloud-workers` (4 cores/run).
- Hand off Claude workers at 400k context; compact the parent at 600k.
- Keep `worker-sweep --wait` active for the 20-minute idle/handoff signal while workers run.
- Stop the parent's monitors/background shells when their work ends.
- Close finished Codex workers as soon as their report arrives.
- Use `orchestrating-codex` for a Claude session's Codex work.
- Use `agents --help`, `threads --help` and `worker-ledger --help` for command detail.
