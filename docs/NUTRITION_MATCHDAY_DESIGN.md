# Match-Day Meal Timing — Design Doc

> **Status: PROPOSAL — needs Nicola's approval before any code.**
> Author: Claude (Opus 4.8), 2026-06-03. Extends `NUTRITION_PERSONALIZATION_DESIGN.md` §6 (the daily training-time check-in, already DECIDED there as the mechanism). Companion to the voice-pantry work.
> Constraint: at most ONE Haiku call per match-day check-in (the fuel suggestion). Timing math is FREE local logic. No new weekly Sonnet calls.
>
> **How to read this:** each section is independently approvable — **Decision / Recommendation / Effort / Reuse-vs-build**. Annotate inline (✅ / ✏️ / ❌) and hand back.

---

## 0. The ask (Nicola, 2026-06-03)

> "You said you have soccer at 8:30 tonight. Are you arriving at 8:30 or playing at 8:30? If you arrive 8:30 you leave 8:15 (field's 15 min away), you play an hour not 90 in a 9v9. From Whoop I know you burn ~X and sweat this much, so eat at ~6 — not heavy, light but energy-giving. After, since it's only an hour, grab a burrito / rice+chicken / rice+shrimp. I don't want the basic suggestions — I want better ones."

In plain terms: **a same-day check-in that, given tonight's match details, works backward from kickoff to tell you WHEN to eat (pre and post) and WHAT — light-but-energy before, a real recovery meal after — tuned to the actual session.**

---

## 1. Scope boundary — this is INTRADAY, not the weekly plan [FOUNDATIONAL framing]

The single most important design decision: **match-day timing adjusts TODAY's meals; it is NOT a weekly-plan input.** Why this matters:

- The weekly Sonnet plan runs Sunday and doesn't know that *this* Wednesday you'll actually play at 8:30 (real life shifts — §6 already decided training time is a daily ask, not a static schedule field, precisely because of this variability).
- So match-day is a **same-day layer**: the morning/afternoon check-in captures the event, computes meal windows for *today*, and re-times (and lightly re-shapes) today's already-planned meals + adds a post-match recovery suggestion.

**Decision needed:** confirm match-day is a today-only adjustment layer, not a weekly-plan field.

**Recommendation:** YES — today-only. It re-times the day's existing PlannedMeals and appends a post-match suggestion; it does not regenerate the week. (If there's no active plan yet, it still works standalone — it just suggests pre/post times + foods without re-timing planned meals.)

---

## 2. The check-in — a real interactive view (the one genuine gap) [MEDIUM]

**Finding:** there is NO interactive daily check-in view today — only `NotificationService.scheduleMorningBriefing` (a one-way push). The §4 "did you eat yesterday?" notice is also push-only. So the check-in surface is **net-new** — but it's the same surface §4 and §6 both said they'd merge into. Build it once, serve all three.

**Design — one daily check-in sheet** (reached from a morning notification tap AND a Dashboard/Nutrition entry point):
- **Q1 (the §6 ask):** "Training today? [Soccer] [Gym] [Rest]". If Soccer → continue; else fall through to normal.
- **Q2:** "What time?" + "Is that **kickoff** or **arrival**?" (your exact distinction — arrival means subtract warm-up).
- **Q3:** "How long? [1h] [90 min] [other]" (9v9 hour vs full 90).
- **Q4 (commute, you said you'll tell it):** "How far is the field? [10] [15] [20] [30] min" — used to back-compute leave-time and frame the pre-match window.
- Optional **§4 merge:** the same sheet shows "did you eat yesterday's plan?" so it's ONE interaction, per §6's decision.

**Effort:** MEDIUM (one SwiftUI sheet + a small per-day model to hold the answers — see §5). Reuses the notification tap-routing pattern.

**Open Q:** entry point — Dashboard card, Nutrition tab banner, or just the morning-notification tap? (Lean: morning notification tap + a Nutrition "Today" banner when a soccer weekday is detected from `footballDays`.)

---

## 3. The timing math — FREE local logic, no AI [MEDIUM]

Given (kickoff or arrival time T, duration D, commute C), compute backward. All pure, unit-testable, no network:

- **Leave time** = (arrival? T : T − warmup) − C. (If "arrival 8:30", leave 8:30 − C; if "kickoff 8:30", leave 8:30 − warmup(~15) − C.)
- **Pre-match meal window:** a real meal ~**3 h before kickoff**, OR if that's impractical (late kickoff, you ate lunch), a **light energy snack ~1–1.5 h before** (banana, toast+honey-alt, rice cake — fast carbs, low fat/fiber so it doesn't sit heavy). Rule from your ask: *light but energy-giving*, never heavy close to play.
- **Post-match window:** recovery meal within ~**1 h after** final whistle (kickoff + D). Protein + carbs to replace what the session burned.
- **Chronological re-sort:** today's existing PlannedMeals get their `scheduledTime` nudged so nothing lands during the match window, and the post-match meal slots in correctly (the Today sort already orders by minutes-of-day — belt-and-suspenders from §6).

**Reuse:** `PlannedMeal.scheduledTime` (String "HH:mm") + the existing parse path; `NotificationService.scheduleMealReminder(mealName:time:)` fires "eat your pre-match meal now" at the computed Date (ready-to-use, confirmed wired).

