---
name: agent-policy-distilled
description: >-
  Author, restructure, register, or debug personally owned AGENTS.md policy,
  Codex skills, hooks, modules, and North activation metadata. Use whenever
  changing agent instructions or skills, deciding what stays always loaded
  versus trigger-on-demand, locating a projected policy source, or verifying
  that one North activation generation reaches provider surfaces.
---

# Agent policy, distilled

Keep one authority for every rule and load it at the narrowest scope that always
covers its trigger.

## Boundaries and decisions

- Treat `north:agent-catalog/sources.json` as the composition authority for the
  exact source catalogs that declare globally unique skill, hook, and module
  IDs and their source-owning `repo:path`.
- Never edit projections under `~/.agents`, `~/.codex`, `/etc/codex`, or
  `~/.local/state/north/agents`. Read the owner repository's instructions and
  change its worktree source.
- Keep universally applicable safety, authority, architecture, and irreversible
  operation rules in the nearest `AGENTS.md`. Put a reliably triggered optional
  workflow in one skill. Use a module only to activate several catalogued units
  as one recursive unit.
- Register one identity once. Do not create aliases, compatibility copies,
  forwarding sources, decorative categories, or hidden module members.
- Keep permission distinct from resolved activity. North resolves module and
  support provenance once; provider adapters consume the immutable generation.
- Keep hook enforcement in hook code and provider wiring. Skill prose must not
  duplicate enforcement or pretend a lifecycle event is `PreToolUse`.

## Minimum workflow

1. Read the owner repository's `AGENTS.md` and `repo-safety-distilled` guidance.
2. Run `agents status`, `agents inspect <id>`, and `agents path <id>` to locate
   current authority and activation evidence.
3. Choose `AGENTS.md`, skill, or module from the loading decision above, then
   edit only the owning source in a worktree.
4. For skills, follow `skill-creator`; for catalog/provider changes, validate
   with the nearest focused fixture. Do not rebuild NixOS for an owner-local
   out-of-store skill.
5. After every required owner and catalog commit is landed and clean `main`
   checkouts are current, use `agents sync`, permission the ID, and confirm
   `status`, `inspect`, and `path` all resolve to landed authority.

Stop before activation when any owner commit is unlanded, any reported path
resolves to a lane or projection, or identity/provenance is ambiguous.

Catalog and activation details live in the reference skill; load it only for an
explicit request or a named unresolved detail, per the always-loaded policy.
