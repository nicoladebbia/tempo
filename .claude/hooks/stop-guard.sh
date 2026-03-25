#!/bin/bash
# Stop Guard Hook
# Runs when Claude tries to stop/finish responding
# Checks if the current build step is properly completed
# Exit 0 = allow stop, Exit 2 = block stop (Claude must keep working)

PROGRESS_FILE="docs/BUILD_PROGRESS.md"
BUILD_PLAN="docs/BUILD_PLAN.md"

# Only run if we're in a /build session (check if BUILD_PROGRESS exists and has in-progress items)
if [[ ! -f "$PROGRESS_FILE" ]]; then
    exit 0
fi

# Check for any step marked as "in progress" (🔨) but not completed
IN_PROGRESS=$(grep -c '🔨' "$PROGRESS_FILE" 2>/dev/null || echo 0)

if [[ "$IN_PROGRESS" -gt 0 ]]; then
    STEP=$(grep '🔨' "$PROGRESS_FILE" | head -1)
    echo "⚠️ Build step still in progress: $STEP"
    echo "Please complete this step and mark it done before stopping."
    echo "Update BUILD_PROGRESS.md: change 🔨 to [x] when the step passes acceptance criteria."
    # Don't block — just remind. Claude will see this feedback.
    exit 0
fi

# All good — allow stop
exit 0
