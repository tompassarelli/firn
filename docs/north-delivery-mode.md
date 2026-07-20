# North delivery mode

The personal NixOS profile deliberately runs North checkout-first. `north` and
`north-mcp` execute `~/code/north/bin/north` and
`~/code/north/bin/north-mcp`, matching the paths used by hooks and interactive
MCP configuration. Before either entrypoint runs, the wrapper asks
`/run/current-system/sw/bin/north-coord-runtime` to validate the selected Fram
deployment and export its exact source, commit, tree, origin, and daemon path.
The selection must be a real, detached, tracked-clean worktree at
`~/.local/state/north/fram-runtime/deployments/<commit>`; package mode is not an
implicit substitute for an ordinary checkout-first command.

North's Beagle source boundary still applies: editing a `.bclj` file does not
change the running Clojure under `~/code/north/out/`. Run the canonical
`~/code/north/build.sh` repair/build loop to regenerate `out/`; the checkout-first
wrapper then exercises that output immediately. Checkout-first removes the Nix
promotion delay, not Beagle code generation.

This is a development policy, not a claim that dirty North source is
reproducible. A missing or non-executable North checkout fails clearly; a dirty,
attached, missing, or path-substituted Fram deployment also fails closed. Set
`NORTH_CHECKOUT` only when deliberately testing another North checkout.

The coordinator on port 7977 is systemd-owned. Its `Type=simple` service uses
the same selector to `exec` the physical `fram-daemon`, so systemd's `MainPID`
is the daemon rather than a backgrounding launcher. Promotions and rollbacks
are serialized transactions that publish one complete current/previous
generation through `~/.local/state/north/fram-runtime/active`. They do not
restart the service. Apply a selection explicitly with
`sudo systemctl restart north-coord.service`; a checkout-side `north up
--restart` must not compete with the system service.

On first installation, the unit runs `north-coord-runtime initialize` as a
distinct initialization transaction. Once initialized, deleting the active
selection is corruption and fails closed; status or startup never reconstructs
package mode from a missing selector.

The flake-pinned package remains part of the system closure behind
`north-packaged` and `north-mcp-packaged`. Use those names to smoke-test what the
current `flake.lock` would deploy. `firn rebuild` promotes committed local North,
Fram, Gaffer, and Beagle revisions only after its build and validation gates.
North's packaged input follows the root Gaffer pin, so the verified North
closure and its routing contract always move together. That pinned promotion is
the reproducible path for another machine or a release.

In short: ordinary names optimize the personal workstation for live harness
development, while the `*-packaged` names expose the pinned promotion candidate
without making it an invisible fallback.
