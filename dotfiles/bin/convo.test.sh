#!/usr/bin/env bash
# convo: properties over the pure core, then one recorded scenario per boundary
# (Claude and Codex JSONL, zstd archives, SQLite, the lock) on a synthetic
# corpus under temp CONVO_ROOT/CONVO_STATE, so the real index is never touched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONVO="$ROOT/dotfiles/bin/convo"
unset CODEX_HOME NORTH_CODEX_POOLED_HOME CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture:?}"' EXIT
fail() { printf 'convo.test.sh:%s: %s\n' "${BASH_LINENO[0]}" "$1" >&2; exit 1; }

runtime_home="$fixture/runtime-home"
mkdir -p "$runtime_home/.local/libexec/convo"
test_python="${CONVO_TEST_PYTHON:-$(command -v python3 || true)}"
[ -n "$test_python" ] || fail 'set CONVO_TEST_PYTHON to run outside a Python-enabled test environment'
ln -s "$test_python" "$runtime_home/.local/libexec/convo/python3"
env -i HOME="$runtime_home" PATH=/no-ambient-python "$CONVO" --help >/dev/null
grep -Fq '".local/libexec/convo/python3": {source: "{package-text(package(path(python3)))}/bin/python3"}' \
  "$ROOT/native/nix/bash.clause"
grep -Fq '".local/libexec/convo/python3" = { "source" = (("" + (builtins."toString" (pkgs."python3"))) + "/bin/python3"); };' \
  "$ROOT/modules/bash/default.nix"
mkdir -p "$fixture/test-bin"
ln -s "$test_python" "$fixture/test-bin/python3"
export PATH="$fixture/test-bin:$PATH"
export CONVO_PYTHON="$test_python"

# ---- properties over the pure core (fixed seed) ----------------------------
python3 - "$CONVO" <<'PY'
import importlib.machinery, importlib.util, io, random, sqlite3, sys
loader = importlib.machinery.SourceFileLoader("convo", sys.argv[1])
convo = importlib.util.module_from_spec(importlib.util.spec_from_loader("convo", loader))
loader.exec_module(convo)
rng = random.Random(20261010)
WORDS = ["deck", "pink", "c289-ko-bottom", "tools/x.ts", "AND", "OR", "NOT", "(", ")",
         '"', "*", "orch*", "naïve", "7,200/7,200", "--render", "a.b", ":", "^", "-", "'"]

db = sqlite3.connect(":memory:")
db.execute("CREATE VIRTUAL TABLE t USING fts5(text, tokenize='porter unicode61 remove_diacritics 2')")
db.execute("INSERT INTO t VALUES('deck pink c289 ko bottom tools x ts naive')")
for _ in range(3000):
    text = " ".join(rng.choice(WORDS) for _ in range(rng.randint(0, 6)))
    plan = convo.plan_query(text, exact=rng.random() < 0.2)
    if plan is None:
        assert not convo.WORD.search(text), text
        continue
    ok = False
    for expr in plan.match:
        try:
            db.execute("SELECT rowid FROM t WHERE t MATCH ?", (expr,)).fetchall()
            ok = True
            break
        except sqlite3.OperationalError:
            pass
    assert ok, f"no expression parses for {text!r}: {plan.match}"
    if plan.partial:
        db.execute("SELECT rowid FROM t WHERE t MATCH ?", (plan.partial,)).fetchall()

convo.LINE_CAP = 40
for _ in range(400):
    lines = [bytes(rng.choice(b"ab{}\" ") for _ in range(rng.randint(0, 70)))
             for _ in range(rng.randint(0, 12))]
    data = b"\n".join(lines) + (b"\n" if rng.random() < 0.5 else b"")
    got = list(convo.scan_lines(io.BytesIO(data), 0, chunk=rng.randint(1, 64)))
    want, start = [], 0
    for ln in data.split(b"\n")[:-1]:
        want.append((start, start + len(ln) + 1, ln if len(ln) <= 40 else None))
        start += len(ln) + 1
    assert got == want, (data, got, want)

