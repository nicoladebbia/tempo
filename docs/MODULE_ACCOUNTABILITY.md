# MODULE_ACCOUNTABILITY — "Lockdown"

> **Module**: Accountability (Lockdown)
> **App**: Tempo — iOS (SwiftUI, iOS 17+)
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `Tempo/Tempo/Views/Accountability/LockdownTabView.swift` (tab container + `OverrideSelectionView`)
- `Tempo/Tempo/Views/Accountability/LockdownMainView.swift` (Today view, cards, leisure bar, unlock celebration)
- `Tempo/Tempo/Views/Accountability/FocusTimerView.swift`, `FocusHistoryView.swift`
- `Tempo/Tempo/Views/Accountability/NonNegotiableSetupView.swift`, `StreakCalendarView.swift`, `WeeklyAccountabilityView.swift`
- `Tempo/Tempo/ViewModels/AccountabilityViewModel.swift` (timer state machine, `computeFocusScore`, `processEndOfDay`, `scheduleSmartNotifications`)
- `Tempo/Tempo/Services/Engines/AccountabilityEngine.swift` (`evaluateState`, `ps5Time`, `isWeekend`, `adjustedTarget`, `applyRestDayOverride`, `updateStreak`, `streakMilestone`, `StreakMilestone`, `AccountabilityOverrideType`)
- `Tempo/Tempo/Services/Notifications/AccountabilityEscalationEngine.swift`, `AccountabilityCopyPool.swift` (built, **unwired**)
- `Tempo/Tempo/Services/LiveActivity/FocusTimerActivityManager.swift`, `TempoWidget/FocusTimerLiveActivity.swift`
- `Tempo/Tempo/Views/Shared/Components/DrillSergeantBubble.swift` (`DrillSergeantMessageGenerator`)
- `Tempo/Tempo/Models/Accountability/` — `NonNegotiable.swift`, `NonNegotiableProgress.swift`, `DailyAccountability.swift`, `StudySession.swift`, `Streak.swift`
- `Tempo/Tempo/Models/User/UserSettings.swift`, `Tempo/Tempo/Utilities/Extensions/Color+Tempo.swift`, `Utilities/Constants/DesignTokens.swift`

---

## Table of Contents

