#!/usr/bin/env bash
# Parse one `north providers` capability line without collapsing independent
# installation, authentication, and headroom facts into a synthetic readiness.
set -euo pipefail

provider="${1:?usage: agent-provider-status.sh <anthropic|openai>}"
awk -v provider="$provider" '
  $1 == provider {
    installed = authenticated = headroom = "unknown"
    for (i = 2; i <= NF; i++) {
      split($i, pair, "=")
      if (pair[1] == "installed") installed = pair[2]
      if (pair[1] == "authenticated") authenticated = pair[2]
      if (pair[1] == "headroom") headroom = pair[2]
    }
    if (installed !~ /^(yes|no|unknown)$/ ||
        authenticated !~ /^(yes|no|unknown)$/ ||
        headroom !~ /^(plenty|normal|low|exhausted|unknown)$/) exit 2
    print installed "|" authenticated "|" headroom
    found = 1
    exit
  }
  END { if (!found) exit 1 }
'
