# ONBOARDING_AND_NOTIFICATIONS — Onboarding Flow & Notification System

> **Module**: Onboarding + Notifications
> **App**: Tempo — iOS (SwiftUI, iOS 17+) + Vapor backend
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS + backend developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):

Onboarding:

- `Tempo/Tempo/ViewModels/OnboardingViewModel.swift` — `enum OnboardingStep`, `advance()`, `goBack()`, persistence, `resumed(fromSaved:)`, `submitToSAcceptance`, `buildDailyPlanProfile()`
- `Tempo/Tempo/Views/Onboarding/OnboardingContainerView.swift` — `stepContent` switch, progress bar
- `Tempo/Tempo/Views/Onboarding/*View.swift` — the six steps: `ValueDemoView`, `GoalSetupView`, `OnboardingAuthView`, `ProfileSetupView`, `PermissionsSetupView`, `OnboardingCompleteView`
- `Tempo/Tempo/DesignSystem/Tide+Onboarding.swift` — the onboarding kit (scaffold, choice cards, notes, footer bar)

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

### 1.2 First Launch

There is no splash step any more: a fresh install opens straight on the hook (`ValueDemoView`, "THIS IS TEMPO", with clearly labelled sample data). The progress bar is hidden on the hook and on the finish screen.

---

## 2. Step-by-Step Onboarding

> **Rework 2026-11-24 — six steps.** Onboarding was cut from 20 steps to 6: hook, goal, sign in, about you, permissions, ready. Everything else is asked later, in the place it is needed. Each dropped question has a default and stays settable in Settings or in the feature (table in 2.2).

### 2.1 The Step Sequence

`OnboardingStep` is a `String, Codable, CaseIterable` enum. `next`/`previous` walk `allCases` in declaration order, so the flow order **is** the enum declaration order.

| #   | `OnboardingStep` | Screen                                                                                                              | Required | Counted in the bar |
| --- | ---------------- | ------------------------------------------------------------------------------------------------------------------- | -------- | ------------------ |
| 1   | `valueDemo`      | `ValueDemoView` ("THIS IS TEMPO"; "Skip tour" also goes to the goal)                                                    | —        | no                 |
| 2   | `goals`          | `GoalSetupView` ("WHAT ARE YOU FIGHTING FOR?"; one card per `PrimaryGoal`, saved to `UserSettings.primaryGoalRaw`)  | **yes**  | 1 of 4             |
| 3   | `auth`           | `OnboardingAuthView` (Terms + Privacy checkbox, then Sign in with Apple; the acceptance is POSTed after sign-in)    | **yes**  | 2 of 4             |
| 4   | `aboutYou`       | `ProfileSetupView` (display name, username with live availability check, one identity menu)                         | **yes**  | 3 of 4             |
| 5   | `permissions`    | `PermissionsSetupView` (Apple Health, Notifications, Location; each optional, each with its own Allow button)       | no       | 4 of 4             |
| 6   | `complete`       | `OnboardingCompleteView` ("YOU'RE IN.")                                                                             | —        | no                 |

- **Terms.** The Apple button is dimmed and blocked until the checkbox is ticked. After a successful sign-in the app posts the acceptance (`submitToSAcceptance`), because the backend `ToSGateMiddleware` answers 451 until it has it. `tosRecorded` is saved so a relaunch does not ask twice. A person already signed in (came back to this step) sees only the checkbox and Continue. The DEBUG-only "Skip Sign In" button is kept (id `onboardingSkipSignIn`).
- **About you.** The username follows the display name until the person types in the username field (`usernameEdited`); a saved username that is not the suggestion counts as typed.
- **Permissions.** Apple Health reads "Done" once asked (Health never reveals whether reading was allowed); Notifications and Location read "On" when granted and offer "Open Settings" when denied.
- **Resuming an older run.** `OnboardingStep.resumed(fromSaved:)` maps every saved step name from the 20-step flow: `splash` and `valueDemo` to the hook, `goals` to the goal, `aiConsent` and `complete` to the finish, and everything in between back to sign-in (where the terms are asked). An unknown name starts over. A person who already finished onboarding (`tempo.onboarding.complete`) never sees any of this again.
- **Launch arguments.** `--uitesting-skip-onboarding` still skips the flow; `--uitesting-reset` clears `tempo.onboarding.complete`.

### 2.2 Questions that were dropped, their default, and where they are set now

