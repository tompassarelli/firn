---
name: convo-reference
description: >-
  Full conversation-search notes for index freshness, filters, bounded source inspection, and restoration.
---

# Conversation search: full notes

## Why the index is the first route

The transcript corpus contains large binary-like payloads and repeated context.
A bounded text index answers the question without turning a name lookup into
a machine-wide scan. Search results identify evidence of a conversation, not
objective truth or a current repository state.

## Corpus and index

The local JSONL corpus contains thousands of transcripts and hundreds of
thousands of messages. Most bytes are image payloads and replayed compaction
records rather than searchable conversation text. `convo` maintains a much
smaller SQLite FTS5 index of extracted message text, answers queries without
opening transcripts, and retains exact `path:line` locations. This also permits
closed transcript files to be compressed beneath the index.
Discovery covers the canonical `~/code/north-data/accounts` tree plus
configured `CODEX_HOME`, `NORTH_CODEX_POOLED_HOME`, and the default pooled
runtime home. Symlinked North projections are canonicalized, so each
transcript is indexed once.

`~/.local/state/north` points to `~/code/north-data`; searching both scans the
same corpus twice, while `--hidden` can add Git objects. A raw hit may also be
one enormous JSON line rather than a useful answer.

## Commands and filters

```text
convo <terms>                 FTS5 search: AND OR NOT "phrase"
convo -x '<literal>'          exact phrase for ids, errors, and paths
convo session <uuid>          transcripts belonging to one session
convo status                  index size, corpus size, and freshness
convo index --full            full rebuild; rarely needed
convo compress --dry-run      estimate reclaim from closed transcripts
convo restore <file>          restore one archived transcript as JSONL
```

Combine `-r user|assistant|thinking|tool`, `--since 3d|2w|6m`, `-p <project>`,
`-n <limit>`, `--json`, and `-u` as needed. Every ordinary search performs an
incremental refresh first across all configured roots; unchanged files are
skipped and only new bytes are read. If the refresh lock or an explicitly
configured root is unavailable, the result is explicitly inconclusive (exit
2), so restore the root or retry after the writer finishes. Successful passes
record the exact reconciled root set. A full rebuild is for index recovery, not
routine freshness. A `-u`/`--no-update` miss is also inconclusive; use that flag
only when a stale hit is useful and freshness is intentionally unnecessary.

## Search recipes

- To isolate what the operator asked: `convo -r user --since 2w "schema rulings"`.
- To find where a defect was first named: `convo -x
  'TODO-FLOOR-NON-VIEW-RESIDUE'`.
- To locate all transcripts for a session: `convo session <uuid>`.
- To find a conclusion, search verdict vocabulary such as `refuted`, `landed`,
  or `ruling`, because topic words recur more broadly.
- To feed another tool, use `--json` for the snippet plus source path and line.

## Guard boundary

`corpus-scan-guard` blocks recursive raw searches rooted at the corpus, its
symlink, or large transcript containers such as `accounts/`, provider/account
roots, `sessions/`, year/month session directories, and `archives/`. Bounded
operations remain possible: one named transcript, a day directory or deeper, a
non-transcript subtree, `find <root> -maxdepth 2`, `rg --max-depth 2`, and
non-recursive `grep`. The normal sequence is indexed search, then a bounded raw
inspection of the named source.

## Compression and resume

Compression rewrites transcripts untouched for 48 hours as `.jsonl.zst`, while
skipping open files and coordinator-named sessions. Indexed search still works.
Provider resume does not: `codex resume <uuid>` needs plain JSONL, so restore
the selected rollout first.

The corpus is local-only and indexes conversations, not repository code,
configuration, commits, or objective truth.

## Interpreting a result

Use the speaker, date, and surrounding source to distinguish a proposed rule
from an accepted decision or a later reversal. A search miss proves absence
only within a successfully refreshed, relevant scope. An unavailable root or
stale index leaves a gap; it does not justify an unbounded raw scan.

Search first, inspect the exact resulting source second. Compression and full
index rebuilding are maintenance operations, not prerequisites for answering
an ordinary historical question.
