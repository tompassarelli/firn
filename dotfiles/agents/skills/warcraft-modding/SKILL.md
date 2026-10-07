---
name: warcraft-modding
description: >-
  Develop and test Warcraft III maps: TypeScript map authoring with Wisp
  (TypeScriptToLua, hot reload into running clients, TypeScript lines for
  in-game errors, fast rebuilds, headless and 32-bit Lua tests) and the native
  game itself (offline LAN test clients, signed-in Battle.net clients, Steam
  Proton startup and recovery, accounts, display choice, desync debugging with
  wisp engine and the desync autopsy, API and netcode quirks, controller and
  multiplayer evidence). Use for any Warcraft III map work, Smashcraft's ts/
  included, and whenever launching, testing or changing code in a running
  Warcraft game. Wurst source authoring belongs to wurst-development.
---

# Warcraft modding

For Smashcraft fighter animation quality and action coverage, use
smashcraft-animation: source-backed silhouettes, drills, rolls/get-ups,
paired grabs/throws and nine-way pain reactions. Keep this skill for the
Warcraft runtime, asset publication and native-test boundary.

Wisp (`bun wisp ...` from the project's TypeScript directory) is the framework
and development environment for Warcraft maps written in TypeScript.
TypeScriptToLua (TSTL) compiles map code to Warcraft's Lua, Bun runs the host
tools and logic tests, and a running game takes new code without re-hosting.
Wisp is maintained in its own repository (https://github.com/tompassarelli/wisp);
its feature index, wisp:docs/index.md (installed as
`node_modules/wisp/docs/index.md`), lists every capability with its setup.
Smashcraft (smashcraft:ts/) is its first project and consumes a pinned Wisp
package; its command list is smashcraft:AGENTS.md. Read the project's style
contract (smashcraft:docs/typescript.md) before writing map code. Use
`wurst-development` for Wurst source; this skill owns the native game for
either language and does not choose or migrate a map's source language. For
Effect APIs and design, also use `effect-development` and follow Smashcraft's
repository-local Effect policy before changing its vendored source or Effect
dependency.

## Command vocabulary

Follow wisp:docs/cli.md for Wisp and game extensions: `wisp NOUN [VERB] [OBJECT...]`.
Map creation is `map build|rebuild`; client state and recovery are `client watch|wait|doctor`;
engine traps are `engine trace` and `engine locate --trace`; numeric checks and tapes
are `parity numeric|tapes`; native sessions are `integrity capture|result|headless`.
A new operation belongs under its existing noun. A new top-level noun requires a
row in the vocabulary table and a feature-index entry. Wisp's docs-index test and
the game's vocabulary test enforce registered nouns and usage flags.

Shared flags keep one meaning: `--client NAME` selects named native clients,
`--clients N` counts simulated clients, `--pairs N` counts pairs, `--profile NAME`
selects the map build, `--map MAP.w3x` selects the built map played or hosted, and
`--ref REF` selects the Git revision measured. Pool graphics use `--pool-profile`;
perf function reporting uses `--functions`; configuration files use `--clients-file`.
Migrate every live in-tree consumer with a rename; add no aliases. Saved dated
evidence retains the invocation it actually measured.

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
   `bun wisp map rebuild MAP.w3x` swaps only the script in about 2-4 s.
   Then `bun wisp fresh MAP.w3x` takes both clients from wherever they are
   into a new game of it, about 24 s. Do a full build only when assets, object
   data or non-TypeScript sources change.
5. **Behavior against the old game.** `LUA=<32-bit lua> bun wisp parity tapes`
   replays the acceptance tapes in compiled Wurst Lua, Bun and 32-bit Lua and
   names the first divergent frame and field, about 6 s cached.

6. **Heavy headless sweeps go to the farm, not this machine.** Smashcraft's
   repository is public, so GitHub's hosted runners are free (about 20 jobs
   at once, four cores each). `bun wisp farm balance --wait` plays the
   level-9, 400-a-pair balance field, one `cpuField --pairs` process a core,
   and prints the verdict and field table: 4.1 min from dispatch, against
   about 25 min locally on the shared machine (7 Oct). `bun wisp farm pads
   --wait` plays every native check script headless against its own `#!`
   expectations, 17 scripts in 4.2 min. Without `--ref` they measure the
   checkout's HEAD; a lane commit goes to a scratch `farm/` branch that is
   deleted after the run. Prefer the farm for any sweep needing no private
   build inputs or Warcraft client.

Re-host only when the map file itself must change. Before rebuilding and
rejoining, try hot reload: it keeps the clients, the lobby and the match state.

For Smashcraft CPU observation/history allocation, consume the shared immutable,
reference-counted snapshots in smashcraft:ts/src/game/match/botPerception.ts
(commit c3814aee): retain histories through `copyBotMemory` and release them
through `clearBotMemory`; never give one owner another owner's mutable history.
Stream the exact canonical checksum bytes through
smashcraft:ts/src/game/replay/canonical.ts and materialize replay text only on
request. In Lua32, 100 warmed four-fighter observation/history-copy samples
used 0.011 KB/frame versus the earlier 97.14 KB/frame; an equivalence sample
kept 1,300 observation strings and 10,000 number encodings identical. Regressions
live in smashcraft:ts/src/game/match/botReactionContracts.tests.ts and
smashcraft:ts/src/game/replay/canonical.tests.ts. Use the unchanged
`playable-bot-four` performance fixture for whole-frame acceptance. This
establishes the measured warmed allocation reduction, not flat memory across
matches or native handle lifetimes.

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
    `+` and `*` don't always round to nearest, and whose raw `/` can land an
    ulp off nearest.
  - Integer division and remainder use the project's `floorDiv`/`floorMod`
    (`idiv`/`imod` for Wurst semantics).
  - Synchronized reals use exact helpers or one operation per `f32()`:
    `f32(a + b)`, `f32(a - b)`, `f32(a * b)` and `f32(a / b)` compile to the
    exact binary32 helpers (a quotient through `divideFloat32`). Non-integer
    literals compile to exact hexadecimal floats, because Warcraft rounds a
    decimal that isn't binary32 its own way (wisp:docs/index.md, the f32 row).
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
- **A handle made at a per-client moment desyncs.** Creating or freeing an
  agent (timer, trigger, code callback closure) on a turn that differs between
  clients changes Tempest's checksum (#158: a `TimerStart` closure).

## Renderer features since Reforged

The complete per-patch index (natives, editor fields, script access, graphics
modes, cost, sources) is smashcraft:docs/design/warcraft-features.md; check
names against the pinned common.j (wisp:src/natives/warcraft.d.ts).

- **Only 3.0.0 (Forsaken Kingdom, Sept 2026) added graphics natives.**
  1.33–1.36 added none, 2.0.x changed shaders, tone map and assets without
  natives. Reach for 3.0 first:
  - fog: `SetTerrainFogExV` and `BlzSetTerrainFog{Style,ZStart,ZEnd,Density,
    HeightStart,HeightEnd,LinearStart,LinearEnd,MaxLinearDensity,DrawOverSky,
    Color}`, styles `FOG_STYLE_HEIGHT`, `_NEW_EXP`, `_NEW_EXP_2`;
  - HD water: `SetHDWaterParams[Ex]`, `BlzSetHDWater*` (HD and the player's
    Water option only);
  - `BlzSetMinShadowCastingPointLightCount`, depth-of-field camera fields,
    doodad/destructable colour and per-doodad animation natives.
- **1.32 still matters:** `BlzShowTerrain`/`BlzShowSkyBox` (hide terrain or
  sky), `CameraSetFocalDistance` (HD), skins, `SetPortraitLight`.
- **Editor-only, no native:** the 3.0 lighting editor and omni lights,
  map post-processing. A script gets lights only from models that contain
  them (unlimited in HD since 3.0, capped in Classic).
- **Impossible:** shaders, LUTs, bloom or exposure control, reading or
  choosing the graphics mode, driving PopcornFX particles.
- Day/night lighting models still drive key and fill light (`SetDayNightModels`);
  2.0 broke custom ones, so measure them on the current client.

## Frames, assets and CI

- **Frames:** declare a panel once as typed frames; Wisp generates its FDF, TOC
  and typed handle bindings and rejects bad names and anchors at build time
  (wisp:docs/ui.md). Prefer it to string-wired `BlzCreateFrameByType` code.
- **Imports:** the map build adds every import, base file and byte check in one
  archive opening (`map-pack replace-list`/`extract-list`; 1,108 files: 49 s to
  12 s). Imports are already compressed; measure before re-encoding assets
  (wisp:docs/asset-ingestion.md).
- **CI:** consumers call Wisp's reusable workflow (wisp:docs/ci.md) for check,
  Lua32 tests, headless journeys and soak. A `.w3x` is built only on a private
  self-hosted runner into its private store, never uploaded as a public artifact.

## Tests

Register tests with `test()` in `*.tests.ts`, so each runs in Bun and in
32-bit Lua. Keep a test only for a contract: a reference value, a gameplay or
netcode invariant, or a reproduced defect. Never change an expected value to
make a port or a change pass; a disagreement is a defect to name.

## Native testing and debugging

Pick the client by what the test needs (Tom, 7 Oct 2026):

- **Offline LAN pool: the default for native testing** (wisp:docs/lan.md).
  Throwaway clients with no account, each pair in a network namespace with
  only loopback, play LAN matches that Wisp hosts. `wisp lan setup --from
  INSTALL [--pairs N]` creates them once (reflinked from an install);
  `wisp lan pool [--pairs N | --pair K...] [--pool-profile parity|visual] [--fps N]` runs pairs admitted by
  the machine-capacity helper (foreground; Ctrl-C stops it); `wisp lan fresh
  MAP [--pair K]` hosts and starts a match; `wisp lan status`, `wisp lan end
  --pair K`. The host logs every turn's actions and compares checksums each
  turn: `wisp engine actions --client lan0a,lan0b [--follow]`, and `engine
  diff ACTIONS.log POLL.log` places each birth in its turn. Pool state is in
  `~/.local/state/wisp/lan/`; its `clients.json` is the clients file for
  `wisp engine` and `withAutopsy`. Pad parity runs, captures, `accept`
  checks and desync hunts go here, and so does the full engine-tooling tier.
  For pool contention, `--fps N` varies only foreground/background frame caps;
  keep the map and active script fixed and compare per-client CPU/GPU cost,
  protected CPU pressure, parity and game time before changing a default cap.
  Consume Wisp's discovery lifecycle mitigation (wisp commit 2aaae0b): close
  the lobby UDP discovery socket when countdown starts; gameplay continues on
  TCP. With Bun 1.3.13, an isolated two-second ECONNREFUSED polling sample
  consumed 1.664 CPU-seconds with the socket retained and 0.0028 after close
  (about 600× less isolated socket cost). The old pair host used 1.11 cores;
  fleet savings require a controlled pair-agent restart and measurement, so
  do not extrapolate the isolated ratio to the fleet. This is a bounded Wisp
  lifecycle mitigation, not a Bun root repair. When comparing this mitigation,
  keep the 60 fps cap and 2 ms autopsy polling unchanged. Procedure and
  regression are in wisp:docs/lan.md and wisp:test/lan.test.ts.
- **Signed-in A and B** (accounts c and b): only for tests that need
  Battle.net itself: real netplay or latency, direct play (`online
  host|join`, Smashcraft #142), spectating. Passive reads only.
- **Tom's install** (account a, display `:0`): Tom's. No agent tests, no
  engine tooling; `wisp play` there only when Tom asks.

Engine tooling has two tiers (wisp:docs/engine.md, "Guardrails"):

- **ONLINE-OK** (allowed on signed-in A/B): passive, out-of-process, nothing
  written. Reading Desync.log and War3Log (`engine desync`), read-only
  `/proc/PID/mem` reads (`engine poll`, whose log names a code callback's
  TypeScript line, `engine diff` of its logs, `engine locate` without
  `--watch`), passive packet capture.
- **OFFLINE-ONLY** (pool clients): anything that traps, stops or modifies the
  process: `engine trace` and `locate --trace` (perf hardware breakpoints),
  `engine trace --lua` (stops the thread with ptrace for the exact Lua and
  TypeScript stack), gdb, memory writes (including the LAN switch, which
  `wisp lan` makes and undoes within a fraction of a second), code or DLL
  injection. The tools refuse unless the client is verifiably offline:
  loopback-only network namespace, no `-uid`, no Battle.net program in its
  prefix, no socket off this machine. A gdb attach made a signed-in client exit.
- Always: only clients the project's clients file declares, never a game on
  `:0`, never other players' games or accounts; your own map only, never for
  cheating. Reads try first and usually work (launcher ancestry or Proton's
  user namespace); when one fails the command prints the
  `kernel.yama.ptrace_scope` commands, which only the owner runs. Keep
  decrypted code dumps and decompiler output private, outside every repository.

On a desync:

1. **Read the autopsy line.** Every native session runner (`wisp client doctor`,
   `wisp client watch`, runs wrapped by `withDoctor` with `autopsy`; in Smashcraft
   `pad`, `integrity capture`, `fresh` and `accept`) runs the desync autopsy
   (wisp:docs/autopsy.md). On a new desync report it prints `desync autopsy:
   first divergent birth #N Class at turn T on client X` and saves the
   evidence under `~/.local/state/wisp/autopsy/<time>/`. Another runner wraps
   its run in `withAutopsy({ clientsFile }, run)`; a pool host passes the
   pool's clients file. `CScriptFunc` names a code callback.
2. **By hand**, for a desync outside a session: `wisp engine desync A B` on
   the clients' Documents folders names the first turn and section (only
   `ipse` means a handle made or freed on a different turn); `engine poll
   --client a,b` during a repro, then `engine diff`, names the birth's class;
   on offline clients `engine trace` gives its game stack and `trace --lua`
   its exact Lua and TypeScript stack. On #158 this took
   the hunt from about 3.5 hours to about 30 minutes; start here before
   one-variable experiments.
3. After a Warcraft update, `engine locate` re-finds the offsets
   (wisp:scripts/wisp/engine/offsets.json).

A scripted native run is invalid, neither pass nor fail, when a client wrote a
new desync report or crashed during it, or a match reached results early;
rerun it. Gameplay boxes pass by checksum parity: the native run of a pad
script equals a headless run of the same script (Smashcraft: `bun wisp pad
... --compare`, scripts in smashcraft:ts/test/native/pads/).

## Native sessions across LAN pairs

`wisp play` is the owner's normal playable path. In Smashcraft it resolves
current main and builds the matching map and helper; never repoint it at an
experiment. Use `fresh`, captures or `accept` for named test candidates,
installed under Maps/00-Smashcraft/tests. Keep the latest playable map and two
previous versions visible at the top level, with older versions in older/. A
script-only rebuild does not update the map's in-game title or missing imports.

Private build inputs (base map, container, clip pools, stage, impact and
imported models, art) are content-addressed: each family is stored once,
read-only, under the hash of its contents, and the revision's
smashcraft:build-inputs.json names each family's hash, so `bun wisp map build`
needs no input flags and verifies them first. New art is `bun wisp inputs add
FAMILY DIR` plus a commit landed like code; never a shared farm, pointer file
or in-place edit (smashcraft:docs/build-inputs.md). Builders of one output share
a lock and publish a private staging folder by one rename; optional parts (the
controller helper) never block the map. A pre-push gate type-checks and audits
type escapes for every push that changes TypeScript.

When independent native checks or maps are ready, run them concurrently on
distinct supported offline LAN pairs. Assign each lane an explicit pair ID
and one owner, an immutable candidate map, and private output paths. Use
`bun wisp lan pool --pair K --pool-profile visual` for the assigned
pair, `bun wisp pad SCRIPT|DIR... --helper H --out PRIVATE_OUTPUT
--map IMMUTABLE_MAP.w3x --pair K` for its batch, or
`bun wisp accept --map IMMUTABLE_MAP.w3x --only ID... --pair K` for its declared acceptance checks.
`--map` uses the already-built candidate without rebuilding it; every
selected check must use the same build profile. Give each revision its own
private path; the same candidate is passed to every selected pair.
Do not let simultaneous acceptance runs rebuild the same mutable map path;
prepare their immutable candidates or use independent lane-owned fixtures.

Serialize operations on the same pair or shared mutable fixture. A measured
capacity or timing constraint may limit concurrent pairs for that workload;
name the measurement and affected interval. Do not create a global single
native-owner queue or infer a bottleneck merely because only one pair is
active. Admit additional clients through machine-capacity, preserve desktop
responsiveness, and investigate measured client/host cost before permanently
shrinking the pool. Pair ownership, signed-in-client restrictions, Tom's :0
boundary and offline-only invasive tooling continue to apply independently.

A timed ten-client batch coordinates its ten clients as one shared measurement
workload, with a fixed candidate, workload and measurement interval. It does
not combine the queues of independent visual/gameplay lanes. Run those lanes
on separate assigned pairs unless they share that fixture or a measured timing
or capacity constraint requires a scoped pause.

- Batch compatible checks within each pair. One fresh map or session covers
  their boxes and its outputs feed their checkers. Independent maps and checks
  use other assigned pairs concurrently.
- Run compatible pad parity scripts as one batch per pair, or shard one
  immutable candidate's batch across explicitly selected pairs:
  `bun wisp pad SCRIPT|DIR... --helper H --out DIR --map MAP.w3x
  --pair K...` (clients per "Native testing and debugging" above). It starts
  one game per pair, types `-dev reset` between scripts (it restores the
  boot match state; smashcraft:ts/test/dev-reset.test.ts holds the next
  match's checksums and moments equal to a new game's), starts every
  headless reference at once (`--headless-jobs N`) and compares as each
  native run ends. Measured on A+B, 7 Oct 2026, the old loop per script:
  new game 42-64 s, native run 23.5-26 s, headless compare 22 s (about
  1 min 50 s; 17 scripts over 35 min). The batch drops the new game and
  overlaps the compare: about 25 s a script per pair plus one new game, a
  reset costing about a second. Real-time runs slip on a saturated host
  (the batch reruns slipped scripts); run it on a quiet host
  (smashcraft:docs/native-bot-session.md, "Many scripts in one game").
- Declare each native box as data next to the issue it closes (map profile,
  setup chat commands, captures, pass rule) and run the batch with
  `wisp accept [--only ID...] [--pair K]` (wisp:docs/accept.md; Smashcraft checks in
  smashcraft:ts/scripts/wisp/acceptChecks.ts). `--dry-run` prints the plan
  without touching clients. In Smashcraft, `--pair K` starts through `lan fresh`
  and routes checks, captures, receipts, doctor and autopsy to that offline
  pair. `wisp integrity capture --clients-file FILE ...` likewise routes
  health checks to the selected clients (smashcraft:docs/native-bot-session.md).
  Consume these supported routes (Smashcraft commit 1745c4df) instead of
  adding bespoke doctor/autopsy wrappers or accidentally recovering online A/B.
- Exact pad pose captures use the original authored `capture` frames. With a
  scripted quick match, Smashcraft holds each pose locally through Wisp's
  framebuffer read while simulation and helper inputs continue unchanged
  (smashcraft:docs/native-bot-session.md). Both drawn receipts must name the
  requested match and frame; a skipped frame, absent completion or stalled clock
  makes the run INVALID, retaining earlier successful images. Wisp bounds a
  framebuffer read to eight seconds and reaps its capture child before returning
  failure (wisp:docs/player-view.md). `held visual` captures establish the pose;
  input-to-screen timing requires the live response route below.
- Keyboard response capture: `bun wisp map build --profile native-input --name NAME --out IMMUTABLE_MAP.w3x`
  retains the playable keyboard path, two-frame delay, rollback and predicted
  pooled fighters, adding developer setup and the response probe (Smashcraft
  commit 019983c0). Ctrl+G starts recording and Ctrl+H exports callback/input
  rows to CustomMapData; the magenta marker identifies the callback drawn in
  captured pixels. Pair original host input timestamps with framebuffer
  timestamps: exported game-clock rows alone do not measure press-to-screen
  latency. Report diagnostic overhead separately; journal integrity uses a
  different input path. See smashcraft:docs/native-bot-session.md,
  "Raw playable cost captures".
- Never hand-drive a broken client. `wisp client doctor [CLIENT...]`
  (wisp:docs/doctor.md) finds each client's state from events and runs its
  known recovery: dropped from Battle.net, crashed, empty Options/Exit Game
  login shell, stale lobby or score screen, stuck loading, a map loaded
  without its imports, two runtimes on one prefix, a launcher whose connection
  failed. It never signs in; it stops with one plain line when the owner must.
  `play`, `fresh`, captures and `accept` run it first and once after a failure.
- Before clicking, reading or waiting on a client, ask `wisp client watch`
  (wisp:docs/watch.md; `bun wisp client watch --once`, `bun wisp client wait CLIENT
  STATE...`). In host code wait with `waitFor` and wrap waits in `unlessLost`.
- Drive and observe through instrumentation (menu socket, map receipts and
  journal, War3Log) before screenshots or OCR. Set up sessions through in-map
  commands and receipts (`-dev quick`, `-dev quick hero NAME`, `-dev quick cpu
  N`, `-dev slots`), never pointer clicks; pixels are evidence, not driving.
- Load the map by hosting through the menu socket after the post-login
  ladder-map scan finishes; Battle.net `-loadfile` can race it and fail every
  war3mapImported asset (Smashcraft #73).
- Order each pair's queue by issues closed per session; finish source and
  headless prep first. Protect performance/cost/timing captures from local
  heavy work within their declared measurement interval; keep independent
  ready native lanes moving outside a measured shared constraint.
- Change one variable per native experiment (route to `debugging`). Research
  Warcraft III bugs and engine behaviour on Hive Workshop (hiveworkshop.com)
  first; Blizzard's forums carry patch notes.

## Displays

Default agent-driven Warcraft to an off-monitor private desktop; use
`private-desktop-development` for that desktop, its capture and input
transport, and read it before creating or controlling one. Use the current
monitor only when the owner's request clearly calls for it, such as a
hands-on controller trial they need to see; confine input to that window.
At the start of a session whose agenda needs the main display, ask the owner
once whether that is fine this session; with a yes, send a one-line heads-up
before each use. Use `image-context-budget` for repeated inspection.

## Startup, recovery and accounts

With Wisp, run `wisp client doctor` instead of manual recovery. Where it stops on an
unknown state, the manual rules are: one runtime per mutable prefix (never
start a second one against a live prefix); start Warcraft with Play in the
already-signed-in Battle.net launcher, never a direct `Warcraft III.exe`
launch as authentication recovery; an empty Options/Exit Game shell after
login is the known post-login failure, recovered by the retained launcher's
Play, not another sign-in; a login form, shell or process is not a successful
launch until the real menu and one gameplay action are verified. Keep working
signed-in clients across map leave/rejoin; restart only an unusable client.
Steps, launcher authentication transport checks, warm exit and observed
evidence: [startup and recovery](references/warcraft-startup.md).

Accounts: encrypted pairs live in nixos-config:secrets/bnet.yaml (a, b, c).
Account a is Tom's personal account and install
(~/.local/share/Steam/steamapps/compatdata/3516115571); the login helper
refuses it, and it needs Tom's explicit per-session authorization. Never sign
in, log out or switch accounts on the owner's launcher, and never pass
`--owner-authorized` without that authorization. Standing case: on 6 Oct 2026
Tom authorized `wisp play` on a's install for Wisp#14/#73 checks only, with no
sign-in, logout or account changes. Test clients use b (client B)
and c (client A, ~/.local/share/wc3-melee/client-a); concurrent online clients
need distinct accounts and separate prefixes. Ordinary credential prompts on
A/B are yours: verify a real login form and the focused field, then run
nixos-config:dotfiles/bin/wc3-login-field (account a|b|c, username|password)
in a shell with jq, xdotool and sops, using the machine SOPS key through sudo.
Never print decrypted values or put them in arguments, clipboard, traces,
screenshots or files. Enable supported persistent login and verify launcher
online state and W3 SSO before Play. Authenticator, CAPTCHA or account lock
is a blocker: notify by email only through an available authenticated route
and say so honestly when there is none.

## Native procedures and evidence

Prefer event-driven automation: advance on observed state (receipts, menu
socket, trace events), with timers only bounding waits; a fixed delay is a
labelled fallback. For repeated menu work, identify the starting screen once,
batch known inputs, and check the ending state; stop a chain on an unexpected
result. Record successful chains (start/end state, build, geometry, inputs,
waits, time, artifact) in the project and measure warm loops separately from
cold launch, loading and builds ([fast native iteration](references/fast-native-iteration.md)).

Before designing or diagnosing input, commands, netcode, rollback or FileIO,
resolve the Warcraft semantics from pinned API documentation, existing map code
and a distinct prior-art approach (`prior-art`), with the API family's
evidence in [API gotchas](references/api-gotchas.md). Player-issued orders
differ from map-script `Issue*Order`; event arrival does not preserve press,
frame or analog value; capture, transport, confirmation, rendering and
button-to-pixel time are different quantities. Answer an input-timing question
with one aggregate end-to-end run on the current release. When integration is
slow but a native baseline works, investigate the harness first and compare the
same bytes, rate, players, phase, prefix and receiver path.

Native multiplayer acceptance needs actual clients joining and playing the same
candidate; synthetic host tests and a working launcher do not establish online
responsiveness or controller feel. For an owner's trial use `bun wisp play`;
confirm roster, stage thumbnails and gameplay before calling a build ready. For
a keyboard mapper trial, enable mapping only while Warcraft is focused and
verify movement, jump and attack; report digital mapping apart from analog
input and hardware latency.

## Failure modes to avoid

Symptom, cause, rule. Smashcraft, 6-7 Oct 2026.

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
- Desync hunt ran 3.5 hours of one-variable native experiments (#158): nobody
  looked inside the engine. Read the autopsy line, then `wisp engine`.
- Green HUD, invisible stage, "menus could not load": `-loadfile` raced the
  post-login ladder-map scan. Host via the menu socket after the scan; treat any
  "model creation failed - war3mapImported" as a failed load.
- Private test client at the wrong aspect, pointer clamps: main-display play
  sharing its prefix rewrote War3Preferences on exit. One prefix per display
  role, or save/restore War3Preferences (wisp:docs/display-settings.md).
- Missing log line read as a state (no LoginDoorClose): War3Log is written in
  bursts. The menu socket outranks the log for sign-in and menus.
- Grey sky for seconds in the first match after a cold start: models draw late.
  Preload stage/scene models; take evidence frames only after a receipt says
  the scene is drawn.
- Missed clicks, wrong pointer targets, slow OCR: XTEST clicks shorter than one
  frame are missed by per-frame-sampled UI. Drive with in-map commands and
  receipts plus the menu socket.
- Receipt wait times out on a fresh game: it rewrote an identical receipt file.
  Wait on a counter or timestamp, never text equality.
- `bun wisp play` broke for every lane ("extract war3mapImported\\...Clip47
  failed", "Cannot open map archive"): ~20 lanes hand-edited one global input
  pointer, and concurrent builders shared an output folder, a `.next` file and
  a build worktree. Content-address shared inputs and name them per revision in
  Git; build into private staging, publish by one rename under a per-key lock.
