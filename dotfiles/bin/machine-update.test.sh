#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$here/machine-update"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
candidates="$work/candidates"
mkdir "$candidates"
cat > "$work/running.lock" <<'JSON'
{"version":7,"root":"root","nodes":{"root":{"inputs":{"nixpkgs":"selected","other":"other","follower":"follower"}},"selected":{"locked":{"lastModified":1,"rev":"running"}},"nixpkgs":{"locked":{"lastModified":1,"rev":"decoy"}},"other":{"locked":{"lastModified":1,"rev":"held"}},"follower":{"inputs":{"nixpkgs":["nixpkgs"]}}}}
JSON
jq '.nodes["fresh-selected"]=.nodes.selected | del(.nodes.selected) | .nodes.root.inputs.nixpkgs="fresh-selected" | .nodes["fresh-selected"].locked={lastModified:100,rev:"fresh"} | .nodes.other.locked={lastModified:100,rev:"unheld"}' "$work/running.lock" > "$work/fresh.lock"
select_lock "$work/fresh.lock" "$work/running.lock" "$work/selected.lock" >/dev/null
jq -e '.nodes[.nodes[.root].inputs.nixpkgs].locked.rev == "fresh" and .nodes.nixpkgs.locked.rev == "decoy" and .nodes.other.locked.rev == "held" and .nodes.follower.inputs.nixpkgs == ["nixpkgs"]' "$work/selected.lock" >/dev/null
jq '.nodes.other.locked={lastModified:2,rev:"aged"}' "$work/running.lock" > "$candidates/$(date -d '8 days ago' +%F).lock"
select_lock "$work/fresh.lock" "$work/running.lock" "$work/selected.lock" >/dev/null
jq -e '.nodes[.nodes[.root].inputs.nixpkgs].locked.rev == "fresh" and .nodes.other.locked.rev == "aged"' "$work/selected.lock" >/dev/null
printf 'ok: selected lock reference journey keeps unrelated hold and follows, adopts aged candidate, refreshes direct-root nixpkgs\n'

command -v north >/dev/null || { printf 'skip: capacity journey needs the north CLI, which this runner does not install\n'; exit 0; }; capacity=$(command -v north)
mkdir -p "$work/bin"
cat > "$work/bin/north" <<'SH2'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-} ${2:-} ${3:-}" == 'capacity host run' ]]; then exec bun "$CAPACITY_STUB" run "${@:4}"; fi
exec "$CAPACITY_CANONICAL" "$@"
SH2
cat > "$work/bin/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" == 4 && "$1" == -C && "$2" == "$CAPACITY_SOURCE_DIR" && "$3" == rev-parse && "$4" == --show-toplevel ]]
printf 'recorded repository probe failure\n' >&2
exit 73
SH
cat > "$work/capacity-stub.js" <<'JS'
const args = Bun.argv.slice(2);
const boundary = args.indexOf('--');
if (args[0] !== 'run' || boundary < 0) process.exit(2);
const classIndex = args.indexOf('--class');
const kind = classIndex < 0 ? 'moderate' : args[classIndex + 1];
const fixture = Bun.spawnSync([process.env.CAPACITY_CANONICAL, 'capacity', 'host', 'fixture',
  '--profile', 'unattended', '--class', kind, '--cores', '3',
  '--memory-total-mib', process.env.CAPACITY_EXECUTE_CHILD ? '16384' : '7943',
  '--memory-available-mib', process.env.CAPACITY_EXECUTE_CHILD ? '16384' : '5898',
  '--protected-cpu-some-avg10-basis-points', '0', '--memory-full-avg10-basis-points', '0',
  '--leased-cpus', '0', '--leased-memory-mib', '0']);
process.stderr.write(fixture.stdout);
if (fixture.exitCode !== 0) process.exit(fixture.exitCode);
if (process.env.CAPACITY_EXECUTE_CHILD) {
  const receipts = process.env.CAPACITY_RECEIPTS;
  const previous = await Bun.file(receipts).exists();
  await Bun.write(receipts, (previous ? await Bun.file(receipts).text() : '') + fixture.stdout.toString());
  if (previous) process.exit(77);
  const child = Bun.spawnSync(args.slice(boundary + 1), { stdin: 'inherit', stdout: 'inherit', stderr: 'inherit' });
  process.exit(child.exitCode);
}
process.stderr.write('external admission receipt; child stopped before execution\n');
process.exit(76);
JS
chmod +x "$work/bin/north" "$work/bin/git"
export CAPACITY_CANONICAL="$capacity" CAPACITY_STUB="$work/capacity-stub.js" CAPACITY_JOURNEY="$work" CAPACITY_SOURCE_DIR="$here" GAME_RESERVE_STATE="$work/game-reserve.json" XDG_RUNTIME_DIR="$work"
journey_path="$work/bin:$PATH"
status=0
PATH="$journey_path" "$here/machine-update" --write >"$work/write.log" 2>&1 || status=$?
[[ "$status" == 73 ]] || { cat "$work/write.log"; printf "writer exited %s; expected repository failure 73\n" "$status"; exit 1; }
[[ "$(cat "$work/write.log")" == 'recorded repository probe failure' ]]
status=0
PATH="$journey_path" MACHINE_UPDATE_ADMITTED=1 "$here/machine-update" --apply >"$work/apply.log" 2>&1 || status=$?
[[ "$status" == 76 ]]
head -n 1 "$work/apply.log" | jq -e '.decision == "RUN" and .cpus == 3 and .memoryMiB == 1985' >/dev/null
printf 'ok: public writer reaches repository probe without outer lease; apply admits an unmeasured heavy update at 3CPU/1985MiB on 7943MiB total\n'

status=0
PATH="$journey_path" CAPACITY_EXECUTE_CHILD=1 CAPACITY_RECEIPTS="$work/receipts.jsonl" "$here/machine-update" --apply >"$work/eligible-apply.log" 2>&1 || status=$?
[[ "$status" == 73 ]] || { cat "$work/eligible-apply.log"; printf "eligible apply exited %s; expected repository failure 73\n" "$status"; exit 1; }
jq -se 'length == 1 and .[0].decision == "RUN" and .[0].cpus == 3' "$work/receipts.jsonl" >/dev/null
[[ "$(tail -n 1 "$work/eligible-apply.log")" == 'recorded repository probe failure' ]]
printf 'ok: public eligible apply admits and executes once, reaches repository probe in actual script directory\n'
