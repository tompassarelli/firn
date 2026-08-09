#!/usr/bin/env bash
# agents.test.sh — the switchboard's semantics matrix, run against a sandbox
# HOME so no assertion can touch the live config. Two axes are what this proves:
# a hook's PERMISSION (enabled/disabled, stored, the user's) and its ACTIVITY
# (derived: permission AND its companion unit being on, never stored) — where
# the companion may be a unit of ANY kind that speaks on/off.
set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$REPO/dotfiles/bin/agents"
FRAG_SRC="$REPO/dotfiles/agents/hooks.d"
SB="$(mktemp -d)"
trap 'rm -rf "$SB" "$SB.frags" "$SB.mods"' EXIT

fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n   %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }
chk() { # desc expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2] got [$3]"; fi
}

ACCT="$SB/.local/state/north/accounts/anthropic/acct-one"

fresh() { # [fragments-dir]
  rm -rf "${SB:?}"
  mkdir -p "$SB/.claude" "$SB/code/nixos-config/main/dotfiles/agents" "$ACCT"
  echo '{"model":"opus","otherKey":42}' > "$SB/.claude/settings.json"
  cp "$REPO/dotfiles/agents/AGENTS.md" "$SB/code/nixos-config/main/dotfiles/agents/AGENTS.md"
  ln -sfn "$REPO/dotfiles/agents/skills" "$SB/code/nixos-config/main/dotfiles/agents/skills"
  # An account copy only exists once a session has made one; apply overwrites
  # what is there and never creates the tree, so the fixture must.
  : > "$ACCT/CLAUDE.md"
  FRAGS="${1:-$FRAG_SRC}"
  # No member lists unless a test writes some: the default is a directory that
  # does not exist, which is also what a machine with no modules.d has.
  MODS="$SB/no-modules"
}

mods() { MODS="$SB.mods"; rm -rf "$MODS"; mkdir -p "$MODS"; }
mod() { # name member...
  local n="$1"; shift
  python3 -c 'import json,sys;json.dump({"members":sys.argv[2:]},open(sys.argv[1],"w"))' \
    "$MODS/$n.json" "$@"
}
mod_ins() { # name instructions-path member...
  local n="$1" f="$2"; shift 2
  python3 -c 'import json,sys;json.dump({"instructions":sys.argv[2],"members":sys.argv[3:]},open(sys.argv[1],"w"))' \
    "$MODS/$n.json" "$f" "$@"
}
markers() { grep -o '<!-- module: [a-z-]* -->' "$SB/.config/agents/CLAUDE.md" | tr '\n' ' ' | sed 's/ $//'; }
skilllinks() { find "$SB/.config/agents/skills" -maxdepth 1 -type l -printf '%f\n' | sort | tr '\n' ' ' | sed 's/ $//'; }

ag() { HOME="$SB" AGENTS_FRAGMENTS="$FRAGS" AGENTS_MODULES="$MODS" bash "$BIN" "$@"; }
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
chk "global seeds as a dir row at the root" "dir global off ~" "$(grep '^dir global ' "$SB/.config/agents/manifest.conf")"
chk "orchestration seeds as a module" "module orchestration off" "$(grep '^module ' "$SB/.config/agents/manifest.conf")"
chk "statusline-script seeds as other" "other statusline-script off" "$(grep '^other ' "$SB/.config/agents/manifest.conf")"
chk "no item kind survives" "0" "$(grep -c '^item ' "$SB/.config/agents/manifest.conf" || true)"
chk "hook bound to a dir row" "hook comment-bloat-guard enabled global" "$(grep '^hook comment-bloat-guard ' "$SB/.config/agents/manifest.conf")"
chk "hook bound to a module" "hook agent-spawn-guard enabled orchestration" "$(grep '^hook agent-spawn-guard ' "$SB/.config/agents/manifest.conf")"
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
chk "legacy unbound -> disabled" "hook hook-detach disabled" "$(grep '^hook hook-detach ' "$SB/.config/agents/manifest.conf")"
chk "legacy on -> enabled" "1" "$(grep -c '^hook .* enabled' "$SB/.config/agents/manifest.conf" > /dev/null; echo 1)"
ag apply > /dev/null
chk "migration composes nothing (blackout)" "" "$(composed_files)"
chk "idempotent: second ensure changes nothing" "" "$(cp "$SB/.config/agents/manifest.conf" "$SB/m1"; ag status > /dev/null; diff "$SB/m1" "$SB/.config/agents/manifest.conf")"

