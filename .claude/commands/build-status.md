# /build-status — Show Build Progress

Read `docs/BUILD_PROGRESS.md` and `docs/BUILD_PLAN.md`, then display a concise status report:

## Report Format

```
## Tempo Build Status

**Progress:** X / Y steps complete (Z%)
**Current Phase:** Phase N: [Phase Name]
**Last Completed:** Step X.Y: [description] — [date]
**Next Up:** Step X.Z: [description]
**Prerequisites Met:** ✅ Yes / ❌ No (list missing)
**Estimated Phase Completion:** ~N more steps

### Phase Summary
Phase 0: ██████████ 10/10 ✅
Phase 1: ██████░░░░  6/10
Phase 2: ░░░░░░░░░░  0/8
...

### Blockers
- [Any blockers from BUILD_PROGRESS.md]

### Notes
- [Any notes from BUILD_PROGRESS.md]
```

Use filled blocks (█) for complete, empty blocks (░) for incomplete. Show all phases.

If there are blockers documented in BUILD_PROGRESS.md, highlight them prominently.
