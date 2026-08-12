#!/usr/bin/env bash
# Behavioural tests for dotfiles/bin/convo. Uses a synthetic corpus under a
# temp CONVO_ROOT/CONVO_STATE, so the real index is never touched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONVO="$ROOT/dotfiles/bin/convo"
fixture="$(mktemp -d)"
trap 'rm -rf "${fixture:?}"' EXIT

export CONVO_ROOT="$fixture/corpus"
export CONVO_STATE="$fixture/state"
adir="$CONVO_ROOT/anthropic/acct/projects/-home-tom-code-demo"
odir="$CONVO_ROOT/openai/acct/sessions/2026/08/12"
mkdir -p "$adir" "$odir" "$CONVO_STATE"

fail() { printf 'convo.test.sh:%s: %s\n' "${BASH_LINENO[0]}" "$1" >&2; exit 1; }
has() { grep -q -- "$2" <<<"$1" || fail "expected /$2/ in: $1"; }
hasnt() { if grep -q -- "$2" <<<"$1"; then fail "unexpected /$2/ in: $1"; fi; }
# convo exits non-zero when nothing matches; assert that, without tripping set -e
nomatch() { if "$CONVO" --color=never "$1" >/dev/null 2>&1; then fail "$2"; fi; }

SID=11111111-2222-3333-4444-555555555555

# ---- fixture: one Claude transcript, one Codex rollout -------------------
python3 - "$adir/$SID.jsonl" "$odir/rollout-x.jsonl" "$SID" <<'PY'
import json, sys
apath, opath, sid = sys.argv[1:4]
def a(role, text, ts):
    return json.dumps({"type": role, "sessionId": sid, "timestamp": ts,
                       "cwd": "/synthetic/demo", "gitBranch": "main",
                       "message": {"role": role,
                                   "content": [{"type": "text", "text": text}]}})
with open(apath, "w") as f:
    f.write(json.dumps({"type": "ai-title", "aiTitle": "Demo session",
                        "sessionId": sid}) + "\n")
    f.write(a("user", "how do we handle QUARKFISH routing", "2026-08-01T10:00:00Z") + "\n")
    f.write(a("assistant", "QUARKFISH routing goes through the dispatcher",
              "2026-08-01T10:00:05Z") + "\n")
    # tool_result must not be indexed: it is machine output, not conversation
    f.write(json.dumps({"type": "user", "sessionId": sid,
                        "timestamp": "2026-08-01T10:00:06Z",
                        "message": {"role": "user", "content": [
                            {"type": "tool_result",
                             "content": "SECRETOUTPUTTOKEN"}]}}) + "\n")
    # push the file past the head-fingerprint window so that appending to it
    # exercises the real incremental path rather than the small-file reset
    for i in range(40):
        f.write(a("assistant", f"filler line {i} " + "padding " * 12,
                  "2026-08-01T10:%02d:00Z" % (10 + i)) + "\n")
with open(opath, "w") as f:
    f.write(json.dumps({"type": "session_meta", "timestamp": "2026-08-02T09:00:00Z",
                        "payload": {"id": "99999999-8888-7777-6666-555555555555",
                                    "cwd": "/synthetic/demo"}}) + "\n")
    f.write(json.dumps({"type": "response_item", "timestamp": "2026-08-02T09:00:01Z",
                        "payload": {"type": "message", "role": "assistant",
                                    "content": [{"type": "output_text",
                                                 "text": "codex says WOMBATSTONE"}]}}) + "\n")
    # a compacted replay must not be double-indexed
    f.write(json.dumps({"type": "compacted", "timestamp": "2026-08-02T09:00:02Z",
                        "payload": {"replacement_history": [
                            {"type": "message", "role": "assistant",
                             "content": [{"type": "output_text",
                                          "text": "codex says WOMBATSTONE"}]}]}}) + "\n")
    # developer boilerplate must not be indexed
    f.write(json.dumps({"type": "response_item", "timestamp": "2026-08-02T09:00:03Z",
                        "payload": {"type": "message", "role": "developer",
                                    "content": [{"type": "input_text",
                                                 "text": "BOILERPLATETOKEN"}]}}) + "\n")
PY

"$CONVO" index >/dev/null

# ---- search finds both providers ----------------------------------------
out="$("$CONVO" --color=never QUARKFISH -n 5)"
has "$out" QUARKFISH
has "$out" "Demo session"
has "$out" "demo"
out="$("$CONVO" --color=never WOMBATSTONE -n 5)"
has "$out" WOMBATSTONE
[ "$(grep -c WOMBATSTONE <<<"$out")" -eq 1 ] || fail "compacted replay was double-indexed"

