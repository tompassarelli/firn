# Model selection for parallel work

Picking the right model — *and* effort level — per agent when fanning out. Cost
spread is real (~10× Haiku→Fable on price, ~12× more low→max on effort), so a
wrong setting on a 10-agent fan-out wastes money *and* wall-time.

Pricing / IDs / limits: authoritative source is the bundled `claude-api` skill
(cached 2026-06-04) or the Models API — not blogs (they lag releases and quote
stale prices).

## Two dials, not one ladder

**Match the setting to the task's reasoning demand, not its importance.** A
"critical" rename is still mechanical → sonnet-low; a throwaway prototype's
architecture is still judgment → Opus. Reaching for Opus "because this matters"
is how money burns on grep-shaped work.

Model and effort are **orthogonal**, not a single 1–9 scale:
- **Model = capability ceiling** (+ cost/speed) — raises what's *possible*.
- **Effort = deliberation depth** on a fixed ceiling — more thinking / tool calls
  / self-checking. A behavioral signal, not a hard budget: at low effort the
  model still thinks on hard problems, just less. (Haiku has *no* effort dial —
  passing `effort` errors.)

Off-diagonal proves they don't collapse: **opus-low** (high ceiling, snap
judgment) vs **sonnet-high** (modest ceiling, many careful steps). And they trade
— Anthropic measured **Opus 4.5 at medium matching Sonnet 4.5's best SWE-bench
score on 76% fewer tokens**: higher ceiling + lower effort beats lower ceiling +
full effort, cheaper. Pick both dials per task.

## The stack

- **sonnet-low** — discovery, triage, locate, read-only fan-out, corpus reads,
  research sweeps. Replaced Haiku as the cheap-wide tier (2026-07-03; below).
- **sonnet-medium** — well-specified build/edit/summarize/extract. The "use
  Sonnet" workhorse (alias policy below).
- **Opus** — judgment: architecture, cross-file refactors, ambiguous debugging,
  adversarial verify/judge, synthesis. The top implementer.
- **Fable** — above Opus: hardest analysis, no-priors design, root-cause,
  research synthesis, planning; the coordinator tier alongside Opus. Never the
  default implementer (own section below).
- **Haiku** — single-shot bulk text ONLY (classify/extract/summarize; one shot
  in, one shot out, NO tool chains). Off the default stack (below).

IDs / prices / context: query the Models API or the `claude-api` skill — never
a static table here. Opus's edge over Sonnet is the hard tail, not the median
task. **Start one bucket lower than feels right on both dials, then escalate**
— promotion is cheap to find; over-provisioning is silent waste (one-low cut
tokens 30–50% with no quality loss).

## Haiku — demoted to single-shot bulk work (2026-07-03)

