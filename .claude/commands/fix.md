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

### Hardcoded color → Design token
```swift
// Before
Color(hex: "#FF4757")
// After
Color.tempo.recovery.red
```

### Hardcoded string → Copy bible key
```swift
// Before
Text("Recovery Score")
// After
Text(L10n.Recovery.scoreTitle)
```

### Missing import
```swift
// Add at top of file
import SwiftData
```

### Force unwrap → Safe optional
```swift
// Before
let score = snapshot.dailyScore!
// After
let score = snapshot.dailyScore ?? 0
```

### Magic number → Spacing token
```swift
// Before
.padding(16)
// After
.padding(.tempoLG)
```

## Report what was fixed:
```
## Auto-Fix Report
**Fixed:** 8 issues
**Needs review:** 2 issues
**Skipped:** 0

### Applied Fixes
1. ✅ DashboardView.swift:34 — Color(hex: "#22C55E") → Color.tempo.recovery.green
2. ✅ DashboardView.swift:67 — .padding(16) → .padding(.tempoLG)
...

### Needs Your Review
1. ⚠️ RecoveryEngine.swift:89 — Recovery threshold uses > instead of >=. Fix? (y/n)
```
