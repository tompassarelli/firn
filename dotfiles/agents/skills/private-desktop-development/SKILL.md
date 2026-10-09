---
name: private-desktop-development
description: >-
  Run GPU-accelerated Linux games and graphical development tools in a private desktop beside Niri, with remote input that never grabs the normal desktop.
---

# Private desktop development

- Resolve the canonical launcher with `agents path private-desktop-development`.
- Use its sibling `scripts/private-desktop.sh`.
- Read `private-desktop.sh --help` for start/control/type/capture syntax, resolution (2560x1440), ports, render nodes, deadlines and paths.
- Provide `agents`, `bun`, `nix` and GPU render-node access.
- Keep game-specific launch commands in the game project.
- Keep rendering and input on the separate hardware-rendered Wayland desktop.
- Never switch Niri or inject input globally.
- Load `image-context-budget` before repeated captures; save originals to disk and inspect bounded text/OCR under its preview and recovery rules.
- Launch retained desktops directly or inside a native `session`.
- Keep the foreground capacity allowance until the session ends.
- Use `--seconds` only for a requested finite deadline.
- Respect an enclosing finite `run` deadline.
- Never run two clients against one mutable Wine/Proton prefix.
- Read the printed run directory and localhost port; control only that run through the launcher.
- Type with `type` from stdin, including secrets.
- Never use `control ... type` or `xdotool type`.
- Keep typing within the supported US layout.
- Use `scripts/private-desktop-type.test.sh` when changing key mapping.
- Check capture exit status before inspection.
- Require an active run, live private socket and a fresh nonempty absolute PNG.
- Respect capture's eight-second timeout and one-second termination grace.
- Treat a preserved old destination as stale.
- Interpret the application's visible state rather than treating a fresh capture as evidence of advancement.
- Resolve `grim` once for retained older sessions.
- Never realize a Nix shell per frame.
- Use lowercase VNC key names and control sequences shorter than eight seconds.
- Use keydown/keyup and mousedown/mouseup for holds.
- Use private XTEST for X11 pointer/window queries only after VNC input fails and the private window is confirmed active.
- Read [private input diagnostics](references/private-input-diagnostics.md) when capture or modifier input disagrees with the app.
- Read [private XTEST](references/private-xtest.md) when setting up fallback X11 control.
- Never use `ydotool`, the normal desktop's DISPLAY/X authority, or normal-desktop focus/window targets.
- Honor explicit current-display testing within the identified game window.
- Never substitute streaming for a requested native controller/latency trial.
- Stop with Ctrl-C or SIGTERM to the foreground wrapper; clean only its exact run directory and processes.
- Keep passwordless VNC bound to `127.0.0.1`.
- Never expose it to a network.
- Use the launcher's per-command `dbus-run-session`.
- Never inherit or recreate the normal desktop's D-Bus address.
- Keep VNC port selection serialized until listener readiness.
- Never replace the launcher lock with independent probes or startup sleeps.
- Start the application only after the requested output mode is set, using its project launcher and supported credential stores.
- Keep secrets out of arguments and logs.
- Check the startup `glxinfo -B` hardware renderer, updating private framebuffer, delivered keys/pointer, ordinary in-game action, and retained normal-desktop focus/input before reporting usability.
- Observe the actual control change before advancing.
- Never infer keyboard delivery from command success or pointer coordinates.
