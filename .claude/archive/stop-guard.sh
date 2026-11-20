#!/bin/bash
# Stop Guard — if a /build step is still marked 🔨 in BUILD_PROGRESS.md, block the
# stop ONCE with a reminder (stop_hook_active prevents loops). Otherwise silent.

INPUT=$(cat)
ACTIVE=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stop_hook_active', False))" 2>/dev/null)
[[ "$ACTIVE" == "True" ]] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
PROGRESS_FILE="$ROOT/docs/BUILD_PROGRESS.md"
[[ -f "$PROGRESS_FILE" ]] || exit 0

STEP=$(/usr/bin/grep -m1 '🔨' "$PROGRESS_FILE")
[[ -z "$STEP" ]] && exit 0

python3 -c 'import json,sys; print(json.dumps({"decision":"block","reason":"Build step still marked in progress: "+sys.argv[1].strip()[:120]+". Finish it and change 🔨 to [x] in docs/BUILD_PROGRESS.md, or log it under ## Blockers if you are blocked."}))' "$STEP"
exit 0
