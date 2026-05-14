# Session Handoff — 2026-05-14 (continuation, b)

> Follow-up to `SESSION_HANDOFF_2026-05-14.md`. That session shipped Fixes
> #1–#5 (with known follow-ups). This session closed those follow-ups and
> landed Fix #6. The remediation queue is now down to Fix #7 (the daily
> time-blocked plan engine) plus the §10 docs sweep.

## What landed in this session

| Fix | Status | Commit |
|---|---|---|
| §3 Anthropic key removal | already shipped | `05c7815e` |
| §4 Subscription gate + AI consent | already shipped | `fefd8547` |
| §5 AIBudgetTracker | already shipped | `32dfa284` |
| §6 AICache | restored in InsightController weekly_report + patterns | `31813d35` |
| §7 9 AI features | digit-prefix decode bug fixed; **all 9 routes smoke-tested green** | `31813d35` |
| §8 Onboarding fields | **shipped end-to-end** | `291ec002` |
| §10 BUILD_PROGRESS.md | 15.3–15.8 marked done | `5ea46063` + `291ec002` |

## Smoke-test record (live backend, user_smoke_test_001)

```
POST /v1/insights/achievement-copy        → 200 fallback copy
GET  /v1/insights/morning-briefing        → 200 template
POST /v1/insights/recovery-prescription   → 200 (digit-prefix fix verified)
POST /v1/insights/training-adjustment     → 200 fallback
POST /v1/insights/dashboard               → 200 fallback insight card
POST /v1/insights/training-program        → 200 fallback PPL split
POST /v1/insights/study-schedule          → 200 even split
POST /v1/nutrition/ai/meal-timing         → 200 default time
GET  /v1/insights/weekly-report           → 200, second call HIT Postgres cache
GET  /v1/insights/patterns                → 200, second call HIT Redis cache
PUT  /v1/user/daily-plan-profile          → 200, Postgres row + nested JSON arrays
GET  /v1/user/daily-plan-profile          → 200, round-trip preserves classes + works
```

All fallback paths fired because `ANTHROPIC_API_KEY` is unset locally —
this is the correct test posture (cheaper than burning real tokens to
prove plumbing). When the key is set, the same routes hit Claude and
return AI-generated payloads instead of the rule-based fallback.

## Notable decisions made this session

1. **Digit-prefix decode bug.** Chose Approach A (rename properties from
   `hrv7dayAvg` → `hrv7DayAvg`). Verified empirically with a one-shot
   Swift probe that `convertFromSnakeCase` produces the capital-D form
   for `_7day` segments. Renamed across `RecoveryPrescriptionService`,
   `TrainingProgramService`, `DashboardInsightsService`,
   `MorningBriefingService`.

2. **AICache restoration.** Rewrote `InsightController.weeklyReport` and
   `patterns` to use `AICacheKey.weeklyReport` (Postgres, 7d) and
   `.patternDetection` (Redis, 24h) instead of the ad-hoc Redis-only
   wiring. Verified by log lines + a Postgres row in `ai_response_cache`.

3. **Onboarding schema (§8).** Per Nicola's direction, went with the
   "richer term-bounded schema" option: MEQ-style 5-point chronotype,
   term start/end dates on the profile, eating window presets (16:8 /
   14:10 / 12:12 / custom) with default windows, free-text examSchedule
   left in place for backward-compat (no auto-parse from Claude — defer
   to a one-shot migration if needed).

4. **DTO casing.** Backend's global `convertFromSnakeCase` plus
   `convertToSnakeCase` strategies bit us once during Fix #6 smoke
   tests: DTO struct property names *must* be camelCase even though the
   wire format is snake_case. Renamed `DailyPlanProfileRequest` /
   `StoredClassBlock` / `StoredWorkBlock` fields accordingly. This is
   the same footgun as the digit-prefix bug — `keyDecodingStrategy` and
   explicit-key types don't compose intuitively. **Watch for it in
   future backend DTOs.**

5. **Commits split into 5.** Intelligence infra → §7 features → iOS key
   removal → iOS subscription gate → docs → Fix #6. Granular history so
   any one piece can be reverted in isolation.

## Local environment state (unchanged from the prior handoff except)

- New migration `CreateUserDailyPlanProfiles` applied. Table
  `user_daily_plan_profiles` exists with one row for
  `user_smoke_test_001`.
- Backend still runs the same way (`swift run` from `tempo-backend/`,
  `CLAUDE_MONTHLY_BUDGET_CENTS=10000` override for smoke tests).
- Test JWT mint and fixture user untouched.

## What's still in the working tree (not committed this session)

`git status` will show ~55 unrelated nutrition UX changes (Fuel quadrant
detail, meal feedback, mark-eaten sheet, weekly review, mealshift
planner, etc.). These pre-date the intelligence remediation and are not
part of this session's deliverable. Decide whether to keep, commit, or
revert them separately. They are **not** required for §9.

## Recommended next session order

1. **Re-orient.** Read this handoff + the prior one. Verify §1 of
   `INTELLIGENCE_REMEDIATION_PLAN.md` if anything has shifted.

2. **Land §9 — the daily time-blocked plan engine.** All prerequisites
   are met:
   - §7.6 (training-program), §7.7 (meal-timing), §7.8 (study-schedule)
     routes are live and smoke-tested.
   - §8 onboarding fields persist locally (SwiftData) and on the
     backend (`/v1/user/daily-plan-profile`).
   - `UserDailyPlanProfile.classBlocks` + `workBlocks` already model
     the fixed-event side of the free-window solver.
   - `RecoveryEngine.suggestPrescription` (existing) provides the
     bedtime fence.
   - EventKit observer is registered in the iOS app.

   Build per `INTELLIGENCE_REMEDIATION_PLAN.md §9`: new SwiftData models
   (`DayPlan`, `TimeBlock`, `TimeBlockKind`), `DayPlanner` service,
   `DayPlanView` UI with drag-reflow, re-plan triggers.

3. **Clean up the unrelated nutrition UX changes** in the working tree
   before declaring §9 done — they're orthogonal but they bloat the
   diff and confuse `git status`.

4. **Rotate the Anthropic key** (still pending from the previous
   handoff). Old key shipped on iOS in prior builds → burned. New key
   goes only into `tempo-backend` env, never into iOS config.

## Cheat sheet: how to test things

```bash
# Run the backend with a generous budget so fallback isn't masked by gate
cd ~/Projects/tempo/tempo-backend
CLAUDE_MONTHLY_BUDGET_CENTS=10000 swift run

# Mint a JWT
JWT=$(~/Projects/tempo/tempo-backend/scripts/mint_test_jwt.py user_smoke_test_001)

# Reset the daily AI-call counter
redis-cli DEL "ai_limit:user_smoke_test_001:$(date +%Y-%m-%d)"

# Re-seed the test user if the fixture window has lapsed
PGPASSWORD=tempo_dev psql -U tempo -h localhost -d tempo -c "
  DELETE FROM user_subscriptions WHERE user_id = 'user_smoke_test_001';
  INSERT INTO user_subscriptions
    (id, user_id, product_id, original_transaction_id,
     purchase_date, expiration_date, is_trial, is_active, environment,
     created_at, updated_at)
  VALUES
    (gen_random_uuid(), 'user_smoke_test_001', 'com.tempo.pro.monthly',
     'TEST_TXN_' || extract(epoch from now())::text,
     NOW(), NOW() + INTERVAL '30 days',
     false, true, 'sandbox', NOW(), NOW());
  UPDATE users SET ai_consent_at = NOW() WHERE id = 'user_smoke_test_001';"
```

End of handoff.