Haiku 4.5 is two generations stale (no Haiku 5 announced), rejects the `effort`
param (400 error), and has a confirmed agentic failure mode: **tool-loops** —
re-calls already-completed tools, stalls multi-step plans
(anthropics/claude-code#10029), hallucinates optional tool params. One looped
or retried worker erases the price gap AND produces claims that cost extra
Opus/Fable verification — verification is the expensive currency, so a cheap
finder that lies is negative-value.

Price reality (2026-07): Haiku $1/$5 per MTok; Sonnet 5 $2/$10 intro through
Aug 31 2026, then $3/$15 — and Sonnet 5's new tokenizer emits ~30% more tokens
for the same text, so the effective gap is ~2.6× now, ~3.9× after Sept 1.
Still worth paying wherever a tool chain exists.

Haiku's remaining slot: **single-shot bulk** classify/extract/summarize — one
prompt in, one answer out, zero tool iterations, high volume. The loop bug
can't fire there and the discount is real.

The true Haiku successor is likely off-Anthropic: Gemini 2.5 Flash
($0.30/$2.50 — 3× cheaper than Haiku, better tool-use reputation) via LiteLLM
proxy → `ANTHROPIC_BASE_URL` into the Agent SDK. Not built; candidate tern SDK
`flash` tier.

## Personal overrides — greenfield / compiler work

The tables above assume tasks *with priors* — that's what SWE-bench measures. My
actual work (compiler, innovative greenfield) often **lacks priors**, so Sonnet's
near-Opus benchmark parity does *not* transfer. **General law, wider than
models: any guidance calibrated on run-of-the-mill work — benchmark parity,
effort ladders, YAGNI/code-minimization ladders — silently mis-advises
priors-poor core work. Before applying a tested default, ask what corpus it
was tested ON.** Bend the defaults:

- **Ambiguous or novel → Opus, as the main agent.** Don't default that work to
  Sonnet. The benchmarks are positive but priors-rich; design work without priors
  is exactly where Opus's ceiling earns its cost.
- **Promotion trigger:** if Sonnet is **taking longer than it should** —
  thrashing, retrying, over-exploring — that's it hitting its ceiling. Promote to
  Opus; don't prompt around it.
- **Sonnet is its own usage bucket** on the Max account — cuts both ways
  *(UNVERIFIED against the 2026-06 plan change: reports say Max moved to one
  unified 5h rolling pool plus a separate monthly credit bucket for
  non-interactive/SDK use. Check /usage before leaning on bucket-splitting;
  the preserve-Opus-headroom logic below survives either way)*:
  - *Use it more than we currently do.* Routing well-trodden build tasks to Sonnet
    spends the Sonnet pool and **preserves Opus headroom** for the hard work — free
    parallel capacity we're leaving on the table.
  - *When the Sonnet bucket is exhausted, disregard the "use Sonnet" guidance* —
    route those build/workhorse tasks to **Opus** (Haiku still covers the
    single-shot bulk subset). Sonnet is the optimization, not a requirement.

Net default for this work: **sonnet-low** discovery/mechanical (Haiku only for
single-shot bulk) · **sonnet-medium** well-trodden build *while the bucket
lasts* · **Opus** anything novel/ambiguous or Sonnet visibly struggling ·
**Fable** the hardest analysis/planning (never default implementation).

## Effort: the second dial

Effort hits *all* tokens — text, tool calls, thinking. Lower → fewer/consolidated
tool calls, less preamble (so fan-out workers run low: you don't *want* them
wandering). Cost ladder (illustrative, third-party): low/med/high/max ≈
**1× / 2.5× / 6× / 12×** output tokens — max is not "a bit more."

Tested task → effort (kentgigger.com):

| Task | Effort | Why |
|---|---|---|
| rename a var / fix a typo | low | pattern-match, no traversal |
| batch rename across ~12 files | **medium** | low missed callers → 3 broken imports; max took 4 min at ~50× cost for no gain |
| write tests against a known function | medium | no deep reasoning |
| debug an unresolved auth race condition | **max** | root cause in 5 min after 1 hr manual — paid for itself |

The 12-file rename is the lesson: both dials have failure modes — too low breaks
correctness, too high burns cost for nothing.

## Sonnet 5 — alias + routing policy (landed 2026-07-02)

Since claude-code **2.1.198** (overlay pin `claude-code-latest` in flake.bnix)
the `sonnet` alias resolves to Sonnet 5. Policy:

- **"use Sonnet" = Sonnet 5 at *medium* effort.** That is the workhorse setting.
- **Don't climb Sonnet's effort ladder.** Harder than sonnet-5-medium ⇒ escalate
  the MODEL (Opus, or Fable for the hardest judgment/novel work), never sonnet
  high/xhigh — a higher ceiling at modest effort beats a maxed lower ceiling
  (same lesson as the Opus-4.5-medium vs Sonnet-4.5-best datapoint above).

**Enforcement — sonnet must NOT inherit a hot session's effort** (an ultracode
session runs xhigh; a bare `model: 'sonnet'` spawn would silently run
sonnet-xhigh, the exact anti-pattern):

- **Workflow `agent()`** — always pair them: `{model: 'sonnet', effort: 'medium'}`.
  Effort inherits the session unless set per call.
- **Agent tool** — has NO per-call effort param; effort inherits the session.
  Spawn the **`sonnet-worker`** agent (frontmatter pins `model: sonnet` +
  `effort: medium`, `~/code/nixos-config/dotfiles/claude/agents/sonnet-worker.md`) instead of
  `general-purpose` + `model: "sonnet"`.