echo
echo "== 2b. re-kinding off \`item\`: each row lands on a real kind, state intact"
fresh
mkdir -p "$SB/.config/agents"
# Deliberately mixed states, and deliberately in place: the row a re-kinding
# rewrites must keep both its state and its position, or a manifest read
# directly (Northbridge) sees a row appear and another vanish.
{ echo "item agents-md on"; echo "hook logcompress enabled"
  echo "item statusline-script on"; echo "skill webdev on"
  echo "item orchestration off"
} > "$SB/.config/agents/manifest.conf"
ag status > /dev/null
m="$SB/.config/agents/manifest.conf"
chk "item agents-md on -> dir global on ~" "dir global on ~" "$(grep '^dir global ' "$m")"
chk "item statusline-script on -> other, state kept" "other statusline-script on" "$(grep '^other ' "$m")"
chk "item orchestration off -> module, state kept" "module orchestration off" "$(grep '^module ' "$m")"
chk "no item row left behind" "0" "$(grep -c '^item ' "$m" || true)"
chk "re-kinding is in place (line 1 stays line 1)" "dir global on ~" "$(sed -n 1p "$m")"
chk "unrelated rows untouched" "skill webdev on" "$(grep '^skill webdev ' "$m")"
chk "re-kinding is idempotent" "" "$(cp "$m" "$SB/m2"; ag status > /dev/null; diff "$SB/m2" "$m")"
# A half-migrated manifest (both rows present) collapses to one instead of
# doubling: the row already carrying the new kind is the survivor, state and all.
{ echo "item agents-md on"; echo "dir global off ~"; echo "skill webdev on"; } > "$m"
ag status > /dev/null
chk "half-migrated: exactly one dir global row" "1" "$(grep -c '^dir global ' "$m")"
chk "half-migrated: the already-re-kinded row wins" "dir global off ~" "$(grep '^dir global ' "$m")"
chk "half-migrated: item gone" "0" "$(grep -c '^item agents-md' "$m" || true)"

echo
echo "== 2c. the global profile writes the global surfaces and nothing per-directory"
fresh; ag status > /dev/null
ag on global > /dev/null
src="$SB/code/nixos-config/main/dotfiles/agents/AGENTS.md"
chk "config-dir CLAUDE.md is the profile, byte for byte" "" "$(diff "$src" "$SB/.config/agents/CLAUDE.md")"
chk "codex AGENTS.md is the profile, byte for byte" "" "$(diff "$src" "$SB/.config/agents/AGENTS.md")"
chk "the account copy is the profile too" "" "$(diff "$src" "$ACCT/CLAUDE.md")"
chk "global writes no per-dir target pair" "0" "$(ls "$SB/.config/agents/dir" | wc -l)"
chk "global hangs no link off a directory" "0" "$(test -e "$SB/CLAUDE.md" -o -L "$SB/CLAUDE.md" && echo 1 || echo 0)"
ag off global > /dev/null
chk "off empties the global surfaces" "0" "$(stat -c %s "$SB/.config/agents/CLAUDE.md")"
chk "off empties the account copy" "0" "$(stat -c %s "$ACCT/CLAUDE.md")"
chk "path global is the profile source" "$src" "$(ag path global)"

