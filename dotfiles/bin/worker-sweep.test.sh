#!/usr/bin/env bash
# Checks are eval strings, expanded when they run.
# shellcheck disable=SC2016,SC2034
# Fixture session for worker-sweep: which workers count as running, the
# STALLED and HANDOFF flags, session selection and --wait's exit.
set -uo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
sweep=$repo/dotfiles/bin/worker-sweep
scratch=$(mktemp -d "${TMPDIR:-/tmp}/worker-sweep-test.XXXXXX")
trap 'rm -rf "${scratch:?}"' EXIT
export CLAUDE_CONFIG_DIR=$scratch/claude THREADS_DB=$scratch/threads.db CODEX_CONFIG_DIR=$scratch/codex

python3 - "$CLAUDE_CONFIG_DIR/projects" <<'PY'
import json, os, sys, time
from datetime import datetime, timezone

root = sys.argv[1]
now = time.time()
def ts(minutes_ago):
    return datetime.fromtimestamp(now - minutes_ago * 60, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
def usage(tokens):
    return {"input_tokens": 10, "cache_read_input_tokens": tokens - 10, "cache_creation_input_tokens": 0}
def brief(m, words="brief"): return {"type": "user", "timestamp": ts(m), "message": {"role": "user", "content": words}}
def tool_use(m, tokens, tid="t1", bg=False):
    return {"type": "assistant", "timestamp": ts(m), "message": {"role": "assistant", "usage": usage(tokens),
            "content": [{"type": "tool_use", "id": tid, "name": "Bash", "input": {"command": "x", "run_in_background": bg}}]}}
def result(m, tid="t1"):
    return {"type": "user", "timestamp": ts(m), "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "content": "ok"}]}}
def text(m, tokens, words):
    return {"type": "assistant", "timestamp": ts(m), "message": {"role": "assistant", "usage": usage(tokens), "content": [{"type": "text", "text": words}]}}
def reminder(m): return {"type": "attachment", "timestamp": ts(m), "attachment": {"type": "total_tokens_reminder"}}
def notice(m, tid):
    return {"type": "attachment", "timestamp": ts(m), "attachment": {"type": "queued_command",
            "prompt": f"<task-notification>\n<tool-use-id>{tid}</tool-use-id>\n<status>completed</status>\n</task-notification>"}}

def session(project, sid, agents):
    d = os.path.join(root, project, sid, "subagents")
    os.makedirs(d)
    for aid, kind, lines in agents:
        with open(os.path.join(d, f"agent-{aid}.jsonl"), "w") as f:
            f.writelines(json.dumps(l) + "\n" for l in lines)
        with open(os.path.join(d, f"agent-{aid}.meta.json"), "w") as f:
            json.dump({"agentType": kind}, f)
    return d

old = session("-home-tom", "old-session", [
    ("oldtool", "worker", [brief(90), tool_use(5, 410000)]),
])
os.utime(old, (now - 3600, now - 3600))
session("-home-tom", "new-session", [
    ("pending", "worker-high", [brief(30, "Item: smashcraft#7"), tool_use(1, 200000)]),
    ("result", "worker", [brief(30), tool_use(2, 150000), result(1), reminder(1)]),
    ("handoff", "worker-high", [brief(40), tool_use(2, 410000), result(2)]),
    ("stalled", "worker", [brief(60), tool_use(25, 90000)]),
    ("bgwait", "worker", [brief(30), tool_use(10, 80000, "bg1", True), result(10, "bg1"), text(9, 81000, "Waiting for the test run.")]),
    ("bgdone", "worker", [brief(30), tool_use(10, 80000, "bg2", True), result(10, "bg2"), text(9, 81000, "Waiting for the test run."), notice(1, "bg2")]),
    ("bgfinal", "worker", [brief(30), tool_use(10, 80000, "bg3", True), result(10, "bg3"), notice(8, "bg3"), text(7, 82000, "Done: waiting is over.")]),
    ("finished", "worker-high", [brief(30), tool_use(5, 300000), result(5), text(4, 301000, "Done: shipped.")]),
    ("interrupted", "worker", [brief(30), tool_use(5, 300000), result(5), {"type": "user", "timestamp": ts(4), "message": {"role": "user", "content": [{"type": "text", "text": "[Request interrupted by user]"}]}}]),
    ("explore", "Explore", [brief(30), tool_use(1, 500000)]),
])
PY

pass=0 fail=0
check() {
  if eval "$2"; then pass=$((pass + 1)); printf 'PASS  %s\n' "$1"
  else fail=$((fail + 1)); printf 'FAIL  %s\n%s\n' "$1" "$out"; fi
}
row() { grep -E "^$1 " <<<"$out"; }

out=$("$sweep")
ids=$(awk '{print $1}' <<<"$out" | sort | tr '\n' ' ')
check 'newest session: running workers only' '[ "$ids" = "bgdone bgwait handoff pending result stalled " ]'
check 'HANDOFF at 410k' 'row handoff | grep -q "ctx=410k.*HANDOFF"'
check 'STALLED after 25 idle minutes' 'row stalled | grep -q "idle=25m.*STALLED"'
check 'fresh worker has no flag' '! row pending | grep -qE "STALLED|HANDOFF"'
check 'tier, running minutes' 'row pending | grep -q "worker-high.*ctx=200k.*ran=30m.*idle=1m"'
check 'waiting on its own background job' 'row bgwait | grep -q waiting-bg'
check 'a pass records finished workers as runs in threads' '"$repo/dotfiles/bin/threads" run-ids | grep -qx finished'
check 'a pass makes a running worker the holder of its Item' '"$repo/dotfiles/bin/threads" list | grep -qE "^smashcraft#7 +pending "'

out=$("$sweep" --session old-session)
check '--session picks that session' '[ "$(awk "{print \$1}" <<<"$out")" = oldtool ]'

out=$(timeout 10 "$sweep" --wait)
status=$?
check '--wait exits at once with the flagged table' '[ "$status" -eq 0 ] && row handoff | grep -q HANDOFF'

out=$("$sweep" --session missing 2>&1)
status=$?
check 'unknown session fails' '[ "$status" -eq 1 ]'

printf 'worker-sweep: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
