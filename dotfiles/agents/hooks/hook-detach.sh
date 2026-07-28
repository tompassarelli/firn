#!/usr/bin/env bash
# Fire-and-forget wrapper for post-hoc telemetry hooks.
#
# PostToolUse hooks run AFTER the tool has already executed. Nothing downstream
# consumes their result, so blocking the agent on them buys exactly nothing —
# but the agent pays the full latency on every single tool call.
#
# Measured 2026-07-29 (3 runs, this machine): north-on-tooluse cost 2132 ms
# synchronously, against 9-11 ms for each guard and 99 ms for logcompress. It
# was ~94% of all hook time in a session; a 200-call session spent ~7 minutes
# waiting on telemetry it never read.
#
# This wrapper drains stdin (the hook payload), hands it to the real hook in a
# detached session, and returns immediately. Guards must NEVER be wrapped in
# this — a guard's verdict is the whole point of running it synchronously.
#
# Usage in a hooks config:
#   hook-detach.sh <real-hook> [args...]
set -u

target=${1:-}
if [ -z "$target" ]; then
  echo "hook-detach: no target given" >&2
  exit 0   # fail open: telemetry plumbing must never block the agent
fi
shift

# Drain stdin before backgrounding: the parent closes the pipe as soon as we
# exit, so the child cannot read it later.
payload="$(mktemp -t hook-detach.XXXXXX)" || exit 0
cat >"$payload" 2>/dev/null || true

if ! command -v "$target" >/dev/null 2>&1 && [ ! -x "$target" ]; then
  rm -f "$payload"
  exit 0   # fail open: a missing telemetry sink is not the agent's problem
fi

# setsid detaches from the session so the harness cannot reap or wait on it.
setsid bash -c '
  t="$1"; p="$2"; shift 2
  "$t" "$@" <"$p" >/dev/null 2>&1
  rm -f "$p"
' _ "$target" "$payload" "$@" >/dev/null 2>&1 &
disown 2>/dev/null || true

exit 0
