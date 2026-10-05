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
