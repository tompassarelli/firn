---
description: Delegate this request through North; current context rides by default, --new starts clean
---

# /delegate — thin North adapter

North owns staffing, provider/account allocation, lifecycle, identity, and
observability. Leave provider and account on North's automatic policy by
default; honor and forward an explicit user/task pin, but never infer one from
the current session. Do not select a concrete model or native provider
agent here. Orchestration describes the work; North resolves the runtime.

Parse `$ARGUMENTS` as one task plus an optional trailing `--new`, then make one
intelligent dependency-shape classification. The user still sees one
`/delegate`; the adapter supplies exactly one of North's mechanical modes:

- **Atomic** — one terminal objective with bounded scope, known inputs and
  outputs, and one verification path. Select exactly one worker-topology Orchestration
  role. Use an unchanged canonical preset when it fits; pass semantic axis
  overrides plus `--override-reason` when a preset is close; or improvise a
  lowercase-kebab-case bespoke role with `--rationale`, an optional `--nearest`,
  and a complete structured `--contract @<absolute-path>` containing exactly
  `responsibility`, `deliverable`, `capabilities`, `mayDecide`, `mustEscalate`,
  `doneWhen`, and `report`. Bespoke is a first-class, recorded composition—not
  a failure to use Orchestration. Never select `director` or orchestrator topology for
  atomic work.
- **Composite** — at least two independently executable terminal units whose
  separation improves independence, certainty, or verification more than it
  costs integration. Use `--composite`; North alone hydrates the canonical
  director, which owns decomposition and reduction. Importance, difficulty, or
  a multi-file footprint alone does not make work composite.

Context carriage is independent of that classification:

- Default: carry this session's useful context. Compose a concise brief with
  current state, binding decisions, relevant `~`-anchored artifacts, remaining
  work, the one assumption that would be costly to rediscover, and the
  classification/role rationale. Exclude secrets and transcript filler. Save
  it under the repository's ignored `docs/private/`.
- `--new`: send only a self-contained task and repository/cwd context; do not
  add `--context`.

Run exactly one classified form, appending `--context <absolute-brief-path>` in
the default context-carrying mode:

```sh
# Atomic: <worker options> may be exact preset, recorded overrides, or bespoke.
north delegate "<task text without --new>" --role <worker-role> <worker-options>

# Composite: the only form that selects the director.
north delegate "<task text without --new>" --composite
```

Omit `--provider` and `--target` by default. Forward them only when the user or
task explicitly pins a provider/account; an account pin is exceptional, never
an allocation guess. Never derive a concrete model from the current
session. Concrete model selection remains provider-catalog/North-owned unless a
supported explicit override contract says otherwise. Semantic Orchestration options
such as tier and reasoning remain valid worker options; they do not name a
provider runtime.

The command must return a managed agent handle and `north watch <id>`. Report
those in at most three lines, including `atomic:<role>` or `composite:director`
and whether context was carried. Do not perform the delegated work inline, do
not create a native Agent/Task/Workflow, and do not add a
worker-spawns-verifier exception: Orchestration worker topology never spawns or
commands another agent.

Only answer inline when the request is a one-line factual lookup already
settled by this session's context; state that exception briefly.

Request: $ARGUMENTS
