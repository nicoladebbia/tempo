# Nutrition Personalization Engine — Design Doc

> **Status: PROPOSAL — needs Nicola's approval before any code.**
> Author: Claude (Opus 4.8), 2026-06-02. Companion: `.plans/nutrition-world-findings.md`, `.plans/nutrition-world-plan.md`.
> Constraint: NO AI generation calls during design/approval. Weekly plan = ONE Sonnet call; daily adjust = FREE local algorithm.
>
> **How to read this:** each section is independently approvable. For each: **Decision needed**, **Recommendation**, **Effort tier** (FOUNDATIONAL / MEDIUM / HEAVY), and **Keep-vs-build**. Annotate inline (✅ approve / ✏️ change / ❌ skip) and hand back.

---

## 0. What's ALREADY wired — KEEP, do not rebuild

The audit (2026-06-02) found the Sonnet prompt is already rich. These work; the doc proposes NOTHING for them except feeding them more data:

- ✅ Dietary restrictions (allergies, dislikes, vegan/halal/etc.) → prompt.
- ✅ **Feedback digest** — 4-week MealFeedback aggregation (recipe ratings, feel chips, ingredient sentiment, substitutions; ≥2 swaps → drop recipe) inlined into the weekly prompt. Free-text notes ARE included. **No separate Haiku digest needed** — it fits the weekly call. (Resolves the earlier open question: weekly prompt, not a separate call.)
- ✅ Observed meal times (14-day rolling actual eat-times per slot) → prompt.
- ✅ Weekly training schedule (real Upper/Lower/Football split from UserSettings) → prompt, with day-type→macro mapping.
- ✅ Expiring pantry items (0–7 day window) → prompt.
- ✅ 7-day Whoop TDEE average → calorie calc (just shipped this session).
- ✅ Grocery generation = plan needs − pantry stock (GroceryListGenerator).

The personalization work is **feeding the MISSING data in** + the retention/daily-adjust/timing changes below — NOT rebuilding the prompt.

---

## 1. Goal weight — RESOLVED: it is NOT collected anywhere [FOUNDATIONAL]

**Finding (verified in onboarding views, not just the model):** Onboarding collects **current weight + height** (`ProfileSetupView`) and a **primary goal enum** cut/lean-gain/maintain (`GoalSetupView`). There is **NO goal/target weight field** anywhere — not in onboarding, not in `DietaryProfile`, not in `UserSettings`. The only `targetWeight` in the codebase is training set weights (unrelated).

So "reach the weight from onboarding" is not currently possible — the app has your *current* weight and a direction (cut/gain), but no *target*. Generation applies a generic ±200/−400 kcal from the enum, not a rate toward a number.

**Decision needed:** add a goal weight (and optionally target date / rate) to onboarding + model + prompt?

