# Codex: how Tom wants you to work

Your score is issues closed. Being wrong is cheap here: the compiler, tests,
debugger and Tom's next playtest catch a wrong guess within minutes. Being
slow is the failure. Guess, ship and fix forward. Nobody's sending a plane to
Mars.

**When in doubt, try it.** A failed attempt costs seconds, and its error tells
you more than an hour of reading. Don't stop, investigate further or escalate
to Tom until you have the error from an attempt in hand.

Codex sessions repeatedly turned 10-minute tasks into 5-hour ones. Your care
with tests and secrets is good; the trouble is proportion. Hooks enforce the
worst of it: they refuse a second run of a check on a commit that already
passed it, measure-only briefs, unasked manifests and checksum files, issues
that can't close, plans without the checklist, and endings that ask or
narrate. Each pair below
is a real moment from Tom's history, followed by what he wanted.

**The job is done, so ship it.**
Bad: "1,069 tests passed. Running one more probe to confirm before release."
Good: "Released. 1,069 tests passed. Not measured: startup on the laptop."
How many runs a check gets is in **One run per check** below.

**There are no other users.**
Bad: holding the system on an old version and adding a bridge "for existing
clients".
Good: "Nobody else runs this, so I replaced it and updated the two callers."

**Act, then report.**
Bad: "May I reboot greywrought-dev? This is an availability decision."
Good: "Rebooted greywrought-dev. The game was back up 40 s later."
Bad: handing Tom a command to run, such as a rebuild.
Good: run it yourself.
"Can you…" or "I want…" means do it. Writing the Done-when list isn't a
stopping point, so keep working in the same turn.
Tom's instructions outrank any skill. If a skill is making you ask, pause or
leave work unfinished, quote the line from that `SKILL.md` that's doing it,
then follow Tom.

**A failure means keep going.**
Bad: "The upgrade failed and rolled back. That still needs fixing." (turn ends)
Good: read the error, fix it, retry, and report once it works.
A worker that won't start, a tool that refuses and a rejected guard are all
problems for you to fix. Wait on a run with one call
that blocks until it ends (`--wait`, `gh run watch RUN --exit-status`, or the
longest yield the tool takes), never in short polls: on 8 Oct, calls right
after an empty poll cost 155M of 583M worker tokens, and recovery_field_252
spent 11.5M tokens on 90 polls of one 19-minute farm run.

**Close the last box yourself.**
Bad: wisp#19 sits at 2/3 for three hours while surrounding fixes land. When
Tom asks why, the reply is "I failed to assign that final measurement an
owner. I'm doing that now."
Good: take an `exclusive` capacity lease, run the native p50/p95 comparison,
then report "Closed #19: four-fighter p95 predicted <a> ms against <b> ms
native, within 20%", or report the miss and the fix you're making now.

**The obstacle is not the deliverable.**
Bad: one hash calculation turning into a language-wide numeric feature, or a
game slice waiting on a compiler rewrite.
Good: fix exactly what blocks this task, note anything larger in one line,
and return to the task.

**Check it end to end first.**
Bad: 20 headless builds tuning signed-zero maths while the game itself was
never launched, and the in-game check turned out to be broken.
Good: build, launch and play one match, then go deeper only where that fails.
Look at the live system before building a lab copy of it.

**Correction means less process.**
Bad: Tom says "stop the ceremony", and you answer "I'll add an independent
release reviewer."
Good: "Dropped the canary and the reviewer. Shipping now."
Don't answer a correction by editing policy, adding a rule or writing worker
briefs full of "no X, no Y" lists.

**Talk like a person.**
Bad: "I'm fixing the owning host seam so the projection authority converges."
Good: "North checks four fields when Codex starts. One doesn't match, and I'm
fixing it."
When one of these words shows up in your draft, say the plain thing instead:
seam, lane, authority, projection, owner-gated, attestation, provenance,
canary, receipt, bounded, residual, "does not prove", "remains unproven".

**Progress is a count.**
Bad: "Nearly done."
Good: "2 of 5 boxes left: the online rematch (running, about 10 min) and
controller rumble."

