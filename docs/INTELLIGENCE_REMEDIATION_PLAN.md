# Tempo Intelligence System — Remediation Plan

> **Audience:** an AI coding agent (Claude Code, Cursor, or similar) operating with full repo access.
> **Status when written:** 2026-05-14, after a deep audit by Claude Opus 4.7.
> **Source audit:** the conversation that produced this file lives in the repo owner's session history. The findings below are the durable summary.
> **App state:** personal-use, not yet on App Store. Currently 1 user (Nicola). Goal is a shippable, multi-user, monetisable product.

---

## 0. How to use this document

This file is the master remediation plan for the Tempo intelligence + monetisation layer. It is structured so an AI agent can read it top-to-bottom and execute without further human input on most steps.

**Before doing anything in this file, the AI MUST run its own verification pass.** The findings here were accurate when written but the codebase changes. The verification pass is specified in §1. Do it. Do not skip it. If your verification disagrees with this document, trust the codebase and update this document with a note explaining what changed.

**Order of operations is non-negotiable.** Fixes are dependency-ordered. Do them in the order given. The first two (Anthropic key removal + backend proxy + subscription gate) are blockers for everything else; do not start §6 work until §3–§5 are merged.

**Conventions used below:**
- `Path:` lines reference exact files relative to the repo root `/Users/nicoladebbia/Projects/tempo/`.
- `Spec:` lines reference the canonical specification document and section.
- Each fix has explicit `Done when:` criteria. Treat them as a test.
- When a fix needs a product decision (price tier, free/Pro feature split), the AI MUST stop and ask the user before implementing. These are marked `DECISION REQUIRED:`.

---

## 1. Mandatory verification pass (run this first, every time)

Before treating any finding in this document as current, the AI must verify by running these commands and reading the results. Do this in a single batch with parallel tool calls.

```bash
# 1.1 — Is the Anthropic key still embedded in the iOS target?
grep -rn -i "anthropic\|claude" Tempo/Tempo/Configuration/ Tempo/Tempo/Info.plist

# 1.2 — Which iOS files still call Anthropic directly?
grep -rln "ClaudeAPIClient\|api.anthropic.com" Tempo/Tempo/

# 1.3 — Which backend routes proxy Claude?
grep -n "register\|use:" tempo-backend/Sources/App/routes.swift
grep -n "api.anthropic.com" tempo-backend/Sources/App/Services/

# 1.4 — Is the subscription controller wired into routes.swift?
grep -n "SubscriptionController" tempo-backend/Sources/App/routes.swift

# 1.5 — Daily time-blocked plan: still unbuilt?
grep -rli "DayPlanner\|TimeBlock\|ScheduleEngine\|DailyTimeBlock" Tempo/Tempo/

# 1.6 — Has the key ever been committed to git?
git log --all --oneline -- Tempo/Tempo/Configuration/Secrets.xcconfig
git log --all -p -S 'sk-ant-api03' --oneline | head -20

# 1.7 — Confirm AI feature count vs. spec
grep -n "^### 3\." docs/AI_INTELLIGENCE_ENGINE.md
```