# ---- machine output and injected boilerplate stay out of the index -------
nomatch SECRETOUTPUTTOKEN "tool_result was indexed"
nomatch BOILERPLATETOKEN "developer msg was indexed"

# ---- reported path:line is exact ----------------------------------------
loc="$("$CONVO" --color=never QUARKFISH -n 1 --json | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print(r["path"], r["line"])')"
path="${loc% *}"; line="${loc##* }"
sed -n "${line}p" "$path" | grep -q QUARKFISH || fail "line $line of $path lacks the match"

# ---- incremental: only new bytes, no duplicates --------------------------
before="$("$CONVO" status | awk '/^messages/{print $2}')"
out="$("$CONVO" index)"
has "$out" "from 0 changed files"
python3 - "$adir/$SID.jsonl" "$SID" <<'PY'
import json, sys
p, sid = sys.argv[1:3]
open(p, "a").write(json.dumps({"type": "assistant", "sessionId": sid,
    "timestamp": "2026-08-01T11:00:00Z", "cwd": "/synthetic/demo",
    "message": {"role": "assistant",
                "content": [{"type": "text", "text": "later ZORBLAX note"}]}}) + "\n")
PY
out="$("$CONVO" index)"
has "$out" "indexed 1 messages from 1 changed files"
has "$("$CONVO" --color=never ZORBLAX)" ZORBLAX
after="$("$CONVO" status | awk '/^messages/{print $2}')"
[ "$after" -eq "$((before + 1))" ] || fail "expected $((before+1)) msgs, got $after"

# ---- oversized line is skipped, its neighbours are not -------------------
python3 - "$adir/giant.jsonl" <<'PY'
import json, sys
sid = "aaaaaaaa-0000-0000-0000-000000000000"
def rec(text, ts):
    return json.dumps({"type": "assistant", "sessionId": sid, "timestamp": ts,
                       "cwd": "/synthetic/demo",
                       "message": {"role": "assistant",
                                   "content": [{"type": "text", "text": text}]}})
with open(sys.argv[1], "w") as f:
    f.write(rec("GIANTPRE marker", "2026-08-03T10:00:00Z") + "\n")
    f.write(rec("X" * (3 << 20), "2026-08-03T10:00:01Z") + "\n")
    f.write(rec("GIANTPOST marker", "2026-08-03T10:00:02Z") + "\n")
PY
"$CONVO" index >/dev/null
has "$("$CONVO" --color=never GIANTPRE)" GIANTPRE
has "$("$CONVO" --color=never GIANTPOST)" GIANTPOST

# ---- a torn trailing line is not indexed until it is complete ------------
torn="$adir/torn.jsonl"
printf '%s' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"TORNTOKEN' >"$torn"
"$CONVO" index >/dev/null
nomatch TORNTOKEN "indexed a torn line"
python3 - "$torn" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({"type": "assistant",
    "sessionId": "bbbbbbbb-0000-0000-0000-000000000000",
    "timestamp": "2026-08-04T10:00:00Z", "cwd": "/synthetic/demo",
    "message": {"role": "assistant",
                "content": [{"type": "text", "text": "TORNTOKEN complete"}]}}) + "\n")
PY
"$CONVO" index >/dev/null
has "$("$CONVO" --color=never TORNTOKEN)" TORNTOKEN

# ---- rewritten/truncated file is reindexed from scratch, not appended ----
python3 - "$adir/torn.jsonl" <<'PY'
import json, sys
open(sys.argv[1], "w").write(json.dumps({"type": "assistant",
    "sessionId": "bbbbbbbb-0000-0000-0000-000000000000",
    "timestamp": "2026-08-04T11:00:00Z", "cwd": "/synthetic/demo",
    "message": {"role": "assistant",
                "content": [{"type": "text", "text": "REPLACEDTOKEN only"}]}}) + "\n")
PY
"$CONVO" index >/dev/null
has "$("$CONVO" --color=never REPLACEDTOKEN)" REPLACEDTOKEN
nomatch TORNTOKEN "stale rows survived a rewrite"

# ---- session lookup resolves without any scan ----------------------------
out="$("$CONVO" --color=never session "$SID")"
has "$out" "$SID.jsonl"
has "$out" "Demo session"

# ---- exact-phrase mode ---------------------------------------------------
has "$("$CONVO" --color=never -x 'QUARKFISH routing goes through')" QUARKFISH

# ---- filters -------------------------------------------------------------
has "$("$CONVO" --color=never QUARKFISH -r user)" "user ·"
out="$("$CONVO" --color=never QUARKFISH -r assistant)"
hasnt "$out" "user ·"

