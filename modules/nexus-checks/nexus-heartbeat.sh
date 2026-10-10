status=$(cat "$CHECKS_STATE/status" 2>/dev/null || echo "fail:no-check-run")
body="$(date -u +%Y-%m-%dT%H:%M:%SZ) $status"
if out=$(gh variable set NEXUS_HEARTBEAT --repo "$HEARTBEAT_REPO" --body "$body" 2>&1); then
  echo "heartbeat set: $body"
elif printf '%s' "$out" | grep -qE 'HTTP 401|Bad credentials'; then
  echo "heartbeat skipped: GitHub rejected the nexus-apply token (401); it goes live when the real token lands"
else
  echo "heartbeat failed: $out" >&2
  exit 1
fi
