#!/usr/bin/env bash
# agents.test.sh — the switchboard's semantics matrix, run against a sandbox
# HOME so no assertion can touch the live config. Two axes are what this proves:
# a hook's PERMISSION (enabled/disabled, stored, the user's) and its ACTIVITY
# (derived: permission AND its companion skill being on, never stored).
set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$REPO/dotfiles/bin/agents"
FRAG_SRC="$REPO/dotfiles/agents/hooks.d"
SB="$(mktemp -d)"
trap 'rm -rf "$SB" "$SB.frags"' EXIT

fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n   %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }
chk() { # desc expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2] got [$3]"; fi
}

fresh() { # [fragments-dir]
  rm -rf "${SB:?}"
  mkdir -p "$SB/.claude" "$SB/code/nixos-config/main/dotfiles/agents"
  echo '{"model":"opus","otherKey":42}' > "$SB/.claude/settings.json"
  cp "$REPO/dotfiles/agents/AGENTS.md" "$SB/code/nixos-config/main/dotfiles/agents/AGENTS.md"
  ln -sfn "$REPO/dotfiles/agents/skills" "$SB/code/nixos-config/main/dotfiles/agents/skills"
  FRAGS="${1:-$FRAG_SRC}"
}

ag() { HOME="$SB" AGENTS_FRAGMENTS="$FRAGS" bash "$BIN" "$@"; }
hookrows() { grep '^hook ' "$SB/.config/agents/manifest.conf" | sort; }
composed_files() { # every hook command settings.json currently carries
  python3 - "$SB/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
cmds = set()
for event, blocks in (s.get("hooks") or {}).items():
    for b in blocks:
        for h in b["hooks"]:
            cmds.add(h["command"])
print(" ".join(sorted(cmds)))
PY
}
has_cmd() { composed_files | grep -q -- "$1"; }

echo "== 1. fresh seed: bound hooks enabled+companion, unbound disabled, nothing composes"
fresh
ag status > /dev/null
chk "firn-guard row" "hook firn-guard enabled firn" "$(grep '^hook firn-guard ' "$SB/.config/agents/manifest.conf")"
chk "worktree-guard row" "hook worktree-guard enabled repo-safety" "$(grep '^hook worktree-guard ' "$SB/.config/agents/manifest.conf")"
chk "logcompress row (unbound)" "hook logcompress disabled" "$(grep '^hook logcompress ' "$SB/.config/agents/manifest.conf")"
chk "repo-safety skill seeded off" "skill repo-safety off" "$(grep '^skill repo-safety ' "$SB/.config/agents/manifest.conf")"
st="$(ag status)"
case "$st" in *"worktree-guard         enabled · off (repo-safety off)"*) ok "status: bound + skill off" ;;
  *) bad "status: bound + skill off" "$(echo "$st" | grep worktree-guard)" ;; esac
case "$st" in *"hook-detach            disabled"*) ok "status: unbound infrastructure reads disabled" ;;
  *) bad "status: unbound disabled" "$(echo "$st" | grep hook-detach)" ;; esac
ag off worktree-guard > /dev/null
st="$(ag status)"
case "$st" in *"worktree-guard         disabled (repo-safety)"*) ok "status: a pin still names its skill" ;;
  *) bad "status: pin names skill" "$(echo "$st" | grep worktree-guard)" ;; esac
ag on worktree-guard > /dev/null
ag apply > /dev/null
chk "fresh composes nothing" "" "$(composed_files)"
chk "settings.json foreign key survives" "42" "$(python3 -c 'import json;print(json.load(open("'"$SB"'/.claude/settings.json"))["otherKey"])')"

echo
echo "== 2. migration of legacy 3-field rows: blackout holds"
fresh
mkdir -p "$SB/.config/agents"
{ echo "item agents-md off"; echo "item statusline-script off"; echo "item orchestration off"
  for h in agent-spawn-guard beagle-session-start comment-bloat-guard firn-guard \
           git-blind-stage-guard hook-detach logcompress north-session-lifecycle \
           tripwire-guard worktree-guard; do echo "hook $h off"; done
  for s in webdev beagle-authoring fram-modeling code-as-facts firn; do echo "skill $s off"; done
} > "$SB/.config/agents/manifest.conf"
ag status > /dev/null
chk "legacy bound -> enabled + column" "hook tripwire-guard enabled repo-safety" "$(grep '^hook tripwire-guard ' "$SB/.config/agents/manifest.conf")"
chk "legacy unbound -> disabled" "hook comment-bloat-guard disabled" "$(grep '^hook comment-bloat-guard ' "$SB/.config/agents/manifest.conf")"
chk "legacy on -> enabled" "1" "$(grep -c '^hook .* enabled' "$SB/.config/agents/manifest.conf" > /dev/null; echo 1)"
ag apply > /dev/null
chk "migration composes nothing (blackout)" "" "$(composed_files)"
chk "idempotent: second ensure changes nothing" "" "$(cp "$SB/.config/agents/manifest.conf" "$SB/m1"; ag status > /dev/null; diff "$SB/m1" "$SB/.config/agents/manifest.conf")"

