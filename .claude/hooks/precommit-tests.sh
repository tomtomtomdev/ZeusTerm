#!/bin/bash
# PreToolUse gate (matcher: Bash, if: git commit). Blocks `git commit` unless the
# Zeus unit-test suite is green. UI tests run separately via /verify (they need signing
# + app launch and are too slow for a commit gate).
#
# Emits a PreToolUse permissionDecision JSON. Exit 0 always — the JSON drives the decision.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"   # .claude/hooks -> project root
PROJ="$ROOT/Zeus/Zeus.xcodeproj"
PKG="$ROOT/Packages/ZeusKit"
LOG="/tmp/zeus-precommit-tests.log"
: > "$LOG"

deny() {
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Commit blocked by Zeus green-bar gate: tests are RED. Fix them before committing. Full failure output: /tmp/zeus-precommit-tests.log"}}'
  exit 0
}

# 1) ZeusKit package unit tests (fast — the core domain/adapter logic).
if [ -f "$PKG/Package.swift" ]; then
  echo "=== swift test (ZeusKit) ===" >>"$LOG"
  if ! ( cd "$PKG" && swift test ) >>"$LOG" 2>&1; then deny; fi
fi

# 2) App unit tests. UI tests run separately via /verify (signing + app launch, too slow here).
if [ -d "$PROJ" ]; then
  echo "=== xcodebuild test (ZeusTests) ===" >>"$LOG"
  if ! xcodebuild test \
        -project "$PROJ" \
        -scheme Zeus \
        -destination 'platform=macOS' \
        -only-testing:ZeusTests \
        -quiet >>"$LOG" 2>&1; then deny; fi
fi

# Green bar -> allow commit (no output = proceed through normal permission flow).
exit 0
