---
name: greywrought-development-distilled
description: >-
  Build, run, test, or change the Greywrought Clause game in
  ~/code/greywrought-clause, including its Bun, Rust, Clause, Wasm, Three.js,
  live-server, worktree, and compiler-pin workflow.
---

# Greywrought development

Treat a conference/demo request as terminal delivery: keep the live game usable,
make the shortest coherent change, run one decision-changing check, and return
the URL before optional cleanup.

## Checkout and authority

- Work only in an owned `~/code/greywrought-clause/worktrees/<slug>` lane. Never
  edit `main/` or `pins/`.
- Before development, fetch and compare the lane base with `origin/main`. Update
  submodules with `git submodule update --init --recursive`, then use Bun for
  dependencies.
- Read the lane's `AGENTS.md`. World rules belong in `src/world/*.clause`;
  TypeScript is presentation and foreign-system shell only.
- Use the Clause commit pinned by `vendor/clause` and verified by
  `scripts/clause-pin.ts`. Never substitute Clause `main` or run a checker in a
  way that redirects Clause build output into Greywrought's Cargo target.

## Resolve the toolchain before the first build

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

After a successful full materialization, host-only TypeScript/Three.js/audio
changes use the faster path:

```sh
nix shell nixpkgs#bun -c bun run build:host
```

Clause changes require the pinned source checker and a fresh full build.

## Run and prove the demo

- Start or preserve one scoped play server from the built lane at
  `http://127.0.0.1:4173/`; do not kill an unknown server.
- The server serves current built files, so rebuild then hard-refresh the page.
- Use `bun run test:browser-playability` as the nearest smoke for page, resident
  session, and character-rig mounting. Use a focused feature check only when its
  result changes delivery.
- Report the observed URL and check. Do not claim audio perception from an
  automated browser; browser audio unlocks on the first pointer or key gesture.

Land through enumerated staging and `safe-push --to main`, then fast-forward the
clean protected main checkout. Preserve unrelated human and peer changes.
