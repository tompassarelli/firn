---
name: firnos
description: >-
  Use WHENEVER editing this user's NixOS configuration at ~/code/nixos-config
  (FirnOS) — adding or removing a package/module, enabling a service, changing
  host config, wiring hooks/skills, bumping inputs, or any "install X
  system-wide" request. The config's write interface is beagle/nix (.bnix files
  that compile to .nix); editing .nix directly is WRONG (it is generated). This
  skill carries the edit→firn build→firn validate loop, the rule that the system
  switch (firn rebuild) is the user's to run, sops-only secrets, tag-driven
  composition, and the schema-query tools. NOT for general Nix in other repos —
  this is specifically the FirnOS repo workflow. Pairs with beagle-authoring
  (the .bnix language itself). The full reference is ~/code/nixos-config/CLAUDE.md.
---

# FirnOS — editing ~/code/nixos-config

The **write interface is beagle/nix**: `.bnix` source compiles to `.nix`. Nix is
the build target, **not** the source of truth. Read `~/code/nixos-config/CLAUDE.md`
for the complete contract — this skill is the operating loop.

```
*.bnix  ──(firn build)──▶  *.nix  ──(firn rebuild, USER runs)──▶  system
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
4. **Never run `firn rebuild` / `nixos-rebuild switch` / `nh switch` / `firn update`.**
   Those activate the system (sudo, new generation) — the user's call, not the
   agent's. (A `PreToolUse` hook hard-denies these.) Verify build-only with
   `nix build .#nixosConfigurations.whiterabbit.config.system.build.toplevel --no-link`
   when validate isn't enough; otherwise hand `firn rebuild` to the user.
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

Never chain `git commit && git push`. Commit first; verify the gitleaks pre-commit
hook passed; only then advise the user to push. New files (`.bnix` + `.nix`) must be
git-added before nix can see them.

## Verify, don't switch

`firn build` + `firn validate` is the default loop. `firn repo diff` re-emits and
diffs vs committed `.nix` (drift check). `nix build … --no-link` is full evaluation
when the static checker can't see a build-time problem. The system switch
(`firn rebuild`) is **always** the user's to run — prepare it, verify it, hand it off.
Only verify `whiterabbit`; skip `thinkpad-x1e`.
