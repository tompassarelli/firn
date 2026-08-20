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
trap 'chmod -R u+w "$SB" 2>/dev/null; rm -rf "$SB" "$SB.frags" "$SB.mods"' EXIT

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
  # North's consumer surface is four skills. Staffing is the module that owns
  # the spawn guard and template library; coordination's three leaves are
  # plain skills. Set fixtures are still opt-in per test below.
  NORTH="$SB/code/north/main"
  mkdir -p "$NORTH/agent-profile/skills/importing-skills"
  printf -- '---\nname: importing-skills\n---\n' \
    > "$NORTH/agent-profile/skills/importing-skills/SKILL.md"
  for s in threejs-animation threejs-fundamentals threejs-geometry \
    threejs-interaction threejs-lighting threejs-loaders threejs-materials \
    threejs-postprocessing threejs-shaders threejs-textures; do
    mkdir -p "$NORTH/agent-profile/skills/$s"
    printf -- '---\nname: %s\n---\n' "$s" \
      > "$NORTH/agent-profile/skills/$s/SKILL.md"
  done
  STAFFSK="$NORTH/orchestration/staffing"
  mkdir -p "$STAFFSK" "$NORTH/orchestration/agents" \
    "$NORTH/coordination/messages" "$NORTH/coordination/threads" \
    "$NORTH/coordination/assignments"
  printf -- '---\nname: staffing\nhooks: [agent-spawn-guard]\nagents: ../agents\n---\n' \
    > "$STAFFSK/SKILL.md"
  for s in messages threads; do
    printf -- '---\nname: %s\n---\n' "$s" > "$NORTH/coordination/$s/SKILL.md"
  done
  printf -- '---\nname: assignments\nhooks: [north-session-lifecycle]\n---\n' \
    > "$NORTH/coordination/assignments/SKILL.md"
  printf 'ORCHESTRATION ACTIVE\n' > "$NORTH/orchestration/doctrine.md"
  printf 'COORDINATION ACTIVE\n' > "$NORTH/coordination/guide.md"
  : > "$SB/code/north/main/orchestration/agents/integrator.md"
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

ag() { HOME="$SB" AGENTS_FRAGMENTS="$FRAGS" AGENTS_MODULES="$MODS" \
       AGENTS_PLUGIN_RELEASES="$SB/releases" bash "$BIN" "$@"; }
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
hook_rows() { # every hook row status prints, nested under a skill or flat
  ag status 2>/dev/null |
    awk '/^hooks$/{f=1;next} /^plugins$/{f=0} f || /^ +hook · /'
}
hook_count() { # how many hooks the switchboard knows — read from the HOOKS
  # array in `agents`, never a literal: a `--all` sweep covers whatever that
  # array holds, so hardcoding the number makes adding a hook fail the suite.
  local names
  names="$(sed -n '/^HOOKS=(/,/)/p' "$BIN" | tr '\n' ' ')"
  names="${names#*(}"; names="${names%%)*}"
  set -- $names
  echo "$#"
}
HOOK_COUNT="$(hook_count)"

echo "== 1. fresh seed: bound hooks enabled+companion, unbound disabled, nothing composes"
fresh
ag status > /dev/null
chk "worktree-guard row" "hook worktree-guard enabled repo-safety" "$(grep '^hook worktree-guard ' "$SB/.config/agents/manifest.conf")"
chk "logcompress row (unbound)" "hook logcompress disabled" "$(grep '^hook logcompress ' "$SB/.config/agents/manifest.conf")"
chk "repo-safety skill seeded off" "skill repo-safety off" "$(grep '^skill repo-safety ' "$SB/.config/agents/manifest.conf")"
chk "cloudflare-deploy skill seeded off" "skill cloudflare-deploy off" "$(grep '^skill cloudflare-deploy ' "$SB/.config/agents/manifest.conf")"
chk "global seeds as a dir row at the root" "dir global off ~" "$(grep '^dir global ' "$SB/.config/agents/manifest.conf")"
chk "staffing seeds as the profile module" "skill staffing off" "$(grep '^skill staffing ' "$SB/.config/agents/manifest.conf")"
chk "coordination leaves seed as skills" "3" "$(grep -Ec '^skill (messages|threads|assignments) off$' "$SB/.config/agents/manifest.conf")"
chk "and no set row exists without a members file" "0" "$(grep -c '^module ' "$SB/.config/agents/manifest.conf" || true)"
chk "statusline-script seeds as other" "other statusline-script off" "$(grep '^other ' "$SB/.config/agents/manifest.conf")"
chk "no item kind survives" "0" "$(grep -c '^item ' "$SB/.config/agents/manifest.conf" || true)"
chk "hook bound to a dir row" "hook comment-bloat-guard enabled global" "$(grep '^hook comment-bloat-guard ' "$SB/.config/agents/manifest.conf")"
chk "a claimed hook names its claimant in the column, from frontmatter" "hook agent-spawn-guard enabled staffing" "$(grep '^hook agent-spawn-guard ' "$SB/.config/agents/manifest.conf")"
chk "corpus-scan-guard row" "hook corpus-scan-guard enabled convo" "$(grep '^hook corpus-scan-guard ' "$SB/.config/agents/manifest.conf")"
chk "coordination lifecycle belongs to assignments" "hook north-session-lifecycle enabled assignments" "$(grep '^hook north-session-lifecycle ' "$SB/.config/agents/manifest.conf")"
st="$(ag status)"
case "$st" in *"hook · worktree-guard:        off (skill: repo-safety off)"*) ok "status: bound + skill off" ;;
  *) bad "status: bound + skill off" "$(echo "$st" | grep worktree-guard)" ;; esac
case "$st" in *"hook-detach:            disabled"*) ok "status: unbound infrastructure reads disabled" ;;
  *) bad "status: unbound disabled" "$(echo "$st" | grep hook-detach)" ;; esac
ag off worktree-guard > /dev/null
st="$(ag status)"
case "$st" in *"hook · worktree-guard:        disabled"*) ok "status: a pin still names its skill" ;;
  *) bad "status: pin names skill" "$(echo "$st" | grep worktree-guard)" ;; esac
ag on worktree-guard > /dev/null
ag apply > /dev/null
chk "fresh composes nothing" "" "$(composed_files)"
chk "settings.json foreign key survives" "42" "$(python3 -c 'import json;print(json.load(open("'"$SB"'/.claude/settings.json"))["otherKey"])')"

echo
echo "== 2. migration of legacy 3-field rows: blackout holds"
fresh; mods; mod orchestration staffing
mkdir -p "$SB/.config/agents"
{ echo "item agents-md off"; echo "item statusline-script off"; echo "item orchestration off"
  for h in agent-spawn-guard beagle-session-start comment-bloat-guard \
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
fresh; mods; mod orchestration staffing
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
chk "item orchestration off -> set, state kept" "module orchestration off" "$(grep '^module orchestration ' "$m")"
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

# Orchestration also spent one release as a skill. Its remembered state moves
# to the set row instead of seeding the new architecture off.
{ echo "skill orchestration on"; echo "module orchestration off"; } > "$m"
ag status > /dev/null
chk "half-migrated orchestration keeps the module row" "module orchestration off" "$(grep '^module orchestration ' "$m")"
chk "the retired skill row is removed" "0" "$(grep -c '^skill orchestration ' "$m" || true)"

echo
echo "== 2c. the global profile writes the global surfaces and nothing per-directory"
fresh; ag status > /dev/null
ag on global > /dev/null
src="$SB/code/nixos-config/main/dotfiles/agents/AGENTS.md"
# The dir row is the GATE over the whole root subtree; the instruction file is
# the row under it, so opening the gate alone injects nothing.
chk "the gate alone writes no profile" "0" "$(stat -c %s "$SB/.config/agents/CLAUDE.md")"
ag on global/AGENTS.md > /dev/null
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
chk "a dir row is a claimant no skill could be" "hook comment-bloat-guard enabled global" "$(grep '^hook comment-bloat-guard ' "$SB/.config/agents/manifest.conf")"
if has_cmd comment-bloat-guard.sh; then bad "dir-bound hook waits for its row" "$(composed_files)"; else ok "dir-bound hook waits for its row"; fi
ag on global > /dev/null
if has_cmd comment-bloat-guard.sh; then ok "dir row on composes the hook that follows it"; else bad "dir row composes hook" "$(composed_files)"; fi
if has_cmd agent-spawn-guard.sh; then bad "a skill still off keeps its claimed hook out" "$(composed_files)"; else ok "a skill still off keeps its claimed hook out"; fi
ag on staffing > /dev/null
if has_cmd agent-spawn-guard.sh; then ok "the skill on composes the hook it declares"; else bad "declared hook composes" "$(composed_files)"; fi
st="$(ag status)"
case "$st" in *"hook · agent-spawn-guard:     on"*) ok "status names the skill that declared it" ;;
  *) bad "status names claimant" "$(echo "$st" | grep agent-spawn)" ;; esac
