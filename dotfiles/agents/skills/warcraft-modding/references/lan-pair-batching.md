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

## Offline setup and client costs

- Follow wisp:docs/lan.md with `wisp lan setup --from "<clone>/pfx/drive_c/Program Files (x86)/Warcraft III" --pairs N` for reflinked installs (under 1 s for four pairs).
- Start admitted loopback-only pairs through `wisp lan pool --pair K... --pool-profile parity` with sound off.
- Run `bun wisp pad SCRIPT... --helper H --out DIR --map MAP --pair K...` against `map build --profile integrity` or `map rebuild MAP --profile integrity`.
- Compare observed setup costs of 70 s from pool start to running pair and 36 s from pad request to match.
- Add pairs one at a time while `protectedCpuSomeAvg10` stays below 20.
- Default to two pairs under normal agent load: online clones off measured 11–20 for two pairs and 22–31 for three; three online clones on measured 44 for two pairs.
- Use `lan fresh MAP [--pair K]`, `lan status` and `lan end --pair K` with state/clients.json under ~/.local/state/wisp/lan/.
- Account for each signed-in clone's roughly 0.5 core plus roughly 1 core of Battle.net browser and sound.
- Close clone games after Blizzard build changes for launcher updates (about 2 min), then recover through `client doctor`.
- Use clone-a's launch script to refuse while Tom's Warcraft/Battle.net runs and stop it within 10 s of either starting.
- Resolve signed-in desktop and launcher services as `wisp-desktop-CLIENT` and `wisp-client-CLIENT` through wisp:docs/doctor.md.

## Pending native issues

- Label landed fixes `needs:native-pair` or `needs:native-single` with the candidate map/script and required rows before moving to other work.
- Batch open issues bearing the assigned label across both repositories in one immutable build/session with many pad scripts/captures.
- Mark active checks `native:running` and skip already marked issues.
- Remove the need label when its box passes or comment the failure.
