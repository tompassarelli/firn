# Greywrought toolchain and builds

## Resolve the consumer's toolchain

These commands record a working route, not a permanent version guarantee.
Check the current manifests before reusing them.

Greywrought currently has no `flake.nix`; do not run `nix develop` and do not
guess that a Bun-only shell can execute Cargo scripts. Read `package.json`,
`rust-toolchain.toml`, and `.cargo/config.toml`, then prove `bun`, `cargo`,
`rustc`, and `cc` are callable before invoking a package script that needs them.

On this machine, Rust is a separately managed rustup toolchain while Bun and a
C linker may be supplied out of store for the command. The known-good full
build shape is:

```sh
nix shell nixpkgs#bun nixpkgs#gcc -c sh -c \
  'export PATH=/home/tom/.rustup/toolchains/1.96.1-x86_64-unknown-linux-gnu/bin:$PATH; exec bun run build:play'
```

If `rust-toolchain.toml` changes, derive and validate the new toolchain path
instead of reusing `1.96.1`. A missing executable is a toolchain-admission
failure, not a game failure; correct it once without retrying speculative shell
variants.

## Choose full versus host-only build

After a successful full materialization, host-only TypeScript/Three.js/audio
changes use the faster path:

```sh
nix shell nixpkgs#bun -c bun run build:host
```

Clause changes require the pinned source checker and a fresh full build.

## Rationale and stopping point

A missing Cargo or linker executable is environment admission, not game
behavior. The host-only path is valid only after the required full artifacts
exist and the edit does not change them. Check that dependency boundary once
instead of blindly trying successive shells or paying a full build for every
browser-only change.