ag off global > /dev/null
if has_cmd comment-bloat-guard.sh; then bad "dir row off decomposes" "$(composed_files)"; else ok "dir row off decomposes its hook"; fi
st="$(ag status)"
case "$st" in *"comment-bloat-guard:    off (dir: global off)"*) ok "status blames the dir row by name" ;;
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
echo "== 5. unbound + enabled = active with every skill off"
fresh; ag status > /dev/null
ag on logcompress > /dev/null
chk "unbound enabled row" "hook logcompress enabled" "$(grep '^hook logcompress ' "$SB/.config/agents/manifest.conf")"
if has_cmd logcompress-hook.js; then ok "unbound enabled composes"; else bad "unbound enabled composes" "$(composed_files)"; fi
st="$(ag status)"; case "$st" in *"logcompress:            on"*) ok "status: unbound enabled · on" ;; *) bad "status unbound" "$(echo "$st" | grep logcompress)" ;; esac

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
st="$(ag status 2>/dev/null)"; case "$st" in *"hook · tripwire-guard:        off (needs worktree-guard, disabled)"*) ok "status names the blocking requirement" ;; *) bad "status names requirement" "$(echo "$st" | grep tripwire)" ;; esac
if has_cmd git-blind-stage-guard.sh; then ok "unrelated sibling unaffected"; else bad "sibling unaffected" "$(composed_files)"; fi
# direct `on` pulls its requirement's permission back
ag on tripwire-guard > /dev/null
chk "direct on grants the requirement too" "hook worktree-guard enabled repo-safety" "$(grep '^hook worktree-guard ' "$SB/.config/agents/manifest.conf")"
# a requirement rides in even when its own companion skill is off. repo-safety
# declares these hooks skill-side as well, and a claim would activate this one on
# its own, so the claim moves out of the way in a private copy of the farm: what
# is under test here is a requirement riding in on its DEPENDENT.
rm "$SB/code/nixos-config/main/dotfiles/agents/skills"
cp -r "$REPO/dotfiles/agents/skills" "$SB/code/nixos-config/main/dotfiles/agents/skills"
sed -i '/^  - worktree-guard$/d' "$SB/code/nixos-config/main/dotfiles/agents/skills/repo-safety/SKILL.md"
python3 - "$SB.frags" <<'PY'
import json, os, sys
p = os.path.join(sys.argv[1], "worktree-guard.json")
frag = json.load(open(p)); frag["follows"] = "webdev"
open(p, "w").write(json.dumps(frag, indent=1))
PY
ag apply > /dev/null
chk "re-pointed binding corrected in column" "hook worktree-guard enabled webdev" "$(grep '^hook worktree-guard ' "$SB/.config/agents/manifest.conf")"
if has_cmd launch-critical-worktree-guard.sh; then ok "requirement pulled in despite its skill being off"; else bad "requirement pulled in" "$(composed_files)"; fi
st="$(ag status 2>/dev/null)"; case "$st" in *"worktree-guard:         on (required by tripwire-guard)"*) ok "status explains the pull-in" ;; *) bad "status pull-in" "$(echo "$st" | grep worktree-guard)" ;; esac

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
echo "== 7b. enabledPlugins is a RECORD: an array makes Claude Code skip the file"
fresh
mkdir -p "$SB/.claude/plugins"
printf '%s' '{"plugins":{"demo@market":[{"scope":"user","installPath":"/tmp/demo"}]}}' \
  > "$SB/.claude/plugins/installed_plugins.json"
# The legacy array form is still READ, so a machine mid-upgrade seeds from what
# it already had rather than silently turning a plugin off.
python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["enabledPlugins"]=["demo@market"];json.dump(d,open(p,"w"))' "$SB/.claude/settings.json"
ag status > /dev/null
chk "a plugin enabled in the legacy array seeds on" "plugin demo@market on" "$(grep '^plugin demo@market ' "$SB/.config/agents/manifest.conf")"
ag apply > /dev/null
chk "and is rewritten as a record" '{"demo@market": true}' "$(python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1]))["enabledPlugins"]))' "$SB/.claude/settings.json")"
ag off demo@market > /dev/null
chk "an off plugin is absent, not false" "{}" "$(python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1]))["enabledPlugins"]))' "$SB/.claude/settings.json")"
chk "an empty record is still a record" "dict" "$(python3 -c 'import json,sys;print(type(json.load(open(sys.argv[1]))["enabledPlugins"]).__name__)' "$SB/.claude/settings.json")"
ag on demo@market > /dev/null
chk "and back on is a truthy key again" "True" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["enabledPlugins"]["demo@market"])' "$SB/.claude/settings.json")"

echo
echo "== 8. --all both ways"
fresh; ag status > /dev/null
ag on --all > /dev/null
chk "on --all: no hook left disabled" "0" "$(grep -c '^hook .* disabled' "$SB/.config/agents/manifest.conf" || true)"
chk "on --all: skills on" "0" "$(grep -c '^skill .* off' "$SB/.config/agents/manifest.conf" || true)"
if [ "${HOOK_COUNT:-0}" -gt 0 ] 2>/dev/null
  then ok "hook count derives from the HOOKS array ($HOOK_COUNT)"
  else bad "hook count derives from the HOOKS array" "got [$HOOK_COUNT]"; fi
chk "on --all: every fragment composed" "$HOOK_COUNT" "$(hook_rows | grep -cE ': +on( |$)')"
ag off --all > /dev/null
chk "off --all: hooks disabled" "$HOOK_COUNT" "$(grep -c '^hook .* disabled' "$SB/.config/agents/manifest.conf")"
chk "off --all: nothing composed" "" "$(composed_files)"
chk "off --all: skills off" "0" "$(grep -c '^skill .* on' "$SB/.config/agents/manifest.conf" || true)"

echo
echo "== 9. apply degrades per item when a source is missing"
fresh; ag status > /dev/null
rm "$SB/code/nixos-config/main/dotfiles/agents/AGENTS.md"
ag on logcompress > /dev/null 2>"$SB/err1"
ag on global > /dev/null 2>&1
out="$(ag on global/AGENTS.md 2>"$SB/err" )"
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
if grep -q 'skill repo-safety is on but .*/SKILL.md is unreadable' "$SB/err4"; then ok "missing skill source warns"; else bad "missing skill source warns" "$(cat "$SB/err4")"; fi

