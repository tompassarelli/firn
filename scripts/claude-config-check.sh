#!/usr/bin/env bash
# Compatibility entry point for older CI jobs and callers.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agent-config-check.sh" "$@"
