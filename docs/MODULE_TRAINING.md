# MODULE_TRAINING — "RepForge" Training Module

> **Module**: Training (RepForge)
> **App**: Tempo — iOS (SwiftUI, iOS 17+)
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `Tempo/Tempo/Views/Training/TrainingTabView.swift`, `TodayWorkoutView.swift`, `ActiveWorkoutView.swift`, `RestTimerView.swift`, `WorkoutSummaryView.swift`, `WeekPlanView.swift`, `ExerciseLibraryView.swift`, `ExerciseDetailView.swift`, `ProgressChartsView.swift`, `WorkoutHistoryView.swift`, `SetFeedbackSheet.swift`, `WorkoutEventEditView.swift`
- `Tempo/Tempo/ViewModels/TrainingViewModel.swift`
- `Tempo/Tempo/Services/Engines/TrainingEngine.swift` (+ `TrainingEngineProtocol.swift`, `MockTrainingEngine.swift`), `Services/Engines/ExerciseLibraryLoader.swift`
- `Tempo/Tempo/Models/Training/` (`Exercise.swift`, `PlannedExercise.swift`, `PlannedSet.swift`, `WorkoutPlan.swift`, `RunSession.swift`, `SetFeedback.swift`)
- `Tempo/Tempo/Resources/Exercises.json`
- `Tempo/Tempo/Views/Shared/Components/NumberStepperView.swift`
- `Tempo/Tempo/Utilities/Constants/DesignTokens.swift`, `Utilities/Extensions/Color+Tempo.swift`, `Font+Tempo.swift`
- `Tempo/TempoWatch/Views/WorkoutView.swift`

---

## Table of Contents