echo
echo "== 2d. a hook follows any kind: a dir row and a module both gate one"
fresh; ag status > /dev/null
chk "comment-bloat-guard follows the global dir row" "hook comment-bloat-guard enabled global" "$(grep '^hook comment-bloat-guard ' "$SB/.config/agents/manifest.conf")"
if has_cmd comment-bloat-guard.sh; then bad "dir-bound hook waits for its row" "$(composed_files)"; else ok "dir-bound hook waits for its row"; fi
ag on global > /dev/null
if has_cmd comment-bloat-guard.sh; then ok "dir row on composes the hook that follows it"; else bad "dir row composes hook" "$(composed_files)"; fi
if has_cmd agent-spawn-guard.sh; then bad "module still off keeps its hook out" "$(composed_files)"; else ok "module still off keeps its hook out"; fi
ag on orchestration > /dev/null
if has_cmd agent-spawn-guard.sh; then ok "module on composes the hook that follows it"; else bad "module composes hook" "$(composed_files)"; fi
st="$(ag status)"
case "$st" in *"agent-spawn-guard      enabled · on (orchestration)"*) ok "status names the module it follows" ;;
  *) bad "status names module" "$(echo "$st" | grep agent-spawn)" ;; esac
ag off global > /dev/null
if has_cmd comment-bloat-guard.sh; then bad "dir row off decomposes" "$(composed_files)"; else ok "dir row off decomposes its hook"; fi
st="$(ag status)"
case "$st" in *"comment-bloat-guard    enabled · off (global off)"*) ok "status blames the dir row by name" ;;
  *) bad "status blames dir row" "$(echo "$st" | grep comment-bloat)" ;; esac
chk "a followed row's own state is untouched by the hook" "dir global off ~" "$(grep '^dir global ' "$SB/.config/agents/manifest.conf")"

echo
echo "== 2e. a name that means two units is called out, loudly, without dying"
fresh
# The collision is planted where inventories actually collide: a registry slug
# that is also a skill name. Registry, not the arrays, because that is the one
# inventory this switchboard does not own.
mkdir -p "$SB/code/north-data/context-dirs"
printf '%s\n' "$SB/somewhere firn" > "$SB/code/north-data/context-dirs.conf"
mkdir -p "$SB/somewhere"
warn="$(ag status 2>&1 >/dev/null)"
case "$warn" in *"duplicate unit name across kinds: firn"*) ok "duplicate name warns" ;;
  *) bad "duplicate name warns" "$warn" ;; esac
chk "duplicate name does not kill status" "1" "$(ag status 2>/dev/null | grep -c '^skills$')"
chk "no duplicate warning when names are unique" "" "$(rm "$SB/code/north-data/context-dirs.conf"; ag status 2>&1 >/dev/null)"

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
frag = json.load(open(p)); frag["follows"] = "webdev"
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
frag = json.load(open(p)); frag.pop("follows")
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
out="$(ag on global 2>"$SB/err" )"
chk "apply still reports" "1" "$(echo "$out" | grep -c '^applied:')"
if grep -q 'global is on but .* is missing' "$SB/err"; then ok "missing source warns"; else bad "missing source warns" "$(cat "$SB/err")"; fi
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
# Dependency order: a hook's parenthetical can only name a row already read.
chk "order" "directory instructions modules skills hooks plugins other" "$(ag status | grep -v '^ ' | tr '\n' ' ' | sed 's/ $//')"
chk "global heads the directory section, scope ~" "global off ~" "$(ag status | sed -n 2p | tr -s ' ' | sed 's/^ //')"

echo
echo "== 11. module member lists: UNION, so a shared member outlives one bundle"
fresh; mods
mod ui-bundle repo-safety
mod ml-bundle repo-safety
ag status > /dev/null
chk "a modules.d file seeds a module row" "module ui-bundle off" "$(grep '^module ui-bundle ' "$SB/.config/agents/manifest.conf")"
chk "membership stays out of the manifest" "0" "$(grep -c 'repo-safety.*ui-bundle\|ui-bundle.*repo-safety' "$SB/.config/agents/manifest.conf" || true)"
ag on repo-safety > /dev/null
chk "own switch is still written" "skill repo-safety on" "$(grep '^skill repo-safety ' "$SB/.config/agents/manifest.conf")"
chk "on but held by every bundle = not linked" "" "$(skilllinks)"
if has_cmd worktree-guard; then bad "a hook following a held skill stays out" "$(composed_files)"; else ok "a hook following a held skill stays out"; fi
ag on ui-bundle > /dev/null
chk "one bundle on releases the member" "repo-safety" "$(skilllinks)"
if has_cmd launch-critical-worktree-guard.sh; then ok "the following hook composes through the bundle"; else bad "hook composes through bundle" "$(composed_files)"; fi
ag on ml-bundle > /dev/null
chk "both bundles on is still one link" "repo-safety" "$(skilllinks)"
ag off ui-bundle > /dev/null
chk "UNION: the other bundle still wants it" "repo-safety" "$(skilllinks)"
if has_cmd launch-critical-worktree-guard.sh; then ok "union keeps the hook composed too"; else bad "union keeps hook" "$(composed_files)"; fi
ag off ml-bundle > /dev/null
chk "last bundle off finally drops it" "" "$(skilllinks)"
st="$(ag status)"
case "$st" in *"repo-safety          on · off (ml-bundle off)"*) ok "status names a holding bundle" ;;
  *) bad "status names bundle" "$(echo "$st" | grep repo-safety)" ;; esac
