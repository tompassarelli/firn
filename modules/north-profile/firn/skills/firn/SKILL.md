---
name: firn
category: nixos
description: >-
  Use whenever editing ~/code/nixos-config (firn): packages, modules, services,
  host config, hooks/skills, inputs, or any "install X system-wide" request.
  Write interface is .bnix (compiled to .nix — never edit .nix). System switch
  (firn rebuild) is agent-runnable; it builds a commit snapshot (rev=HEAD), so
  commit your own changes first — nobody's uncommitted state blocks or leaks.
  NOT general Nix in other repos.
hooks:
  - firn-system-policy
---

# firn — editing ~/code/nixos-config

The **write interface is beagle/nix**: `.bnix` source compiles to `.nix`. Nix is
the build target, **not** the source of truth. Read `nixos-config:AGENTS.md`
for the complete contract — this skill is the operating loop. The `.bnix` language
itself → beagle-authoring.

```
*.bnix  ──(firn build)──▶  *.nix  ──(firn rebuild)──▶  system
```

## The four rules that bite

1. **Edit `.bnix`, never `.nix`.** The `.nix` is generated; the next `firn repo build`
   overwrites any hand-edit. This applies to host config too —
   `hosts/<host>/configuration.bnix`, not `configuration.nix`.
2. **After any `.bnix` change: `firn repo build` then `firn repo validate`.** Build
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
   (`~/code/beagle`, `~/code/north`), the exact
   committed local `refs/heads/main` remains promotable while the active checkout
   is dirty or off-main because only that Git object enters the build. A missing,
   rewound, or divergent local `main` holds the already-verified pin.
   It switches the system — sudo, new generation — and `firn rollback` / the
   boot menu undo it. Raw `nixos-rebuild switch` / `nh switch` and
   `firn repo upgrade now` (wholesale input bumps) stays the USER's — the hook still
   denies those. Build-only verification when validate isn't enough:
   `nix build .#nixosConfigurations.whiterabbit.config.system.build.toplevel --no-link`.

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
firn repo build                  # generates modules/<name>/default.nix
firn repo validate               # 0 errors
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

## Read a focused guide only when needed

- Option existence or types: `nixos-config:docs/schema-introspection.md`.
- Renaming option paths: `nixos-config:docs/renaming-option-paths.md`.
- Compiler queries: `nixos-config:docs/compiler-queries.md`.
- Non-obvious validation failures: `nixos-config:docs/repair-pipeline.md` and
  `nixos-config:docs/diagnosing-schema-errors.md`.
- Tag composition: `nixos-config:docs/tags-composition.md`.
- Module flake inputs: `nixos-config:docs/flake-inputs.md`.
- Darwin compatibility: `nixos-config:docs/platform-compatibility.md`.
- Input bumps: `nixos-config:docs/bumping-inputs.md`.
- Importing existing Nix: `nixos-config:docs/importing-nix.md`.
- Verification rung selection: `nixos-config:docs/verification.md`.
- A whiterabbit silent reboot: `nixos-config:docs/crash-recovery.md`.

## Verify, then switch

`firn repo build` + `firn repo validate` is the default loop. `firn repo diff` re-emits and
diffs vs committed `.nix` (drift check). `nix build … --no-link` is full evaluation
when the static checker can't see a build-time problem. The system switch
(`firn rebuild`) is agent-runnable: it builds and switches a commit snapshot
(`rev=HEAD`), so commit your own changes first — uncommitted state (anyone's)
never blocks it and never enters the generation. `firn rollback` undoes.
`firn repo upgrade now` (input bumps) stays the user's. Only verify `whiterabbit`;
skip `thinkpad-x1e`.
