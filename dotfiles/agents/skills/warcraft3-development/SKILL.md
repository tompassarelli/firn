---
name: warcraft3-development
description: >-
  Develop and test Warcraft III maps in the native game, including Battle.net
  startup, Steam Proton on Linux, post-login recovery, controller trials and
  multiplayer test sessions, API quirks, input transport and netcode diagnosis.
  Applies on primary and private displays. Boundary: native game runtime and
  testing only; TypeScript or Wurst authoring belongs to the source-language skills.
---

# Warcraft III development

This skill owns Warcraft-specific runtime setup, recovery and native testing.
Keep the project's map build, installed candidate and intended Warcraft version
aligned. Use `warcraft-modding` when authoring
TypeScript and `wurst-development` when authoring Wurst; this skill
does not choose or migrate the map's source language.

## Select the test display

Default Warcraft development and testing to an off-monitor subsession. An
explicit off-monitor request also selects that path. Use
[private desktop development](../private-desktop-development/SKILL.md) for the
private GPU desktop, display environment, capture and input transport. Read that
skill before creating or controlling a private desktop. Keep Warcraft launch,
authentication and map iteration decisions here; the desktop skill is generic.

Use the current monitor when the owner's request or immediate testing needs
clearly call for it, such as a hands-on controller trial they need to see and
play. Do not require special wording or another confirmation when that intent
is clear. Use the native Warcraft window there and confine input to that window.
A streamed private desktop adds another input/display path and is not equivalent
for this trial. Use `image-context-budget` for repeated inspection.

## Startup and post-login recovery

Read this sequence before launching or recovering Warcraft, including controller
trials. Recover the current process, prefix, display and signed-in launcher from
the project handoff before taking action.

When the project uses Wisp, run `wisp doctor [CLIENT...]` (wisp:docs/doctor.md)
first instead of the manual recoveries below: it starts Battle.net alone on a
free prefix, presses Play in the signed-in launcher, ends a second runtime, a
crashed game and its error dialog, a disconnected game or the empty
Options/Exit Game shell and relaunches with Play, leaves stale lobbies, and
restarts a launcher whose connection failed. It never signs in; it stops with
one plain line when the owner must. Follow the steps below by hand only where
doctor stops on an unknown state.

1. Reuse a working game. For a cold start, first establish that no Wine/Proton
   client uses the selected mutable prefix. Use the existing Steam Linux Runtime
   and installed GE-Proton to start **Battle.net Launcher.exe** in that prefix
   on the intended display. Separate Steam runtime namespaces can create two
   independent wineservers against one prefix; their isolation does not make
   this safe. Never start another runtime against a live prefix.
2. Use **Play in the already-signed-in Battle.net launcher** to start Warcraft.
   A direct `Warcraft III.exe -launch -uid w3` invocation is not equivalent to
   this observed successful path. Do not replace Play with direct execution or
   assume an in-game login will survive restarting the executable.
3. Verify the real main menu, enter Custom Games and load the intended map.
   Verify one actual gameplay action before announcing controller readiness.
   A login form, Options/Exit Game shell, mapper profile or game process is not
   a successful launch. Keep the launcher and signed-in game available.

If login closes to an empty Options/Exit Game shell, treat it as the known
post-login failure, not a request for another sign-in. Inspect the retained
launcher and the exact previously successful sequence before changing state.
The observed recovery relaunched an unusable game with the retained launcher's
Play button; it did not establish that any restart preserves authentication.
Do not discard another completed login to retry direct execution. If a current
session has a no-restart constraint, prepare the launcher path without closing
the game; resolve that constraint before applying a relaunch.

Alt+Enter can repair clipped/windowed rendering, but is not an established fix
for missing menu contents. One failed toggle closes that hypothesis. Inspect
BlizzardBrowser through the owning Wine runtime's children: Linux process names
can be `CrBrowserMain`, `CrRendererMain` and `CrGpuMain`, so absence of the literal
name `BlizzardBrowser` does not establish browser startup failure. Keep auth
values out of process/log output. Preserve the distinction between observed
recovery and an unresolved underlying defect.

Observed evidence and the failed alternative are retained in
[nixos-config:Warcraft startup evidence](references/warcraft-startup.md).

Keep signed-in Warcraft clients and their private desktops open through normal
map leave/rejoin iterations. Leave the map, return to the lobby, and rejoin with
the existing clients. Restart only an actually unusable or terminated client,
or when the owner explicitly asks to stop it. A test iteration or elapsed time
alone is not a reason to discard a working signed-in session.

