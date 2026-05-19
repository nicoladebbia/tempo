# STATE_MACHINES — Formal State Machine Specifications

> **Module**: Cross-cutting (state machines for every stateful feature)
> **App**: Tempo — iOS (SwiftUI, iOS 17+)
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes the state enums and transitions the code actually has, not the original aspirational formal spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `Tempo/Tempo/ViewModels/TrainingViewModel.swift` — `enum WorkoutSessionState` (+ `ExerciseSubState`, `PausedFromState`)
- `Tempo/Tempo/ViewModels/AccountabilityViewModel.swift` — `enum FocusTimerState` (+ `PausedFocusState`)
- `Tempo/Tempo/Services/Engines/AccountabilityEngine.swift` — `enum DailyAccountabilityState`, `evaluateState(...)`
- `Tempo/Tempo/Services/Integrations/WhoopServiceProtocol.swift` / `WhoopService.swift` — `enum WhoopConnectionState`
- `Tempo/Tempo/ViewModels/OnboardingViewModel.swift` — `enum OnboardingStep`
- `Tempo/Tempo/Services/Notifications/AccountabilityEscalationEngine.swift` — `enum EscalationState` (+ `ResolutionReason`)
- `Tempo/Tempo/Services/Subscriptions/SubscriptionServiceProtocol.swift` — `enum SubscriptionState`
- `Tempo/Tempo/Views/Nutrition/Wizard/WizardCoordinator.swift` — `enum WizardStep`, `WizardCoordinator`
- Data-only models (no state enum): `Models/Accountability/Streak.swift`, `Models/Arena/ChallengeLocal.swift`, `Models/Recovery/DailyPrescription.swift`, `Models/Training/SetFeedback.swift`

> **Divergence from original spec:** The original v1.1 spec defined 16 formal machines + the MealPlanIntakeWizard, each with full transition tables, entry/exit actions, timeout handling, persistence, UI mapping, notification triggers, and analytics events. The code implements **8 as real Swift state enums** (several renamed and flattened), and **does not model 9 of them as state machines at all** (they exist as plain data, booleans, ints, or not at all). The exhaustive transition/notification/analytics tables in the old spec were aspirational; this AS-BUILT doc records the actual enum shape and the real transition sites, and preserves the spec intent in divergence callouts.

---

## Table of Contents

