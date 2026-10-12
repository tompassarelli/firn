# NixOS configuration

- Keep host credentials in the private overlay with sops-nix (docs/secrets.md); firn holds no secrets.
- Treat this repository and its issues as public: keep Tom's location, email and other personal data out of issues, comments, commits and docs.
- Write Galileo `.gal` sources and compile them through `firn repo build`; never edit generated `.nix`.
- Ask the runtime's `galileo help`, `galileo refs` and `galileo schema explain` (pinned by `config/galileo-revision`) for uncertain compiler/schema facts.
- Compose one package/service per module through `myConfig.modules.*` and declared tags; let dynamic imports discover modules.
- Verify `whiterabbit` and `nexus`; use `firn rebuild` for exact committed snapshots on the laptop and `firn host deploy nexus` (from a checkout at origin/main of the repo nexus upgrades from) for nexus.
- Keep general commands under `dotfiles/bin/` and repository commands in entity-first `firn`.
- Route agent tools, hooks and skills to north; route secrets, host identity, Tom's policy and account skills to south.
- Public and reusable goes to north or firn; Tom-specific or secret goes to south.

## Routes

Use `firn --help` and its topic help for commands.
Use the `firn` skill for configuration changes and `agent-policy` for policy activation.
Read `modules/north-profile/firn/docs/nixos-config-rules.md` for source/module/tag/dotfile detail.

## Checks

Tests follow `north:harness/skills/testing/SKILL.md`; see `docs/verification.md`.
After .gal edits, run `firn repo build` then `firn repo validate`.
For agent policy, run `~/code/north/main/harness/scripts/agent-config-check.sh`.
For activation, run `~/code/north/main/harness/scripts/agent-config-check.sh --local`.