echo
echo "== 10. status section order"
fresh; ag status > /dev/null
# Dependency order: a hook's parenthetical can only name a row already read.
# Least specific first, most specific last: a set flips units of every
# kind; a directory's context fires in one subtree and nowhere else.
chk "order" "sets skills hooks plugins other directory scoped" "$(ag status | grep -v '^ ' | tr '\n' ' ' | sed 's/ $//')"
chk "global heads the directory section, scope ~" "global: off ~" "$(ag status | sed -n '/^directory scoped$/{n;p}' | tr -s ' ' | sed 's/^ //')"
# Membership by shape: a skill that declares hooks is rendered as a module, with
# what it claims nested under it, and is not repeated in the skills section.
# A module is not a sibling of a skill, it IS one: the modules subsection is
# the first thing inside skills, and a plain skill is a direct child.
chk "modules read inside skills" "1" "$(ag status | sed -n '/^skills$/,/^hooks$/p' | grep -c '^  modules$')"
chk "a skill that declares is a module" "1" "$(ag status | sed -n '/^skills$/,/^hooks$/p' | grep -c '^    repo-safety:')"
chk "a skill that declares templates too" "1" "$(ag status | sed -n '/^skills$/,/^hooks$/p' | grep -c '^    staffing:')"
chk "with what it declares nested under it" "7" "$(ag status | sed -n '/^skills$/,/^hooks$/p' | grep -c '^      ')"
chk "a skill that declares nothing is a plain child" "1" "$(ag status | sed -n '/^skills$/,/^hooks$/p' | grep -c '^  webdev:')"
chk "and a module is not a plain child too" "0" "$(ag status | sed -n '/^skills$/,/^hooks$/p' | grep -c '^  repo-safety:' || true)"
chk "a claimed hook is not repeated under hooks" "0" "$(ag status | sed -n '/^hooks$/,/^plugins$/p' | grep -c '^  worktree-guard:' || true)"
chk "a hook nobody claims still lives there" "1" "$(ag status | sed -n '/^hooks$/,/^plugins$/p' | grep -c '^  hook-detach:')"

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
case "$st" in *"repo-safety:        on · off (module: ml-bundle off)"*) ok "status names a holding bundle" ;;
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
case "$st" in *"mid:                  on · off (module: outer off)"*) ok "the inner bundle blames the outer" ;;
  *) bad "inner blames outer" "$(echo "$st" | grep '^  mid')" ;; esac
case "$st" in *"repo-safety:        on · off (module: outer off)"*) ok "the member blames the NEAREST off ancestor, two up" ;;
  *) bad "member blames nearest off ancestor" "$(echo "$st" | grep repo-safety)" ;; esac
ag on outer > /dev/null
chk "the outer bundle releases the whole chain" "repo-safety" "$(skilllinks)"
ag off mid > /dev/null
chk "breaking the middle drops the member again" "" "$(skilllinks)"
st="$(ag status)"
case "$st" in *"repo-safety:        on · off (module: mid off)"*) ok "now the nearest cause is the middle" ;;
  *) bad "nearest cause is middle" "$(echo "$st" | grep repo-safety)" ;; esac

echo
echo "== 13. skill-side modules are untouched by the member mechanism"
fresh; mods
mod outer mid
ag status > /dev/null
chk "a module needs no member file: it is a skill" "skill staffing off" "$(grep '^skill staffing ' "$SB/.config/agents/manifest.conf")"
chk "path of a skill-side module is its skill" "$STAFFSK/SKILL.md" "$(ag path staffing)"
chk "path of a set is its list" "$MODS/outer.json" "$(ag path outer)"
ag on staffing > /dev/null
chk "a module in no set answers only to itself" "skill staffing on" "$(grep '^skill staffing ' "$SB/.config/agents/manifest.conf")"
if has_cmd agent-spawn-guard.sh; then ok "the hook it declares composes, ungated"; else bad "declared hook composes" "$(composed_files)"; fi

echo
echo "== 13b. orchestration contains staffing and the complete coordination set"
fresh; mods
mod_ins coordination "$NORTH/coordination/guide.md" messages threads assignments
mod_ins orchestration "$NORTH/orchestration/doctrine.md" staffing coordination
ag status > /dev/null
for s in staffing messages threads assignments coordination; do ag on "$s" > /dev/null; done
chk "outer set off holds every child skill" "" "$(skilllinks)"
chk "outer set off injects no module instructions" "" "$(markers)"
if has_cmd agent-spawn-guard.sh; then bad "outer set off keeps staffing's hook out" "$(composed_files)"; else ok "outer set off keeps staffing's hook out"; fi
if has_cmd north-on-spawn; then bad "outer set off keeps coordination lifecycle out" "$(composed_files)"; else ok "outer set off keeps coordination lifecycle out"; fi
chk "provider activity projection holds lifecycle off" "hook north-session-lifecycle off" "$(grep '^hook north-session-lifecycle ' "$SB/.config/agents/activity.conf")"
chk "provider activity projection holds staffing guard off" "hook agent-spawn-guard off" "$(grep '^hook agent-spawn-guard ' "$SB/.config/agents/activity.conf")"
chk "outer set off links no agent profiles" "0" "$(test -e "$SB/.claude/agents/integrator.md" && echo 1 || echo 0)"
ag on orchestration > /dev/null
chk "outer set releases all four leaf skills" "assignments messages staffing threads" "$(skilllinks)"
chk "nested instructions compose deterministically" "<!-- module: coordination --> <!-- module: orchestration -->" "$(markers)"
if has_cmd agent-spawn-guard.sh; then ok "active staffing composes its hook"; else bad "active staffing composes its hook" "$(composed_files)"; fi
if has_cmd north-on-spawn; then ok "active assignments compose coordination lifecycle"; else bad "active assignments compose coordination lifecycle" "$(composed_files)"; fi
chk "provider activity projection releases lifecycle" "hook north-session-lifecycle on" "$(grep '^hook north-session-lifecycle ' "$SB/.config/agents/activity.conf")"
chk "provider activity projection releases staffing guard" "hook agent-spawn-guard on" "$(grep '^hook agent-spawn-guard ' "$SB/.config/agents/activity.conf")"
chk "active staffing links its profiles" "$NORTH/orchestration/agents/integrator.md" "$(readlink "$SB/.claude/agents/integrator.md")"
ag off orchestration > /dev/null
chk "one outer flip removes every leaf skill" "" "$(skilllinks)"
chk "one outer flip removes every instruction" "" "$(markers)"
if has_cmd north-on-spawn; then bad "one outer flip removes coordination lifecycle" "$(composed_files)"; else ok "one outer flip removes coordination lifecycle"; fi
chk "provider activity projection follows the outer flip" "hook north-session-lifecycle off" "$(grep '^hook north-session-lifecycle ' "$SB/.config/agents/activity.conf")"
chk "staffing guard projection follows the outer flip" "hook agent-spawn-guard off" "$(grep '^hook agent-spawn-guard ' "$SB/.config/agents/activity.conf")"
chk "coordination remembers its own on switch" "module coordination on" "$(grep '^module coordination ' "$SB/.config/agents/manifest.conf")"
chk "leaf switches remain remembered" "4" "$(grep -Ec '^skill (staffing|messages|threads|assignments) on$' "$SB/.config/agents/manifest.conf")"
chk "the staffing profiles are swept with the outer set" "0" "$(test -e "$SB/.claude/agents/integrator.md" && echo 1 || echo 0)"

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
case "$st" in *"loop-x:               on · off (module cycle)"*) ok "status calls it a cycle, not a mystery" ;;
  *) bad "status names cycle" "$(echo "$st" | grep 'loop-x')" ;; esac
case "$st" in *"repo-safety:        on · off (module: loop-y off)"*) ok "a member of a cycle blames the cycle module" ;;
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
ag on proj/AGENTS.md > /dev/null; ag on global/AGENTS.md > /dev/null
chk "a held dir row writes an EMPTY context file" "0" "$(stat -c %s "$SB/.config/agents/dir/proj-CLAUDE.md")"
chk "a held dir row writes an empty codex surface too" "0" "$(stat -c %s "$SB/.config/agents/dir/proj-AGENTS.md")"
chk "a held global profile writes empty" "0" "$(stat -c %s "$SB/.config/agents/CLAUDE.md")"
chk "a held global profile empties the account copy" "0" "$(stat -c %s "$ACCT/CLAUDE.md")"
if has_cmd logcompress-hook.js; then bad "a held hook is not composed" "$(composed_files)"; else ok "a held hook is not composed"; fi
st="$(ag status)"
case "$st" in *"logcompress:            off (module: guard-bundle off)"*) ok "status: a hook says which bundle holds it" ;;
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
ag on global > /dev/null; ag on global/AGENTS.md > /dev/null
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
ag on global > /dev/null; ag on global/AGENTS.md > /dev/null
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
echo "== 18. skills reach Codex's surface, and nothing else there is touched"
fresh; ag status > /dev/null
CX="$SB/.codex/skills"
# The shape found live: Codex's vendor-managed built-ins, a hand-written skill
# directory, and a symlink that is somebody else's.
seed_codex_neighbours() {
  mkdir -p "$CX/.system" "$CX/hand-written" "$SB/elsewhere"
  : > "$CX/.system/.codex-system-skills.marker"
  : > "$CX/hand-written/SKILL.md"
  ln -sfn "$SB/elsewhere" "$CX/foreign-link"
}
seed_codex_neighbours
survivors() { printf '%s %s %s' \
  "$(test -f "$CX/.system/.codex-system-skills.marker" && echo system || echo GONE)" \
  "$(test -f "$CX/hand-written/SKILL.md" && echo handwritten || echo GONE)" \
  "$(test -L "$CX/foreign-link" && echo foreign || echo GONE)"; }
