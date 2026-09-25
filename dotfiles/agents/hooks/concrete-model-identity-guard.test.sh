#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_GUARD="$HERE/concrete-model-identity-guard.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/concrete-model-identity-guard.XXXXXX")"
trap 'rm -rf "${SCRATCH:?}"' EXIT
NORTH_V2_REPO="${AGENT_CONFIG_NORTH_V2_REPO:-$HOME/code/north-v2/main}"
MODEL_CATALOG="$NORTH_V2_REPO/agent-machinery/selection/catalog.json"
PROVIDER_HOOKS="$SCRATCH/provider-hooks"
TODO="$SCRATCH/home/code/todo"
ACTIVATION="$SCRATCH/activation.json"
mkdir -p "$TODO" "$SCRATCH/work" "$PROVIDER_HOOKS/lib"

for source in authoring-killswitch.sh north-agent-activation.sh; do
  candidate="$HERE/../lib/$source"
  if [ ! -r "$candidate" ]; then
    printf 'missing Firn-owned hook helper: %s\n' "$candidate" >&2
    exit 1
  fi
  ln -s "$candidate" "$PROVIDER_HOOKS/lib/$source"
done
ln -s "$SOURCE_GUARD" "$PROVIDER_HOOKS/concrete-model-identity-guard.sh"
GUARD="$PROVIDER_HOOKS/concrete-model-identity-guard.sh"

set_active() {
  local permission=off
  [ "$1" = true ] && permission=on
  printf '{"schema":"north.agent-activation/v1","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[{"id":"concrete-model-identity-guard","kind":"hook","category":"authoring","permission":"%s","active":%s}]}\n' "$permission" "$1" >"$ACTIVATION"
}
set_active true

payload() {
  python3 - "$@" <<'PY'
import json
import sys

tool, path, text = sys.argv[1:]
tool_input = {"file_path": path}
if tool == "Write":
    tool_input["content"] = text
elif tool == "Edit":
    tool_input["new_string"] = text
elif tool == "MultiEdit":
    tool_input = {"filePath": path, "edits": [{"newString": text}]}
print(json.dumps({"tool_name": tool, "tool_input": tool_input}))
PY
}

patch_payload() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

cwd, patch = sys.argv[1:]
print(json.dumps({"tool_name": "apply_patch", "cwd": cwd, "tool_input": {"input": patch}}))
PY
}

bash_payload() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

cwd, command = sys.argv[1:]
print(json.dumps({"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": command}}))
PY
}

pass=0 fail=0
run_case() {
  local expect="$1" description="$2" input="$3" output decision ok=0
  shift 3
  output="$(printf '%s' "$input" | env -u AGENT_NO_AUTHORING_HOOKS \
    HOME="$SCRATCH/home" TODO_ROOT="$TODO" NORTH_AGENT_ACTIVATION="$ACTIVATION" \
    NORTH_AGENT_PYTHON=/etc/codex/hooks/runtime/python3 \
    "$@" "$GUARD" 2>&1)"
  decision="$(python3 -c 'import json,sys
try:
    value=json.loads(sys.argv[1] or "null")
except Exception:
    print("malformed")
else:
    print((value or {}).get("hookSpecificOutput", {}).get("permissionDecision", "silent"))' "$output")"
  case "$expect" in
    deny) [ "$decision" = deny ] && ok=1 ;;
    allow) [ "$decision" = silent ] && ok=1 ;;
  esac
  if [ "$ok" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s: expected=%s decision=%s output=%s\n' "$description" "$expect" "$decision" "$output" >&2
  fi
}

run_case deny 'Write attempt model placeholder' \
  "$(payload Write "$TODO/task.md" 'model = "inherited"')"
run_case deny 'Edit reviewer model placeholder' \
  "$(payload Edit "$TODO/task.md" 'reviewer_model = "inherited-parent-model"')"
run_case deny 'MultiEdit model placeholder' \
  "$(payload MultiEdit "$TODO/task.md" 'model = "inherited from supervisor"')"
