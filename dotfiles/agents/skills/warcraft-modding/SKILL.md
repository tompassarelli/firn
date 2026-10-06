---
name: warcraft-modding
description: >-
  Boundary: TypeScript map authoring and the Wisp dev loop; launching,
  sign-in and native game control belong to warcraft3-development.
  Develop Warcraft III maps in TypeScript compiled to Lua (TypeScriptToLua),
  using Wisp: hot reload into running multiplayer clients, TypeScript
  lines for in-game errors, two-second map rebuilds, scripted fresh matches,
  and logic tests and replay tapes checked in Bun and 32-bit Lua. Use for any TypeScript map work, Smashcraft's ts/
  included, and whenever changing code in a running Warcraft game.
---

# Warcraft modding (TypeScript and Wisp)

Wisp (`bun wisp ...` from the project's TypeScript directory) is the framework
and development environment for Warcraft maps written in TypeScript. TypeScriptToLua (TSTL) compiles map code to Warcraft's Lua, Bun
runs the host tools and logic tests, and a running game takes new code without
re-hosting. Wisp is maintained in its own repository
(https://github.com/tompassarelli/wisp); Smashcraft (smashcraft:ts/) is its
first project and consumes a pinned Wisp package. Read the
project's style contract (smashcraft:docs/typescript.md) before writing map
code, and use `warcraft3-development` for launching, signing in and
controlling the game. For Effect APIs and design, also use
`effect-development` and follow Smashcraft's repository-local Effect
policy before changing its vendored source or Effect dependency.

## Effect in Wisp

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

0. **Every save.** Leave `bun wisp dev` running: it keeps the checker, the
   affected tests and the headless runtime warm and prints type errors (about
   0.06 s), the affected unit tests (about 0.6 s) and a two-client headless
   journey (about 2 s) after each save. Add `--data <client A CustomMapData>
   --data <client B ...>` to also hot-reload running clients.
1. **Logic.** `bun run test` runs every test, about 2 s. A focused run takes about
   0.07 s: `bun test test/game.test.ts -t NAME`. `bun run check` type-checks
   with TypeScript 7 in about 0.4 s. `bun wisp headless` plays the real bundle
   in simulated clients without Warcraft and reports desyncs, error reports and
   what a player would see wrong, in about 1.6 s.
2. **Emitted Lua.** Run `LUA=<32-bit lua> bun scripts/lua-tests.ts` to run the
   same tests in 32-bit Lua. That catches what Bun can't: integer wrap, binary32
   rounding and TSTL output.
3. **The running game.** Leave
   `bun wisp hot --data <client A CustomMapData> --data <client B ...> --watch`
   running. A save reaches both clients in about 0.4 s: only changed modules
   are sent. Its log reports each version as running or refused, with the time
   from save to both clients' acknowledgements, and prints in-game errors as TypeScript
   file and line about 0.05 s after they happen.
4. **A changed map file.** After one full project build,
   `bun wisp rebuild MAP.w3x` swaps only the script in about 2-4 s.
   Then `bun wisp fresh MAP.w3x` takes both signed-in clients from
   wherever they are into a new game of it, about 24 s. Do a full build only
   when assets, object data or non-TypeScript sources change.
5. **Behavior against the old game.** `LUA=<32-bit lua> bun wisp tapes`
   replays the acceptance tapes in compiled Wurst Lua, Bun and 32-bit Lua and
   names the first divergent frame and field, about 6 s cached.

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

How a reload applies: the host publishes each client's payload, then its
manifest, into `CustomMapData/<prefix>-hot`. Every client polls for its own
manifest, loads and verifies its copy and answers ready or refuse. On the last answer,
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
    `Date`, `JSON`, `Intl`, and Node, Bun and DOM APIs. Outside tests it also
    rejects `any`, `as unknown as` and non-null `!`; use the project's `at()`
    lookup for indices the caller guarantees.
- **`Preloader`:** it checks on every call whether a file exists, but runs the
  content it first read from that path for the rest of the session. Any file
  the host writes for the game to read again needs a new name for new content.
- **No `debug` library in map Lua:** error reports carry the failing line, and
  Wisp records a thrown value's TypeScript throw site at compile time. Full
  call stacks need the opt-in stack-traces plugin (development builds only).
- **`Object.assign`:** in Lua it skips fields whose value is `undefined`; copy
  records with optional fields field by field.

## Tests

Register tests with `test()` in `*.tests.ts`, so each runs in Bun and in
32-bit Lua. Keep a test only for a contract: a reference value, a gameplay or
netcode invariant, or a reproduced defect. Never change an expected value to
make a port or a change pass; a disagreement is a defect to name.

## Native client time is the bottleneck

Signed-in native clients are scarce: one pair is one serial lane, and one
owner drives it. Everything else runs in parallel around it.

- Batch native checks. One fresh map or session covers every presentation box
  that needs it; one bot session's outputs feed every checker that consumes
  them (replay-to-checksum, stall recovery, cost/overlay, captures). Test all
  new characters and content in one combined match, not one session each.
- Declare each native box as data next to the issue it closes (map profile,
  setup chat commands, captures, pass rule) and run the batch with
  `wisp accept [--only ID...]` (wisp:docs/accept.md; Smashcraft:
  `bun wisp accept`, checks in smashcraft:ts/scripts/wisp/acceptChecks.ts).
  `--dry-run` prints the plan without touching clients; each check reports
  pass, fail or needs-look with its private evidence folder.
- Never hand-drive a broken client. `wisp doctor [CLIENT...]`
  (wisp:docs/doctor.md; Smashcraft: `bun wisp doctor`) finds each client's
  state from events and runs its known recovery: dropped from Battle.net,
  crashed with the error dialog up, empty Options/Exit Game login shell,
  stale lobby or score screen, stuck loading, a map loaded without its
  imports, two runtimes on one prefix, a launcher whose connection failed.
  It stops with one plain line only when the owner must sign in. `play`,
  `fresh`, bot captures and `accept` run it before they start and once after
  a failure.
- Order the native queue by issues closed per session. Finish source and
  headless prep (driver fixes, command sequences) before native time, not during.
- The native lane gets machine priority. Perf, cost and timing captures need a
  quiet host: pause or defer heavy local jobs (suites, soaks, graph
  regeneration) for that window, and never let capacity gating starve it.
- Change one variable per native experiment; never confound launch path with
  display or config (route to `debugging`).
- Load the map by hosting through the menu socket after the game's post-login
  ladder-map scan (Maps/Download/Season<N>) finishes. Battle.net `-loadfile`
  can race that scan and make every war3mapImported asset fail (War3Log
  evidence, Smashcraft #73, 6 Oct 2026).
- Drive and observe through existing instrumentation (menu WebSocket, map
  receipts and journal, War3Log) before screenshots or OCR.
- Set up native sessions through in-map commands and receipts (slots,
  fighters, stage), never pointer clicks or OCR; pixels are for capturing
  evidence, not for driving.
- Before clicking, reading or waiting on a client, ask `wisp watch` what it is
  doing (wisp:docs/watch.md; Smashcraft: `bun wisp watch --once`, `bun wisp
  client wait CLIENT STATE...`): signed in, menu screen, lobby, loading, in
  match, results, disconnected or crashed, its map's load errors and the
  ladder scan, each from the menu socket, War3Log, crash reports, receipts or
  processes. In host code wait with `waitFor` and wrap existing waits in
  `unlessLost`, so a crash or lost Battle.net fails at once.

## Failure modes to avoid

Symptom, cause, rule. Smashcraft, 6 Oct 2026. Native-runtime classes (menu-socket
load, pixel driving, one variable) are in "Native client time is the bottleneck"
above and in `warcraft3-development`.

- "no element 1 in a table of 1" every tick at stage select: presentation built
  for one selection (stage decks drawn at shell start) outlived it. Key
  persistent presentation by the selection it was built for; headless journeys
  step through stage and fighter selection with computer slots
  (smashcraft:ts/test/bot-selection.test.ts).
- Bun and Lua tapes diverge (stray element, electric): a scratch object reused
  across hits/throws leaked fields; Bun runs all tapes in one process, Lua one
  process per tape. Reset every field of a reused scratch object; tapes catch it
  only when run in sequence.
- Every lane's Lua suite breaks on a literal like 0.02 or 1.4: not binary32 per
  the emitted-Lua number check. Wrap non-integer literals in `f32(...)` in tests too.
- 100+ MB Lua allocation spikes: per-kit text rebuilt by string concatenation in
  every checksum. Precompute static digests at load; no per-frame string building.
- Native work grinding for hours, duplicate CPU, edits landing in protected
  main: one agent owned all native work, each lane ran its own graph
  regeneration/soak, a relative `git worktree add` path resolved inside main.
  One native job per agent with a deadline and 20-minute reports; one shared
  regeneration/baseline; absolute worktree paths.