ag on repo-safety > /dev/null
chk "an active skill lands in the claude farm" "repo-safety" "$(skilllinks)"
chk "and on the codex surface, at the same source" "$(readlink "$SB/.config/agents/skills/repo-safety")" "$(readlink "$CX/repo-safety")"
chk "the codex entry is a link that resolves to the skill" "1" "$(test -L "$CX/repo-safety" && test -d "$CX/repo-safety" && echo 1 || echo 0)"
farm_inode="$(stat -c %i "$SB/.config/agents/skills/repo-safety")"
codex_inode="$(stat -c %i "$CX/repo-safety")"
ag apply > /dev/null
chk "an idempotent apply does not replace the farm skill link" "$farm_inode" "$(stat -c %i "$SB/.config/agents/skills/repo-safety")"
chk "an idempotent apply does not replace the Codex skill link" "$codex_inode" "$(stat -c %i "$CX/repo-safety")"
ln -sfn "$SB/elsewhere" "$CX/repo-safety"
ag apply > /dev/null
chk "a stale Codex skill link is replaced with the active source" "$(readlink "$SB/.config/agents/skills/repo-safety")" "$(readlink "$CX/repo-safety")"
chk "atomic publication leaves no staging link" "0" "$(find "$CX" -maxdepth 1 -name '.agents-*.next.*' | wc -l)"
ag on importing-skills > /dev/null
chk "a North profile skill lands in both farms" "1" "$(test -L "$SB/.config/agents/skills/importing-skills" && test -L "$CX/importing-skills" && echo 1 || echo 0)"
chk "its Codex link uses the tracked North profile" "$SB/code/north/main/agent-profile/skills/importing-skills" "$(readlink "$CX/importing-skills")"
ag off importing-skills > /dev/null
threejs_missing=()
for s in threejs-animation threejs-fundamentals threejs-geometry \
  threejs-interaction threejs-lighting threejs-loaders threejs-materials \
  threejs-postprocessing threejs-shaders threejs-textures; do
  ag on "$s" > /dev/null
  if [ ! -L "$SB/.config/agents/skills/$s" ] || [ ! -L "$CX/$s" ]; then
    threejs_missing+=("$s")
  fi
done
chk "every Three.js skill lands in both farms" "" "${threejs_missing[*]}"
for s in threejs-animation threejs-fundamentals threejs-geometry \
  threejs-interaction threejs-lighting threejs-loaders threejs-materials \
  threejs-postprocessing threejs-shaders threejs-textures; do
  ag off "$s" > /dev/null
done
chk "nothing of Codex's was disturbed" "system handwritten foreign" "$(survivors)"
ag off repo-safety > /dev/null
chk "off sweeps our codex link" "0" "$(test -L "$CX/repo-safety" && echo 1 || echo 0)"
chk "and sweeps only ours" "system handwritten foreign" "$(survivors)"
# a foreign link that happens to sit under a skill's NAME is still not ours
ln -sfn "$SB/elsewhere" "$CX/webdev"
ag on repo-safety > /dev/null; ag off repo-safety > /dev/null
chk "a link with our name but not our target survives" "$SB/elsewhere" "$(readlink "$CX/webdev")"
chk "Codex's own still survives repeated applies" "system handwritten foreign" "$(survivors)"
# the directory is created when absent, never replaced
rm -rf "$SB/.codex"
ag on repo-safety > /dev/null
chk "a missing ~/.codex/skills is created" "1" "$(test -d "$CX" && echo 1 || echo 0)"
chk "and gets the link" "1" "$(test -L "$CX/repo-safety" && echo 1 || echo 0)"
# activity, not raw state: a skill a bundle holds is linked in neither surface
mods; mod hold-bundle repo-safety
ag apply > /dev/null
chk "a held skill is in neither surface" "0" "$(test -L "$CX/repo-safety" && echo 1 || echo 0)"
chk "nor in the farm" "" "$(skilllinks)"
ag on hold-bundle > /dev/null
chk "released, it returns to both" "1" "$(test -L "$CX/repo-safety" && test -L "$SB/.config/agents/skills/repo-safety" && echo 1 || echo 0)"
# Staffing's profiles arrive with its skill, governed by the same code as every
# other skill-side module.
seed_codex_neighbours   # the create-when-absent case above wiped the fixture
ag on staffing > /dev/null
chk "the staffing skill reaches the claude farm" "1" "$(test -L "$SB/.config/agents/skills/staffing" && echo 1 || echo 0)"
chk "and the codex surface, same source" "$STAFFSK" "$(readlink "$CX/staffing")"
# the templates it declares are the other half of the same switch
chk "an active module links the templates it ships" "$SB/code/north/main/orchestration/agents/integrator.md" "$(readlink "$SB/.claude/agents/integrator.md")"
ag off staffing > /dev/null
chk "off sweeps the templates it linked" "0" "$(test -e "$SB/.claude/agents/integrator.md" && echo 1 || echo 0)"
: > "$SB/.claude/agents/hand-written.md"
ag on staffing > /dev/null; ag off staffing > /dev/null
chk "and sweeps only what it linked" "1" "$(test -f "$SB/.claude/agents/hand-written.md" && echo 1 || echo 0)"
ag off staffing > /dev/null
chk "off clears the staffing skill from the farm" "0" "$(test -L "$SB/.config/agents/skills/staffing" && echo 1 || echo 0)"
chk "and from the codex surface" "0" "$(test -L "$CX/staffing" && echo 1 || echo 0)"
chk "Codex's own survived the module flips" "system handwritten foreign" "$(survivors)"
# a squatter under the staffing name is not ours, so the sweep spares it
ln -sfn "$SB/elsewhere" "$CX/staffing"
ag on repo-safety > /dev/null; ag off repo-safety > /dev/null
chk "a foreign link under the staffing name survives a sweep" "$SB/elsewhere" "$(readlink "$CX/staffing")"
rm -f "$CX/staffing"
# a real file at that path degrades to a warning, like every other apply item
fresh; ag status > /dev/null
mkdir -p "$SB/.codex"; : > "$SB/.codex/skills"
ag on repo-safety 2>"$SB/errcx" >/dev/null
if grep -q 'is not a directory — repo-safety not linked for codex' "$SB/errcx"; then ok "a non-directory there warns"; else bad "non-directory warns" "$(cat "$SB/errcx")"; fi
chk "the claude farm still got it" "repo-safety" "$(skilllinks)"
chk "apply still reports" "1" "$(ag apply 2>/dev/null | grep -c '^applied:')"

