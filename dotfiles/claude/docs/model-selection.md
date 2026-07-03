# Model selection for parallel work

**Normative routing lives in the gaffer plugin's doctrine** (injected every
session; edit in `~/code/gaffer`). This doc is the evidence, calibration,
and personal-surface reference BEHIND it — on any conflict, gaffer wins.

Two dials per agent: **model = capability ceiling**, **effort = deliberation
depth**. Orthogonal — opus-low (high ceiling, snap judgment) ≠ sonnet-high
(low ceiling, many careful steps). They trade: Opus-4.5-medium matched
Sonnet-4.5-best on SWE-bench at 76% fewer tokens — higher ceiling at modest
effort beats a maxed lower ceiling. Pricing/IDs: Models API or the `claude-api`
skill, never blogs.

**Tier = the task's reasoning demand, never its importance.** A critical rename
is still mechanical → sonnet-low; a throwaway prototype's architecture is still
judgment → Opus. Start one tier lower than feels right on both dials; escalate
on evidence — promotion is cheap, over-provisioning is silent waste.

## The stack

Anthropic's own /model menu agrees with this shape: Opus = "everyday,
complex tasks" (the recommended default), Sonnet = "routine tasks", Fable =
"hardest and longest-running".

- **sonnet-low** — discovery, triage, locate, read-only fan-out, research
  sweeps, mechanical single-shot edits.
- **sonnet-medium** — the PATTERN-EXTENSION tier, not the workhorse:
  **junior/mid-level dev tasks** — grunt work and/or extremely
  well-specified, relatively simple work; extends established patterns in
  well-trodden, solidified code. **Layer floor:** NEVER
  foundational / architecture / library code, however mechanical the task
  looks — the layer of the stack sets the floor, not apparent difficulty.
  sonnet-high ≈ never: dominated by opus-medium (shingle law, below).
- **Opus — the WORKHORSE, medium…xhigh** — **senior dev / staff engineer /
  tech lead shaped tasks**: frontier work, anything designing something new,
  foundational stack layers, cross-file refactors, ambiguous debugging,
  adversarial verify, synthesis. **Default high; xhigh is the
  preferred building rung** for real frontier work (official guidance:
  xhigh = recommended agentic starting point); medium threads in for
  scoped, well-specified "entry-senior" tasks (e.g. implementation
  escalated from sonnet). opus-max: rare — tends to overthink; only with
  demonstrated headroom, and mostly dominated by fable rungs now.
- **Fable — OPT-IN, availability-gated (high|xhigh when live)** —
  **architect/inventor grade, especially on weak existing priors**:
  hardest analysis, no-priors design, root-cause, planning. NOT a standing
  rung: the Max-plan Fable window is limited and week-scoped (verified
  2026-07-03; treat any availability belief older than ~7 days as stale;
  only the USER can run `/usage` — unknown ⇒ assume out). Route to Fable
  only when the task is truly above Opus AND the bucket is verified live.
  **Fallback when out: opus-xhigh tops the ramp; substitute capacity with
  structure** (judge panels, adversarial verify, loop-until-dry).
  Coordinator tier. Never default implementer. Own usage bucket. **Spawned fable work: xhigh** (pre-filtered hardest; no rung
  above — a re-run costs more than the effort delta). Sessions: high. max
  reserved for extremely critical junctures with demonstrated headroom —
  officially gated on "evals show measurable headroom at xhigh"; documented
  overthinking failure modes (judgment reversal, spurious complexity).

