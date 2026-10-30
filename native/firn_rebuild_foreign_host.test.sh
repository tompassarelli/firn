#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/firn-foreign-host-test.XXXXXX")"
trap 'rm -rf -- "${scratch:?}"' EXIT
mkdir -p "$scratch/repo" "$scratch/bin" "$scratch/tmp"
git -C "$scratch/repo" init -q
git -C "$scratch/repo" config user.name Firn
git -C "$scratch/repo" config user.email firn@example.invalid
git -C "$scratch/repo" commit -qm baseline --allow-empty
for tool in nix sudo nixos-rebuild nix-env; do
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >>"%s/calls"\nexit 1\n' "$tool" "$scratch" >"$scratch/bin/$tool"
  chmod +x "$scratch/bin/$tool"
done
cat >"$scratch/bin/readlink" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == /nix/var/nix/profiles/system ]]; then
  printf 'system-41-link\n'
else
  exec /run/current-system/sw/bin/readlink "$@"
fi
SH
chmod +x "$scratch/bin/readlink"
rebuild() {
  env PATH="$scratch/bin:$PATH" TMPDIR="$scratch/tmp" FIRN_REPO="$scratch/repo" FIRN_HOST=whiterabbit \
    bun "$here/firn_rebuild_host.mjs" host rebuild "$1" >"$scratch/out" 2>&1
}
status=0
rebuild nexus || status=$?
[[ "$status" == 64 ]] || { cat "$scratch/out" >&2; printf 'foreign host rebuild exited %s, not 64\n' "$status" >&2; exit 1; }
rg -Fq 'firn host deploy nexus' "$scratch/out"
[[ ! -e "$scratch/calls" ]] || { printf 'foreign host rebuild ran a build tool\n' >&2; exit 1; }
status=0
rebuild whiterabbit || status=$?
[[ "$status" == 65 ]] || { cat "$scratch/out" >&2; printf 'local host rebuild did not reach review (exit %s)\n' "$status" >&2; exit 1; }
rg -Fq 'last switched revision is unavailable' "$scratch/out"
printf 'ok: firn rebuild refuses a host other than this machine before any build and names firn host deploy\n'
