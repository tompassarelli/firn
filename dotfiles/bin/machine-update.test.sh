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