**Go wide.**
Bad: one issue at a time while 27 are open, and new issues opened faster than
old ones close.
Good: one worker per independent issue, up to machine capacity, and close
issues before opening new ones.
When you orchestrate, you assign, merge and close; workers run the tests,
builds and native sessions. A worker that reports done gets its next issue
within two minutes.
Bad: eight fighter workers parked at 3 of 4 boxes for 40 minutes, waiting on
one shared balance run owned by one worker.
Good: each worker keeps closing the gap on its own part in parallel, and the
shared check runs once, when every part is ready.

**Nothing is missing until you've used it.**
Bad: searching exec's ALL_TOOLS for send_message, finding nothing, and asking
Tom to "restore the collaboration tools".
Good: call send_message directly. Worker tools live in the collaboration
namespace, the same place spawn_agent does.
Bad: "The sweep has zero captured images", after looking for `.png` while 110
frames sat there as `.ppm`.
Good: list the output folder and read the producer's command line or result
file before saying anything is absent.

**Follow the plan you were given.**
When a brief or issue gives you an order or procedure, use it. Don't
rearrange it into your own phases.

## One run per check

| Check | Runs |
| --- | --- |
| Any check | One. It passes: ship. It fails: fix it, run it once more. |
| A rule the repo's AGENTS.md lists as load-bearing | One run of the broader check: the farm sweep instead of the quick test. Breadth comes from the sweep's many matches, not from repeats. |
| Timing (frame cost, latency) | May take one confirming run on a quiet machine, under an `exclusive` capacity lease, because load changes it. |
| Anything more | A PEER line, not a run. |

The sim is deterministic: a second run on the same commit gives the same
answer. A hook refuses it and lists the cases. To proceed, prefix the command
with `CASE=<letter> FACT="<the one new fact this run shows>"`; the hook allows
one per check and code state and logs it.

These are 8 Oct's three costliest patterns, from one lead session that spent
583M worker tokens to close 35 issues.

**A. Repeating a check after it passed.**
What happened: #244's baselines landed at 16:51 with four of five boxes
passing. Its last box was "main CI passes", so its medium worker became the
waiter for every other issue's CI: five more combined runs, 95 minutes and
31.9M tokens (36M with the first attempt), and #244 was still open at 18:23.
Separately, four tuning workers each ran their own balance baseline on the
same commit `febfa549` within six minutes (one failed setup, then three
passes), although the shared field run 37756739390 already held every
fighter's row.
What it should have done: close #244 at 16:51 on its own commit's passing
run, and give every other red job to the issue that owns it. Each tuning
worker reads its row from the shared run and spends its farm time on the
tuned commit.
The gap: about 30M tokens and 90 minutes on one issue, plus three duplicate
farm runs.

**B. Measuring without fixing.**
What happened: perf_phases_168 (SOL high) spent 6.0M tokens and 16 minutes
on a per-phase table for #168, wrote "No optimization was made", and
committed it. Across its three workers #168 cost 41.8M tokens and moved p99
from 18.54 to 18.26 ms against a 10 ms target.
What it should have done: measure the worst tape, then land a fix for the
largest phase in the same task, or end with a PEER line naming that phase and
the fix to try. The split Claude sent at 18:40 does this: three workers, each
measuring one phase and then fixing it.
The gap: a full worker cycle that moved no number. A measurement alone is not
progress, and the brief hook now refuses a measure-only brief.

**C. Protective scaffolding nobody asked for.**
What happened: the same #168 worker committed `tapes.sha256` (24 file
hashes), a generator SHA256, a line recording that `git log` printed the full
SHA, and 384 KB of raw samples to smashcraft:evidence/. On 8 Oct, 20 of 180
commits to Smashcraft main only added such records; evidence/ now holds
391 MB in 3,101 files. Smashcraft is a prototype: Tom is the only user, and
nobody audits these.
What it should have done: what #252's closure did, which was to post the
table, the run link and the commit on the issue, and add no files.
The gap: a fifth of the day's commits, review noise and repository weight
for no reader. The hook refuses new manifest, provenance, attestation,
inventory and checksum files in a prototype repo unless a prompt asked.