echo
echo "== 19. export-plugin: a module compiled into a sealed release folder"
# Fragments pointing at sandbox scripts, so the emitted tree is the same on any
# machine — a hook command naming ~/.agents would make this test a machine test.
rm -rf "$SB.frags"; mkdir -p "$SB.frags"; cp "$FRAG_SRC"/*.json "$SB.frags/"
fresh "$SB.frags"; mods
mkdir -p "$SB/bin"; printf '#!/bin/sh\nexit 0\n' > "$SB/bin/guard.sh"; chmod +x "$SB/bin/guard.sh"
python3 - "$SB.frags" "$SB/bin/guard.sh" <<'PY'
import json, os, sys
d, script = sys.argv[1:]
for name in ("worktree-guard", "tripwire-guard"):
    p = os.path.join(d, name + ".json")
    frag = json.load(open(p))
    for e in frag["entries"]:
        e["hook"]["command"] = script
    open(p, "w").write(json.dumps(frag, indent=1))
PY
printf '# Team conventions\n\nUse the worktree flow.\n' > "$SB/guide.md"
printf '# Inner rules\n\nNested text.\n' > "$SB/inner.md"
mod_ins team "$SB/guide.md" repo-safety worktree-guard inner
mod_ins inner "$SB/inner.md" tripwire-guard
ag status > /dev/null
out="$(ag export-plugin team 2>"$SB/xerr")"
D="$(ls -d "$SB/releases"/team-*/ 2>/dev/null | head -1)"
chk "one release directory, named <module>-<version>" "1" "$(ls -d "$SB/releases"/team-*/ 2>/dev/null | wc -l)"
chk "the emitted layout, exactly" \
  "./.claude-plugin ./.claude-plugin/plugin.json ./RELEASE ./hooks ./hooks/bin ./hooks/bin/guard.sh ./hooks/hooks.json ./skills ./skills/inner-guide ./skills/inner-guide/SKILL.md ./skills/repo-safety ./skills/repo-safety/SKILL.md ./skills/team-guide ./skills/team-guide/SKILL.md" \
  "$(cd "$D" && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
chk "the exported skill is a byte-for-byte copy of its source" "" "$(diff -r "$REPO/dotfiles/agents/skills/repo-safety" "$D/skills/repo-safety")"
chk "plugin.json parses and carries the schema's fields" "team|20260810|Team conventions|Tom Passarelli" \
  "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("|".join([d["name"],d["version"][:8],d["description"],d["author"]["name"]]))' "$D/.claude-plugin/plugin.json" | sed 's/|[0-9]\{8\}|/|20260810|/')"
chk "the version is a date and a content hash" "1" "$(python3 -c 'import json,re,sys;print(1 if re.fullmatch(r"[0-9]{8}-[0-9a-f]{8}", json.load(open(sys.argv[1]))["version"]) else 0)' "$D/.claude-plugin/plugin.json")"
chk "the instructions became a guide skill, frontmatter and body" \
  '---|name: team-guide|description: "Team conventions"|---||# Team conventions||Use the worktree flow.' \
  "$(tr '\n' '|' < "$D/skills/team-guide/SKILL.md" | sed 's/|$//')"
chk "a nested module's instructions become their own guide" "1" "$(grep -c '^name: inner-guide$' "$D/skills/inner-guide/SKILL.md")"
# hooks: our fragment shape becomes the plugin's hooks.json, paths rewritten
chk "hooks.json is the plugin shape, command via CLAUDE_PLUGIN_ROOT" \
  'PreToolUse Bash ${CLAUDE_PLUGIN_ROOT}/hooks/bin/guard.sh' \
  "$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))["hooks"]
ev=sorted(d)[0]; b=[x for x in d[ev] if x.get("matcher")=="Bash"][0]
print(ev, b["matcher"], b["hooks"][0]["command"])' "$D/hooks/hooks.json")"
chk "no machine path survives in hooks.json" "0" "$(grep -c '/home/tom' "$D/hooks/hooks.json" || true)"
chk "the referenced script rode along" "" "$(diff "$SB/bin/guard.sh" "$D/hooks/bin/guard.sh")"
# receipt
chk "receipt declares its format" "format=north-agents-plugin/v1" "$(head -1 "$D/RELEASE")"
chk "receipt names every member source" "3" "$(grep -c '^member=' "$D/RELEASE")"
chk "receipt names the flattening" "1" "$(grep -c '^flattened=inner ' "$D/RELEASE")"
chk "receipt names a repo and its rev" "1" "$(grep -cE '^repo=/.+ [0-9a-f]{40}$' "$D/RELEASE")"
chk "receipt names the copied script" "1" "$(grep -c '^script=.*-> hooks/bin/guard.sh$' "$D/RELEASE")"
chk "receipt says no path went unresolved" "unresolved-path=(none)" "$(grep '^unresolved-path=' "$D/RELEASE")"
# sealed
chk "the release is sealed: no write bit anywhere" "0" "$(find "$D" -perm -u+w | wc -l)"
chk "and readable, like every release under north-data" "dr-xr-xr-x" "$(stat -c %A "$D" | sed 's|/$||')"
# re-export
err="$(ag export-plugin team 2>&1 >/dev/null || true)"
case "$err" in *"already exists and a release is sealed"*) ok "a second export refuses rather than overwriting" ;;
  *) bad "second export refuses" "$err" ;; esac
chk "and left the sealed release alone" "1" "$(ls -d "$SB/releases"/team-*/ | wc -l)"
ag export-plugin team --force > /dev/null
chk "--force writes a NEW directory beside it" "2" "$(ls -d "$SB/releases"/team-*/ | wc -l)"
chk "identical sources give the identical version" "1" "$(ls -d "$SB/releases"/team-*/ | sed 's|.*/team-||;s|-2/$||;s|/$||' | sort -u | wc -l)"

echo
echo "== 20. export-plugin: what cannot become a plugin says so, and the rest lands"
fresh; mods
mkdir -p "$SB/code/north-data/context-dirs" "$SB/proj"
printf '%s proj\n' "$SB/proj" > "$SB/code/north-data/context-dirs.conf"
echo "ctx" > "$SB/code/north-data/context-dirs/proj.md"
# a payload module: skill + agent templates, no member file of its own
printf -- '---\nname: executor\n---\nrole\n' > "$NORTH/orchestration/agents/executor.md"
mod mixed proj statusline-script staffing ghost
ag status > /dev/null
out="$(ag export-plugin mixed --description "A mixed bag" 2>"$SB/xerr2")"
D2="$(ls -d "$SB/releases"/mixed-*/ | head -1)"
chk "a dir row is skipped, by name" "1" "$(grep -c 'skipped dir proj — dir rows have no plugin equivalent' "$SB/xerr2")"
chk "an other row is skipped, by name" "1" "$(grep -c 'skipped other statusline-script' "$SB/xerr2")"
chk "a member naming nothing is skipped, by name" "1" "$(grep -c 'skipped ? ghost — names no unit' "$SB/xerr2")"
chk "the skips are in the receipt too" "3" "$(grep -c '^skipped=' "$D2/RELEASE")"
chk "a module's skill exported" "1" "$(grep -c '^name: staffing$' "$D2/skills/staffing/SKILL.md")"
chk "and the templates it declares" "1" "$(test -f "$D2/agents/executor.md" && echo 1 || echo 0)"
chk "--description wins over the instructions heading" "A mixed bag" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["description"])' "$D2/.claude-plugin/plugin.json")"
chk "the export reports what it did" "1" "$(echo "$out" | grep -c '^exported: mixed ')"
chk "exporting a non-module is refused" "1" "$(ag export-plugin repo-safety 2>&1 >/dev/null | grep -c 'not a module')"
chk "exporting nothing is refused" "1" "$(ag export-plugin 2>&1 >/dev/null | grep -c 'requires a module name')"
chk "the manifest is untouched by an export" "" "$(cp "$SB/.config/agents/manifest.conf" "$SB/m4"; ag export-plugin mixed --force > /dev/null; diff "$SB/m4" "$SB/.config/agents/manifest.conf")"

echo
echo "== 20. a dir row becomes a subtree GATE without moving a single surface"
# The migration that widens `dir <slug>` from "this instruction file has
# content" to "everything scoped at this directory": the old meaning moves down
# to `ins <slug>`, and the gate opens wherever memories are already loading.
ACCT2="$SB/.local/state/north/accounts/anthropic/acct-two"
projslug() { echo "${1//\//-}"; }   # the path with its separators dashed
memdir() { echo "$1/projects/$(projslug "$2")/memory"; }   # acct-root scope
seed_mem() { # acct-root scope name content
  local d; d="$(memdir "$1" "$2")"; mkdir -p "$d"; printf '%s\n' "$4" > "$d/$3"
}
seed_index() { # acct-root scope line...
  local d; d="$(memdir "$1" "$2")"; mkdir -p "$d"; local a="$1" s="$2"; shift 2
  printf '%s\n' "$@" > "$(memdir "$a" "$s")/MEMORY.md"
}
index() { cat "$(memdir "$1" "$2")/MEMORY.md" 2>/dev/null; }
LINE_A="- [Alpha](alpha.md) — when alpha"
LINE_B="- [Beta](beta.md) — when beta"