for _ in range(500):
    words = [rng.choice(["alpha", "beta", "gamma", "tests", "x" * rng.randint(1, 30)])
             for _ in range(rng.randint(1, 120))]
    text, term = " ".join(words), rng.choice(words)
    snip = convo.snippet(text, [term], 80)
    assert len(snip) <= 82, snip
    assert convo.stem(term) in snip.lower(), (term, snip)

calls = {"role": "tool", "text": "Bash command=convo deck pink"}
for _ in range(300):
    hits = [dict(rng.choice([calls, {"role": "assistant", "text": "deck"},
                             {"role": "user", "text": "pink deck"}]),
                 id=i, bm25=-rng.random() * 10, session=rng.choice("ABCD"))
            for i in range(rng.randint(1, 30))]
    groups = convo.rank_sessions(hits, ["deck"], frozenset("A"))
    order = [g["session"] for g in groups]
    assert len(order) == len(set(order))
    assert "A" not in order[:-1], order
    assert sum(g["hits"] for g in groups) == sum(not convo.is_convo_call(h) for h in hits)
    assert all(not convo.is_convo_call(g["best"]) for g in groups)
print("convo core properties: ok")
PY

export CONVO_ROOT="$fixture/corpus"
export CONVO_STATE="$fixture/state"
adir="$CONVO_ROOT/openai/acct/sessions/2026/08/01"
odir="$CONVO_ROOT/openai/acct/sessions/2026/08/12"
mkdir -p "$adir" "$odir" "$CONVO_STATE"

has() { grep -q -- "$2" <<<"$1" || fail "expected /$2/ in: $1"; }
hasnt() { if grep -q -- "$2" <<<"$1"; then fail "unexpected /$2/ in: $1"; fi; }
nomatch() { local rc=0; "$CONVO" --color=never "$1" >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 1 ] || fail "$2 (exit $rc)"; }
q() { "$CONVO" --color=never "$@"; }

set +e
out="$(q ANYTHING 2>&1)"; rc=$?
set -e
[ "$rc" -eq 2 ] || fail "a query without an index returned $rc"
has "$out" "convo index"

SID=11111111-2222-3333-4444-555555555555

# ---- fixture: two Codex rollouts -----------------------------------------
python3 - "$adir/$SID.jsonl" "$odir/rollout-x.jsonl" "$SID" <<'PY'
import json, sys
apath, opath, sid = sys.argv[1:4]
def a(role, text, ts):
    block = "input_text" if role == "user" else "output_text"
    return json.dumps({"type": "response_item", "timestamp": ts,
                       "payload": {"type": "message", "role": role,
                                   "content": [{"type": block, "text": text}]}})
with open(apath, "w") as f:
    f.write(json.dumps({"type": "session_meta", "timestamp": "2026-08-01T09:59:00Z",
                        "payload": {"id": sid, "cwd": "/synthetic/demo",
                                    "agent_nickname": "Demo session"}}) + "\n")
    f.write(a("user", "how do we handle QUARKFISH routing", "2026-08-01T10:00:00Z") + "\n")
    f.write(a("assistant", "QUARKFISH routing goes through the dispatcher",
              "2026-08-01T10:00:05Z") + "\n")
    f.write(json.dumps({"type": "response_item", "timestamp": "2026-08-01T10:00:06Z",
                        "payload": {"type": "custom_tool_call_output",
                                    "output": "SECRETOUTPUTTOKEN"}}) + "\n")
    f.write(a("user", "<environment_context> INJECTEDTOKEN </environment_context>",
              "2026-08-01T10:00:07Z") + "\n")
    f.write(json.dumps({"type": "response_item", "timestamp": "2026-08-01T10:00:08Z",
                        "payload": {"type": "function_call", "name": "exec_command",
                                    "arguments": json.dumps({"cmd": "make c289-ko-bottom"})}}) + "\n")
    for i in range(40):
        f.write(a("assistant", f"filler line {i} " + "padding " * 12,
                  "2026-08-01T10:%02d:00Z" % (10 + i)) + "\n")
