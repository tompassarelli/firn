# GitHub Actions: sources

Read when revising the `github-actions` skill or when one of its numbers needs
its evidence. GitHub docs fetched 2026-10-08. Each entry: link, date read,
what we took. Tags in `SKILL.md` (for example [L1]) point here. GitHub's docs
pages carry no revision date; re-fetch them when a plan or limit changes.

## GitHub documentation

- [L1] "Actions limits",
  https://docs.github.com/en/actions/reference/limits, read 2026-10-08.
  Took: concurrent jobs on standard GitHub-hosted runners per account or
  organization: Free 20 (5 macOS), Pro 40 (5), Team 60 (5), Enterprise 500
  (50); a matrix generates at most 256 jobs per workflow run; a job runs at
  most 6 hours; `GITHUB_TOKEN` gets 1,000 requests an hour per repository.
  Jobs over the concurrency limit are queued.
- [R1] "Rate limits for the REST API",
  https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api,
  read 2026-10-08. Took: an authenticated user gets 5,000 requests an hour,
  combined with every GitHub App or OAuth app acting for that user and every
  personal access token; secondary limits of 100 concurrent requests, 900
  points a minute for REST, 90 s of CPU time per 60 s, 80 content-creating
  requests a minute and 500 an hour; exceeding either gives `403` or `429`;
  a spent primary limit shows `x-ratelimit-remaining: 0`; for a secondary
  limit honour `retry-after`, else `x-ratelimit-reset`, else wait at least a
  minute, then back off exponentially; `/rate_limit` doesn't count against
  the primary limit but can count against secondary limits.
- [B1] "Best practices for using the REST API",
  https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api,
  read 2026-10-08. Took: avoid polling (prefer webhooks); make requests
  serially, not concurrently; wait at least one second between mutating
  requests; obey `retry-after` and `x-ratelimit-reset`; continuing to make
  requests while limited may get the integration banned; a conditional
  request answered `304` doesn't count against the primary limit.
- [C1] "Control the concurrency of workflows and jobs",
  https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency,
  read 2026-10-08. Took: one running and at most one pending run or job per
  concurrency group; a new pending entry cancels the existing pending one;
  `cancel-in-progress: true` cancels the running one; the
  `${{ github.workflow }}-${{ github.ref }}` group example; ordering within a
  group is FIFO by when each began waiting and not guaranteed.
- [W1] "Running variations of jobs in a workflow",
  https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations,
  read 2026-10-08. Took: `jobs.<job_id>.strategy.max-parallel` sets how many
  matrix jobs run at once, even when more runners are free; `fail-fast`
  cancels the matrix's in-progress and queued jobs when one fails.

## Incident, 2026-10-08

Full analysis: wisp:docs/ci.md, "Runner capacity and waiting". Commits:
wisp 61b6fb8, 9405407, 8a56976; smashcraft 0b8ef4e5, e06e9071, 4556648f.

- Queue: two balance fields queued 109 shard jobs in 13 minutes on the
  account (then on GitHub Free, 20 jobs; it is now GitHub Pro, 40). Every farm run after them waited 10 to 15 minutes per
  stage (plan, shards, merge): waiting jobs were served in arrival order
  across smashcraft and wisp. Filtering runs by status hid the load because
  jobs inside "queued" runs were already running.
- API: `403 API rate limit exceeded` refusals were the hourly 5,000 truly
  spent (5,000 used between about 04:32 and 05:26 UTC, some 90 calls a
  minute; the refused responses said 0 left and gave the reset time), while
  `gh api rate_limit` showed 5,000 left throughout. Cause: each waiting
  `farm --wait` polled every 5 s (about 24 calls a minute) and about twenty
  agents ran their own `gh run view` loops.
- Fixes that worked: balance shards went from 54 to 27 jobs (8 pairs a job);
  per-workflow caps (`max-parallel` 8 for balance and farm test, 6 for pads,
  4 for perf); CI once per ref with superseded runs cancelled; `--wait`
  polls 10 s then times 1.5 up to 60 s, resetting on progress; `farm test`
  joins an existing run of its commit before pushing anything; every farm
  `gh` call retries rate-limit refusals from 30 s doubling to 5 minutes with
  jitter, for up to 65 minutes. Afterwards a fresh run started its first job
  in 6 s.
- Also learned: Autoland's one-at-a-time concurrency group is correct but
  serializes landings, so it holds only Autoland runs; scratch branches
  leaked whenever their deletion was left to a step after the run, so
  deletion must be registered when the branch is created.