# ---- the index is self-sufficient: a vanished source still renders --------
# This is the property every storage decision below rests on. If a snippet
# still needed the transcript, no transcript could ever be compressed.
mkrec() { # <file> <token> <ts>
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
path, token, ts = sys.argv[1:4]
with open(path, "w") as f:
    for i in range(3):
        f.write(json.dumps({"type": "assistant", "sessionId":
                            "cccccccc-0000-0000-0000-%012d" % i,
                            "timestamp": ts, "cwd": "/synthetic/demo",
                            "message": {"role": "assistant", "content": [
                                {"type": "text",
                                 "text": f"{token} record {i} " + "pad " * 30}]}})
                + "\n")
PY
}

mkrec "$adir/orphan.jsonl" ORPHANTOKEN 2026-08-05T10:00:00Z
"$CONVO" index >/dev/null
rm -f "$adir/orphan.jsonl"
out="$("$CONVO" --color=never ORPHANTOKEN -n 1)"
has "$out" "ORPHANTOKEN record"
has "$out" "orphan.jsonl:1"

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

# a file some process still holds open is not closed, whatever its mtime says
sleep 120 9<"$held" &
holder=$!
# `|| true` is load-bearing: errexit is live inside an EXIT trap, so a kill of
# an already-reaped holder would abandon the cleanup and exit 1 on a green run.
trap 'kill "$holder" 2>/dev/null || true; rm -rf "${fixture:?}"' EXIT

# ---- dry run reports and changes nothing ---------------------------------
out="$("$CONVO" compress --dry-run --color=never)"
has "$out" "projected"
has "$out" "1 open by a process"
[ -f "$cold" ] || fail "--dry-run compressed a file"
[ ! -f "$cold.zst" ] || fail "--dry-run wrote an archive"

# ---- the sweep compresses only what is provably closed -------------------
printf '%s\n' "{\"version\":\"north:agent-roster:v1\",\"agents\":[{\"uuid\":\"$RSID\"}]}" \
  >"$fixture/roster.json"
"$CONVO" compress -q --color=never >/dev/null
[ -f "$cold.zst" ] && [ ! -f "$cold" ] || fail "a closed transcript was not compressed"
[ -f "$warm" ] && [ ! -f "$warm.zst" ] || fail "a warm transcript was compressed"
[ -f "$held" ] && [ ! -f "$held.zst" ] || fail "an OPEN transcript was compressed"
[ -f "$rostered" ] && [ ! -f "$rostered.zst" ] ||
  fail "a transcript the coordinator names was compressed"
kill "$holder" 2>/dev/null || true

# the archive is the original, byte for byte
zstd -dcq "$cold.zst" | cmp -s - "$fixture/cold.orig" || fail "archive lost bytes"

# ---- a compressed source stays searchable, under its .jsonl provenance ---
out="$("$CONVO" --color=never COLDTOKEN -n 1)"
has "$out" "COLDTOKEN record"
has "$out" "cold.jsonl:1"
hasnt "$out" ".zst"

# adopting a compressed source must not re-read it
has "$("$CONVO" index)" "from 0 changed files"
# and the sweep is idempotent
out="$("$CONVO" compress --dry-run --color=never)"
hasnt "$out" "cold.jsonl"

# ---- an archive that was never seen uncompressed is indexed from scratch --
mkrec "$adir/arch.jsonl" ARCHTOKEN 2026-08-06T10:00:00Z
zstd -q --long=27 --rm "$adir/arch.jsonl"
has "$("$CONVO" --color=never ARCHTOKEN)" "ARCHTOKEN record"

# ---- when both forms exist the uncompressed one wins ---------------------
mkrec "$adir/dual.jsonl" STALEZSTTOKEN 2026-08-06T10:00:00Z
zstd -q --long=27 "$adir/dual.jsonl" && rm -f "$adir/dual.jsonl"
mkrec "$adir/dual.jsonl" DUALTOKEN 2026-08-06T10:00:00Z
"$CONVO" index >/dev/null
has "$("$CONVO" --color=never DUALTOKEN)" "DUALTOKEN record"
nomatch STALEZSTTOKEN "the archive shadowed the live transcript"

# ---- restore puts the transcript back ------------------------------------
"$CONVO" restore "$cold.zst" >/dev/null
[ -f "$cold" ] && [ ! -f "$cold.zst" ] || fail "restore did not replace the archive"
cmp -s "$cold" "$fixture/cold.orig" || fail "restore lost bytes"
has "$("$CONVO" index)" "from 0 changed files"
has "$("$CONVO" --color=never COLDTOKEN -n 1)" "COLDTOKEN record"

echo "convo.test.sh: all assertions passed"
