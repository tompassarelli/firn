# Warcraft startup evidence

On 3 October 2026, the earlier two-client run recovered client A from an empty
post-login screen by keeping its signed-in Battle.net launcher and prefix,
closing the unusable game, and selecting Play in that launcher. It entered
Multiplayer and the public channel without another human login. Client B's
launcher failed to create the game process; its separate direct-launch and
Alt+Enter recovery is narrower evidence and does not replace the launcher-first
procedure. Neither observation proves the underlying authentication/menu defect
fixed.

The successful A sequence is recorded in conversation
01a0f6b6-0b0f-7942-b6ed-22e8b72fd4cf, 3 October 01:18–01:24 UTC, and
smashcraft:build/two-client-current-state.md under the 01:32 UTC checkpoint.
Use the indexed convo CLI to retrieve the exact sequence when needed.

Later that day, a primary-display controller trial directly restarted
Warcraft III.exe after a completed in-game login. This required the owner to
sign in again and returned to the same empty Options/Exit Game shell. Resizing
and Alt+Enter changed display geometry without fixing the menu. Do not encode
either action as a reliable authentication or blank-menu repair.

The running browser was initially missed because process discovery searched
only for BlizzardBrowser. Its Chromium process names were CrBrowserMain,
CrRendererMain and CrGpuMain. Inspect known runtime children and bounded safe
argument fields before diagnosing a missing browser.

Separate Steam runtime invocations also produced duplicate wineservers against
one mutable prefix. Check prefix ownership across host processes before launch;
reuse the current runtime rather than treating a fresh namespace as a new client.

Scope check: this procedure applies to a Warcraft launch or blank post-login
menu. An ordinary map leave/rejoin with a working signed-in game does not call
for a launcher restart. Display clipping alone is a geometry problem until
evidence establishes otherwise.

On 6 October 2026 the owner started the "Warcraft III (Battle.net)" Steam
shortcut on the primary display while automation client A's runtime still owned
the same prefix, creating a second wineserver. With client A then stopped, that
launcher's Play still failed twice: battle.net logged `Could not launch
C:/Program Files (x86)/Warcraft III/_retail_/x86_64/Warcraft III.exe (FAILED)`
and the pending launch expired after 15 s. After fully exiting that launcher
(tray Exit) and confirming no process remained on the prefix, starting the same
shortcut alone launched the game on the first Play. A launcher whose runtime
started against a live prefix stays unable to create the game process; restart
it as the prefix's only runtime.

Custom Games "Join game name" is case-sensitive: "Smashcraft" returned GAME NOT
FOUND for a lobby named "smashcraft"; the exact name and its password joined.
A passworded lobby never appears in another client's Custom Games list.

## Manual startup and recovery detail

Use this only where `wisp doctor` stops on an unknown state.

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
BlizzardBrowser through the owning Wine runtime's children (`CrBrowserMain`,
`CrRendererMain`, `CrGpuMain`). Keep auth values out of process/log output.

For a warm exit from a running match, use F10 → Game Menu → E (End Game) →
Q (Quit Mission), then the score screen's Back to Custom Games; Quit Mission
is distinct from Exit Game (details in fast-native-iteration.md). Native labels
can be gold; re-observe with a matching colour mask before declaring a client
unresponsive.

Private XTEST is the gameplay input path on a private desktop and the
private-desktop launcher's compositor capture the observation path. Verify the
pointer position before clicks: an absolute XTEST move may leave it unchanged
under Xwayland, while relative motion moved it in the retained native menus.
One single-player Smashcraft run tested movement, jump and attack via private
XTEST over 300 ticks with no dropped trace entries. Warcraft's VNC virtual
input remains unreliable and unresolved.

## Launcher authentication transport

Before recovery or Play, check launcher authentication transport separately
from its visible account label. A socket bound to an address no longer on the
host, repeated authentication RPC timeouts, or explicit W3 SSO-generation
failure means the launcher is unhealthy; do not launch or request another sign-in
in that state. A launcher may start Warcraft even after SSO generation fails.
Use smashcraft:tools/wc3-auth-transport when present; its source-present result
is not proof of authenticated readiness. Keep the network/VPN route stable
during retained sessions. A reconnect can reveal absent saved login tokens;
classify that challenge separately from transport failure. Use persistent login
only through the application's supported option.