**Effort:** MEDIUM (a pure `MatchDayTimingCalculator` + re-timing the day's meals + 2 scheduled notifications). Its own unit tests (arrival-vs-kickoff, commute, duration, late-kickoff→snack-not-meal).

---

## 4. The food suggestions — the "not basic" part [MEDIUM, 1 Haiku call]

This is where you said the basic suggestions aren't good enough. Two halves:

- **Pre-match (light + energy):** suggest from the day's plan + pantry first ("you have bananas + rice cakes → eat those at 6:15"). Fast-digesting carbs, low fat/fiber/protein-bomb. Not a guess — pantry-aware.
- **Post-match (real recovery, eat-out-aware):** here's the upgrade. Since it's only an hour and you might eat out, the suggestion is **session-tuned and specific**, not "have a balanced meal":
  - Reads the session burn (from Whoop history — see §6 reuse) → sets the recovery target (e.g. ~600–800 kcal, 40g protein).
  - Suggests **concrete options at your level**: "rice + chicken bowl (~700 kcal, 45g protein) or shrimp burrito — both hit your post-session protein; skip if you already had a big lunch." Tuned to your goal weight + the day's remaining calorie budget (so a cut day suggests leaner; a high-burn day allows the burrito).
  - **ONE Haiku call** generates 2–3 specific options given {burn, remaining budget, goal, pantry, "eating out"} — cheap, gated, same proxy as voice-pantry.

**Effort:** MEDIUM (pantry-first pre-match logic is local; post-match is one Haiku call with a tight prompt). Cost posture matches the shipped voice/Haiku envelope.

**Open Q:** post-match — always offer eat-out options, or only when you say "I'm eating out after"? (Lean: ask in the check-in — "eating out after? [yes/home]" — one tap, big quality difference.)

---

## 5. Data model — where match info lives [FOUNDATIONAL]

Match-day is today-only, so it does NOT go in the weekly `MealPlanIntake` (that's weekly). Instead a small per-day record:

**`MatchDayPlan`** (new lightweight @Model or transient struct):
- `date`, `kickoffTime: Date`, `isArrivalTime: Bool`, `durationMin: Int`, `commuteMin: Int`, `eatingOutAfter: Bool`
- computed: `leaveTime`, `preMatchMealTime`, `postMatchWindow`
- `estimatedBurnKcal: Double?` (from Whoop soccer history)

**Reuse the burn lookup:** `WhoopService.fetchWorkouts(for:)` → filter `sportID == 1` (soccer) over the last N sessions → average `caloriesBurned`/`durationMinutes` → "based on your typical soccer you burn ~X/hour." The non-gym confirm flow (`TrainingViewModel.NonGymActivityState`, `whoopSportID(for: .football)`) already does soccer detection + aggregation — **reuse its logic, don't duplicate the sport-ID handling.**

**Effort:** FOUNDATIONAL (one small model + a burn-history helper that wraps existing Whoop fetch).

---

## 6. Reuse-vs-build summary

**REUSE (≈60%, confirmed wired):**
- `WhoopService.fetchWorkouts(for:)` → soccer burn history (sportID 1).
- `TrainingViewModel` non-gym confirm logic → soccer detection + burn aggregation pattern.
- `NotificationService.scheduleMealReminder(mealName:time:)` → fire pre/post-match reminders at computed Dates.
- `PlannedMeal.scheduledTime` + Today sort → re-time the day's meals.
- The Haiku proxy (`nutritionProxyText`, `caller` tag) → post-match food suggestion.

**BUILD (the real new work):**
- The interactive daily check-in sheet (§2) — net-new, but the shared §4/§6 surface.
- `MatchDayTimingCalculator` (§3) — pure, tested.
- `MatchDayPlan` model + burn-history helper (§5).
- Post-match suggestion prompt (§4) — one Haiku call.

**GAPS confirmed:** no interactive check-in view exists; no per-day training TIME stored (only weekday+type bitmask). Both are addressed above without touching the weekly plan.

---

## 7. Proposed sequencing (after approval + after a weekly plan is validated on-device)

**Prereq:** generate + sanity-check one real weekly plan on-device (the layer below this must work first).

**Tier A — the spine:** §2 check-in sheet + §3 timing calculator + §5 model. Ships "tell it your match → it tells you when to eat + reminds you." Pure-logic, testable.

**Tier B — the intelligence:** §4 pantry-first pre-match + Haiku post-match suggestions (the "not basic" upgrade). + §6 Whoop burn personalization.

**Tier C — polish:** merge the §4 "did you eat yesterday" + §6 check-in into one daily interaction; surface match-day in the Dashboard.

Each tier tested before the next. Match-day stays a same-day layer; the weekly Sonnet call is untouched.

---

## Open questions for Nicola
- §2: check-in entry point — morning-notification tap, Nutrition "Today" banner, Dashboard card, or all three? (Lean: notification + Today banner.)
- §4: post-match — always offer eat-out options, or gate on an "eating out after?" tap in the check-in? (Lean: one-tap ask.)
- §3: default warm-up buffer for "arrival" vs "kickoff" — 15 min OK, or ask?
- §1: when there's NO active weekly plan, should match-day still run standalone (suggest pre/post times + foods without re-timing planned meals)? (Lean: yes.)
- Scope: is the burrito/rice-bowl post-match suggestion the Tier B acceptance test?
```
**Verdict:** STRONG — this is the feature that makes Tempo a life-OS, not a tracker; ~60% reuses wired code; the new work is well-bounded and mostly pure-logic.
**Confidence:** high
**If I'm wrong:** if the daily check-in sheet proves to be heavy UI work (multi-step, state-managed) it could balloon past MEDIUM — Tier A's sheet is the cost risk to watch.
**What I'm NOT saying:** not claiming the weekly plan underneath is validated — that's the stated prereq before building this.
```
