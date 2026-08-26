---
name: firn-distilled
description: >-
  Use whenever editing ~/code/nixos-config (firn): packages, modules, services,
  host config, hooks/skills, inputs, launchers, builds, updates, closures,
  live/out-of-store entrypoints, or any "install X system-wide" request. Also
  use for decisions that could put project source or build outputs, dev
  servers, fast-moving CLIs, SDKs, compilers, package managers, or toolchain
  implementations into the boot/system closure. Write interface is .bnix
  (compiled to .nix — never edit .nix). System switch (firn rebuild) is
  agent-runnable; it builds a commit snapshot (rev=HEAD), so commit your own
  changes first — nobody's uncommitted state blocks or leaks. NOT general Nix
  in other repos.
---

# Firn, distilled

Firn owns stable machine and service responsibility. Project source, build
outputs, dev servers, fast-moving CLIs, SDKs, compilers, package managers, and
toolchain implementations default outside the boot/system closure.

## Hard boundaries

- Edit Beagle/Nix `.bnix` sources only; never hand-edit generated `.nix`.
- After every `.bnix` change, run `firn repo build` and then
  `firn repo validate`. Stage both source and generated target explicitly.
- Add one package or service per module under `modules/<name>/`; dynamic imports
  discover it. Enable through declared options/tags and default new modules to
  `whiterabbit` unless the operator names another host.
- Put project/toolchain lifecycle in a project dev shell, separately managed
  user runtime/profile, or direct out-of-store launcher. A system-closure
  exception must name a long-lived machine/service consumer, responsibility,
  lifecycle owner, and why local execution cannot satisfy it.
- `firn rebuild` builds and switches exact committed `HEAD`; commit owned
  changes first. Never use raw `nixos-rebuild`, `nh switch`, or
  `firn repo upgrade now`. Verify only `whiterabbit`.

## Minimum workflow

1. Read `nixos-config:AGENTS.md`, repository safety, and any closer instructions.
2. Classify lifecycle responsibility and locate the authoritative `.bnix`.
3. Query package/schema/compiler facts rather than guessing.
4. Edit `.bnix`; run `firn repo build`, then `firn repo validate` once each.
5. Explicitly stage every changed `.bnix` and generated `.nix`, commit the
   coherent checkpoint, and use stronger evaluation only when static validation
   cannot decide the risk.
6. Run `firn rebuild` only when a system switch is in scope and the exact commit
   is ready; confirm the printed snapshot identity.

Stop on an unknown schema/path, generated-only diff, untracked module pair,
uncommitted snapshot, or closure exception without its named consumer case.
Use `firn repo doctor` only for a specific stale/untracked/orphan/cache suspicion.

Module and rollback details live in the reference skill; load it only for an
explicit request or a named unresolved detail, per the always-loaded policy.
