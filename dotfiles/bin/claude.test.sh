#!/usr/bin/env bash
set -euo pipefail

launcher="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/claude"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/claude-launcher-test.XXXXXX")"
trap 'rm -rf -- "${scratch:?}"' EXIT

unset CLAUDE_CONFIG_DIR CLAUDE_CODE_OAUTH_TOKEN
export HOME="$scratch/home"
export NORTH_STATE_DIR="$HOME/.local/state/north"
export NORTH_USAGE_GATE="$HOME/.local/state/agents/usage-gate.json"
export CLAUDE_RUNTIME="$scratch/bin/fake-claude"

mkdir -p "$HOME/.claude/agents" "$HOME/.claude/skills" "$NORTH_STATE_DIR/profiles" "$NORTH_STATE_DIR/claude-tokens" "$HOME/.local/state/agents" "$scratch/bin"
printf 'shared-md\n' >"$HOME/.claude/CLAUDE.md"
printf '{}\n' >"$HOME/.claude/settings.json"

cat >"$CLAUDE_RUNTIME" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "auth" && "${2:-}" == "login" ]]; then
  email="${4:-user@example.com}"
  printf '{"loggedIn":true}\n' >"$CLAUDE_CONFIG_DIR/.credentials.json"
  printf '{"oauthAccount":{"emailAddress":"%s","accountUuid":"uuid-%s"}}\n' "$email" "$email" >"$CLAUDE_CONFIG_DIR/.claude.json"
  exit 0
fi
printf 'config=%s token=%s args=%s\n' "${CLAUDE_CONFIG_DIR:-}" "${CLAUDE_CODE_OAUTH_TOKEN:-}" "$*"
EOF
chmod +x "$CLAUDE_RUNTIME"

# Seed accounts a (100% weekly) and b (25% weekly, 10% 5h)
mkdir -p "$NORTH_STATE_DIR/profiles/claude-a" "$NORTH_STATE_DIR/profiles/claude-b"
printf 'tok-a\n' >"$NORTH_STATE_DIR/claude-tokens/claude-a"
printf 'tok-b\n' >"$NORTH_STATE_DIR/claude-tokens/claude-b"
cat >"$NORTH_STATE_DIR/claude-accounts.json" <<'EOF'
{
  "a": { "email": "alpha@example.org" },
  "b": { "email": "bravo@work.io" }
}
EOF
cat >"$NORTH_USAGE_GATE" <<'EOF'
{
  "claude": {
    "windows": {
      "claude:a": [
        { "window": "5h", "used_pct": 0.0, "resets_at": "2099-01-01T00:00:00Z", "reset_h": 2.0 },
        { "window": "week", "used_pct": 100.0, "resets_at": "2099-01-01T00:00:00Z", "reset_h": 24.0 }
      ],
      "claude:b": [
        { "window": "5h", "used_pct": 10.0, "resets_at": "2099-01-01T00:00:00Z", "reset_h": 3.0 },
        { "window": "week", "used_pct": 25.0, "resets_at": "2099-01-01T00:00:00Z", "reset_h": 48.0 }
      ]
    }
  }
}
EOF

fail() { printf 'claude.test.sh: %s\n' "$1" >&2; exit 1; }

# 1. Default `claude` selects account with available usage (b)
out="$("$launcher" -p "hello")"
[[ "$out" == "config=$NORTH_STATE_DIR/profiles/claude-b token=tok-b args=-p hello" ]] || fail "expected default to pick b, got: $out"

# 2. Target specific account by email or domain
out="$("$launcher" alpha@example.org -p "hi")"
[[ "$out" == "config=$NORTH_STATE_DIR/profiles/claude-a token=tok-a args=-p hi" ]] || fail "expected email to pick a, got: $out"
out="$("$launcher" work.io -p "hi")"
[[ "$out" == "config=$NORTH_STATE_DIR/profiles/claude-b token=tok-b args=-p hi" ]] || fail "expected domain to pick b, got: $out"

# 3. Bootstrap a brand new account (allocates claude-c, links profile files, saves pasted token)
out="$(printf 'sk-ant-new-c\n' | "$launcher" charlie@new.dev -p 'bootstrapped')"
[[ "$out" == "config=$NORTH_STATE_DIR/profiles/claude-c token=sk-ant-new-c args=-p bootstrapped" ]] || fail "bootstrap token failed: $out"
[[ -L "$NORTH_STATE_DIR/profiles/claude-c/settings.json" ]] || fail "profile links not created"
[[ "$(jq -r '.c.email' "$NORTH_STATE_DIR/claude-accounts.json")" == "charlie@new.dev" ]] || fail "new email not recorded"

# 4. Bootstrap via browser login (Enter -> claude auth login --email)
out="$(printf '\n' | "$launcher" delta@new.dev -p 'browser-login')"
[[ "$out" == "config=$NORTH_STATE_DIR/profiles/claude-d token= args=-p browser-login" ]] || fail "bootstrap browser login failed: $out"
[[ "$(jq -r '.d.uuid' "$NORTH_STATE_DIR/claude-accounts.json")" == "uuid-delta@new.dev" ]] || fail "uuid not synced from .claude.json"

# 5. Unauthenticated account with EOF fails cleanly
if "$launcher" echo@new.dev -p 'eof' </dev/null >/dev/null 2>&1; then
  fail "expected EOF on unauthenticated account to fail"
fi

# 6. Pass-through when CLAUDE_CONFIG_DIR is already set
out="$(CLAUDE_CONFIG_DIR=/custom/dir "$launcher" -p "raw")"
[[ "$out" == "config=/custom/dir token= args=-p raw" ]] || fail "passthrough failed: $out"

# 7. The profile merge names each profile by its own file: a last profile with no oauthAccount inherits nothing
mkdir -p "$NORTH_STATE_DIR/profiles/claude-z"
printf '{"cachedUsageUtilization":{"utilization":{"five_hour":{"utilization":99,"resets_at":"2099-01-01T00:00:00Z"}}}}\n' >"$NORTH_STATE_DIR/profiles/claude-z/.claude.json"
"$launcher" -p "merge" >/dev/null
[[ "$(jq -r '.z.email // "none"' "$NORTH_STATE_DIR/claude-accounts.json")" == "none" ]] || fail "claude-z inherited an email"
[[ "$(jq -r '.d.email' "$NORTH_STATE_DIR/claude-accounts.json")" == "delta@new.dev" ]] || fail "claude-d lost its email"
[[ "$(jq -r '.c.email' "$NORTH_STATE_DIR/claude-accounts.json")" == "charlie@new.dev" ]] || fail "claude-c lost its email"
[[ "$(jq -r '.c.cached // "none"' "$NORTH_STATE_DIR/claude-accounts.json")" == "none" ]] || fail "claude-c inherited claude-z's usage"
[[ "$(jq -r '.z.cached.five_hour.utilization' "$NORTH_STATE_DIR/claude-accounts.json")" == "99" ]] || fail "claude-z usage not recorded under claude-z"

printf 'claude launcher tests passed\n'