1. [Workout Session](#1-workout-session) — IMPLEMENTED
2. [Focus Timer](#2-focus-timer) — IMPLEMENTED (thinned)
3. [Daily Accountability](#3-daily-accountability) — IMPLEMENTED (thinned)
4. [Whoop Sync](#4-whoop-sync) — IMPLEMENTED (renamed, flattened)
5. [NutriTrack Sync](#5-nutritrack-sync) — NOT IMPLEMENTED
6. [Non-Negotiable Item](#6-non-negotiable-item) — NOT IMPLEMENTED
7. [Streak](#7-streak) — NOT IMPLEMENTED (data only)
8. [Challenge](#8-challenge) — NOT IMPLEMENTED (bool only)
9. [Friend Request](#9-friend-request) — NOT IMPLEMENTED (int only)
10. [Onboarding](#10-onboarding) — IMPLEMENTED (renamed, superset)
11. [Push Notification Escalation](#11-push-notification-escalation) — IMPLEMENTED (renamed)
12. [Workout Plan Generation](#12-workout-plan-generation) — NOT IMPLEMENTED
13. [Recovery Prescription](#13-recovery-prescription) — NOT IMPLEMENTED
14. [App Sync Orchestrator](#14-app-sync-orchestrator) — NOT IMPLEMENTED
15. [Subscription](#15-subscription) — IMPLEMENTED
16. [Exercise Set](#16-exercise-set) — NOT IMPLEMENTED
17. [MealPlanIntakeWizard](#17-mealplanintakewizard) — IMPLEMENTED

**Summary:** 8 implemented as Swift state enums (4 of them renamed and/or thinned vs spec), 9 not implemented as state machines.

---

## 1. Workout Session

**Status: IMPLEMENTED.** Real type: `enum WorkoutSessionState: Codable, Equatable` in `TrainingViewModel.swift`. This is the closest match to spec of any machine — associated values are preserved.

### Swift Enum (as built)

```swift
enum WorkoutSessionState: Codable, Equatable {
    case idle
    case warmup(exerciseIndex: Int, warmupSetIndex: Int)
    case exercise(ExerciseSubState)
    case cooldown
    case summary
    case saved
    case paused(previousState: PausedFromState, pauseStartTime: Date)
    case interruptedCall(previousState: PausedFromState)
    case crashedRecovery
    case discarded

    enum ExerciseSubState: Codable, Equatable {
        case setActive(exerciseIndex: Int, setIndex: Int)
        case resting(exerciseIndex: Int, setIndex: Int, remainingSeconds: TimeInterval)
        case betweenExercises(fromIndex: Int, toIndex: Int)
    }

    enum PausedFromState: Codable, Equatable {
        case warmup(exerciseIndex: Int, warmupSetIndex: Int)
        case exercise(ExerciseSubState)
        case cooldown
    }

    var isActive: Bool // true for warmup/exercise/cooldown
}
```

### States

10 top-level cases: `idle`, `warmup`, `exercise` (wrapping the 3-case `ExerciseSubState`: `setActive` / `resting` / `betweenExercises`), `cooldown`, `summary`, `saved`, `paused`, `interruptedCall`, `crashedRecovery`, `discarded`. The orthogonal pause overlay is modelled via `PausedFromState` (covers `warmup`, `exercise`, `cooldown` — `exercise` wraps `ExerciseSubState`, so all five spec pause origins are covered).

### Transitions (real call sites)

`TrainingViewModel`: `startWorkout()` enters `warmup`/`exercise`; `logSet` / rest-timer flow drives `ExerciseSubState`; finish path → `summary` → `saved`; `discardWorkout()` → `discarded`; crash-recovery restore → `crashedRecovery`; phone-call interruption → `interruptedCall`; pause/resume swap `paused(previousState:pauseStartTime:)`. `sessionState` is the single source of truth, persisted via `Codable`.

> **Divergence from original spec:** The state *shape* matches the spec including associated values and the concurrent `ExerciseSubState` region. The spec's exhaustive transition/notification/analytics tables (e.g. `set.completed`, `WorkoutCompleted` cross-machine emit, Live Activity coordination) are not all wired as discrete tracked events; the enum and its transitions are real, the surrounding observability is partial.

---

## 2. Focus Timer

**Status: IMPLEMENTED, thinned.** Real type: `enum FocusTimerState: Equatable` in `AccountabilityViewModel.swift`. All documented states exist; **the spec's associated-value payloads are stripped** and the enum is **not `Codable`**.

### Swift Enum (as built)

```swift
enum FocusTimerState: Equatable {
    case idle
    case configuring
    case focusing(remaining: TimeInterval)
    case sessionDone(sessionCount: Int)
    case onBreak(remaining: TimeInterval)
    case breakDone
    case longBreak(remaining: TimeInterval)
    case completed(totalSessions: Int)
    case review
    case paused(previous: PausedFocusState)
    case cancelled

    enum PausedFocusState: Equatable {
        case focusing(remaining: TimeInterval)
        case onBreak(remaining: TimeInterval)
        case longBreak(remaining: TimeInterval)
    }

    var isActive: Bool // true for focusing/onBreak/longBreak
}
```

### States & transitions

11 cases. Lifecycle: `idle → configuring → focusing → sessionDone → onBreak/longBreak → breakDone → … → completed → review → idle`. `paused(previous:)` overlays the active timer states; `cancelled` is the abandon path. Timer remaining is recomputed from `Date()` diffs on foreground (no background timers).

> **Divergence from original spec:** Associated values were dropped vs spec:
> - spec `configuring(sessionType:subject:)` → code bare `configuring`
> - spec `focusing(session:totalSessions:remainingSeconds:)` → code `focusing(remaining:)`
> - spec `review(focusScore:totalTime:distractions:)` → code bare `review`
> - spec `cancelled(savedPartialTime:)` → code bare `cancelled`
>
> Enum is **not `Codable`**; the spec required `Codable` for app-kill persistence of an in-flight focus session. State shape is faithful; the data payloads and persistence are not.

---

## 3. Daily Accountability

**Status: IMPLEMENTED, thinned.** Real type: `enum DailyAccountabilityState: String, Codable` in `AccountabilityEngine.swift`. Full transition graph is implemented in `evaluateState(...)`; cases are raw `String` with **no associated values**.

### Swift Enum (as built)

```swift
enum DailyAccountabilityState: String, Codable {
    case morningSetup
    case tracking
    case approachingDeadline
    case finalWarning
    case unlocked
    case dayFailed
    case overrideActive
    case review
}
```

### States & transitions

8 cases. `AccountabilityEngine.evaluateState(accountability:override:)` is the transition function — it returns `morningSetup`, `tracking`, `approachingDeadline`, `finalWarning`, `unlocked`, `dayFailed`, or `overrideActive` based on progress, deadline proximity, and override. `review` exists in the enum but is **never returned by `evaluateState`** (it is a UI/history concern only).

> **Divergence from original spec:** Spec cases carried payloads (e.g. `tracking(completedCount:totalCount:)`, `approachingDeadline(minutesRemaining:)`). Code uses payload-free `String`-raw cases; counts/minutes are computed separately and passed through view-model state, not the enum. The full deadline-driven transition graph is implemented and the engine cites the spec by section.

---

## 4. Whoop Sync

**Status: IMPLEMENTED, renamed and flattened.** Real type: `enum WhoopConnectionState: Sendable, Equatable` in `WhoopServiceProtocol.swift` (the spec name was `WhoopSyncState`).

### Swift Enum (as built)

```swift
enum WhoopConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}
```

### States & transitions

4 cases. `WhoopService` assigns `connectionState` across the OAuth connect, token refresh, and sync paths: `disconnected → connecting → connected`, with `error(String)` on any failure and a return to `disconnected` on `disconnect()`.

> **Divergence from original spec:** Renamed `WhoopSyncState → WhoopConnectionState` and **substantially flattened**. The spec defined `disconnected / authorizing / connected(WhoopConnectionSubState) / tokenExpired / refreshing`, with a nested `WhoopConnectionSubState` (`idle / syncing / staleData`) and a typed `WhoopSyncError`. The code has **no nested sync sub-state, no `tokenExpired`, no `refreshing` case**, and uses an untyped `error(String)`. Token refresh happens internally without a distinct state. Connection lifecycle is real and wired, but it is a much simpler machine than specified.

---

## 5. NutriTrack Sync

> **Status: NOT IMPLEMENTED.** No `NutriTrackSyncState` enum, no NutriTrack sync service exists in the iOS code. The entire NutriTrack integration and its `disconnected / connecting / connected(syncing|idle|staleData) / pinExpired` machine are absent. (Only an unrelated string mention exists in `Services/Engines/FoodCanonicalizer.swift`.)

> **Divergence from original spec:** Spec'd cross-machine emit `NutriTrackDataReceived` (Appendix A) has no source — this machine does not exist to fire it.

---

## 6. Non-Negotiable Item

> **Status: NOT IMPLEMENTED.** No `NonNegotiableItemState` enum. Non-negotiable items exist as data, but the spec's per-item lifecycle (`notStarted / inProgress / completed / overdue / skipped` with associated values) is not modelled. Progress is tracked ad hoc by the accountability engine, not via a per-item state enum.

---

## 7. Streak

> **Status: NOT IMPLEMENTED as a state machine.** Data scaffolding only. `Models/Accountability/Streak.swift` is a `@Model` class with `currentCount`, `longestCount`, `freezesUsed`, `freezesAvailable`, `lastCompletedDate`, plus computed `isActive` (last completion ≥ yesterday) and `canFreeze` Bools. There is **no `StreakState` enum**.

> **Divergence from original spec:** The spec's `inactive / active(N) / atRisk(minutesToMidnight) / broken(previousLength:brokenAt:) / preserved(freezeUsedAt:freezesRemaining:)` machine has no representation. Only an `inactive` vs `active` distinction exists, via the `isActive` boolean. `atRisk`, `broken`, and `preserved` are not modelled, so the Appendix A cross-machine triggers (`StreakAtRisk`, `active(N) → active(N+1)`) have no source state to fire from.

---

## 8. Challenge

> **Status: NOT IMPLEMENTED as a state machine.** `Models/Arena/ChallengeLocal.swift` is a `@Model` class with `isActive: Bool`, `startDate`, `endDate`, `myScore`, plus a computed `hasEnded`. There is **no `ChallengeState`, `ChallengeMetric`, or `ChallengeResult` enum**.

> **Divergence from original spec:** The spec's 9-state lifecycle (`invited / accepted / declined / expired / active / ending / completed / cancelled / abandoned`) is reduced to a single `isActive` Bool + `hasEnded` computed. No invitation / accept / decline / grace / abandon transitions exist.

---

## 9. Friend Request

> **Status: NOT IMPLEMENTED as a state machine.** No `FriendRequestState` enum. `ViewModels/ArenaViewModel.swift` exposes only `pendingRequestCount: Int`. The friend-system UI (`Views/Arena/FriendSystemView.swift`) exists, but the relationship is not modelled as a state enum.

> **Divergence from original spec:** The spec's `none / pendingSent / pendingReceived / accepted / declined / blocked / expired` relationship machine is collapsed to an integer count of pending requests.

---

## 10. Onboarding

**Status: IMPLEMENTED, renamed and expanded.** Real type: `enum OnboardingStep: String, Codable, CaseIterable` in `OnboardingViewModel.swift` (the spec name was `OnboardingState`). The code is a **superset** of the spec.

### Swift Enum (as built — declaration order = step order)

```swift
enum OnboardingStep: String, Codable, CaseIterable {
    case splash
    case valueDemo
    case goals
    case healthkit
    case auth
    case profile
    case identity
    case trainingSetup
    case academicSetup
    case dailyRhythm
    case classSchedule
    case eatingWindow
    case studyPreferences
    case trainingPreferences
    case weekendMode
    case whoopConnect
    case notifications
    case tosAccept
    case aiConsent
    case complete
}
```

### Transitions

Step sequencing is driven by `CaseIterable` declaration order (`stepNumber` is derived from it). The "show then ask" flow demonstrates value before collecting data: `splash → valueDemo → goals → healthkit → auth → profile → … → complete`.

> **Divergence from original spec:** Renamed `OnboardingState → OnboardingStep`. All documented spec steps are present (splash / auth / profile / trainingSetup / academicSetup / goals / whoopConnect / healthkit / notifications / complete), and the code **adds** many more: `valueDemo`, `identity`, `dailyRhythm`, `classSchedule`, `eatingWindow`, `studyPreferences`, `trainingPreferences`, `weekendMode`, `tosAccept`, `aiConsent`. The spec's `nutritrackConnect` and `arena` steps are **absent** (no NutriTrack integration; no separate arena onboarding step). Implemented and then some.

---

## 11. Push Notification Escalation

**Status: IMPLEMENTED.** Real type: `enum EscalationState: Codable, Equatable` nested in `AccountabilityEscalationEngine` (the spec name was `NotificationEscalationState`). Near-exact match including associated values.

### Swift Enum (as built)

```swift
enum EscalationState: Codable, Equatable {
    case quiet
    case gentle(briefingSentAt: Date)
    case firm(lastNotificationAt: Date)
    case urgent(lastNotificationAt: Date, notificationCount: Int)
    case critical(lastNotificationAt: Date)
    case resolved(reason: ResolutionReason)

    enum ResolutionReason: String, Codable {
        case allTasksComplete
        case dayEnded
        case overrideActivated
    }
}
```

### States, transitions & persistence

6 cases. Escalation tiers are scheduled relative to evening start (Gentle E−5.5h, Firm E−2.5h, Urgent E−1h, Final E−30min). `state` lives on the engine and is persisted to `UserDefaults` (keys `notification_escalation_state` / `notification_escalation_date`), reloaded in `init` via `loadState()`. `resolved(reason:)` is reached on all-tasks-complete, day-end, or override activation.

> **Divergence from original spec:** Only the type name differs (`NotificationEscalationState → EscalationState`). States, associated values, and `ResolutionReason` match the spec exactly.

---

## 12. Workout Plan Generation

> **Status: NOT IMPLEMENTED.** No `WorkoutPlanState`, `StaleReason`, or `RegenerationReason` enum in `TrainingEngine.swift` / `TrainingViewModel.swift`. The spec's `stale / generating / ready / modified / regenerating` workout-plan lifecycle does not exist; training plan generation is not modelled as a state machine. (`MealPlanGeneratorService.swift` has an unrelated nutrition `GenerationState` — not this machine.)

---

## 13. Recovery Prescription

> **Status: NOT IMPLEMENTED.** `Models/Recovery/DailyPrescription.swift` is a flat `@Model` (fields: `trainingRec`, `nutritionRecs`, `warnings`, `wasFollowed`) with no state. `RecoveryViewModel` has a generic `enum RecoveryLoadState` (a UI load state used by `loadState`), **not** the spec's `RecoveryPrescriptionState`. The spec's `pendingData / generating / active / expired / regenerating` machine with `PartialRecoveryData` / `RecoveryInputData` is absent — prescriptions are stored as flat rows with no lifecycle or regeneration state.

---

## 14. App Sync Orchestrator

> **Status: NOT IMPLEMENTED.** No `AppSyncState` enum. `Services/Sync/SyncCoordinatorProtocol.swift` defines only `enum SyncResolution` (`keepLocal` / `keepRemote` / `merge`) — a conflict-resolution enum, not the orchestrator machine. `BackgroundSyncService` / `DailyResetCoordinator` exist but there is no `idle / syncing / complete / partialFailure / fullFailure / retry / offlineQueue` enum.

> **Divergence from original spec:** The spec's multi-integration parallel-sync orchestrator (4 concurrent child syncs with per-child 30s timeout, `IntegrationSource` set, `SyncError`, retry backoff, and the Appendix B parallel-combination rules) does not exist as a state machine.

---

## 15. Subscription

**Status: IMPLEMENTED.** Real type: `enum SubscriptionState: Codable, Equatable` in `SubscriptionServiceProtocol.swift`. Case set and shape match the spec.

### Swift Enum (as built)

```swift
enum SubscriptionState: Codable, Equatable {
    case free
    case trial(startDate: Date, endDate: Date)
    case active(productId: String, expirationDate: Date, isAutoRenewing: Bool)
    case gracePeriod(productId: String, graceEndDate: Date)
    case expired(lastProductId: String, expiredAt: Date)
    case churned(lastProductId: String, expiredAt: Date)

    var isPro: Bool // true for trial/active/gracePeriod
}
```

### States

6 cases matching the spec's `free / trial / active / gracePeriod / expired / churned` shape with associated values (product ids and dates). `isPro` gates Pro feature access. Products: `SubscriptionProduct` (`monthly`, `annual`, `studentMonthly`, `studentAnnual`).

> **Divergence from original spec:** Enum existence, case set, associated values, and `Codable`/`Equatable` conformance verified. The spec's full transition table (StoreKit 2 transaction-driven), entry/exit actions, and notification triggers were not deeply traced against transaction handling — the machine exists and is the gate for Pro access, but transition completeness vs spec is not exhaustively verified here.

---

## 16. Exercise Set

> **Status: NOT IMPLEMENTED.** No `ExerciseSetState` enum. `Models/Training/SetFeedback.swift` defines feedback enums — `BreathDifficulty` (`easy` / `moderate` / `gassed`) and `FormQuality` (`clean` / `sloppy` / `failed`) — which are **post-set self-report signals, not a set lifecycle**. There is no `pending / inProgress / completed / failed / skipped` set-state enum.

> **Divergence from original spec:** Per-set state is handled implicitly inside `WorkoutSessionState.ExerciseSubState` (`setActive` / `resting`) rather than the spec's standalone `ExerciseSetState` with `targetWeight` / `actualReps` payloads. The dedicated machine and its `set.completed` / `set.failed` / `set.skipped` analytics events do not exist as a discrete machine.

---

## 17. MealPlanIntakeWizard

**Status: IMPLEMENTED.** Real type: `enum WizardStep: Int, CaseIterable, Identifiable, Sendable` in `WizardCoordinator.swift`, driven by `@Observable @MainActor final class WizardCoordinator`. Strong match to spec.

### Swift Enum (as built)

```swift
enum WizardStep: Int, CaseIterable, Identifiable, Sendable {
    case cookingCapacity
    case leftoverTolerance
    case eatingWindow
    case pantryGap
    case groceryIntent
    case recoveryOverride
    case temporaryExclusions
    case review
}
```

### States

8 steps. Visibility table (conditional steps recomputed from intake + launch snapshot):

| State | Always shown? | Skip predicate |
|-------|---------------|----------------|
| `cookingCapacity` | Yes | n/a |
| `leftoverTolerance` | Yes | n/a |
| `eatingWindow` | Yes (v1) | Future: skip when `UserSettings.eatingWindow` exists |
| `pantryGap` | Conditional | Skip when pantry recently populated |
| `groceryIntent` | Conditional | Skip when `pantryGap` did not fire or user chose "from pantry" |
| `recoveryOverride` | Conditional | Skip when WHOOP recovery unavailable |
| `temporaryExclusions` | Yes | n/a (in-step Skip button) |
| `review` | Yes | n/a |

### Transitions (real methods)

`WizardCoordinator`: `currentStep` (private(set), starts at `visibleSteps.first ?? .review`); `visibleSteps` recomputed via `computeVisibleSteps(snapshot:intake:)`; `advance()` recomputes visible steps and moves to next visible step; `goBack()` moves to previous visible step (no-op at first); `onComplete(MealPlanIntake)` emits final intake and dismisses; `onCancel()` discards the draft and dismisses.

### Invariants (enforced in code)

- `visibleSteps.first == .cookingCapacity` (always).
- `visibleSteps.last == .review` (always).
- `currentStep ∈ visibleSteps` after every transition.

> **Divergence from original spec:** All 8 spec states present; advance/goBack/visibleSteps recomputation and `onComplete` submit implemented per spec. The spec's PostHog analytics events (`meal_plan_wizard.opened`, `…step_advanced`, `…cancelled`, `…completed`) are deferred and not yet emitted.

---

## Appendix A: Cross-Machine Interaction Map

> **Status: NOT IMPLEMENTED as a formal event bus.** The spec mandated cross-machine event emission (`WorkoutCompleted`, `FocusSessionCompleted`, `DayUnlocked`, `WhoopDataReceived`, `NutriTrackDataReceived`, `StreakAtRisk`, `SubscriptionStateChanged`, etc.). There is no central event bus wiring these. Several source machines do not exist as state machines at all (NutriTrack Sync, Streak-as-machine, Challenge, Workout Plan, Recovery Prescription, App Sync), so the spec'd triggers from them have no source. Cross-machine effects that do happen (e.g. workout save updating challenge scores, day-unlock affecting escalation) are wired ad hoc through view models / engines, not via the formal event map.

---

## Appendix B: Concurrent State Region Rules

### Workout Session — Exercise Sub-States (IMPLEMENTED)

`WorkoutSessionState.exercise` wraps the mutually-exclusive `ExerciseSubState` (`setActive` / `resting` / `betweenExercises`). The pause overlay is orthogonal: `PausedFromState` covers `warmup`, `exercise` (which itself wraps `ExerciseSubState`), and `cooldown` — so all spec'd pause origins are representable. This region is real and matches the spec.

### App Sync Orchestrator — Parallel Sub-Syncs

> **Status: NOT IMPLEMENTED.** The 4-way concurrent child-sync region (Whoop / HealthKit / NutriTrack / Calendar, per-child 30s timeout, union-of-outcomes parent transition) does not exist — see §14.

---

## Appendix C: State Machine Invariants

These were design invariants in the original spec. Their AS-BUILT status:

1. **No machine in two states simultaneously** — holds for the implemented enums (single `state`/`sessionState`/`currentStep` property each); concurrent regions modelled only in Workout Session.
2. **Every terminal state reachable / every non-terminal state has an exit** — holds by inspection for the 8 implemented enums.
3. **App kill → recoverable state.** Partially: `WorkoutSessionState`, `DailyAccountabilityState`, `EscalationState`, `SubscriptionState` are `Codable` and persisted. **`FocusTimerState` is NOT `Codable`** and is not persisted across kill — a spec invariant violation.
4. **Time-dependent transitions use `Date` diffs, not background timers** — followed (workout/focus timers recompute from `Date()` on foreground).
5. **`Codable` enums handle unknown cases gracefully** — not centrally enforced; decode fallbacks are per-call-site, not guaranteed.
6. **Atomic transitions / cross-machine events fire after persist** — not formally enforced; no transaction wrapper or event bus exists (see Appendix A).

> **Status: NOT IMPLEMENTED — formal verification & test matrix.** The spec's testing requirements (exhaustive transition tests, invalid-transition tests, persistence round-trip, timeout, crash-recovery, concurrent-access, cross-machine event tests for every machine) are not realised as a complete suite. Treat the invariant list as design guidance, not as code-enforced guarantees.
