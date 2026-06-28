<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/firn-logo.png" width="150">
    <source media="(prefers-color-scheme: light)" srcset="assets/firn-logo-dark.png" width="150">
    <img alt="firn" src="assets/firn-logo.png" width="150">
  </picture>
</p>

**firn is a typed front-end for NixOS and nix-darwin — it catches option
typos and type errors at the source line, before `nixos-rebuild` ever runs.**

Keeps the standard NixOS module model, swaps in a small Racket DSL
([beagle/nix](https://github.com/tompassarelli/beagle)) for authoring,
adds pre-eval diagnostics that catch option typos and type errors at
the source line — typically cutting edit/validate loops from
~30 seconds to ~5 seconds.

```
$ firn rebuild
modules/printing/default.bnix:6:7: unknown option services.pipwire.alsa.enable
  did you mean: services.pipewire.alsa.enable or services.pipewire.pulse.enable?
modules/foo/default.bnix:9:34: type mismatch at services.openssh.enable:
  expected bool, got string
hosts/laptop/configuration.bnix:11:47: type mismatch at boot.loader.systemd-boot.consoleMode:
  "atuo" not in enum {…} — did you mean "auto"?
```

`file:line:col` precision on the value, with did-you-mean suggestions,
before `nixos-rebuild` runs. That's the whole pitch — the validator
lives in [beagle](https://github.com/tompassarelli/beagle).

## Who is this for?

This repository is two things at once: the firn framework, and the
author's real NixOS + nix-darwin config built on it. To use firn for
your own machines, **start from [`template/`](template/)**. The full
repo (`hosts/whiterabbit/`, ~166 modules) is here as a study
reference, not as something to fork wholesale.

## Quick start

```bash
nix flake init -t github:tompassarelli/firn     # drops template/ in cwd
git clone https://github.com/tompassarelli/beagle ../beagle    # compiler + validator
cp /etc/nixos/hardware-configuration.nix .
# edit hosts/my-machine/configuration.bnix and hosts/my-machine/enabled-tags.bnix
./scripts/firn-build && nixos-rebuild switch --flake .#my-machine
```

`BEAGLE_PATH` overrides the sibling-clone location. macOS works the
same way via `lib.mkDarwinSystem` and a `darwinConfigurations` entry —
`firn rebuild` detects Darwin and dispatches to `darwin-rebuild`.

## Daily commands

```bash
firn rebuild          # build + validate + switch (current host)
firn validate         # static check the .bnix tree
firn impact           # preview what would build
firn diff             # diff regenerated .nix vs committed
firn enable <name>    # enable a tag (or un-blacklist a module)
firn disable <name>   # disable a tag (or hard-off a module)
```

These are first-class bare shortcuts — defaults are auto-detected
(current host, `all` for aggregates). Every command is ultimately a
`<node> <edge> [<leaf>]` triple (`firn tag enable terminal`,
`firn host rebuild thinkpad-x1e`); run `firn` with no args for the
full grid, or `firn <node>` for one entity's edges.

## Secrets

[sops-nix](https://github.com/Mic92/sops-nix): encrypted `secrets/*.yaml` are
committed, the private age key stays machine-local, `.sops.yaml` lists the
public recipients. Only `awscli` and `clockify` use secrets — both opt-in, off
by default, so the config builds clean without them.

→ **[docs/secrets.md](docs/secrets.md)** — key layout + bring-your-own-key fork recipe.

## Architecture

**Module** = atom (one package/service, `modules/<name>/default.bnix`).
**Tags** = composition (a module declares `:tags`; hosts select tags; the
resolver unions memberships minus a per-host disabled list).
**Host** = leaf (`configuration.bnix` + `enabled-tags.bnix`). `.bnix` is the
source, `.nix` is generated — both committed, edit the `.bnix`.

→ **[docs/architecture.md](docs/architecture.md)** — resolver chain, repo layout, module auto-discovery.

## Documentation

- [docs/TAGS.md](docs/TAGS.md) — tag-driven composition model,
  resolution algorithm, worked examples
- [tompassarelli/beagle](https://github.com/tompassarelli/beagle) —
  the DSL itself: compiler, validator, schema extractor, migration tool
- The `firn` CLI is self-documenting: `firn` (full grid),
  `firn <node>` (one entity), `firn schema explain <path>` (schema
  introspection)

## Tradeoffs

- One sibling-repo dependency (`../beagle`).
- Two-language requirement (Racket s-expressions + Nix concepts).
- Two artifacts per file (`.bnix` + `.nix`, both committed).
- Schema cache is host-specific and dated; regenerate after flake
  input changes.
- DSL ceiling — escape hatch (`raw-file`, hand-written `.nix`,
  `nix-ident`) covers the gaps.

## Inspired by

[doomemacs/doomemacs](https://github.com/doomemacs/doomemacs) ·
[basecamp/omarchy](https://github.com/basecamp/omarchy) ·
[fufexan/dotfiles](https://github.com/fufexan/dotfiles) ·
[redyf/nixdots](https://github.com/redyf/nixdots) ·
[eduardofuncao/nixferatu](https://github.com/eduardofuncao/nixferatu)

## License

[Apache-2.0](LICENSE)
