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
   Then `bun wisp fresh MAP.w3x` takes both clients from wherever they are
   into a new game of it, about 24 s. Do a full build only when assets, object
   data or non-TypeScript sources change.
5. **Behavior against the old game.** `LUA=<32-bit lua> bun wisp tapes`
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

## Tests

Register tests with `test()` in `*.tests.ts`, so each runs in Bun and in
32-bit Lua. Keep a test only for a contract: a reference value, a gameplay or
netcode invariant, or a reproduced defect. Never change an expected value to
make a port or a change pass; a disagreement is a defect to name.

## Native testing and debugging

Pick the client by what the test needs (Tom, 7 Oct 2026):

- **Offline LAN pool: the default for native testing** (landing; until
  `wisp lan` is on Wisp main, use A/B). `wisp lan pool --pairs N` runs pairs
  of throwaway clients with no account, each in its own network namespace with
  no internet, playing over LAN. Its clients file is
  `~/.local/state/wisp/lan/clients.json`. Pad parity runs, captures, `accept`
  checks and desync hunts go here, and so does the full engine-tooling tier.
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
  process: `engine watch` and `locate --watch` (perf hardware breakpoints),
  `engine watch --lua` (stops the thread with ptrace for the exact Lua and
  TypeScript stack), gdb, memory writes (including the LAN provider switch), code or
  DLL injection. The tools refuse unless the client is verifiably offline:
  loopback-only network namespace, no `-uid`, no Battle.net program in its
  prefix, no socket off this machine. A gdb attach made a signed-in client exit.
- Always: only clients the project's clients file declares, never a game on
  `:0`, never other players' games or accounts; your own map only, never for
  cheating. Reads try first and usually work (launcher ancestry or Proton's
  user namespace); when one fails the command prints the
  `kernel.yama.ptrace_scope` commands, which only the owner runs. Keep
  decrypted code dumps and decompiler output private, outside every repository.

On a desync:

1. **Read the autopsy line.** Every native session runner (`wisp doctor`,
   `wisp watch`, runs wrapped by `withDoctor` with `autopsy`; in Smashcraft
   `pad`, `parity capture`, `fresh` and `accept`) runs the desync autopsy
   (wisp:docs/autopsy.md). On a new desync report it prints `desync autopsy:
   first divergent birth #N Class at turn T on client X` and saves the
   evidence under `~/.local/state/wisp/autopsy/<time>/`. Another runner wraps
   its run in `withAutopsy({ clientsFile }, run)`; a pool host passes the
   pool's clients file. `CScriptFunc` names a code callback.
2. **By hand**, for a desync outside a session: `wisp engine desync A B` on
   the clients' Documents folders names the first turn and section (only
   `ipse` means a handle made or freed on a different turn); `engine poll
   --client a,b` during a repro, then `engine diff`, names the birth's class;
   on offline clients `engine watch` gives its game stack and `watch --lua`
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

## Native client time is the bottleneck

`wisp play` is the owner's normal playable path. In Smashcraft it resolves
current main and builds the matching map and helper; never repoint it at an
experiment. Use `fresh`, captures or `accept` for named test candidates,
installed under Maps/00-Smashcraft/tests. Keep the latest playable map and two
previous versions visible at the top level, with older versions in older/. A
script-only rebuild does not update the map's in-game title or missing imports.

One client pair is one serial lane with one owner. Everything else runs in
parallel around it.

- Batch native checks. One fresh map or session covers every box that needs
  it; one session's outputs feed every checker that consumes them. Test all
  new characters and content in one combined match.
- Declare each native box as data next to the issue it closes (map profile,
  setup chat commands, captures, pass rule) and run the batch with
  `wisp accept [--only ID...]` (wisp:docs/accept.md; Smashcraft checks in
  smashcraft:ts/scripts/wisp/acceptChecks.ts). `--dry-run` prints the plan
  without touching clients.
- Never hand-drive a broken client. `wisp doctor [CLIENT...]`
  (wisp:docs/doctor.md) finds each client's state from events and runs its
  known recovery: dropped from Battle.net, crashed, empty Options/Exit Game
  login shell, stale lobby or score screen, stuck loading, a map loaded
  without its imports, two runtimes on one prefix, a launcher whose connection
  failed. It never signs in; it stops with one plain line when the owner must.
  `play`, `fresh`, captures and `accept` run it first and once after a failure.
- Before clicking, reading or waiting on a client, ask `wisp watch`
  (wisp:docs/watch.md; `bun wisp watch --once`, `bun wisp client wait CLIENT
  STATE...`). In host code wait with `waitFor` and wrap waits in `unlessLost`.
- Drive and observe through instrumentation (menu socket, map receipts and
  journal, War3Log) before screenshots or OCR. Set up sessions through in-map
  commands and receipts (`-dev quick`, `-dev quick hero NAME`, `-dev quick cpu
  N`, `-dev slots`), never pointer clicks; pixels are evidence, not driving.
- Load the map by hosting through the menu socket after the post-login
  ladder-map scan finishes; Battle.net `-loadfile` can race it and fail every
  war3mapImported asset (Smashcraft #73).
- Order the native queue by issues closed per session; finish source and
  headless prep first. The native lane gets machine priority: defer heavy
  local jobs during perf, cost and timing captures.
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

With Wisp, run `wisp doctor` instead of manual recovery. Where it stops on an
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
- Native work grinding for hours, duplicate CPU, edits landing in protected
  main: one agent owned all native work, each lane ran its own graph
  regeneration/soak, a relative `git worktree add` path resolved inside main.
  One native job per agent with a deadline and 20-minute reports; one shared
  regeneration/baseline; absolute worktree paths.
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
