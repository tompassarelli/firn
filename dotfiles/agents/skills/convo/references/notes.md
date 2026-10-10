# convo: maintenance and internals

## Corpus and index

`convo` indexes the canonical `~/code/north-data/accounts` tree, a configured
`CODEX_HOME` and `NORTH_CODEX_POOLED_HOME`, the default pooled runtime home,
and Claude Code's `~/.claude/projects` (or `$CLAUDE_CONFIG_DIR/projects`). In a
Claude projects tree only `<project>/<session>.jsonl` and
`<project>/<session>/subagents/agent-<id>.jsonl` are transcripts; a subagent
file carries its parent's session id and its own agent id. A Codex subagent
rollout carries its lead's session id. A file reached twice through symlinks or
hardlinks is indexed once.

The index is `~/.local/state/convo/index-v4.db` (SQLite, FTS5 with porter
stemming and bm25). Tables: `files` (one row per transcript, with its byte
offset), `msg` (every message: file, line, time, role, tool, body), `body`
(each distinct text once) and `ftx` (full text of each body, keyed by the
first message that said it). A text repeated by a Codex fork or a re-sent
prompt is ranked once, at its first occurrence; with filters, the first
occurrence that passes them is shown. Tool calls
are indexed as `<tool> <key>=<value>`; tool output, images, developer
messages and compaction replays are not indexed.

A new schema version gets a new file name. Build it once with `convo index`
under a machine-capacity lease (moderate class); it reads every transcript,
and searches refuse to run without it. `convo index --full` rebuilds from
scratch. Every ordinary search then runs an incremental pass that stats each
transcript and reads only appended bytes.

## Guard boundary

`corpus-scan-guard` blocks recursive raw searches rooted at the corpus, its
symlink, or large transcript containers such as `accounts/`, provider and
account roots, `sessions/`, year and month directories, and `archives/`.
Bounded reads remain possible: one named transcript, a day directory or
deeper, `find <root> -maxdepth 2` and `rg --max-depth 2`. `~/.local/state/north`
points to `~/code/north-data`, so searching both reads the corpus twice.

## Compression and resume

`convo compress` rewrites Codex rollouts untouched for 48 hours as
`.jsonl.zst` (zstd -3, 128 MiB window), skipping files any process holds open
and sessions the coordinator roster names. It verifies a byte-exact round trip
before unlinking the source. Claude Code transcripts are never compressed;
`compress` reports how many it left alone. Search keeps working on archives,
but `codex resume <uuid>` needs plain JSONL, so run `convo restore <file>`
first. Compression, restore and full rebuilds are maintenance, never
prerequisites for answering a question.

## Skill usage

A Claude Skill load is a `tool` message with `tool = 'Skill'` and text
`Skill skill=<name>`. Count loads and sessions over a frozen window straight
from the index (`sqlite3 -readonly ~/.local/state/convo/index-v4.db` after one
`convo index`):

```sql
SELECT substr(b.text, 13) AS skill, COUNT(*) AS loads,
       COUNT(DISTINCT f.session_id) AS sessions
FROM msg m JOIN body b ON b.id = m.body JOIN files f ON f.id = m.file_id
WHERE f.provider = 'anthropic' AND m.tool = 'Skill'
  AND m.ts >= '2026-09-26' AND m.ts < '2026-10-10T17:00'
GROUP BY skill ORDER BY loads DESC;
```

Codex has no Skill tool; it reads the file, so count `tool` messages whose
body text matches `skills/<name>/SKILL.md` with `f.provider = 'openai'`.
Loads include retries and re-reads: use the counts to find unused skills,
never to rank value.
