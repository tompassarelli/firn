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
for both languages), `smashcraft-animation` for fighter animation,
`smashcraft-stage-design` for stage art and `effect-development` for Effect. Bun-hosted tools (commands, runners, builds,
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
1. **Logic.** Run the tests a change affects locally (`bun wisp dev`, or
   `bun test test/game.test.ts -t NAME`, 0.07 s); `bun run check` (0.4 s);
   `bun wisp headless` plays the real bundle in simulated clients and reports
   desyncs and visible faults (1.6 s). Full suites run on the farm, never on
   this machine: `bun wisp farm test --wait` runs the full Bun and 32-bit Lua
   suites for HEAD on GitHub's runners and prints the counts and each failing
   test (Smashcraft and Wisp; wisp:docs/farm.md).
2. **Emitted Lua.** The farm's Lua suite (locally,
   `LUA=<32-bit lua> GAME_TESTS=PATH bun scripts/lua-tests.ts` for the affected
   modules) runs the same tests in 32-bit Lua, catching integer wrap, binary32
   rounding and TSTL output that Bun can't.
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

- **Live build is 3.0.0.24268 again** (Blizzard rolled 3.0.1 back, 9 Oct;
  check `curl http://us.patch.battle.net:1119/w3/versions`). On 3.0.0.24268
  the offline LAN pool plays two-client matches on Wisp's own host and private
  LAN plugin, which only accepts that build. 3.0.1.24342 had no LAN provider,
  so if the live build leaves 24268, pool pairs stop at solo games until the
  plugin is checked on the new build. Patch notes still call 3.0 online only.
  The 3.0.1 items below (Blz names, art, asset fixes) are absent from 24268.
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
  The `testing` skill decides each test's level, tier, cost and deletion.

## Native testing

A native box in a subsystem with zero corpus divergence is met by its
headless check plus the weekly native spot batch (wisp#69). Every native
session records automatically; keep the covered recordings in Smashcraft's
`ts/test/corpus/`, where `bun wisp parity corpus` replays them in Bun and
32-bit Lua on every push. Native lanes batch the weekly spot checks with
their other pending sessions. A first divergent frame or field needs a fix
before that subsystem's headless check can meet its native box.

- **Offline LAN pool** (wisp:docs/lan.md), the default for every native
  check on 3.0.0.24268: pad parity, captures, `accept`, desync hunts and
  engine tools. One updated install feeds every pair, with no account and no
  sign-in: `wisp lan setup --from "<clone>/pfx/drive_c/Program Files
  (x86)/Warcraft III" --pairs N` (reflinked copies, under 1 s for 4 pairs),
  then `wisp lan pool --pair K... --pool-profile parity` (sound off; each pair
  in a loopback-only namespace, admitted by the capacity helper), then
  `bun wisp pad SCRIPT... --helper H --out DIR --map MAP --pair K...` with an
  integrity map (`map build --profile integrity`, or `map rebuild MAP
  --profile integrity`; the default dev build never answers the chat setup).
  Measured 9 Oct: a pair runs 70 s after `lan pool` starts and is in a match
  36 s after `pad` asks; two pairs played pad scripts at once with every
  native checksum, row and fighter line equal to headless. Add pairs one at a
  time while `protectedCpuSomeAvg10` stays under 20: two pairs is the default
  on this machine under normal agent load (with the online clones off, two
  pairs read 11-20 and three read 22-31; with the three clones on, two read
  44). `lan fresh MAP
  [--pair K]`, `lan status`, `lan end --pair K`; state and `clients.json` are
  in `~/.local/state/wisp/lan/`.
- **Signed-in clones B, C and D** (accounts b, c and d): only for tests that
  need Battle.net itself (real netplay, `online host|join`, spectating), as
  password-protected private games, and as the updated install the pool is
  copied from. Leave them stopped otherwise: each costs about 0.5 core plus
  about 1 core of Battle.net browser and its sound. After a Blizzard build
  change, close each clone's game (Battle.net updates it on exit, about 2
  min) and bring it back with `client doctor`. Passive reads only.
- **Clone-a** (account a, Tom's): a third test client used only while Tom
  isn't playing (one login per account). `launch.sh a RUN_DIR` refuses while
  his Warcraft or Battle.net runs and stops clone-a within 10 s when either
  starts (wisp:docs/lan.md). Start it only through that script.
- **Tom's install** (account a, display `:0`): no agent tests or engine
  tools; `wisp play` there only when Tom asks.

Signed-in clients run as user services that outlive the agent that started
them: `bun wisp client start [CLIENT...] --clients-file FILE` starts each
missing private desktop (`wisp-desktop-CLIENT`) and Battle.net
(`wisp-client-CLIENT`), runs doctor and returns at the menu; `client status`
names the service behind each, `client stop` stops them
(wisp:docs/doctor.md, "Clients as services"). Never start a client or desktop
from a shell or background task: it dies when that task ends.

Each client set (an offline pair, a signed-in clone pair, clone-a) has one
lane owner. It runs every pending native check in batches: one immutable
build, one session, many pad scripts and captures (`pad SCRIPT|DIR...`,
`accept --only ID...`). An issue's worker lands its fix, labels the issue
`needs:native-pair` (two clients) or `needs:native-single`, comments the map
or script and rows to capture, and moves on; it never starts clients itself.
The lane's queue is the open issues with its label, in either repository:
when a batch ends, it takes the next ones and removes the label when it ticks
the box or comments a failure. A lane adds `native:running` to an issue while
its check runs and skips issues that already carry it.

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
Tom's. When Tom's install shows the sign-in form, sign it in for him with
account a from the encrypted store, the same way doctor signs in test clients
(Tom, 8 Oct): a playtest is ready only when he can press Start. Never sign it
out, switch it, or run it on a test client. Never print decrypted credentials.

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