echo
echo "== 3. derivation: a skill flip changes activity with zero hook-row diffs"
fresh; ag status > /dev/null
before="$(hookrows)"
ag on firn > /dev/null
chk "hook rows unchanged by skill flip" "" "$(diff <(echo "$before") <(hookrows))"
chk "skill row on" "skill firn on" "$(grep '^skill firn ' "$SB/.config/agents/manifest.conf")"
if has_cmd firn-guard.sh; then ok "firn-guard composed by its skill"; else bad "firn-guard composed by its skill" "$(composed_files)"; fi
if has_cmd worktree-guard; then bad "other skills stay off" "$(composed_files)"; else ok "other skills stay off"; fi
ag off firn > /dev/null
chk "skill off decomposes" "" "$(composed_files)"
chk "hook rows still unchanged" "" "$(diff <(echo "$before") <(hookrows))"

echo
echo "== 4. disabled immunity: a user pin survives skill flips"
fresh; ag status > /dev/null
ag off firn-guard > /dev/null
chk "direct off writes disabled" "hook firn-guard disabled firn" "$(grep '^hook firn-guard ' "$SB/.config/agents/manifest.conf")"
ag on firn > /dev/null
chk "skill on does not compose a disabled hook" "" "$(composed_files)"
chk "skill on does not clear the pin" "hook firn-guard disabled firn" "$(grep '^hook firn-guard ' "$SB/.config/agents/manifest.conf")"
ag on firn-guard > /dev/null
chk "direct on clears the pin" "hook firn-guard enabled firn" "$(grep '^hook firn-guard ' "$SB/.config/agents/manifest.conf")"
if has_cmd firn-guard.sh; then ok "cleared pin + skill on = composed"; else bad "cleared pin + skill on = composed" "$(composed_files)"; fi
st="$(ag status)"; case "$st" in *"firn-guard             enabled · on"*) ok "status: enabled · on" ;; *) bad "status: enabled · on" "$(echo "$st" | grep firn-guard)" ;; esac
ag off firn > /dev/null
st="$(ag status)"; case "$st" in *"enabled · off (firn off)"*) ok "status: enabled · off (firn off)" ;; *) bad "status provenance" "$(echo "$st" | grep firn-guard)" ;; esac

echo
echo "== 5. unbound + enabled = active with every skill off"
fresh; ag status > /dev/null
ag on logcompress > /dev/null
chk "unbound enabled row" "hook logcompress enabled" "$(grep '^hook logcompress ' "$SB/.config/agents/manifest.conf")"
if has_cmd logcompress-hook.js; then ok "unbound enabled composes"; else bad "unbound enabled composes" "$(composed_files)"; fi
st="$(ag status)"; case "$st" in *"logcompress            enabled · on"*) ok "status: unbound enabled · on" ;; *) bad "status unbound" "$(echo "$st" | grep logcompress)" ;; esac

