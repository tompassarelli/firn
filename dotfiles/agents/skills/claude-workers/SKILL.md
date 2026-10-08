---
name: claude-workers
agents: [claude]
description: Claude Code worker tiers (Haiku 5.5, Opus 5.5), their escalation ladder, Anthropic's priors, where work can run (this machine, GitHub Actions, Anthropic's cloud), and running workers from a Claude session. Use with staffing whenever a Claude session starts workers, or when going faster or short of local capacity.
---

# Claude Code workers

Tom's choices (8 Oct): Opus 5.5 medium is the default; no Sonnet, no Opus
low, nothing above Opus high; Fable only when Tom asks.

| Tier | Agent | Start here when |
| --- | --- | --- |
| haiku | `worker-haiku` (Haiku 5.5, high) | Mechanical, fully specified, short: exact edits, ticking and closing issues, running a named check or prepared script and reporting its numbers; lookups and extraction from large logs or documents; triaging an issue list; recurring summaries and status reports. |
| medium | `worker` (Opus 5.5, medium) | Default: features, fixes with a known cause, tooling, docs and skills, setup. |
| high | `worker-high` (Opus 5.5, high) | Multi-step or ambiguous work: unknown-cause debugging, netcode, engine, performance, cross-module work, native checks, research. |

Ladder: haiku, medium, high, then one more high attempt whose brief carries
the failure evidence, then one recommendation to Tom.

## Anthropic's priors

From the launch charts (Opus 5.5, 22 Sep 2026; Haiku 5.5, 7 Oct 2026). They
set a category's start only until the ledger has five closed issues for it.

- Mergeable code changes peak at Opus medium (FrontierCode: medium 54.6%,
  high 54%, xhigh 51%, max 54% at seven times medium's cost).
- Multi-step terminal work and ambiguous multi-file tasks gain from medium to
  high (Terminal-Bench 57 to 64%, CursorBench 52 to 56%). Above high, xhigh
  adds 2 points at twice the cost and max is no better.
- Only knowledge work and long data collection keep gaining above high
  (GDPval 1690 to 1820 Elo at xhigh). Our 27 Opus xhigh runs before 8 Oct
  averaged 76 minutes and 111k tokens, and 6 clearly finished.
- Haiku high beats Opus low on lookup and knowledge work (GDPval 1420 against
  1225 Elo at under half the cost) but not on multi-step coding
  (Terminal-Bench about 22% against 38%). Medium to high is Haiku's cheapest
  large gain on multi-step tool use (OSWorld 53 to 61% for 1.4 times the
  cost), at about a tenth of Opus medium's cost per task. Its max costs what
  Opus medium does and scores no higher, so a failed haiku attempt goes to
  Opus medium, never to a higher Haiku effort.
- Price ratio: Haiku 5.5's tokens cost about a fortieth of Opus 5.5's ($0.10
  and $0.50 against $4 and $20 per million input and output tokens). Its
  prompts over 100k tokens cost five times as much, still an eighth of Opus,
  so reading a large log for one answer stays a haiku task.

## Where work runs

Pick the place by what the task needs, and check all three when going faster
or when the machine is the bottleneck:

- This machine: anything that needs local files, Warcraft clients or Tom's
  install. Sustained multi-core work goes through `machine-capacity`.
- GitHub Actions: farm suites and sweeps; 20 jobs and 5,000 API calls an hour
  shared by every agent (`github-actions`).
- Anthropic's cloud: code-only work in the public smashcraft and wisp repos,
  4 cores per run, landing itself through Autoland (`cloud-workers`). Each
  branch also costs Actions jobs.

## Running them

Start independent workers in the background in one message. At 400k tokens
of context the worker-handoff hook tells a worker to write a handoff note and
stop; start a fresh worker of the same tier from the note, or request a
handoff sooner. The parent session compacts at 600k. Keep
`worker-sweep --wait` running: it wakes the parent when a worker has been
idle 20 minutes or needs a handoff. `worker-ledger` records a run with model
Haiku as tier `haiku`, whatever agent type started it.

The parent stops its own monitors and background shells once nothing needs them; a finished worker's row clears by itself after about 30 s, and a row that lingers means a background task is still running. The subagent-teardown hook refuses a worker's finish while its own background shells or Monitor watches still run.
