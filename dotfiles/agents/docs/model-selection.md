# Model and payload selection

This file is the personal adapter, not another routing doctrine. Normative
semantics live in `~/code/gaffer/doctrine.md` and
`~/code/gaffer/docs/routing.md`; provider/account allocation lives in
`~/code/north/docs/provider-architecture.md`. If this file disagrees with
either, those sources win.

Shared policy never chooses a concrete provider model, account, SDK, or
subscription pool. Gaffer describes the work; North resolves an executable
runtime and records both the request and the result.

## Compose the semantic request

Decide each Gaffer axis independently:

1. `role` names the responsibility and deliverable. Start with a canonical
   preset. If none fits, author a fully specified bespoke composition.
2. `taskGrade` describes the work's scope and expected judgment: `novice`,
   `junior`, `mid`, `senior`, `staff`, `principal`, or `research-grade`.
3. `domainRequirements` states expertise/context the brief must actually load.
4. `topology` is coordination authority: `worker` or `orchestrator`. Verifier
   and judge are worker roles, not topologies. Choose from dependency shape;
   importance alone does not justify an orchestrator.
5. `tier` is the capability floor: `economy`, `standard`, `senior`, or
   `frontier`. Task shape, leverage, blast radius, and foundational-layer floors
   inform it; provider names do not.
6. `reasoning` is deliberation: `low`, `medium`, `high`, `xhigh`, or `max`.
   It remains independent from tier, but the pair must be supported by a
   provider catalog.
7. `posture` is `explore`, `deliver`, or `preserve`.
8. `composition` records provenance: exact preset, preset plus explicit
   overrides/reason, or a complete bespoke contract.

Presets are defaults, not coupled identities. An override changes only the
named axes and records why. A bespoke composition requires responsibility,
deliverable, canonical capabilities, decision authority, escalation bounds,
done criteria, and report shape; `nearestPreset` is optional and grants no
authority.

## Send the complete request

The managed MCP envelope contains the eight Gaffer fields plus North-owned
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
`north spawn <preset> "<prompt>"` hydrates a known preset mechanically.
Delegation is dependency-shape classified rather than a director alias:

```sh
north delegate "<task>" --role <worker-role> [spawn options] # atomic
north delegate "<task>" --composite [spawn options]          # composite
```

The intelligent `/delegate` adapter makes that decision while preserving one
user-facing verb. Atomic work selects exactly one terminal worker composition:
an unchanged preset, a preset with explicit axis overrides and an
`--override-reason`, or a fully specified bespoke role with rationale and a
structured contract. Presets are defaults, not a closed vocabulary; repeated
bespoke use is recorded for possible human promotion review, and North renders
its provenance as `gaffer:bespoke:<id>` rather than a generic `custom` or
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
Gaffer's provider catalogs. It may substitute provider/account/model only
before side effects and only while preserving tier, reasoning, and authority.
Any degradation is explicit and recorded.

Concrete model names, temporary availability windows, usage endpoint details,
and per-provider calibration belong under `~/code/gaffer/providers/`,
`~/code/gaffer/docs/`, and North's provider adapters. Never copy them into
shared spawn policy, never route through API keys or API-credit balances, and
never use native provider inheritance as a substitute for an explicit Gaffer
request.

Personal domain/posture defaults live in
`~/code/nixos-config/dotfiles/agents/docs/praxis/README.md`.
