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
[off-monitor development](../off-monitor-development-distilled/SKILL.md) for the
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
