#!/usr/bin/env bash
set -euo pipefail
# Owner-reserved refusal happens before any window or secret delivery work beyond decrypt.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
grep -q 'owner_reserved_unencrypted: true' "$REPO/secrets/bnet.yaml" || { echo 'FAIL: marker missing' >&2; exit 1; }
grep -q -- '--owner-authorized' "$REPO/dotfiles/bin/wc3-login-field" || { echo 'FAIL: flag missing' >&2; exit 1; }
grep -q '"$typer" type "$private_run"' "$REPO/dotfiles/bin/wc3-login-field" || { echo 'FAIL: not typing through the private desktop' >&2; exit 1; }
! grep -q 'xdotool type' "$REPO/dotfiles/bin/wc3-login-field" || { echo 'FAIL: xdotool typing remains' >&2; exit 1; }
bash -n "$REPO/dotfiles/bin/wc3-login-field"
echo 'PASS: wc3-login-field owner-reserved gate present; types through the private desktop'