**Shingle law:** each model has ~2 practical effort rungs, and a model's top
rung is dominated by the next model's bottom rung (sonnet-high ⊂
opus-medium; opus-max mostly ⊂ fable-high *when Fable is live*). The
STANDING ramp: sonnet-low → sonnet-medium → opus-medium → opus-high/xhigh.
Fable rungs (high → xhigh → max, rare) extend it ONLY when the bucket is
verified available. Route on the ramp, not per-model dials.
- **Haiku** — single-shot bulk classify/extract ONLY, NO tool chains: tool-loop
  bug (anthropics/claude-code#10029), rejects `effort` (400), two gens stale.
  One looped worker erases the price gap and emits claims that cost Opus-tier
  verification. True successor is off-Anthropic (Gemini Flash via LiteLLM →
  `ANTHROPIC_BASE_URL`); unbuilt — candidate tern `flash` tier.

## Route by task shape, not difficulty

First triage question (dial 1): is this task execution, implementation,
integration, design, or invention?

- **execute** — bounded, mechanical: apply patch, rename, obvious tests → sonnet-low
- **implement** — one feature/fix inside known patterns → sonnet-medium
- **integrate** — cross-file, ambiguous debugging, refactor with behavior at
  stake → Opus
- **design** — choose the shape: APIs, lifecycles, decomposition → Opus;
  Fable only when no priors
- **invent** — is the primitive itself right? what should exist? → Fable
  plans, Opus implements/reviews

Shape picks the MODEL; effort is still set separately (dial 2). Difficulty ≠
shape: a hard-but-local testable bug is still *implement* (unless the priors
law fires); a one-line naming decision that shapes an API is *design*. **Blast
radius routes up; importance alone never does** — blast radius = the decision
shapes the system going forward, importance = the outcome matters to the user.
"Coordinates agents" is not a spawn shape — that's the session itself.

**Layer floor overrides shape:** *implement* on foundational / library /
architecture code routes to Opus regardless of how mechanical it looks —
Sonnet only extends established patterns in solidified code. Frontier =
Opus; well-trodden extension = Sonnet.

Dials 3–4 (role authority, posture) are cached as paste-ready spawn blocks
in the gaffer repo (`~/code/gaffer/docs/` — roles, postures, model deltas;
canonical). Personal domain-posture defaults:
`~/code/nixos-config/dotfiles/claude/docs/praxis/README.md`. Compose, don't
re-derive; keep assembled payloads ≤ ~60 lines.

## Buckets (Max plan, /usage-verified 2026-07-03)

One unified pool: sonnet/opus/haiku. **Fable: own bucket.** So Sonnet routing =
cheaper draw on the shared pool (cost-weighting, not free capacity), and Fable
coordination spends no worker budget. Pool hot → push hardest work up to Fable;
Fable hot → coordinator drops to Opus. Re-check /usage when tight.

## Priors law (compiler / greenfield work)

Benchmarks measure priors-rich work. **Any default calibrated on
run-of-the-mill corpora — benchmark parity, effort ladders, YAGNI ladders —
mis-advises priors-poor core work. Ask what corpus it was tested on.**
Ambiguous or novel → Opus as the main agent. Sonnet thrashing / retrying /
over-exploring = ceiling hit → promote the model, don't prompt around it.

## Effort

Effort hits all tokens (text, tool calls, thinking). Cost ladder ≈
**1× / 2.5× / 6× / 12×** for low/med/high/max. Fan-out workers run low — you
don't want them wandering.

| Task | Effort |
|---|---|
| rename a var, fix a typo | low |
| batch rename across ~12 files | medium — low broke imports; max = ~50× cost, no gain |
| tests against a known function | medium |
| unresolved auth race condition | max — root cause in 5 min after 1 hr manual |

## Sonnet alias policy

`sonnet` = Sonnet 5 (claude-code ≥ 2.1.198). **"Use Sonnet" = sonnet-5 at
medium.** Harder ⇒ escalate the MODEL, never sonnet high/xhigh. **Pin BOTH
dials on every spawn** — a bare `model:'sonnet'` inherits the session's effort
(ultracode runs xhigh: the exact anti-pattern).

- Workflow `agent()`: always paired — `{model:'sonnet', effort:'medium'}`.
- Agent tool has no effort param → spawn a gaffer squad agent
  (`gaffer:implementer` = sonnet-medium + delta; `gaffer:executor` = sonnet-low), not
  general-purpose + `model:"sonnet"`.
- Agent frontmatter takes `effort: low|medium|high|xhigh|max`; there is no
  global effort env (only `CLAUDE_CODE_SUBAGENT_MODEL`).

## Fable

Analyst/planner, not implementer. Coding ≤ Opus. Escalate implementation to
Fable only after Opus repeatedly fails the same defect. Shape: Fable
diagnoses/plans → Opus/Sonnet implement → Opus reviews. **Inheritance trap**:
in a Fable session, Workflow `agent()` and the Agent tool inherit fable — PIN
`model:'opus'|'sonnet'` on every implementation spawn.

## Routing patterns

Tiered routing vs uniform-Opus: ~50–80% cheaper, no quality regression (tested).

- **Routed stack** (default) — sonnet-low discovers → sonnet-medium builds →
  Opus judges → Fable plans/analyzes the hardest.
- **Planner/executor** — Opus/Fable orchestrator → Sonnet executors →
  sonnet-low sub-tools.
- **Confidence-gated** — start sonnet-low; low confidence → sonnet-medium;
  second failure → Opus. Best when difficulty is unknown.
- **Discovery wide, judgment narrow** — sonnet-low sweep → Opus verify. The
  verifier never reuses the finder's model, and the coordinator spot-checks
  load-bearing claims itself whatever the tier.

## Spawn surfaces

- **tern SDK** (PRIMARY while /my-config dispatch=tern; native tools denied
  there): `mcp__tern__spawn {model: opus|sonnet|haiku, effort}` — pin both.
  `AGENT_MODEL` sets the dispatch default; `AGENT_CAVEMAN` / `AGENT_LAWS` /
  `AGENT_ESO` ride along.
- **Agent tool** (native mode): `model: haiku|sonnet|opus|fable`. Forks always
  inherit the parent model.
- **Workflow**: per-call `opts.model` + `opts.effort`; omit model to inherit;
  `effort:'low'` for mechanical stages.
- **Claude Code subagents**: `CLAUDE_CODE_SUBAGENT_MODEL` sets the default;
  per-agent frontmatter overrides (built-in Explore runs Haiku).

## Sources

kentgigger.com (effort, tested); ayautomate / augmentcode (routing, tested);
platform.claude.com effort docs + Fable 5 prompting guide (official per-model
effort guidance, web-verified 2026-07-03). Still no public per-effort
benchmark table for Fable 5 — the high/xhigh/max guidance is official but
qualitative; figures directional; re-check on own evals.
