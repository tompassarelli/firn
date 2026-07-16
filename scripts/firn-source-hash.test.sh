#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/firn-source-hash"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts/firn-cmds"
printf '#lang racket/base\n' >"$TMP/scripts/firn.rkt"
printf '#lang racket/base\n' >"$TMP/scripts/firn-cmds/a.rkt"

first="$(FIRN_REPO="$TMP" "$SCRIPT")"
second="$(FIRN_REPO="$TMP" "$SCRIPT")"
[ "$first" = "$second" ]
printf '(define changed #t)\n' >>"$TMP/scripts/firn-cmds/a.rkt"
third="$(FIRN_REPO="$TMP" "$SCRIPT")"
[ "$first" != "$third" ]

printf 'ok: firn-source-hash\n'

