---
name: firn-distilled
description: >-
  Use whenever editing ~/code/nixos-config (firn): packages, modules, services,
  host config, hooks/skills, inputs, launchers, builds, updates, closures,
  live/out-of-store entrypoints, or any "install X system-wide" request. Also
  use for decisions that could put Tom-maintained or other high-churn project
  source or build outputs, dev servers, fast-moving CLIs, SDKs, compilers,
  package managers, or toolchain implementations into the boot/system closure.
  Write interface is .bnix
  (compiled to .nix — never edit .nix). System switch (firn rebuild) is
  agent-runnable; it builds a commit snapshot (rev=HEAD), so commit your own
  changes first — nobody's uncommitted state blocks or leaks. NOT general Nix
  in other repos.
---

# Firn, distilled

Firn owns stable machine and service responsibility. Project source, build
outputs, dev servers, fast-moving CLIs, SDKs, compilers, package managers, and
toolchain implementations are default-denied from the boot/system closure.

## Hard boundaries

- Edit Beagle/Nix `.bnix` sources only; never hand-edit generated `.nix`.
- After every `.bnix` change, run `firn repo build` and then
  `firn repo validate`. Stage both source and generated target explicitly.
- Add one package or service per module under `modules/<name>/`; dynamic imports
  discover it. Enable through declared options/tags and default new modules to
  `whiterabbit` unless the operator names another host.
- Decide closure membership from actual reachability from
  `system.build.toplevel`. A derivation, package, flake input, filesystem
  worktree, or pin may exist without permission or membership; never treat its
  presence as either. Do not put Tom-maintained or declared high-churn project
  source or build outputs into a closure root by default.
- Keep project/toolchain lifecycle in a filesystem worktree or immutable pin,
  project dev shell, separately managed user runtime/profile, atomic promoted
  runtime selector, or direct out-of-store launcher. Pins ordinarily stay out
  of the Nix store and system closure.
- Admit an exception only from one source-owned declaration that names the
  exact project identity and provenance, selected host, authoritative ingress
  module plus option or service origin, exact admitted closure scope,
  `stable-machine` or `stable-service` kind, long-lived consumer,
  responsibility, lifecycle owner, and the concrete reason every local or
  out-of-store route fails. Convenience, reproducibility alone, or a missing
  field is not an exception.
- `firn repo upgrade now` may advance inputs only in an owned worktree when the
  requested outcome includes that update. Inspect and commit its exact changes
  before activation.
- `firn rebuild` builds and switches exact committed `HEAD`; commit owned
  changes first. Never use raw `nixos-rebuild` or `nh switch`. Verify only
  `whiterabbit`.

## Minimum workflow

1. Read `nixos-config:AGENTS.md`, repository safety, and any closer instructions.
2. Resolve exact project identity from source-owned provenance and local Git
   evidence; never infer stewardship from a name, URL substring, or provider
   organization lookup.
3. Trace whether the proposed source or output is actually reachable from a
   boot/system closure root, then classify lifecycle responsibility and locate
   the authoritative `.bnix`. Stop rather than infer reachability.
4. Query package/schema/compiler facts rather than guessing.
5. Edit `.bnix`; run `firn repo build`, then `firn repo validate` once each.
6. When an input update is in scope, run `firn repo upgrade now` in the owned
   worktree and inspect its result. Explicitly stage every intended path,
   commit the coherent checkpoint, and use stronger evaluation only when
   static validation cannot decide the risk.
7. Run `firn rebuild` only when a system switch is in scope and the exact commit
   is ready; confirm the printed snapshot identity.

Stop on an unknown schema/path, generated-only diff, untracked module pair,
uncommitted snapshot, uncertain maintained-project reachability, or incomplete
closure exception. Use `firn repo doctor` only for a specific
stale/untracked/orphan/cache suspicion.

Module and rollback details live in the reference skill; load it only for an
explicit request or a named unresolved detail, per the always-loaded policy.
