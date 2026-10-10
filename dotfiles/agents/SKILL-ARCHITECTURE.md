# Skills and hooks architecture

The live catalog is authoritative: `agents status --json`, `agents inspect
<id>`, and `agents path <id>` resolve identities, activity, and source owners.

## Source and activation

- `north:agent-machinery/` owns reusable workflows and the work-ownership contract.
- `nixos-config:dotfiles/agents/` owns operator policy and local hook sources.
- `nixos-config:modules/north-profile/firn/skills/` owns configuration workflows.
- `nixos-config:dotfiles/agents/catalog-config.json` declares owner registrations,
  module/support relationships, and distribution targets.

North composes published sources and permissions into one activation generation.
Its instruction, skill, and provider-hook projections are consumers of those
sources. Edit the owning source and use the sanctioned projection workflow.

Permission is not activity: permitted members may be claimed by an enabled
module, and a supported active unit may activate its hook. Hook execution does
not depend on reading a skill. A declared distribution target does not prove
that a provider invokes an event.

## Guide layout

Each idea is one skill with a plain name. Its `SKILL.md` contains the complete
ordinary workflow; its `references/` folder (`notes.md` plus topic files) holds
detail for a specific unresolved question. Keep scripts, fixtures, and UI
metadata with their consuming skill. Reference files are not additional skills
or a second routinely loaded instruction set.

## Provider bindings

`guard[]` in `nixos-config:dotfiles/agents/policy-owners.toml` is the one
source of provider wiring: each hook's Claude and Codex events, and a reason
for each provider it does not bind. `scripts/agent-policy-contract.py --repo .
--write` generates `modules/north-profile/claude-hooks.json` and
`modules/codex/requirements.toml` from it; the contract rejects a hand edit of
either, a `default.bnix` provider adapter list other than the Codex-bound
hooks plus `providerSupport`, and an undeclared asymmetry. The Codex-only
behavior guard binds every tool before and after it runs, `UserPromptSubmit`
and `Stop`, so a new behavior check is a change to its decider rather than a
new binding.

Hook implementations live under `nixos-config:dotfiles/agents/hooks/`; shared
activation support lives under `nixos-config:dotfiles/agents/lib/`. Firn's
provider adapter invokes its separately promoted command implementation.

Keep each hook identity stable across source, activity lookup, provider wiring,
and fixtures. Generic worktree and pin protection remains independent of the
configuration compiler's identity.
