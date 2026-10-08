#!/usr/bin/env bash
# Checks are eval strings, expanded when they run.
# shellcheck disable=SC2016
# threads against a scratch database and a fake gh: claims, handoffs, ready
# from GitHub's open issues and blocked-by, run ingest, parallel writers.
set -uo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
threads=$repo/dotfiles/bin/threads
scratch=$(mktemp -d "${TMPDIR:-/tmp}/threads-test.XXXXXX")
trap 'rm -rf "${scratch:?}"' EXIT
export THREADS_DB=$scratch/threads.db GH_TRACE=$scratch/gh.trace PATH=$scratch/bin:$PATH

# smashcraft: #1 blocked by open #2, #2 open, #3 open, #4 blocked by closed #5.
mkdir "$scratch/bin"
cat >"$scratch/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_TRACE"
issue() { printf '{"number":%s,"title":"T%s","blockedBy":{"nodes":[%s]}}' "$1" "$1" "${2:-}"; }
blocker() { printf '{"number":%s,"state":"%s","repository":{"nameWithOwner":"tompassarelli/smashcraft"}}' "$1" "$2"; }
case "$*" in
  *name=smashcraft*)
    nodes="$(issue 1 "$(blocker 2 OPEN)"),$(issue 2),$(issue 3),$(issue 4 "$(blocker 5 CLOSED)")" ;;
  *) nodes="" ;;
esac
printf '{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[%s]}}}}\n' "$nodes"
GH
chmod +x "$scratch/bin/gh"

pass=0 fail=0 out=""
check() {
  if eval "$2"; then pass=$((pass + 1)); printf 'PASS  %s\n' "$1"
  else fail=$((fail + 1)); printf 'FAIL  %s\n%s\n' "$1" "$out"; fi
}
t() { "$threads" "$@" 2>&1; }

t claim smashcraft#3 --by alice >/dev/null
out=$(t claim smashcraft#3 --by bob); status=$?
check '[spec] a claim on an issue someone else holds is refused' \
  '[ "$status" -eq 1 ] && grep -q "already owned by alice" <<<"$out"'

out=$(t release smashcraft#3 --by alice --to bob; t list)
check '[spec] release --to hands the issue over and records the handoff' \
  'grep -qE "^smashcraft#3 +bob" <<<"$out" && [ "$(sqlite3 "$THREADS_DB" "select data from events where kind = '"'handoff'"'")" = '"'"'{"from": "alice", "to": "bob"}'"'"' ]'

out=$(t ready)
check '[spec] ready lists open issues minus open blockers and held issues' \
  '[ "$(cut -f1 <<<"$out" | tr "\n" " ")" = "smashcraft#2 smashcraft#4 " ]'
t ready >/dev/null
check '[spec] ready asks GitHub once per repo per minute' \
  '[ "$(grep -c "name=smashcraft" "$GH_TRACE")" -eq 1 ]'

brief=$'Goal: x\nItem: tompassarelli/smashcraft#3. Follows: a111. Category: Tooling.\nETA 45 min.'
printf '%s\n' \
  "$(jq -cn '{id:"a111",ended:"2026-10-08T01:00:00Z",tier:"high",actual_min:30,eta_min:20,tokens:1000,outcome:"handoff",note:"~/h/a111.md",brief:"Item: smashcraft#3"}')" \
  "$(jq -cn --arg b "$brief" '{id:"a222",ended:"2026-10-08T02:00:00Z",tier:"xhigh",actual_min:50,eta_min:45,tokens:2000,outcome:"done",brief:$b}')" |
  "$threads" ingest 2>/dev/null
out=$(t show smashcraft#3; t summary)
check '[spec] runs take Item, Follows and Category from the brief; a new agent is a change of hands' \
  'grep -q "a222 xhigh follows a111  50m/45m ETA  done" <<<"$out" && grep -q "handoff  a111 -> a222" <<<"$out" && grep -q "note ~/h/a111.md" <<<"$out" && grep -qE "^tooling +xhigh +1 +1 +100%" <<<"$out"'

# 40 processes, each making 25 claims through threads' own entry point.
for w in $(seq 1 40); do
  python3 - "$threads" "$w" <<'PY' >/dev/null &
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("threads", sys.argv[1])
spec = importlib.util.spec_from_loader("threads", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
for n in range(25):
    assert mod.main(["claim", f"wisp#{int(sys.argv[2]) * 100 + n}", "--by", f"w{sys.argv[2]}"]) == 0
PY
done
wait
out=$(sqlite3 "$THREADS_DB" "select count(*) from claims where item like 'wisp#%'")
check '[invariant] 40 writers x 25 parallel writes keep all 1000' '[ "$out" = 1000 ]'

printf 'threads: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
