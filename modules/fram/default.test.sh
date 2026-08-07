#!/usr/bin/env bash
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$MODULE_DIR/default.bnix"
GENERATED="$MODULE_DIR/default.nix"

extract_list() {
  local file="$1" binding="$2"
  awk -v binding="$binding" '
    $0 ~ "^[[:space:]]*" binding "([[:space:]]*=.*)?[[:space:]]*$" {
      active = 1
    }
    active {
      line = $0
      while (match(line, /"[^"]*"/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
      if ($0 ~ /]/) {
        exit
      }
    }
  ' "$file"
}

assert_list() {
  local file="$1" binding="$2" expected="$3" actual
  actual="$(extract_list "$file" "$binding")"
  if [[ "$actual" != "$expected" ]]; then
    printf '%s %s mismatch\nexpected:\n%s\nactual:\n%s\n' \
      "$file" "$binding" "$expected" "$actual" >&2
    exit 1
  fi
}

dev=$'fram\nfram-server\nfram-mcp\nfram-primer\nfram-up\nfram-code-author'
packaged=$'fram\nfram-server\nfram-mcp\nfram-primer'

for file in "$SOURCE" "$GENERATED"; do
  assert_list "$file" devCommandNames "$dev"
  assert_list "$file" packagedCommandNames "$packaged"
done

grep -Fq 'devCommands (builtins.map mkDev devCommandNames)' "$SOURCE"
grep -Fq 'packagedCommands (builtins.map mkPackaged packagedCommandNames)' "$SOURCE"
grep -Fq 'devCommands = builtins.map mkDev devCommandNames;' "$GENERATED"
grep -Fq 'packagedCommands = builtins.map mkPackaged packagedCommandNames;' "$GENERATED"
grep -Fq 'provenance=checkout path=$target' "$SOURCE"
grep -Fq '(builtins.readFile (s inputs.fram "/bin/fram-code-status"))' "$SOURCE"
grep -Fq '++ [framPkg framCodeStatus] devCommands packagedCommands' "$SOURCE"
grep -Fq 'framCodeStatus' "$GENERATED"
grep -Fq 'builtins.readFile "${inputs.fram}/bin/fram-code-status"' "$GENERATED"

printf 'ok: Fram ordinary core and code status are input-locked; six checkout commands are explicit *-dev surfaces\n'
