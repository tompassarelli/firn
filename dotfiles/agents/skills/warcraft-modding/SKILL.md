---
name: warcraft-modding
description: >-
  Develop and test Warcraft III maps: TypeScript maps with Wisp (hot reload,
  fast rebuilds, headless and 32-bit Lua tests) and the native game (offline
  LAN test clients, signed-in clients, startup recovery, desync debugging).
  Use for any Warcraft III map work, Smashcraft's ts/ included.
grounded: 2026-10-09
written: 2026-10-09
---

# Warcraft modding

## Source and runtime

- Use `bun wisp ...` from the project's TypeScript directory for TypeScriptToLua map code and Bun host tools.
- Resolve Wisp capabilities through wisp:docs/index.md at node_modules/wisp/docs/index.md.
- Read smashcraft:AGENTS.md and smashcraft:docs/typescript.md before changing Smashcraft's pinned Wisp consumer in ts/.
- Discover Smashcraft commands through help and the documentation index.
- Use `wurst-development` for Wurst source, `smashcraft-animation` for fighter animation and `smashcraft-stage-design` for stage art.
- Use `effect-development` for Bun host tools that start processes, wait, retry, hold resources or parse outside data.
- Keep Lua-compiled map code in plain TypeScript without Effect imports.
- Follow wisp:docs/cli.md's noun-first command vocabulary and update all callers on renames without aliases.
- Register new nouns in the vocabulary and feature index.

## Fast iteration

- Leave `bun wisp dev` running for type errors, affected tests and two-client headless journeys on each save.
- Run affected tests locally and send full Bun/32-bit Lua suites to `bun wisp farm test --wait` for HEAD.
- Prefer hot reload before script-only rebuilds or full builds.
- Build fully only for assets, object data or non-TypeScript sources.
- Send heavy headless sweeps without private inputs or Warcraft clients to the farm.
- Read [fast-native-iteration.md](references/fast-native-iteration.md) for command flags, measured iteration costs and warm procedures.
- Bind engine callbacks once through `trampoline(name)` and register handlers through `on(name, handler)`.
- Store reload-surviving state in declared globals rather than module locals.
- Register all handlers, including the reloader, in entry `install()` at startup and after reload without module-scope work.
- Convert changed global-state shapes or start a fresh match.
- Preserve map files, object data, assets and existing handles during reload.
- Write each client's payload before its manifest in `CustomMapData/<prefix>-hot`.
- Require all clients to verify and install on the same frame or refuse together.

## Engine constraints

- Model wrapping 32-bit integers and binary32 arithmetic, including non-nearest `+`/`*` rounding and division up to an ulp off.
- Use `floorDiv`/`floorMod` or Wurst-semantic `idiv`/`imod`.
- Wrap each synchronized real operation separately in `f32()`.
- Compile noninteger literals to exact hex floats.
- Avoid compiler-rejected `%`, `>>>`, `Math.floor(a / b)`, nonbinary32 decimal literals, randomness, Date, JSON, Intl and host/DOM APIs.
- Write decimal literals through `f32()`, including tests.
- Avoid `any`, `as unknown as` and non-null `!` outside tests, using the project's `at()`.
- Use new Preloader paths for new content because each path's first content stays cached all session despite existence checks.
- Use recorded TypeScript throw sites without assuming a Lua debug library; enable the stack-traces plugin for full stacks.
- Copy optional fields individually because Lua `Object.assign` skips undefined fields.
- Create/free timers, triggers and callbacks only on synchronized turns to avoid checksum divergence.
- Read [api-gotchas.md](references/api-gotchas.md) for patch-specific natives, assets, input, sync, FileIO and Warsmash investigation.
- Confirm Warsmash behavior against the real game before changing Wisp.
- Write behavior notes in wisp:docs/warsmash-notes.md instead of copying/adapting AGPL-3.0 Warsmash code into MIT Wisp.
- Declare typed UI frames through wisp:docs/ui.md.
- Measure existing compressed imports before re-encoding through wisp:docs/asset-ingestion.md.
- Use wisp:docs/ci.md's reusable workflow and keep private-runner .w3x builds off public uploads.
- Register `test()` in `*.tests.ts` for Bun and 32-bit Lua under the `testing` skill.
- Keep tests only for external references or decided numbers with sources; add no bug regression unless existing behavior was genuinely missed.

## Native clients and checks

