<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/firn-logo.png" width="150">
    <source media="(prefers-color-scheme: light)" srcset="assets/firn-logo-dark.png" width="150">
    <img alt="firn" src="assets/firn-logo.png" width="150">
  </picture>
</p>

**firn is a NixOS framework with ordinary Nix modules and a Bun CLI.**

`firn check` catches unknown options, option type errors and failed assertions
through NixOS evaluation before building. It also runs statix, deadnix and
nixfmt. Enable `nixd` or `nil` in your editor for diagnostics while editing.
Modules declare typed options and guard configuration with `lib.mkIf`.

## What is in this repository

- **The framework.** The `firn` CLI (`dotfiles/bin/firn`, `native/`), `lib.mkSystem`, the tag resolver, the validator, tests and the starter [`template/`](template/).
- **A module library.** 231 module directories under `modules/` (`ls modules | wc -l`). Each module is one package or service, selected by tags.
- **One reference host.** `hosts/whiterabbit/` enables 158 of those modules, directly or through tags. Its private values (email, timezone, input devices and secrets) are not in this repository. They come from a private overlay.

The server host nexus is defined in a private overlay; its modules (`nexus-*`, `wg-nexus`, `github-pat`) live here.

## Private overlays

firn holds no personal values. To run a machine, write a small private flake
that takes firn as an input and calls `lib.mkSystem`:

```nix
{
  inputs.firn.url = "github:tompassarelli/firn";

  outputs = { self, firn, ... }: {
    nixosConfigurations.<host> = firn.lib.mkSystem {
      hostname = "<host>";
      hostConfig = "${firn}/hosts/<host>/configuration.nix";
      hardwareConfig = ./hosts/<host>/hardware-configuration.nix;
      extraModules = [ ./hosts/<host>.nix ];
    };
  };
}
```

Here `<host>` names a reference host that firn ships, such as `whiterabbit`.
To start from nothing, point `hostConfig` at your own `configuration.nix`, as
the template does.

The overlay's own files hold what makes the machine yours:

- **Identity:** `myConfig.modules.users.email` and
  `myConfig.modules.timezone.zone` (an IANA name); the reference host keeps
  its public username and full name in firn, and an overlay may override them.
- **Devices:** per-device settings, such as input device IDs, go in the
  overlay's host file.
- **Secrets:** an encrypted `secrets/*.yaml` and `.sops.yaml` in the overlay,
  and the option that names each file, for example
  `myConfig.modules.awscli.sopsFile` or `myConfig.modules.cloudflare-auth.sopsFile`.
- **Private modules:** anything else goes in `extraModules`.

Built on its own, firn uses neutral defaults: an empty email and full name,
and the default timezone. Secret-backed modules have no default file, so one
enabled without an overlay value fails evaluation. See [docs/secrets.md](docs/secrets.md).

## Quick start

```bash
nix flake init -t github:tompassarelli/firn     # drops template/ in cwd
firn-runtime-update
# rename the template's placeholder host to <host>: its directory under hosts/
# and its nixosConfigurations entry in flake.nix
cp /etc/nixos/hardware-configuration.nix hosts/<host>/hardware-configuration.nix
# edit hosts/<host>/configuration.nix
firn check
firn rebuild <host>
```

The CLI runs TypeScript with Bun; `FIRN_REPO` selects the configuration checkout.
On macOS, `lib.mkDarwinSystem` builds a `darwinConfigurations` entry instead.

## Agent tooling

Agent tools, hooks and skills are not in this repository. They live in
[tompassarelli/north](https://github.com/tompassarelli/north). firn's
`north-profile` module (`myConfig.modules.north-profile.enable`) installs them
on a host: it publishes North's shared agent surfaces at `~/.agents` and
projects North's hook registration into `~/.claude/settings.json`.

## Commands

Commands take the shape `<node> <edge> [<leaf>]`. Run `firn` with no arguments
for the full grid, or `firn <node>` for one entity.

```bash
firn rebuild [host]           # build, validate and switch the current host
firn rollback <generation>    # activate one exact prior generation
firn check                    # evaluation, assertions, linters and formatting
firn repo build               # resolve composition metadata
firn repo validate            # check the Nix configuration
firn repo diff all            # compare repository changes
firn host impact [<host>]     # what a rebuild would change
firn host status <host>       # modules a host enables directly
firn tag enable <tag>         # add a tag to the current host
firn tag disable <tag>        # remove a tag from the current host
firn tag status               # enabled tags and the resolved active modules
firn module list all          # every module (also: used, unused)
firn schema explain <path>    # schema entry and repo references for an option
firn secret list all          # encrypted secret names under secrets/
```

## Architecture

**Module** = atom (one package or service, in `modules/<name>/`).
**Tags** = composition. A module's `metadata.json` declares membership and
opt-in tags; a host's `tags.json` selects tags, additions, drops and disables.
The resolver unions enabled memberships and applies the host's edits.
**Host** = leaf. `configuration.nix` sets host options; `tags.json` records
composition and direct module choices. Nix is the configuration source.

→ [docs/architecture.md](docs/architecture.md) for the resolver chain and repo layout,
and [docs/TAGS.md](docs/TAGS.md) for tag composition.

## Documentation

- [docs/secrets.md](docs/secrets.md): key layout and the bring-your-own-key recipe
- [docs/TAGS.md](docs/TAGS.md): tag-driven composition and resolution
- [docs/verification.md](docs/verification.md): checks before builds and derivation comparisons
- `firn --help` and `firn schema explain <path>`: the CLI is self-documenting

## Tradeoffs

- Full option checking evaluates NixOS and needs the locked inputs available.
- JSON composition metadata accompanies Nix modules so the CLI can edit tags.

## Inspired by

[doomemacs/doomemacs](https://github.com/doomemacs/doomemacs) ·
[basecamp/omarchy](https://github.com/basecamp/omarchy) ·
[fufexan/dotfiles](https://github.com/fufexan/dotfiles) ·
[redyf/nixdots](https://github.com/redyf/nixdots) ·
[eduardofuncao/nixferatu](https://github.com/eduardofuncao/nixferatu)

## License

Firn is dual-licensed under either the [MIT License](LICENSE-MIT) or the
[Apache License, Version 2.0](LICENSE-APACHE), at your option
(`MIT OR Apache-2.0`).
