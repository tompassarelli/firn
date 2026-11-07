# Landing

`safe-push --to main` queues a lane on the lander (`north-land@nixos-config`, the unit for this repository, whose remote is github.com/tompassarelli/firn). The lander picks every queued lane onto main as one candidate, runs the seconds-long scans, and pushes. Landing takes seconds.

`.safe-push` sets `land.check-local`, `land.inferred = false` and no `land.check` line, so nothing slow runs before the push. Each `land.after` line (owners, tools/firn cargo test, native, drift, dotfiles and `nix flake check`) runs once per landed batch on main under one `landing.capacity` lease. A red run bisects the batch and reverts only its culprit lane.

To add a check, add a `land.after` line with the paths it covers; a `land.check` line is for a check that finishes in seconds and cannot be undone after the push.

After a landing, `firn-host-follow` on the laptop pins the overlay to the new main through a landed overlay lane, deploys each remote host and rebuilds the laptop, and alarms the proxy about a host that failed.