- Agent frontmatter supports `effort: low|medium|high|xhigh|max`; there is no
  global `CLAUDE_CODE_SUBAGENT_EFFORT` env (only `..._MODEL`).

## Fable — analyst/planner tier, NOT the implementer

Fable sits above Opus (Mythos-class ceiling). Its edge is the hardest
*analysis*: architecture with no priors, root-causing thorny bugs, research
synthesis, adversarial judgment, planning. It is **not the coding tier**:

- **Coding/editing/building default to the standard ladder** (sonnet-low →
  sonnet-medium → Opus). Opus is the top implementer.
- **Escalate implementation to Fable only on a real blocker**: Opus has
  repeatedly failed the same defect, or the fix hinges on analysis Opus can't
  crack. Deliberate, per-task — never a default route.
- **Shape**: Fable diagnoses/plans → Opus/Sonnet implement → review at Opus.
- **Inheritance trap**: a coordinator session running on Fable leaks it —
  Workflow `agent()` without `opts.model` and the Agent tool both inherit the
  session model. In a Fable session, explicitly pin `model: 'opus'|'sonnet'`
  on every implementation spawn.

## Routing patterns for fan-out

Tiered routing vs uniform-Opus cut cost **~50–80%, no quality regression**
(tested, multiple sources). Converging patterns:

- **Routed stack** — sonnet-low discovers/triages → sonnet-medium builds → Opus
  judges → Fable plans/analyzes the hardest. Default shape.
- **Planner / executor** — Opus/Fable orchestrator (1–2 calls, holds context) →
  Sonnet executors (N/step) → sonnet-low sub-tools. Maps to coordinator/worker.
- **Confidence-gated escalation** — start every item on sonnet-low; →
  sonnet-medium on low confidence, → Opus on a second failure. Most items
  terminate at the bottom tier. Best when difficulty is unknown up front.
- **Discovery wide, judgment narrow** — cheap-and-wide sweep (sonnet-low) →
  expensive-and-narrow synth/verify (Opus). Verify must NOT reuse the cheap model
  that produced the finding. And model-independent: the coordinator spot-checks
  every load-bearing worker claim itself (grep/`tern show`/direct read) — worker
  reports are claims, not facts, whatever tier produced them.

## How this maps to our tools

- **tern SDK (the PRIMARY spawn surface** while the /my-config dispatch setting is `tern` —
  the native tools below are denied there; see `my-config`): `mcp__tern__spawn`
  takes `{model: opus|sonnet|haiku, effort}` per call; env `AGENT_MODEL` sets
  the dispatch.ts default; `AGENT_CAVEMAN` rides along. Same rule as Workflow:
  pin BOTH dials per spawn — workers must not inherit a hot session's effort.

Native-path mappings (apply only under `my-config dispatch warn|native`):

- **Agent tool** — `model: "haiku" | "sonnet" | "opus" | "fable"`. (A `fork`
  always inherits the parent model; the override is ignored there.)
- **Workflow** — per-agent `opts.model` + `opts.effort` on each `agent()` call.
  Default to omitting `model` (inherits the session model); set it only when
  confident. Use `opts.effort: 'low'` for cheap mechanical stages.
- **Claude Code subagents** — `CLAUDE_CODE_SUBAGENT_MODEL` sets the subagent
  default (e.g. Sonnet) while the main session stays on Opus; per-agent frontmatter
  overrides (the built-in Explore subagent runs on Haiku this way).
- **cavecrew agents** already encode tier intent — honor it:
  - `cavecrew-investigator` (read-only locate) → Sonnet, low (was Haiku — an
    impossible combo with `low`, and tool-chained; re-tiered 2026-07-03)
  - `cavecrew-builder` (1–2 file edit) → Sonnet, medium
  - `cavecrew-reviewer` (severity-tagged diff review) → Sonnet medium, or Opus
    when the diff needs real judgment

## Sources

Tested (ran the workloads): kentgigger.com (effort), ayautomate.com /
augmentcode.com (routing + cost). Other blogs restate Anthropic — taxonomy, no
measurement. **No rigorous public task × model × effort grid exists** — treat
figures as directional and re-check on your own evals.
