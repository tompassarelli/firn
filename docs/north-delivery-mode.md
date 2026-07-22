# North delivery mode

Ordinary North and Fram commands are generation-owned. `north`, `north-mcp`,
the Claude lifecycle/status commands, and the Codex managed lifecycle adapters
resolve immutable package or `/nix/store` executables selected by the active
NixOS generation. They scrub inherited `NORTH_CHECKOUT`; ordinary launchers,
hooks, MCP adapters, services, and status surfaces cannot select a development
checkout implicitly.

Mutable execution is an explicit development surface. `north-dev` and
`north-mcp-dev` alone honor `NORTH_CHECKOUT` (defaulting to
`~/code/north`), and the `fram-*-dev` commands alone honor `FRAM_CHECKOUT`
(defaulting to `~/code/fram`). Every development command prints
`provenance=checkout` with its exact target before execution. No ordinary name
falls back to a checkout when its package command is unavailable.

North's Beagle source boundary still applies: editing a `.bclj` file does not
change generated Clojure under `~/code/north/out/`. Run the canonical
`~/code/north/build.sh` repair/build loop, then use an explicitly named
`north-dev` command to exercise that checkout. Ordinary commands change only
after Firn verifies and activates a new generation.

Claude's SessionStart/SubagentStart/PostToolUse/Stop hooks call exact
`/run/current-system/sw/bin/north-*` package wrappers. Its statusline observer
and SessionEnd concern/stream-sync paths use the same generation-owned surface.
Codex's managed manifest calls `/etc/codex/hooks/*-codex` adapters through exact
runtime interpreters; those adapters delegate to the North package installed at
`/etc/codex/hooks/north`. Beagle SessionStart performs its project-context gate
before invoking generation-owned `fram-code-status`.

The coordinator on port 7977 is systemd-owned. Its `Type=simple` service uses
the same selector to `exec` the physical `fram-daemon`, so systemd's `MainPID`
is the daemon rather than a backgrounding launcher. Promotions and rollbacks
are serialized transactions that publish one complete current/previous
generation through `~/.local/state/north/fram-runtime/active`. They do not
restart the service. Apply a selection explicitly with
`sudo systemctl restart north-coord.service`; a checkout-side `north up
--restart` must not compete with the system service. The ordinary Firn `north`
and `north-packaged` wrappers reject direct `north up` launch/restart commands
before entering North code, while preserving the read-only `north up
--check-runtime` probe.

Before systemd loads the fact log, an `ExecCondition` checks that port 7977 is
free. A pre-existing listener skips startup instead of entering a memory-heavy
restart loop; the health probe separately requires the service `MainPID` to own
the listening socket. After removing a foreign listener, explicitly run
`sudo systemctl restart north-coord.service`; a skipped condition does not poll
the port or claim it later.

On first installation, the unit runs `north-coord-runtime initialize` as a
distinct initialization transaction. Once initialized, deleting the active
selection is corruption and fails closed; status or startup never reconstructs
package mode from a missing selector.

`north-packaged`, `north-mcp-packaged`, and the `fram-*-packaged` aliases expose
the same flake-selected package boundary for explicit smoke tests. `firn rebuild`
promotes committed local North, Fram, Gaffer, and Beagle revisions only after
its build and validation gates. North's packaged input follows the root Gaffer
pin, so the verified North closure and its routing contract move together.

In short: ordinary names are immutable production surfaces, explicit `*-dev`
names are checkout surfaces with visible provenance, and `*-packaged` names are
explicit package smoke aliases. The three modes never select one another
silently.