run_case deny 'self model placeholder' \
  "$(payload Write "$TODO/task.md" 'model = "self"')"
run_case deny 'parent model placeholder' \
  "$(payload Write "$TODO/task.md" 'model = "parent"')"
run_case deny 'default model placeholder' \
  "$(payload Write "$TODO/task.md" 'model = "default"')"
run_case deny 'automatic-selection model placeholder' \
  "$(payload Write "$TODO/task.md" 'model = "auto"')"
run_case deny 'ambient model marker' \
  "$(payload Write "$TODO/task.md" 'model = "ambient"')"
run_case deny 'lineage model marker' \
  "$(payload Write "$TODO/task.md" 'model = "lineage"')"
run_case deny 'plausible unknown model identity' \
  "$(payload Write "$TODO/task.md" 'model = "future-provider-model-9"')"
while IFS= read -r alias; do
  run_case deny "provider alias $alias" \
    "$(payload Write "$TODO/task.md" "model = \"$alias\"")"
done < <(printf '%s\n' inherited parent default auto ambient lineage)
while IFS= read -r exact_model; do
  run_case allow "exact provider model $exact_model" \
    "$(payload Write "$TODO/task.md" "model = \"$exact_model\"")"
done < <(jq -r '.providers[].models[].id' "$MODEL_CATALOG")
run_case allow 'historical exact model identity' \
  "$(payload Write "$TODO/task.md" 'model = "gpt-5"')"
run_case deny 'assignment-ledger model column' \
  "$(payload Write "$TODO/model-assignment-ledger.md" '2026-01-01 | task | inherited collaboration agent | high | pending | note')"
run_case deny 'calibration model label' \
  "$(payload Edit "$TODO/estimate-calibration.md" 'model: inherited-parent-model; reasoning: high')"
run_case deny 'calibration inline model field' \
  "$(payload Edit "$TODO/estimate-calibration.md" '| 2026-01-01 | fixture | model=inherited-parent-model reasoning=high | checkpoint |')"
run_case deny 'calibration narrative model placeholder' \
  "$(payload Edit "$TODO/estimate-calibration.md" 'fixture — inherited high worker')"
run_case deny 'calibration table model placeholder' \
  "$(payload Edit "$TODO/estimate-calibration.md" '| Attempt | Actor / model | Outcome |
| --- | --- | --- |
| fixture | inherited-root closure owner | done |')"
run_case allow 'calibration completed-table current-source prose' \
  "$(payload Edit "$TODO/estimate-calibration.md" '| 2026-01-01 | fixture | 1m | 1m | 1.00x | current-source generation is valid prose |')"
run_case allow 'calibration completed-table current prose' \
  "$(payload Edit "$TODO/estimate-calibration.md" '| 2026-01-01 | fixture | 1m | 1m | 1.00x | current Clause behavior is valid prose |')"
run_case deny 'calibration named model column placeholder' \
  "$(payload Write "$TODO/estimate-calibration.md" '| Attempt | Model | Outcome |
| --- | --- | --- |
| fixture | parent | pending |')"

bad_patch='*** Begin Patch
*** Update File: code/todo/task.md
@@
+model = "inherited"
*** End Patch'
repair_patch='*** Begin Patch
*** Update File: code/todo/task.md
@@
-model = "inherited"
+model = "gpt-5.6-sol"
*** End Patch'
bad_table_patch='*** Begin Patch
*** Update File: code/todo/estimate-calibration.md
@@
+| Attempt | Model | Outcome |
+| --- | --- | --- |
+| fixture | parent | pending |
*** End Patch'
run_case deny 'patch adds placeholder' "$(patch_payload "$SCRATCH/home" "$bad_patch")"
run_case deny 'patch adds header-defined calibration placeholder' \
  "$(patch_payload "$SCRATCH/home" "$bad_table_patch")"
run_case allow 'patch removes placeholder' "$(patch_payload "$SCRATCH/home" "$repair_patch")"
run_case deny 'Bash redirect writes placeholder' \
  "$(bash_payload "$SCRATCH/home" "printf 'model = \"inherited\"' > '$TODO/task.md'")"