Then read these files in full before proposing changes:
- `docs/AI_INTELLIGENCE_ENGINE.md` — entire file (~2,600 lines). This is the spec.
- `docs/ARCHITECTURE_DECISIONS.md` — at minimum ADR-004 (Vapor), ADR-008 (JWT), ADR-013 (EventKit), ADR-018 (Claude on backend only), ADR-020 (Freemium pricing).
- `docs/MONETIZATION_STRATEGY.md` — for free/Pro feature split.
- `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 6.6 — for AI cost math.
- `tempo-backend/Sources/App/Services/InsightService.swift` — full file. This is the template for new AI services.
- `tempo-backend/Sources/App/Services/NutritionAIService.swift` — full file. This is the template for the simpler text-only Claude calls.
- `tempo-backend/Sources/App/Controllers/InsightController.swift` and `SubscriptionController.swift` — full files.
- `Tempo/Tempo/Services/Nutrition/ClaudeAPIClient.swift` — the file we are deleting.
- All five iOS direct callers of `ClaudeAPIClient`:
  - `Tempo/Tempo/Services/Nutrition/NutritionCoachService.swift`
  - `Tempo/Tempo/Services/Nutrition/MealPlanGeneratorService.swift`
  - `Tempo/Tempo/Services/Nutrition/NaturalLanguageLoggingService.swift`
  - `Tempo/Tempo/Services/Nutrition/MealRedistributionService.swift`
  - `Tempo/Tempo/Services/Nutrition/PhotoAnalysisService.swift`
- `Tempo/Tempo/Services/Subscriptions/SubscriptionService.swift` — existing client.
- `Tempo/Tempo/App/APIClient.swift` (or wherever it lives — find via `grep -rn "class APIClient\|struct APIClient" Tempo/Tempo/`) — the JWT-attaching HTTP client.

After verification, write a short note (≤200 words) at the top of your work session that says: "Verified against 2026-05-14 plan. Deltas found: [list], or: no deltas, plan is still accurate." Then proceed.

---

## 2. Current state (summary, post-verification)

These are the findings the plan is built on. The AI must confirm or correct them in §1.

### 2.1 Intelligence layer is 2/12 complete

`docs/AI_INTELLIGENCE_ENGINE.md` §1 lists 12 AI features. Reality:

| State | Count | Features |
|---|---|---|
| End-to-end through backend | 2 | Weekly Report (`/v1/insights/weekly-report`), Pattern Detection (`/v1/insights/patterns`) |
| Single-shot endpoint exists, spec calls for batch | 1 | Drill Sergeant (`/v1/insights/drill-sergeant` exists; spec §3.4 requires Sun + Wed batch of 3 days × 6 channels = 36 copies — not built) |
| Rule-based, no AI path | 4 | Training Program, Recovery Prescription, Meal Timing, Morning Briefing |
| Completely missing | 5 | Training Adjustment, Study Schedule Optimization, Achievement Copy, Dashboard Insights, Notification Batch Pre-Generation |

`docs/BUILD_PROGRESS.md` Phase 15 is marked ✅ complete. **This is wrong.** Correct it as part of §10.

### 2.2 Side-channel nutrition AI bypasses the backend

Five iOS services call Anthropic directly via `Tempo/Tempo/Services/Nutrition/ClaudeAPIClient.swift`:
- `NutritionCoachService` — coach Q&A
- `MealPlanGeneratorService` — weekly meal plan generation
- `NaturalLanguageLoggingService` — "I ate 2 eggs and toast"
- `MealRedistributionService` — recompute remaining meals
- `PhotoAnalysisService` — vision-based meal logging

These are functional but architecturally wrong. They violate ADR-018 ("Claude called from Vapor backend only — never from iOS directly").

### 2.3 Anthropic API key ships in the app binary

- **Location:** `Tempo/Tempo/Configuration/Secrets.xcconfig:12` holds a live key (`sk-ant-api03-…`).
- **Build path:** all three xcconfigs (`Development`, `Staging`, `Production`) preprocess it into `Info.plist:42–43` via `INFOPLIST_PREPROCESSOR_DEFINITIONS`.
- **Runtime:** `ClaudeAPIClient.swift:61` reads `Bundle.main.infoDictionary["ANTHROPIC_API_KEY"]` and uses it as `x-api-key` to `https://api.anthropic.com/v1/messages`.
- **Git history:** clean. `.gitignore:15` excludes `Secrets.xcconfig`. The key was never committed.
- **Exposure:** any user can `unzip Tempo.ipa && plutil -p Payload/Tempo.app/Info.plist` to extract it. Public App Store release means anyone can drain the account.

### 2.4 Subscription infrastructure is partially built but not wired

- iOS: `Tempo/Tempo/Services/Subscriptions/SubscriptionService.swift` uses StoreKit 2, observes transactions, tracks state. `Tempo/Tempo/Views/Shared/PaywallView.swift` exists. `SubscriptionProduct` enum exists.
- Backend: `tempo-backend/Sources/App/Controllers/SubscriptionController.swift` has `verifyReceipt`, `subscriptionStatus`, `handleWebhook` methods. Receipt model + migrations exist.
- **Critical gap:** `SubscriptionController` is **not registered** in `tempo-backend/Sources/App/routes.swift`. The routes do not exist at runtime.
- No subscription middleware checks any AI route. There is no enforcement layer.

### 2.5 Infrastructure layer (AI §2.3–§11) is thin

