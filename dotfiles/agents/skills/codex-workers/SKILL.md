---
name: codex-workers
agents: [codex]
description: Codex worker tiers (SOL 6.1 medium and high) and their escalation ladder. Use with staffing whenever a Codex session starts workers.
---

# Codex workers

Set `model` and `reasoning_effort` on every `spawn_agent` call; the ledger
reads the tier from them.

| Tier | Model and effort | Start here when |
| --- | --- | --- |
| medium | `gpt-6.1-sol` medium | Default and floor: features, fixes with a known cause, tooling, docs and skills, setup, mechanical work. |
| high | `gpt-6.1-sol` high | Multi-step or ambiguous work: unknown-cause debugging, netcode, determinism, engine, performance, cross-module work, native lane owners. |

Never low; never max. Ladder: medium, high, then one recommendation to
whoever started this session: Tom, or a supervisor whose brief says how to
escalate. Use Astra only when Tom
asks for it by name (9 Oct: it drains his usage and SOL is good enough). Let
the ledger move a category's start.

Close a worker as soon as its final report (Done:, Not done: or Blocked:) arrives; keep only workers that are running or waiting on one blocking command.