| Dropped question                                      | Default                                                       | Where it is set now                                                         |
| ----------------------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Training days per week                                | 4 (Upper/Lower split)                                         | Settings > Training > Split                                                 |
| Experience level                                      | not set (read as Beginner)                                    | Settings > Training > Experience                                            |
| Preferred training time of day                        | any free slot                                                 | Settings > Training > Usual training time                                   |
| Wake time, sleep target                               | 07:00, 23:00                                                  | Settings > Schedule                                                         |
| Evening start                                         | 19:30                                                         | Settings > Schedule > Leisure starts                                        |
| Eating window, breakfast, post-workout meal           | 12 hours, defaults                                            | Settings > Diet Profile                                                     |
| Study session length                                  | 25 / 5 / 15 min                                               | Settings > Focus Timer                                                      |
| Whoop                                                 | not connected                                                 | Settings > Connections                                                      |
| Apple Health, Notifications, Location                 | asked on the permissions step; Continue without allowing leaves them off           | Permissions step, Settings > Connections, Settings > Notifications          |
| Terms and Privacy                                     | asked on the sign-in step                                     | —                                                                           |
| AI consent                                            | off                                                           | asked in place when an AI feature needs it (`AIBlockerCard`), and Settings  |
| Goal                                                  | none until chosen                                             | Settings > Profile > Goal                                                   |
| Name, username, identity                              | —                                                             | Settings > Profile                                                          |
| Time-waster, university, chronotype, class/work/term, weekend mode | not used by any feature                          | dropped; the daily-plan fields stay in the saved blob with their defaults   |

The daily-plan fields (`buildDailyPlanProfile()` → `UserDailyPlanProfile` SwiftData row + backend sync) are still written with defaults, so the planner behaves as it did for a person who tapped through the old steps.

### 2.3 Steps that no longer exist

`OnboardingSplashView`, `HealthKitPermissionView`, `IdentitySetupView`, `TrainingSetupView`, `AcademicSetupView`, `DailyPlanProfileViews`, `WhoopConnectView`, `NotificationSetupView`, `TermsAcceptanceView`, `AIConsentView` and the orphaned `ArenaIntroView` were deleted. NutriTrack was removed product-wide (backend `Migrations/DropNutriTrackIntegrations.swift`), so it never returns as a step.

### 2.4 Global Onboarding UX

`OnboardingContainerView` sets `.preferredColorScheme(.dark)`. The progress bar is a single continuous fill driven by `OnboardingStep.progressPosition` (1 to 4), hidden on the hook and the finish screen. Step transitions use `.transition(.opacity)`. `advance()` walks `currentStep.next`; falling off the end calls `complete()`. `goBack()` walks `.previous` when `canGoBack` (not on the hook or the finish screen). Every step uses `OnboardingScaffold` and works at accessibility sizes.

---

## 3. Onboarding UX Details

### 3.1 Data Persistence Strategy

Implemented. `OnboardingViewModel` persists the current step to `UserDefaults` key `tempo.onboarding.step` and the in-memory state JSON to `tempo.onboarding.data`; it resumes at the last step on relaunch. A saved step from the older 20-step flow is mapped by `OnboardingStep.resumed(fromSaved:)` (see 2.1) rather than crashing. The blob also carries `primaryGoal` and `tosRecorded`; `ContentView.ensureUserProfile` reads it once to create the profile and settings, and a goal chosen on a phone that already has a profile replaces the saved one. On `complete()` it sets `tempo.onboarding.complete` and clears the step/data keys.

### 3.2 Validation Rules / Error States / Accessibility

Partial. `canContinue` gates each step: a goal on the goal step, the ticked terms on sign-in, a name and a valid username on about-you; permissions are always optional. `ProfileSetupView` has real per-field username validation (length + charset + availability) with error strings. Systematic per-field validation rules and the spec's documented error-state copy across every step are not verified. Dynamic Type / VoiceOver behavior is not independently auditable from code.

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

> **Status: IMPLEMENTED (Nov 2026) — Quiet Hours enforcement.** `NotificationPolicy` (`Services/Notifications/NotificationPolicy.swift`) is applied in `NotificationService` where reminders are scheduled: inside the window a reminder is skipped (not delayed), except escalating accountability warnings and defrost reminders. It covers reminders Tempo schedules on this phone; server pushes, rest and workout timers, snoozes and the Recovery Coach schedulers are not covered. The page also has one three-level setting (Essential / Balanced / Everything) over the per-category toggles, and an in-app list of today's notifications (`NotificationInbox`).

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