| System | Status |
|---|---|
| Per-model circuit breakers | Implemented (`InsightService.swift:367`) |
| Retry with malformed-JSON repair | Partial — extracts JSON but does not retry with simplified prompt per §2.3 |
| Budget tracker | **Stub** — `trackTokenUsage` logs but does not enforce the monthly cap or 50/80/95% thresholds |
| Daily per-user limit (12 calls/day) | Partial — `checkDailyAILimit` exists |
| Response caching (`insight:weekly:{user}:{week}`) | **Missing** — no `insights` table, no Redis cache; every call hits Claude |
| Data anonymization (§4.4) | **Missing** |
| User AI consent (§11.3) | **Missing** — no checkbox in `OnboardingViewModel` |
| Fallback templates (§8) | Partial — weekly report, drill sergeant, pattern detection have fallbacks; morning briefing, recovery prescription, meal timing do not (because the AI features don't exist) |

### 2.6 Daily time-blocked plan is fully unbuilt

Grep `DailyPlan|TimeBlock|ScheduleEngine|DayPlanner` returns zero hits in `Tempo/Tempo/`. The only hits are `WeeklyPlan.days: [DailyPlan]` in `STATE_MACHINES.md` / `MODULE_TRAINING.md`, which refers to the **weekly training plan** (a 7-element list of workout types), not an hour-by-hour day plan.

The daily plan is a **new composite feature** that fuses spec §3.5 (training program) + §3.7 (study schedule) + §3.8 (meal timing) + EventKit free-window discovery (`ADR-013`) + onboarding personalisation. It is not a regression against an existing spec section; it does not appear in `AI_INTELLIGENCE_ENGINE.md` at all.

### 2.7 Onboarding does not capture the fields the daily plan needs

`Tempo/Tempo/ViewModels/OnboardingViewModel.swift` captures: `displayName`, `username`, `doesTrain`, `trainingTypes`, `daysPerWeek`, `preferredSplit`, `experienceLevel`, `university`, `yearOfStudy`, `examSchedule` (free-text string), `primaryGoal`, `studyTarget`, `mealTarget`, `timeWasters`, `eveningStartTime`, `whoopConnected`, `healthkitGranted`, `notificationsGranted`.

**Missing for daily plan:**
- `wakeTime` (Date, time-only) — first block of day
- `sleepTargetHours` (Double, 7.0–9.0) — bedtime fence
- `chronotype` (`{earlyBird, neutral, nightOwl}`) — AM vs PM bias
- `classBlocks` (`[ClassSchedule]` with weekday + start + end + course code) — replaces the unstructured `examSchedule` string
- `workOrJobHours` (`[WeeklyWorkBlock]?`) — fixed blocks not in EventKit
- `trainingTimePreference` (`{morning, midday, evening, anyFree}`)
- `eatingWindow` (`(start, end)`) — intermittent fasting support
- `mealAnchors` (`{breakfastSkipped, postWorkoutMandatory}`)
- `studySessionLengthPref` (Int, e.g. 25/50/90 min) — Pomodoro size
- `weekendDifferential` (`{sameAsWeekday, lateWake, fullOff}`)
- `aiConsent` (Bool) — required by AI spec §11.3 before any Claude route is callable

---

## 3. FIX #1 — Eliminate the embedded Anthropic key (highest urgency)

**Why first.** Every TestFlight or App Store build today ships the key in `Info.plist`. Anyone with the .ipa can extract it. The key is single-user authentication to Nicola's Anthropic account with no rate limit per attacker. Rotate AFTER the proxy is built so the new key never lives on a client.

**Dependency:** none.
**Blocks:** §4 (subscription gate), §5 (multi-tenant billing), public release.

### 3.1 Build five new backend routes that proxy the iOS-side Claude callers

Mirror the pattern in `tempo-backend/Sources/App/Services/NutritionAIService.swift` (text-only Haiku) and `InsightService.swift` (multi-model, circuit breaker, fallback).

Routes to add under `protected.grouped("nutrition", "ai")` in `routes.swift`:

| Route | Model | Replaces | Notes |
|---|---|---|---|
| `POST /v1/nutrition/ai/coach/ask` | Haiku 4.5 | `NutritionCoachService` | Multi-turn conversation; pass full transcript |
| `POST /v1/nutrition/ai/meal-plan/generate` | Sonnet 4.6 | `MealPlanGeneratorService` | High `max_tokens` (32K already configured); should be background job + push notification on completion, not synchronous |
| `POST /v1/nutrition/ai/meal-plan/redistribute` | Haiku 4.5 | `MealRedistributionService` | Synchronous |
| `POST /v1/nutrition/ai/log/natural-language` | Haiku 4.5 | `NaturalLanguageLoggingService` | Synchronous |
| `POST /v1/nutrition/ai/log/photo` | Haiku 4.5 (Vision) | `PhotoAnalysisService` | Multipart upload, base64 image to Claude. Per AI spec §10.2 this is "v2" — consider Pro-gating from day one |

Each route follows this template (copy from `InsightController.weeklyReport`):

```
1. JWT-protected (via `protected` group)
2. Rate-limited per user (existing RateLimitMiddleware at 20/min)
3. Subscription check — see §4 — return 402 for free users
4. Daily AI call limit check (existing `checkDailyAILimit`)
5. Build prompt from request body
6. Call service (which calls Claude with circuit breaker + retry + token tracking)
7. Increment daily AI count
8. Return Envelope<T>
```

Move prompts from iOS to backend:
- `Tempo/Tempo/Services/Nutrition/MealPlanPrompts.swift` → `tempo-backend/Sources/App/Services/Prompts/MealPlanPrompts.swift`
- `Tempo/Tempo/Services/Nutrition/NutritionCoachPrompts.swift` → `tempo-backend/Sources/App/Services/Prompts/NutritionCoachPrompts.swift`
- `Tempo/Tempo/Services/Nutrition/MealRedistributionPrompts.swift` → `tempo-backend/Sources/App/Services/Prompts/MealRedistributionPrompts.swift`
- `Tempo/Tempo/Services/Nutrition/MealRecipePrompts.swift` → `tempo-backend/Sources/App/Services/Prompts/MealRecipePrompts.swift`

Delete the iOS copies after moving. Prompts are pure data; no Swift-runtime dependencies.

**Done when:**
- All five routes return 200 with valid responses when called via curl with a valid JWT.
- `tempo-backend/Sources/App/Services/Prompts/` exists with the four prompt files.
- No prompt files remain in `Tempo/Tempo/Services/Nutrition/`.

### 3.2 Refactor the five iOS services to call backend instead of Anthropic

For each of the five services in §2.2:

1. Replace the `private let claude: ClaudeAPIClient` dependency with `private let apiClient: APIClient` (already used elsewhere in the app — find via `grep -rn "class APIClient" Tempo/Tempo/`).
2. Replace each `claude.send(model:..., systemPrompt:..., userPrompt:...)` call with `apiClient.post("/v1/nutrition/ai/<route>", body: <RequestDTO>)`.
3. Define matching `Codable` request/response DTOs in the iOS service and in the backend (same shape, snake_case via the existing `ContentConfiguration`).

Match each iOS service to the backend route from the table in §3.1.

**Done when:**
- All five services compile with no reference to `ClaudeAPIClient`.
- Manual smoke test: each AI nutrition feature still works end-to-end via the backend.

### 3.3 Delete `ClaudeAPIClient.swift` and scrub the key

After §3.2 compiles and all five callers are migrated:

1. Delete `Tempo/Tempo/Services/Nutrition/ClaudeAPIClient.swift`.
2. Delete the `ANTHROPIC_API_KEY` line from:
   - `Tempo/Tempo/Configuration/Secrets.xcconfig`
   - `Tempo/Tempo/Configuration/Development.xcconfig` (remove from `INFOPLIST_PREPROCESSOR_DEFINITIONS`)
   - `Tempo/Tempo/Configuration/Staging.xcconfig` (same)
   - `Tempo/Tempo/Configuration/Production.xcconfig` (same)
3. Delete the `ANTHROPIC_API_KEY` `<key>` + `<string>` block from `Tempo/Tempo/Info.plist:42–43`.
4. Remove the `__ANTHROPIC_API_KEY__=$(ANTHROPIC_API_KEY)` token from the preprocessor define lines in all three xcconfigs.

**Done when:**
- `grep -rn -i "anthropic\|claude" Tempo/Tempo/ Tempo/Tempo.xcodeproj/` returns ZERO hits (excluding `Tempo.app` build artifacts in DerivedData if any).
- Build succeeds (the key is no longer referenced).
- `plutil -p Tempo/Tempo/Info.plist` does not show `ANTHROPIC_API_KEY`.

### 3.4 Rotate the key in Anthropic console

Manual step for the user:
1. Anthropic console → API Keys → revoke the old key.
2. Generate a new key.
3. Add it to `tempo-backend` environment (Railway/Fly secret named `ANTHROPIC_API_KEY`). The backend already reads this — see `InsightService.swift` and `NutritionAIService.swift` for confirmation.
4. Verify the new key works by hitting `/v1/insights/weekly-report` with a test JWT.

**Done when:**
- Old key returns 401 from Anthropic if used directly.
- New key is in backend env only.
- Backend AI routes return 200.

---

## 4. FIX #2 — Wire and enforce the subscription gate

**Why second.** The proxy in §3 means free users could spam expensive Claude calls. Without a subscription gate every public user is a cost center. Per `docs/TECHNICAL_FEASIBILITY_AUDIT.md` §6.6: AI must be Pro-only or the unit economics never work.

**Dependency:** §3 complete (need routes to gate).
**Blocks:** public App Store submission.

### 4.1 Wire `SubscriptionController` into `routes.swift`

Currently `tempo-backend/Sources/App/Controllers/SubscriptionController.swift` defines the routes (`POST /verify`, `GET /status`, `POST /webhook`) but the controller is **not registered** in `tempo-backend/Sources/App/routes.swift`.

Add this block to `routes.swift` after the existing protected routes:

```swift
// Subscriptions — per BUILD_PLAN Step 20.1
// POST /v1/subscription/verify  (JWT)
// GET  /v1/subscription/status  (JWT)
// POST /v1/subscription/webhook (unauthenticated, JWS-verified)
try v1.grouped("subscription")
    .grouped(RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .user))
    .register(collection: SubscriptionController())
```

**Done when:** `curl /v1/subscription/status` with a valid JWT returns the user's status.

### 4.2 Add `SubscriptionMiddleware` to the backend

New file `tempo-backend/Sources/App/Middleware/SubscriptionMiddleware.swift`:

- Reads the authenticated user from JWT.
- Looks up the user's active subscription in the `subscriptions` table (or Redis cache with 5-minute TTL).
- If active → call `next.respond(to: request)`.
- If not → throw `Abort(.paymentRequired, reason: "Pro subscription required")` with a structured payload `{ error: "subscription_required", upgrade_url: "tempo://paywall" }`.

Apply the middleware to every AI route:
- All routes under `protected.grouped("insights")`
- All routes under `protected.grouped("nutrition", "ai")`
- The new routes from §3.1

Do NOT apply it to: auth, whoop integration management, sync, devices, friend/leaderboard/challenge/achievement reads. Those remain free.

**Done when:**
- Free user JWT → AI route → 402 with structured upgrade payload.
- Pro user JWT → AI route → 200.

### 4.3 Add `requiresProAccess` to the iOS APIClient

When the iOS app hits a 402 from any AI route:
1. `APIClient` decodes the structured payload.
2. Throws a typed `APIError.subscriptionRequired` error.
3. The calling view catches the error and presents `PaywallView`.

Update each of the five iOS services migrated in §3.2 to surface this cleanly (don't fail silently — show paywall).

**Done when:**
- Tapping "Generate meal plan" as a free user opens the paywall instead of erroring.

### 4.4 Decide the free / Pro feature split

**DECISION REQUIRED.** Read `docs/MONETIZATION_STRATEGY.md` first. Then ask the user to confirm:

| Feature | Free | Pro |
|---|---|---|
| Dashboard 4-quadrant view | ✅ | ✅ |
| Workout logging | ✅ | ✅ |
| Non-negotiables tracking | ✅ | ✅ |
| HealthKit + Whoop sync | ✅ | ✅ |
| Rule-based recovery zones | ✅ | ✅ |
| Weekly Report (AI) | ❌ | ✅ |
| Pattern Detection (AI) | ❌ | ✅ |
| Drill Sergeant copy variants (AI) | ❌ | ✅ |
| Meal plan generation (AI) | ❌ | ✅ |
| Natural-language food logging (AI) | ❌ | ✅ |
| Nutrition coach Q&A (AI) | ❌ | ✅ |
| Meal redistribution (AI) | ❌ | ✅ |
| Photo meal logging (AI) | ❌ | ✅ (or Pro+) |
| Arena (leaderboards, friends, XP) | Limited (5 friends) | Unlimited |
| Daily time-blocked plan (when built) | Rule-based skeleton ✅ | AI-hydrated copy ✅ |

Default to this table unless the user says otherwise.

### 4.5 Decide the pricing tier

**DECISION REQUIRED.** Three options, ask the user:

**Option A (recommended, matches ADR-020):** Single Pro tier $4.99/mo or $39.99/yr. Student discount $3.99/mo via .edu verification.

**Option B:** Two-tier — Pro Lite $2.99/mo (Haiku only, 50 calls/mo) + Pro $4.99/mo (all models, 12 calls/day).

**Option C:** Single tier with usage-metered overage (NOT recommended — Apple discourages metered billing for consumer apps; complex UI).

Default to Option A.

**Done when:** App Store Connect has the products configured, `SubscriptionProduct` enum on iOS matches, and the price is rendered correctly in `PaywallView`.

### 4.6 Add `aiConsent` to onboarding (AI spec §11.3)

Even with a Pro gate, Apple Review and GDPR/CCPA require explicit consent before sending user health data to a third-party AI processor.

1. Add `var aiConsent: Bool = false` to `OnboardingViewModel`.
2. Add a new onboarding step (between `notifications` and `complete`) titled "AI Coaching":
   - Body copy: "Tempo uses Claude AI to generate personalised insights from your training, sleep, and nutrition data. Your data is sent to Anthropic only when you trigger an AI feature, and is never used to train their models. You can disable AI features anytime in Settings."
   - Two buttons: "Enable AI features" / "Skip — use rule-based only"
3. Persist consent to `UserSettings` (SwiftData) and sync to backend on next login.
4. Backend: store `ai_consent_at: Timestamp?` on `User`. `SubscriptionMiddleware` checks this in addition to subscription status — if consent is missing, return 402 with `{ error: "ai_consent_required" }`.

**Done when:** A user who skipped AI consent cannot trigger AI features even if they have an active Pro subscription, and gets a clear in-app prompt to enable it in Settings.

---

## 5. FIX #3 — Enforce `AIBudgetTracker` as a hard ceiling

**Why third.** Once §3 + §4 ship, you have per-user gating but no global ceiling. A bug, abuse, or 10x signup spike can still produce a surprise Anthropic bill.

**Dependency:** §3 complete.
**Blocks:** confident scaling beyond ~100 users.

Per AI spec §5.4:

1. Move `currentMonthSpendCents` from in-memory (current `InsightService` stub) to PostgreSQL — add `ai_monthly_spend` table: `(year_month TEXT PRIMARY KEY, spend_cents INT, updated_at TIMESTAMP)`.
2. Replace `trackTokenUsage` (`InsightService.swift:327`) with a real `AIBudgetTracker` actor that:
   - Reads the current month's spend from DB on init, caches in memory.
   - On every Claude call: checks `currentMonthSpendCents + estimatedCost <= monthlyBudgetCents` BEFORE making the call. If over → throw `AIError.budgetExhausted` → fallback path.
   - Persists spend deltas to DB every 60s (or on every call if simpler).
3. Implement the 50/80/95% threshold actions per spec §5.4:
   - 50% → log warning, set `pattern_detection_frequency = biweekly` in a settings table
   - 80% → disable on-demand pattern queries, downgrade pattern detection from Opus to Sonnet
   - 95% → disable all non-essential AI features (only recovery prescription remains)
   - 100% → all AI features return 503 with `{ error: "ai_budget_exhausted" }`; iOS falls back to rule-based outputs
4. Default `AIConfig.monthlyBudgetCents` to 5000 ($50). Configurable via `Environment.get("CLAUDE_MONTHLY_BUDGET_CENTS")`.

**Done when:**
- Setting the budget to $0.01 in env and making any AI call returns 503 with the fallback payload.
- Spend across requests persists to DB and is reread on backend restart.

---

## 6. FIX #4 — Add response caching

**Why fourth.** Spec §6 mandates caching weekly reports forever, pattern detection per-correlation, etc. Currently every request hits Claude. At any meaningful user count this is wasted spend.

**Dependency:** §3, §5 complete.

1. Add `insights` PostgreSQL table: `(id UUID, user_id UUID, feature TEXT, cache_key TEXT, response JSONB, generated_at TIMESTAMP, expires_at TIMESTAMP)` with index on `(user_id, feature, cache_key)`.
2. In each AI service, before calling Claude:
   - Compute cache key per spec §6.1 (e.g. `insight:weekly:{user_id}:{week_start}`).
   - Check `insights` table. If hit and not expired → return cached response with `cached: true` flag.
   - On miss → call Claude → store result with appropriate TTL → return.
3. TTLs per spec §6.1 (weekly report: 7 days soft / forever hard; pattern detection: 7 days; etc.).
4. Implement stale-while-revalidate (§6.2): return stale response immediately, fire background refresh.

**Done when:** A second identical call within the TTL window returns from cache (verified by checking DB or by Claude call count metric).

---

## 7. FIX #5 — Build the missing AI features

**Why now.** With §3–§6 done, the architecture supports adding features safely: each new feature gets a route, a service mirroring `InsightService`, a circuit breaker, budget tracking, caching, subscription gate. All five pieces are reusable.

**Dependency:** §3, §4, §5, §6 complete.

Build in this order (P0 → P2 per spec §1):

### 7.1 Recovery Prescription (Haiku, P0)
- Route: `POST /v1/insights/recovery-prescription`
- Spec: §3.6
- Trigger: daily after Whoop sync (silent push from existing webhook handler)
- Inputs: Whoop today + 3-day trend, NutriTrack yesterday, calendar today, training-days-since-rest
- iOS consumer: `RecoveryEngine.swift` — add async method that calls backend and falls back to current rule-based output

### 7.2 Morning Briefing template engine (free, P0)
- Spec: §3.1 + §8.1 (template-first, Haiku fallback)
- This is FREE for users (no Claude call by default) — implement the template engine in Swift on backend
- Route: `GET /v1/insights/morning-briefing` returns the rendered template
- Haiku fallback fires only when template flags 3+ competing priorities
- iOS consumer: `NotificationService.swift:180` already accepts `BriefingContent`; populate it from this route

### 7.3 Training Adjustment (Haiku, P1)
- Route: `POST /v1/insights/training-adjustment`
- Spec: §3.11
- Trigger: on Whoop sync if recovery delta > 10 points
- Inputs: today's Whoop, planned workout
- iOS consumer: `TrainingEngine.swift` — async path

### 7.4 Drill Sergeant batch generation (Sonnet, P1)
- Replace single-shot `/v1/insights/drill-sergeant` with batch job
- Spec: §3.4
- Trigger: Sunday + Wednesday at 20:00 (scheduled job, same pattern as `WeeklySummaryJob`)
- Output: 36 notification copies (3 days × 6 channels × 2 batches/week) cached per user per day
- iOS consumer: `AccountabilityEscalationEngine.swift` — read from cache when scheduling notifications

### 7.5 Dashboard Insights (Haiku, P1)
- Route: `GET /v1/insights/dashboard`
- Spec: §3.10
- Trigger: on dashboard load if input-data hash changed since last generation
- iOS consumer: `DashboardViewModel.swift` — call on view appear

### 7.6 Training Program (Sonnet, P1)
- Route: `POST /v1/insights/training-program` (background job, push when ready)
- Spec: §3.5
- Trigger: weekly plan generation OR recovery-triggered re-planning
- iOS consumer: `TrainingEngine.swift` — replace rule-based output

### 7.7 Meal Timing (Haiku, P2)
- Route: `POST /v1/nutrition/ai/meal-timing` (lives under nutrition, not insights)
- Spec: §3.8
- Trigger: on NutriTrack data change
- iOS consumer: `NutritionEngine.mealTimingSuggestions` — replace with backend call

### 7.8 Study Schedule Optimization (Sonnet, P2)
- Route: `POST /v1/insights/study-schedule`
- Spec: §3.7
- Trigger: on exam creation/edit, or weekly planning
- DEPENDS ON: structured `classBlocks` from onboarding (see §7 onboarding gap)
- iOS consumer: new `StudyScheduleService.swift`

### 7.9 Achievement Copy (Haiku, P2)
- Route: `POST /v1/insights/achievement-copy`
- Spec: §3.9
- Trigger: on achievement unlock
- iOS consumer: `AchievementLibrary.swift` — async path

### 7.10 Notification Batch Pre-Generation (Sonnet, P1)
- Covered by §7.4 (same scheduled job)

For each: write the service mirroring `InsightService.weeklyReport`, write the controller method mirroring `InsightController.weeklyReport`, add subscription middleware, add cache, write a fallback, write a quality validator per spec §7.1.

**Done when:** All 12 features in `AI_INTELLIGENCE_ENGINE.md §1` have a working backend route with circuit breaker + budget tracker + cache + fallback + subscription gate.

---

## 8. FIX #6 — Capture the onboarding fields the daily plan needs

**Why now.** Cheap to ship. Day-1 personalisation. Doesn't depend on the daily plan engine.

**Dependency:** none (can ship in parallel with §3–§6).

Add fields to `OnboardingViewModel` and `UserSettings` (SwiftData) per §2.7. New onboarding steps:

1. **Wake & sleep** — wake time picker, sleep target hours slider, chronotype enum picker.
2. **Class schedule** — multi-row editor for weekday + start + end + course code. Replace the free-text `examSchedule` string.
3. **Work hours** (optional) — same shape as class blocks.
4. **Meal preferences** — eating window pickers, "skip breakfast?" toggle, "post-workout meal mandatory?" toggle.
5. **Study preferences** — Pomodoro length segmented control (25 / 50 / 90 min).
6. **Training preferences** — time-of-day segmented control (morning / midday / evening / any free).
7. **Weekend differential** — segmented control.

Persist to backend on next sync. Migrate the existing free-text `examSchedule` by attempting to parse on first launch, falling back to a "please re-enter your class schedule" prompt for existing users.

**Done when:** all 11 fields from §2.7 are captured and round-trip to backend.

---

## 9. FIX #7 — Build the daily time-blocked plan engine

**Why last.** It depends on §3 (proxy), §4 (gate), §6 (cache), §7 (training/study/meal AI features), §8 (onboarding fields).

**Dependency:** §3, §4, §6, §7.1–§7.8, §8 complete.

### 9.1 Data models

New SwiftData models:
- `DayPlan` — `(id, date, userId, generatedAt, blocks: [TimeBlock])`
- `TimeBlock` — `(id, dayPlanId, kind: TimeBlockKind, startMinuteOfDay: Int, endMinuteOfDay: Int, title: String, copy: String?, sourceId: String?)`
- `TimeBlockKind` enum — `class, exam, work, football, training, study, meal, recovery, sleep, free`

### 9.2 Free-window solver

New `Tempo/Tempo/Services/Engines/DayPlanner.swift`:
1. Fetch all EventKit events for the day → fixed blocks (R2 in §10.2 of the audit).
2. Compute free windows (R3) ≥ minimum useful length per kind.
3. Place training block respecting recovery + football constraints (R4) — call `/v1/insights/training-program` from §7.6 for the AI prose.
4. Place meals at anchored intervals (R5) — call `/v1/nutrition/ai/meal-timing` from §7.7.
5. Place study Pomodoros (R6) — call `/v1/insights/study-schedule` from §7.8.
6. Insert bedtime fence (R8) from `RecoveryEngine.suggestPrescription`.
7. Persist to SwiftData (R11).

### 9.3 Re-planning triggers

`DayPlanner.replan(reason:)` is called when:
- EventKit observer fires (new event added/deleted/changed)
- Whoop sync completes with a new recovery score
- Workout is logged earlier than planned

### 9.4 UI

New `Tempo/Tempo/Views/Dashboard/DayPlanView.swift`:
- Vertical 24h timeline.
- Each block is draggable (R10); subsequent blocks reflow.
- Tap a block → detail sheet with AI-generated copy.
- "Re-plan today" button at top.

### 9.5 Rule-based skeleton always works

Per ADR-014 (offline-first): if any AI route fails or the user is offline, render the rule-based skeleton without AI copy. Never block the timeline on a Claude call.

**Done when:**
- Opening the dashboard shows a full day timeline.
- EventKit calendar events appear as fixed blocks.
- Training, meals, study blocks are placed in free windows.
- Dragging a block reflows the others.
- Offline mode shows the skeleton without AI copy.

---

## 10. FIX #8 — Update `BUILD_PROGRESS.md`

Once §3 is merged, correct Phase 15 in `docs/BUILD_PROGRESS.md`:

```
## Phase 15: AI Intelligence Engine
- [x] 15.1: Claude API Backend Service ✅ 2026-03-25
- [x] 15.2: Weekly Report + Drill Sergeant Copy ✅ 2026-03-25
- [ ] 15.3: Migrate nutrition AI off iOS direct calls ⚠️ post-audit fix
- [ ] 15.4: Wire SubscriptionController + SubscriptionMiddleware
- [ ] 15.5: Enforce AIBudgetTracker
- [ ] 15.6: Add response caching layer
- [ ] 15.7: Build missing AI features (recovery prescription, morning briefing, training adjustment, drill sergeant batch, dashboard insights, training program, meal timing, study schedule, achievement copy)
- [ ] 15.8: Capture daily-plan onboarding fields
- [ ] 15.9: Build daily time-blocked plan engine
```

Mark items complete as the corresponding §s of this doc are finished.

---

## 11. Out of scope for this document

- Whoop production access approval (separate effort — track in `docs/TECHNICAL_FEASIBILITY_AUDIT.md` §2.1)
- Apple Watch companion (Phase 18, separate)
- Arena social features beyond what already exists
- Migration from SwiftData to anything else (ADR-003 stands)
- Any frontend redesign

---

## 11.5 Implementation log

| Fix | Status | Notes |
|---|---|---|
| §3 — Anthropic key removal + backend proxy | ✅ Shipped | 5 services migrated, key never committed to git, scrubbed from xcconfigs + Info.plist + pbxproj. Side benefit: APIClient now auto-unwraps backend `Envelope<T>` (fixed a latent bug). |
| §4 — Subscription gate | ✅ Shipped | `SubscriptionController` wired into routes; new `SubscriptionMiddleware` gates `/v1/insights/*`, `/v1/nutrition/ai/*`, `/v1/nutrition/receipts/structure`. Per-user 5-min Redis cache with explicit invalidation on verify/consent/webhook. New `TempoErrorMiddleware` preserves `Abort.identifier` as `code` so iOS can distinguish `subscription_required` from `ai_consent_required` without string parsing. AI consent column added to `User` (migration `AddAIConsentToUsers`). New `UserController` exposes `GET /v1/user/me` and `POST /v1/user/ai-consent`. New onboarding step `.aiConsent` between `.notifications` and `.complete` (`AIConsentView.swift`). iOS `APIError` gained `.subscriptionRequired` + `.aiConsentRequired` cases, decoded from the 402 body. |

## 12. Verdict — when is the system shippable to the App Store?

After §3, §4, §5, §6, §8 are merged. §7 and §9 are post-launch enhancements (the rule-based engines + the 2 working AI features are enough for v1). Public release without §3 + §4 is irresponsible — the embedded key alone is a hard block.

Estimated work order: §3 → §4 → §5 → §6 → §8 (in parallel with §5/§6) → ship v1. Then §7.1 → §7.2 → §9 → §7.3 etc. as v1.1, v1.2.

---

*End of remediation plan. The next agent: run §1 verification, post the delta note, then start at §3.*