with open(opath, "w") as f:
    f.write(json.dumps({"type": "session_meta", "timestamp": "2026-08-02T09:00:00Z",
                        "payload": {"id": "99999999-8888-7777-6666-555555555555",
                                    "cwd": "/synthetic/demo"}}) + "\n")
    f.write(a("assistant", "codex says WOMBATSTONE", "2026-08-02T09:00:01Z") + "\n")
    f.write(a("assistant", "QUARKFISH routing goes through the dispatcher",
              "2026-08-02T09:00:01Z") + "\n")
    f.write(a("assistant", "c289 then ko later bottom", "2026-08-02T09:00:01Z") + "\n")
    f.write(json.dumps({"type": "compacted", "timestamp": "2026-08-02T09:00:02Z",
                        "payload": {"replacement_history": [
                            {"type": "message", "role": "assistant",
                             "content": [{"type": "output_text",
                                          "text": "codex says WOMBATSTONE"}]}]}}) + "\n")
    f.write(json.dumps({"type": "response_item", "timestamp": "2026-08-02T09:00:03Z",
                        "payload": {"type": "message", "role": "developer",
                                    "content": [{"type": "input_text",
                                                 "text": "BOILERPLATETOKEN"}]}}) + "\n")
PY

# ---- fixture: one Claude Code session and its subagent --------------------
CSID=77777777-8888-4999-aaaa-bbbbbbbbbbbb
cdir="$CONVO_ROOT/anthropic/acct/projects/-synthetic-claude"
mkdir -p "$cdir/$CSID/subagents" "$cdir/$CSID/scratchpad"
python3 - "$cdir" "$CSID" <<'PY'
import json, os, sys
d, sid = sys.argv[1:3]
def rec(t, content, ts, **kw):
    return json.dumps({"type": t, "sessionId": sid, "cwd": "/synthetic/claude",
                       "timestamp": ts, "message": {"role": t, "content": content},
                       **kw}, separators=(",", ":")) + "\n"
with open(os.path.join(d, sid + ".jsonl"), "w") as f:
    f.write(json.dumps({"type": "ai-title", "sessionId": sid,
                        "aiTitle": "Claude demo"}) + "\n")
    f.write(rec("user", "please check PELICANGATE status", "2026-08-08T10:00:00Z"))
    f.write(rec("assistant", [
        {"type": "thinking", "thinking": "consider PELICANTHINK"},
        {"type": "text", "text": "PELICANGATE is open"},
        {"type": "tool_use", "id": "t1", "name": "Skill",
         "input": {"skill": "machine-capacity"}},
        {"type": "tool_use", "id": "t2", "name": "Bash",
         "input": {"command": "convo PELICANGATE"}}], "2026-08-08T10:00:05Z"))
    f.write(rec("user", [{"type": "tool_result", "tool_use_id": "t1",
                          "content": "CLAUDETOOLRESULT"}], "2026-08-08T10:00:06Z"))
    f.write(rec("user", "<task-notification> PELICANGATE worker done", "2026-08-08T10:00:07Z"))
with open(os.path.join(d, sid, "subagents", "agent-a1.jsonl"), "w") as f:
    f.write(rec("assistant", [{"type": "text", "text": "subagent says HERONLOOP"}],
                "2026-08-08T10:01:00Z", isSidechain=True))
with open(os.path.join(d, sid, "scratchpad", "notes.jsonl"), "w") as f:
    f.write(rec("assistant", "SCRATCHTOKEN", "2026-08-08T10:02:00Z"))
with open(os.path.join(d, "eval-results.jsonl"), "w") as f:
    f.write(rec("assistant", "SCRATCHTOKEN", "2026-08-08T10:02:00Z"))
PY

"$CONVO" index >/dev/null

