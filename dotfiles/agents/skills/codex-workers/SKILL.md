---
name: codex-workers
agents: [codex]
description: Codex worker tiers (SOL 6.1, Astra) and their escalation ladder. Use with staffing whenever a Codex session starts workers.
---

# Codex workers

Set `model` and `reasoning_effort` on every `spawn_agent` call; the ledger
reads the tier from them.

| Tier | Model and effort | Start here when |
| --- | --- | --- |
| medium | `gpt-6.1-sol` medium | Default and floor: features, fixes with a known cause, tooling, docs and skills, setup, mechanical work. |
| high | `gpt-6.1-sol` high | Multi-step or ambiguous work: unknown-cause debugging, netcode, determinism, engine, performance, cross-module work, native lane owners. |
| escalation | `gpt-6-astra` xhigh | Only after a high attempt failed or left the box unfinished. |

Never low; never max. Ladder: medium, high, Astra xhigh, then one
recommendation to Tom. No published chart or price ratio here covers SOL 6.1
against Astra, so compare tokens within one model and let the ledger move a
category's start.
