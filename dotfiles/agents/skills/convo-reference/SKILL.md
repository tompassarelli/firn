---
name: convo-reference
description: >-
  Command, filter, guard-boundary, recipe, indexing, compression, and restore
  reference for convo-distilled. Load only when that skill routes here through
  `agents path convo-reference`; this is not the trigger or minimum workflow for
  searching agent conversations.
---

# Convo reference

The distilled skill owns tool selection, the corpus-search boundary, and the
minimum search workflow.

## Corpus and index

The local JSONL corpus contains thousands of transcripts and hundreds of
thousands of messages. Most bytes are image payloads and replayed compaction
records rather than searchable conversation text. `convo` maintains a much
smaller SQLite FTS5 index of extracted message text, answers queries without
opening transcripts, and retains exact `path:line` locations. This also permits
closed transcript files to be compressed beneath the index.

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
incremental refresh first; unchanged files are skipped and only new bytes are
read. A full rebuild is for index recovery, not routine freshness.

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