# ---- Claude Code transcripts are decoded --------------------------------
out="$(q PELICANGATE)"
has "$out" "Claude demo"
has "$out" "77777777 .*(claude, 3 hits)"
out="$(q -m PELICANGATE)"
has "$out" "user · please check PELICANGATE"
has "$out" "system · <task-notification>"
hasnt "$out" "command=convo"
has "$(q -r user -m PELICANGATE)" "please check"
hasnt "$(q -r user -m PELICANGATE)" "task-notification"
has "$(q -r tool PELICANGATE)" "command=convo"
has "$(q -r thinking PELICANTHINK)" PELICANTHINK
has "$(q -t skill -x 'Skill skill=machine-capacity')" "tool:Skill"
has "$(q HERONLOOP)" "77777777/a1"
has "$(q -s a1 subagent)" HERONLOOP
has "$(q session 7777)" "agent-a1.jsonl"
has "$(q session "$CSID")" "ask · please check PELICANGATE status"
nomatch CLAUDETOOLRESULT "a Claude tool_result was indexed"
nomatch SCRATCHTOKEN "a non-session file was indexed as a transcript"

# ---- the caller's own session ranks last -----------------------------------
out="$(CLAUDE_CODE_SESSION_ID="$CSID" q QUARKFISH PELICANGATE)"
has "$out" "has every word"
first="$(grep -m1 -E '^ *1 ' <<<"$out")"
hasnt "$first" 77777777

# ---- Codex rollouts -------------------------------------------------------
out="$(q QUARKFISH)"
has "$out" "Demo session"
has "$out" "demo"
[ "$(grep -c 'QUARKFISH routing goes' <<<"$out")" -eq 1 ] || fail "a repeated text was indexed twice"
has "$(q -m WOMBATSTONE)" WOMBATSTONE
[ "$(q -m WOMBATSTONE | grep -c WOMBATSTONE)" -eq 1 ] || fail "compacted replay was double-indexed"
has "$(q -r system INJECTEDTOKEN)" INJECTEDTOKEN
nomatch SECRETOUTPUTTOKEN "tool output was indexed"
nomatch BOILERPLATETOKEN "developer message was indexed"
out="$(q -m c289-ko-bottom)"
has "$out" "make c289-ko-bottom"
hasnt "$out" "c289 then ko"
has "$(q -t exec_command make)" "cmd=make c289-ko-bottom"

# ---- a hit opens to its exact source -------------------------------------
read -r id path line < <(q --json -m QUARKFISH routing -r user |
  python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print(r["id"], r["path"], r["line"])')
sed -n "${line}p" "$path" | grep -q QUARKFISH || fail "line $line of $path lacks the match"
out="$(q show "$id" -C 1)"
has "$out" "how do we handle QUARKFISH routing"
has "$out" "↓ .*QUARKFISH routing goes through"
has "$(q show "$id" --json)" '"text": "how do we handle QUARKFISH routing'

# ---- query forms and filters ---------------------------------------------
has "$(q -x 'QUARKFISH routing goes through')" QUARKFISH
has "$(q QUARKFISH -r user -m)" "user ·"
hasnt "$(q QUARKFISH -r assistant -m)" "user ·"
has "$(q --since 3000d -r user)" "how do we handle"
has "$(q --provider claude PELICANGATE)" "Claude demo"
set +e
q --since yesterday QUARKFISH >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -eq 2 ] || fail "an unreadable --since returned $rc"

# ---- incremental: only new bytes, no duplicates --------------------------
before="$("$CONVO" status | awk '/^messages/{print $2}')"
has "$("$CONVO" index)" "from 0 changed files"
python3 - "$adir/$SID.jsonl" <<'PY'
import json, sys
open(sys.argv[1], "a").write(json.dumps({"type": "response_item",
    "timestamp": "2026-08-01T11:00:00Z",
    "payload": {"type": "message", "role": "assistant",
                "content": [{"type": "output_text", "text": "later ZORBLAX note"}]}}) + "\n")
PY
has "$("$CONVO" index)" "indexed 1 messages from 1 changed files"
has "$(q ZORBLAX)" ZORBLAX
after="$("$CONVO" status | awk '/^messages/{print $2}')"
[ "$after" -eq "$((before + 1))" ] || fail "expected $((before+1)) msgs, got $after"

