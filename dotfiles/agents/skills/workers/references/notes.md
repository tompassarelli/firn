# Workers: notes

Detail that `SKILL.md` links to. Read a section only when the named question
arises.

## Tier and ledger experiments

Treat these ledger-derived rules as experiments: recheck `worker-ledger --summary`
after every 10 new closures in a category and change a rule when the numbers move.

- `worker-ledger --recommend` names the cheapest tier at 80% Done without a later
  `Follows:` run (and landed when it committed) in the finest cell with 5 runs. It
  backs off Surface, Verify, Scope, then Spec, and changes a cell's pick only on a
  15-point lead.
- Haiku trial: send each other tooling, balance-tuning and bug-known-cause item to
  `worker-haiku` with `Arm: haiku-trial` until the finest facet cell with 5 runs has
  5 Haiku closures or 2 Haiku failures. A failure goes to Opus medium with `Follows:`.
  The ledger's haiku rows decide the category default (Haiku 29/32 mechanical at a
  1-minute median, 2026-10-10).
- Haiku ended its turn mid-run twice on 2026-10-10, killing the run, so keep it
  away from judged art, bisects, native checks and waits longer than 2 minutes.
- Opus high's overall rates (feature 6/25, native-check 0/8) come from escalated
  hard cases and do not rank tiers. Alternate each feature or native-check that Opus
  medium left unfinished between escalation to Opus high and the cheaper fix (split
  the feature into smaller boxes; fix the native-check's client, capacity or host
  cause), and compare closures on those leftovers only.
- Provider benchmarks only before 5 closed category issues at that tier.
- Token cost: compare Haiku and Opus at 1:40, and price Haiku prompts above 100k
  tokens at 5 times their normal rate.
- Escalate to the next tier printed by `agents plan` only after `Stop: reasoning`
  (wrong cause or two failed fixes).

## Review lenses and findings

- Lenses: desync or determinism hunter, frame-time profiler, new player at first
  match, Warcraft engine limits, maintainer six months later, cheapest alternative,
  attacker of the measurement itself. Record the lens that found each accepted flaw
  so the ledger keeps the useful ones.
- Weigh findings by evidence first and reviewer tier second. A finding with a
  failing scenario, test or measurement counts whatever model raised it. An
  unevidenced finding from Opus max or xhigh or Astra xhigh gets investigated. One
  from a smaller model (Gemini, Haiku, Codex medium) gets one check by a stronger
  model before anyone acts on it or dismisses it.
- Reviewer order when the reviewer must come from another family: Codex
  `gpt-6-astra` xhigh while Codex usage remains, else `gpt-6.1-sol` high, else Opus at
  a different tier. Gemini is the cheap extra reviewer (`gemini-review`), public diffs
  only.

## Compute routing (agreed with Tom 2026-10-10)

- Cloud runs cost only the same plan usage a local worker would, with the machine
  included. Code-only Smashcraft and Wisp items go to `cloud-workers` first (4 cores
  per run, no run cap).
- Parallel batch work (balance and CPU fields, suites, soaks) goes to GitHub runners
  through `github-actions` first, and to vast.ai through `vast-job` when the farm
  queue delays a result.
- Always-on Warcraft clients, the offline LAN pool and GPU work go to the Hetzner box
  once it exists, and to the vast.ai VM until then. Signed-in Definitive clients stay
  local unless moved deliberately.
- Rent no other CPU provider: DigitalOcean and similar cost several times vast.ai for
  the same cores.
- A job longer than the 45-minute leash (renders, long captures) runs yourself under a
  capacity lease; staff a short worker to use its output.

## Landing mechanics

- Autoland repository: the worker ends once `safe-push --to main` has pushed its
  `claude/land-*` branch, reporting `Done: queued <branch>`. Autoland lands it, and a
  Haiku worker ticks its boxes after landing.
- Elsewhere: run `safe-push` in the foreground with a 10-minute timeout. If the
  landing outlasts that, report the exact lane for the parent to land in the
  background.
- While main is red, staff its fix first and keep queuing lanes behind it. Never
  cancel an Autoland run: a cancelled bisect half strands its lanes.
- Before a playtest's last blocker lands, prebuild its map with the fix applied and
  run the frame-cost compare, so the build cannot fail at playtest time.
- Before landing a `Spec: judged` cross-module or cross-repo lane, have a reviewer from
  another family or tier review the diff for wrong behaviour and weakened tests (plus
  Gemini on public repos), and fix what it shows before `safe-push`.
- Before an issue closes, `worker-haiku` reruns each Done when check against origin/main
  and quotes the numbers; close only when every box reproduces.

## Recycling and waits

- The worker-handoff hook nudges a worker between tool calls. The worker-wait-guard
  hook keeps workers out of foreground waits, so messages arrive at once.
- A recycled worker's handoff is written at a natural checkpoint. Check the fresh
  worker 5 minutes later for rediscovery.
- Expect a report at 45 minutes or twice ETA, whichever comes first.

## Lead ticks

- `tick` (see `agents routines show tick`) runs `threads unowned`, `worker-sweep
  --session` and `capacity-watchdog report --minutes 5 --minutes 30 | jq -c
  '{minutes, flags}'`. It acts only on flagged rows, so a quiet tick spawns no
  worker.
- `worker-sweep` ignores STALLED rows idle more than 300 minutes; those are
  pre-compaction transcripts.
- The DAG rebuild runs every 3rd tick or on a state change, and a lane whose push log
  ends in a rebase-and-retry message is requeued with `scratchpad/rebase-requeue.sh`.
- Count issues with `--limit 500`. Re-arm the origin/main landing monitor when it has
  expired.
