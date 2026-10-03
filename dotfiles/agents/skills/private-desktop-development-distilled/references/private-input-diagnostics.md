# Private capture and modifier delivery investigation

Status: unresolved input defect; no runtime repair claimed. Recorded 2026-10-03.

## Distinguish the boundaries

A successful VNC command and an X pointer coordinate do not establish that a
Wine control consumed a shortcut. Compare the actual control before and after
one harmless synthetic input, then clear it and verify the empty state. Keep
credentials and authentication submission out of this probe. Capture through
the private compositor when diagnosing whether a VNC frame is stale; disagreement
is evidence to investigate, not grounds for another login attempt.

The observed login field accepted VNC letters, but VNC Ctrl+A followed by
BackSpace did not restore its empty placeholder. A held-Control comparison
also failed. Private XTEST Ctrl+A/BackSpace restored the placeholder. XTEST is
an independently observed working delivery path in this case; it does not
repair the VNC defect or prove that authentication succeeds.

## Measured event difference

An isolated X11 event window on the same private display received:

| Event | VNC state mask | XTEST state mask |
| --- | --- | --- |
| Control_L press | 0x4 | 0x0 |
| A press with Control held | 0x4 | 0x4 |
| Control_L release | 0x0 | 0x4 |

The VNC modifier event state already reflects the modifier transition; XTEST
reports the preceding state. This is a concrete event difference, not yet proof
that it alone causes Wine's shortcut failure. Fixed waits are not a repair.

The running server was wayvnc 0.10.0. In wayvnc:src/keyboard.c,
`keyboard_feed` and `keyboard_feed_code` call `keyboard_apply_mods` before
`send_key`; `keyboard_apply_mods` emits the virtual keyboard modifier request.
That source order matches the measured modifier-before-key behavior. The next
owning test is whether corrected modifier/key ordering preserves ordinary and
symbol-level input and fixes the same Wine field. It requires a separately
owned upstream repair; do not modify a running Python environment or claim a
launcher workaround closes it.

Source inspected: wayvnc 0.10.0, Nix source
`/nix/store/f59wf3r1khlx525wk0qcgq6vlhzs02i2-source`; ISC license in
wayvnc:COPYING. No source implementation was copied.

## Capture evidence and limits

Earlier captures were reported nearly black while native captures showed the
application. Six subsequent A captures and one B capture were nonblack without
restarting either compositor or VNC server. Paired captures showed matching
application geometry and content; small pixel differences remain from cursor
and separate capture times. The earlier black-frame failure did not reproduce
in this investigation and is not resolved by those successes.

The installed vncdotool 1.4.2 client already waits through empty rectangle
updates. Its cursor rectangle handling still counts a cursor pseudo-rectangle
as a rectangle. This is a candidate early-completion path, not an established
cause of the reported black frames. A decisive reproduction must record update
ordering and distinguish framebuffer pixels from cursor/size announcements.

Local evidence (ephemeral; no account text in event trace):
`/tmp/private-input-probe.log`, `/tmp/capture-worker-vnc.png`,
`/tmp/capture-worker-native.png`, `/tmp/capture-worker-b-vnc.png`,
`/tmp/capture-worker-b-native.png`, `/tmp/capture-worker-final-clear.png`.
Screenshots may contain account UI; keep them private and never publish them.
The synthetic field was cleared, the probe process closed, and the login window
restored. No login was submitted and no live client was restarted.

## Canonical native capture (2026-10-04)

The canonical launcher now reads the exact private compositor with `grim`;
VNC remains a separate input channel. A reported VNC frame missed the current
Warcraft main menu while direct native capture exposed Single Player,
Multiplayer and Options. The owning generic correction is to make framebuffer
inspection independent of the VNC client's update-completion behavior. This
changes the capture path; it does not establish or repair the upstream VNC
failure's cause, which remains unresolved above.

The updated launcher captured three frames from each of two retained private
sessions, without sending input or restarting either client. All six PNGs were
2560x1440 and nonempty. Normalized pixel means ranged from 0.103115 to 0.124235;
standard deviations ranged from 0.105996 to 0.126528. Capture-command wall times
were 1.533, 1.496, 1.497 seconds for A and 1.952, 1.955, 1.944 seconds for B.
These samples establish the observed native path and cost on those sessions,
not a general latency guarantee or proof of every application state. Private
local evidence: `/tmp/native-capture-20261004/`; do not publish the screenshots.

The shell fixture exercises exact private display/runtime selection and removal
of inherited `WAYLAND_SOCKET`, fresh success, partial and empty failures, and
inactive-session rejection. Success atomically replaces the destination;
failure keeps its previous bytes and returns nonzero. Always gate inspection
on command success, or an old destination can still be mistaken for new proof.
The command timeout limits an unresponsive capture; it does not make a frame
proof of application readiness. Application-state names and readiness decisions
belong to the application's own workflow.
