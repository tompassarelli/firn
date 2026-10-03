# Fast Warcraft native procedures

The repeated loop is a retained client entering a named map/test, running a
known action sequence, and producing verified state or a fresh trace. Optimize
this warm loop. Cold Battle.net startup, interactive authentication, downloads
and map compilation have different costs and must not be mixed into its ratio.

## Record only useful chains

Keep game-specific procedures in the consuming repository, such as
wc3-melee:tools/wc3-procedure and wc3-melee:tools/wc3-procedures/ records. The
generic private-desktop skill continues to own private display/capture transport.

A record needs the named action, starting screen/phase, desired ending
screen/phase, exact ordered input commands, necessary waits, supported geometry
and Warcraft build, and an observed end-state artifact. Mark a chain candidate
until it actually reaches that ending state. A process, focused window or
successful input-tool exit is not that proof. State-specific clicks may use
known coordinates for one layout; re-identify the layout after a resolution or
interface change. Never guess a long chain from an unverified starting screen.

Useful procedure boundaries include launcher Play → real main menu, main menu →
map chooser/lobby, lobby → loaded selection, selection → combat, combat →
results/rematch, and diagnostic state → complete fresh trace export. Split at
asynchronous loading or authentication, not at every predictable key/click.
Do not enter or record credentials in procedure files.

## Execute without unnecessary round trips

Resolve the existing private run directory and tools once. Check its live
private socket and window before input; pass its display/Xauthority explicitly.
Use one XTEST command for each bounded chain. The launcher supports multiple
ordered input actions, so a short sequence does not require one tool call per
action. Use VNC for capture only in Warcraft. Keep guaranteed releases in the
runner when a chain owns held keys.

Capture or read an existing native trace once at a meaningful end boundary.
Use cropped text/OCR or trace fields, not full-screen decorative-background OCR.
Require a fresh completed artifact. When the expected result is absent, stop
that procedure and examine the first unproven boundary. Do not issue the same
optimistic chain repeatedly against a changed state.

Retain both signed-in clients and their private desktops between map iterations.
Keep the currently proven recipe and actual live state in the project handoff.
An expired estimate does not justify restarting a working client.

## Measure the claim

For an equivalent start/end procedure, retain before/after elapsed times,
successful completion, game build/map, client/display and relevant load. Separate
input submission, loading and verified result time when the distinction changes
the optimization. Report sample count and individual observations; a scripted
input-call fixture measures command overhead, not successful Warcraft navigation.

The requested 5–10× speedup is a target for the named warm loop. Use measured
ratios only for equivalent completed loops. If menu control or loading remains
the dominant blocker, report it and repair that boundary rather than claiming
that fewer tool calls made the whole development loop 10× faster.
