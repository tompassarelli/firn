# Model and payload selection

This file is the personal adapter, not another routing doctrine. Normative
semantics live in `north:orchestration/doctrine.md` and
`north:orchestration/docs/routing.md`; provider/account allocation lives in
`north:docs/provider-architecture.md`. If this file disagrees with
either, those sources win.

Shared policy never chooses a concrete provider model, account, SDK, or
subscription pool. Orchestration describes the work; North resolves an executable
runtime and records both the request and the result.

## Compose the semantic request

Decide each Orchestration axis independently:

1. `role` names the responsibility and deliverable. Start with an exact stock
   template when its responsibility, deliverable, done criteria, report shape,
   and fixed topology/capability boundary fit. Override only task grade,
   domains, tier, reasoning, or posture, with a reason, while those properties
   remain unchanged. Any topology/authority change — or a different
   responsibility, deliverable, done criteria, report shape, or capability
   boundary — requires a fully specified bespoke composition.
2. `taskGrade` describes the work's scope and expected judgment: `novice`,
   `junior`, `mid`, `senior`, `staff`, `principal`, or `research-grade`.
3. `domainRequirements` states expertise/context the brief must actually load.
   It is prompt/context metadata, not proof of connector capability,
   authentication, or pre-turn authority. Deterministic Linear operations use
   the separate `north linear` surface.
4. `topology` is coordination authority: `worker` or `orchestrator`. Verifier
   and judge are worker roles, not topologies. Choose from dependency shape;
   importance alone does not justify an orchestrator.
5. `tier` is the capability floor: `economy`, `standard`, `senior`, or
   `frontier`. Task shape, leverage, blast radius, and foundational-layer floors
   inform it; provider names do not.
6. `reasoning` is deliberation: `low`, `medium`, `high`, `xhigh`, or `max`.
   It remains independent from tier, but the pair must be supported by a
   provider catalog.
7. `posture` is `explore`, `deliver`, `evaluate`, or `preserve`. `evaluate`
   orders its priorities as evidence quality, decision correctness, coverage,
   speed, then polish. It licenses adversarial probes, reproduction, and an
   explicit `cannot-determine` result; it forbids unsupported verdicts,
   criteria invented after seeing results, and modification of the artifact
   under evaluation.
8. `composition` records provenance: exact template, template plus explicit
   overrides/reason, or a complete bespoke contract. The compatibility wire
   retains `composition.kind:"preset"` for templates and `nearestPreset` for
   the optional nearest-template hint.

Templates are reusable defaults for common input-to-deliverable shapes, not
mandatory identities or a closed role vocabulary. An override changes only
the named axes and records why; it is not a way to disguise a different
deliverable. A bespoke composition requires responsibility, deliverable,
canonical capabilities, decision authority, escalation bounds, done criteria,
and report shape; `nearestPreset` is optional and grants no authority.

Verifier and judge remain distinct worker roles. A verifier decides one claim:
affirmative evidence can confirm it, counterevidence can refute it, and
ambiguous or missing coverage yields `cannot-determine`. A judge compares
multiple supplied alternatives against criteria declared before scoring and
rejects a comparison whose candidates or criteria are not actually comparable.

## Attach verification to the outcome

Verification is neither a third topology nor a mandatory verifier after every
worker. A self-contained terminal worker supplies evidence against its local,
objective done-bars; add a context-carrying verifier sibling only when the
leverage of a plausible wrong verdict warrants independent attestation. When
several pieces produce an emergent aggregate, the director always assigns a
context-carrying verifier sibling to independently attest the whole outcome —
per-piece evidence does not prove the integration. The verifier reports a
per-claim verdict, probe, and observed result. The director consumes and
reconciles that evidence and may spot-check at most one suspicious load-bearing
claim; rerunning completion probes wholesale is worker execution.

## Send the complete request

The managed MCP envelope contains the eight Orchestration fields plus North-owned
execution controls and the prompt:

```json
{
  "prompt": "implement the bounded change",
  "provider": "auto",
  "role": "implementer",
  "taskGrade": "mid",
  "domainRequirements": [],
  "topology": "worker",
  "tier": "standard",
  "reasoning": "medium",
  "posture": "deliver",
  "composition": {"kind": "preset", "id": "implementer", "overrides": []}
}
```

Direct `mcp__north__spawn` callers send this complete object. The forcing CLI
`north spawn <template-id> "<prompt>"` hydrates a known template mechanically;
its emitted machine payload still uses `composition.kind:"preset"`. Run
`north templates` to inspect the stock catalog and its resolved routing
defaults before selecting one.
Delegation is dependency-shape classified rather than a director alias:

```sh
north delegate "<task>" --role <worker-role> [spawn options] # atomic
north delegate "<task>" --composite [spawn options]          # composite
```

The intelligent `/delegate` adapter makes that decision while preserving one
user-facing verb. Atomic work selects exactly one terminal worker composition:
an unchanged template, a template with explicit axis overrides and an
`--override-reason`, or a fully specified bespoke role with rationale and a
structured contract. Templates are defaults, not a closed vocabulary; repeated
bespoke use is recorded for possible human promotion review, and North renders
its provenance as `orchestration:bespoke:<id>` rather than a generic `custom` or
missing-composition label. Composite work alone hydrates the canonical director,
which owns fan-out and reduction.
Importance and difficulty do not substitute for two independently executable
units. Managed North paths fail closed rather than inventing a mode or missing
axes.

Context carriage is orthogonal: `--context <file>` may accompany either form;
the chat adapter carries a concise session brief by default and `/delegate
<task> --new` omits it. The chat adapter leaves provider/account allocation on
North's automatic policy by default and forwards a pin only when the user or
task explicitly requires one; account pins are exceptional, and it never
infers either pin from the current provider session. Concrete model selection
remains provider-catalog/North-owned unless a supported explicit override
contract says otherwise.

## Runtime allocation

Use `provider:"auto"` unless the user or task explicitly pins a provider or
account. North filters for authentication and enforceable capabilities, reads
provider subscription-usage signals, applies the configured balanced,
preferential, or reserved allocation policy, and resolves tier+reasoning via
Orchestration's provider catalogs. It may substitute provider/account/model only
before side effects and only while preserving tier, reasoning, and authority.
Any degradation is explicit and recorded.

Concrete model names, temporary availability windows, usage endpoint details,
and per-provider calibration belong under `north:orchestration/providers/`,
`north:orchestration/docs/`, and North's provider adapters. Never copy them into
shared spawn policy, never route through API keys or API-credit balances, and
never use native provider inheritance as a substitute for an explicit Orchestration
request.

Personal domain/posture defaults live in
`~/code/nixos-config/dotfiles/agents/docs/praxis/README.md`.