1. [Design System & Shared Components](#1-design-system--shared-components)
2. [Screen 1: Lockdown Main View (Today)](#2-screen-1-lockdown-main-view-today)
3. [Screen 2: Focus Timer View](#3-screen-2-focus-timer-view)
4. [Screen 3: Non-Negotiable Setup View](#4-screen-3-non-negotiable-setup-view)
5. [Screen 4: Streak & Consistency View](#5-screen-4-streak--consistency-view)
6. [Screen 5: Notification System](#6-screen-5-notification-system)
7. [Drill Sergeant Personality](#7-drill-sergeant-personality)
8. [Weekend Mode](#8-weekend-mode)
9. [Exam Mode](#9-exam-mode)
10. [Settings](#10-settings)
11. [Behavioral Psychology Framework](#11-behavioral-psychology-framework)
12. [Unlock Psychology & Reward System](#12-unlock-psychology--reward-system)
13. [Rest Day / Sick Day / Mental Health System](#13-rest-day--sick-day--mental-health-system)
14. [Weekly & Monthly Review System](#14-weekly--monthly-review-system)
15. [Edge Cases & Overrides (31)](#15-edge-cases--overrides)
16. [Data Model Summary](#16-data-model-summary)

---

## 1. Design System & Shared Components

The original spec used a `tempo.color.*` / `tempo.space.*` / `tempo.radius.*` dotted-token namespace with fixed hex values, point sizes, and line heights. **That namespace does not exist in code.** The real system is the shared Tempo design system:
- Colors: named asset colorsets accessed via static `Color` accessors in `Utilities/Extensions/Color+Tempo.swift`.
- Spacing / radius / opacity / animation: Swift enums in `Utilities/Constants/DesignTokens.swift` (`TempoSpacing`, `TempoRadius`, `TempoOpacity`, `TempoAnimation`).
- Typography: static `Font` accessors in `Font+Tempo.swift`, mapped to relative system text styles (Dynamic Type aware), NOT fixed 34pt/28pt/etc. sizes.
- Haptics: see canonical `docs/SOUND_AND_HAPTICS.md` and `Utilities` haptic helpers.

> **Divergence from original spec:** §1.1–§1.3 token *names, values, and access pattern* changed entirely. The hex table, the 34/28/22pt typographic scale with line heights, and the dotted spacing tokens (`tempo.space.screen.edge`, `tempo.radius.2xl`, etc.) are not enforced in code. Concrete hex lives in the asset catalog; sizes scale with Dynamic Type. Read `Color+Tempo.swift` / `DesignTokens.swift` for ground truth — this module reuses the app-wide system identically to the Dashboard module (see `MODULE_DASHBOARD.md` §1).

### 1.4 Haptic Patterns

Accountability-specific haptics (unlock celebration triple-haptic, completion, override) are fired inline from the views. `docs/SOUND_AND_HAPTICS.md` is canonical for patterns; no Accountability-local haptic token table exists in code.

### 1.5 Shared Components

`DrillSergeantBubble` (`Views/Shared/Components/DrillSergeantBubble.swift`) and `ConfettiCanvasView` (used by the unlock overlay in `LockdownMainView`) are the load-bearing shared components. `TempoFAB` exists app-wide but is not used by this module.

---

## 2. Screen 1: Lockdown Main View (Today)

**Status: IMPLEMENTED.** `Views/Accountability/LockdownMainView.swift`, hosted by `LockdownTabView`.

### 2.1 Screen Structure

ScrollView with status banner, drill-sergeant bubble, progress ring, non-negotiable cards, leisure status bar, quick action, empty/loading states, pull-to-refresh, and an unlock celebration overlay. State is driven by `AccountabilityViewModel` + `AccountabilityEngine.evaluateState`.

### 2.2 Header Section

Status banner (`statusBanner`) with time context (`statusTimeContext`) and a progress ring with a progress *prediction* enhancement not in the spec.

> **Status: NOT IMPLEMENTED — exam countdown in header.** The spec's "Exam in {exam_days} days" banner line does not exist. There is no Exam entity and `statusTimeContext` has no exam-day branch (see §9).

### 2.3 Non-Negotiable Cards

`NonNegotiableCardView` with the spec'd states (`notStarted` / `inProgress` / `completed` / `overdue` / `skipped`). Tap-to-update progress and a skip action are wired through `AccountabilityEngine.updateProgress` / `skipNonNegotiable`.

> **Status: NOT IMPLEMENTED — weekend-target sub-label.** The §8.5 "Weekend target" indicator under the progress bar is absent; weekend study-target halving happens silently in `AccountabilityEngine.adjustedTarget` with no card-level signposting.

### 2.4 Leisure Status Section

`leisureStatusBar` shows locked/unlocked leisure (PS5) state, driven by `AccountabilityEngine.checkLeisureUnlock` and `ps5Time(for:)`.

### 2.5 Quick Action Button

Implemented — context-aware primary action on the main view.

### 2.6 Time Remaining Indicator

Implemented via `statusTimeContext` / `ps5Time`. No timezone/DST-aware logic — uses `Calendar.current` naively (see §15.7/§15.8).

### 2.7 Pull to Refresh

Implemented — standard SwiftUI `.refreshable`.

### 2.8 Empty State

Implemented — empty/loading states render when no non-negotiables exist.

---

## 3. Screen 2: Focus Timer View

**Status: IMPLEMENTED (gated).** `Views/Accountability/FocusTimerView.swift`; timer state machine in `AccountabilityViewModel`.

> **Divergence from original spec:** The entire Focus Timer is gated behind `UserSettings.focusTimerEnabled` (**default `false`**, `LockdownTabView`). It is hidden until the user enables it; the spec assumed it always present.

### 3.1–3.11 Timer Core

Pomodoro timer, session indicator, subject selector, circular timer display, accumulated-time display, distraction button, primary/secondary controls, settings sheet, break screen, and completion/review overlays are all implemented. Background screen-lock and `scenePhase`-driven distraction auto-detect work; idle timer is disabled during a session; partial sessions are saved on interruption.

### 3.12 Live Activity (iOS 16+)

**IMPLEMENTED.** `Services/LiveActivity/FocusTimerActivityManager.swift` + `TempoWidget/FocusTimerLiveActivity.swift` with Dynamic Island expanded / compact / minimal regions and lock-screen presentation. Started from the timer state machine in `AccountabilityViewModel`.

### 3.13 Focus Score System

**IMPLEMENTED.** `AccountabilityViewModel.computeFocusScore` uses the exact spec weights (35% distraction + 25% pause-frequency + 20% pause-duration + 20% completion).

> **Divergence from original spec:** The *on-screen live* score in `FocusTimerView` uses a simplified `100 − 10·distractions` heuristic; the weighted formula above is applied at session save, not in the live readout.

### 3.14 Study Analytics

**PARTIAL.** `Views/Accountability/FocusHistoryView.swift` — per-subject breakdown, time-of-day heatmap, weekly chart, average focus-score stat.

> **Status: NOT IMPLEMENTED — exam-linked study planning.** The §3.14 "Study Planning (Exam-Linked)" calendar-blocking suggestions are absent — no Exam entity and no EventKit integration here.

---

## 4. Screen 3: Non-Negotiable Setup View

**Status: IMPLEMENTED.** `Views/Accountability/NonNegotiableSetupView.swift`.

### 4.1–4.8 Setup Mechanics

List, add/edit/delete, reorder, type picker, icon picker (`IconPicker`), target editor, active-days picker, capacity warning (max 7, footer), and default templates (`addDefaultTemplates`) are all implemented.

> **Divergence from original spec:** Per-day differentiated targets ("Study M-F 2h, Sa-Su 1h", spec §8.2) are **not modeled**. There is no `NonNegotiable.weekendTargetValue` field; weekend halving is hardcoded study-only logic in `AccountabilityEngine.adjustedTarget`, not configurable per non-negotiable.

---

## 5. Screen 4: Streak & Consistency View

**Status: IMPLEMENTED.** `Views/Accountability/StreakCalendarView.swift`.

### 5.1–5.7 Streak UI

Current/longest streak header, this-week dots, 365-day heatmap, freeze info (2/month), milestones list, at-risk indicator, and a share card are all implemented. Backed by `Streak.swift` + `AccountabilityEngine.streakMilestone`. Heatmap cell colors and streak rules match spec §5.2/§5.3.

> **Divergence from original spec:** Streak Recovery is **not** part of the model (see §12.5). `Streak.swift` exposes only `breakStreak()` and `useFreeze()` — no recovery/grace fields.

---

## 6. Screen 5: Notification System

**Status: NOT IMPLEMENTED (as specified).** The spec's full 6-tier escalation system (Tier 0 Morning Briefing → Tier 6 Weekly Summary, §6.1–§6.9) is built as `Services/Notifications/AccountabilityEscalationEngine.swift` (4-tier copy pool via `AccountabilityCopyPool`, persistence, resolve-on-complete) but is **instantiated nowhere** — `grep "AccountabilityEscalationEngine("` returns only the class definition. None of the tiered behavior, tier-shift, or weekly-summary scheduling runs.

> **Divergence from original spec:** The shipping notification path is an ad-hoc `AccountabilityViewModel.scheduleSmartNotifications`, not the tiered engine. It does not implement the §6.2–§6.8 tier copy, escalation timing, completion-celebration push, or weekly-summary push.

---

## 7. Drill Sergeant Personality

**Status: PARTIAL.** `Views/Shared/Components/DrillSergeantBubble.swift` — `DrillSergeantMessageGenerator.generate`.

### 7.1–7.3 Identity / Voice / Copy by Scenario

Context-aware message generation with escalating intensity by daily state (morning / tracking / approaching / final-warning / failed branches) is implemented and data-driven.

### 7.4 Intensity Adjustment

> **Status: NOT IMPLEMENTED — tone-driven copy.** `DrillSergeantMessageGenerator` does **not** branch on `UserSettings.notificationIntensity`. A shared `NotificationSettingsView` *does* read/write `notificationIntensity`, but that value is consumed only by `AccountabilityCopyPool` / the unwired `AccountabilityEscalationEngine` (see §6). The live bubble and `scheduleSmartNotifications` ignore it — the Gentle/Standard/Savage setting is settable but inert. No Savage-mode copy/disclaimer rules.

### 7.5 Does It Learn?

> **Status: NOT IMPLEMENTED.** Correctly Phase 2 / out of scope — no learning loop in code, matching spec intent.

---

## 8. Weekend Mode

**Status: PARTIAL.** `AccountabilityEngine.isWeekend` (`Calendar.isDateInWeekend`).

### 8.1–8.4 Detection / Timing / Copy

Automatic weekend detection works. `ps5Time(for:)` branches to `defaultPS5TimeWeekend` (later unlock) vs `defaultPS5TimeWeekday`. `adjustedTarget` halves study targets on weekends. Weekend morning copy variant exists in `DrillSergeantBubble`.

> **Divergence from original spec:** Weekend PS5 time and weekday/weekend windows are **hardcoded `DateComponents` constants** in `AccountabilityEngine`, not user-configurable (no Settings UI — see §10). Weekend target reduction is hardcoded study-only ÷2, not per-non-negotiable config (§8.2).

### 8.5 Reduced Targets Display

> **Status: NOT IMPLEMENTED.** No reduced-target indicator on cards (see §2.3); halving is silent.

### 8.6 Automatic Detection

Implemented (`isWeekend`).

---

## 9. Exam Mode

> **Status: NOT IMPLEMENTED (as specified).** The ~150-line spec (Exam entity, manage-exams UI, threshold/calendar auto-activation, exam banner, countdown with escalating urgency, post-exam celebration, multi-exam priority, exam-aware notifications, deactivation) does **not** exist. There is no Exam model anywhere (`find -iname "*exam*"` → no Swift files). `UserSettings` has only `examMode: Bool` + `examModeEndDate: Date?`, and `DashboardSettingsView` exposes a single bare toggle writing `examMode`.

> **Divergence from original spec — partial study boost only:** A +50% study-target path exists: `AccountabilityEngine.adjustedTarget` bumps study targets when `daysToNextExam <= 7`. But `daysToNextExam` is a `static var` set externally by `DashboardViewModel` (`resolvedExams`), **not** driven by any user-creatable Exam entity. No countdown, banner, celebration, or multi-exam logic is built on top of it.

---

## 10. Settings

> **Status: NOT IMPLEMENTED — Lockdown Settings screen.** There is no dedicated Lockdown Settings surface (§10.1/§10.2). The gear icon on `LockdownTabView` routes to the generic app settings toolbar. There is no UI for: notification tier toggles, briefing time, quiet hours, PS5 weekday/weekend times, weekend briefing time, timer defaults surfaced as Lockdown settings, Exam Mode config, rest-days-per-month, sick day, reset streak, or reset all.

> **Divergence from original spec:** A shared `Views/Shared/NotificationSettingsView.swift` exposes a `notificationIntensity` picker, and backing fields exist in `UserSettings` (`notificationIntensity`, quiet-hours, `weekendMode`, `examMode`, `focusTimerEnabled`). But most are not consumed by Lockdown logic (see §7.4), and PS5 times are hardcoded constants in `AccountabilityEngine`, not user-configurable.

---

## 11. Behavioral Psychology Framework

> **Status: N/A (rationale, not a feature).** §11.1–§11.12 are academic justifications. The concrete mechanisms they motivate are graded under §12 — most are MISSING. Notably the §11.2 "no manual force-unlock" design intent **is** honored in code (no force-unlock path exists; see §15.3).

---

## 12. Unlock Psychology & Reward System

### 12.1–12.2 The Lock & Progressive Feedback

**PARTIAL.** `LockdownMainView.unlockCelebrationOverlay` — confetti, score, streak badge, triple-haptic via `checkForUnlock`.

> **Status: NOT IMPLEMENTED — progressive lock feedback.** The §12.2 cracks/strain/breathing lock states and the §12.1 chain-breaking metaphor animation are absent; the overlay is a generic confetti celebration.

### 12.3 Guilt Mechanism for Skips

> **Status: NOT IMPLEMENTED.** `NonNegotiableProgress.wasSkipped` exists, but `checkForUnlock` fires the same full triple-haptic confetti celebration regardless of skips. No muted "via skips" celebration and no Skip Rate metric in `StreakCalendarView`.

### 12.4 Reward Escalation System

**PARTIAL.** `AccountabilityEngine.StreakMilestone` enum (3/5/7/14/21/30/50/100-day) carries titles, `xpBonus`, and `grantsBonusHour`. Milestones are *displayed* in `StreakCalendarView`.

> **Divergence from original spec:** `grantsBonusHour` is **cosmetic** — read only by `StreakCalendarView` for display text, never consumed by `ps5Time()`, so the 5-day bonus hour never actually extends leisure. `xpBonus` is not wired to Arena. The milestone trigger lives in `processEndOfDay`, which is **never called** (see §14 / cross-cutting).

### 12.5 Streak Recovery Mechanism

> **Status: NOT IMPLEMENTED.** `Streak.swift` has no `recoveryAvailableUntil` / `lastRecoveryUsedDate` / `preBreakStreak` fields and only `breakStreak()` / `useFreeze()`. No 24h grace, no restore-to-N−1, no recovery banner.

### 12.6 Implementation Intention Reinforcement

> **Status: NOT IMPLEMENTED.** No `ImplementationIntention` model and no post-review "when/where will you study" prompt in `WeeklyAccountabilityView`.

---

## 13. Rest Day / Sick Day / Mental Health System

**Status: PARTIAL.** `AccountabilityEngine.AccountabilityOverrideType` enum + `applyRestDayOverride`; `OverrideSelectionView` in `LockdownTabView`; `updateStreak` preserves streak on override.

### 13.1–13.4 Rest / Sick / Mental Health / Injury

Per-type target modification and streak preservation match spec §13.1–§13.4 logic.

> **Divergence from original spec:** Entry is via an ellipsis menu → pushed list, **not** the §13.5 "What kind of day?" bottom sheet from the header. Single-day only (no duration picker for sick/injury). No softer per-type notification copy (escalation engine unwired — see §6). `maxRestDaysPerMonth` is an unused constant — no monthly-max enforcement. Injury Mode is an override-list case, not the spec'd Settings toggle.

### 13.5 Decision Tree

> **Status: NOT IMPLEMENTED — as a bottom sheet.** Logic exists; the spec'd header-triggered decision-tree sheet does not.

---

## 14. Weekly & Monthly Review System

**Status: PARTIAL.** `Views/Accountability/WeeklyAccountabilityView.swift` — live-computed report card: overall grade, category grades, daily breakdown, study chart, streak section, best/worst, `LetterGrade`.

> **Status: NOT IMPLEMENTED — persistence, scheduling, monthly.** No `WeeklyReview`/`MonthlyReview` persisted entities. No Sunday-8PM trigger (§14.1) — manual navigation only via ellipsis menu. No Monthly Review view (§14.2), no month-over-month comparison, no personal-records tracking, no AI verdict. It is an on-demand snapshot, not the spec'd reviewed/persisted/notified system.

> **Cross-cutting:** `AccountabilityViewModel.processEndOfDay` (score finalization + overall/per-habit streak update + milestone check) is **never called** from any view or scene hook. End-of-day finalization does not happen automatically; streaks/scores update only incrementally on in-app completion.

### 14.3 Semester Review (Phase 2)

> **Status: NOT IMPLEMENTED.** Correctly out of scope per spec.

---

## 15. Edge Cases & Overrides (31)

> **Status: NOT IMPLEMENTED (systematic handling).** The 31 sub-cases (§15.1–§15.31) are largely unhandled. Spot-verified: ADHD-friendly mode (§15.28) — no `adhdFriendlyMode`/`adhdGraceDaysPerWeek` anywhere; notification-fatigue detection (§15.31) — none; re-engagement flow (§15.18) — none; vacation mode (§15.6) — only an `AccountabilityOverrideType` case, no `vacationModeEndDate` handling; timezone/DST (§15.7/§15.8) — no timezone-aware logic, `AccountabilityEngine` uses `Calendar.current` naively. A few are implicitly covered: all-complete-by-noon → unlocked (§15.2); override → streak preserved (§15.5).

### 15.3 Manual Override (Force Unlock)

> **Status: NOT IMPLEMENTED — by design.** Correctly absent: there is no force-unlock path, matching the §11.2 commitment-device intent. This is the desired behavior, not a gap.

---

## 16. Data Model Summary

**Status: PARTIAL.** `Models/Accountability/` — `NonNegotiable.swift`, `NonNegotiableProgress.swift` (≈ spec `DailyRecord`), `DailyAccountability.swift` (day container), `StudySession.swift` (≈ spec `DailyEntry`), `Streak.swift`. All have backend-sync DTOs. Plus `UserSettings.swift`.

> **Divergence from original spec — §16.1 entities/fields:**
> - **Missing entities:** `Exam`, `WeeklyReview`, `MonthlyReview`, `ImplementationIntention` (none exist in code).
> - **Missing fields:** `NonNegotiable.weekendTargetValue` / `updatedAt`; `Streak.recoveryAvailableUntil` / `lastRecoveryUsedDate` / `preBreakStreak` / `consecutivePerfectDays` / `streakFrozenUntil` / `bestRecentStreak`.
> - **Shape divergence:** per-record status is a bool + `wasSkipped`, not the spec'd 7-state enum.
>
> The schema divergence is internally consistent with the missing recovery / review / exam features above.

### 16.2 Derived Calculations

Daily score (`AccountabilityEngine.calculateDailyScore`), streak (`updateStreak`), focus score (`AccountabilityViewModel.computeFocusScore`), and adjusted targets (`adjustedTarget`) are computed live. No persisted derived snapshots (no review entities — see §14).

---

## Cross-Cutting Wiring Gaps (load-bearing, not a spec section)

1. **`AccountabilityEscalationEngine` is dead code.** Fully built (4-tier copy pool, persistence, resolve-on-complete) but instantiated nowhere. Every notification feature that depends on it — §6 tiers, §7.4 tones, §8.3 tier shifts, §12.4 reward pushes, §13 per-type copy — is inert. The shipping path is the ad-hoc `AccountabilityViewModel.scheduleSmartNotifications`.
2. **`processEndOfDay` is never called.** No scene/lifecycle hook invokes it. No automatic end-of-day score/streak finalization or milestone trigger; reward escalation (§12.4) and review persistence (§14) depend on it.
3. **No Lockdown Settings UI.** Backing fields exist in `UserSettings`; most are unreachable from any screen and/or unconsumed by Lockdown logic. PS5 times are hardcoded engine constants.
4. **Exam Mode is a single boolean.** No entity, UI, countdown, calendar-detect, or study-plan. Only an externally-set `daysToNextExam` static drives a silent +50% study boost.