chk "flipping a bundle never rewrites the member's own row" "skill repo-safety on" "$(grep '^skill repo-safety ' "$SB/.config/agents/manifest.conf")"

echo
echo "== 12. modules of modules: two deep, and the chain says the nearest cause"
fresh; mods
mod outer mid
mod mid repo-safety
ag status > /dev/null
ag on repo-safety > /dev/null; ag on mid > /dev/null
chk "an inner bundle held by an outer one composes nothing" "" "$(skilllinks)"
st="$(ag status)"
case "$st" in *"mid                  on · off (outer off)"*) ok "the inner bundle blames the outer" ;;
  *) bad "inner blames outer" "$(echo "$st" | grep '^  mid')" ;; esac
case "$st" in *"repo-safety          on · off (outer off)"*) ok "the member blames the NEAREST off ancestor, two up" ;;
  *) bad "member blames nearest off ancestor" "$(echo "$st" | grep repo-safety)" ;; esac
ag on outer > /dev/null
chk "the outer bundle releases the whole chain" "repo-safety" "$(skilllinks)"
ag off mid > /dev/null
chk "breaking the middle drops the member again" "" "$(skilllinks)"
st="$(ag status)"
case "$st" in *"repo-safety          on · off (mid off)"*) ok "now the nearest cause is the middle" ;;
  *) bad "nearest cause is middle" "$(echo "$st" | grep repo-safety)" ;; esac

echo
echo "== 13. payload-only modules are untouched by the member mechanism"
fresh; mods
mod outer mid
ag status > /dev/null
chk "orchestration needs no member file" "module orchestration off" "$(grep '^module orchestration ' "$SB/.config/agents/manifest.conf")"
chk "path of a payload-only module is its payload" "$SB/code/north/main/orchestration/doctrine.md" "$(ag path orchestration)"
chk "path of a member-list module is its list" "$MODS/outer.json" "$(ag path outer)"
ag on orchestration > /dev/null
chk "a payload module in no bundle answers only to itself" "module orchestration on" "$(grep '^module orchestration ' "$SB/.config/agents/manifest.conf")"
if has_cmd agent-spawn-guard.sh; then ok "its follower composes, ungated"; else bad "follower composes" "$(composed_files)"; fi

echo
echo "== 14. a membership cycle is named, and everything in it derives inactive"
fresh; mods
mod loop-x loop-y
mod loop-y loop-x repo-safety
ag status > /dev/null
ag on repo-safety > /dev/null
warn="$(ag on loop-x 2>&1 >/dev/null)"
case "$warn" in *"module cycle: loop-x -> loop-y -> loop-x"*) ok "the cycle is named, both hops" ;;
  *) bad "cycle named" "$warn" ;; esac
ag on loop-y > /dev/null 2>&1
chk "both switches are on regardless" "2" "$(grep -c '^module loop-. on' "$SB/.config/agents/manifest.conf")"
chk "a cycle composes nothing" "" "$(skilllinks)"
st="$(ag status 2>/dev/null)"
case "$st" in *"loop-x               on · off (module cycle)"*) ok "status calls it a cycle, not a mystery" ;;
  *) bad "status names cycle" "$(echo "$st" | grep 'loop-x')" ;; esac