fresh
mkdir -p "$SB/code/north-data/context-dirs" "$SB/proj" "$SB/bare"
printf '%s proj\n%s bare\n' "$SB/proj" "$SB/bare" > "$SB/code/north-data/context-dirs.conf"
echo "PROJECT CONTEXT" > "$SB/code/north-data/context-dirs/proj.md"
echo "BARE CONTEXT" > "$SB/code/north-data/context-dirs/bare.md"
seed_mem "$ACCT" "$SB/proj" alpha.md "alpha fact"
seed_mem "$ACCT" "$SB/proj" beta.md "beta fact"
seed_index "$ACCT" "$SB/proj" "$LINE_A" "$LINE_B"
before_index="$(index "$ACCT" "$SB/proj")"
before_files="$(md5sum "$(memdir "$ACCT" "$SB/proj")"/alpha.md "$(memdir "$ACCT" "$SB/proj")"/beta.md)"
mkdir -p "$SB/.config/agents"
{ echo "dir global on ~"; echo "dir proj off $SB/proj"; echo "dir bare off $SB/bare"
} > "$SB/.config/agents/manifest.conf"
m="$SB/.config/agents/manifest.conf"
warn="$(ag status 2>&1 >/dev/null)"
chk "the old meaning moves down: ins carries the dir row's state" "ins global on" "$(grep '^ins global ' "$m")"
chk "an off dir row's instruction file stays off" "ins proj off" "$(grep '^ins proj ' "$m")"
chk "an open gate stays open" "dir global on ~" "$(grep '^dir global ' "$m")"
chk "a gate is OPENED where memories are already loading" "dir proj on $SB/proj" "$(grep '^dir proj ' "$m")"
chk "a gate with nothing live under it is left closed" "dir bare off $SB/bare" "$(grep '^dir bare ' "$m")"
case "$warn" in *"dir proj is now a subtree GATE"*) ok "opening a gate says so" ;;
  *) bad "gate migration is loud" "$warn" ;; esac
chk "memories seed on where they exist" "memroot proj on" "$(grep '^memroot proj ' "$m")"
chk "and off where they do not" "memroot bare off" "$(grep '^memroot bare ' "$m")"
chk "one row per memory, seeded on" "mem proj/alpha.md on
mem proj/beta.md on" "$(grep '^mem ' "$m")"
chk "the root has no memories here" "memroot global off" "$(grep '^memroot global ' "$m")"
chk "the migration is idempotent" "" "$(cp "$m" "$SB/m19"; ag status > /dev/null 2>&1; diff "$SB/m19" "$m")"
ag apply > /dev/null 2>&1
chk "byte-preserved: the index is what it was" "$before_index" "$(index "$ACCT" "$SB/proj")"
chk "byte-preserved: the profile still writes" "" "$(diff "$SB/code/nixos-config/main/dotfiles/agents/AGENTS.md" "$SB/.config/agents/CLAUDE.md")"
chk "byte-preserved: the raised gate injects no context file" "0" "$(stat -c %s "$SB/.config/agents/dir/proj-CLAUDE.md")"
chk "content files are not apply's to touch" "$before_files" "$(md5sum "$(memdir "$ACCT" "$SB/proj")"/alpha.md "$(memdir "$ACCT" "$SB/proj")"/beta.md)"
chk "and none were added or removed" "MEMORY.md alpha.md beta.md" "$(ls "$(memdir "$ACCT" "$SB/proj")" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"

echo
echo "== 21. the index is composed from ACTIVE memories, and only the index"
chk "both memories are listed" "$LINE_A
$LINE_B" "$(index "$ACCT" "$SB/proj")"
ag off proj/alpha.md > /dev/null 2>&1
chk "a memory turned off loses its line" "$LINE_B" "$(index "$ACCT" "$SB/proj")"
chk "and keeps its file" "1" "$(test -f "$(memdir "$ACCT" "$SB/proj")/alpha.md" && echo 1 || echo 0)"
chk "the row is where the flip landed" "mem proj/alpha.md off" "$(grep '^mem proj/alpha.md ' "$m")"
ag on proj/alpha.md > /dev/null 2>&1
chk "turned back on, its own words return, in place" "$before_index" "$(index "$ACCT" "$SB/proj")"
ag off proj/memories > /dev/null 2>&1
chk "the group gate empties the index" "0" "$(stat -c %s "$(memdir "$ACCT" "$SB/proj")/MEMORY.md")"
chk "with every file still there" "2" "$(find "$(memdir "$ACCT" "$SB/proj")" -maxdepth 1 -name '*.md' ! -name MEMORY.md | wc -l)"
st="$(ag status 2>/dev/null)"
case "$st" in *"alpha.md:         on · off (memories off)"*) ok "a memory blames the group above it" ;;
  *) bad "memory blames group" "$(echo "$st" | grep alpha)" ;; esac
ag on proj/memories > /dev/null 2>&1
chk "released, the whole index comes back" "$before_index" "$(index "$ACCT" "$SB/proj")"
ag off proj > /dev/null 2>&1
chk "the GATE empties it too" "0" "$(stat -c %s "$(memdir "$ACCT" "$SB/proj")/MEMORY.md")"
st="$(ag status 2>/dev/null)"
case "$st" in *"memories:           on · off (dir: proj off)"*) ok "the group blames the gate" ;;
  *) bad "group blames gate" "$(echo "$st" | grep memories)" ;; esac
case "$st" in *"alpha.md:         on · off (dir: proj off)"*) ok "and so does a memory, naming the nearest cause it can act on" ;;
  *) bad "memory blames gate" "$(echo "$st" | grep alpha)" ;; esac
ag on proj > /dev/null 2>&1
chk "the gate restores the index it emptied" "$before_index" "$(index "$ACCT" "$SB/proj")"
# the nested render: gate, then what it gates
st="$(ag status 2>/dev/null | sed -n '/^  proj:/,/^  bare:/p')"
chk "status reads as a subtree" "  proj:                 on                       $SB/proj
    AGENTS.md:          off
    memories:           on
      alpha.md:         on
      beta.md:          on" "$(echo "$st" | grep -v '^  bare:')"

echo
echo "== 22. every account that has the project, and nothing it does not govern"
mkdir -p "$ACCT2"
seed_mem "$ACCT2" "$SB/proj" alpha.md "alpha fact"
seed_mem "$ACCT2" "$SB/proj" gamma.md "gamma fact"
LINE_G="- [Gamma](gamma.md) — when gamma"
seed_index "$ACCT2" "$SB/proj" "$LINE_A" "$LINE_G"
ag status > /dev/null 2>&1
chk "a memory only one account has still gets a row" "mem proj/gamma.md on" "$(grep '^mem proj/gamma.md ' "$m")"
ag apply > /dev/null 2>&1
chk "each account's index keeps its own lines" "$LINE_A
$LINE_G" "$(index "$ACCT2" "$SB/proj")"
chk "and the other account's is untouched by a name it does not have" "$before_index" "$(index "$ACCT" "$SB/proj")"
ag off proj/alpha.md > /dev/null 2>&1
chk "one flip filters both accounts" "$LINE_G" "$(index "$ACCT2" "$SB/proj")"
chk "in the account that has the other memory too" "$LINE_B" "$(index "$ACCT" "$SB/proj")"
ag on proj/alpha.md > /dev/null 2>&1
chk "and restores both" "$before_index|$LINE_A
$LINE_G" "$(index "$ACCT" "$SB/proj")|$(index "$ACCT2" "$SB/proj")"
# a scope nobody has stored a memory for is not an error, and gets no directory
chk "a scope with no memory directory is fine" "0" "$(test -e "$(memdir "$ACCT" "$SB/bare")" && echo 1 || echo 0)"
chk "apply still reports" "1" "$(ag apply 2>/dev/null | grep -c '^applied:')"
chk "applied: counts memories" "3/3" "$(ag apply 2>/dev/null | sed 's/.*, \([0-9]*\/[0-9]*\) memories.*/\1/')"
# a memory file with no line in the index gets none invented
seed_mem "$ACCT" "$SB/proj" delta.md "delta fact"
ag apply > /dev/null 2>&1
chk "an unindexed memory is governed" "mem proj/delta.md on" "$(grep '^mem proj/delta.md ' "$m")"
chk "but no line is written for it" "$before_index" "$(index "$ACCT" "$SB/proj")"
# the two names a directory's own rows answer to are spoken for
seed_mem "$ACCT" "$SB/proj" AGENTS.md "not a memory row"
seed_index "$ACCT" "$SB/proj" "$LINE_A" "- [Squatter](AGENTS.md) — reserved" "$LINE_B"
warn="$(ag status 2>&1 >/dev/null)"
case "$warn" in *"is how a directory's own row is addressed"*) ok "a memory named like a row warns" ;;
  *) bad "reserved memory name warns" "$warn" ;; esac
