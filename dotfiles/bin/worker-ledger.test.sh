#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/worker-ledger-test.XXXXXX")
trap 'rm -rf "${scratch:?}"' EXIT
export THREADS_DB=$scratch/threads.db CLAUDE_CONFIG_DIR=$scratch/claude CODEX_CONFIG_DIR=$scratch/codex
python3 - "$CODEX_CONFIG_DIR" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1]); directory=root/'sessions/2026/10/08';directory.mkdir(parents=True)
def write(name, records):
    (directory/f'rollout-{name}.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in records))
def row(kind,payload,minute=0):
    return dict(type=kind,timestamp=f'2026-10-08T00:{minute:02}:00Z',payload=payload)
write('parent',[row('session_meta',dict(id='parent',timestamp='2026-10-08T00:00:00Z',source='cli')),
 row('response_item',dict(type='function_call',name='spawn_agent',call_id='spawn',arguments=json.dumps(dict(message='Item: firn#5\nFollows: prior\nCategory: tooling\nETA: 10 minutes',model='gpt-6.1-sol',reasoning_effort='medium')))),
 row('response_item',dict(type='function_call_output',call_id='spawn',output=json.dumps(dict(task_name='/root/finished'))))])
def worker(name,brief='',finished=False):
    rs=[row('session_meta',dict(id=name,timestamp='2026-10-08T00:00:00Z',source=dict(subagent=dict(thread_spawn=dict(parent_thread_id='parent',agent_path='/root/'+name))))),
        row('turn_context',dict(model='gpt-6.1-sol',effort='medium'))]
    if brief:rs.append(row('response_item',dict(type='message',role='assistant',phase='commentary',content=[dict(type='output_text',text=brief)])))
    rs.append(row('event_msg',dict(type='token_count',info=dict(total_token_usage=dict(output_tokens=321),last_token_usage=dict(input_tokens=900))),5))
    if finished:rs.append(row('response_item',dict(type='message',role='assistant',phase='final',content=[dict(type='output_text',text='Done: landed.')]),5))
    write(name,rs)
worker('finished',finished=True)
worker('running','Item: wisp#70\nCategory: native-check\nETA: 20 minutes',finished=True)
worker('untracked',finished=True)
PY
subagents=$CLAUDE_CONFIG_DIR/projects/-home-tom/session/subagents
mkdir -p "$subagents"
printf '%s\n' '{"agentType":"worker"}' >"$subagents/agent-haiku1.meta.json"
printf '%s\n' \
  '{"type":"user","timestamp":"2026-10-08T00:00:00Z","sessionId":"session","message":{"content":"Item: smashcraft#255\nCategory: mechanical\nETA: 15 minutes"}}' \
  '{"type":"assistant","timestamp":"2026-10-08T00:04:00Z","requestId":"r1","message":{"model":"claude-haiku-5-5","usage":{"output_tokens":50,"input_tokens":700},"content":[{"type":"text","text":"Done: landed."}]}}' \
  >"$subagents/agent-haiku1.jsonl"
"$repo/dotfiles/bin/worker-ledger" --since 2026-10-08 >/dev/null
"$repo/dotfiles/bin/worker-ledger" --since 2026-10-08 >/dev/null
python3 - "$THREADS_DB" <<'PY'
import sqlite3,sys
c=sqlite3.connect(sys.argv[1])
r=c.execute("select agent,item,follows,tier,category,minutes,eta_min,tokens,peak_ctx,outcome from runs where agent!='haiku1'").fetchall()
want=[('finished','firn#5','prior','gpt-6.1-sol medium','tooling',5,10,321,900,'done'),
      ('running','wisp#70',None,'gpt-6.1-sol medium','native-check',5,20,321,900,'done')]
assert r==want,(r,want)
h=c.execute("select tier,category,minutes from runs where agent='haiku1'").fetchone()
assert h==('haiku','mechanical',4),h
print('PASS a Claude worker running a Haiku model is recorded as tier haiku')
assert c.execute('select count(*) from claims').fetchone()[0]==0,'finished workers must release holds'
print('PASS [spec #5] Codex plaintext spawn brief records fields, model/effort, timing and tokens exactly once')
PY

mkdir "$scratch/bin"
cat >"$scratch/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' '{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}'
GH
chmod +x "$scratch/bin/gh"
out=$(PATH="$scratch/bin:$PATH" "$repo/dotfiles/bin/worker-ledger" --summary)
[[ "$out" =~ tooling[[:space:]]+gpt-6.1-sol[[:space:]]+medium[[:space:]]+1[[:space:]]+1 ]]
[[ "$out" =~ native-check[[:space:]]+gpt-6.1-sol[[:space:]]+medium[[:space:]]+1[[:space:]]+1 ]]
printf '%s\n' 'PASS [spec #5] encrypted brief repeated in commentary counts once by category and model/effort in summary'
