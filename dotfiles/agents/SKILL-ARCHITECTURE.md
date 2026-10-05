# Skills and hooks architecture

The live catalog is authoritative: `agents status --json`, `agents inspect
<id>`, and `agents path <id>` resolve identities, activity, and source owners.

## Source and activation

- `north:agent-machinery/` owns reusable workflows and run-design contracts.
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

A distilled guide contains the complete ordinary workflow. A reference entrypoint
or supporting topic file holds detail for a specific unresolved question. Keep
scripts, fixtures, and UI metadata with their consuming skill. Reference files
are not additional skills or a second routinely loaded instruction set.

## Provider bindings

`nixos-config:modules/codex/requirements.toml` declares the exact managed Codex
policy: nine PreToolUse bindings for seven guards. The worktree and concrete
model guards each bind both edit and shell events; Firn system policy applies
to every tool. Provider binding contracts live in
`nixos-config:dotfiles/agents/policy-owners.toml` and are checked by
`nixos-config:scripts/agent-policy-contract.py`.

Hook implementations live under `nixos-config:dotfiles/agents/hooks/`; shared
activation support lives under `nixos-config:dotfiles/agents/lib/`. Firn's
provider adapter invokes its separately promoted command implementation.

Keep each hook identity stable across source, activity lookup, provider wiring,
and fixtures. Generic worktree and pin protection remains independent of the
configuration compiler's identity.