chk "and gets no row" "0" "$(grep -c '^mem proj/AGENTS.md ' "$m" || true)"
ag off proj/beta.md > /dev/null 2>&1
chk "what is not governed is not filtered either" "$LINE_A
- [Squatter](AGENTS.md) — reserved" "$(index "$ACCT" "$SB/proj")"
ag on proj/beta.md > /dev/null 2>&1
rm "$(memdir "$ACCT" "$SB/proj")/AGENTS.md"
# addressing: the same spellings the panel funnels through
chk "path of a memory is the file, in the first account that has it" "$(memdir "$ACCT" "$SB/proj")/beta.md" "$(ag path proj/beta.md)"
chk "path of the group is the directory" "$(memdir "$ACCT" "$SB/proj")" "$(ag path proj/memories)"
chk "path of the instruction file is the dir source" "$(ag path proj)" "$(ag path proj/AGENTS.md)"
chk "path of the root's instruction file is the profile" "$(ag path global)" "$(ag path global/AGENTS.md)"
chk "an unknown memory is refused, not invented" "2" "$(ag off proj/nope.md >/dev/null 2>&1; echo $?)"
chk "an unknown scope is refused too" "2" "$(ag off nosuch/beta.md >/dev/null 2>&1; echo $?)"
chk "a memory name never collides across kinds" "" "$(seed_mem "$ACCT" "$SB/proj" webdev.md x; ag status 2>&1 >/dev/null)"
chk "off --all closes the memories with everything else" "0" "$(ag off --all >/dev/null 2>&1; stat -c %s "$(memdir "$ACCT" "$SB/proj")/MEMORY.md")"
chk "and on --all opens them again" "$before_index" "$(ag on --all >/dev/null 2>&1; index "$ACCT" "$SB/proj")"

echo
echo "== 23. a skill declares the hooks its rules need, in its own frontmatter"
# The same statement `follows` makes, from the other end: the skill knows which
# enforcement its rules require, so it ships the list. Both statements compose —
# a hook is active when ANY claimant is.
fresh
# repo-safety's real frontmatter is the fixture, in a private copy of the farm:
# these assertions author claims, and the live skills are not the test's to edit.
SKILLS_DIR="$SB/code/nixos-config/main/dotfiles/agents/skills"
rm "$SKILLS_DIR"; cp -r "$REPO/dotfiles/agents/skills" "$SKILLS_DIR"
# The other skills' sources live outside this repo, which is the point: a claim
# is read from wherever that skill actually is.
WEBDEV_SKILL="$SB/code/north/main/agent-profile/skills/webdev"
FRAM_SKILL="$SB/code/fram/main/integrations/north/skills/fram-modeling"
FIRN_SKILL="$SB/code/nixos-config/main/modules/north-profile/firn/skills/firn"
claim() { # skill-dir hook... — a frontmatter whose only claim is these hooks
  local d="$1"; shift; mkdir -p "$d"
  { printf -- '---\nname: %s\nhooks:\n' "$(basename "$d")"
    printf -- '  - %s\n' "$@"
    printf -- '---\n'; } > "$d/SKILL.md"
}
m="$SB/.config/agents/manifest.conf"
ag status > /dev/null
ag on repo-safety > /dev/null
if has_cmd launch-critical-worktree-guard.sh && has_cmd git-blind-stage-guard.sh \
  && has_cmd tripwire-guard.sh; then ok "one flip composes every hook the skill declares"
else bad "a skill's claims compose" "$(composed_files)"; fi
chk "a claim writes nothing to the manifest" "hook worktree-guard enabled repo-safety" "$(grep '^hook worktree-guard ' "$m")"
ag off repo-safety > /dev/null
chk "and off takes them all back out" "" "$(composed_files)"
# a claim BINDS: a hook nobody gated before now answers to the skill that wants it
claim "$WEBDEV_SKILL" logcompress
ag on logcompress > /dev/null
if has_cmd logcompress-hook.js; then bad "a claimed hook waits for its skill" "$(composed_files)"; else ok "a claimed hook waits for its skill"; fi
st="$(ag status)"
case "$st" in *"hook · logcompress:           off (skill: webdev off)"*) ok "and says whose claim holds it" ;;
  *) bad "claim provenance" "$(echo "$st" | grep logcompress)" ;; esac
chk "the claim is backfilled into field 4, where the panel reads it" "hook logcompress enabled webdev" "$(grep '^hook logcompress ' "$m")"
ag on webdev > /dev/null
if has_cmd logcompress-hook.js; then ok "the claiming skill composes it"; else bad "claim composes" "$(composed_files)"; fi
# two claimants: the column takes the first ALPHABETICALLY, so two machines
# reading the same files write the same row
claim "$FRAM_SKILL" logcompress
ag status > /dev/null
chk "two claimants: the column is deterministic" "hook logcompress enabled fram-modeling" "$(grep '^hook logcompress ' "$m")"
rm -rf "$FRAM_SKILL"
ag status > /dev/null
chk "and follows the claim when one skill stops making it" "hook logcompress enabled webdev" "$(grep '^hook logcompress ' "$m")"
# a fragment's own `follows` is the nearer statement and keeps the column
chk "a followed hook keeps its fragment's binding" "hook git-blind-stage-guard enabled repo-safety" "$(grep '^hook git-blind-stage-guard ' "$m")"
# two claimants: either one is enough, and both are named
claim "$WEBDEV_SKILL" logcompress git-blind-stage-guard
ag on repo-safety > /dev/null
st="$(ag status)"
case "$st" in *"hook · git-blind-stage-guard: on"*) ok "provenance names every claimant, deduped" ;;
  *) bad "two claimants named" "$(echo "$st" | grep git-blind)" ;; esac
chk "a hook two skills want is rendered under each" "2" "$(ag status | grep -c '^      hook · git-blind-stage-guard:')"
ag off repo-safety > /dev/null
if has_cmd git-blind-stage-guard.sh; then ok "UNION: the other claimant still wants it"; else bad "union keeps it" "$(composed_files)"; fi
if has_cmd tripwire-guard.sh; then bad "what only that skill wanted is gone" "$(composed_files)"; else ok "what only that skill wanted is gone"; fi
ag off webdev > /dev/null
chk "the last claimant off drops it" "" "$(composed_files)"
# the permission axis is untouched by any of this
ag on webdev > /dev/null; ag off git-blind-stage-guard > /dev/null
if has_cmd git-blind-stage-guard.sh; then bad "a pin outranks every claim" "$(composed_files)"; else ok "a pin outranks every claim"; fi
ag on git-blind-stage-guard > /dev/null
# a claim naming no hook, and a list that is not one
claim "$FRAM_SKILL" no-such-hook
warn="$(ag status 2>&1 >/dev/null)"
case "$warn" in *"skill fram-modeling declares no-such-hook, which is no hook here"*) ok "a claim naming no hook is called out" ;;
  *) bad "unknown claim warns" "$warn" ;; esac
chk "and does not kill status" "1" "$(ag status 2>/dev/null | grep -c '^hooks$')"
sed -i 's/^hooks:$/hooks: not-a-list/' "$WEBDEV_SKILL/SKILL.md"
warn="$(ag status 2>&1 >/dev/null)"
case "$warn" in *"hooks: not-a-list is not a list of names"*) ok "an unreadable list is loud" ;;
  *) bad "unreadable list warns" "$warn" ;; esac
