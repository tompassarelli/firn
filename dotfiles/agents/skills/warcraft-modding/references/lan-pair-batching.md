# Running native checks across LAN pairs

When independent native checks or maps are ready, run them concurrently on
distinct supported offline LAN pairs. Assign each lane an explicit pair ID
and one owner, an immutable candidate map, and private output paths. Use
`bun wisp lan pool --pair K --pool-profile visual` for the assigned
pair, `bun wisp pad SCRIPT|DIR... --helper H --out PRIVATE_OUTPUT
--map IMMUTABLE_MAP.w3x --pair K` for its batch, or
`bun wisp accept --map IMMUTABLE_MAP.w3x --only ID... --pair K` for its declared acceptance checks.
`--map` uses the already-built candidate without rebuilding it; every
selected check must use the same build profile. Give each revision its own
private path; the same candidate is passed to every selected pair.
Do not let simultaneous acceptance runs rebuild the same mutable map path;
prepare their immutable candidates or use independent lane-owned fixtures.

Serialize operations on the same pair or shared mutable fixture. A measured
capacity or timing constraint may limit concurrent pairs for that workload;
name the measurement and affected interval. Do not create a global single
native-owner queue or infer a bottleneck merely because only one pair is
active. Admit additional clients through machine-capacity, preserve desktop
responsiveness, and investigate measured client/host cost before permanently
shrinking the pool. Pair ownership, signed-in-client restrictions, Tom's :0
boundary and offline-only invasive tooling continue to apply independently.

A timed ten-client batch coordinates its ten clients as one shared measurement
workload, with a fixed candidate, workload and measurement interval. It does
not combine the queues of independent visual/gameplay lanes. Run those lanes
on separate assigned pairs unless they share that fixture or a measured timing
or capacity constraint requires a scoped pause.

- Batch compatible checks within each pair. One fresh map or session covers
  their boxes and its outputs feed their checkers. Independent maps and checks
  use other assigned pairs concurrently.
- Declare each native box as data next to the issue it closes (map profile,
  setup chat commands, captures, pass rule) and run the batch with
  `wisp accept [--only ID...] [--pair K]` (wisp:docs/accept.md; Smashcraft checks in
  smashcraft:ts/scripts/wisp/acceptChecks.ts). `--dry-run` prints the plan
  without touching clients. In Smashcraft, `--pair K` starts through `lan fresh`
  and routes checks, captures, receipts, doctor and autopsy to that offline
  pair. `wisp integrity capture --clients-file FILE ...` likewise routes
  health checks to the selected clients (smashcraft:docs/native-bot-session.md).
  Consume these supported routes (Smashcraft commit 1745c4df) instead of
  adding bespoke doctor/autopsy wrappers or accidentally recovering online A/B.
- Order each pair's queue by issues closed per session; finish source and
  headless prep first. Protect performance/cost/timing captures from local
  heavy work within their declared measurement interval; keep independent
  ready native lanes moving outside a measured shared constraint.
