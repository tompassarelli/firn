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
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
iss() { printf '{"number":%s,"title":"T%s","labels":[%s],"body":"%s","comments":[%s]}' "$@"; }
lab() { printf '{"name":"priority:%s"}' "$1"; }
case "$*" in
  "issue list -R tompassarelli/smashcraft"*)
    printf '[%s]\n' "$(iss 15 15 "$(lab next)" '- [ ] a' ''),$(iss 16 16 '' '- [ ] a' ''),$(iss 17 17 "$(lab now)" '- [x] done' ''),$(iss 18 18 "$(lab later)" '- [ ] a' ''),$(iss 10 10 "$(lab now)" '- [ ] a\n- [ ] b' ''),$(iss 11 11 "$(lab now)" '- [ ] a' ''),$(iss 12 12 "$(lab now)" '- [ ] a' ''),$(iss 13 13 "$(lab now)" '- [ ] a' "{\"body\":\"Blocked: needs Tom\",\"createdAt\":\"$now\"}"),$(iss 14 14 "$(lab now)" '- [ ] a' '')"
    exit ;;
  "issue list -R tompassarelli/wisp"*) printf '[%s]\n' "$(iss 20 20 "$(lab now)" '- [ ] a' '')"; exit ;;
  *refPrefix*name=smashcraft*)
    printf '{"data":{"repository":{"refs":{"nodes":[{"name":"main","target":{"committedDate":"%s"}},{"name":"claude/fix-12","target":{"committedDate":"%s"}},{"name":"claude/other","target":{"committedDate":"%s"}}]}}}}\n' "$now" "$now" "$now"
    exit ;;
  *refPrefix*) printf '{"data":{"repository":{"refs":{"nodes":[]}}}}\n'; exit ;;
  *compare*)
    printf '{"data":{"repository":{"defaultBranchRef":{"b0":{"commits":{"nodes":[]}},"b1":{"commits":{"nodes":[{"message":"Tidy\\n\\nUnlike #14, this leaves the ledger alone."}]}}}}}}\n'
    exit ;;
esac
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

out=$(t claim nixos-config#9 --by alice >/dev/null; t claim tompassarelli/firn#9 --by bob)
check '[spec] a checkout alias and the GitHub name are the same issue' \
  'grep -q "firn#9 is already owned by alice" <<<"$out"'
t release firn#9 --by alice >/dev/null

out=$(t ready)
check '[spec] ready lists open issues minus open blockers and held issues' \
  '[ "$(cut -f1 <<<"$out" | tr "\n" " ")" = "smashcraft#2 smashcraft#4 " ]'
t ready >/dev/null
check '[spec] ready asks GitHub once per repo per minute' \
  '[ "$(grep -c "name=smashcraft" "$GH_TRACE")" -eq 1 ]'

brief=$'Goal: x\nItem: tompassarelli/smashcraft#3. Follows: a111. Category: Tooling. Arm: escalate.\nETA 45 min.'
printf '%s\n' \
  "$(jq -cn '{id:"a111",ended:"2026-10-08T01:00:00Z",tier:"high",actual_min:30,eta_min:20,tokens:1000,outcome:"handoff",note:"~/h/a111.md",brief:"Item: smashcraft#3"}')" \
  "$(jq -cn --arg b "$brief" '{id:"a222",ended:"2026-10-08T02:00:00Z",tier:"xhigh",actual_min:50,eta_min:45,tokens:2000,outcome:"done",brief:$b}')" |
  "$threads" ingest 2>/dev/null
out=$(t show smashcraft#3; t summary)
check '[spec] runs take Item, Follows, Category and Arm from the brief; a new agent is a change of hands' \
  'grep -q "a222 xhigh follows a111  50m/45m ETA  done" <<<"$out" && grep -q "handoff  a111 -> a222" <<<"$out" && grep -q "note ~/h/a111.md" <<<"$out" && grep -qE "^tooling +xhigh +escalate +1 +1 +100%" <<<"$out"'

row() { jq -cn "$@"; }
row '{id:"a333",status:"running",tier:"medium",started:"2026-10-08T03:00:00Z",eta_min:30,brief:"Item: smashcraft#4"}' |
  "$threads" ingest 2>/dev/null
out=$(t list)
check '[spec] a running worker whose brief has Item: holds the issue with no claim command' \
  'grep -qE "^smashcraft#4 +a333 .* 30m" <<<"$out"'
row --arg s "$(date -u -d '45 minutes ago' +%Y-%m-%dT%H:%M:%S.000Z)" \
  '{id:"a444",status:"running",tier:"high",started:$s,eta_min:20,brief:"Item: smashcraft#2"}' | "$threads" ingest 2>/dev/null
out=$(t list)
check '[spec] the clock runs from when the worker started, and past 2x ETA it is overdue' \
  'grep -qE "^smashcraft#2 +a444 +4[56]m +20m +OVERDUE" <<<"$out"'
out=$(t ready)
check '[spec] an issue a running worker holds is not ready' '! grep -q "^smashcraft#4" <<<"$out"'
row '{id:"a333",status:"finished",ended:"2026-10-08T03:20:00Z",tier:"medium",actual_min:20,tokens:1,outcome:"done",brief:"Item: smashcraft#4"}' |
  "$threads" ingest 2>/dev/null
out=$(t list)
check '[spec] the worker finishing releases the issue' '! grep -q "^smashcraft#4" <<<"$out"'

# smashcraft#5 is closed (not in the open set): a medium run, then a high one after it.
{ row '{id:"b1",ended:"2026-10-08T04:00:00Z",tier:"medium",actual_min:10,tokens:3000,outcome:"not done",brief:"Item: smashcraft#5 Category: bug-known-cause"}'
  row '{id:"b2",ended:"2026-10-08T05:00:00Z",tier:"high",actual_min:10,tokens:5000,outcome:"done",brief:"Item: smashcraft#5 Follows: b1 Category: frobnicate"}'
} | "$threads" ingest 2>/dev/null
out=$(t summary)
check '[spec] a category outside the fixed list counts as unknown' 'grep -qE "^unknown +high +1 " <<<"$out"'
check '[spec] closure groups by the first run: issues, closed, runs and tokens per closed issue, escalations' \
  'grep -qE "^bug-known-cause +medium +1 +1 +2.0 +8k +100%" <<<"$out"'

t claim smashcraft#11 --by alice --eta 30 >/dev/null
t block wisp#20 waits on smashcraft#13 >/dev/null
out=$(t unowned)
check '[spec] unowned: priority:now first, then unlabeled, next, later; owner from a claim or a branch name, blocked from a comment or a block record' \
  '[ "$(cut -f1-4 <<<"$out")" = "$(printf "%s\n" "smashcraft#10	priority:now	UNOWNED	2" "smashcraft#11	priority:now	alice	1" "smashcraft#12	priority:now	branch:claude/fix-12	1" "smashcraft#13	priority:now	blocked:needs Tom	1" "smashcraft#14	priority:now	UNOWNED	1" "wisp#20	priority:now	blocked:waits on smashcraft#13	1" "smashcraft#16	-	UNOWNED	1" "smashcraft#15	priority:next	UNOWNED	1" "smashcraft#18	priority:later	UNOWNED	1" "priority:now unowned=2 blocked=2 owned=2")" ]'

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