case "$st" in *"repo-safety          on · off (loop-y off)"*) ok "a member of a cycle blames the cycle module" ;;
  *) bad "member blames cycle module" "$(echo "$st" | grep repo-safety)" ;; esac
chk "status still exits clean under a cycle" "1" "$(ag status >/dev/null 2>&1 && echo 1 || echo 0)"

echo
echo "== 15. apply composes by ACTIVITY: dirs, skills, hooks, all gated alike"
fresh; mods
mkdir -p "$SB/code/north-data/context-dirs" "$SB/proj"
printf '%s proj\n' "$SB/proj" > "$SB/code/north-data/context-dirs.conf"
echo "PROJECT CONTEXT" > "$SB/code/north-data/context-dirs/proj.md"
mod docs-bundle proj global
mod guard-bundle logcompress
ag status > /dev/null
ag on proj > /dev/null; ag on global > /dev/null; ag on logcompress > /dev/null
chk "a held dir row writes an EMPTY context file" "0" "$(stat -c %s "$SB/.config/agents/dir/proj-CLAUDE.md")"
chk "a held dir row writes an empty codex surface too" "0" "$(stat -c %s "$SB/.config/agents/dir/proj-AGENTS.md")"
chk "a held global profile writes empty" "0" "$(stat -c %s "$SB/.config/agents/CLAUDE.md")"
chk "a held global profile empties the account copy" "0" "$(stat -c %s "$ACCT/CLAUDE.md")"
if has_cmd logcompress-hook.js; then bad "a held hook is not composed" "$(composed_files)"; else ok "a held hook is not composed"; fi
st="$(ag status)"
case "$st" in *"logcompress            enabled · off (guard-bundle off)"*) ok "status: a hook says which bundle holds it" ;;
  *) bad "hook names bundle" "$(echo "$st" | grep logcompress)" ;; esac
ag on docs-bundle > /dev/null
chk "the bundle releases the dir context" "PROJECT CONTEXT" "$(cat "$SB/.config/agents/dir/proj-CLAUDE.md")"
chk "and the global profile with it" "1" "$(test -s "$SB/.config/agents/CLAUDE.md" && echo 1 || echo 0)"
if has_cmd comment-bloat-guard.sh; then ok "the hook following the released profile composes"; else bad "follower of released profile" "$(composed_files)"; fi
ag on guard-bundle > /dev/null
if has_cmd logcompress-hook.js; then ok "the released hook composes"; else bad "released hook composes" "$(composed_files)"; fi
chk "applied: line counts active dirs, not on ones" "1/1" "$(ag apply | sed 's/.*, \([0-9]*\/[0-9]*\) dir contexts.*/\1/')"
ag off docs-bundle > /dev/null
chk "applied: a held dir counts as 0" "0/1" "$(ag apply | sed 's/.*, \([0-9]*\/[0-9]*\) dir contexts.*/\1/')"
chk "manifest is untouched by all this gating" "dir proj on $SB/proj" "$(grep '^dir proj ' "$SB/.config/agents/manifest.conf")"
chk "modules are idempotent across ensure" "" "$(cp "$SB/.config/agents/manifest.conf" "$SB/m3"; ag status > /dev/null; diff "$SB/m3" "$SB/.config/agents/manifest.conf")"

