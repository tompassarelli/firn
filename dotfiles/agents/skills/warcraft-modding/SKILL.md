---
name: warcraft-modding
description: >-
  Develop and test Warcraft III maps with Wisp TypeScript (hot reload, headless
  and 32-bit Lua tests) or the native game (LAN and signed-in clients, startup
  recovery, desync debugging), including Smashcraft's ts/.
grounded: 2026-10-10
written: 2026-10-10
metadata:
  kind: domain
---

# Warcraft modding

## Source and runtime

- Run `bun wisp ...` from the project's TypeScript directory; resolve capabilities through wisp:docs/index.md (`node_modules/wisp/docs/index.md`) and the noun-first vocabulary in wisp:docs/cli.md. Rename nouns with all callers and no aliases; register new nouns in the vocabulary and feature index.
- Smashcraft: read smashcraft:AGENTS.md and smashcraft:docs/typescript.md before changing its pinned Wisp consumer in `ts/`; discover commands through help and the docs index.
- Other skills: `wurst-development` (Wurst), `smashcraft-animation`, `smashcraft-stage-design`, `lua-performance` (frame cost, Lua ceilings), `effect-development` (Bun host tools that start processes, wait, retry, hold resources or parse outside data). Keep map code in plain TypeScript without Effect imports.

## Fast iteration

- Keep `bun wisp dev` running for type errors, affected tests and two-client headless journeys. Run affected tests locally; send full Bun and 32-bit Lua suites and heavy headless sweeps without private inputs or clients to `bun wisp farm test --wait` for HEAD. Read [fast-native-iteration.md](references/fast-native-iteration.md) for flags, measured costs and warm procedures.
- Prefer hot reload over script-only rebuilds, and those over full builds; build fully only for assets, object data or non-TypeScript sources.
- Reload safety: bind engine callbacks once through `trampoline(name)` and register handlers through `on(name, handler)` in entry `install()`, at startup and after reload, with no module-scope work. Keep reload-surviving state in declared globals, not module locals. Convert changed global-state shapes or start a fresh match. Preserve map files, object data, assets and handles.
- Write each client's payload before its manifest in `CustomMapData/<prefix>-hot`; all clients verify and install on the same frame or refuse together.

## Engine constraints

- Numerics: model wrapping 32-bit integers and binary32 arithmetic, including non-nearest `+`/`*` rounding and division up to an ulp off. Use `floorDiv`/`floorMod` or Wurst-semantic `idiv`/`imod`. Wrap each synchronized real operation separately in `f32()`, write decimal literals through `f32()` (tests included), and compile noninteger literals to exact hex floats.
- Avoid compiler-rejected `%`, `>>>`, `Math.floor(a / b)`, nonbinary32 decimal literals, randomness, Date, JSON, Intl and host/DOM APIs. Outside tests, avoid `any`, `as unknown as` and non-null `!`; use the project's `at()`.
- Assets and sync: new content uses new Preloader paths, since a path's first content stays cached all session despite existence checks. Copy optional fields individually (Lua `Object.assign` skips undefined). Create and free timers, triggers and callbacks only on synchronized turns to avoid checksum divergence.
- Errors: use recorded TypeScript throw sites without assuming a Lua debug library; enable the stack-traces plugin for full stacks. Read [api-gotchas.md](references/api-gotchas.md) for patch-specific natives, assets, input, sync, FileIO and Warsmash investigation.
- Warsmash is AGPL-3.0: confirm its behavior against the real game before changing Wisp, and write behavior notes in wisp:docs/warsmash-notes.md rather than copying or adapting its code into MIT Wisp.
- Build plumbing: declare typed UI frames through wisp:docs/ui.md; measure existing compressed imports before re-encoding (wisp:docs/asset-ingestion.md); use wisp:docs/ci.md's reusable workflow and keep private-runner .w3x builds off public uploads.
- Tests: register `test()` in `*.tests.ts` for Bun and 32-bit Lua under the `testing` skill. Keep tests only for external references or sourced decided numbers; add no bug regression unless existing behavior was genuinely missed.

## Native clients and checks

