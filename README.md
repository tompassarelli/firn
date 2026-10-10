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
repo (`hosts/whiterabbit/`, ~188 modules) is here as a study
reference, not as something to fork wholesale.

## Quick start

```bash
nix flake init -t github:tompassarelli/firn     # drops template/ in cwd
git clone https://github.com/tompassarelli/beagle ../beagle    # compiler + validator
cp /etc/nixos/hardware-configuration.nix .
# edit hosts/my-machine/configuration.bnix and hosts/my-machine/enabled-tags.bnix
firn repo build && nixos-rebuild switch --flake .#my-machine
```

`BEAGLE_PATH` overrides the sibling-clone location. macOS works the
same way via `lib.mkDarwinSystem` and a `darwinConfigurations` entry —
`firn rebuild` detects Darwin and dispatches to `darwin-rebuild`.

## Commands

```bash
firn rebuild          # build + validate + switch (current host), then its environment apps when the host has one
firn-environment-switch [host] [flake] # install the host environment apps (Blender, Obsidian) in ~/.nix-profile, outside the system closure
machine-update        # nightly inputs, validation, exact build, landing and switch
agent-runtime-update [version|latest] # Codex, Claude and agy at 02:00 and 13:00
claude-runtime-update [version|latest] # install verified official Claude binary
claude                # launch the atomically selected Claude runtime
agy-runtime-update [version|latest] # install verified official Antigravity binary
agy                   # launch the atomically selected Antigravity runtime
vast-job --offer-query Q --max-hours H --run CMD --fetch P --to DIR # rent, run, fetch, destroy one capped vast.ai job
vast-reaper [--dry-run]  # every 5 min: destroy vast-job instances past deadline or without a live supervisor; runner VM credit floor (warn $5, teardown $2.50)
lane-gc [--dry-run] [--unlanded] # hourly: retire landed clean idle worktrees/branches; report unlanded work
capacity-watchdog report         # 30 s sampler (user service): 5/30-min load, PSI, lease and unleased-process windows and incidents
git-maintenance-nightly          # 03:17 timer: git maintenance per ~/code/*/main inside a moderate capacity lease
update-status         # report successful automatic updates older than 36 hours
update-notify SERVICE # desktop notification with the failed service's journal
proton-log-watchdog   # strip PROTON_LOG from Wisp launch.sh, truncate clone logs over 1 GiB
skill-review-queue    # weekly: open or update the north issue of skill reviews older than 30 days
codex-shared-idle SOCKET # probe live loaded threads before runtime adoption
codex-runtime-refresh # adopt the selected runtime only on idle shared servers
firn repo validate    # static check the .bnix tree
firn host impact      # preview what would build
firn repo diff        # diff regenerated .nix vs committed
firn tag enable <t>   # enable a tag
firn tag disable <t>  # disable a tag
agent-instruction-check --repo DIR --ref HEAD # published AGENTS.md and global-policy limits
agent-instruction-check --global FILE        # generated global policy (repeat --global)
```

Commands use a `<node> <edge> [<leaf>]` triple. Leaves default to the current
host or `all` where the edge defines that default. `firn rebuild [host]` is the
canonical build-and-switch shortcut; run `firn` with no args for the full grid
or `firn <node>` for one entity's edges.

`lane-gc` (hourly timer, module `lane-gc`) retires worktrees and branches already
on origin/main that are clean, idle and not in use, and lists everything else in
`~/.local/state/agents/lane-gc/unlanded.txt`; the `unlanded-work` SessionStart hook
announces entries older than 24 h.

## Secrets

[sops-nix](https://github.com/Mic92/sops-nix): encrypted `secrets/*.yaml` are
committed, the private age key stays machine-local, `.sops.yaml` lists the
public recipients. The `awscli` module is opt-in, so the config builds clean
without it.

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

Firn is dual-licensed under either the [MIT License](LICENSE-MIT) or the
[Apache License, Version 2.0](LICENSE-APACHE), at your option
(`MIT OR Apache-2.0`).
