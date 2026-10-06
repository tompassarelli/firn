#!/usr/bin/env bash
set -euo pipefail
# Owner-reserved refusal happens before any window or secret delivery work beyond decrypt.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
grep -q 'owner_reserved_unencrypted: true' "$REPO/secrets/bnet.yaml" || { echo 'FAIL: marker missing' >&2; exit 1; }
grep -q -- '--owner-authorized' "$REPO/dotfiles/bin/wc3-login-field" || { echo 'FAIL: flag missing' >&2; exit 1; }
bash -n "$REPO/dotfiles/bin/wc3-login-field"
echo 'PASS: wc3-login-field owner-reserved marker and gate present'
