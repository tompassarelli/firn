#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy="$repo/dotfiles/agents/AGENTS.md"

grep -Fq 'A skill'"'"'s `SKILL.md` is the complete normal operating surface:' "$policy"
grep -Fq 'never read' "$policy"
grep -Fq 'its `references/` merely because they are linked.' "$policy"
grep -Fq 'explicitly requests that detail or when you name a specific unresolved question' "$policy"
if grep -Fq 'follow its required references.' "$policy"; then
  printf 'stale unconditional reference-loading rule remains\n' >&2
  exit 1
fi
skill_roots=("$repo/dotfiles/agents/skills" "$repo/modules/north-profile/firn/skills")
if find "${skill_roots[@]}" -mindepth 1 -maxdepth 1 -type d \
  \( -name '*-distilled' -o -name '*-reference' \) | grep -q .; then
  printf 'suffixed skill identity remains; use one plain-named skill with references/\n' >&2
  exit 1
fi
if rg -n 'agents path [^` ]*-reference|read the returned skill completely|always read `?references/' \
  "${skill_roots[@]}" -g 'SKILL.md' >/dev/null; then
  printf 'skill still mandates unconditional reference loading\n' >&2
  exit 1
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cat >"$scratch/compliant" <<'FIXTURE'
Follow SKILL.md. Read references/ only for an explicit request or a named unresolved detail.
FIXTURE
cat >"$scratch/violation" <<'FIXTURE'
Follow SKILL.md and always read references/ first.
FIXTURE
grep -Fq 'Read references/ only for an explicit request' "$scratch/compliant"
if grep -Fq 'always read references/' "$scratch/violation"; then
  : # negative fixture intentionally demonstrates the forbidden behavior
else
  printf 'negative fixture did not encode forbidden behavior\n' >&2
  exit 1
fi
printf 'ok: SKILL.md default-complete; references/ exceptional\n'
