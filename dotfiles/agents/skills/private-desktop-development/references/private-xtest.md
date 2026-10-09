# Private XTEST

- Set `run_dir` to the launcher's printed run path.
- Read `DISPLAY` from that run's `display` and `XAUTHORITY` from its `xauthority`.
- Require a nonempty display and a live private Wayland socket.
- Pass the run's authority explicitly even when empty; never inherit the normal desktop's authority.
- Use `xdotool` only for private pointer/window queries after confirming the private window is active.

```bash
private_display=$(<"$run_dir/display")
private_xauthority=$(<"$run_dir/xauthority")
test -n "$private_display" && test -S "$run_dir/runtime/wayland-0"
nix shell nixpkgs#xdotool --command env DISPLAY="$private_display" \
  XAUTHORITY="$private_xauthority" xdotool mousemove 640 360 click 1
```
