---
name: warcraft-typescript-development-distilled
description: >-
  Develop Warcraft III maps in TypeScript compiled to Lua (TypeScriptToLua),
  using Warcraft Live: hot reload into running multiplayer clients, TypeScript
  lines for in-game errors, two-second map rebuilds and logic tests checked
  in Bun and 32-bit Lua. Use for any TypeScript map work, Smashcraft's ts/
  included, and whenever changing code in a running Warcraft game.
---

# Warcraft TypeScript development

Warcraft Live is the development environment for Warcraft maps written in
TypeScript. TypeScriptToLua (TSTL) compiles map code to Warcraft's Lua, Bun
runs the host tools and logic tests, and a running game takes new code without
re-hosting. Smashcraft (smashcraft:ts/) is its first project. Until a second
map needs it, it lives inside that repository, not in a separate SDK. Read the
project's style contract (smashcraft:docs/typescript.md) before writing map
code, and use `warcraft3-development-distilled` for launching, signing in and
controlling the game. For Effect APIs and design, also use
`effect-development-distilled` and follow Smashcraft's repository-local Effect
policy before changing its vendored source or Effect dependency.

## Effect in Warcraft Live

Effect is a deliberate part of Smashcraft's TypeScript application and host
tooling architecture. Prefer its services, typed failures, Schema boundaries,
scoped resource handling, and bounded concurrency where those abstractions
clarify a real application boundary. Keep deterministic frame simulation,
synchronized gameplay state, and other latency-sensitive code as small, pure
records and functions unless a measured design requires Effect there. Do not
put Effect imports in code compiled into synchronized game Lua: the current
Smashcraft toolchain probe (`effect@4.0.1`, TSTL 1.37.1) fails at module
resolution because Effect has no Lua source for TSTL to load. Use Effect in
Bun-hosted TypeScript services and tools. Reconsider map-Lua use only after an
actual TSTL compile and Warcraft Lua32 run both pass. Never import from the
vendored `repos/effect` tree; imports must resolve through the project's pinned
package dependency.

## Take the fastest signal

Work from the cheapest check that can answer the question:

1. **Logic.** `bun test` runs every test, about 1 s. A focused run takes about
   0.07 s: `bun test test/game.test.ts -t NAME`. `bun run check` type-checks
   with TypeScript 7 in about 0.3 s.
2. **Emitted Lua.** Run `LUA=<32-bit lua> bun scripts/lua-tests.ts` to run the
   same tests in 32-bit Lua. That catches what Bun can't: integer wrap, binary32
   rounding and TSTL output.
3. **The running game.** Leave
   `bun scripts/hot.ts --data <client A CustomMapData> --data <client B ...> --watch`
   running. Every save reaches both clients in about 1-1.5 s. Its log reports
   each version as running or refused, and prints in-game errors as TypeScript
   file and line about 0.05 s after they happen.
4. **A changed map file.** After one full project build,
   `bun scripts/map.ts rebuild MAP.w3x` swaps only the script in about 2 s.
   Then rejoin. Do a full build only when assets, object data or non-TypeScript
   sources change.

Re-host only when the map file itself must change. Before rebuilding and
rejoining, try hot reload: it keeps the clients, the lobby and the match state.

## Write code that reloads

- Engine callbacks bind to `trampoline(name)` once and get their behavior from
  `on(name, handler)`, both from the project's dispatch module. A reload
  re-registers handlers; timers and triggers created at start keep running.
- State that must survive a reload lives in a global (`declare global { var
  __name: State | undefined }`). A reloaded bundle has fresh module locals.
- The entry module's `install()` registers every handler, dispatch and the
  reloader's own. It runs at start and after each reload, so the reloader and
  error reporting reload too. Module scope does no work.
- Reloading never changes the map file, object data, assets or handles created
  earlier. A reload that changes the shape of global state must convert it, or
  start a fresh match.

How a reload applies: the host client announces the new version. Every client
loads and verifies its copy and answers ready or refuse. On the last answer,
all clients install on the same frame, or none do. "hot reload N not applied"
names the reason; nothing has changed in any client.

## Warcraft facts the tools enforce or rely on

- **Numbers:**
  - Warcraft's Lua has 32-bit integers that wrap, and binary32 numbers whose raw
    `+` and `*` don't always round to nearest.
  - Integer division and remainder use the project's `floorDiv`/`floorMod`
    (`idiv`/`imod` for Wurst semantics).
  - Synchronized reals use exact helpers or `f32()`.
  - The compiler rejects `%`, `>>>`, `Math.floor(a / b)`, decimal literals that
    aren't binary32 values (write the exact value or `f32(0.1)`), `Math.random`,
    `Date`, `JSON`, `Intl`, and Node, Bun and DOM APIs.
- **`Preloader`:** it checks on every call whether a file exists, but runs the
  content it first read from that path for the rest of the session. Any file
  the host writes for the game to read again needs a new name for new content.
- **No `debug` library in map Lua:** error reports carry the failing line but
  no stack, and a thrown `Error` carries no position.
- **`Object.assign`:** in Lua it skips fields whose value is `undefined`; copy
  records with optional fields field by field.

## Tests

Register tests with `test()` in `*.tests.ts`, so each runs in Bun and in
32-bit Lua. Keep a test only for a contract: a reference value, a gameplay or
netcode invariant, or a reproduced defect. Never change an expected value to
make a port or a change pass; a disagreement is a defect to name.
