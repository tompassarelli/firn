# NixOS configuration

- Keep host credentials in the private overlay with sops-nix (docs/secrets.md); firn holds no secrets.
- Treat this repository and its issues as public: keep Tom's location, email and other personal data out of issues, comments, commits and docs.
- Write NixOS modules in `.nix`, with typed options and guarded configuration.
- Use `firn schema explain` and the selected host's NixOS options for uncertain option types or declarations.
- Compose one package/service per module through `myConfig.modules.*` and declared tags; let dynamic imports discover modules.
- Verify `whiterabbit` and each remote host; use `firn rebuild` for exact committed snapshots on the laptop and `firn host deploy HOST` (from a checkout at origin/main of the repo the host upgrades from) for a remote host with the upgrade unit.
- Keep general commands under `dotfiles/bin/` and repository commands in entity-first `firn`.
- Route agent tools, hooks and skills to north; route secrets, host identity, Tom's policy and account skills to south.
- Public and reusable goes to north or firn; Tom-specific or secret goes to south.

## Routes

Use `firn --help` and its topic help for commands.
Use the `firn` skill for configuration changes and `agent-policy` for policy activation.
Read `modules/north-profile/firn/docs/nixos-config-rules.md` for source/module/tag/dotfile detail.

## Checks

Tests follow `north:agent-machinery/skills/verification/SKILL.md`; see `docs/verification.md`.
After source edits, run `firn check`. After composition metadata edits, run `firn repo build` first.
For agent policy, run `north agent-config-check`.
For activation, run `north agent-config-check --local`.
