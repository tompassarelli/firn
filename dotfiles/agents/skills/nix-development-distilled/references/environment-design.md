# Output and environment design

## Consumer contract

Make the project declare the environment needed to build and test it. A
successful ad-hoc `nix shell` invocation is evidence for what belongs in the
project flake, not the finished workflow.

## Boundaries

- Read repository instructions and inspect existing flakes, lock files,
  language manifests, build scripts, and actual supported platforms first.
- Keep project development outside the NixOS system closure. A project flake,
  package, or dev shell does not authorize adding the project or its toolchain
  to host configuration. Route machine configuration to `firn-distilled`.
- Follow source authority. In Tom-owned greenfield Nix work, author
  `#lang beagle/nix` `.bnix` and commit its generated `.nix` sibling; preserve
  existing plain Nix in externally owned or non-greenfield projects unless a
  migration is explicitly requested. Use `beagle-authoring-distilled` for
  `.bnix` work and repair missing Beagle capability upstream rather than
  hand-editing the generated Nix.
- Never put credentials in a flake, lock file, shell hook, substituter URL, or
  command. Do not add caches, trusted keys, or global Nix settings without a
  named consumer and separate authority.

## Select outputs by actual consumers

Start from the immediate workflow:

- `devShells.<system>.default` for an edit/build/test environment;
- `packages.<system>` only when a Nix-built artifact is consumed;
- `apps.<system>` for an intentional `nix run` interface;
- `checks.<system>` only for checks that `nix flake check` should own;
- `nixosModules`, `darwinModules`, or templates only when the project actually
  exports those interfaces.

Do not add every standard output for completeness. Declare only real supported
systems; do not imply portability that was not exercised. Prefer direct
Nixpkgs output definitions for one or two systems, and add flake-parts,
flake-utils, or another framework only when repeated cross-system structure
earns the dependency.

## Declare the complete development environment

Use the project's existing language manifest or toolchain file as version
authority where possible. Include the compiler or interpreter, package manager,
formatter, linter, linker, `pkg-config`, headers, and native libraries that the
nearest build actually needs. Use `mkShell` when a compiler toolchain is
required and `mkShellNoCC` when it is not.

Prefer Nixpkgs alone when it satisfies the required version. When it does not,
compare the conventional pinned toolchain provider with one viable alternative
and choose the smaller fit. Reuse native manifests such as
`rust-toolchain.toml` instead of maintaining the same version and components in
parallel. Pin every flake input in `flake.lock`; update the lock deliberately
and inspect which inputs moved.

Keep shell hooks minimal and deterministic. They may establish project-local
environment variables or existing lightweight setup, but must not install
global packages, mutate host configuration, fetch mutable installers, start
unrequested services, or hide a missing declared dependency.

## Rationale and alternatives

A development shell declares tools available to a command; a package declares
how an artifact is built. Neither automatically belongs in the machine closure.
Keeping native version manifests authoritative avoids two independently edited
toolchain pins. Frameworks pay when repeated structure needs them, not because
a flake is expected to look elaborate.
