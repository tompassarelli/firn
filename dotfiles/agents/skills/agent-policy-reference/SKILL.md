---
name: agent-policy-reference
description: >-
  Detailed agent-policy reference for catalog ownership, loading-layer
  selection, skill and hook registration, North activation resolution, and
  provider projection evidence. Use after agent-policy-distilled routes here.
---

# Agent policy reference

`agent-policy-distilled` owns the policy decisions and stop conditions. Use
this unit for their detailed procedure and evidence model.

## Locate authority

Use the stable Firn client to inspect the current immutable generation:

```text
agents status
agents inspect <id>
agents path <id>
```

The client delegates to `north config agents`; it owns no catalog, resolver,
permission state, or projector. Correlate the reported ID with exactly one row
in `north:agent-catalog/catalog.json`. That row supplies the kind, exact owner
`repo:path`, trigger metadata, support relations, and distributions.

## Loading-layer selection

| Need | Unit | Registration consequence |
| --- | --- | --- |
| Rule constrains every applicable action | nearest `AGENTS.md` | instruction distribution |
| Coherent workflow has a reliable request/task trigger | skill | one skill ID and owner |
| Several catalogued units activate together | module | recursive member closure |
| Enforcement or telemetry at a provider event | hook | exact event wiring and support provenance |

Instruction files and template trees are distributions attached to catalogued
units, not additional unit kinds. Modules compose already catalogued skills,
hooks, and modules.

## Skill and hook registration detail

Create or revise a standard skill with the system `skill-creator`: precise
frontmatter, focused body/resources, matching interface metadata when present,
and `quick_validate.py`. Add its exact owner path to the North catalog once.

For hooks, keep the implementation and lifecycle source identity exact. Record
which units a hook supports in the catalog rather than skill frontmatter. A
provider wrapper retains its actual lifecycle event and consumes North's
resolved activity; it does not independently resolve module closure or claims.

## Resolution and projection model

Stored permission answers whether a unit may run. Resolved activity additionally
requires an active parent or supported claimant. North retains all module and
support provenance, renders provider projections into a private generation,
and atomically advances `current`. Provider adapters read that generation.

After source and catalog publication, run:

```text
agents sync
agents on <id>
agents status
agents inspect <id>
agents path <id>
```

Inspect `~/.local/state/north/agents/current/activation.json`. Expected evidence
is schema `north.agent-activation/v1`, one generation/digest identity, the exact
owner, stored permission, resolved activity, full provenance, and provider
activation paths. Resolve each path and confirm it points to landed owner
authority. Finished owner lanes and branches can then be reaped through the
owner repository's safety workflow.
