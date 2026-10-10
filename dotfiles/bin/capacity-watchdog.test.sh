#!/usr/bin/env bash
# Recorded scenario through the decision core: an unleased 5-core tree held
# for 2 minutes is one incident with cgroup, cwd and parent chain; the same
# load in a capacity scope and a 3.9-core tree are not. Git repack outside the
# nightly timer is terminated, inside it is not. Then the real sampler SIGTERMs
# a live fake `git repack` process.
set -uo pipefail
target="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/capacity-watchdog"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/capacity-watchdog-test.XXXXXX")"
fake=""
trap '[ -z "$fake" ] || kill "$fake" 2>/dev/null; rm -rf "${scratch:?}"' EXIT
pass=0 fail=0
check() { if [ "$1" = ok ]; then pass=$((pass + 1)); printf 'PASS  %s\n' "$2"; else fail=$((fail + 1)); printf 'FAIL  %s\n      %s\n' "$2" "${3:-}"; fi; }

python3 - "$scratch/scenario.jsonl" <<'EOF'
import json, sys
U = "/user.slice/user-1000.slice/user@1000.service/"
app, scope = U + "app.slice/app-niri-ghostty-1.scope", U + "agent.slice/agent-capacity.slice/agent-capacity-" + "a" * 32 + ".scope"
nightly = U + "app.slice/git-maintenance-nightly.service"
def proc(pid, ppid, sid, args, cgroup, rate, t, cwd="/srv/repo/main"):
    return {"pid": pid, "ppid": ppid, "sid": sid, "comm": args[0].split("/")[-1][:15], "args": args, "cgroup": cgroup,
            "ticks": int(rate * 100 * t), "start": str(pid * 10), "rssKiB": 1024, "cwd": cwd}
with open(sys.argv[1], "w") as out:
    for i in range(6):
        t = i * 30
        procs = [proc(400, 1, 400, ["claude"], app, 0.2, t)]
        procs.append(proc(500, 400, 500, ["git", "maintenance", "run", "--auto", "--detach"], app, 0, t))
        procs += [proc(501 + k, 500, 500, ["git", "pack-objects", "--all"], app, 1.0, t) for k in range(5)]
        procs += [proc(601 + k, 1, 600, ["cargo", "build"], scope, 1.0, t) for k in range(6)]
        procs += [proc(701 + k, 1, 700, ["bun", "test"], app, 0.975, t) for k in range(4)]
        procs.append(proc(800, 1, 800, ["git", "-C", "/x", "repack", "-d"], nightly, 0.5, t))
        procs.append(proc(900, 400, 400, ["git", "fetch", "origin"], app, 0.1, t))
        out.write(json.dumps({"at": 1_700_000_000_000 + t * 1000, "load": [1, 1, 1], "cpuPsi": 50, "cpuPsi60": 40, "memPsi": 0,
            "memFullPsi": 0, "memAvailableMiB": 60000, "memTotalMiB": 96000, "cgroups": {}, "procs": procs, "leases": []}) + "\n")
EOF
CAPACITY_WATCHDOG_DIR="$scratch/state" "$target" replay "$scratch/scenario.jsonl" >"$scratch/out.jsonl"

trees="$(jq -s '[.[] | select(.kind == "unleased-tree")]' "$scratch/out.jsonl")"
[ "$(jq length <<<"$trees")" = 1 ] && check ok 'one unleased-tree incident across the scenario' || check bad 'one unleased-tree incident' "$trees"
[ "$(jq -r '.[0].cgroup' <<<"$trees")" = 'app.slice/app-niri-ghostty-1.scope' ] && [ "$(jq -r '.[0].seconds' <<<"$trees")" = 120 ] \
  && check ok 'incident names the unleased cgroup after 120 s' || check bad 'incident cgroup and duration' "$trees"
[ "$(jq -r '.[0].cwd' <<<"$trees")" = /srv/repo/main ] && jq -e '.[0].chain | length == 3 and (.[1] | startswith("500 git maintenance")) and (.[2] | startswith("400 claude"))' <<<"$trees" >/dev/null \
  && check ok 'incident records cwd and the parent chain up to the agent' || check bad 'incident cwd and chain' "$trees"
terms="$(jq -s -c '[.[] | select(.term) | .term] | unique' "$scratch/out.jsonl")"
[ "$terms" = '[500,501,502,503,504,505]' ] && check ok 'git maintenance and its pack-objects outside the timer are terminated; nightly repack and fetch are not' \
  || check bad 'terminated pids' "$terms"

mkdir -p "$scratch/fake"
mkfifo "$scratch/fake/blocker"
(cd "$scratch/fake" && exec -a git bash -c 'cat blocker; :' repack) &
fake=$!
sleep 0.3
CAPACITY_WATCHDOG_DIR="$scratch/state" CAPACITY_WATCHDOG_NOTIFY= "$target" sample --once >/dev/null 2>&1
sleep 0.3
if kill -0 "$fake" 2>/dev/null; then check bad 'live fake git repack is terminated by the sampler' "pid $fake alive"; else check ok 'live fake git repack is terminated by the sampler'; fake=""; fi
grep -q "git-maintenance-terminated: SIGTERM git repack" "$scratch/state/incidents.md" 2>/dev/null \
  && check ok 'termination is logged to incidents.md' || check bad 'termination logged' "$(cat "$scratch/state/incidents.md" 2>/dev/null)"
[ "$(wc -l <"$scratch/state/samples.jsonl")" -ge 1 ] && check ok 'sampler appended a sample' || check bad 'sample appended'

printf 'capacity-watchdog: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