# ---- a rewritten first copy hands its text to the next copy ---------------
has "$(q -m 'QUARKFISH routing goes' -s 99999999)" "99999999"
python3 - "$adir/$SID.jsonl" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({"type": "response_item",
    "timestamp": "2026-08-04T11:00:00Z",
    "payload": {"type": "message", "role": "assistant",
                "content": [{"type": "output_text", "text": "REWRITTENTOKEN only"}]}}) + "\n")
PY
"$CONVO" index >/dev/null
has "$(q REWRITTENTOKEN)" REWRITTENTOKEN
nomatch ZORBLAX "stale rows survived a rewrite"
has "$(q -m 'QUARKFISH routing goes')" "99999999"
python3 - "$adir/$SID.jsonl" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({"type": "response_item",
    "timestamp": "2026-08-04T12:00:00Z",
    "payload": {"type": "message", "role": "assistant",
                "content": [{"type": "output_text", "text": "PAD " * 1200 + "TAILTOKENA"}]}}) + "\n")
PY
"$CONVO" index >/dev/null
has "$(q TAILTOKENA)" TAILTOKENA
python3 - "$adir/$SID.jsonl" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
with open(sys.argv[1], "r+b") as f:
    f.write(data.replace(b"TAILTOKENA", b"TAILTOKENB"))
PY
"$CONVO" index >/dev/null
has "$(q TAILTOKENB)" TAILTOKENB
nomatch TAILTOKENA "a same-length tail rewrite stayed stale"

# ---- oversized and torn lines --------------------------------------------
python3 - "$adir/giant.jsonl" <<'PY'
import json, sys
def rec(text, ts):
    return json.dumps({"type": "response_item", "timestamp": ts,
                       "payload": {"type": "message", "role": "assistant",
                                   "content": [{"type": "output_text", "text": text}]}})
with open(sys.argv[1], "w") as f:
    f.write(rec("GIANTPRE marker", "2026-08-03T10:00:00Z") + "\n")
    f.write(rec("X" * (3 << 20), "2026-08-03T10:00:01Z") + "\n")
    f.write(rec("GIANTPOST marker", "2026-08-03T10:00:02Z") + "\n")
PY
torn="$adir/torn.jsonl"
printf '%s' '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"TORNTOKEN' >"$torn"
"$CONVO" index >/dev/null
has "$(q GIANTPRE)" GIANTPRE
has "$(q GIANTPOST)" GIANTPOST
nomatch TORNTOKEN "indexed a torn line"
printf '%s\n' '"}]}}' >>"$torn"
"$CONVO" index >/dev/null
has "$(q TORNTOKEN)" TORNTOKEN

# ---- the index is self-sufficient: a vanished source still renders --------
mkrec() { # <file> <token> <ts>
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
path, token, ts = sys.argv[1:4]
with open(path, "w") as f:
    for i in range(3):
        f.write(json.dumps({"type": "response_item", "timestamp": ts,
                            "payload": {"type": "message", "role": "assistant",
                                        "content": [{"type": "output_text",
                                                     "text": f"{token} record {i} " + "pad " * 30}]}})
                + "\n")
PY
}
mkrec "$adir/orphan.jsonl" ORPHANTOKEN 2026-08-05T10:00:00Z
"$CONVO" index >/dev/null
rm -f "$adir/orphan.jsonl"
has "$(q ORPHANTOKEN -m -n 1 --json)" 'orphan.jsonl", "line": [123]'

