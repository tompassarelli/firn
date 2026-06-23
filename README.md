<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/firnos-logo.png" width="150">
    <source media="(prefers-color-scheme: light)" srcset="assets/firnos-logo-dark.png" width="150">
    <img alt="FirnOS" src="assets/firnos-logo.png" width="150">
  </picture>
</p>

**FirnOS is a source-aware authoring layer for NixOS and nix-darwin.**

Keeps the standard NixOS module model, swaps in a small Racket DSL
([beagle/nix](https://github.com/Autonymy/beagle)) for authoring,
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
lives in [beagle](https://github.com/Autonymy/beagle).

## Who is this for?

This repository is two things at once: the FirnOS framework, and the
author's real NixOS + nix-darwin config built on it. To use FirnOS for
your own machines, **start from [`template/`](template/)**. The full
repo (`hosts/whiterabbit/`, ~166 modules) is here as a study
reference, not as something to fork wholesale.

## Quick start

```bash
nix flake init -t github:tompassarelli/firnos     # drops template/ in cwd
git clone https://github.com/Autonymy/beagle ../beagle    # compiler + validator
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

## Architecture

- **Module** = atom. One package or service. Lives in
  `modules/<name>/default.bnix` (with a regenerated `default.nix`
  sibling).
- **Tags** = composition. A module joins a tag via `:tags` (default-on)
  or `:tags-opt-in` (opt-in) in its `.bnix`. Hosts declare a tag
  selection; the resolver unions per-tag memberships and subtracts a
  per-host disabled list. See [docs/TAGS.md](docs/TAGS.md).
- **Host** = leaf. `hosts/<host>/configuration.bnix` sets options;
  `hosts/<host>/enabled-tags.bnix` picks the tag set.

`firn rebuild` runs `firn-build` → `firn-validate` → `nixos-rebuild` →
tag. Modules auto-discover via the flake's dynamic `imports` — adding a
module means creating the directory + `.bnix`, running `firn-build`,
and `git add`-ing both files. No flake edits.

```
.
├── flake.bnix         source-of-truth flake (#lang beagle/nix)
├── flake.nix          generated
├── modules/  hosts/    .bnix source (+ generated .nix siblings)
├── scripts/           firn (CLI), firn-build, firn-validate, firn-extract-schema
├── template/          starting point for `nix flake init -t`
├── dotfiles/  secrets/  assets/
├── docs/              TAGS.md — composition model
└── tests/             validator regression fixtures (.bnix)
```

Both `.bnix` and `.nix` are committed because the flake reads from the
git tree. **Edit the `.bnix`** — `firn-build` overwrites direct `.nix`
edits.

## Documentation

- [docs/TAGS.md](docs/TAGS.md) — tag-driven composition model,
  resolution algorithm, worked examples
- [Autonymy/beagle](https://github.com/Autonymy/beagle) —
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

MIT
