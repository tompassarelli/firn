# North delivery mode

The personal NixOS profile deliberately runs North checkout-first. `north` and
`north-mcp` execute `~/code/north/bin/north` and
`~/code/north/bin/north-mcp`, matching the paths used by hooks and interactive
MCP configuration. Shell scripts, TypeScript/Clojure source loaded directly by
the entrypoints, and regenerated outputs are therefore exercised immediately
without rebuilding NixOS.

North's Beagle source boundary still applies: editing a `.bclj` file does not
change the running Clojure under `~/code/north/out/`. Run the canonical
`~/code/north/build.sh` repair/build loop to regenerate `out/`; the checkout-first
wrapper then exercises that output immediately. Checkout-first removes the Nix
promotion delay, not Beagle code generation.

This is a development policy, not a claim that dirty source is reproducible. A
missing or non-executable checkout fails clearly; it never silently substitutes
different code. Set `NORTH_CHECKOUT` only when deliberately testing another
checkout.

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