**Recommendation:** YES.
- Add `goalWeightKg: Double?` to `DietaryProfile` (lightweight SwiftData migration — confirmed no V2 needed).
- Add a goal-weight field to `GoalSetupView` (and an editable spot — see §7 Settings page).
- Feed `currentWeightKg`, `goalWeightKg`, and a sane weekly rate (e.g. 0.25–0.5 kg/wk, capped by TDEECalculator's existing 25% deficit / 15% surplus safety rails) into the prompt + calorie target so the deficit/surplus is *computed toward the target*, not a flat enum offset.
- Re-derive each Sunday: as current weight changes (HealthKit/Whoop body weight, or manual), recompute the surplus/deficit to stay on track.

**Effort:** FOUNDATIONAL (small migration + one onboarding field + prompt line). Highest intent-match — this is the "end goal" you named.

**DECIDED (2026-06-02):** goal weight + **weekly rate** (e.g. 0.25/0.5 kg/wk). **CRITICAL implementation note:** the rate-derived deficit/surplus must REPLACE `TDEECalculator.applyGoalAdjustment`'s enum offset (±200/−400), NOT stack on it — else the deficit double-counts (same bug class as the carryover overlap). Reconcile INSIDE `TDEECalculator.calculate`: the `primaryGoal` enum becomes the *direction*, the rate sets the *magnitude*. Both callers (fallbackTargets, MealPlanGeneratorService) hit calculate, so centralize there. Verify: a profile with goal weight + rate is not adjusted twice.

---

## 2. Plan history retention — STOP destroying the learning signal [FOUNDATIONAL]

**Finding:** `MealPlanGeneratorService` (lines 854–871) **hard-deletes** active plans on regen. Cascade: `WeeklyMealPlan → PlannedMeal → Recipe` all wiped. What SURVIVES already: `MealFeedback` (`.nullify` + denormalized recipeID), `MealLog` (independent). What DIES: per-meal **eaten/skipped/modified status**, **actualEatenAt** times, and the recipes — i.e. the record of what you actually did vs. what was planned.

`PantryItem` and `Recipe` already use an `isArchived` soft-delete pattern to copy.

**Decision needed:** confirmed with Nicola — **keep behavior + feedback, archive the plan** + a **"Past Plans" history view**.

**Design:**
- Add `isArchived: Bool = false` to `WeeklyMealPlan` (lightweight migration).
- Generator: replace `modelContext.delete(existing)` with `existing.isActive = false; existing.isArchived = true`. (Fixes the original duplicate-meals bug differently: the Today/active queries already filter on `isActive` + `coversToday` from this session's Phase 1, so archived plans won't pollute Today.)
- **Prune policy:** keep last **8 weeks** of archived plans; delete older on the Sunday run (storage bound + still plenty of history for the AI).
- **Past Plans view:** new screen (Plan tab or Settings) listing prior weeks → tap → what was planned, what you ate (status badges), adherence %, feedback.
- **Personalization read:** the Sunday prompt reads last week's archived plan's PlannedMeal statuses + actualEatenAt + feedback = "what actually happened," not just the prescription.

**Effort:** FOUNDATIONAL (migration + soft-delete swap + prune) + MEDIUM (the history view UI). Split into two sub-phases so the data fix lands before the UI.

**Cross-surface:** touches WeeklyMealPlan (shared). Verify Today, Plan, Fuel, Dashboard after — enumerate readers per CLAUDE.md shared-model rule.

---

## 3. Pantry-stock into the prompt — the sleeper, highest intent-match [FOUNDATIONAL]

**Finding:** Only **expiring** pantry items reach the prompt. Full stock does NOT — so the AI literally cannot build meals around what you already own. You spent half your original message on exactly this ("use mainly the things I already have in the pantry").

**Decision needed:** inject full (non-archived, qty>0) pantry inventory into the weekly prompt + instruct pantry-first meal building?

**Recommendation:** YES — cheap prompt change, huge intent-match.
- Add a "pantry on hand" block to `weeklyPlanPrompt()`: canonical name + quantity + unit, grouped by storage location.
- Prompt directive: "Prefer recipes that consume pantry stock before specifying new purchases. Only add a grocery item when a recipe genuinely needs something not on hand."
- This makes the grocery list (already = needs − stock) shrink correctly, matching your "buy the correct amounts" goal.

**Effort:** FOUNDATIONAL (prompt builder + one data fetch). Do early.

**Note:** the **intelligent short-split** (9 eggs over 3 days, whole-number portions, not 3.5+3.5) is *generator/prompt* logic that belongs here: the prompt must instruct whole-unit portioning for countable foods and respect pantry quantity caps. Deferred from the decrement service (already built) — it's a generation concern.

---

## 4. Daily adjust + MacroCarryover — ONE system, conservative, Whoop-gated missed-log [MEDIUM]

**Finding + the hard problem:** `MacroCarryoverService` exists and its **entire job** is spreading (target − actual) over 5 days — which is **exactly what you rejected** ("if a day has 3k but I log 2500, it can't give 500 the next day"). Its forgot-to-log guard only skips when **ZERO** logs exist; your scenario is *partial* (logged breakfast+dinner, forgot lunch → shows 1000, looks like a fake ~2000 deficit) and **sails past the guard**.

**Decision needed:** (a) does the new conservative daily-adjust **REPLACE** MacroCarryover, or coexist? (b) confirm the missed-log detector design.

**Recommendation:**
- **REPLACE.** Rip out the 5-day deficit spread. Two overlapping deficit systems is a bug factory. The new daily-adjust is the single system.
- **Conservative rule:** do NOT aggressively dump a deficit forward. If yesterday was a *real* small deficit (logged plausibly, under target by a little), surface it as information ("you're slightly under — fine") and apply at most a *gentle* nudge (capped, e.g. ≤150 kcal) to today, NOT the full delta. Never carry a surplus into a cut.
- **Missed-log detector (the key piece — uses Whoop as you intended):** flag a day as *probable missed-log* (not a real deficit) when logged intake is implausibly low **relative to Whoop expenditure + the number of planned meals left unmarked**. Concretely: if `loggedCalories < 0.5 × (whoopExpenditure or TDEE)` AND ≥1 planned meal has no eaten/skipped status → treat as missed-log: **trigger a notification** ("Did you eat lunch? Log it.") and do **NOT** carry the gap.
- Morning "did you eat yesterday's plan?" confirmation (your earlier choice) feeds the same detector.

**Effort:** MEDIUM. Touches MacroCarryoverService (rip/replace), NutritionTargetCalculator (reads the adjustment), DailyResetCoordinator (capture call site), + a notification.

---

## 5. Per-day Whoop strain/recovery/sleep into the prompt [MEDIUM]

**Finding:** Only the 7-day TDEE *average* is used. Per-day strain, recovery, and sleep are all fetchable (fetchRecoveryBatch, fetchSleepBatch, WhoopCycleData.strain) but NOT injected into the weekly prompt.

**Decision needed:** feed last-week per-day strain/recovery/sleep into the Sunday prompt?

**Recommendation:** YES, summarized (not raw 7×N numbers — token budget). Per training day: strain band (low/med/high), recovery zone (red/yellow/green), sleep hours. Lets the AI bias carbs/protein/calories to high-strain + low-recovery days. The recovery-adjusted logic (NutritionEngine.adjustedTargets) already exists for *today*; this extends the *signal* into weekly planning.

**Effort:** MEDIUM (batch fetch + prompt summarization block).

---

## 6. Variable meal count + training-time snack placement [MEDIUM]

**Finding:** Hardcoded **4 meals/day** (B/L/D/Snack, 25/30/30/15%). Snack defaults to ~16:00 regardless of training time. No pre/post-workout placement.

**Decision needed:** support variable meal count + snack placement around training time?

**Recommendation:** YES — this was an explicit complaint (Dinner 19:30 then Snack 16:00 out of order; same times daily).
- Let the prompt choose **2–6 meals/day** based on eating window, calorie load, and training. Multiple snacks allowed (AM, mid-afternoon, post-dinner).
- **Training-time anchoring:** pass each day's training *time* (not just type) — if you train 18:00, place a pre-workout snack ~16:30–17:00 and/or a post-workout meal; if 15:00, shift accordingly. Requires training *time* in the schedule (today only the type/weekday is wired — check UserSettings for a per-day time; if absent, add it).
- **Chronological guarantee:** the generator/parser must sort meals by time so a 16:00 snack never renders after a 19:30 dinner (belt-and-suspenders; the Today sort already does minutes-of-day).

**Effort:** MEDIUM (prompt meal-structure rules + possibly add training-time to schedule + parser ordering).

**DECIDED (2026-06-02):** training time = a **daily check-in ask** ("playing soccer today? what time? gym? what time?"), NOT a static per-day schedule field — handles real-life variability. This **merges with the §4 morning "did you eat yesterday's plan?" check-in** into one daily interaction. The answer feeds snack placement for the day's meals. (Tier 2 — does not affect Tier 1.)

---

## 7. Settings "Meal Plan" page + Saturday pre-run notification [MEDIUM]

**Finding:** Re-onboarding-style intake exists (MealPlanIntake: cookableDaysThisWeek, leftoverTolerance, eatingWindow, groceryIntent). Stable prefs (allergies, dislikes) live in DietaryProfile.

**Decision needed:** confirmed with Nicola — replace weekly re-onboarding with a **Settings "Meal Plan" page** (edit anytime) + a **Saturday pre-run notification** ("anything to change before tomorrow's plan?").

**Design:**
- One Settings screen: stable prefs (allergies, dislikes, dietary flags, goal weight from §1) + weekly-changing fields (cookable days, leftover tolerance, eating window, grocery budget/stores). Edit anytime; the Sunday run reads current values.
- Saturday notification → taps into that screen.
- Removes the weekly wizard friction (you'd skip it within two weeks).

**Effort:** MEDIUM (one settings view wiring existing models + one scheduled notification).

---

## 8. Per-muscle protein targeting — phase LAST [HEAVY]

**Finding:** Training schedule is known by *type* (Upper/Lower/Football). `Exercise.muscleGroup` / `secondaryMuscles` exist in the Training domain but **nutrition never reads them**. No per-exercise volume/RPE reaches nutrition.

**Decision needed:** target protein/nutrients by muscle worked (e.g. heavy leg week → more protein on/after leg days)?

**Recommendation:** YES but LAST — it's a Training→Nutrition cross-domain integration that could eat a week alone. Don't let it anchor the doc's difficulty. Start coarse: feed last week's per-day training *type* + volume proxy (sets completed) and let the AI bias protein timing; full per-muscle modeling is a later refinement.

**Effort:** HEAVY (cross-domain data path Training→Nutrition; new read of Exercise muscle data).

---

## Proposed sequencing (after approval)

**Tier 1 — FOUNDATIONAL (cheap, high-intent):** §1 goal weight · §2a archive retention (data) · §3 pantry-stock-in-prompt.
**Tier 2 — MEDIUM:** §4 daily-adjust/carryover replace + missed-log notif · §6 meal count/timing · §7 Settings page + Saturday notif · §2b Past Plans view · §5 per-day Whoop.
**Tier 3 — HEAVY:** §8 per-muscle protein.

Each tier = its own build phase, tested + verified before the next (never stack untested). Weekly Sonnet call stays the only paid path; everything in §4 is free local logic.

## Open questions for Nicola
- §1: also collect a **target date / weekly rate**, or just goal weight + let the safety-railed default rate apply?
- §4: confirm REPLACE MacroCarryover (vs coexist).
- §6: is per-day training **time** stored in UserSettings today, or do we add it? (Affects snack-placement effort.)
- Prune policy §2: 8 weeks of history OK, or keep more/less?
