---
name: github-actions
description: >-
  Write or change GitHub Actions workflows, dispatch or wait on runs, or run
  many agents against GitHub within the account's job limit and hourly API
  budget: cap matrices, poll with backoff, clean up scratch branches.
grounded: 2026-10-10
written: 2026-10-10
metadata:
  kind: playbook
---

# GitHub Actions

- Read [sources](references/sources.md) only when revising a limit or resolving its source.
- Share the account's 20 concurrent jobs (at most 5 macOS) across repositories; check the plan before assuming that limit.
- Share Tom's 5,000 REST calls/hour across tokens/apps/agents.
- Budget workflow `GITHUB_TOKEN` separately at 1,000/hour/repository.
- Respect secondary limits of 100 concurrent requests, 900 points/minute and 80 content-creating requests/minute.
- Limit a workflow to about 8 of the 20 slots with `strategy.max-parallel`, leaving CI's first job able to start within one minute.
- Use fewer, larger shards to reduce checkout/setup and queue cost.
- Route heavy shard jobs with `runs-on: ${{ vars.FARM_RUNNER || 'ubuntu-latest' }}` (smashcraft, wisp: the `farm-big` self-hosted box, never for pull requests); delete the variable when the box is gone, or those jobs queue instead of falling back to hosted runners.
- Treat the legal 256-job matrix as a ceiling.
- Set CI concurrency to `${{ github.workflow }}-${{ github.ref }}` with `cancel-in-progress: true`.
- Keep fixed non-cancelling concurrency groups for landings only.
- Exclude farm/tests and account for replacement of older pending runs.
- Dispatch Balance, Playtest and soak runs only on a commit already on main, in a per-workflow `cancel-in-progress` group, and cancel them when that commit is reverted.
- Cap a batched landing queue at 2 lanes per batch until it tests each lane on its own first; batches of 3 or more went 0 of 15 green.
- Count queued and running jobs before large dispatches with `gh api repos/OWNER/REPO/actions/runs/ID/jobs`.
- Count missing `runner_name` as waiting.
- Wait or shrink dispatches near the account limit.
- Join an existing queued/running same-workflow run on the commit.
- Never dispatch or push a scratch branch for a duplicate run.
- Cancel superseded pushes, abandoned experiments and unnecessary fields with `gh run cancel ID`; never cancel a landing-queue run.
- Register scratch-branch deletion at creation through a trap, finally or workflow cleanup.
- Wait through the repository's own waiting tool; implement a waiter only when none exists.
- Poll after 10 seconds, multiply unchanged intervals by 1.5 up to 60 seconds, and reset to 10 seconds on job starts/finishes.
- Use one or two API calls per poll.
- Budget twenty waiters at the 60-second cap for about 2,400 calls/hour.
- Batch job reads, make requests sequentially and prefer conditional requests whose 304 responses do not count.
- Treat rate-limit HTTP 403/429 as real; inspect the refused response headers rather than trusting `gh api rate_limit`.
- Wait for `x-ratelimit-reset` when remaining is zero, or honor `retry-after` for secondary limits.
- Retry every tooling `gh` rate-limit refusal with header delays or 30-second exponential backoff capped at five minutes, with jitter, for about 65 minutes across hourly reset.
- Print waits to stderr.
- Never retry immediately while refused.
- Stop your own polling when refusals start.
- Never add an agent to check them.
- Use `gh api --help`, `gh workflow run --help`, and `gh run --help` for command detail.