# ---- compression ---------------------------------------------------------
printf '%s\n' '{"version":"north:agent-roster:v1","agents":[]}' >"$fixture/roster.json"
export CONVO_ROSTER_CMD="cat $fixture/roster.json"
RSID=dddddddd-1111-2222-3333-444444444444
cold="$adir/cold.jsonl"; warm="$adir/warm.jsonl"
held="$adir/held.jsonl"; rostered="$adir/$RSID.jsonl"
mkrec "$cold" COLDTOKEN 2026-08-05T10:00:00Z
mkrec "$warm" WARMTOKEN 2026-08-05T10:00:00Z
mkrec "$held" HELDTOKEN 2026-08-05T10:00:00Z
mkrec "$rostered" ROSTEREDTOKEN 2026-08-05T10:00:00Z
cp "$cold" "$fixture/cold.orig"
touch -d '3 days ago' "$cold" "$held" "$rostered"
sleep 120 9<"$held" &
holder=$!
# errexit is live inside an EXIT trap, so a kill of a reaped holder needs || true.
trap 'kill "$holder" 2>/dev/null || true; rm -rf "${fixture:?}"' EXIT

out="$("$CONVO" compress --dry-run --color=never)"
has "$out" "projected"
has "$out" "1 open by a process"
[ -f "$cold" ] && [ ! -f "$cold.zst" ] || fail "--dry-run changed a file"

printf '%s\n' "{\"version\":\"north:agent-roster:v1\",\"agents\":[{\"uuid\":\"$RSID\"}]}" \
  >"$fixture/roster.json"
"$CONVO" compress -q --color=never >/dev/null
[ -f "$cold.zst" ] && [ ! -f "$cold" ] || fail "a closed transcript was not compressed"
[ -f "$warm" ] && [ ! -f "$warm.zst" ] || fail "a warm transcript was compressed"
[ -f "$held" ] && [ ! -f "$held.zst" ] || fail "an OPEN transcript was compressed"
[ -f "$rostered" ] && [ ! -f "$rostered.zst" ] || fail "a transcript the coordinator names was compressed"
kill "$holder" 2>/dev/null || true
zstd -dcq "$cold.zst" | cmp -s - "$fixture/cold.orig" || fail "archive lost bytes"

out="$(q COLDTOKEN -m -n 1 --json)"
has "$out" "cold.jsonl\""
has "$("$CONVO" index)" "from 0 changed files"
hasnt "$("$CONVO" compress --dry-run --color=never)" "cold.jsonl"

mkrec "$adir/arch.jsonl" ARCHTOKEN 2026-08-06T10:00:00Z
zstd -q --long=27 --rm "$adir/arch.jsonl"
has "$(q ARCHTOKEN)" "ARCHTOKEN record"

mkrec "$adir/dual.jsonl" STALEZSTTOKEN 2026-08-06T10:00:00Z
zstd -q --long=27 "$adir/dual.jsonl" && rm -f "$adir/dual.jsonl"
mkrec "$adir/dual.jsonl" DUALTOKEN 2026-08-06T10:00:00Z
"$CONVO" index >/dev/null
has "$(q DUALTOKEN)" "DUALTOKEN record"
nomatch STALEZSTTOKEN "the archive shadowed the live transcript"

"$CONVO" restore "$cold.zst" >/dev/null
[ -f "$cold" ] && [ ! -f "$cold.zst" ] || fail "restore did not replace the archive"
cmp -s "$cold" "$fixture/cold.orig" || fail "restore lost bytes"
has "$("$CONVO" index)" "from 0 changed files"

# ---- configured pooled CODEX_HOME and projected mirror -------------------
unset CONVO_ROOT
HOME="$fixture/home"
export HOME
pooled="$HOME/.local/state/north/codex-pooled"
north_data_name=north-data
data_home="$HOME/code/$north_data_name"
mkdir -p "$data_home/accounts/openai/acct/sessions/2026/08/07" \
         "$pooled/sessions/2026/08/07" "$HOME/.local/state"
ln -s "$pooled" "$data_home/codex-pooled"
export NORTH_CODEX_POOLED_HOME="$data_home/accounts/openai/acct"
export CODEX_HOME="$pooled"
export CONVO_STATE="$fixture/pooled-state"
mkrec "$data_home/accounts/openai/acct/sessions/2026/08/07/account.jsonl" \
  ACCOUNTROOT 2026-08-07T10:00:00Z
