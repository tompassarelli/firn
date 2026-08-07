# North delivery mode

North is delivered on two channels. Its **application code** is the fast
channel: `north` and `north-mcp` execute `$NORTH_CHECKOUT` (default
`~/code/north/main`), so a fix is live when it is written. Their **runtime** is
the slow channel — engine root, Fram classpath, and every tool selector come
from the generation-pinned `north-env`, never from the checkout — and the
wrapper exports `NORTH_PACKAGE_MODE=checkout` plus a `git describe --dirty`
`NORTH_PACKAGE_REV` so `north doctor` shows exactly what ran. `north-packaged`
and `north-mcp-packaged` are the escape hatch: the exact flake package, with
inherited `NORTH_CHECKOUT` scrubbed.

Fram commands and every North lifecycle surface stay generation-owned. The
Claude lifecycle/status commands (`north-on-spawn`, `north-on-tooluse`,
`north-on-stop`, `north-mark-delegated`, `north-session-end`,
`north-stream-sync`, `concern`) and the Codex managed lifecycle adapters
resolve immutable package or `/nix/store` executables selected by the active
NixOS generation and scrub inherited `NORTH_CHECKOUT`. A hook fires inside
another agent's turn, where a half-saved checkout is an outage rather than a
fast loop.

`~/.local/bin` is itself a generation-owned link to the store-backed
`dotfiles/bin` tree. The `claude`, `codex`, and `safe-push` launchers therefore
change only with an activated Firn generation; live PATH never follows edits in
the canonical checkout. The packaged `safe-push` exposes explicit `--to`
destinations so a scanned commit cannot be published through an ambient branch
mapping.

Each retained system/Home Manager generation keeps its own launcher tree. A
boot-menu or manual generation selection therefore restores that generation's
exact `~/.local/bin` target without consulting the working checkout; there is
no `firn rollback` command.

Fram's mutable execution remains an explicit development surface: the
`fram-*-dev` commands alone honor `FRAM_CHECKOUT` (defaulting to
`~/code/fram/main`) and print `provenance=checkout` with their exact target.
`north-dev` and `north-mcp-dev` survive as the selector-mediated path — they
route through `north-coord-runtime exec-checkout`, which refuses while the Fram
runtime is package mode. Ordinary `north`/`north-mcp` deliberately do NOT use
that path; coupling North's channel to Fram's is what the split removes. No
name silently falls back across channels: a missing checkout executable makes
`north` exit 127 naming `north-packaged`, and `north-packaged` never reads a
checkout.

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
the same selector to `exec` the physical `fram-server`, so systemd's `MainPID`
is the server rather than a backgrounding launcher. Promotions and runtime
rollbacks are serialized transactions that publish one complete
current/previous generation through
`~/.local/state/north/fram-runtime/active`. They do not restart the service.
An ordinary service restart validates and preserves that sealed selection; it
never silently resets an explicitly promoted development runtime. Apply a
selection explicitly with
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

Before startup, the unit runs `north-coord-runtime ensure-default`. On a
pristine first installation it seals the generation's package as the default;
afterward it validates and preserves the selected runtime. An explicit
`north-coord-runtime package` resets the selection to package mode. Deleting or
corrupting initialized active state fails closed; startup never reconstructs a
missing selector.

`north-packaged`, `north-mcp-packaged`, and the `fram-*-packaged` aliases expose
the same flake-selected package boundary for explicit smoke tests. A Firn
rebuild makes verified package revisions available but does not overwrite an
explicit coordinator development selection; adopt the new Fram package with
`north-coord-runtime package`. North's packaged input follows the root Orchestration
pin, so the verified North closure and its routing contract move together.

In short: ordinary names are immutable production surfaces, explicit `*-dev`
names are checkout surfaces with visible provenance, and `*-packaged` names are
explicit package smoke aliases. The three modes never select one another
silently.
