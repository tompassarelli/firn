---
name: convo
description: >-
  Search past agent conversations with the `convo` CLI — full-text across every
  Claude Code, Codex, and North Bridge transcript on this machine. Use this
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

`convo` maintains a SQLite full-text index (~240 MB, 0.3% of the corpus) that
stores word positions and a byte offset per message, never a copy of the text.
Snippets are read back from the original JSONL at query time.

## Why not just grep

`~/.local/state/north` is a symlink to `~/code/north-data`, so naming both in
one search scans the same bytes twice; `--hidden` adds every `.git` object.
That is the 3.5 GB run. It is also usually the wrong instrument: transcripts
are line-oriented JSON, so a grep hit gives you a 59 MB line, not an answer.

Use `rg` for code. Use `convo` for conversations.

## The commands worth knowing

```
convo <terms>                 full-text search (FTS5 syntax: AND OR NOT "phrase")
convo -x '<literal>'          exact phrase — use for ids, error strings, paths
convo session <uuid>          locate every transcript for a session
convo status                  index size, corpus size, freshness
convo index --full            rebuild from scratch (rarely needed)
```

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

**Feeding results to other tooling** — `--json` emits structured hits with
file paths and byte offsets, so a follow-up can read the exact message.

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