ln "$data_home/accounts/openai/acct/sessions/2026/08/07/account.jsonl" \
  "$data_home/accounts/openai/acct/sessions/2026/08/07/account-hardlink.jsonl"
mkrec "$pooled/sessions/2026/08/07/pooled.jsonl" POOLEDROOT 2026-08-07T10:01:00Z
claude_tx="$HOME/.claude/projects/-synthetic-local/$CSID.jsonl"
mkdir -p "${claude_tx%/*}"
python3 - "$claude_tx" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    for i in range(3):
        f.write(json.dumps({"type": "assistant", "timestamp": "2026-08-07T10:02:00Z",
                            "message": {"role": "assistant", "content": [
                                {"type": "text", "text": f"LOCALCLAUDE {i}"}]}}) + "\n")
PY
"$CONVO" index >/dev/null
has "$(q LOCALCLAUDE)" "LOCALCLAUDE"
[ "$(q -m POOLEDROOT | grep -c POOLEDROOT)" -eq 3 ] || fail "pooled mirror duplicated messages"
[ "$(q -m ACCOUNTROOT | grep -c ACCOUNTROOT)" -eq 3 ] || fail "a hardlink duplicated messages"
has "$("$CONVO" status)" "4 reconciled"
before="$("$CONVO" status | awk '/^messages/{print $2}')"
ln "$data_home/accounts/openai/acct/sessions/2026/08/07/account.jsonl" \
  "$data_home/accounts/openai/acct/sessions/2026/08/07/0-account.jsonl"
"$CONVO" index >/dev/null
[ "$("$CONVO" status | awk '/^messages/{print $2}')" -eq "$before" ] ||
  fail "a hardlink added later duplicated messages"
nomatch NOT_IN_ANY_CONFIGURED_ROOT "absent query unexpectedly matched"

set +e
out="$(q -u DEFINITELY_ABSENT_TOKEN 2>&1)"; rc=$?
set -e
[ "$rc" -eq 2 ] || fail "no-update miss returned $rc"
has "$out" "refresh inconclusive (update disabled)"

saved_codex_home="$CODEX_HOME"
export CODEX_HOME="$fixture/missing-codex-home"
set +e
out="$(q DEFINITELY_ABSENT_TOKEN 2>&1)"; rc=$?
set -e
[ "$rc" -eq 2 ] || fail "missing CODEX_HOME returned $rc"
has "$out" "CODEX_HOME is unavailable"
export CODEX_HOME="$saved_codex_home"

# ---- a lock held past the wait cannot become a definitive absence -----------
for sub in search session; do
  ready="$CONVO_STATE/lock-ready"
  rm -f "$ready"
  python3 - "$CONVO_STATE/index-v4.db.lock" "$ready" <<'PY' &
import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_CREAT | os.O_RDWR, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(3)
PY
  locker=$!
  for _ in $(seq 1 50); do [ -f "$ready" ] && break; sleep 0.02; done
  [ -f "$ready" ] || fail "lock holder did not become ready"
  set +e
  out="$(q "$sub" 22222222-3333-4444-5555-666666666666 2>&1)"; rc=$?
  set -e
  wait "$locker"
  [ "$rc" -eq 2 ] || fail "$sub under lock contention returned $rc"
  has "$out" "refresh inconclusive"
done

# ---- a real sweep never compresses a Claude transcript --------------------
cp "$claude_tx" "$fixture/claude.orig"
codex_tx="$pooled/sessions/2026/08/07/pooled.jsonl"
touch -d '3 days ago' "$claude_tx" "$codex_tx"
out="$("$CONVO" compress --color=never)"
has "$out" "never      1 Claude"
[ -f "$codex_tx.zst" ] || fail "an eligible Codex rollout was not compressed"
[ ! -e "$claude_tx.zst" ] || fail "a Claude transcript was compressed"
cmp -s "$claude_tx" "$fixture/claude.orig" || fail "a Claude transcript changed"

echo "convo.test.sh: all assertions passed"
