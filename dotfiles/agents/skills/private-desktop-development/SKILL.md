---
name: private-desktop-development
description: >-
  Run GPU-accelerated Linux games and graphical development tools in a private desktop beside Niri, with remote input that never grabs the normal desktop.
---

# Private desktop development

Use this when an application must keep rendering or receiving input while the
owner uses the normal desktop. It starts a separate headless Wayland compositor
with hardware rendering and a loopback-only VNC control channel. Niri remains
the everyday desktop; do not switch desktops or inject input globally.

Before repeated captures, load `image-context-budget`. Capture to
disk and inspect with bounded text/OCR by default; keep recordings and screenshot
sequences out of conversation history. Follow its cumulative preview budget and
text-only recovery rule after a payload-size failure.

## Start the private desktop

Use the canonical launcher at `scripts/private-desktop.sh` from this skill.
It needs `agents`, `bun`, `nix`, and access to the configured GPU render node.
Run it from any project; keep game-specific commands in that project's own
launcher or shell.

```bash
skill_file=$(agents path private-desktop-development)
skill_dir=$(dirname "$skill_file")
"$skill_dir/scripts/private-desktop.sh" start --resolution 2560x1440 \
  -- COMMAND ARG...
```

The command after `--` runs with only the private display environment. Its exit
ends the session. Without a command, the launcher stays open until explicitly
stopped or Ctrl-C. There is no default wall-clock deadline. Add `--seconds 3600`
only when a finite deadline is wanted. Each run gets a private runtime directory, unique Wayland
socket, and an available localhost VNC port. The launcher uses labwc with
wlroots GLES rendering on the selected DRM render node and contains the session
in the shared machine-capacity helper's foreground `session` mode, keeping its
resource allowance for the entire live session. VNC tools reuse one Python
environment under `${XDG_CACHE_HOME:-~/.cache}/private-desktop`, keyed to the
Python interpreter. Parallel starts wait for its installation; each runtime
directory holds only a link to it, so stopping desktops does not retain a new
53 MiB dependency copy in runtime tmpfs. Launch directly or inside a
helper `session`; an enclosing finite `run` scope still imposes its deadline.
Do not run two clients against one
mutable Wine/Proton prefix.

Read the printed run directory and port. Control it only through the launcher:

```bash
"$skill_dir/scripts/private-desktop.sh" capture RUN_DIR /absolute/path/frame.png
"$skill_dir/scripts/private-desktop.sh" control RUN_DIR move 640 360 key enter
"$skill_dir/scripts/private-desktop.sh" control RUN_DIR keydown shift pause 0.2 keyup shift
"$skill_dir/scripts/private-desktop.sh" control RUN_DIR mousedown 1 pause 0.2 mouseup 1
```

Capture reads the compositor framebuffer directly through `grim` using the exact
run's saved Wayland display and private runtime directory. VNC remains the input
channel. Capture needs an active run and a live private socket; it has an
eight-second timeout with a one-second forced-termination grace, and atomically
replaces the requested absolute PNG only after successful nonempty output.
Check its exit status before OCR or pixel inspection: failure preserves an older
destination, which is not fresh evidence. A fresh frame proves capture, not that
the application advanced; interpret its visible state in the owning project.

Startup resolves `grim` once and records its executable in the run. For a
retained session started before that declaration, put `grim` on PATH once for
the whole capture loop (for example, enter `nix shell nixpkgs#grim`). Do not
realize a Nix shell for every frame. Capture never sends input or restarts a
client. Keep original images on disk and report bounded text or measurements.

`vncdo` actions are case-sensitive; use lowercase key names such as `f10`.
Keep each control sequence shorter than the command's eight-second bound.
`mousedown`/`mouseup` and `keydown`/`keyup` allow held inputs. Use VNC input
when the application handles its key and pointer events correctly. For an X11
app whose VNC input path fails, private-display XTEST through `xdotool` is
supported after confirming its window is active on that private display.

The launcher writes its private X display and X authority value to files in the
exact run directory. Set `run_dir` to the printed Run path and read both values
from that run. Require the display to be nonempty and the private socket to be
live. The authority value can be empty for this private Xwayland server; pass
that empty value explicitly so the normal desktop's authority is not inherited.
For example:

```bash
private_display=$(<"$run_dir/display")
private_xauthority=$(<"$run_dir/xauthority")
test -n "$private_display" && test -S "$run_dir/runtime/wayland-0"
nix shell nixpkgs#xdotool --command env DISPLAY="$private_display" \
  XAUTHORITY="$private_xauthority" xdotool mousemove 640 360 click 1
```

Never use `ydotool`, or run `xdotool` with the normal desktop's `DISPLAY` or
X authority. Do not change normal-desktop focus or target windows on it.
A user request that clearly calls for hands-on testing on the current display
overrides this private-display default: confine control to the identified game
window. Do not require another confirmation when that intent is clear. Do not
substitute a streamed desktop for a requested native controller/latency trial.

To stop, send Ctrl-C to the foreground launcher (or SIGTERM to its wrapper).
An explicit `--seconds` deadline also ends the session. Use
only its exact run directory and processes for cleanup; never kill the user's
desktop or another session. Logs and captures remain in the printed runtime
directory until logout. VNC binds to `127.0.0.1` with no password, so do not
change that address to expose it to a network.

## Session bus and concurrent startup

The canonical launcher gives each client command its own live session bus with
`dbus-run-session`. Do not inherit or manually recreate the normal desktop's
D-Bus address. A stale inherited address can make Steam's container fail before
launching the app, even while the private compositor and VNC are healthy. Keep
this at the generic private-desktop boundary, separate from Warcraft login.

Parallel starts serialize VNC port selection until the selected listener has
bound its port. A free-port probe alone does not reserve a port. The launcher
checks listener readiness and releases its startup lock before client work.
Do not choose ports independently and rely on a startup sleep to avoid collision.

Observed repair: two simultaneous Warcraft desktop starts obtained distinct
ports and both passed the previous stale-D-Bus container failure. This establishes
startup transport, not game authentication, input delivery or capture fidelity.

## Add a graphical application

Start applications only after the launcher has set the requested output mode.
Use the normal project launcher and environment for the target application;
put reusable project-specific flags or prefix selection in that project, not
in this generic launcher. Existing account state and credentials stay in their
application's supported stores. Do not expose secrets in process arguments or
logs.

## Verify the path

Check the startup `glxinfo -B` log for the hardware renderer. Use the capture
command to confirm the private framebuffer updates. Before declaring a game
usable, verify that key and pointer events arrive in the private app, the app
responds to an ordinary in-game action, and the normal desktop retains focus
and input. Report what you observed; do not infer game support from compositor
startup or a launcher screen.

If capture disagrees with the native compositor or Wine ignores modifier chords,
read [nixos-config:private input diagnostics](references/private-input-diagnostics.md).
Verify the actual control changed before advancing; a successful command or
pointer coordinate alone does not establish keyboard delivery.
