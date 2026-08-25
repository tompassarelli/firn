---
name: convo
description: >-
  Search past agent conversations with the `convo` CLI — full-text across every
  Codex and North Bridge transcript on this machine. Use this
  whenever the answer might live in an earlier session: "when did we discuss
  X", "what did I decide about Y", "find that session", recovering a prior
  ruling, tracking down where a defect was first named, or locating a session
  by its id. Reach for this INSTEAD of grep/rg/find over ~/code/north-data or
  ~/.local/state/north — those paths hold a 77 GiB transcript corpus and a
  single unscoped ripgrep there measured 3.5 GB of RSS and a quarter of a
  24-core machine, while the same lookup through convo costs 31 MB and 0.4 s.
---

# convo — search the conversation corpus

Everything ever said to or by an agent on this machine is on disk as JSONL:
~6,400 transcripts, ~560,000 messages, 77 GiB and growing daily. That corpus
is the machine's memory of its own decisions — which is why the answer to
"why did we do it that way" is usually in it, and why searching it naively is
so expensive.

`convo` maintains a SQLite full-text index (~1 GB, ~1% of the corpus) holding
the extracted message text — the actual conversation in 87 GiB of transcripts
is under a gigabyte; the rest is base64 image payload and Codex compaction
records replaying whole threads. A query is answered entirely from the index
and opens no transcript at all, which is what lets closed transcripts be
compressed underneath it. The recorded `path:line` stays exact.

## Why not just grep

`~/.local/state/north` is a symlink to `~/code/north-data`, so naming both in
one search scans the same bytes twice; `--hidden` adds every `.git` object.
That is the 3.5 GB run. It is also usually the wrong instrument: transcripts
are line-oriented JSON, so a grep hit gives you a 59 MB line, not an answer.

Use `rg` for code. Use `convo` for conversations.

`corpus-scan-guard` enforces exactly that boundary, so this is a refusal you
will meet rather than a rule you must remember. It denies a recursive search
(`rg`/`grep -r`/`find`/`fd`/`ag`) whose root is the corpus root, the symlink,
or an interior container still holding tens of gigabytes — `accounts/`, a
provider, an account, its `sessions/` or `projects/`, a sessions year or
month, `archives/`. Everything narrower stays allowed: one named transcript,
a single day directory and deeper, any
non-transcript subtree of `north-data`, `find <root> -maxdepth 2`,
`rg --max-depth 2`, and any non-recursive `grep`. The intended sequence is
`convo` to name the file, raw tools from there.

## The commands worth knowing

```
convo <terms>                 full-text search (FTS5 syntax: AND OR NOT "phrase")
convo -x '<literal>'          exact phrase — use for ids, error strings, paths
convo session <uuid>          locate every transcript for a session
convo status                  index size, corpus size on disk, freshness
convo index --full            rebuild from scratch (rarely needed)
convo compress --dry-run      what a sweep of closed transcripts would reclaim
convo restore <file>          put one archived transcript back as .jsonl
```

`convo compress` rewrites transcripts nothing has touched for 48 hours as
`.jsonl.zst` (~8x on this corpus), skipping any file a process still holds
open and any session the coordinator names. Searching is unaffected. A
provider resuming its own thread is not: `codex resume <uuid>` needs the
rollout as plain JSONL, so `convo restore` it first.

Useful filters, combinable: `-r user|assistant|thinking|tool` (role),
`--since 3d|2w|6m` (recency), `-p <project>`, `-n <limit>`, `--json`,
`-u` (skip the refresh when you want speed and staleness is fine).

## Recipes that answer real questions

**"What did Tom actually ask for?"** — `-r user` cuts out agent chatter, which
is most of the corpus by volume:
`convo -r user --since 2w "schema rulings"`

**"Where was this defect first named?"** — search the exact code or symbol:
`convo -x 'TODO-FLOOR-NON-VIEW-RESIDUE'`

**"Which session was that?"** — `convo session <uuid>` prints every transcript
that session owns, including its subagents, with message counts and time span.

**"What did we conclude, not just discuss?"** — searching for the conclusion's
vocabulary ("refuted", "landed", "ruling") beats searching the topic, because
topics recur across sessions while verdicts are stated once.

**Feeding results to other tooling** — `--json` emits structured hits with the
snippet and the `path`/`line` the message came from.

## How it stays current

Every search runs an incremental refresh first: unchanged files are skipped by
identity and only new bytes are read, so a no-op refresh costs ~0.26 s. Cold
builds take minutes and are only needed once — pass `-u` if you are in a hot
loop and do not care about the last few messages.

## What it will not do

It indexes conversations, not repositories: code, configs, and commits are not
in it. It is local-only over Tom's own data — nothing leaves the machine. And
it finds messages, not truth: an agent asserting something in 2026-08-09 is a
record of a claim, so verify load-bearing findings against the tree before
acting on them.
