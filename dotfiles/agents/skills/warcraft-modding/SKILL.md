---
name: warcraft-modding
description: >-
  Develop and test Warcraft III maps: TypeScript maps with Wisp (hot reload,
  fast rebuilds, headless and 32-bit Lua tests) and the native game (offline
  LAN test clients, signed-in clients, startup recovery, desync debugging).
  Use for any Warcraft III map work, Smashcraft's ts/ included.
---

# Warcraft modding

Wisp (`bun wisp ...` from the project's TypeScript directory) is the framework
for Warcraft maps written in TypeScript: TypeScriptToLua (TSTL) compiles map
code to Warcraft's Lua, Bun runs host tools and tests, and a running game takes
new code without re-hosting. Its feature index is wisp:docs/index.md
(`node_modules/wisp/docs/index.md`). Smashcraft (smashcraft:ts/) uses a pinned
Wisp; its command list is smashcraft:AGENTS.md. Read
smashcraft:docs/typescript.md before writing map code.

Use `wurst-development` for Wurst source (this skill covers the native game
for both languages), `smashcraft-animation` for fighter animation and
`effect-development` for Effect. Bun-hosted tools (commands, runners, builds,
captures, farm jobs) are Effect programs when they start processes, wait,
retry, hold a resource or parse outside data; a test in each repo fails a new
one that isn't. Map code compiled to Lua can't import Effect and stays plain
TypeScript.

## Commands

Follow wisp:docs/cli.md: `wisp NOUN [VERB] [OBJECT...]` (`map build|rebuild`,
`client watch|wait|doctor`, `engine trace`, `parity numeric|tapes`,
`integrity capture|result|headless`). A new operation goes under an existing
noun; a new noun needs a vocabulary row and a feature-index entry, which tests
enforce. Flags mean one thing: `--client NAME` native clients, `--clients N`
simulated clients, `--pairs N` pairs, `--profile NAME` map build, `--map
MAP.w3x` built map, `--ref REF` revision measured, `--pool-profile` pool
graphics, `--functions` perf reporting, `--clients-file` a clients file. A
rename updates every caller; no aliases.

## Take the fastest signal

0. **Every save.** Leave `bun wisp dev` running: type errors (about 0.06 s),
   affected tests (0.6 s) and a two-client headless journey (2 s) after each
   save. `--data <client A CustomMapData> --data <client B ...>` also
   hot-reloads running clients.
1. **Logic.** `bun run test` (about 2 s); `bun test test/game.test.ts -t NAME`
   (0.07 s); `bun run check` (0.4 s); `bun wisp headless` plays the real
   bundle in simulated clients and reports desyncs and visible faults (1.6 s).
2. **Emitted Lua.** `LUA=<32-bit lua> bun scripts/lua-tests.ts` runs the same
   tests in 32-bit Lua, catching integer wrap, binary32 rounding and TSTL
   output that Bun can't.
3. **The running game.** `bun wisp hot --data <A> --data <B> --watch` sends
   only changed modules to both clients in about 0.4 s, says whether each
   version runs or was refused, and prints in-game errors as TypeScript lines.
4. **A changed map file.** Try hot reload first; it keeps clients, lobby and
   match state. After one full build, `bun wisp map rebuild MAP.w3x` swaps
   only the script (2-4 s) and `bun wisp fresh MAP.w3x` moves both clients
   into a new game (24 s). Full builds only for assets, object data or
   non-TypeScript sources.
5. **Behavior against the old game.** `LUA=<32-bit lua> bun wisp parity
   tapes` replays the acceptance tapes in Wurst Lua, Bun and 32-bit Lua and
   names the first differing frame and field (6 s cached).
6. **Heavy headless sweeps go to the farm.** Smashcraft is public, so GitHub's
   runners are free (about 20 jobs, four cores each). `bun wisp farm balance
   --wait` plays the level-9 balance field in 4.1 min (25 min locally); `bun
   wisp farm pads --wait` plays all 17 native check scripts headless in 4.2
   min. Without `--ref` they test HEAD via a scratch `farm/` branch. Use the
   farm for any sweep that needs no private build inputs or Warcraft client.

## Write code that reloads

- Engine callbacks bind to `trampoline(name)` once and get behavior from
  `on(name, handler)` (the project's dispatch module). A reload re-registers
  handlers; timers and triggers made at start keep running.
- State that survives a reload lives in a global (`declare global { var
  __name: State | undefined }`); module locals start fresh.
- The entry module's `install()` registers every handler, the reloader's
  included, at start and after each reload. Module scope does no work.
- A reload never changes the map file, object data, assets or existing
  handles. A reload that changes the shape of global state converts it or
  starts a fresh match.

The host writes each client's payload, then its manifest, to
`CustomMapData/<prefix>-hot`; each client verifies its copy and answers ready
or refuse. All clients install on the same frame or none do; "hot reload N not
applied" names the reason.

## Warcraft facts the tools rely on

- **Numbers.** Lua integers are 32-bit and wrap; binary32 `+` and `*` don't
  always round to nearest and `/` can be an ulp off. Use `floorDiv`/`floorMod`
  (`idiv`/`imod` for Wurst semantics). Synchronized reals take one operation
  per `f32()`: `f32(a + b)`, `f32(a - b)`, `f32(a * b)`, `f32(a / b)`.
  Non-integer literals compile to exact hex floats.
- **Rejected by the compiler:** `%`, `>>>`, `Math.floor(a / b)`, decimals
  that aren't binary32 (write `f32(0.1)`, in tests too), `Math.random`,
  `Date`, `JSON`, `Intl`, Node, Bun and DOM APIs; outside tests also `any`,
  `as unknown as` and `!` (use the project's `at()`).
- **`Preloader`** checks each call whether a file exists but runs the content
  it first read from that path all session. New content needs a new name.
- **No `debug` library.** Errors carry the failing line and Wisp records the
  TypeScript throw site. Full stacks need the opt-in stack-traces plugin.
- **`Object.assign`** skips `undefined` fields in Lua; copy optional fields
  one by one.
- **A handle made at a per-client moment desyncs.** Creating or freeing a
  timer, trigger or callback on a turn that differs between clients changes
  the checksum (#158).

## Warcraft 3.0 (September 2026) changes

From the patch notes for 3.0.0 (build 24268, 12 Sep) and 3.0.1 (build 24342, 7 Oct):

- **Online only.** LAN mode is removed, and the client must stay online (offline
  only through the Classic Client, reported to be Legacy 1.29, which has no Lua
  and can't run Wisp maps). Our offline pool ran on 3.0.0 but stops at a
  war3_loader assertion on 3.0.1; 3.0.1's notes don't mention it. Native checks
  run as password-protected online private games on Tom's three accounts unless
  an isolated, internet-free pool copy starts (wisp:docs/lan.md).
- **Natives.** 3.0 natives carry the `Blz` prefix as of 3.0.1, and the
  unprefixed names will be removed. New: cooldown resets and settings, an
  aura toggle, `BlzUnitHeal`, `BlzRemoveEffect`, `BlzResetUnitTalents`, and
  `BlzSetCameraAllowsHotkeyTargetLock` (the old camera lock functions now
  disable hotkey target lock). Declare them in Wisp and model them headlessly
  before using them (wisp#51).
- **Art changed in 3.0.1.** The Pandaren Brewmaster and Orc Grunt are
  reanimated, and about 35 spell effects were retuned, among them Blizzard,
  Divine Shield, Immolation, Starfall, Black Arrow, Breath of Fire, Banish,
  Life and Mana Drain, Roar, Forked Lightning and Death Coil. Re-derive clip
  tables and re-take reference captures that use them.
- **Assets and sound.** OGG audio imports work, and the floating-text cap is
  10,000. 3.0.1 fixed custom-asset loading and model paths containing periods.
  Definitive Edition plays classic sounds, so a sound check names its graphics
  mode.
- **Fixed engine bugs.** Projectiles appear when the target is very close, and
  new lightning effects no longer remove old ones. Drop workarounds for either.
- **Graphics.** The modes are Classic, Definitive Edition and Reforged. 3.0.0
  removed Bloom, Portrait Bloom, Particles and Spells and added Point Light
  Shadows, Water and Supersampling; 3.0.1 restored Ambient Occlusion. Test
  profiles set the mode and Ambient Occlusion explicitly. Forsaken Paladin is
  a neutral tavern hero in all three modes.

## When the engine does something odd

Check [Warsmash](https://github.com/Retera/WarsmashModEngine) first. It
rebuilds Warcraft III's simulation and renderer from scratch, and its author
has already worked out most odd engine behavior: animation blending and
playback, pathing, collision, order queues, and attack and damage timing. The
simulation is under `core/src/com/etheller/warsmash/viewer5/handlers/w3x/simulation/`.
A fork with a browser-build branch,
[ErikSom/WarsmashModEngine `HTML`](https://github.com/ErikSom/WarsmashModEngine/tree/HTML),
is the reference for playing a map outside Warcraft (wisp#48). Its live build,
[warsmash.pages.dev](https://warsmash.pages.dev) (v0.2.0), loads maps from the
player's own Warcraft III files kept in browser storage and plays multiplayer
over lockstep WebRTC peer to peer, with no server.

- It's a lead, not the answer. Confirm the behavior against the real game
  before changing Wisp; Warsmash targets older versions and skips models newer
  than 1.33.
- Read it; never copy or adapt its code. It's AGPL-3.0 and Wisp is MIT. Write
  what you learn as a behavior note (a number, formula or order of events) in
  wisp:docs/warsmash-notes.md, and build from the note.

## Frames, assets, CI and tests

- Declare panels as typed frames (wisp:docs/ui.md). Imports are already
  compressed; measure before re-encoding (wisp:docs/asset-ingestion.md).
- CI uses Wisp's reusable workflow (wisp:docs/ci.md); a `.w3x` is built only
  on a private runner and never uploaded publicly.
- Register tests with `test()` in `*.tests.ts` so each runs in Bun and 32-bit
  Lua. Keep a test only for a reference value, a gameplay or netcode
  invariant, or a reproduced defect. Never change an expected value to pass.

## Native testing

- **Offline LAN pool, the default while it starts** (wisp:docs/lan.md; it fails
  on 3.0.1, see Warcraft 3.0 changes): throwaway clients,
  each pair in a loopback-only network namespace. `wisp lan setup --from
  INSTALL [--pairs N]` once; `wisp lan pool [--pairs N | --pair K...]
  [--pool-profile parity|visual] [--fps N]` runs pairs through the
  machine-capacity helper; `wisp lan fresh MAP [--pair K]`, `lan status`,
  `lan end --pair K`. State and `clients.json` are in
  `~/.local/state/wisp/lan/`. Pad parity, captures, `accept` and desync hunts
  run here.
- **Signed-in A and B** (accounts c and b): tests that need Battle.net (real
  netplay, `online host|join`, spectating), and every native check while the
  offline pool can't start, as password-protected private games. Passive
  reads only.
- **Clone-a** (account a, Tom's): a third test client used only while Tom
  isn't playing (one login per account). `launch.sh a RUN_DIR` refuses while
  his Warcraft or Battle.net runs and stops clone-a within 10 s when either
  starts (wisp:docs/lan.md). Start it only through that script.
- **Tom's install** (account a, display `:0`): no agent tests or engine
  tools; `wisp play` there only when Tom asks.

Each client set (an offline pair, the signed-in A+B pair, clone-a) has one
lane owner. It runs every pending native check in batches: one immutable
build, one session, many pad scripts and captures (`pad SCRIPT|DIR...`,
`accept --only ID...`). An issue's worker lands its fix, hands the native box
to the lane and moves on; it never starts clients itself.

Engine tools (wisp:docs/engine.md, "Guardrails"): signed-in A/B allow only
passive reads (`engine desync`, `engine poll`, `engine diff`, `engine locate`
without `--watch`, packet capture). Anything that traps, stops or changes the
process (`engine trace`, `locate --trace`, `trace --lua`, gdb, memory writes,
injection) runs only on offline pool clients: loopback-only namespace, no
`-uid`, no Battle.net program in the prefix. A gdb attach made a signed-in
client exit. Only clients in the project's clients file, never `:0`, never
other players' games, never for cheating. Keep decrypted code dumps outside
every repository.

On a desync:

1. **Read the autopsy line.** Session runners (`client doctor`, `client
   watch`, Smashcraft's `pad`, `integrity capture`, `fresh`, `accept`) print
   `desync autopsy: first divergent birth #N Class at turn T on client X` and
   save evidence under `~/.local/state/wisp/autopsy/` (wisp:docs/autopsy.md).
   Wrap other runners in `withAutopsy({ clientsFile }, run)`. `CScriptFunc`
   names a code callback.
2. **By hand:** `wisp engine desync A B` on the Documents folders names the
   first turn and section (`ipse`: a handle made or freed on a different
   turn); `engine actions --client lan0a,lan0b` shows the host's turn log;
   `engine poll --client a,b` then `engine diff` names the class; offline,
   `engine trace --lua` gives the Lua and TypeScript stack. This cut #158 from
   3.5 hours to 30 minutes.
3. After a Warcraft update, `engine locate` re-finds the offsets.

A native run where a client crashed, wrote a new desync report or reached
results early is neither pass nor fail; rerun it. A gameplay check passes when
the native run of a pad script matches a headless run of it (`bun wisp pad ...
--compare`, scripts in smashcraft:ts/test/native/pads/).

## Native sessions

- `wisp play` is Tom's playable path and builds current main; never point it
  at an experiment. Test maps go through `fresh`, captures or `accept`. Before
  calling a build ready, confirm roster, stage thumbnails and gameplay.
- `bun wisp map build` needs no input flags: private build inputs are stored
  by content hash and named in smashcraft:build-inputs.json. Add art with
  `bun wisp inputs add FAMILY DIR` and commit it; never edit inputs in place.
- Never hand-drive a broken client: `wisp client doctor` detects and recovers
  known states and never signs in. Before clicking, reading or waiting on a
  client, ask `wisp client watch` (`--once`, or `client wait CLIENT STATE`).
- Set up sessions with in-map commands (`-dev quick`, `-dev quick hero NAME`,
  `-dev quick cpu N`, `-dev slots`); observe through the menu socket, the
  map's status files and War3Log; never drive with pointer clicks. Host
  through the menu socket after the post-login ladder-map scan, since
  `-loadfile` can race it and lose every imported asset (#73).
- Change one variable per native experiment (`debugging`); search Hive
  Workshop for Warcraft bugs first.

Agent-driven Warcraft runs on an off-monitor private desktop
(`private-desktop-development`). Use the main display only when Tom's request
needs it: ask once per session, then give a one-line heads-up before each use.

## Startup and accounts

Run `wisp client doctor` instead of manual recovery. If it stops: one runtime
per prefix; start Warcraft with Play in the signed-in Battle.net launcher,
never a direct `Warcraft III.exe` launch; an empty Options/Exit Game shell
after login is fixed by the launcher's Play, not another sign-in. A launch
counts only once the real menu and one gameplay action work. Account a is
Tom's: never sign in, out or switch accounts on it without his say-so for that
session. Never print decrypted credentials.

## References

Read a file only when its trigger matches:

| File | Read when |
|---|---|
| [native-sessions.md](references/native-sessions.md) | you need doctor's recovered states, chat-setup steps, map version layout or input-timing evidence rules |
| [warcraft-startup.md](references/warcraft-startup.md) | doctor stopped and you must start or recover a client by hand |
| [accounts-and-login.md](references/accounts-and-login.md) | signing in a test client, or any account question |
| [lan-pair-batching.md](references/lan-pair-batching.md) | running several native checks or maps at once, or declaring `accept` checks |
| [pad-and-input-capture.md](references/pad-and-input-capture.md) | running pad script batches, pose captures, or timing keyboard press-to-screen |
| [lan-discovery.md](references/lan-discovery.md) | tuning pool frame caps or the lobby discovery socket's CPU cost |
| [fast-native-iteration.md](references/fast-native-iteration.md) | automating repeated menu or native steps and timing warm loops |
| [api-gotchas.md](references/api-gotchas.md) | choosing an input, sync or FileIO API path |
| [renderer-features.md](references/renderer-features.md) | adding fog, water, lighting or other graphics natives |
| [bot-perception.md](references/bot-perception.md) | changing Smashcraft CPU observation, history or replay checksum code |
| [effect-in-wisp.md](references/effect-in-wisp.md) | adding Effect to Smashcraft tools or map code |
| [failure-modes.md](references/failure-modes.md) | a Smashcraft session or build shows a symptom you don't recognize |
