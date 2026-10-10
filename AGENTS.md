profile: tooling

# NixOS configuration

- Store credentials under `secrets/` with sops-nix and reference `sops.secrets."name"`.
- Treat this repository and its issues as public: keep Tom's location, email and other personal data out of issues, comments, commits and docs.
- Write Beagle/Nix `.bnix` or explicitly selected Clause modules and compile through `firn repo build`.
- Query Beagle from `~/code/beagle/main` or the immutable Clause pin in `config/clause-revision` for uncertain compiler/schema facts.
- Compose one package/service per module through `myConfig.modules.*` and declared tags; let dynamic imports discover modules.
- Verify `whiterabbit` and `nexus`; use `firn rebuild` for exact committed snapshots on the laptop and `firn host deploy nexus` (from a lane at origin/main) for nexus.
- Keep general commands under `dotfiles/bin/` and repository commands in entity-first `firn`.

## Routes

Use `firn --help` and its topic help for commands.
Use the `firn` skill for configuration changes and `agent-policy` for policy activation.
Read `modules/north-profile/firn/docs/nixos-config-rules.md` for source/module/tag/dotfile detail.
Read `native/nix/README.md` for the focused Clause module check.

## Checks

After .bnix edits, run `firn repo build` then `firn repo validate`.
For agent policy, run `~/code/north/main/socrates/scripts/agent-config-check.sh`.
For activation, run `~/code/north/main/socrates/scripts/agent-config-check.sh --local`.