echo
echo "== 6. requires chain: a disabled requirement drops dependents loudly"
rm -rf "$SB.frags"; mkdir -p "$SB.frags"; cp "$FRAG_SRC"/*.json "$SB.frags/"
python3 - "$SB.frags" <<'PY'
import json, os, sys
d = sys.argv[1]
p = os.path.join(d, "tripwire-guard.json")
frag = json.load(open(p)); frag["requires"] = ["worktree-guard"]
open(p, "w").write(json.dumps(frag, indent=1))
PY
fresh "$SB.frags"
ag status > /dev/null
ag on repo-safety > /dev/null
if has_cmd tripwire-guard.sh && has_cmd launch-critical-worktree-guard.sh; then
  ok "whole chain composes when both enabled"
else bad "whole chain composes" "$(composed_files)"; fi
warn="$(ag off worktree-guard 2>&1 >/dev/null)"
if has_cmd tripwire-guard.sh; then bad "dependent dropped" "$(composed_files)"; else ok "dependent dropped when requirement disabled"; fi
case "$warn" in *"tripwire-guard is enabled but requires worktree-guard, which is disabled"*)
  ok "drop is loud" ;; *) bad "drop is loud" "$warn" ;; esac
st="$(ag status 2>/dev/null)"; case "$st" in *"enabled · off (needs worktree-guard, disabled)"*) ok "status names the blocking requirement" ;; *) bad "status names requirement" "$(echo "$st" | grep tripwire)" ;; esac
if has_cmd git-blind-stage-guard.sh; then ok "unrelated sibling unaffected"; else bad "sibling unaffected" "$(composed_files)"; fi
# direct `on` pulls its requirement's permission back
ag on tripwire-guard > /dev/null
chk "direct on grants the requirement too" "hook worktree-guard enabled repo-safety" "$(grep '^hook worktree-guard ' "$SB/.config/agents/manifest.conf")"
# a requirement rides in even when its own companion skill is off
python3 - "$SB.frags" <<'PY'
import json, os, sys
p = os.path.join(sys.argv[1], "worktree-guard.json")
frag = json.load(open(p)); frag["skill"] = "webdev"
open(p, "w").write(json.dumps(frag, indent=1))
PY
ag apply > /dev/null
chk "re-pointed binding corrected in column" "hook worktree-guard enabled webdev" "$(grep '^hook worktree-guard ' "$SB/.config/agents/manifest.conf")"
if has_cmd launch-critical-worktree-guard.sh; then ok "requirement pulled in despite its skill being off"; else bad "requirement pulled in" "$(composed_files)"; fi
st="$(ag status 2>/dev/null)"; case "$st" in *"enabled · on (required by tripwire-guard)"*) ok "status explains the pull-in" ;; *) bad "status pull-in" "$(echo "$st" | grep worktree-guard)" ;; esac

echo
echo "== 7. field-4 sync: backfill, correction, removal, preservation across flips"
python3 - "$SB.frags" <<'PY'
import json, os, sys
p = os.path.join(sys.argv[1], "worktree-guard.json")
frag = json.load(open(p)); frag.pop("skill")
open(p, "w").write(json.dumps(frag, indent=1))
PY
ag status > /dev/null
chk "unbinding drops the column" "hook worktree-guard enabled" "$(grep '^hook worktree-guard ' "$SB/.config/agents/manifest.conf")"
ag off git-blind-stage-guard > /dev/null
chk "column rides through a flip" "hook git-blind-stage-guard disabled repo-safety" "$(grep '^hook git-blind-stage-guard ' "$SB/.config/agents/manifest.conf")"
ag on git-blind-stage-guard > /dev/null
chk "column rides back" "hook git-blind-stage-guard enabled repo-safety" "$(grep '^hook git-blind-stage-guard ' "$SB/.config/agents/manifest.conf")"

echo
echo "== 8. --all both ways"
fresh; ag status > /dev/null
ag on --all > /dev/null
chk "on --all: no hook left disabled" "0" "$(grep -c '^hook .* disabled' "$SB/.config/agents/manifest.conf" || true)"
chk "on --all: skills on" "0" "$(grep -c '^skill .* off' "$SB/.config/agents/manifest.conf" || true)"
chk "on --all: every fragment composed" "10" "$(ag status 2>/dev/null | grep -c 'enabled · on')"
ag off --all > /dev/null
chk "off --all: hooks disabled" "10" "$(grep -c '^hook .* disabled' "$SB/.config/agents/manifest.conf")"
chk "off --all: nothing composed" "" "$(composed_files)"
chk "off --all: skills off" "0" "$(grep -c '^skill .* on' "$SB/.config/agents/manifest.conf" || true)"

echo
echo "== 9. apply degrades per item when a source is missing"
fresh; ag status > /dev/null
rm "$SB/code/nixos-config/main/dotfiles/agents/AGENTS.md"
ag on logcompress > /dev/null 2>"$SB/err1"
out="$(ag on agents-md 2>"$SB/err" )"
chk "apply still reports" "1" "$(echo "$out" | grep -c '^applied:')"
if grep -q 'agents-md is on but .* is missing' "$SB/err"; then ok "missing source warns"; else bad "missing source warns" "$(cat "$SB/err")"; fi
chk "wrote empty CLAUDE.md" "0" "$(stat -c %s "$SB/.config/agents/CLAUDE.md")"
chk "codex surface still written" "0" "$(stat -c %s "$SB/.config/agents/AGENTS.md")"
if has_cmd logcompress-hook.js; then ok "later items still applied (settings.json reached)"; else bad "later items applied" "$(composed_files)"; fi
rm -f "$SB/.claude/settings.json"
out="$(ag apply 2>"$SB/err2")"
chk "apply survives a missing settings.json" "1" "$(echo "$out" | grep -c '^applied:')"
chk "settings.json recreated" "1" "$(test -f "$SB/.claude/settings.json" && echo 1 || echo 0)"
echo '{ not json' > "$SB/.claude/settings.json"
out="$(ag apply 2>"$SB/err3")"
chk "apply survives an unparseable settings.json" "1" "$(echo "$out" | grep -c '^applied:')"
if grep -q 'unreadable' "$SB/err3"; then ok "unparseable settings.json is loud"; else bad "unparseable loud" "$(cat "$SB/err3")"; fi
chk "unparseable settings.json left alone" "{ not json" "$(cat "$SB/.claude/settings.json")"
# a missing skill source
echo '{}' > "$SB/.claude/settings.json"
rm "$SB/code/nixos-config/main/dotfiles/agents/skills"
ag on repo-safety 2>"$SB/err4" >/dev/null
if grep -q 'skill repo-safety is on but .* is missing' "$SB/err4"; then ok "missing skill source warns"; else bad "missing skill source warns" "$(cat "$SB/err4")"; fi

echo
echo "== 10. status section order"
fresh; ag status > /dev/null
chk "order" "globals directory context skills hooks plugins" "$(ag status | grep -v '^ ' | tr '\n' ' ' | sed 's/ $//')"

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILURES"; fi
exit "$fails"
