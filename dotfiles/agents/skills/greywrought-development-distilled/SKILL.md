---
name: greywrought-development-distilled
description: >-
  Build, run, or change the Greywrought Clause game using its pinned compiler, declared toolchain, and existing playability check.
---

# Greywrought development

For a demo request, keep the live game usable and return its tested URL before
optional cleanup.

Work in an owned lane. Fetch and compare its base with origin/main, initialize
declared submodules, and use Bun. Read the project instructions: world rules
belong in Clause; TypeScript is presentation and foreign-system integration.

Use the Clause pin declared by `vendor/clause` and the project's pin checker.
Keep compiler outputs in the compiler's lane. Resolve the required Bun, Rust,
and C-linker tools from current manifests before running a build script;
missing tools are environment failures, not game failures.

Use the full build for Clause changes and the existing host-only build after
successful materialization for presentation/audio changes. For the concrete
environment commands and their assumptions, read
[toolchain and build notes](references/toolchain-and-build.md).

Preserve one scoped play server at `http://127.0.0.1:4173/`; never kill an
unknown server. Rebuild and hard-refresh, then use
`bun run test:browser-playability` for the page, resident session, and rig.
Report the URL and observed check. Automated checks do not establish perceived
audio; browser audio unlock requires a user gesture.

Land through repository safety. A development build does not authorize a
production deployment.