run_case deny 'Bash clobber redirect writes placeholder' \
  "$(bash_payload "$SCRATCH/home" "printf 'model = \"self\"' >| '$TODO/task.md'")"
run_case deny 'Bash combined redirect writes placeholder' \
  "$(bash_payload "$SCRATCH/home" "printf 'model = \"default\"' &> '$TODO/task.md'")"
run_case deny 'Bash redirect writes assignment-ledger placeholder' \
  "$(bash_payload "$SCRATCH/home" "printf '%s\\n' '2026-01-01 | task | inherited collaboration agent | high | pending | note' > '$TODO/model-assignment-ledger.md'")"
run_case deny 'Bash tee writes assignment-ledger placeholder' \
  "$(bash_payload "$SCRATCH/home" "printf '%s\\n' '2026-01-01 | task | inherited collaboration agent | high | pending | note' | tee '$TODO/model-assignment-ledger.md' >/dev/null")"
run_case deny 'Bash in-place edit writes placeholder' \
  "$(bash_payload "$SCRATCH/home" "sed -i 's/model = self/model = inherited-parent-model/' '$TODO/task.md'")"
run_case deny 'Bash sed backup-suffix edit writes placeholder' \
  "$(bash_payload "$SCRATCH/home" "sed -i.bak 's/model = self/model = inherited-parent-model/' '$TODO/task.md'")"
run_case deny 'Bash sed attached-suffix edit writes placeholder' \
  "$(bash_payload "$SCRATCH/home" "sed -ibak 's/model = self/model = inherited-parent-model/' '$TODO/task.md'")"
run_case deny 'Bash sed long backup-suffix edit writes placeholder' \
  "$(bash_payload "$SCRATCH/home" "sed --in-place=.bak 's/model = self/model = inherited-parent-model/' '$TODO/task.md'")"
run_case allow 'Bash in-place edit repairs a placeholder' \
  "$(bash_payload "$SCRATCH/home" "sed -i 's/model = self/model = gpt-5.6-sol/' '$TODO/task.md'")"
run_case deny 'quoted sed command writes placeholder' \
  "$(bash_payload "$SCRATCH/home" "'sed' -i 's/model = gpt-5.6-sol/model = self/' '$TODO/task.md'")"
run_case deny 'static nested Bash writes placeholder' \
  "$(bash_payload "$SCRATCH/home" "bash -c 'printf \"model = self\" > \"$TODO/task.md\"'")"
run_case deny 'static nested sh option cluster writes placeholder' \
  "$(bash_payload "$SCRATCH/home" "sh -lc 'printf \"model = parent\" > \"$TODO/task.md\"'")"
run_case deny 'Bash patch writes placeholder' \
  "$(bash_payload "$SCRATCH/home" "apply_patch <<'PATCH'
$bad_patch
PATCH")"
run_case allow 'Bash read-only search remains legal' \
  "$(bash_payload "$SCRATCH/home" "rg 'model = \"inherited\"' '$TODO'")"
run_case allow 'Bash non-in-place sed remains legal' \
  "$(bash_payload "$SCRATCH/home" "sed 's/model = self/model = inherited-parent-model/' '$TODO/task.md'")"
run_case allow 'Bash redirect outside todo remains legal' \
  "$(bash_payload "$SCRATCH/home" "printf 'model = \"inherited\"' > '$SCRATCH/work/report.md'")"
run_case allow 'Bash quoted mention without a write remains legal' \
  "$(bash_payload "$SCRATCH/home" "echo 'model = \"inherited\"'")"
run_case allow 'unrelated placeholder command does not taint concrete redirect' \
  "$(bash_payload "$SCRATCH/home" "echo 'model = \"self\"'; printf 'model = \"gpt-5.6-sol\"' > '$TODO/task.md'")"
