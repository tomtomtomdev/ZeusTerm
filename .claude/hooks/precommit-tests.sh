#!/bin/bash
# PreToolUse gate (matcher: Bash, if: git commit). Blocks `git commit` unless the
# Zeus unit-test suite is green. UI tests run separately via /verify (they need signing
# + app launch and are too slow for a commit gate).
#
# Emits a PreToolUse permissionDecision JSON. Exit 0 always — the JSON drives the decision.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"   # .claude/hooks -> project root
PROJ="$ROOT/Zeus/Zeus.xcodeproj"
LOG="/tmp/zeus-precommit-tests.log"

if [ ! -d "$PROJ" ]; then
  # Can't find the project — fail open so we never wedge commits on a misconfig.
  exit 0
fi

if xcodebuild test \
      -project "$PROJ" \
      -scheme Zeus \
      -destination 'platform=macOS' \
      -only-testing:ZeusTests \
      -quiet >"$LOG" 2>&1; then
  # Green bar -> allow commit (no output = proceed through normal permission flow).
  exit 0
fi

# Red bar -> deny with a static reason (no string interpolation = no JSON-escaping hazard).
printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Commit blocked by Zeus green-bar gate: `xcodebuild test` (scheme Zeus, target ZeusTests) FAILED. Fix the red tests before committing. Full failure output: /tmp/zeus-precommit-tests.log"}}'
exit 0