For a warm exit from a running match, use **F10 → observe Game Menu → E
(End Game) → observe submenu → Q (Quit Mission)**, then observe the score
screen and choose Back to return to Custom Games. Quit Mission is distinct
from Exit Game. This path retained the signed-in process in the native trial.
Do not restart because OCR did not recognize a menu: native labels can be gold,
and white-only extraction can miss them. Re-observe with the matching color
mask/full-screen OCR and verify the actual state before declaring unresponsiveness.

For Warcraft, use private XTEST for gameplay input and the private-desktop
launcher's native compositor capture for observation. Verify actual pointer
position before clicks; an absolute XTEST move may leave it unchanged under
Xwayland. Relative XTEST motion moved the pointer in the retained native menus;
check the resulting position and screen rather than inferring delivery.
One observed single-player Smashcraft run tested movement, jump, and attack via
private XTEST over 300 ticks (about five seconds), with no dropped trace entries;
the capture showed the Archer attack state and CPU interaction. Warcraft's VNC virtual
input remains unreliable and unresolved. This does not prove multiplayer,
performance, or audio behavior, and does not establish a VNC fix or root cause.

## Avoid repeated authentication

Before recovery or Play, check launcher authentication transport separately from
its visible account label. A socket bound to an address no longer on the host,
repeated authentication RPC timeouts, or explicit W3 SSO-generation failure
means the launcher is unhealthy. Do not launch or request another game sign-in
in that state. A launcher may start Warcraft even after SSO generation fails.
Use the project
smashcraft:tools/wc3-auth-transport check when present; its source-present result
is not proof of authenticated readiness. Keep the network/VPN route stable during retained sessions; observe address and
connection changes rather than estimating token lifetime. Require distinct
accounts for concurrent online clients and one runtime per mutable prefix.

Preserve account stores and working games. Re-establish the broken connection
through the supported launcher path, then check actual authentication and game
access. A reconnect can reveal absent saved login tokens; classify that actual
challenge separately from transport failure. Do not promise silent recovery.
Use persistent login only through the application's supported option; never
store or script passwords. Notify the owner by the requested email channel only
when an actual interactive challenge remains after transport recovery, and
only when an authenticated sending route is available. Report an unavailable
mail route explicitly; do not claim a notification was sent.

## Fast native iteration

When the map's code is TypeScript with Wisp, change running code
with its hot reload instead of rebuilding and rejoining. Its in-game error
report gives the TypeScript line. Rejoin only when the map file must change
(see `warcraft-modding`).

Prefer event-driven automation with real state detection. Advance on observed
window/focus, control availability and resulting game state; elapsed time is
not readiness. Use native callbacks, UI state or trace events where available,
then fresh bounded OCR observation when those signals are unavailable. Timers
bound waits. Fixed delays are an explicitly labeled fallback for a boundary
without a usable signal, never the first approach.

Use recorded, state-specific input procedures for repeated menu and map work.
Recover the current session once, identify the starting screen, then batch the
known inputs in one private XTEST invocation. Check the meaningful ending screen
or fresh map trace rather than taking a screenshot and reasoning after every
click. Keep authentication and loading transitions as separate boundaries.
Stop a chain on an unexpected result; repair or re-identify that boundary
instead of replaying guessed clicks. Never promote a candidate chain as verified
without the actual native ending state.

Record successful chains with their start/end states, Warcraft build, display
geometry, ordered inputs, required waits, elapsed time and verification artifact
in the project. Reuse them across warm leave/rejoin, rematch and probe-export
iterations without restarting signed-in clients. Resolve tool paths once per
session; keep transient PIDs, coordinates and session directories out of this
skill. Use the project's procedure runner when present.

Measure the same warm procedure before and after; report cold launcher/login,
loading, build and test time separately. The owner's target is 5–10× faster
iteration, not permission to remove checks or a claim already achieved. See
[fast procedure guidance](references/fast-native-iteration.md) when recording,
executing or measuring a chain.

## Warcraft API gotchas and prior art

Before designing or diagnosing input, commands, netcode, rollback or FileIO,
resolve the relevant Warcraft-specific semantics from pinned API documentation,
existing map code and a distinct viable prior-art approach. Compare native
player-issued unit/order, ability and shop-event proxies alongside synchronized
key events, local polling and `BlzSendSyncData`; the first chosen API is not the
whole design space. Use `prior-art` for the decision and read
[nixos-config:Warcraft API evidence](references/api-gotchas.md) for the relevant
API family. Ordinary asset, balance or copy edits do not trigger this research.
Stop when the evidence selects the next implementation or discriminating test.

