---
name: agent-policy
description: >-
  Author, restructure, register, or debug personally owned AGENTS.md policy,
  Codex skills, hooks, modules, and North activation metadata. Use whenever
  changing agent instructions or skills, deciding what stays always loaded
  versus trigger-on-demand, locating a projected policy source, or verifying
  that one North activation generation reaches provider surfaces.
---

# Agent policy

Keep one source for each rule and make its loading scope match its trigger.

## Locate authority before editing

Run `agents status`, `agents inspect <id>`, and `agents path <id>` to read
North's current immutable activation generation. The `agents` command is only a
stable Firn client of `north config agents`; it owns no catalog, permission
state, resolver, or projector.

North composes the catalog only from the exact owners declared in
`north:agent-catalog/sources.json`. Those source catalogs give every globally
unique ID exactly one kind (`skill`, `hook`, or `module`) and one exact owner
`repo:path`. Never edit `~/.agents`, `~/.codex`, `/etc/codex`, or a
generation under `~/.local/state/north/agents`. Read each owning repository's
root `AGENTS.md` and use repo-safety for its write and landing path.

## Choose the loading layer

Keep only rules that must constrain every applicable action in `AGENTS.md`:
safety boundaries, authority and source-of-truth declarations, project
architecture invariants, and irreversible-operation rules. State each once,
at the narrowest directory that always covers its action.

Put a coherent optional workflow in one skill when a user request or task
shape can trigger it reliably. The frontmatter description must name both the
capability and concrete trigger phrases or contexts. Do not create aliases,
compatibility copies, decorative categories, or tiny one-paragraph skills.
Delete replaced prose after the skill is registered and activation is proved.

Use a Module only when several skills, hooks, modules, instruction payloads, or
agent templates must activate as one recursive unit. Modules recursively
compose skills, hooks, and other modules; they are not a second kind of skill.
Instruction files and template trees are distributions attached to a
catalogued unit; they are never hidden members or extra unit kinds.

## Create or revise a skill

Use the system skill-creator for skill structure, frontmatter, interface
metadata, and validation. Keep this skill authoritative only for ownership,
registration, activation, and projection behavior.

Register the unit once in North's catalog with its exact source-owning
`repo:path`, trigger metadata, support relations, and distribution targets.
The catalog may point into NixOS or Beagle; never copy an owner-local source
into North merely to activate it. A global ID cannot collide across kinds, and
a rename is one atomic replacement with no compatibility alias.

Permission and activity are separate. Stored permission says whether a unit
may run; resolved activity also requires an active parent or supported
claimant. North resolves both once, retains all module/support provenance, renders
every projection into a private generation, and atomically advances `current`.
Provider adapters read that generation and never resolve activity themselves.

Hooks remain enforcement or telemetry mechanisms with explicit provider
wiring. The North catalog records which units a hook supports; skill
frontmatter does not mirror that relation. Never copy hook behavior into skill
prose or treat prose as enforcement. Each provider lifecycle hook keeps its
exact source identity and does not pretend to be a `PreToolUse` guard.

## Validate and activate

Run the skill-creator validator for each standard skill. Validate extended
frontmatter and provider wiring with the nearest catalog/provider fixture.
Do not rebuild the system for an owner-local out-of-store skill source.

After all owner and North catalog commits land and their clean `main`
checkouts are current, run:

```text
agents sync
agents on <id>
agents status
agents inspect <id>
agents path <id>
```

Require `~/.local/state/north/agents/current/activation.json` to report schema
`north.agent-activation/v1`, one exact generation/digest identity, the expected
owner, permission, activity, provenance, and activation paths. Confirm every
reported path resolves to landed owner authority rather than a lane or live
projection, then reap finished worktrees and branches.