1. [Design System & Foundations](#1-design-system--foundations)
2. [Today's Workout View](#2-todays-workout-view)
3. [Active Workout View](#3-active-workout-view)
4. [Weight Input System](#4-weight-input-system)
5. [Plate Calculator](#5-plate-calculator)
6. [Superset, Circuit & Drop Set Support](#6-superset-circuit--drop-set-support)
7. [Rest Timer System](#7-rest-timer-system)
8. [Workout Summary (Post-Workout)](#8-workout-summary-post-workout)
9. [Week Plan View](#9-week-plan-view)
10. [Exercise Library](#10-exercise-library)
11. [Progress Charts](#11-progress-charts)
12. [Personal Records System](#12-personal-records-system)
13. [Running & Cardio Module](#13-running--cardio-module)
14. [Training Settings](#14-training-settings)
15. [Workout Generation Algorithm](#15-workout-generation-algorithm)
16. [Progressive Overload Logic](#16-progressive-overload-logic)
17. [Recovery-Based Adjustment Algorithm](#17-recovery-based-adjustment-algorithm)
18. [Football Integration](#18-football-integration)
19. [Deload Week Specification](#19-deload-week-specification)
20. [Import / Export System](#20-import--export-system)
21. [Apple Watch Companion](#21-apple-watch-companion)
22. [Appendices](#22-appendices)

---

## 1. Design System & Foundations

The Training module consumes the **same shared design system** as the rest of the app — there is no Training-specific token set.
- Colors: named asset catalog colorsets (`Tempo/Tempo/Assets.xcassets/Colors/*.colorset`), accessed via static `Color` accessors in `Color+Tempo.swift` (`Color.tempoSignal`, `Color.tempoRecoveryGreen/Yellow/Red`, `Color.tempoPRGold`, `Color.tempoTextPrimary/Secondary`, etc.).
- Spacing / radius / opacity / animation / elevation: Swift enums in `DesignTokens.swift` (`TempoSpacing`, `TempoRadius`, `TempoOpacity`, `TempoAnimation`, `TempoShadow`/`TempoElevation`).
- Typography: static `Font` accessors in `Font+Tempo.swift`, mapped to system text styles (Dynamic Type aware), NOT fixed point sizes.

> **Divergence from original spec:** The original §1.1–1.8 specified a Training-local palette, a fixed-point typography scale, a per-device component-dimension matrix, an explicit touch-target table, a full haptic-feedback map, and a per-screen animation spec. **None of those are Training-specific in code** — Training reuses the global tokens. The dotted-token namespace, fixed pt sizes, device dimension tables, and the formal haptic map do not exist. See `MODULE_DASHBOARD.md` §1 for the canonical token tables (single source of truth).

> **Status: NOT IMPLEMENTED — §1.6 haptic-feedback map / §1.8 accessibility spec.** Haptics are called ad hoc at a few interaction points; there is no centralized RepForge haptic map. There are no composed accessibility labels/values/hints across Training views beyond stock SwiftUI controls and the toolbar `.accessibilityLabel`/`.accessibilityHint` on `TrainingTabView`'s "More" menu.

---

## 2. Today's Workout View

### 2.1 Overview — IMPLEMENTED

`TrainingTabView` is the module entry point: a `NavigationStack` hosting `TodayWorkoutView(viewModel:)`, with a top-leading toolbar **Menu** ("line.3.horizontal") exposing Week Plan, Exercise Library, Progress, and History as `NavigationLink`s, plus the shared settings toolbar. Active Workout and Summary are presented as `fullScreenCover`s from `TrainingTabView`.

> **Divergence from original spec:** Navigation to Week Plan / Library / Progress / History is a single toolbar **Menu**, not the spec's nav-bar buttons / segmented sub-navigation.

### 2.2–2.7 Screen Structure, Recovery Badge, Meta Bar, Exercise Cards — IMPLEMENTED

`TodayWorkoutView` is a `ScrollView` with: header (date + workout title), **recovery badge bar** (green/yellow/red zone color + adjustment label, with transparency text explaining the recovery-driven volume/intensity change), **workout meta bar** (exercise count / sets / est. duration), and the **exercise list**. Exercises are populated by `TrainingViewModel.populateExercises`. Each exercise card shows the prescription plus a last-3-session performance summary and a trend indicator ("Recent" trend). Recovery badge logic is backed by `TrainingEngine.classifyRecoveryZone` / `adjustForRecovery`.

### 2.8 Superset / Circuit / Drop Set Grouping — DIVERGED

`TodayWorkoutView` renders a `supersetCard` for consecutive exercises sharing the same `PlannedExercise.supersetGroup: Int?`.

> **Divergence from original spec:** Only **2-exercise supersets** render. There is **no circuit visual and no drop-set badge/prescription** — `PlannedExercise`/`PlannedSet` have no circuit or drop-set model fields. See §6.

### 2.9 "Start Workout" Button — IMPLEMENTED

`startWorkoutButton` launches the Active Workout `fullScreenCover` via the bound `showActiveWorkout`.

### 2.10 Rest Day View — PARTIAL

A rest-day state renders in `TodayWorkoutView`.

> **Divergence from original spec:** The "Start a Mobility Flow" affordance shows a **"coming soon" alert** — mobility flows are not implemented (see §10 mobility count = 0).

### 2.11 Football Day View / 2.12 Day-Before-Football (T-1) — PARTIAL

The engine produces `.football` / `.mobility` plan types (`TrainingEngine`), and `WeekPlanView` renders "Match day" cards.

> **Divergence from original spec:** There is **no dedicated rich Football Day screen** (pre-match prep checklist, T-1 specific UI). Only a generic plan-type label/badge. Football scheduling logic itself is real — see §18.

### 2.13 Swap Exercise Flow

> **Status: NOT IMPLEMENTED.** No `swapExercise` in `TrainingViewModel` and no swap UI in `TodayWorkoutView` (only a static "Swapped to Mobility" string label exists on the recovery badge).

### 2.14 Add Exercise Flow

> **Status: NOT IMPLEMENTED.** No `addExercise` in `TrainingViewModel` (only `addSet`); no add-exercise UI.

### 2.15 Drag-to-Reorder — PARTIAL

`TrainingViewModel.moveExercises(from:to:)` exists.

> **Divergence from original spec:** The reorder logic is present but **not wired to a drag UI** — `TodayWorkoutView` renders a `ForEach`, not an `.onMove` `List`. There is no drag handle.

### 2.16 Pull-to-Refresh

> **Status: NOT IMPLEMENTED.** `TodayWorkoutView`'s `ScrollView` has no `.refreshable` modifier.

### 2.17 Edge Cases — PARTIAL

Rest-day, generated-plan, and recovery-adjusted states render. The spec's full edge-case matrix (no plan / generation failure / partial data variants) is not exhaustively built; the view falls back to the generated plan or rest-day state.

---

## 3. Active Workout View

### 3.1–3.5 Set Logging — IMPLEMENTED (core interaction)

`ActiveWorkoutView` drives exercise-by-exercise set logging: per-set weight, reps, and a Finish/DONE action. `TrainingViewModel.logSet` persists each set to SwiftData. This is the real core loop.

### 3.6 Completed Sets History — PARTIAL

Per-set completion is shown as **progress dots** with +/- set buttons.

> **Divergence from original spec:** There is **no per-set history table** (weight × reps list of completed sets) on the active screen as specced — only the dot strip.

### 3.7 Rest Timer — IMPLEMENTED

`ActiveWorkoutView` routes to `RestTimerView` after a set. See §7.

### 3.8 Exercise Navigation — IMPLEMENTED

`ActiveWorkoutView` exercise transitions are driven by a state machine in `TrainingViewModel`.

### 3.9 Live Activity / Lock Screen

> **Status: NOT IMPLEMENTED.** `Services/LiveActivity/` contains only Focus-timer activity attributes/manager. There is **no workout Live Activity / `WorkoutAttributes`** anywhere.

### 3.10 Workout Duration Timer — IMPLEMENTED

`ActiveWorkoutView` shows a running timer bar; `TrainingViewModel.startElapsedTimer` backs it.

### 3.11 Auto-Pause Detection

> **Status: NOT IMPLEMENTED.** No auto-pause / `CoreMotion` references in Training views or `TrainingViewModel`.

### 3.12 Warm-Up Sets — IMPLEMENTED

`TrainingViewModel` auto-generates 50% / 75% warm-up sets for compound lifts; `ActiveWorkoutView` distinguishes warm-up dots visually.

### 3.13 End Workout Flow / 3.14 Crash Recovery — IMPLEMENTED

`ActiveWorkoutView` has an end-workout flow and a crash-recovery content path; `TrainingViewModel.resumeFromCrash` restores an in-progress session.

### 3.15 Set Feedback Sheet — IMPLEMENTED (not in original spec)

After a working set is logged ("Finish Set"), `SetFeedbackSheet` is presented: a bottom sheet capturing **RPE** (dial), **breathing difficulty**, **form quality**, and an optional note. It persists a `SetFeedback` model (`Models/Training/SetFeedback.swift`) linked to the `PlannedSet`. Triggered by Finish Set only (not rest-timer expiry); not re-prompted if dismissed; in-progress taps live in `@State` until Save (no draft model — accepted product gap).

> **Note:** This feature is **as-built but absent from the original spec.** It is the real RPE-capture mechanism; the spec assumed RPE was entered inline on the set-logging row (it is not).

---

## 4. Weight Input System

### 4.1 Method A — Smart Stepper — PARTIAL

`Views/Shared/Components/NumberStepperView.swift` provides a stepper with a long-press accelerate gesture, used by `ActiveWorkoutView` for weight/reps entry.

> **Divergence from original spec:** The step is a **fixed 2.5** passed by `ActiveWorkoutView` — it is **not context-aware per equipment** (no 2 kg dumbbell / 4 kg kettlebell increments). There is no separate outer quick-add (−2.5 / +2.5) row.

### 4.2 Method B — Scroll Wheel Picker

> **Status: NOT IMPLEMENTED.** No picker / scroll-wheel weight entry exists.

### 4.3 Method C — Direct Keyboard Entry

> **Status: NOT IMPLEMENTED.** The weight display is not tappable; there is no custom numeric keypad component.

### 4.4 Input Method Selection

> **Status: NOT IMPLEMENTED.** Only Method A exists, so there is no method-selection setting.

### 4.5 Unit Toggle (kg/lbs)

> **Status: NOT IMPLEMENTED.** `ActiveWorkoutView` hardcodes the unit `"kg"`; there is no session unit toggle. (A global weight-unit setting exists on `UserSettings` and is read by some history/volume views, but the active set-logging UI is kg-only.)

### 4.6 Bodyweight Exercise Handling

> **Status: NOT IMPLEMENTED.** The `Exercise` model has no `isBodyweight` flag; `ActiveWorkoutView` always shows a kg weight stepper. No BW / weighted / assisted modes.

### 4.7 Pre-Fill Intelligence — PARTIAL

`TrainingViewModel.stickyWeight` + `ActiveWorkoutView`'s set-input loader pre-fill the previous set's weight (sticky within session) and the target reps.

> **Divergence from original spec:** Only **sticky-within-session + target-reps** pre-fill is implemented. No "returning after a break" adjustment, no recovery −5% pre-fill at the input level, and no similar-exercise estimate for first-time exercises.

---

## 5. Plate Calculator

> **Status: NOT IMPLEMENTED.** There is no plate calculator anywhere in Training views or `TrainingViewModel` — no algorithm, no one-line hint, no plate diagram, no smart suggestions. (`TrainingEngine` has an unrelated `case .barbell: 40.0` default-weight constant only.) The entire original §5.1–5.7 is absent.

---

## 6. Superset, Circuit & Drop Set Support

### 6.1–6.2 Supersets (2-exercise pairs) — PARTIAL

`PlannedExercise.supersetGroup: Int?` + `TrainingViewModel.assignSupersetGroups` group exercises; `TodayWorkoutView`'s `supersetCard` renders consecutive same-group exercises together.

> **Divergence from original spec:** Visual grouping renders, but there is **no alternating A1/B1 active-workout superset flow**, no "no rest" banner logic, and no create/break-superset UI.

### 6.3 Circuits (3+ exercise groups)

> **Status: NOT IMPLEMENTED.** No circuit model field or circuit-specific flow; `supersetGroup` only handles consecutive same-int pairs.

### 6.4 Drop Sets

> **Status: NOT IMPLEMENTED.** No drop-set field on `PlannedExercise`/`PlannedSet`, no drop-set config or active flow.

### 6.5 Creating / Breaking Groups

> **Status: NOT IMPLEMENTED.** No "Convert to Superset / Drop Set / Break" menus or drag-to-group UI anywhere in Training views.

---

## 7. Rest Timer System

### 7.1–7.5, 7.8 — IMPLEMENTED

`RestTimerView` renders a rest-timer circle with +15s and skip controls; `TrainingViewModel.restDuration` supplies equipment/exercise-based defaults; `scheduleRestTimerNotification` fires a local notification so the timer survives backgrounding.

### 7.6 Rest Timer in Superset/Circuit Mode / 7.7 Drop Set Mode

> **Status: NOT IMPLEMENTED.** Superset-mode and drop-set-mode rest behavior are not implemented because those groupings (§6.3/§6.4) do not exist in the model.

---

## 8. Workout Summary (Post-Workout)

### 8.1, 8.3–8.5, 8.9 — IMPLEMENTED

`WorkoutSummaryView` renders a header, a stats grid, a Personal Records badge section (driven by detected PRs), a per-exercise breakdown, and a save action that persists the completed `WorkoutPlan`.

### 8.2 Completion Ring — DIVERGED

> **Divergence from original spec:** There is **no animated completion ring** — the summary header uses a **static checkmark icon**, not the spec's count-up progress ring.

### 8.6 Tomorrow's Outlook / 8.7 Add Notes / 8.8 Share Card

> **Status: NOT IMPLEMENTED.** No tomorrow's-outlook section, no add-notes field, and no share-card / `ImageRenderer`/`ShareLink` export on the summary.

---

## 9. Week Plan View

### 9.1–9.4 — IMPLEMENTED

`WeekPlanView` renders a 7-day grid with daily detail cards, AI-generated plan content, and a deload banner. Plan generation is real: `TrainingEngine.generateWeekPlan` produces the week's split-aware, recovery- and football-constrained plan.

### 9.5 Regenerate Plan / 9.6 Manual Override / 9.7 Week Navigation

> **Status: NOT IMPLEMENTED.** `WeekPlanView` has no regenerate button, no per-day override editor, and no previous/next-week navigation — `loadWeekPlan` loads the current week only.

### 9.8 Edge Cases — PARTIAL

Generated-plan, deload-week, and football-day states render. The full spec edge-case matrix (generation failure / empty-week fallbacks) is not exhaustively built.

---

## 10. Exercise Library

### 10.1–10.2 Screen, Search & Filters — IMPLEMENTED

`ExerciseLibraryView` provides search, muscle/equipment filter chips, and a grouped list. `ExerciseLibraryLoader` loads the seed JSON from the bundle.

### 10.3 Exercise Data Schema — IMPLEMENTED

`Exercise` (`Models/Training/Exercise.swift`). Seed JSON fields: `name`, `muscleGroup`, `secondaryMuscles`, `equipment`, `movementPattern`, `isCompound`, `defaultSets`, `defaultReps`, `restSeconds`, `instructions`, `cues`. The model also has `isCustom` and a `demoAsset` string.

### 10.4 Complete Exercise Database — DIVERGED (real count differs)

`Resources/Exercises.json` contains **147 exercises** (verified by JSON parse), broken down as:

| Muscle group | Count |
|--------------|-------|
| back | 22 |
| quads | 23 |
| shoulders | 20 |
| core | 19 |
| chest | 16 |
| biceps | 10 |
| triceps | 10 |
| hamstrings | 8 |
| glutes | 7 |
| calves | 6 |
| forearms | 4 |
| cardio | 2 |
| **total** | **147** |

> **Divergence from original spec:** The doc title claimed "150+ exercises" and the body enumerated **~325 named exercises across 13 categories**. Reality: **147 total.** Strength categories roughly track the spec, but the spec's separate **CARDIO (10 listed) → only 2 seeded**, **MOBILITY (15 listed) → 0 seeded**, and **FOOTBALL-SPECIFIC (10 listed) → 0 seeded**. There is no "mobility" or "football-specific" muscle group in the data at all. The exhaustive named-exercise tables in the original §10.4 are aspirational and do not reflect the seed.

### 10.5 Exercise Detail View — PARTIAL

`ExerciseDetailView` is real and substantial: demo area, info pills, a stats card, an estimated-1RM Swift Charts chart, instructions, cues, and rest-time customization.

> **Divergence from original spec:** The "demo area" uses a static `demoAsset` string, **not video/animation**. The seed JSON sets no `demoAsset` values, so the demo area is effectively empty.

### 10.6 Custom Exercise Creation

> **Status: NOT IMPLEMENTED.** `Exercise` has an `isCustom` flag but there is **no creation UI** anywhere in Training views.

---

## 11. Progress Charts

### 11.1–11.4 — IMPLEMENTED

`ProgressChartsView` renders real Swift Charts: volume bars, muscle-group distribution from real workout history, and a push/pull balance analysis (Overview / Exercises / Muscles content). The per-exercise progression chart is in `ExerciseDetailView`. All driven by real `@Query`/SwiftData history.

---

## 12. Personal Records System

### 12.1–12.3 PR Detection — IMPLEMENTED

`TrainingEngine.detectPersonalRecord` computes a Brzycki estimated-1RM and detects all-time and rep-max PRs. Detected PRs surface in `WorkoutSummaryView` and in the `ActiveWorkoutView` cooldown.

### 12.4 PR Notification / 12.5 PR History Screen — PARTIAL

> **Divergence from original spec:** PR celebration is an **in-summary badge only** — there is no dedicated PR push notification and no standalone PR history / progression screen.

### 12.6 PR Achievements — PARTIAL

PR → Arena achievement wiring is referenced but not verified within the Training module (lives in the Arena module).

---

## 13. Running & Cardio Module

> **Status: NOT IMPLEMENTED.** A `RunSession` model exists (`Models/Training/RunSession.swift`) but is referenced **only** by the SwiftData schema and `RecoveryAIInsightService` — it has **zero UI**. There is no run-type picker, no pace-zone config, no interval-programming builder, no active run view, no VO2max estimation, no splits, and no run summary anywhere in Training views or `TrainingViewModel`. The entire original §13.1–13.8 is absent; the only artifact is the persisted model.

---

## 14. Training Settings

> **Status: NOT IMPLEMENTED.** `TrainingTabView` has a code comment referencing a `TrainingSettingsView`, but **no such view exists** (`Views/Settings/` contains only `PrivacyInfoView.swift`). The underlying settings (`footballDays`, split, deload frequency) exist on `UserSettings` and are read by `TrainingViewModel` loaders, but there is **no Training settings UI to edit them**.

---

## 15. Workout Generation Algorithm

### 15.1–15.6 — IMPLEMENTED

`TrainingEngine.generateWorkout` + `generateWeekPlan` implement a real generation algorithm: split sequencing, recovery-zone constraints, T-0/T-1/T+1 football logic, and priority-ordered exercise selection (`TrainingViewModel.selectExercises` / `exercisePriorityOrder` / `populateExercises`, including set counts, warm-ups, and superset assignment).

> **Divergence from original spec:** Functionally complete but **simpler than the full §15.4 pseudocode** — e.g. split rotation is keyed on day-of-year rather than a full volume-landmark distribution. The §15.5 volume-distribution and §15.6 evidence-based rest tables are encoded as engine constants, not the literal spec tables.

---

## 16. Progressive Overload Logic

### 16.1–16.2, 16.6 — IMPLEMENTED

`TrainingEngine.calculateProgressiveOverload` implements the 2-of-3 progression rule (counts successful sessions, +increment on 2/3 success, −increment on 3 consecutive fails) with equipment-specific increments. Per-exercise progression is displayed as the "Recent" trend on `TodayWorkoutView` exercise cards.

### 16.3 RPE-Informed Adjustments / 16.4 Recovery-Adjusted Progression / 16.5 Missed-Week Handling — PARTIAL

> **Divergence from original spec:** RPE-informed adjustment and missed-week / returning-after-break handling are **not implemented**. (Recovery adjustment exists at the plan level — see §17 — not as a progression-rule input.) Note RPE *is* now captured post-set via `SetFeedbackSheet` (§3.15) but is not yet fed back into the overload algorithm.

---

## 17. Recovery-Based Adjustment Algorithm

### 17.1–17.3 — IMPLEMENTED

`TrainingEngine.classifyRecoveryZone` (Green ≥67 / Yellow ≥34 / Red below) and `adjustForRecovery` apply volume/intensity adjustments to the generated plan. Transparency text explaining the adjustment renders in the `TodayWorkoutView` recovery badge.

### 17.4 Historical Learning

> **Status: NOT IMPLEMENTED.** No adaptive personalization of recovery thresholds over time.

---

## 18. Football Integration

### 18.1–18.3 — IMPLEMENTED

`TrainingEngine` implements T-0 (lock to match), T-1 (no legs — `isFootballTMinus1` + `swapLegsForUpper` + `preferredUpperType`), T+1 (upper-only), and two-matches-per-week scheduling, applied in `generateWorkout`/`generateWeekPlan`.

### 18.4 Calendar Integration — PARTIAL

`CalendarServiceProtocol.detectFootballDays` exists and `TrainingEngine` has a calendar-aware `generateWeekPlan` overload.

> **Divergence from original spec:** The calendar-aware overload is **not called** by `TrainingViewModel` — `loadWeekPlan`/`loadToday` pass only static `UserSettings.footballDays`. Calendar-detected football days are **not merged** into plan generation.

---

## 19. Deload Week Specification

### 19.1–19.2, 19.4 — PARTIAL

`TrainingEngine.isDeloadWeek` detects every-Nth-week deloads; a `deloadWeightMultiplier` (0.6) exists; deload banners render in `TodayWorkoutView` and `WeekPlanView`.

### 19.3 Three Deload Options / 19.5 Post-Deload

> **Status: NOT IMPLEMENTED.** The three deload options (volume cut / intensity cut / full rest-week choice) and post-deload handling are not implemented — only a single fixed strategy. (Whether `deloadWeightMultiplier` is actually applied to populated set weights is not confirmed in `populateExercises`; treat application as unverified.)

---

## 20. Import / Export System

> **Status: NOT IMPLEMENTED.** No export format, no Strong/Hevy import, no generic CSV import, no conflict resolution, no validation — none of `WorkoutExport`/`importStrong`/`importHevy`/CSV exists anywhere in the app target. The entire original §20.1–20.6 is absent.

---

## 21. Apple Watch Companion

### 21.1–21.3 — PARTIAL

`TempoWatch/Views/WorkoutView.swift` provides workout / active / rest views, a complication, and `WatchConnectivityService.sendAction` for phone messaging.

> **Divergence from original spec — stub data:** The watch active-workout uses **hardcoded dummy data**. The Start button sets `exerciseName = "Bench Press"`, `lastWeight = 80`, `lastReps = 8`, `totalSets = 4` as literals; the "ADJUST" button is an empty placeholder. The watch is **not driven by real plan data from the phone**.

### 21.4–21.6 Watch Workout / Active / Rest Views — PARTIAL

Views exist (per above) but render the stub data, not the real plan.

### 21.7 Watch Superset Flow / 21.8 Watch Workout Summary

> **Status: NOT IMPLEMENTED.** No watch superset flow and no watch workout summary.

### 21.9 Watch-Phone Sync / 21.10 Battery

> **Divergence from original spec:** Only a fire-and-forget `WatchConnectivityService.sendAction(.startWorkout)` exists. There is no real bidirectional set-sync and no battery-management strategy.

---

## 22. Appendices

### Appendix A: Data Model (Key Entities)

Real SwiftData entities in `Models/Training/`: `WorkoutPlan`, `PlannedExercise` (with `supersetGroup: Int?`, no circuit/drop-set fields), `PlannedSet`, `Exercise` (with `isCustom`, `demoAsset`), `RunSession` (persisted, UI-less — see §13), and `SetFeedback` (RPE/breath/form — see §3.15). All are registered in `Models/Schema/TempoSchemaV1.swift`.

> **Divergence from original spec:** The original Appendix A entity set assumed circuit/drop-set/run-tracking models with full field sets. The actual models are leaner (`supersetGroup` int only; `RunSession` exists but unused by UI). `SetFeedback` is a real entity the original spec did not anticipate.

### Appendix B: Navigation Map

Real map: `TrainingTabView` → `TodayWorkoutView`; toolbar Menu → `WeekPlanView` / `ExerciseLibraryView` / `ProgressChartsView` / `WorkoutHistoryView`; `fullScreenCover` → `ActiveWorkoutView` → `RestTimerView` (push) and `SetFeedbackSheet` (sheet) → `WorkoutSummaryView` (cover). `ExerciseLibraryView` → `ExerciseDetailView`. `WorkoutEventEditView` wraps `EKEventEditViewController` for calendar event editing.

> **Divergence from original spec:** No swap/add-exercise routes, no plate-calculator route, no running routes, no training-settings route, no week-navigation routes (all reflect the NOT-IMPLEMENTED sections above).

### Appendix C: Gesture Summary

Implemented gestures: stepper long-press accelerate (`NumberStepperView`), stock SwiftUI scroll/tap/navigation. The spec's drag-to-reorder, drag-to-group, swipe actions, and per-set swipe gestures are **not implemented** (see §2.15, §6.5).

### Appendix D: Notification Schedule

Implemented: the background **rest-timer local notification** (`TrainingViewModel.scheduleRestTimerNotification`).

> **Status: NOT IMPLEMENTED — the rest of the schedule.** No workout-reminder, PR, deload-week, or missed-workout notifications (consistent with §3.9, §12.4, §19).

---

*End of as-built description. Reconciled to code on 2026-05-19. Where this doc and the source disagree, the source is authoritative — fix the doc, not the code, unless the divergence is itself the bug.*
