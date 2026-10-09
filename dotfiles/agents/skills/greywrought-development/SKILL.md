---
name: greywrought-development
description: >-
  Build, run, or change the Greywrought Clause game using its pinned compiler, declared toolchain, and existing playability check.
---

# Greywrought

- Return the usable tested demo URL before optional cleanup.
- Compare the worktree with origin/main, initialize declared submodules and use Bun.
- Keep world rules in Clause and TypeScript for presentation/foreign integration.
- Use `vendor/clause` and the project's pin checker, with compiler outputs in its worktree.
- Resolve Bun, Rust and C-linker tools from manifests before building.
- Use the full build for Clause changes and host-only build after materialization for presentation/audio.
- Preserve one owned server at `http://127.0.0.1:4173/`, rebuild and hard-refresh.
- Run `bun run test:browser-playability` and report its URL/result.
- Require a user gesture for browser audio unlock and Tom's observation for perceived audio.
- Land through `repo-safety`; deploy only when requested.

Use [toolchain/build notes](references/toolchain-and-build.md) for environment commands.