echo
echo "== 16. account copies are real files that never alias the master"
fresh; ag status > /dev/null
ag on global > /dev/null
src="$SB/code/nixos-config/main/dotfiles/agents/AGENTS.md"
# The live incident, exactly: an old account entry was a symlink resolving back
# to the master, so `> acct` truncated the master before `cat` could read it.
rm -f "$ACCT/CLAUDE.md"; ln -s "$SB/.config/agents/CLAUDE.md" "$ACCT/CLAUDE.md"
ag apply > /dev/null
chk "the master survives an aliasing account entry" "" "$(diff "$src" "$SB/.config/agents/CLAUDE.md")"
chk "the aliasing link is replaced, not followed" "0" "$(test -L "$ACCT/CLAUDE.md" && echo 1 || echo 0)"
chk "and the account copy is a real file with the content" "" "$(diff "$src" "$ACCT/CLAUDE.md")"
chk "the codex surface is intact too" "" "$(diff "$src" "$SB/.config/agents/AGENTS.md")"
# heal, don't skip: the loop globs account DIRECTORIES now
rm -f "$ACCT/CLAUDE.md"
ag apply > /dev/null
chk "a deleted account copy heals on the next apply" "1" "$(test -f "$ACCT/CLAUDE.md" && echo 1 || echo 0)"
chk "and heals with the content, not an empty file" "" "$(diff "$src" "$ACCT/CLAUDE.md")"
mkdir -p "$SB/.local/state/north/accounts/anthropic/acct-two"
ag apply > /dev/null
chk "a never-seeded account is written for the first time" "1" "$(test -f "$SB/.local/state/north/accounts/anthropic/acct-two/CLAUDE.md" && echo 1 || echo 0)"
chk "and it carries the profile" "" "$(diff "$src" "$SB/.local/state/north/accounts/anthropic/acct-two/CLAUDE.md")"
ag off global > /dev/null
chk "off still empties every account copy" "0" "$(stat -c %s "$ACCT/CLAUDE.md")"

echo
echo "== 17. a module's instructions ride on the global surfaces while it is active"
fresh; mods
echo "AAA-CONTEXT" > "$SB/a-ins.md"
echo "ZZZ-CONTEXT" > "$SB/z-ins.md"
mod_ins a-mod "$SB/a-ins.md" repo-safety
mod_ins z-mod "$SB/z-ins.md"
ag status > /dev/null
ag on global > /dev/null
src="$SB/code/nixos-config/main/dotfiles/agents/AGENTS.md"
chk "an inactive module appends nothing" "" "$(diff "$src" "$SB/.config/agents/CLAUDE.md")"
ag on a-mod > /dev/null
chk "an active module appends its file" "1" "$(grep -c '^AAA-CONTEXT$' "$SB/.config/agents/CLAUDE.md")"
chk "behind a marker naming it" "<!-- module: a-mod -->" "$(markers)"
chk "the profile is still first, whole" "$(head -1 "$src")" "$(head -1 "$SB/.config/agents/CLAUDE.md")"
chk "the codex surface carries the composed result" "" "$(diff "$SB/.config/agents/CLAUDE.md" "$SB/.config/agents/AGENTS.md")"
chk "so does the account copy" "" "$(diff "$SB/.config/agents/CLAUDE.md" "$ACCT/CLAUDE.md")"
ag on z-mod > /dev/null
chk "two modules append in modules.d filename order" "<!-- module: a-mod --> <!-- module: z-mod -->" "$(markers)"
chk "both contents are there" "2" "$(grep -c '^AAA-CONTEXT$\|^ZZZ-CONTEXT$' "$SB/.config/agents/CLAUDE.md")"
ag off a-mod > /dev/null
chk "turning one off leaves no trace of it" "<!-- module: z-mod -->" "$(markers)"
chk "and drops its content" "0" "$(grep -c '^AAA-CONTEXT$' "$SB/.config/agents/CLAUDE.md" || true)"
# a module held by a bundle is inactive, so its instructions do not ride either
mod holding-bundle z-mod
ag apply > /dev/null
chk "a module held by a bundle appends nothing" "" "$(markers)"
ag on holding-bundle > /dev/null
chk "released, it appends again" "<!-- module: z-mod -->" "$(markers)"
# per-item degradation: a missing instructions file must not cost the rest
rm "$SB/z-ins.md"
ag on a-mod 2>"$SB/errm" >/dev/null
if grep -q 'module z-mod is active but .* is missing' "$SB/errm"; then ok "a missing instructions file warns"; else bad "missing instructions warns" "$(cat "$SB/errm")"; fi
chk "the module that still has its file composes" "<!-- module: a-mod -->" "$(markers)"
chk "and the profile survives the gap" "$(head -1 "$src")" "$(head -1 "$SB/.config/agents/CLAUDE.md")"
chk "apply still reports" "1" "$(ag apply 2>/dev/null | grep -c '^applied:')"
chk "instructions never touch the manifest" "module a-mod on" "$(grep '^module a-mod ' "$SB/.config/agents/manifest.conf")"

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILURES"; fi
exit "$fails"