- Parity: meet a subsystem's native box through its headless check plus the weekly native spot batch only when corpus divergence is zero. Keep recorded covered sessions in smashcraft:ts/test/corpus/ for `bun wisp parity corpus` on every push, and fix the first divergent frame or field before substituting headless coverage.
- Measure native truth with exact reads before pixels: on offline 3.0.0 pool clients, use the engine debugger's reads (frame number, Lua state, checksums, per-frame cost; see wisp:docs/builds.md) and stack-trace builds, aligned by frame number. Use screenshots only for appearance that only pixels show. Gameplay checks pass when native pad output matches headless through `bun wisp pad ... --compare`.
- Clients: Classic runs on the offline LAN pool at build 3.0.0.24268; Definitive, Battle.net tests and the updated install feeding the Classic pool run on signed-in clones B/C/D. Check the live build with `curl http://us.patch.battle.net:1119/w3/versions` before relying on the build-specific LAN plugin, and keep pool pairs in solo games when the live build leaves 24268. Use integrity maps for pad chat setup, not default dev maps. Read [lan-pair-batching.md](references/lan-pair-batching.md) for pool setup, capacity, pair ownership and issue queues.
- Native work runs off Tom's machine on the vast.ai Warcraft VM through the vast-ai skill's path and pool recipe; account b is signed in there only.
- Never touch Tom's game install; use account a only as clone-a through its launch.sh, which yields to Tom's game.
- Lifecycle: start signed-in clients as user services with `bun wisp client start [CLIENT...] --clients-file FILE`, not shell or background tasks; manage them with `client status` and `client stop`; keep them at the menu for the next Battle.net check. Give each one-client capture one worker, and a pair one worker only for sync, netplay and EX checks. Run passive engine reads only on signed-in clients.
- Run a build's native spot checks as one batch sharded across every free client, judge once and tick every box it covers; keep tooling reference captures off native lanes.
- Restrict traps, trace, gdb, memory writes and injection to offline pool clients with loopback-only namespaces, no `-uid` and no Battle.net program in the prefix; restrict tools to the project's clients file; keep decrypted code dumps outside repositories.
- Desync: read the runners' `desync autopsy` line first and preserve output under ~/.local/state/wisp/autopsy/; wrap other runners with `withAutopsy({ clientsFile }, run)`. Read [native-sessions.md](references/native-sessions.md) for manual diagnosis. Rerun invalid native sessions after crashes, new desync reports or premature results.

## Play and recovery

- Use `wisp play` to build current main for Tom, and route experiments through fresh, captures or accept. Confirm roster, stage thumbnails and gameplay before declaring a build ready.
- Build through `bun wisp map build` with hashed private inputs in smashcraft:build-inputs.json. Add art with `bun wisp inputs add FAMILY DIR` and commit the result, never editing stored inputs in place.
- Recover clients with `wisp client doctor`, not by hand-driving known failure states. Check `client watch --once` or `client wait CLIENT STATE` before clicking, reading or waiting on clients. Use in-map setup commands and observe through menu sockets, status files and War3Log, not pointer clicks.
- Host through the menu socket after the post-login ladder-map scan, so `-loadfile` does not lose imported assets.
- Search Hive Workshop first for Warcraft bugs, and change one variable per native experiment under `debugging`. Use off-monitor private desktops through `private-desktop-development`, and keep native tests on them.
- Keep one runtime per prefix and launch Warcraft through signed-in Battle.net Play, not Warcraft III.exe. Fix an empty Options/Exit Game shell through launcher Play rather than another sign-in. Count launch success only after the real menu and one gameplay action work.
- Never print decrypted credentials.

## Conditional references

- [warcraft-startup.md](references/warcraft-startup.md) when doctor stops and manual recovery is needed.
- [accounts-and-login.md](references/accounts-and-login.md) for test sign-in or account questions.
- [pad-and-input-capture.md](references/pad-and-input-capture.md) for pad batches, pose captures or press-to-screen timing.
- [lan-discovery.md](references/lan-discovery.md) for pool caps or lobby discovery CPU costs.
- [renderer-features.md](references/renderer-features.md) for graphics natives.
- [bot-perception.md](references/bot-perception.md) for CPU observation, history or checksum changes.
- [effect-in-wisp.md](references/effect-in-wisp.md) for Effect integration.
- [failure-modes.md](references/failure-modes.md) for unfamiliar build or session symptoms.
