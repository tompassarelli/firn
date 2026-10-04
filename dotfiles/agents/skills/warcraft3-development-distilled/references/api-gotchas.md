# Warcraft API evidence for input, networking and FileIO

Use the relevant family to answer the current decision, not as a checklist for
all map changes. Sources below were inspected on 2026-10-04. Jassdoc is community
annotation of the native declarations, not a Blizzard latency guarantee. Its
pinned source is
[common.j at d49b2ba](https://github.com/lep/jassdoc/blob/d49b2ba47c72ad757aa17abdfa9ccd55a7493fd5/common.j).
A declaration establishes availability/signature; annotations and reports need
their stated version scope. Confirm decisive behavior on the actual game build.

## Choose an ingress path by the semantics it preserves

| Path | What the inspected source supports | What a native comparison must establish |
| --- | --- | --- |
| `BlzTriggerRegisterPlayerKeyEvent` | Game-synchronized key events, modifier mask and separate down/up registration. The annotation reports one down event in 1.31.1 but roughly 30 fluctuating repeats/second in 1.32.10. | Current-build repeat/release behavior, modifiers, focus and delay. A received key event is not the original local capture time. Do not blindly synchronize it again. |
| `BlzIsKeyPressed`, `BlzIsMetaKeyPressed`, `BlzIsMouseButtonPressed` | Declared from 3.0.0.24268; the declarations supply no latency or synchronization contract. | Treat local-device samples as local input until an explicit transport establishes shared data. Check availability, sampling cadence and edges shorter than the polling interval. Polling does not recover presses missed between samples. |
| `BlzSendSyncData` plus player sync event | Sends a prefix/data string to players; receiver registration selects player and prefix, `fromServer` is documented as false, and `GetTriggerPlayer()` identifies the sender. | End-to-end receipt, ordering, loss/backlog and sustained throughput on the actual topology and receiver workload. A boolean return is not remote receipt or simulation confirmation. |
| Player-issued unit orders, ability commands or shop actions | Order, spell and sell event families and their event-response natives expose engine gameplay actions. | Whether a real player/UI-issued action supplies the desired signal quickly enough on both clients, and the cost of selection, hotkeys, target/queue rules, cooldowns, resources or stock. Match the actual order/cast/effect/sale phase required. |

Native command proxies are real alternatives, not proof of a free arbitrary-data
channel. A command action does not automatically encode key release, held state,
original capture frame or continuous analog values. Define those semantics
before judging whether the proxy fits. Compare an actual player-issued command
with the sync path; calling `IssueImmediateOrder`/`IssuePointOrder` in a timer
would test map simulation orders instead. These script calls are not documented
as sending a local player's command to peers. Warcraft runs map simulation on
all clients; do not issue divergent gameplay mutations under `GetLocalPlayer()`.

`ForceUIKey` is another distinct path: documentation says it consumes one ASCII
letter/digit, depends on the player's hotkey layout and may fire key-down without
key-up. `ForceUICancel` has different key-event behavior and hotkey-layout bugs.
Neither is a faithful substitute for physical key transitions. In an order
proxy, separately prove the local UI action, resulting command and remote event.

Sources in pinned common.j:
[key/sync/polling declarations](https://github.com/lep/jassdoc/blob/d49b2ba47c72ad757aa17abdfa9ccd55a7493fd5/common.j#L27640),
[order events](https://github.com/lep/jassdoc/blob/d49b2ba47c72ad757aa17abdfa9ccd55a7493fd5/common.j#L3865),
[spell/shop events](https://github.com/lep/jassdoc/blob/d49b2ba47c72ad757aa17abdfa9ccd55a7493fd5/common.j#L4425),
[script orders](https://github.com/lep/jassdoc/blob/d49b2ba47c72ad757aa17abdfa9ccd55a7493fd5/common.j#L18348),
[local-player execution](https://github.com/lep/jassdoc/blob/d49b2ba47c72ad757aa17abdfa9ccd55a7493fd5/common.j#L18773),
[UI key simulation](https://github.com/lep/jassdoc/blob/d49b2ba47c72ad757aa17abdfa9ccd55a7493fd5/common.j#L21173).

## Sync payload and timing claims

[BlzSendSyncData documentation](https://lep.nrw/jassbot/doc/BlzSendSyncData)
says prefix and data are limited to “something like 255 bytes”; it does not
promise an exact universal cap or calls-per-second quota. Measure the boundary
if it determines the representation. Bytes are not characters: a 2.0.4 note
warns that splitting a multibyte character across chunks makes individual chunks
invalid for display, even when joining first preserves the text.

For a slow integration with a working baseline, first compare registration,
duplicate sends/listeners, prefix routing, encoding, receiver work, queues and
instrumentation. Hold bytes, send rate, participant count, game phase and
receiver path constant; changing these together cannot identify the cause.
Use sequence IDs, sender/receiver counts and a sustained run long enough to
expose growing backlog. Separate capture-to-send, send-to-receipt and
receipt-to-confirmation. Correlate with independent monotonic wall time; game
tick counters alone cannot establish elapsed time when callbacks stall or bunch.
Two hosts' timestamps need a measured clock relationship before subtraction.
Rendering and physical response require their own observation. Callbacks that
continue running do not exclude expensive callback work, uneven frame pacing,
or a stalled renderer. Make the next test distinguish an implementation change,
not merely collect another latency number.

## Preloader/FileIO is not an ordinary fresh file read

[Preloader documentation](https://lep.nrw/jassbot/doc/Preloader), at the pinned
revision above, reports that a successfully read path is cached for the map
load/restart (tested 2.0.3.22988). Re-executing that path can execute old contents.
The historical 1.33 bug kept data until a full game restart; the annotation
places the map-reload cache-reset fix around 1.35–1.36.1 with uncertain exact
version. Neither report establishes current 3.0 behavior. Test same-path
overwrite, fresh paths, missing and populated files separately if that choice
blocks the consumer. Do not infer populated-file cost from absent-file probes.

Preload scripts run in a restricted context, not the map's normal globals and
Blizzard.j environment. Lua maps compile Jass preload text through Jass2Lua;
syntax/translation failures are documented as capable of crashing the game.
File data may differ per player and must be treated as asynchronous/local
until explicitly synchronized before shared simulation use. Local-file registry
requirements are themselves version-dependent. A successful export does not
prove the next read is fresh, synchronized or safe at the intended rate.

Related prior art:
[hidden Jass2Lua transpiler](https://www.hiveworkshop.com/threads/blizzards-hidden-jass2lua-transpiler.337281/),
[File I/O techniques](https://www.hiveworkshop.com/threads/exploring-file-i-o-tricks-and-techniques.307710/),
[cache bug discussion](https://us.forums.blizzard.com/en/warcraft3/t/bug-preload-files-are-being-cache%E2%80%99d/29413/35).
These are implementation reports and investigation leads, not new guarantees.

## Rollback prior art does not settle Warcraft transport

The [GGPO developer guide at 7ddadef8](https://github.com/pond3r/ggpo/blob/7ddadef8546a7d99ff0b3530c6056bc8ee4b9c0a/doc/DeveloperGuide.md)
requires deterministic stepping and complete save/load of gameplay state, with
rendering separable from resimulation. Its prediction limit can stop advancement;
network servicing must keep running. Exclude cosmetic effects/audio from state
only when they do not affect simulation, and prevent replayed side effects from
being emitted twice. These are integration requirements, not a claim that
Warcraft exposes all the facilities GGPO needs.

[Slippi's emulator input implementation at 60f7b634](https://github.com/project-slippi/Ishiiruka/blob/60f7b63496fb6ec7b9180a04f16f3edc0ad89fe2/Source/Core/InputCommon/GCAdapter.cpp)
and [launcher at 0930a2b6](https://github.com/project-slippi/slippi-launcher/blob/0930a2b66bdda78cebd0444c5e56249fea516cbe/README.md)
illustrate the separation of device acquisition, game runtime and launcher.
They do not establish a Warcraft analog ingress, independent transport, snapshot
facility or latency ceiling. Inspect the actual Slippi rollback seam when that
is the decision; adapter support alone is not rollback evidence. Public prior
art permits investigation, not unlicensed source derivation.

Keep native reproductions and measurements with the consumer project, naming
map/source revision, Warcraft build, clients, workload, observed endpoints and
uncertainty. Promote a historical observation to a current claim only after the
smallest current-build reproduction decides it. For example, an ordinary asset
edit needs no transport study; seconds of delay in a new input integration does.
