#!/usr/bin/env bash
# Checks are eval strings, expanded when they run.
# shellcheck disable=SC2016
# threads against a scratch database: ownership, handoffs, needs, run
# ingest from briefs, and parallel writers.
set -uo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
threads=$repo/dotfiles/bin/threads
scratch=$(mktemp -d "${TMPDIR:-/tmp}/threads-test.XXXXXX")
trap 'rm -rf "${scratch:?}"' EXIT
export THREADS_DB=$scratch/threads.db

pass=0 fail=0 out=""
check() {
  if eval "$2"; then pass=$((pass + 1)); printf 'PASS  %s\n' "$1"
  else fail=$((fail + 1)); printf 'FAIL  %s\n%s\n' "$1" "$out"; fi
}
t() { "$threads" "$@" 2>&1; }

t add base "Base" >/dev/null
t add top "Top" --needs base >/dev/null
t add free "Free" >/dev/null
t claim base --by alice >/dev/null

out=$(t claim base --by bob); status=$?
check '[spec] a claim on an item someone else owns is refused' \
  '[ "$status" -eq 1 ] && grep -q "already owned by alice" <<<"$out"'

out=$(t release base --by alice --to bob; t show base)
check '[spec] release --to hands the item over and records the handoff' \
  'grep -q "owner: bob" <<<"$out" && grep -q "handoff  alice -> bob" <<<"$out"'

out=$(t ready)
check '[spec] ready excludes owned items and items needing an open item' \
  '[ "$(cut -f1 <<<"$out" | tr "\n" " ")" = "free " ]'

t close base --by bob --outcome shipped >/dev/null
out=$(t ready)
check '[spec] closing the need makes the item ready' \
  '[ "$(cut -f1 <<<"$out" | sort | tr "\n" " ")" = "free top " ]'

brief=$'Goal: x\nItem: top. Follows: a111. Category: Tooling.\nETA 45 min.'
printf '%s\n' \
  "$(jq -cn '{id:"a111",ended:"2026-10-08T01:00:00Z",tier:"high",actual_min:30,eta_min:20,tokens:1000,outcome:"not done",brief:"Item: top"}')" \
  "$(jq -cn --arg b "$brief" '{id:"a222",ended:"2026-10-08T02:00:00Z",tier:"xhigh",actual_min:50,eta_min:45,tokens:2000,outcome:"done",brief:$b}')" |
  "$threads" ingest 2>/dev/null
out=$(t show top; t summary)
check '[spec] runs take Item, Follows and Category from the brief; a new agent is a change of hands' \
  'grep -q "a222 xhigh follows a111  50m/45m ETA  done" <<<"$out" && grep -q "handoff  a111 -> a222" <<<"$out" && grep -qE "^tooling +xhigh +1 +1 +100%" <<<"$out"'

# 40 processes, each making 25 writes through threads' own entry point.
for w in $(seq 1 40); do
  python3 - "$threads" "$w" <<'PY' >/dev/null &
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("threads", sys.argv[1])
spec = importlib.util.spec_from_loader("threads", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
for n in range(25):
    assert mod.main(["add", f"p{sys.argv[2]}-{n}", "parallel"]) == 0
PY
done
wait
out=$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select count(*) from items where id like \"p%\"").fetchone()[0])' "$THREADS_DB")
check '[invariant] 40 writers x 25 parallel writes keep all 1000' '[ "$out" = 1000 ]'

printf 'threads: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