run_case allow 'concrete redirect does not inherit later unrelated placeholder' \
  "$(bash_payload "$SCRATCH/home" "printf 'model = \"gpt-5.6-sol\"' > '$TODO/task.md' && echo 'model = \"parent\"'")"
run_case allow 'shell comment does not taint concrete redirect' \
  "$(bash_payload "$SCRATCH/home" "printf 'model = \"gpt-5.6-sol\"' > '$TODO/task.md' # model = self")"
run_case allow 'unrelated redirect name does not taint concrete model value' \
  "$(bash_payload "$SCRATCH/home" "printf 'model = \"gpt-5.6-sol\"' > '$TODO/task.md' 2> '$SCRATCH/work/default.log'")"

run_case allow 'quoted redirection token is ordinary data' \
  "$(bash_payload "$SCRATCH/home" "printf '%s\\n' '>' '$TODO/task.md' 'model = \"self\"'")"
run_case allow 'sed argument mention is not a command' \
  "$(bash_payload "$SCRATCH/home" "echo sed -i 's/model = gpt-5.6-sol/model = self/' '$TODO/task.md'")"
run_case allow 'tee argument mention is not a command' \
  "$(bash_payload "$SCRATCH/home" "echo tee '$TODO/task.md' 'model = self'")"
run_case allow 'nested shell mention is ordinary prose' \
  "$(bash_payload "$SCRATCH/home" "echo \"bash -c 'printf model=self > $TODO/task.md'\"")"

run_case allow 'concrete model' \
  "$(payload Write "$TODO/task.md" 'model = "gpt-5.6-sol"')"
run_case allow 'reasoning may describe selection behavior' \
  "$(payload Write "$TODO/task.md" 'reasoning = "inherited"')"
run_case allow 'ordinary prose use' \
  "$(payload Write "$TODO/task.md" 'The capability is inherited from the context.')"
run_case allow 'ordinary data-model prose use' \
  "$(payload Write "$TODO/task.md" 'The data model: inherited from the parent schema.')"
run_case allow 'assignment ledger comment header' \
  "$(payload Edit "$TODO/model-assignment-ledger.md" '# ts | task | model | effort | outcome | note')"
run_case allow 'calibration inherited-route prose with concrete model' \
  "$(payload Write "$TODO/estimate-calibration.md" 'fixture — two inherited-route gpt-5.6-sol writers.')"
run_case allow 'same field outside todo' \
  "$(payload Write "$SCRATCH/work/task.md" 'model = "inherited"')"
run_case allow 'malformed JSON fails open' 'not-json'

set_active false
run_case allow 'inactive unit' \
  "$(payload Write "$TODO/task.md" 'model = "inherited"')"
set_active true
printf 'not-json\n' >"$ACTIVATION"
run_case allow 'malformed activation' \
  "$(payload Write "$TODO/task.md" 'model = "inherited"')"
printf '{"schema":"north.agent-activation/v1","catalogDigest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generationId":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","units":[%s,%s]}\n' \
  '{"id":"concrete-model-identity-guard","kind":"hook","category":"authoring","permission":"on","active":true}' \
  '{"id":"concrete-model-identity-guard","kind":"hook","category":"authoring","permission":"on","active":true}' \
  >"$ACTIVATION"
run_case allow 'duplicate activation unit' \
  "$(payload Write "$TODO/task.md" 'model = "inherited"')"
rm -f "$ACTIVATION"
run_case allow 'missing activation' \
  "$(payload Write "$TODO/task.md" 'model = "inherited"')"
set_active true
run_case allow 'session switch disables' \
  "$(payload Write "$TODO/task.md" 'model = "inherited"')" \
  AGENT_NO_AUTHORING_HOOKS=1

oversized="$(python3 - "$TODO/oversized.md" <<'PY'
import json
import sys
print(json.dumps({
    "tool_name": "Write",
    "tool_input": {
        "file_path": sys.argv[1],
        "content": 'model = "inherited"\n' + "x" * 1048577,
    },
}))
PY
)"
run_case allow 'oversized input fails open' "$oversized"

printf 'concrete-model-identity-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
