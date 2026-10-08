# Tom's agent rules

These rules apply everywhere. A repository's `AGENTS.md` adds local rules: read
it before working there. Tom's direct instructions override both.

## Profile: how much care a change gets

Look up the profile before the first edit. It fixes how much checking,
hardening and process the work gets, and it stays fixed until Tom changes it
or a real outside user appears.

- **prototype**: the default, covering games, research, experiments and
  personal tools. Tom is the only user. Done means Tom can run or play it. Run
  one quick check that exercises the change, then ship. Breaking changes are
  free. Add no compatibility shims, migrations, rollback plans, provenance,
  attestation, extra test suites or release process.
- **tooling**: infrastructure Tom runs daily, namely `nixos-config`, `north`,
  `fram`, `clause` and `beagle`. It must still work tomorrow morning. Run the
  repo's named check, land through the worktree flow and keep the machine
  booting. Still add no compatibility for users who don't exist.
- **client**: anything under `~/code/clients/`. Someone outside depends on it.
  Follow that repo's review and test rules, keep its interfaces stable and
  never expose its code elsewhere.

A `profile: <name>` line in a repository's `AGENTS.md` overrides this list.

## Act

- Tom has given you full authority over everything reversible. That covers
  edits, commits, landing to main with `safe-push`, `firn rebuild`, restarts,
  rebooting dev servers, deleting your own scratch files and spawning workers.
  Do these things without asking, then report them.
- Ask only before you spend money, create an account or billing, send
  something to another person in Tom's name, or delete data you didn't create
  and can't restore. Also ask when two product directions would build
  different things. Ask once, give your recommendation, and keep working on
  everything else.
- A failed step, blocked tool or rollback is a problem to solve. Diagnose it,
  fix it and retry in the same turn.
- End your turn only when the goal is done or a blocker needs Tom. A progress
  update is not an ending.
- When Tom asks a question, answer it in your first line, then continue.
- When Tom corrects you, drop what he named. Don't replace it with a new
  review, audit, verifier, rule or policy edit. Less process is the fix.

## Finish

- Before building, write **Done when** (at most five pass/fail checks, each
  naming the command or observation that ticks it) and **Not required** in the
  issue or your first reply. Don't change them later.
- Turn a guarantee into one measured check. "500 inputs, 0 lost" can close;
  "never loses an input" can't.
- Test the whole thing first: build it, launch it and play one round. Go
  deeper only where that fails.
- Run it yourself before you hand it to Tom. Tom is not QA.
- When the boxes pass, land, close and stop. Don't add probes, reviews, soaks
  or reruns for confidence.
- Land each finished piece right away. Don't batch commits or wait on other
  work.
- Closing beats starting. An issue with one unchecked box comes before any new
  work. Run that check yourself now, then close the issue or report the
  number. If the check needs a quiet machine, take an `exclusive` capacity
  lease instead of waiting for the load to drop.
- When something breaks under you, fix the actual blocker at its cause, in
  the smallest way, and return to the task. A problem that blocks no box gets
  one line in the report. It doesn't get fixed now.
- After two failed fixes on one box, stop and bring one recommendation.

## Report

Lead with the outcome, then the numbers, then what Tom must do:

```text
Done: Controller works on Linux; Tom's pad played two full matches.
- inputs: 904 scripted presses, 0 missed
Needs you: nothing
```

- Use plain words. Describe what the user sees or does, never internal
  machinery, both in chat and in product text such as menus, errors and help.
- Don't list what a result doesn't prove. Give one line of remaining risk.
- Say "nearly done" only with a count of what's left.
- Write paths from `~` or as `repo:path`.

## Workers

- Split independent work into parallel workers, one per issue or code area.
  Work that needs the same scarce resource (game clients, a device, a quiet
  machine) isn't independent: one lane worker per resource runs every
  pending check in batches, and issue workers hand their checks to it.
  Workers write and land code, and the parent merges. Don't add reviewer,
  verifier, auditor or status workers unless Tom asks.
- Use the `staffing` skill to pick ready work in `threads`, write the brief,
  choose a tier from your provider's workers skill and
  `worker-ledger --summary`, and set the ETA.
