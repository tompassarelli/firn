---
name: firn
description: >-
  Use whenever editing ~/code/nixos-config (firn): packages, modules, services,
  host config, hooks/skills, inputs, or any "install X system-wide" request.
  Write interface is .bnix (compiled to .nix — never edit .nix). System switch
  (firn rebuild) is agent-runnable; it builds a commit snapshot (rev=HEAD), so
  commit your own changes first — nobody's uncommitted state blocks or leaks.
  NOT general Nix in other repos.
---

# firn — editing ~/code/nixos-config

The **write interface is beagle/nix**: `.bnix` source compiles to `.nix`. Nix is
the build target, **not** the source of truth. Read `~/code/nixos-config/AGENTS.md`
for the complete contract — this skill is the operating loop. The `.bnix` language
itself → beagle-authoring.

```
*.bnix  ──(firn build)──▶  *.nix  ──(firn rebuild)──▶  system
```

## The five rules that bite

1. **Edit `.bnix`, never `.nix`.** The `.nix` is generated; the next `firn build`
   overwrites any hand-edit. This applies to host config too —
   `hosts/<host>/configuration.bnix`, not `configuration.nix`.
2. **After any `.bnix` change: `firn build` then `firn validate`.** Build
   regenerates the `.nix`; validate is the schema/type/path check (~5s) and is the
   right verification for "enable X" / "set X to Y" edits.
3. **`git add` BOTH the `.bnix` and the generated `.nix`.** Flakes only see
   git-tracked files — an untracked module is invisible to `builtins.readDir` and
   silently skipped.
4. **`firn rebuild` builds a COMMIT SNAPSHOT (`rev=HEAD`), never the working
   tree — commit YOUR changes first or they won't be in the build.** No
   session's uncommitted state (yours or a peer's) can block the rebuild or
   leak into the generation; the pipeline prints exactly which in-flight files
   it excluded and validates the snapshot itself. For local inputs
   (beagle/fram/gaffer/north), committed `main` HEAD remains promotable with dirty WIP
   because only its exact Git object enters the build; off-`main` still holds
   the already-verified pin.
   It switches the system — sudo, new generation — and `firn rollback` / the
   boot menu undo it. Raw `nixos-rebuild switch` / `nh switch` and
   `firn update` (wholesale input bumps) stay the USER's — the hook still
   denies those. Build-only verification when validate isn't enough:
   `nix build .#nixosConfigurations.whiterabbit.config.system.build.toplevel --no-link`.
5. **Secrets via sops-nix only.** Encrypted files in `secrets/`, referenced with
   `sops.secrets."name"`. Never inline a plaintext credential anywhere in the repo
   (a gitleaks pre-commit hook will catch it).

## Add a package / module

1 package = 1 module. No exceptions.

```
modules/<name>/default.bnix      # author this (clone an existing simple module, e.g. modules/tree)
```

```clojure
#lang beagle/nix
(ns default)
(nix/module [config lib pkgs ...]
  {:tags [cli-tools]                                   ;; optional tag membership
   :options.myConfig.modules.<name>.enable (lib.mkEnableOption "...")
   :config (lib.mkIf config.myConfig.modules.<name>.enable
             {:environment.systemPackages (nix/with pkgs [<name>])})})
```

Then:

```bash
firn build                       # generates modules/<name>/default.nix
firn validate                    # 0 errors
git add modules/<name>           # BOTH .bnix and .nix
```

The flake auto-imports every directory under `modules/` (dynamic `readDir`), so
**no flake edit is needed** — just create the dir and git-add. Confirm the package
name exists first: `nix eval nixpkgs#<name>.name`.

## Enable a module on the host

New modules default off (`mkEnableOption`). Turn on in the **host source**
`hosts/whiterabbit/configuration.bnix` (whiterabbit is the primary host), mirroring
the siblings:

```clojure
:myConfig.modules.<name>.enable true
```

Composition is also **tag-driven**: a module joins a tag via `:tags [...]`; hosts
enable tags in `hosts/<host>/enabled-tags.bnix`. Direct-enable and tags both work;
match what neighbors do. `firn tag resolve whiterabbit` debugs "why is X enabled?".

## Query the schema instead of grepping

```bash
beagle-schema services.openssh.enable        # type, default, enum
beagle-schema --search ssh                    # fuzzy
firn schema explain <path-or-validator-error> # decode an unknown-option error
firn repo doctor                              # untracked/stale/orphan/validator checks
```

## Commit discipline

Never chain `git commit && git push`. Commit first and let the gitleaks pre-commit
hook run; then push it yourself via `safe-push` — the global push rules apply (push
freely at sensible checkpoints; the human is not a push gate). New files
(`.bnix` + `.nix`) must be git-added before nix can see them.

## Verify, then switch

`firn build` + `firn validate` is the default loop. `firn repo diff` re-emits and
diffs vs committed `.nix` (drift check). `nix build … --no-link` is full evaluation
when the static checker can't see a build-time problem. The system switch
(`firn rebuild`) is agent-runnable: it builds and switches a commit snapshot
(`rev=HEAD`), so commit your own changes first — uncommitted state (anyone's)
never blocks it and never enters the generation. `firn rollback` undoes.
`firn update` (input bumps) stays the user's. Only verify `whiterabbit`;
skip `thinkpad-x1e`.