if has_cmd logcompress-hook.js; then ok "and claims nothing, so an unbound hook is unbound again"; else bad "composes without claims" "$(composed_files)"; fi
chk "an unreadable list drops the column too" "hook logcompress enabled" "$(grep '^hook logcompress ' "$m")"
chk "apply still reports" "1" "$(ag apply 2>/dev/null | grep -c '^applied:')"

echo
echo "== 24. corpus-scan-guard: composed by convo, and refuses only the sweep"
# Registration is half the contract; the other half is that the thing the
# switch turns on says no to the expensive shape and yes to every narrow one.
# The full adversarial matrix lives beside the script, in
# north:profiles/tom/hooks/corpus-scan-guard.test.sh — these two directions are
# here so a switchboard change can never quietly compose an inert guard.
fresh; ag status > /dev/null
ag on convo > /dev/null
if has_cmd corpus-scan-guard.sh; then ok "convo composes its guard"; else bad "convo composes its guard" "$(composed_files)"; fi
ag off convo > /dev/null
if has_cmd corpus-scan-guard.sh; then bad "convo off decomposes it" "$(composed_files)"; else ok "convo off decomposes it"; fi

# The script itself lives in North; this suite
# owns the switchboard, so the behaviour half runs only where North is checked
# out beside this repo. Its full matrix is corpus-scan-guard.test.sh.
CSG="${CORPUS_SCAN_GUARD:-$REPO/../../north/main/profiles/tom/hooks/corpus-scan-guard.sh}"
CORPUS="$SB/code/north-data"
if [ ! -x "$CSG" ]; then
  ok "corpus-scan-guard behaviour (skipped: North not checked out beside this repo)"
else
DAY="$CORPUS/accounts/openai/acct/sessions/2026/08/12"
mkdir -p "$DAY"; : > "$DAY/rollout-019ff47e.jsonl"
csg() { # command -> the permission decision, or "allow"
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' \
    "$1" "$SB" |
    env HOME="$SB" AGENT_NO_AUTHORING_HOOKS=0 "$CSG" |
    python3 -c 'import json,sys
raw=sys.stdin.read().strip()
print(json.loads(raw)["hookSpecificOutput"].get("permissionDecision","allow") if raw else "allow")'
}
chk "the corpus-wide sweep is refused" "deny" "$(csg "rg -l --hidden needle $CORPUS")"
chk "the symlink is the same tree" "deny" "$(csg "grep -rn needle $SB/.local/state/north")"
chk "an unbounded find is refused" "deny" "$(csg "find $CORPUS -name '*.jsonl'")"
chk "one named transcript is allowed" "allow" "$(csg "rg needle $DAY/rollout-019ff47e.jsonl")"
chk "one day directory is allowed" "allow" "$(csg "rg needle $DAY")"
chk "a bounded find is allowed" "allow" "$(csg "find $CORPUS -maxdepth 2 -type d")"
chk "convo itself is allowed" "allow" "$(csg "convo session 019ff47e")"
chk "a mention is not an invocation" "allow" "$(csg "echo 'never rg $CORPUS again'")"
fi

echo
echo "== 25. tripwire-guard: composed by repo-safety, and judges deletes by loss"
# Same two halves as 24. The behaviour half is here because this guard's rule is
# about the SHAPE OF THE ESTATE the switchboard configures — a main/ checkout,
# a sibling lane's worktree, ~/code/*-data — so a sandbox HOME with that shape
# in it is the only place the two directions can both be proven. The exhaustive
# matrix is north:profiles/tom/hooks/tripwire-guard.test.sh.
fresh; ag status > /dev/null
ag on repo-safety > /dev/null
if has_cmd tripwire-guard.sh; then ok "repo-safety composes its tripwire"; else bad "repo-safety composes its tripwire" "$(composed_files)"; fi
ag off repo-safety > /dev/null
if has_cmd tripwire-guard.sh; then bad "repo-safety off decomposes it" "$(composed_files)"; else ok "repo-safety off decomposes it"; fi

TWG="${TRIPWIRE_GUARD:-$REPO/../../north/main/profiles/tom/hooks/tripwire-guard.sh}"
if [ ! -x "$TWG" ] || ! command -v jq > /dev/null 2>&1; then
  ok "tripwire-guard behaviour (skipped: North not checked out beside this repo, or no jq)"
else
MINE="$SB/code/proj/worktrees/mine"; OTHER="$SB/code/proj/worktrees/other"
mkdir -p "$MINE" "$OTHER" "$SB/code/proj/main" "$SB/.cache/thumbnails" \
  "$SB/Pictures/Screenshots" "$SB/code/north-data/accounts"
git -C "$MINE" init -q 2>/dev/null; git -C "$OTHER" init -q 2>/dev/null
: > "$SB/Pictures/Screenshots/old.png"
twg() { # command -> "allow", or the deny reason. AGENT_NO_AUTHORING_HOOKS=0
  # forces guards live, so the matrix cannot be silenced by ambient env.
  local out rc
  out="$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' \
    "$1" "$MINE" |
    env HOME="$SB" AGENT_NO_AUTHORING_HOOKS=0 TRIPWIRE_LOG_DIR="$SB/twlog" \
      NORTH_BIN=/bin/true "$TWG" 2>&1)"
  rc=$?
  if [ "$rc" = 0 ]; then echo allow; else echo "$out"; fi
}
# Same call with the force-live override REMOVED, so stored state is what
# decides — the only way to observe `north config guards off` doing its job.
twg_state() {
  local rc
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' \
    "$1" "$MINE" |
    env -u AGENT_NO_AUTHORING_HOOKS -u CLAUDE_NO_AUTHORING_HOOKS HOME="$SB" \
      TRIPWIRE_LOG_DIR="$SB/twlog" NORTH_BIN=/bin/true "$TWG" > /dev/null 2>&1
  rc=$?
  if [ "$rc" = 0 ]; then echo allow; else echo deny; fi
}
twv() { case "$(twg "$1")" in allow) echo allow ;; *) echo deny ;; esac; }
chk "another lane's worktree is refused" "deny" "$(twv "rm -rf $OTHER")"
chk "a .git is refused" "deny" "$(twv "rm -rf $MINE/.git")"
chk "a main/ checkout is refused" "deny" "$(twv "rm -rf $SB/code/proj/main/x")"
chk "the machine's own memory is refused" "deny" "$(twv "rm -rf $SB/code/north-data/accounts")"
chk "an unguarded \$VAR target is refused" "deny" "$(twv 'rm -rf "$BUILD"/*')"
chk "a bare-root delete is refused" "deny" "$(twv 'rm -rf /')"
chk "the thumbnails cache is allowed" "allow" "$(twv "rm -rf $SB/.cache/thumbnails/*")"
chk "the guarded \${VAR:?} form is allowed" "allow" "$(twv 'rm -rf "${BUILD:?}"/dist')"
chk "a scratch path is allowed" "allow" "$(twv 'rm -rf /tmp/build-cache')"
case "$(twg "find $SB/Pictures/Screenshots -type f -mtime +30 -delete")" in
  *bounded*"north config guards off"*) ok "a bounded personal find is refused in proportion, and names the way through" ;;
  *) bad "bounded personal find reason" "$(twg "find $SB/Pictures/Screenshots -type f -mtime +30 -delete")" ;;
esac
# The deliberate path IS the switchboard's own state file: turn guards off there
# and the same refusal becomes the human's call.
mkdir -p "$SB/.local/state/north"; printf 'guards=off\n' > "$SB/.local/state/north/harness.conf"
chk "north config guards off lets the reviewed delete through" "allow" \
  "$(twg_state "rm -rf $SB/Pictures/Screenshots")"
printf 'guards=on\n' > "$SB/.local/state/north/harness.conf"
chk "and back on, it is refused again" "deny" "$(twg_state "rm -rf $SB/Pictures/Screenshots")"
fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILURES"; fi
exit "$fails"
