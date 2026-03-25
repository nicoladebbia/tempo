# /build-step — Show or Execute a Specific Build Step

**Usage:** `/build-step [step_number]` (e.g., `/build-step 3.2`)

Read `docs/BUILD_PLAN.md` and find the step matching the given number.

## Display Mode (default)
Show the full step details:
- Step number and name
- Time estimate
- Prerequisites: list each prerequisite step and whether it's complete (check BUILD_PROGRESS.md)
- Docs to reference: list each doc file and section
- What to build: full description
- Acceptance criteria
- Files to create/modify

## Execute Mode
After showing the details, ask: "Execute this step? (yes/no)"

If yes:
1. Verify ALL prerequisites are met (marked [x] in BUILD_PROGRESS.md)
2. If prerequisites NOT met, show which ones are missing and STOP
3. If prerequisites met, follow the same workflow as /build for this single step
4. Mark complete in BUILD_PROGRESS.md
5. Commit

If the user provides no step number, show the NEXT uncompleted step.