- Meet a subsystem's native box through its headless check plus weekly native spot batch only when corpus divergence is zero.
- Keep automatically recorded covered sessions in smashcraft:ts/test/corpus/ for `bun wisp parity corpus` on every push in Bun/32-bit Lua.
- Fix the first divergent frame/field before substituting headless coverage for native checks.
- Measure native truth with exact reads before pixels: on offline 3.0.0 pool clients, use the engine debugger's reads (frame number, Lua state, checksums, per-frame cost; see wisp:docs/builds.md capabilities) and stack-trace builds, align native and Wisp frames by the read frame number, and use screenshots only for appearance that only pixels show.
- Use the offline LAN pool only for Classic on build 3.0.0.24268 and signed-in clones B/C/D for Definitive.
- Check the live build with `curl http://us.patch.battle.net:1119/w3/versions` before relying on the build-specific LAN plugin.
- Keep pool pairs in solo games when the live build leaves 24268 until the plugin is checked on that build.
- Use integrity maps for pad chat setup rather than default dev maps.
- Read [lan-pair-batching.md](references/lan-pair-batching.md) for pool setup, capacity limits, pair ownership and issue queues.
- Use signed-in clones B/C/D for Definitive, Battle.net tests and the updated install feeding the Classic pool.
- Preserve signed-in clients at the menu for the next assigned Battle.net check.
- Never touch Tom's game install or account a.
- Start signed-in clients through `bun wisp client start [CLIENT...] --clients-file FILE` user services rather than shell/background tasks.
- Use `client status` and `client stop` for those services.
- Give each offline Classic pair or signed-in Definitive/Battle.net pair one worker for its batched native checks.
- Run passive engine reads only on signed-in clients.
- Restrict traps, trace, gdb, memory writes and injection to offline pool clients with loopback-only namespaces, no `-uid` and no Battle.net program in the prefix.
- Restrict tools to the project's clients file and keep decrypted code dumps outside repositories.
- Read the runners' `desync autopsy` line first and preserve output under ~/.local/state/wisp/autopsy/.
- Wrap other runners with `withAutopsy({ clientsFile }, run)`.
- Read [native-sessions.md](references/native-sessions.md) for manual desync diagnosis and session setup.
- Rerun invalid native sessions after crashes, new desync reports or premature results.
- Pass gameplay checks when native pad output matches headless through `bun wisp pad ... --compare`.

## Play and recovery

- Use `wisp play` to build current main for Tom and route experiments through fresh, captures or accept.
- Confirm roster, stage thumbnails and gameplay before declaring a build ready.
- Build through `bun wisp map build` using hashed private inputs in smashcraft:build-inputs.json.
- Add art with `bun wisp inputs add FAMILY DIR` and commit the result without editing stored inputs in place.
- Recover clients with `wisp client doctor` rather than hand-driving known failure states.
- Check `client watch --once` or `client wait CLIENT STATE` before clicking, reading or waiting on clients.
- Use in-map setup commands and observe through menu sockets, status files and War3Log rather than pointer clicks.
- Host through the menu socket after the post-login ladder-map scan to avoid -loadfile losing imported assets.
- Search Hive Workshop first for Warcraft bugs and change one variable per native experiment under `debugging`.
- Use off-monitor private desktops through `private-desktop-development`.
- Keep native tests on private desktops.
- Keep one runtime per prefix and launch Warcraft through signed-in Battle.net Play instead of Warcraft III.exe.
- Fix an empty Options/Exit Game shell through launcher Play rather than another sign-in.
- Count launch success only after the real menu and one gameplay action work.
- Never print decrypted credentials.

## Conditional references

- Read [warcraft-startup.md](references/warcraft-startup.md) when doctor stops and manual recovery is needed.
- Read [accounts-and-login.md](references/accounts-and-login.md) for test sign-in or account questions.
- Read [pad-and-input-capture.md](references/pad-and-input-capture.md) for pad batches, pose captures or press-to-screen timing.
- Read [lan-discovery.md](references/lan-discovery.md) for pool caps or lobby discovery CPU costs.
- Read [renderer-features.md](references/renderer-features.md) for graphics natives.
- Read [bot-perception.md](references/bot-perception.md) for CPU observation/history/checksum changes.
- Read [effect-in-wisp.md](references/effect-in-wisp.md) for Effect integration.
- Read [failure-modes.md](references/failure-modes.md) for unfamiliar build/session symptoms.
