#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
guard=$here/north-runtime-owner-guard

"$guard" status
"$guard" agents --json
"$guard" up --check-runtime

for invocation in 'up' 'up --restart' 'up --unexpected'; do
  read -r -a args <<<"$invocation"
  if output=$("$guard" "${args[@]}" 2>&1); then
    printf 'systemd ownership guard accepted direct lifecycle command: north %s\n' "$invocation" >&2
    exit 1
  fi
  grep -Fq 'owned by north-coord.service' <<<"$output"
  grep -Fq 'sudo systemctl restart north-coord.service' <<<"$output"
done

printf 'ok: Firn ordinary North wrapper rejects direct coordinator lifecycle before checkout execution\n'

# Execute a built live wrapper through the real runtime selector. The probe uses
# North's production trusted resolver, so this proves the wrapper overwrites any
# ambient forgery with the exact immutable managed Codex executable before the
# checkout receives control.
if [ -n "${NORTH_LIVE_WRAPPER_BIN:-}" ]; then
  live_checkout_target="${NORTH_LIVE_CHECKOUT_TARGET:-north}"
  case "$live_checkout_target" in
    north|north-mcp) ;;
    *)
      printf 'unsupported North live checkout target: %s\n' "$live_checkout_target" >&2
      exit 1
      ;;
  esac
  [ -x "$NORTH_LIVE_WRAPPER_BIN" ] || {
    printf 'built North live wrapper is not executable: %s\n' "$NORTH_LIVE_WRAPPER_BIN" >&2
    exit 1
  }
  [ -x "${NORTH_TRUSTED_RUNTIME_BUN:-/run/current-system/sw/bin/bun}" ] || {
    printf 'trusted-runtime probe Bun is unavailable\n' >&2
    exit 1
  }
  [ -f "${NORTH_TRUSTED_RUNTIME_MODULE:-/home/tom/code/north/sdk/src/trusted-runtime.ts}" ] || {
    printf 'trusted-runtime probe module is unavailable\n' >&2
    exit 1
  }
  expected_managed_codex="${NORTH_EXPECTED_MANAGED_CODEX_BIN:-$(readlink -f /etc/codex/runtime/bin/codex)}"
  [[ "$expected_managed_codex" = /nix/store/*/bin/codex ]] &&
    [ -x "$expected_managed_codex" ] || {
      printf 'expected managed Codex is not an immutable executable: %s\n' "$expected_managed_codex" >&2
      exit 1
    }

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/north-live-wrapper.XXXXXX")"
  trap 'rm -rf "${scratch:?}"' EXIT
  mkdir -p "$scratch/checkout/bin"
  ln -s "${NORTH_TRUSTED_RUNTIME_BUN:-/run/current-system/sw/bin/bun}" \
    "$scratch/checkout/bin/$live_checkout_target"
  probe_source='import { trustedManagedCodexExecutable } from "'"${NORTH_TRUSTED_RUNTIME_MODULE:-/home/tom/code/north/sdk/src/trusted-runtime.ts}"'"; console.log(trustedManagedCodexExecutable())'
  observed="$({
    NORTH_CHECKOUT="$scratch/checkout" \
    NORTH_MANAGED_CODEX_BIN=/tmp/ambient-codex-forgery \
      "$NORTH_LIVE_WRAPPER_BIN" -e "$probe_source"
  })"
  [ "$observed" = "$expected_managed_codex" ] || {
    printf 'built North live wrapper resolved managed Codex to %s, expected %s\n' \
      "$observed" "$expected_managed_codex" >&2
    exit 1
  }
  printf 'ok: built %s live wrapper passes exact managed OpenAI executable preflight\n' \
    "$live_checkout_target"
fi
