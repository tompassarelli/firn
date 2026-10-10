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
farm='text(await tools.exec_command({cmd:"bun wisp farm balance \\"wren 120\\" --wait",workdir:"/w"}))'
rs=[row('session_meta',dict(id='repeater',timestamp='2026-10-08T00:00:00Z',source=dict(subagent=dict(thread_spawn=dict(parent_thread_id='parent',agent_path='/root/repeater'))))),
    row('turn_context',dict(model='gpt-6.1-sol',effort='high')),
    row('response_item',dict(type='message',role='assistant',phase='commentary',content=[dict(type='output_text',text='Item: smashcraft#250\nCategory: balance-tuning\nETA: 20 minutes')]))]
for n in (1,2,3):
    rs.append(row('response_item',dict(type='custom_tool_call',name='exec',call_id=f'c{n}',input=farm),n))
    rs.append(row('response_item',dict(type='custom_tool_call_output',call_id=f'c{n}',output=[dict(type='input_text',text='{"exit_code":0,"output":"pass"}')]),n))
rs.append(row('response_item',dict(type='message',role='assistant',phase='final',content=[dict(type='output_text',text='Done: measured.')]),5))
write('repeater',rs)
PY
subagents=$CLAUDE_CONFIG_DIR/projects/-home-tom/session/subagents
mkdir -p "$subagents"
printf '%s\n' '{"agentType":"worker"}' >"$subagents/agent-haiku1.meta.json"
printf '%s\n' \
  '{"type":"user","timestamp":"2026-10-08T00:00:00Z","sessionId":"session","message":{"content":"Item: smashcraft#255\nCategory: mechanical\nETA: 15 minutes"}}' \
  '{"type":"assistant","timestamp":"2026-10-08T00:04:00Z","requestId":"r1","message":{"model":"claude-haiku-5-5","usage":{"output_tokens":50,"input_tokens":700},"content":[{"type":"text","text":"Done: landed."}]}}' \
  >"$subagents/agent-haiku1.jsonl"
printf '%s\n' \
  '{"type":"user","timestamp":"2026-10-08T00:00:00Z","sessionId":"session","message":{"content":"Item: smashcraft#256\nCategory: mechanical"}}' \
  '{"type":"assistant","timestamp":"2026-10-08T00:01:00Z","requestId":"r1","message":{"model":"claude-haiku-5-5","usage":{"output_tokens":5},"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"cd /w && git -c gc.auto=0 commit -qm fix"}}]}}' \
  '{"type":"user","timestamp":"2026-10-08T00:02:00Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}' \
  '{"type":"assistant","timestamp":"2026-10-08T00:03:00Z","requestId":"r2","message":{"model":"claude-haiku-5-5","usage":{"output_tokens":5},"content":[{"type":"text","text":"Done: committed."}]}}' \
  >"$subagents/agent-commit1.jsonl"
printf '%s\n' '{"agentType":"worker"}' >"$subagents/agent-commit1.meta.json"
"$repo/dotfiles/bin/worker-ledger" --since 2026-10-08 >/dev/null
"$repo/dotfiles/bin/worker-ledger" --since 2026-10-08 >/dev/null
python3 - "$THREADS_DB" <<'PY'
import sqlite3,sys
c=sqlite3.connect(sys.argv[1])
e=dict(c.execute("select agent,expects_landing from runs").fetchall())
assert (e['commit1'],e['haiku1'],e['repeater'])==(1,0,0),e
print('PASS a run expects a landing exactly when its transcript ran a git commit or push')
r=c.execute("select agent,item,follows,tier,category,minutes,eta_min,tokens,peak_ctx,outcome from runs where agent not in ('haiku1','commit1')").fetchall()
want=[('finished','firn#5','prior','gpt-6.1-sol medium','tooling',5,10,321,900,'done'),
      ('running','wisp#70',None,'gpt-6.1-sol medium','native-check',5,20,321,900,'done'),
      ('repeater','smashcraft#250',None,'gpt-6.1-sol high','balance-tuning',5,20,0,0,'done')]
assert r==want,(r,want)
h=c.execute("select tier,category,minutes from runs where agent='haiku1'").fetchone()
assert h==('haiku','mechanical',4),h
print('PASS a Claude worker running a Haiku model is recorded as tier haiku')
rep=c.execute("select repeats,landed from runs where agent='repeater'").fetchone()
assert rep==(2,0),rep
print('PASS a Codex worker that reran a passing farm check twice and pushed nothing counts 2 repeats, no landing')
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
[[ "$out" =~ repeat_runs[[:space:]]+no_landing ]]
[[ "$out" =~ balance-tuning[[:space:]]+gpt-6.1-sol[[:space:]]+high[[:space:]].*[[:space:]]2[[:space:]]+1/1 ]]
printf '%s\n' 'PASS [spec #5] encrypted brief repeated in commentary counts once by category and model/effort in summary'
