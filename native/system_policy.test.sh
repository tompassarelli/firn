#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRN_SYSTEM_POLICY_TEST_MODULE="$here/system_policy_test.ts" timeout --foreground 30 "${FIRN_BUN:-bun}" --eval \
  'const m = await import(process.env.FIRN_SYSTEM_POLICY_TEST_MODULE); process.exitCode = m.runScenarios() + m.runProperties(process.env.CI ? 512 : 128);'
