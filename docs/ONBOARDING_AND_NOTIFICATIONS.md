# ONBOARDING_AND_NOTIFICATIONS — Onboarding Flow & Notification System

> **Module**: Onboarding + Notifications
> **App**: Tempo — iOS (SwiftUI, iOS 17+) + Vapor backend
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS + backend developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):

Onboarding:
- `Tempo/Tempo/ViewModels/OnboardingViewModel.swift` — `enum OnboardingStep`, `advance()`, `goBack()`, persistence, `buildDailyPlanProfile()`
- `Tempo/Tempo/Views/Onboarding/OnboardingContainerView.swift` — `stepContent` switch, `progressBar`, splash auto-advance
- `Tempo/Tempo/Views/Onboarding/*View.swift` — per-step screens (`OnboardingSplashView`, `ValueDemoView`, `GoalSetupView`, `HealthKitPermissionView`, `OnboardingAuthView`, `ProfileSetupView`, `IdentitySetupView`, `TrainingSetupView`, `AcademicSetupView`, `DailyPlanProfileViews`, `WhoopConnectView`, `NotificationSetupView`, `TermsAcceptanceView`, `AIConsentView`, `OnboardingCompleteView`, `ArenaIntroView` *(orphaned)*)

Notifications:
- `Tempo/Tempo/Services/Notifications/NotificationService.swift` — scheduling, categories, 64-slot eviction, daily budget, badge, sound
- `Tempo/Tempo/Services/Notifications/AccountabilityEscalationEngine.swift` — escalation state machine
- `Tempo/Tempo/Services/Notifications/AccountabilityCopyPool.swift` — `CopyTier`, `CopyIntensity`, `pick()`, `interpolate()`
- `Tempo/Tempo/Resources/AccountabilityCopy.json` — the only copy bank that exists
- `Tempo/Tempo/Views/Settings/NotificationSettingsView.swift` — settings UI
- `Tempo/Tempo/Models/UserSettings.swift` — settings persistence
- `tempo-backend/Sources/App/Services/APNsService.swift` — P8 token-based APNs (ADR-019)
- `tempo-backend/Sources/App/Jobs/{NotificationScheduleJob,WeeklySummaryJob,DrillSergeantBatchJob,LeaderboardRefreshJob,ProcessedNotificationsCleanupJob}.swift`
- `tempo-backend/Sources/App/configure.swift` — job scheduling

---

## Table of Contents

