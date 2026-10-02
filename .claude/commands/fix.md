---
description: Apply safe fixes from the latest /review; ask before judgment calls.
---

# /fix — Auto-Fix Issues Found by Review

Automatically fix issues identified by the `/review` command or by individual agents.

## Workflow

1. **Read the latest review results**: check if `/review` was run recently in this conversation
2. **If no recent review**: run `/review` first to identify issues
3. **Categorize fixes by risk**:
   - **Safe auto-fix**: Missing imports, hardcoded colors → tokens, spacing magic numbers → scale values, missing accessibility labels
   - **Needs judgment**: Architectural changes, state machine modifications, data model changes
   - **Manual only**: Business logic changes, algorithm modifications

4. **Apply safe fixes automatically**:
   - For each safe fix, apply the change using Edit tool
   - After each fix, re-read the file to verify the fix is correct
   - Track what was fixed

5. **For judgment fixes**: explain the issue and proposed fix, ask user to approve

6. **After all fixes**: run the relevant review agent again to verify fixes resolved the issues

## Fix Patterns
Use only token names that exist (see `.claude/agents/design-system-police.md` for the list and where they live).

### Hardcoded color → Design token
```swift
// Before
Color(hex: "#22C55E")
// After
Color.tempoRecoveryGreen
```

### Hardcoded text font → Type scale
```swift
// Before
Text(title).font(.system(size: 22, weight: .bold))
// After
Text(title).font(.tempoTitle2)
```
(`Image(systemName:)` icon sizing with `.font(.system(size:))` is fine — leave it.)

### Magic number → Spacing token
```swift
// Before
.padding(16)
// After
.padding(TempoSpacing.lg)
```

### Improvised copy → Copy bible
Strings are inline `Text("…")` literals (no L10n layer). Replace improvised user-facing text with the exact string from `docs/UX_COPY_BIBLE.md`; keep it a literal.

### Missing import
```swift
// Add at top of file
import SwiftData
```

### Force unwrap → handle the missing value (needs judgment)
Never replace `!` with `?? 0` on user-facing numbers: showing 0 for "no data" is wrong data. Unwrap and show the empty/placeholder state instead, and ask if the right fallback is unclear.
```swift
// Before
Text("\(snapshot.dailyScore!)")
// After
if let score = snapshot.dailyScore { Text("\(score)") } else { Text("—") }
```

## Report what was fixed:
```
## Auto-Fix Report
**Fixed:** 8 issues
**Needs review:** 2 issues
**Skipped:** 0

### Applied Fixes
1. ✅ DashboardView.swift:34 — Color(hex: "#22C55E") → Color.tempoRecoveryGreen
2. ✅ DashboardView.swift:67 — .padding(16) → .padding(TempoSpacing.lg)
...

### Needs Your Review
1. ⚠️ RecoveryEngine.swift:89 — Recovery threshold uses > instead of >=. Fix? (y/n)
```
