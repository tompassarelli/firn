# Native session rules in detail

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
  Native chat setup uses Wisp's `openObservedChat` and `confirmedCommand`
  (wisp:scripts/wisp/chatSetup.ts; wisp:docs/watch.md): wait for the selected
  pair's fresh binding-ready files, observe Return's new chat publication,
  and confirm both requested map receipts before scripted input. Missing setup
  is INVALID at its first client boundary. Journal chat leaves a match paused;
  a continuing workload explicitly resumes and observes both helper receipts.
- Load the map by hosting through the menu socket after the post-login
  ladder-map scan finishes; Battle.net `-loadfile` can race it and fail every
  war3mapImported asset (Smashcraft #73).
- Change one variable per native experiment (route to `debugging`). Research
  Warcraft III bugs and engine behaviour on Hive Workshop (hiveworkshop.com)
  first; Blizzard's forums carry patch notes.

## Procedures and evidence

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