- [Part 1: Onboarding Flow](#part-1-onboarding-flow)
  - [1. Pre-Onboarding](#1-pre-onboarding)
  - [2. Step-by-Step Onboarding](#2-step-by-step-onboarding)
  - [3. Onboarding UX Details](#3-onboarding-ux-details)
  - [4. Onboarding Funnel Optimization](#4-onboarding-funnel-optimization)
  - [5. Re-Onboarding](#5-re-onboarding)
- [Part 2: Notification System](#part-2-notification-system)
  - [6. Notification Architecture](#6-notification-architecture)
  - [7. Push Notification Infrastructure](#7-push-notification-infrastructure)
  - [8. Notification Channels — Copy Bank](#8-notification-channels--copy-bank)
  - [9. Notification Timing Engine](#9-notification-timing-engine)
  - [10. Notification Settings UI](#10-notification-settings-ui)
  - [11. Notification Smart Logic](#11-notification-smart-logic)
  - [12. Re-Engagement Sequences](#12-re-engagement-sequences)
  - [13. First Week Experience](#13-first-week-experience)
  - [14. Localization](#14-localization)
  - [15. Legal & Compliance](#15-legal--compliance)

---

# PART 1: ONBOARDING FLOW

## 1. Pre-Onboarding

### 1.1 App Store Listing

> **Status: NOT IMPLEMENTED (in app code).** App Store listing copy, screenshots, and metadata are marketing artifacts (an `appstore/` directory exists in the repo) and are not part of the app target. Not auditable as implementation.

### 1.2 First Launch: Splash Screen

`OnboardingSplashView` renders `TempoLogoView(size: 80, showGlow: true)` plus a `Text("TEMPO")` wordmark. `OnboardingContainerView` auto-advances off `.splash` after `Task.sleep(for: .seconds(1.8))`. The progress bar is hidden during `.splash`, `.valueDemo`, and `.complete`.

> **Divergence from original spec:** The spec called for a 4-ring convergence animation. The code is a **wordmark + logo loader**, not a ring animation (commit `4292b6ee` explicitly replaced the prior skeleton with the wordmark loader). No ring geometry, no convergence choreography.

---

## 2. Step-by-Step Onboarding

> **Divergence from original spec — THE ENTIRE FLOW MODEL.** The spec described a **13-step ordered flow** (Welcome → Sign In → Profile → Training → Academics → Goals → Whoop → NutriTrack → HealthKit → Notifications → AI Consent → Arena Preview → Summary/Briefing). The code implements a **20-case `OnboardingStep` enum** with a **"show-then-ask" ordering** that front-loads value and goals *before* authentication. The spec's step numbers, copy progress model ("Step 4 of 13"), and several screens do not exist as described. This section documents the **actual** sequence.

### 2.1 The Actual Step Sequence

`OnboardingStep` is a `String, Codable, CaseIterable` enum. `next`/`previous` walk `allCases` in declaration order, so the flow order **is** the enum declaration order. There is no separate ordered-flow table — declaration order is the single source of truth (intentional: "adding/reordering steps doesn't require touching" a switch). The 20 cases, in flow order:

| # | `OnboardingStep` | Screen | Required | Skippable |
|---|------------------|--------|----------|-----------|
| 1 | `splash` | `OnboardingSplashView` (wordmark loader, auto-advance 1.8s) | — | — |
| 2 | `valueDemo` | `ValueDemoView` ("THIS IS TEMPO") | — | — |
| 3 | `goals` | `GoalSetupView` ("WHAT ARE YOU FIGHTING FOR?") | **yes** | no |
| 4 | `healthkit` | `HealthKitPermissionView` ("LET'S CONNECT YOUR HEALTH DATA.") | no | yes |
| 5 | `auth` | `OnboardingAuthView` (Sign in with Apple; value-prop headline merged here) | **yes** | no |
| 6 | `profile` | `ProfileSetupView` (display name **+ inline username**) | **yes** | no |
| 7 | `identity` | `IdentitySetupView` ("What best describes you?" → `UserProfile.identityLabel`) | **yes** | no |
| 8 | `trainingSetup` | `TrainingSetupView` | no | yes |
| 9 | `academicSetup` | `AcademicSetupView` | no | yes |
| 10 | `dailyRhythm` | wake time + sleep target + chronotype (`DailyPlanProfileViews`) | no | yes |
| 11 | `classSchedule` | term-bounded weekly class schedule + work shifts | no | yes |
| 12 | `eatingWindow` | intermittent-fasting / eating-window preferences | no | yes |
| 13 | `studyPreferences` | Pomodoro length + study session preferences | no | yes |
| 14 | `trainingPreferences` | preferred training time of day | no | yes |
| 15 | `weekendMode` | weekend differential | no | yes |
| 16 | `whoopConnect` | `WhoopConnectView` ("YOUR BODY TALKS. LET'S LISTEN.") | no | yes |
| 17 | `notifications` | `NotificationSetupView` ("THE DRILL SERGEANT NEEDS YOUR ATTENTION.") | no | yes |
| 18 | `tosAccept` | `TermsAcceptanceView` (ToS + Privacy; backend `ToSGateMiddleware` 451-gates until accepted) | **yes** | no |
| 19 | `aiConsent` | `AIConsentView` ("ENABLE AI COACHING."; Anthropic disclosure; backend `SubscriptionMiddleware` 402-gates AI routes) | no | yes |
| 20 | `complete` | `OnboardingCompleteView` ("YOU'RE IN.") | — | — |

`isRequired` = `{auth, profile, identity, goals}`. `isSkippable` = `{healthkit, trainingSetup, academicSetup, dailyRhythm, classSchedule, eatingWindow, studyPreferences, trainingPreferences, weekendMode, whoopConnect, notifications, aiConsent}`. `stepNumber` is derived from `allCases.firstIndex`. The daily-plan-profile block (steps 10–15) feeds `buildDailyPlanProfile()` → `UserDailyPlanProfile` SwiftData row + backend sync (per INTELLIGENCE_REMEDIATION_PLAN.md §8).

### 2.2 Steps That Diverge

- **Step 3 `profile` — inline username.** `ProfileSetupView` collects display name **and username with a live availability check** (`checkUsernameAvailability()`, 3–30 chars, allowed-charset validation).

  > **Divergence from original spec:** The spec explicitly *deferred* username to first Arena access ("Username: DEFERRED"). Code collects it inline during onboarding. Photo picker from the spec is not present.

- **Step 1 value prop merged into `auth`.** The spec's standalone "Welcome / Value Prop" screen (headline "STOP MANAGING YOUR LIFE IN 5 DIFFERENT APPS") lives on `OnboardingAuthView` together with Sign in with Apple. `ValueDemoView` ("THIS IS TEMPO") is the separate `valueDemo` step. No ring animation on either.

  > **Divergence from original spec:** Spec's "Why is sign-in required?" bottom sheet and 2-cancellation hint not present. A "Skip Sign In (Debug Only)" affordance exists on `OnboardingAuthView`.

- **Academics split across three screens.** Spec's single Academics step is `AcademicSetupView` ("YOUR ACADEMICS." — spec headline was "NOW THE HARD PART. YOUR BRAIN.") + `ClassScheduleView` + `StudyPreferencesView`. No in-flow "add courses"/"add exams" chips, no daily-study-goal segmented selector, no in-step calendar import.

- **Goals abbreviated.** `GoalSetupView` headline "WHAT ARE YOU FIGHTING FOR?" and the evening-start copy ("This is when the drill sergeant gets serious.") match. The spec's 8-max non-negotiable editor, time-waster selector, and primary-goal cards are abbreviated/not all confirmed present.

### 2.3 Steps That Are MISSING

> **Status: NOT IMPLEMENTED — Step 8 "Connect NutriTrack."** No NutriTrack onboarding step exists; there is no `nutritrack` case in `OnboardingStep`. NutriTrack was removed product-wide (backend `Migrations/DropNutriTrackIntegrations.swift`). The spec section is stale.

> **Status: NOT IMPLEMENTED — Step 12 "Arena Preview" (in-flow).** `ArenaIntroView` ("WELCOME TO THE ARENA.") exists as a file but is **orphaned**: there is no `.arena*` case in `OnboardingStep` and no branch in `OnboardingContainerView.stepContent`. It is unreachable as an onboarding step.

> **Status: NOT IMPLEMENTED — Step 13 "Summary / First Day Briefing."** No data-recap + Day-1 briefing step exists. `OnboardingCompleteView` is a generic "YOU'RE IN." completion screen, not the spec's summary of collected data plus first-day briefing.

### 2.4 Global Onboarding UX

`OnboardingContainerView` sets `.preferredColorScheme(.dark)`. The progress bar is a **single continuous fill** (`geo.size.width * viewModel.progress`, height 3, `.easeInOut(0.3)`), hidden on splash/valueDemo/complete. Step transitions use `.transition(.opacity)` (a code comment notes `.scale`/`.move` caused overflow artifacts). `advance()` walks `currentStep.next` with `.easeInOut(0.3)`; falling off the end calls `complete()`. `goBack()` walks `.previous` when `canGoBack`. `skip()` is `advance()`.

> **Divergence from original spec:** Spec required a **13-segment** progress bar and a **0.35s horizontal slide** transition. Code uses one continuous fill bar and an opacity crossfade. No 13 discrete segments.

---

## 3. Onboarding UX Details

### 3.1 Data Persistence Strategy

Implemented. `OnboardingViewModel` persists the current step to `UserDefaults` key `tempo.onboarding.step` and the in-memory state JSON to `tempo.onboarding.data`; it resumes at the last step on relaunch. A migration guard handles a saved step that no longer maps to a valid case (e.g. the removed "arena") by falling back rather than crashing. On `complete()` it sets `tempo.onboarding.complete` and clears the step/data keys.

### 3.2 Validation Rules / Error States / Accessibility

Partial. The required/skippable model exists (`isRequired`, `isSkippable`). `ProfileSetupView` has real per-field username validation (length + charset + availability) with error strings. Systematic per-field validation rules and the spec's documented error-state copy across every step are not verified. Dynamic Type / VoiceOver behavior is not independently auditable from code.

---

## 4. Onboarding Funnel Optimization

> **Status: NOT IMPLEMENTED.** No Quick Start vs Full Setup path split, no `onboarding_*` funnel analytics events, no A/B-test harness, no progressive-disclosure deferral logic in `OnboardingViewModel`, no drop-off recovery flows. The spec's "Quick Start uses provisional auth" only loosely corresponds to a `.provisional` authorization option in `NotificationSettingsView` (a settings re-request path), not an onboarding funnel path.

---

## 5. Re-Onboarding

> **Status: NOT IMPLEMENTED.** No mechanism to re-prompt skipped Whoop/HealthKit/notification integrations after onboarding. No re-onboard / promptSkipped / connectWhoopLater code path. Late-integration and settings-deep-link recovery flows from the spec do not exist.

---

# PART 2: NOTIFICATION SYSTEM

> The notification **core** (scheduling, categories, 64-slot budget, daily-budget cost system, escalation state machine, APNs P8, four scheduled backend jobs) is **REAL and solid**. The retention/intelligence layers (re-engagement, smart context logic, localization, full copy banks) are largely **MISSING**. Each section below states which.

## 6. Notification Architecture

### 6.1 Accountability Escalation Timeline

Implemented. `AccountabilityEscalationEngine.scheduleEscalations` drives an `EscalationState` machine (quiet / gentle / firm / urgent / critical / resolved) relative to the user's evening start and calls `notificationService.scheduleAccountabilityEscalation`. On resolution it calls `updateBadgeCount(0)`.

> **Divergence from original spec:** The exact E-5.5h / E-2.5h / E-1h / E-30min offset formulas are not line-verified, but the staged escalation structure is present.

### 6.2 Local vs Push / 64-Slot Limit

Implemented. `NotificationService.maxPendingNotifications = 64`. When pending requests reach the cap, the service evicts the **farthest-future** pending notification (sorted by `UNCalendarNotificationTrigger.nextTriggerDate()`) before adding new ones. `rescheduleAllForToday(...)` rebuilds the day's schedule and resets the daily budget. `isWithinPreScheduleWindow(date)` gates scheduling to a forward window.

### 6.3 Notification Categories & Actions

Implemented. `registerCategories()` registers the category/action set (morning briefing, accountability gentle/firm/urgent/final/clear, meal, training, recovery, bedtime, etc.), invoked during setup. Action set matches the spec closely.

### 6.4 Grouping / Badge / Sound

Partial. `updateBadgeCount(_:)` and `sound(for categoryID:)` (custom-sound mapping) are implemented. Thread-id grouping keyed `tempo.[channel].[date]`, badge = incomplete-non-negotiables semantics, and presence of the custom `.caf` sound files are not line-confirmed.

### 6.5 Time Sensitive Interruption Levels

Implemented. Morning briefing schedules at `.timeSensitive`; tier → interruption-level mapping exists; backend `APNsService` switches `interruptionLevel`. No Critical Alerts entitlement is used (matches the feasibility remediation).

---

## 7. Push Notification Infrastructure

### 7.1 APNs Authentication (P8 Token-Based)

Implemented. `APNsService` uses **P8 token-based (key-based) auth per ADR-019** ("Direct APNs with P8 token-based authentication"), with `sendAlert`, `sendSilent`, and invalid-token handling. Device-token lifecycle is handled by `PushRegistrationService` + `DeviceController` + the `CreateDeviceTokens` migration.

### 7.2 APNs Payload Structure

Partial. `APNsService` builds the payload with `type` / `interruption_level` / `category` and switches `interruptionLevel`. Per-channel relevance score (0.0–1.0) and `thread-id` / `deep_link` payload fields are not confirmed in the payload builder.

### 7.3 Provisional Notifications

Partial. A `.provisional` authorization option is used in `NotificationSettingsView` (settings re-request). It is **not** wired as the spec's pre-Step-10 Quick Start trial flow.

### 7.4 Live Activities + Dynamic Island

Partial. A focus-timer Live Activity is implemented (`Services/LiveActivity/FocusTimerActivityAttributes.swift` + `FocusTimerActivityManager.swift`, referenced from `AccountabilityViewModel`). Workout and accountability-countdown Live Activities from the spec are not present.

### 7.5 Background App Refresh

Partial. `rescheduleAllForToday` exists and runs on foreground. No `BGAppRefreshTask` / `BGProcessingTask` registration was found — rescheduling depends on app foreground, not a background task.

### 7.6 Backend Scheduled Jobs

Implemented. Wired in `configure.swift`:
- `MorningBriefingJob` (struct lives in `NotificationScheduleJob.swift` — file/struct name mismatch, harmless) — every 15 min
- `WeeklySummaryJob` — Sunday 20:00
- `DrillSergeantBatchJob` — Sun + Wed 20:00
- `ProcessedNotificationsCleanupJob` — daily 04:00
- `LeaderboardRefreshJob` — present (Arena module)

---

## 8. Notification Channels — Copy Bank

> **Divergence from original spec — MASSIVE SHORTFALL.** The spec defined **13 channels × 30+ variations × 4 intensities**. The code has exactly **one** copy bank: `Resources/AccountabilityCopy.json` (~101 lines), covering only the accountability channels.

What exists:
- `AccountabilityCopyPool.pick(tier:intensity:context:)` selects from `AccountabilityCopy.json`.
- `CopyTier` enum: `gentle / firm / urgent / critical / allClear` (5 tiers).
- `CopyIntensity` enum: `gentle / firm / savage` — **3 intensities, not 4**. There is no distinct "Drill Sergeant" intensity; level 3 collapses into firm/savage.
- Roughly 3–5 variations per tier/intensity (~60 strings total), not 30+.
- `AccountabilityCopyPool` has recency/dedupe weighting and an `interpolate(template:context:)` engine (`CopyContext` variables) — **for accountability copy only**.

> **Status: NOT IMPLEMENTED — copy banks for all non-accountability channels.** Morning Briefing, Meal, Training, Recovery, Bedtime, Arena/Social, Weekly Summary, and Streak Warning have **scheduling functions** in `NotificationService` (`scheduleMorningBriefing`, `scheduleMealReminder`, `scheduleTrainingReminder`, `scheduleRecoveryNotification`, `scheduleBedtimeReminder`, `scheduleStreakWarning`) and the backend builds the briefing/weekly bodies, but each has a **single hardcoded string per channel**, not a per-intensity 30+ variation bank. The spec's per-channel Channel-1-through-13 copy banks do not exist as data.

---

## 9. Notification Timing Engine

Partial. Only DST-safe scheduling is real: `NotificationService` schedules via `UNCalendarNotificationTrigger(dateMatching: DateComponents)` (DST-safe per spec).

> **Status: NOT IMPLEMENTED — adaptive timing & suppression.** No `AdaptiveTimingEngine` (no 14-day wake-time learning / response-pattern learning), no `CalendarAwareFilter` / calendar-aware suppression, no in-app suppression guard. The spec marks calendar-aware suppression **MANDATORY**; it is entirely absent.

---

## 10. Notification Settings UI

Partial. `NotificationSettingsView` provides: an intensity section (4 `IntensityOption`s in the UI; `UserSettings.intensity` Int defaults to 3), a quiet-hours section (UI + time pickers), and several per-channel toggles (morning briefing, recovery, meal, bedtime, weekly, accountability …). `UserSettings` has `quietHours` fields, `weekendMode`, `examMode` / `examModeEndDate`.

> **Divergence from original spec:** Not all 13 channels are individually toggleable — they are grouped (e.g. one accountability toggle). No sound selector and no "Open iOS Settings" advanced row confirmed.

> **Status: NOT IMPLEMENTED — Intensity Level Behavior Matrix.** Only 3 distinct copy intensities exist (`CopyIntensity` gentle/firm/savage); the UI's 4-level selector collapses Drill Sergeant into firm/savage. Per-intensity Time-Sensitive behavior and override-shaming differences are not implemented.

> **Status: NOT IMPLEMENTED — Quiet Hours enforcement.** `UserSettings` has `quietHours` fields and the settings UI renders a quiet-hours section, but **no code in `Services` ever reads `quietHours`**. The scheduling layer never suppresses or queues based on quiet hours. This is **dead data** — settings + UI exist, enforcement does not.

> **Status: NOT IMPLEMENTED — adaptive/weekend schedule.** Wake/evening/bedtime time config exists, but Whoop/Health auto-detect of schedule, 14-day adaptive learning, and the "weekend +1h" behavior are not enforced (`weekendMode` is a settings flag with no scheduling effect).

---

## 11. Notification Smart Logic

### 11.1 Hard Daily Notification Budget

Implemented. `NotificationService.dailyBudgetCap = 6.0`; `budgetSpentToday` tracks spend; `canSpendBudget(cost:)` / `spendBudget(cost:)` / `resetDailyBudget()` enforce the cap. Each scheduling function passes a per-channel `budgetCost`; over-budget notifications are skipped with a log. A bypass/defrost path exists. Priority-resolution / merge-on-contention is not verified.

### 11.2 Anti-Spam Rules

Partial. `cancelPendingEscalationsOnForeground()` implements cancel-on-foreground. `AccountabilityCopyPool` recency/dedupe weighting implements copy de-duplication.

> **Status: NOT IMPLEMENTED — the "max 1 notification / 30 min" global throttle and the "no encouragement within 45 min of a warning" rule.** No global rate throttle exists.

### 11.3 Notification Fatigue Detector

> **Status: NOT IMPLEMENTED.** No ignored-counter and no 3/5/8/12-ignored fatigue escalation anywhere.

### 11.4 Context-Aware Adjustments

> **Status: NOT IMPLEMENTED.** `UserSettings` has `weekendMode` / `examMode` / `examModeEndDate` fields but **no enforcement logic anywhere** — they are dead data. No calendar suppression (spec marks this **MANDATORY**), no adaptive timing engine, no first-week intensity taper, no consecutive-miss handling, no batching, no DND awareness.

### 11.5 Content Personalization Variables

Partial. `AccountabilityCopyPool.interpolate(template:context:)` with `CopyContext` supplies variable substitution for accountability copy only. Other channels build strings ad hoc; not all documented variables are wired.

---

## 12. Re-Engagement Sequences

> **Status: NOT IMPLEMENTED.** The entire churn re-engagement subsystem (Day 2/3/5/7/14/30/60 inactivity pushes, copy banks, escalation/stop rules) is absent. There is no inactivity detection, no scheduled backend job (the only Jobs are MorningBriefing / WeeklySummary / DrillSergeantBatch / LeaderboardRefresh / ProcessedNotificationsCleanup), and no `notif.reengage` copy.

---

## 13. First Week Experience

> **Status: NOT IMPLEMENTED.** No scripted Day-1/2/3 notification logic, no adaptive Day-4-7 behavior, no first-week intensity taper, no Day-1 "complete ONE non-negotiable" scripting, and no Day-3/Day-7 milestone notifications anywhere in `NotificationService` or the backend jobs.

---

## 14. Localization

> **Status: NOT IMPLEMENTED.** There is **no** `Localizable.strings` / `.xcstrings` in the app target, no `notif.*` string keys, no `NSLocalizedString` / `String(localized:)` for notification copy, and no `it.lproj`. All copy is hardcoded English in JSON (`AccountabilityCopy.json`, ~60 strings) and Swift string literals. The spec's `notif.morning.*` / `notif.reengage.*` key namespaces, pluralization handling, per-locale date/unit formatting, Italian localization, and the localization testing checklist do not exist.

---

## 15. Legal & Compliance

Partial. Opt-out exists via settings toggles + the `.provisional` path. Backend gates exist: `ToSGateMiddleware` (451 until ToS accepted), `SubscriptionMiddleware` / AI-consent gate (402 `ai_consent_required`), and an `AddAIConsentToUsers` migration; `PrivacyInfoView` exists in app.

> **Divergence from original spec:** "No health data in lock-screen payloads" is **not** verified at the payload-builder level — the backend morning-briefing body includes the recovery zone. GDPR notification-preference export is not confirmed.
