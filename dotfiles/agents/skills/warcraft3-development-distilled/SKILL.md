---
name: warcraft3-development-distilled
description: >-
  Develop and test Warcraft III maps in the native game, including Battle.net
  startup, Steam Proton on Linux, post-login recovery, controller trials and
  multiplayer test sessions. Applies on primary and private displays; use the
  source-language skill separately for Wurst, Lua or Jass authoring.
---

# Warcraft III development

This skill owns Warcraft-specific runtime setup, recovery and native testing.
Keep the project's map build, installed candidate and intended Warcraft version
aligned. Use `wurst-development-distilled` when authoring Wurst; this skill does
not choose or migrate the map's source language.

## Select the test display

Default Warcraft development and testing to an off-monitor subsession. An
explicit off-monitor request also selects that path. Use
[private desktop development](../private-desktop-development-distilled/SKILL.md) for the
private GPU desktop, display environment, capture and input transport. Read that
skill before creating or controlling a private desktop. Keep Warcraft launch,
authentication and map iteration decisions here; the desktop skill is generic.

Use the current monitor when the owner's request or immediate testing needs
clearly call for it, such as a hands-on controller trial they need to see and
play. Do not require special wording or another confirmation when that intent
is clear. Use the native Warcraft window there and confine input to that window.
A streamed private desktop adds another input/display path and is not equivalent
for this trial. Use `image-context-budget-distilled` for repeated inspection.

## Startup and post-login recovery

Read this sequence before launching or recovering Warcraft, including controller
trials. Recover the current process, prefix, display and signed-in launcher from
the project handoff before taking action.

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

For Warcraft, use private XTEST for gameplay input and VNC for capture only.
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
wc3-melee:tools/wc3-auth-transport check when present; its source-present result
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
pairs live in nixos-config:secrets/bnet.yaml (a and b, in source-file order).
Use the machine SOPS key through sudo; never print decrypted values, put them
in tool arguments, clipboard, traces or screenshots, or write plaintext files.
The helper nixos-config:dotfiles/bin/wc3-login-field reads a selected field into
a pipe and types it into the active private Battle.net/Warcraft window.

First verify a real login form and the focused target field, using text/OCR
without retaining account text. Use separate account/prefix bindings for A/B.
Run the helper with the exact private run, account a|b, and username|password
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

Use [Wurst development](../wurst-development-distilled/SKILL.md) for source,
object data, UI components and focused headless checks. Keep the map project
AGENTS.md current with its source layout, pinned toolchain and actual commands.
Prefer headless layout/type checks before native iteration; use this skill for
click/focus, presentation, authentication and multiplayer proof. An upstream
Grill feature or macOS toolchain claim is not a verified capability of this map.
