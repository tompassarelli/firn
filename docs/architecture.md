# Architecture

A module owns one package or service in `modules/<name>/default.nix`.
It declares typed options under `myConfig.modules.<name>` and applies its
configuration under `lib.mkIf cfg.enable`. Multi-file modules keep option
and configuration concerns together in that directory.

Module `metadata.json` records tags, opt-in tags, per-tag overrides, platform
support and required flake inputs. Host `tags.json` records enabled tags,
additions, drops, disables and direct module choices. The resolver unions
memberships and applies host edits. The NixOS module system checks the
resulting options and assertions at evaluation. See [TAGS.md](TAGS.md).

`flake.nix` owns inputs, overlays and the system constructors. Dynamic imports
discover module directories. `configuration.nix` owns a host's settings;
private overlay flakes supply secrets and private host identity.

The CLI's command tables and workflow controllers live in `native/` and run
as TypeScript on Bun. `dotfiles/bin/firn` launches that runtime. Configuration
needs no separate compiler. `firn repo build` resolves composition;
`firn check` evaluates and lints before a build. `firn rebuild` uses committed
snapshots, builds the host closure and activates the exact resulting path.

North is promoted independently through `~/.local/share/north/bin/north`.
Firn owns its stable launcher, guard wiring and delivery-liveness entry.
