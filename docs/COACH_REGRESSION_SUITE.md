# Coach v2.1 — 8-Script Manual Regression Suite

Gate for shipping Coach v2.1. Run all 8 in iOS Simulator (Debug,
iPhone 16 Pro or newer) against a real backend OR with the `MockNutriton
CoachService`-equivalent stub data, depending on smoke vs full pass.

Each script is **PASS / FAIL / SKIPPED** and the suite passes only when
all 8 are PASS. SKIPPED is fine for paths that depend on environment
the tester can't provide (real Anthropic key, HK sleep history, etc).

## Setup

1. Fresh Simulator install OR `Reset Content and Settings` between
   scripts so seeded preferences don't bleed.
2. Set `CLAUDE_COACH_MONTHLY_BUDGET_CENTS=15000` (high) so we don't
   trip the sub-cap during the run.
3. Test user logged in with AI consent granted.
4. At least one `WeeklyMealPlan` + one `WorkoutPlan` for today.

## Script 1 — Simple action

**Goal:** verify a one-shot tool dispatch lands in SwiftData.

1. Open Coach tab → finish interview → first chat.
2. Type "move dinner to 8pm".
3. Expect: assistant bubble + tool-result card + dinner's
   `PlannedMeal.scheduledTime` mutated to "20:00".
4. Verify: open Nutrition Today; dinner row shows the new time.
5. PASS when: mutation persists, undo button appears, notification
   reschedules.

## Script 2 — Multi-step plan

**Goal:** swapDayType + dependent moveMeal + clarifying askUser.

1. Type "soccer at 7pm tonight".
2. Expect: agent calls `swapDayType` (→ `.soccer`), then either
   `insertActivity` or `askUser` ("dinner before or after the match?").
3. Tap a choice chip.
4. PASS when: day type swap visible in Training, dinner shifted,
   chip-tap message appended.

## Script 3 — Preference teaching

**Goal:** explicit pattern → high-confidence userVerified-ish row.

1. Type "fyi I never eat before 11am".
2. Expect: agent acks, `recordPreference` tool fires.
3. End the chat.
4. Open Settings → "Coach's Memory" → Likes tab → Always section.
5. PASS when: row exists with subject `meal_timing.breakfast.skipped`
   (or similar), source = Explicit, confidence ≥ 0.85.

## Script 4 — Preference correction

**Goal:** user edits memory → next conversation reflects the edit.

1. From Script 3's state, tap the row → edit text to "user eats
   breakfast around 9am instead" → Save.
2. Verify row is now source = Verified, confidence = 100%.
3. Start a new chat ("End chat" then type "what should I have for
   breakfast?").
4. PASS when: agent's response references the 9am habit, not the 11am
   one.

## Script 5 — Contradiction handling

**Goal:** `PreferenceHealthCheck` flags a contradicted high-confidence
pref → agent surfaces it via askUser on next chat open.

1. Seed: insert a `LearnedPreference` with `subject="training.match_days"`,
   `confidence=0.85`, `source=.observed`. (Do via debug menu or
   in-Simulator data injection.)
2. Seed: insert 2 `LearnedOutcome` rows with `outcome=.badSleep` and
   `decisionPrefID` linking to that pref, both `gradedAt` within last
   14 days.
3. Trigger daily-reset (background task or wait).
4. Open Coach (close previous chat first).
5. PASS when: agent's first turn surfaces the contradiction via
   `askUser` ("Quick check — you used to lift Tuesdays but…"); pref's
   `needsReview` is true, and the "Review" badge appears in Memory view.

## Script 6 — Cold-start with interview

**Goal:** fresh install → interview → first chat is personal.

1. Wipe Simulator.
2. Onboard fresh, grant AI consent.
3. Open Coach tab → interview presents.
4. Answer Q1 = "Ask first", Q2 = "Drill-sergeant", Q3 = meals + sleep,
   Q4 = "intermittent fasting", skip Q5 + Q6.
5. Verify: 4 prefs land in Memory (push_when_tired, tone.style,
   tone.silent_track, red_lines.never_suggest).
6. First chat: type "I'm tired".
7. PASS when: agent's response uses drill-sergeant tone AND asks first
   before pushing OR easing (matches Q1 setting).

## Script 7 — Self-grading

**Goal:** a graded outcome → weekly card increments correctly.

1. From Script 1's state (dinner moved to 20:00), mark the dinner
   `MealLog.loggedAt` near 20:05 the same day.
2. Trigger daily-reset (the outcome grader runs).
3. Open Coach tab.
4. PASS when: WeeklySelfGradeCard appears at top with `Suggestions
   made: 1, You took: 1, Worked well: 1, You regretted: 0`.
5. Tap card X → confirm dismissed for the rest of the ISO week.

## Script 8 — Voice + inline pill

**Goal:** voice input + cross-tab Coach access.

1. From Training tab, tap "Ask Coach" inline pill (when integration is
   wired).
2. Bottom sheet opens with "Asking from Training" subtitle.
3. Tap mic, say "swap today to pull day".
4. Verify: transcript appears live in field, send button activates.
5. Tap send (or rely on submitLabel).
6. PASS when: agent calls `swapDayType` → `.pull`, today's workout
   updates, sheet stays open, conversation thread continues (not
   forked from a fresh CoachConversation).

## Failure recovery

If any script fails, capture:
- The failing assertion (what was expected vs observed).
- Console log snapshot from `Logger.coach` if available.
- Screenshot of the surface that misbehaved.

Triage matrix:

| Failure mode | Likely cause | First-look file |
|---|---|---|
| Tool fires but mutation absent | `CoachToolDispatcherAdapter` arg-parsing | `CoachAdapters.swift` |
| Wrong day's data graded | `parseDate` timezone | `CoachAdapters.swift:parseDate` |
| Memory row inserted with wrong source | extractor confidence floor | `PreferenceExtractor.candidatePassesFloor` |
| Card doesn't appear when expected | empty-state short-circuit | `WeeklySelfGradeCard` body |
| Pill opens fresh chat | sheet wiring forks new conversation | `CoachInlinePill` host integration |

## Pass criteria

8/8 PASS → ship v2.1. Anything FAILED → fix + re-run the failing
script only (suite is independent per-script).
