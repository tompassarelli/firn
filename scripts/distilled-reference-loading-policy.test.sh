#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy="$repo/dotfiles/agents/AGENTS.md"

grep -Fq 'A distilled skill is the normal complete operating surface:' "$policy"
grep -Fq 'never load a linked `*-reference` skill merely because it is linked.' "$policy"
grep -Fq 'reference only when the user explicitly requests its detail' "$policy"
if grep -Fq 'follow its required references.' "$policy"; then
  printf 'stale unconditional reference-loading rule remains\n' >&2
  exit 1
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cat >"$scratch/compliant" <<'EOF'
Use the distilled skill. Load a reference only for an explicit request or a named unresolved detail.
EOF
cat >"$scratch/violation" <<'EOF'
Use the distilled skill and always follow its required references.
EOF
grep -Fq 'Load a reference only for an explicit request' "$scratch/compliant"
if grep -Fq 'always follow its required references' "$scratch/violation"; then
  : # negative fixture intentionally demonstrates the forbidden behavior
else
  printf 'negative fixture did not encode forbidden behavior\n' >&2
  exit 1
fi
printf 'ok: distilled skills default-complete; references exceptional\n'
