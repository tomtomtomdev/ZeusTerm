#!/bin/bash
# UserPromptSubmit hook. Inspects the prompt and, when it looks like a feature / bug-fix /
# refactor request, injects a short reminder of the Zeus workflow rules (TDD, tests-before-bugfix,
# Fowler refactoring) as additionalContext. Stays silent otherwise so it isn't noisy.
set -uo pipefail

PY=/usr/bin/python3
[ -x "$PY" ] || PY=python3

PROMPT="$("$PY" -c 'import sys,json
try: print(json.load(sys.stdin).get("prompt",""))
except Exception: print("")' 2>/dev/null)"

LOWER="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')"
emit=""

printf '%s' "$LOWER" | grep -Eq 'feature|implement|build a|new view|new screen|add (a|the|support)|create a' \
  && emit="$emit • Building a feature → TDD is mandatory: write the failing test FIRST (RED), minimal code (GREEN), then refactor. Invoke the tdd-kent-beck skill before writing production code."

printf '%s' "$LOWER" | grep -Eq 'bug|fix|broken|crash|error|fails|failing|regression|not working|doesn.t work' \
  && emit="$emit • Bug fix → run the test suite FIRST to capture the baseline, then write a failing reproduction test (tdd-kent-beck / legacy-code for seams), then fix until green."

printf '%s' "$LOWER" | grep -Eq 'refactor|clean ?up|restructure|rename|extract|decouple|simplify|tidy' \
  && emit="$emit • Refactoring → invoke refactoring-fowler. Tests green before AND after; name the smell + the named refactoring; two-hats rule (no behavior change while refactoring)."

[ -z "$emit" ] && exit 0

"$PY" -c 'import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Zeus workflow rules (from CLAUDE.md):"+sys.argv[1]}}))' "$emit"
exit 0