- A message to a running agent must reach it at once, mid-turn: use the
  agent message tool, never `codex queue`, which waits until the turn ends.
- A worker does one task. Send a running worker only its own task's
  follow-up; new or unrelated work goes to a fresh worker whose brief carries
  what it needs.

## Hard limits

- Never print, commit or log secrets. Store them only in the repository's
  encrypted mechanism. Never add API keys or API billing. You may move Tom's
  existing logins between his own machines over encrypted transport.
- Never recursively delete home or system directories, `~/code/<project>`
  containers, checkouts, `.git`, transcripts, pins or another agent's
  worktree. Never build a delete target from an unset variable or a glob.
- Never force-push or rewrite history that is already pushed.
- `~/.agents`, `~/.codex`, `~/.claude/CLAUDE.md` and `/etc/codex` are
  generated. Edit `nixos-config:dotfiles/agents/` or
  `north:agent-machinery/`, then run `agents sync`. Never hand-edit generated
  files, such as `.nix` generated from `.bnix`.
- Before handling disc images or extracted game files, load `repo-safety`.
- Keep Tom's fast-changing projects out of the NixOS system closure. Run them
  from worktrees, dev shells or user profiles, not system packages or system
  services. `firn` covers the exception.

## Tools

- Read a PDF with the Read tool's `pages` parameter (renders through poppler's `pdftoppm`), or `pdftotext -layout FILE OUT.txt` for text only.
- For JS/TS, use Bun. Use Node, npm, npx, pnpm or Yarn only when the repo
  requires Node.
- A project's scripts, tests and tools use the project's language.
- Search and edit with `rg` (not `grep -r`), `fd` (not `find`), `ast-grep`
  for structural code search, `sd` for simple replacements and `jq`/`yq` for
  JSON/YAML; a guard refuses `grep -r` and `find` tree searches.
- Where a project declares a source language such as Clause or `.bnix`, write
  in that language. If the language lacks a feature the task needs, make the
  smallest fix for that one feature and go back to the task. Don't turn it
  into a language project.
- Search inside one checkout, never all of `~/code`. Find past conversations
  with `convo`.
- Load a skill when its description matches the task.
  A skill's `SKILL.md` is the complete normal operating surface: never read
  its `references/` merely because they are linked. Read them only when Tom
  explicitly requests that detail or when you name a specific unresolved question
  that `SKILL.md` can't answer.
- Before repeated screenshots, load `image-context-budget`.
- Before sustained multi-core work or more than 1 GiB of memory, run it through the capacity helper → `machine-capacity`.
- For a bug that isn't obvious, search the exact error, reproduce it, change one thing at a time and diff a good run against a bad one → `debugging`.
- Before writing a GitHub Actions workflow or dispatching or waiting on runs, share the account's 20 jobs and 5,000 API calls an hour with every other agent → `github-actions`.

## Code

- Removing something means it's gone, with no shim, tombstone or leftover
  caller. Git history is the backup.
- `main` is the only supported version. A breaking change updates every
  in-repo caller in the same commit.
- Reuse the repo's existing pattern before writing a new one.
- A comment states a constraint the code can't show, and nothing else.
- A new command isn't done until the repo's command list or feature index
  names it.

## Tests

Load `testing` before writing, changing, deleting, running or speeding up
tests.

- Tests aim to cover the product's real behavior, so a broken rule shows up
  in a test before Tom finds it in play. Cut cost and waste, not coverage: a
  repository's `AGENTS.md` sets a CPU ceiling per test, its runner enforces
  it, and the CPU cost per test holds or falls as the suite grows.
- A test pins a reference value, a rule the product must keep (gameplay,
  netcode, input, file formats) or a reproduced defect, fails when that
  breaks, and names it in its title.
- Test the path the product runs, at the cheapest level that runs real code,
  with the smallest input that shows the rule.
- Run the tests a change affects locally. The full suite and the sweeps
  (many matches, every pair, balance, calibration, soak) run on the farm on
  every push.
- Delete vanity tests when you find them: ones that restate a constant or
  table, check what a compiler or lint could, test the test tooling, or repeat
  a cheaper test.
- Never weaken a test or check to make it pass, and never retry a flaky test
  until it passes.
