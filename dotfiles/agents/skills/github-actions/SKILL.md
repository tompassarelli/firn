---
name: github-actions
description: >-
  Write or change GitHub Actions workflows, dispatch or wait on runs, or run
  many agents against GitHub: share the account's concurrent-job limit and
  hourly API budget, cap matrices, join runs, poll with backoff, and clean up
  scratch branches.
---

# GitHub Actions

Every repository on Tom's account shares one pool of runners and one API
budget, and every agent spends from both. One workflow or one waiting loop can
starve all the others. Tags like [L1] name the evidence in
`references/sources.md`; read it when revising this skill or when a number
here needs its source.

## The two shared limits

- **Concurrent jobs.** The account runs at most 20 jobs at once on GitHub
  Free (5 macOS), across all its repositories [L1]. Jobs over the limit wait,
  and in practice they start in arrival order, so a 100-job field dispatched
  first holds every later run back until it drains. Check the plan before
  assuming 20.
- **API calls.** Tom's login has 5,000 REST calls an hour, shared by every
  token, app, `gh` session and agent acting as him [R1]. `GITHUB_TOKEN`
  inside a workflow has its own 1,000 an hour per repository [L1, R1].
  Bursts also hit secondary limits: 100 concurrent requests, 900 points a
  minute, 80 content-creating requests a minute [R1].

## Writing workflows

- Size every matrix against the job limit and leave headroom for CI: no
  workflow may hold more than about 8 of the 20 slots, so a fresh push's first
  job starts within a minute. Set `strategy.max-parallel` on every matrix that
  can exceed that [W1].
- Use fewer, bigger shards. Pack enough work into each job that checkout and
  setup stay a small part of it; halving the job count halves the queue it
  makes. A balance field went from 54 to 27 jobs by playing 8 pairs a job.
- Run CI once per branch, so a newer push cancels the superseded run [C1]:

  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: true
  ```
- A one-at-a-time workflow (a fixed concurrency group, no cancel) is correct
  for landing to main, but it serializes everything in it, and a newer
  pending run replaces the older pending one [C1]. Keep only landings in that
  group; never put farm or test runs in it.
- A matrix of up to 256 jobs is legal [L1]; that is a ceiling, not a target.

## Dispatching runs

- Count queued and running **jobs**, not runs, before a large dispatch. A
  queued run can hold running jobs, so filtering runs by status hides the
  load: `gh api repos/OWNER/REPO/actions/runs/ID/jobs` per active run, and a
  job with no `runner_name` is still waiting. If the account is near its
  limit, wait or shrink the dispatch rather than adding to the queue.
- One run per commit. Before dispatching a test of a commit, look for a
  queued or running run of the same workflow on that commit and join it.
  Never push a scratch branch or dispatch a duplicate to get "your own" run.
- Cancel runs you superseded: an older push, an abandoned experiment, a
  field whose answer you no longer need (`gh run cancel ID`).
- Register a scratch branch's deletion when you create it (a cleanup trap,
  a `finally`, or the workflow deleting its own ref when it ends). A scratch
  branch deleted "after the run" leaks whenever the agent dies first.

## Waiting on runs

- Wait through the repository's own tool (for example
  `bun wisp farm ... --wait`), never a hand-written `gh run view` or
  `gh run watch` loop. If the repo has no waiting tool and you need one,
  write it with the backoff below.
- Back off: first poll after 10 s, then 1.5 times longer after each poll that
  shows no change, capped at 60 s, back to 10 s when a job starts or
  finishes. One poll should be one or two API calls. At the 60 s cap, twenty
  waiting agents spend about 2,400 calls an hour, inside the 5,000.
- Budget for many agents: a 5 s poll costs about 24 calls a minute; twenty
  agents doing that spend the whole hour's budget in under 15 minutes.
  Batch reads (one jobs listing, not one call per job), make requests one at
  a time, and prefer conditional requests, whose `304` answers don't count
  [B1].

## Rate-limit refusals

- `HTTP 403` or `429` with "API rate limit exceeded" is real. Read the
  refused response's headers: `x-ratelimit-remaining: 0` with
  `x-ratelimit-reset` means the hour's budget is spent; `retry-after` means a
  secondary limit [R1, B1]. Don't trust `gh api rate_limit` for this; on
  8 Oct it showed 5,000 left while every call was refused. To see the real
  budget, look at a real request's headers:
  `curl -sI -H "Authorization: token $(gh auth token)" https://api.github.com/repos/OWNER/REPO | rg -i x-ratelimit`.
- Every `gh` call in tooling retries a rate-limit refusal: honour
  `retry-after` or `x-ratelimit-reset` when present, otherwise wait 30 s and
  double each time up to 5 minutes, with jitter, for long enough to cross an
  hourly reset (about 65 minutes). Say on stderr that it is waiting. Retrying
  at once while refused can get the integration banned [B1].
- When refusals start, stop your own polling first. Don't add another agent
  to "check on it".

## Worked contrast

Bad: twenty agents each dispatch their own farm run of the same few commits
and poll `gh run view` every 5 s, while a 109-job balance field sits ahead of
them. Every stage waits 10 to 15 minutes, and the hourly API budget runs out
in under an hour. Good: the field runs 27 jobs at most 8 at once, each agent
joins the run already testing its commit and waits through the repo's
backoff, and a fresh run starts its first job in 6 seconds.

The 8 Oct incident, its measurements and the fixes are in
`references/sources.md` under "Incident".
