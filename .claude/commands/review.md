# /review — Full Self-Review Suite

Run ALL validation agents in parallel against the current codebase. This is the "is everything correct?" command.

## Workflow

1. **Identify what to review**: Find all `.swift` files modified since the last git commit (or all Swift files if no commits yet):
   ```
   git diff --name-only HEAD -- '*.swift'
   ```
   If no changes, review all Swift files in the project.

2. **Launch 5 review agents in parallel** using the Agent tool:

   a. **design-system-police** (Haiku — fast)
      - Feed it all View files
      - Check colors, typography, spacing, components

   b. **swift-compiler** (Haiku — fast)
      - Feed it all new/modified Swift files
      - Check imports, types, optionals, syntax

   c. **architecture-guard** (Sonnet — thorough)
      - Feed it the entire project structure
      - Check ADR compliance, dependency control, patterns

   d. **doc-sync-checker** (Haiku — fast)
      - Feed it all model and view files
      - Cross-check against DATA_MODELS_IOS.md, WIREFRAMES.md, STATE_MACHINES.md

   e. **build-reviewer** (Sonnet — thorough)
      - Feed it the current build step context
      - Overall quality and completeness check

3. **Compile results** into a single report:

```
## Tempo Review Report
**Files reviewed:** X
**Agents run:** 5

### Results
| Agent | Status | Issues |
|-------|--------|--------|
| Design System Police | ✅ / ⚠️ / ❌ | N issues |
| Swift Compiler | ✅ / ⚠️ / ❌ | N issues |
| Architecture Guard | ✅ / ⚠️ / ❌ | N issues |
| Doc Sync Checker | ✅ / ⚠️ / ❌ | N issues |
| Build Reviewer | ✅ / ⚠️ / ❌ | N issues |

### Critical Issues (must fix)
1. [issue from any agent]
2. [issue from any agent]

### Warnings (should fix)
1. [warning]

### All Clear ✅ (if no issues)
```

4. **If critical issues found**: list them with suggested fixes. Ask the user: "Fix these now?"
5. **If all clear**: "All 5 review agents passed. Code is clean."