Distinguish player/engine-issued commands from map-script `Issue*Order` calls;
local script orders are not an assumed synchronization channel. Event arrival
alone does not preserve the original press/release, capture frame or analog
value. Local capture, transport receipt, simulation confirmation, rendering and
physical button-to-pixel timing are different quantities. Continuing game
callbacks prove neither cheap callbacks nor smooth rendering or wall-clock
cadence. To answer an owner's input-timing question, measure end to end in one
aggregate run on the current release, as defined by the project's input-integrity
issue. Instrument individual stages only to debug a failure of that run.

When a native baseline works but integration has abnormal latency, investigate
the integration and harness first. Compare the same bytes, message rate, player
count, game phase, prefix and receiver path, with sustained load and independent
wall-clock correlation. Do not diagnose an engine quota, garbage collection,
OS input or menu interference without evidence that discriminates that cause.
Keep the minimal reproduction, exact source revision and Warcraft build with
observations; label documentation claims, historical measurements and hypotheses
separately. A missing-file preload test says nothing conclusive about populated
read cost; one API's result does not establish another's behavior.

## Controller and multiplayer evidence

For a keyboard mapper trial, load the project's matching key preset and enable
mapping only while Warcraft is focused. Verify movement, jump and attack in the
loaded map before announcing readiness. Device recognition and profile parsing
alone do not prove gameplay. Report digital mapping separately from continuous
analog input, trigger pressure and hardware latency.

Native multiplayer acceptance needs actual clients joining and playing the same
candidate. Synthetic host tests, local gameplay and a successful launcher do not
establish online responsiveness, fairness or controller feel. Preserve signed-in
clients across map leave/rejoin cycles and record the current live state in the
project handoff rather than hard-coding transient process IDs into this skill.

## Authorized account login

The owner authorized username/password entry for both test accounts. Encrypted
pairs live in nixos-config:secrets/bnet.yaml (a and b, in source-file order; c is the third account added 6 Oct 2026 for the new test client prefix ~/.local/share/wc3-melee/client-a).
Use the machine SOPS key through sudo; never print decrypted values, put them
in tool arguments, clipboard, traces or screenshots, or write plaintext files.
The helper nixos-config:dotfiles/bin/wc3-login-field reads a selected field into
a pipe and types it into the active private Battle.net/Warcraft window.

First verify a real login form and the focused target field, using text/OCR
without retaining account text. Use separate account/prefix bindings for A/B.
Run the helper with the exact private run, account a|b|c, and username|password
inside a shell providing jq, xdotool and sops. Deliver username, Tab into the
verified password field, deliver password, then submit through the observed
login control. Enable supported persistent login and verify actual launcher
online state and W3 SSO before Play. Window focus alone is not a login-form
check. A helper exit is not authenticated success.

Handle ordinary credential prompts autonomously; do not ask the owner to type
these stored credentials. Authenticator, CAPTCHA, account lock or unsupported
interactive challenge is a separate blocker. Notify by email only through an
available authenticated mail route; report unavailable delivery honestly.

## Wurst authoring and UI workflow

Use [Wurst development](../wurst-development/SKILL.md) for source,
object data, UI components and focused headless checks. Keep the map project
AGENTS.md current with its source layout, pinned toolchain and actual commands.
Prefer headless layout/type checks before native iteration; use this skill for
click/focus, presentation, authentication and multiplayer proof. An upstream
Grill feature or macOS toolchain claim is not a verified capability of this map.

## Failure modes to avoid

Symptom, cause, rule. Smashcraft, 6 Oct 2026.

- Green HUD, invisible stage, "menus could not load": `-loadfile` raced the
  post-login ladder-map scan. Host via the menu socket after the scan; treat any
  "model creation failed - war3mapImported" as a failed load.
- Private test client renders at the wrong aspect, pointer clamps, frame checks
  miss: main-display play sharing its prefix rewrote War3Preferences (window
  mode, size, resolution, fps, refresh) on exit. One prefix per display role, or
  save/restore War3Preferences around main-display play and have doctor verify
  each client's display settings.
- Missing log line read as a state (no LoginDoorClose): War3Log is written in
  bursts. The menu socket outranks the log for sign-in and menus; the log is
  evidence only for what it contains.
- Grey sky for seconds in the first match after a cold start: models draw late.
  Preload stage/scene models before match frames; take evidence frames only
  after a receipt says the scene is drawn.
- Missed clicks, wrong pointer targets, slow OCR: XTEST clicks shorter than one
  frame are missed by per-frame-sampled UI, targets depend on render area. Drive
  with in-map commands and receipts plus the menu socket; pixels are evidence only.
- Hours lost on a native experiment: launch path and display changed together.
  One variable per run; route to `debugging`.
- Receipt wait times out on a fresh game: it rewrote an identical receipt file.
  Wait on a counter or timestamp, never text equality.
