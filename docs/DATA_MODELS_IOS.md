# DATA_MODELS_IOS — SwiftData Models (As-Built)

> **Module**: Data Layer (SwiftData persistence)
> **App**: Tempo — iOS (SwiftUI, iOS 17+, Swift 6)
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually persists, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `Tempo/Tempo/Models/Schema/TempoSchemaV1.swift` → `TempoSchemaV1`
- `Tempo/Tempo/Models/Schema/TempoModelContainer.swift` → `TempoModelContainer`
- `Tempo/Tempo/Models/{User,Dashboard,Training,Accountability,Recovery,Arena,Sync,Integrations,Nutrition,Schedule}/*.swift`
- `Tempo/Tempo/Models/{Enums,SharedTypes}/*.swift`
- `Tempo/Tempo/Services/Sync/{MockSyncCoordinator,SyncCoordinatorProtocol,BackgroundSyncService}.swift`

> **SwiftData production notes (still accurate):**
> - Every `@Model` carries an explicit `@Attribute(.unique) var id` (UUID, or `String` for `CachedFood`) on top of SwiftData's auto `persistentModelID`. Intentional — stable sync identifier.
> - Enum properties are stored as `String`/`Int` raw-value mirrors (`typeRaw`, `statusRaw`, …) with `@Transient` computed accessors.
> - Arrays of custom types serialize to `Data` (JSON) via `*JSON` fields; arrays of `@Model` use `@Relationship`.
> - `@Transient` computeds are excluded from the schema.
> - `#Predicate` cannot capture locals in iOS 17 — date math is inlined or passed via `FetchDescriptor`.

---

## Table of Contents

1. [Schema Configuration & ModelContainer](#1-schema-configuration--modelcontainer)
2. [Enums & Shared Types](#2-enums--shared-types)
3. [User & Settings Models](#3-user--settings-models)
4. [Dashboard Models](#4-dashboard-models)
5. [Training Models](#5-training-models)
6. [Accountability Models](#6-accountability-models)
7. [Recovery Models](#7-recovery-models)
8. [Arena Models](#8-arena-models)
9. [Sync Models](#9-sync-models)
10. [Integration State Models](#10-integration-state-models)
11. [Query Patterns Per Screen](#11-query-patterns-per-screen)
12. [Indexes & Performance](#12-indexes--performance)
13. [Sync Conflict Resolution](#13-sync-conflict-resolution)
14. [Data Lifecycle & Cleanup](#14-data-lifecycle--cleanup)
15. [Thread Safety & ModelContext Patterns](#15-thread-safety--modelcontext-patterns)
16. [Migration Strategy](#16-migration-strategy)
17. [Undocumented As-Built Model Families](#17-undocumented-as-built-model-families)

---

## 1. Schema Configuration & ModelContainer

Source: `TempoSchemaV1.swift` → `TempoSchemaV1`, `TempoModelContainer.swift` → `TempoModelContainer`.

`TempoSchemaV1` is the **only** versioned schema and registers **50 `@Model` classes** (the original spec listed 26). The schema is a superset of the doc: it adds `UserDailyPlanProfile`, `ClassBlock`, `WorkBlock`, `DayPlan`, `TimeBlock`, `SetFeedback`, `ActivityEvent`, `DailyScoreEntry`, and the entire 17-class Nutrition family. The spec's `NutriTrackConnection` is **not** registered (it does not exist — see §10.2).

`TempoModelContainer.create(inMemory:)` (`@MainActor`) builds `Schema(TempoSchemaV1.models)` and a single `ModelConfiguration`:

| Config | Spec value | As-built value |
|--------|-----------|----------------|
| Configuration name | `"TempoStore"` | `"Tempo"` |
| Group container id | `group.app.tempo` | `group.app.tempo.Tempo` |
| `migrationPlan:` arg | `TempoMigrationPlan.self` | **not passed** |
| `allowsSave:` | `true` | not set (default) |
| `cloudKitDatabase:` | `.none` | `.none` ✓ |
| `isStoredInMemoryOnly:` | `inMemory` | `inMemory` ✓ |

`create()` also pre-creates `Library/Application Support` inside the app-group container and falls back to `.none` group container when the group URL is unavailable or `inMemory`. `preview()` delegates to `create(inMemory: true)`.

> **Divergence from original spec:** There is **no `TempoSchemaV2`, no `TempoMigrationPlan`, and no `migrationPlan:` argument**. The container deliberately evolves V1 in place. The rationale is documented in `TempoModelContainer.create`'s own source comment:
>
> > *"V1 is the live schema. The new recipe fields … evolve V1 rather than spinning up V2: SwiftData's `VersionedSchema` requires V2 to declare its OWN model classes … and the app hasn't shipped to production yet — there's nothing to migrate. A real V2 will be introduced post-launch when a breaking change lands."*
>
> See §16 for the full migration posture.

---

## 2. Enums & Shared Types

Source: `Models/Enums/{Workout,Accountability,Recovery,Arena,Sync}Enums.swift`, `Models/Nutrition/NutritionEnums.swift`, `Models/SharedTypes/{WeightUnit,TrainingSplit,ActiveDays}.swift`, plus inline enums in `UserDailyPlanProfile.swift`, `SetFeedback.swift`, `MealFeedback.swift`, `PantryItem.swift`.

All spec-required enums exist with matching raw values. Notable as-built deltas:

| Enum | Source | Delta vs spec |
|------|--------|---------------|
| `RecoveryInsightType` | `RecoveryEnums.swift` | **Adds** `aiDailyParagraph`, `aiWeeklyRecap` on top of `correlation`/`pattern`/`recommendation` |
| `XPSource` | `ArenaEnums.swift` | **Adds** `earlyBird` (`early_bird`) on top of the documented set |
| `TrackingMethod` | `AccountabilityEnums.swift` | **Drops** the spec's `autoNutritrack` case (nutrition no longer auto-tracked via NutriTrack) |
| `League`, `DailyXPGoal` | `ArenaEnums.swift` | New enums not in doc (Arena gamification) |
| `Chronotype`, `TrainingTimePreference`, `EatingWindowPreset`, `WeekendDifferential` | `UserDailyPlanProfile.swift` | New (day-plan profile) |
| `MealType`, `MealSource`, `FoodDataSource`, `MealStatus`, `DayType`, `DietaryGoal`, `SkillLevel`, `CookingSkill`, `BiologicalSex`, `NutritionCoachingTrigger` | `NutritionEnums.swift` | New (Nutrition family) |
| `BreathDifficulty`, `FormQuality`, `MealFeel`, `IngredientSentiment`, `PantryUnit`, `PantryStorageLocation`, `PantryPurchaseSource`, `ReceiptLineUnit`, `RecipeMealType`, `RecipeDifficulty`, `RecipeSkill`, `RecipeSource`, `LeftoverTolerance` | various | New, support the undocumented families in §17 |

Shared value types: `WeightUnit` (`kg`/`lb`), `TrainingSplit` (`ppl`/`upper_lower`/`full_body`/`bro_split`/`custom`), `ActiveDays` (bitmask `struct`).

> **Note (color-system fossil, not a model issue):** `RecoveryZone.color` (`RecoveryEnums.swift`) still returns dotted-token strings `"tempo.color.recovery.green|yellow|red"`. The dotted-token namespace is dead everywhere else (see `MODULE_DASHBOARD.md` §1) — these strings resolve to nothing useful. Out of scope for the model layer; flagged here for the next color-system pass.

---

## 3. User & Settings Models

### 3.1 UserProfile

Source: `Models/User/UserProfile.swift` → `UserProfile`. **IMPLEMENTED (superset).**

| Property | Type | Notes |
|----------|------|-------|
| `id`, `appleID`, `username` | UUID / String / String | all `@Attribute(.unique)` |
| `displayName`, `avatarURL` | String / String? | |
| `identityLabel` | String | **default `"Athlete"` — beyond spec** |
| `timezone` | String | |
| `weightKg`, `heightCm`, `age` | Double? / Double? / Int? | |
| `trainingSplitRaw`, `footballDaysRaw`, `equipmentJSON`, `weightUnitRaw` | String / Int / Data? / String | raw mirrors + `@Transient` accessors |
| `totalXP`, `currentLevel` | Int / Int | |
| `createdAt`, `updatedAt` | Date / Date | |
| `settings` | `UserSettings?` | `@Relationship(.cascade, inverse: \UserSettings.userProfile)` |

`@Transient`: `trainingSplit`, `footballDays`, `equipment`, `weightUnit`, `estimatedBMR`. Has `DTO: Codable` (snake_case incl. `identity_label`), `apply(from:)`, `validate()` with `ValidationError`.

> **Divergence from original spec:** Adds `identityLabel` + DTO `identity_label`. Otherwise field-for-field.

### 3.2 UserSettings

Source: `Models/User/UserSettings.swift` → `UserSettings`. **IMPLEMENTED (large superset).**

All spec fields present (`notificationIntensity`, leisure/wake/bedtime minutes, `pomodoroDuration`/`breakDuration`/`longBreakDuration`, `weekendMode`/`examMode`/`examModeEndDate`). 1:1 `@Relationship(.nullify)` back to `UserProfile`.

> **Divergence from original spec:** Adds ~20 fields beyond spec: per-notification toggles (`morningBriefingEnabled`, `accountabilityEnabled`, `recoveryEnabled`, `mealRemindersEnabled`, `bedtimeReminderEnabled`, `streakWarningEnabled`, `arenaNotificationsEnabled`, `weeklyReportEnabled`, `trainingReminderEnabled`, `soundEnabled`), quiet hours (`quietHoursEnabled`/`Start`/`EndMinutes`), training mirrors (`trainingSplitRaw`, `weightUnitRaw`, `footballDaysRaw`), `autoStartRestTimer`, `showPlateCalculator`, `autoDeload`, `deloadFrequencyWeeks`, `focusTimerEnabled`, `dailyXPGoalRaw`, `leagueRaw`. DTO mirrors all of these.

---

## 4. Dashboard Models

### 4.1 DailySnapshot

Source: `Models/Dashboard/DailySnapshot.swift` → `DailySnapshot`. **IMPLEMENTED (exact + extended block).**

Keyed by `@Attribute(.unique) date`. Carries biometrics (`recoveryScore`, `hrv`, `rhr`, `sleepHours`, `sleepScore`, `strain`), nutrition (`caloriesConsumed`/`calorieTarget`, protein/carbs/fat actual+target, `mealsLogged`/`mealsPlanned`), study (`studyMinutes`/`studyTarget`), movement (`steps`, `activeCalories`, `workoutCompleted`, `workoutTypeRaw`), an extended `spo2`/`skinTemp` block, `dailyScore`, `nonNegotiablesCompleted`/`Total`, `updatedAt`. `@Transient` compliance computeds: `calorieCompliance`, `proteinCompliance`, `studyCompliance`, `nonNegotiableCompliance`, `recoveryZone`, `macrosOnTarget`, `workoutType`. Full snake_case `DTO`.

> **Divergence from original spec:** No `init(from: DTO)` convenience initializer (spec §15.2 references `DailySnapshot(from: dto)`). Apply path is the standard `apply(from:)` pattern instead.

### 4.2 Dashboard View Models

> **Status: N/A — non-persisted.** `BodyQuadrantData`/`FuelQuadrantData`/`MindQuadrantData`/`MoveQuadrantData`/`NonNegotiableItem` are plain structs on `DashboardViewModel`, not `@Model`. Owned by `MODULE_DASHBOARD.md` §2.2 — out of scope for the SwiftData layer.

### 4.3 DailyScoreEntry

See §17.5 — this `@Model` exists in code and schema but was never in the original spec.

---

## 5. Training Models

Source: `Models/Training/*.swift`.

| Model | Source | Status / as-built notes |
|-------|--------|-------------------------|
| `Exercise` | `Exercise.swift` | IMPLEMENTED. **Adds `preferredRestSeconds`**. Cascade to `PlannedExercise`/`ExerciseHistory`/`PersonalRecord`. `@Transient`: muscleGroup, secondaryMuscles, equipment, movementPattern, cues, currentEstimated1RM, allTimePR |
| `WorkoutPlan` | `WorkoutPlan.swift` | IMPLEMENTED. `date`/`typeRaw`/`statusRaw`/`recoveryAdjustment`/`durationMinutes`/`startedAt`/`finishedAt`; cascade `exercises` |
| `PlannedExercise` | `PlannedExercise.swift` | IMPLEMENTED. `order`, `supersetGroup`, nullify links to plan+exercise, cascade `sets` |
| `PlannedSet` | `PlannedSet.swift` | IMPLEMENTED. target/actual reps+weight, `rpe`, `completed`, `restSeconds`, `isWarmup` |
| `ExerciseHistory` | `ExerciseHistory.swift` | IMPLEMENTED. **Adds `setsPerformed`** beyond spec |
| `PersonalRecord` | `PersonalRecord.swift` | IMPLEMENTED. `typeRaw`/`value`/`date`/`workoutPlanID`/`context` |
| `RunSession` | `RunSession.swift` | IMPLEMENTED. **Adds `elevationGainMeters`, `avgCadence`** beyond spec |
| `SetFeedback` | `SetFeedback.swift` | Code-only, undocumented — see §17.4 |

> **Divergence from original spec:** `Exercise.preferredRestSeconds`, `ExerciseHistory.setsPerformed`, `RunSession.elevationGainMeters`/`avgCadence` are all supersets. `SetFeedback` is an entirely new model (§17.4).

---

## 6. Accountability Models

Source: `Models/Accountability/*.swift`.

| Model | Source | Status / as-built notes |
|-------|--------|-------------------------|
| `NonNegotiable` | `NonNegotiable.swift` | IMPLEMENTED. `name`/`typeRaw`/`icon`/`targetValue`/`trackingMethodRaw`/`activeDaysRaw`/`order`/`isActive`/`createdAt`; cascade `progressEntries`. `isActive` is the soft-delete flag (see §14) |
| `DailyAccountability` | `DailyAccountability.swift` | IMPLEMENTED. unique `date`, `leisureUnlocked`/`unlockedAt`, `totalStudyMinutes`, `accountabilityScore`; cascade `nonNegotiableProgress` + `studySessions` |
| `NonNegotiableProgress` | `NonNegotiableProgress.swift` | IMPLEMENTED. **Adds `wasSkipped` (default false)** and `sourceDataJSON`/`sourceData` accessor beyond spec |
| `StudySession` | `StudySession.swift` | IMPLEMENTED. start/end, `durationMinutes`, `subject`, `sessionTypeRaw`, `focusScore`, `distractions`, `completedPomodoros` |
| `Streak` | `Streak.swift` | IMPLEMENTED. `typeRaw`, `currentCount`, `longestCount`, `lastCompletedDate`, `freezesUsed`/`freezesAvailable` |

> **Divergence from original spec:** `NonNegotiableProgress` adds `wasSkipped` + `sourceDataJSON`.

---

## 7. Recovery Models

Source: `Models/Recovery/*.swift`.

| Model | Source | Status / as-built notes |
|-------|--------|-------------------------|
| `DailyRecovery` | `DailyRecovery.swift` | IMPLEMENTED (**large superset**). Adds full sleep-stage breakdown: `sleepEfficiency`, `sleepConsistency`, `deepSleepMin`, `remSleepMin`, `lightSleepMin`, `awakeMin`, `sleepNeededBaseline`, `sleepDebt`, plus `respiratoryRate`, `avgHR`, `maxHR`, `caloriesBurned`. Unique `date`; cascade `prescription` |
| `DailyPrescription` | `DailyPrescription.swift` | IMPLEMENTED. `trainingRec`/`trainingDetail`, `nutritionRecsJSON`, `bedtimeTarget`, `caffeineCutoff`, `hydrationTargetMl`, `warningsJSON`, `wasFollowed`; nullify link to `DailyRecovery` |
| `RecoveryInsight` | `RecoveryInsight.swift` | IMPLEMENTED. `typeRaw`/`title`/`body`/`dataPointsJSON`/`confidence`/`wasDismissed`/`dismissedAt`. Type enum extended (§2) |

> **Divergence from original spec:** `DailyRecovery` is a substantial superset (sleep-stage + respiratory + HR + calories).

---

## 8. Arena Models

Source: `Models/Arena/*.swift`.

| Model | Source | Status / as-built notes |
|-------|--------|-------------------------|
| `XPEvent` | `XPEvent.swift` | IMPLEMENTED. `date`/`sourceRaw`/`amount`/`eventDescription`/`createdAt`; `@Transient` `source`, `isPenalty` |
| `Achievement` | `Achievement.swift` | IMPLEMENTED. unique `badgeID`, `name`/`achievementDescription`/`categoryRaw`/`rarityRaw`/`xpReward`/`earnedAt`/`isHidden`/`progressValue`/`targetValue` |
| `ChallengeLocal` | `ChallengeLocal.swift` | IMPLEMENTED. `serverID`/`name`/`metric`/`startDate`/`endDate`/`myScore`/`isActive`/`challengeDescription`/`participantCount`/`myRank` |
| `ActivityEvent` | `ActivityEvent.swift` | Code-only, undocumented — see §17.6 |

---

## 9. Sync Models

Source: `Models/Sync/*.swift`.

| Model | Source | Status / as-built notes |
|-------|--------|-------------------------|
| `SyncState` | `SyncState.swift` | IMPLEMENTED. unique `entityType`, `lastSyncedAt`, `lastServerVersion`, `pendingChangesCount`; `@Transient` `hasPendingChanges`, `timeSinceLastSync`, `isStale` |
| `PendingSync` | `PendingSync.swift` | IMPLEMENTED. `entityType`/`entityID`/`actionRaw`/`payload`/`createdAt`/`retryCount`/`lastError`/`nextRetryAt`; `@Transient` `action`, `isReadyForRetry`, `isExhausted` |

These models exist and persist, but the coordinator that consumes them is mocked — see §13/§15.

---

## 10. Integration State Models

### 10.1 WhoopConnection

Source: `Models/Integrations/WhoopConnection.swift` → `WhoopConnection`. **IMPLEMENTED (superset).**

`isConnected`, `lastSyncAt`, `tokenExpiresAt`, `whoopUserID`, `statusMessage`, **`didBackfill` (default false — beyond spec)**. `@Transient` `isTokenExpired`, `lastSyncFormatted`.

> **Divergence from original spec:** Adds `didBackfill` (gates first-connect historical backfill).

### 10.2 NutriTrackConnection

> **Status: NOT IMPLEMENTED.** This model does not exist anywhere in the codebase (0 references) and is not registered in `TempoSchemaV1`. The original spec assumed nutrition integration via a NutriTrack proxy with a persisted connection record. The app instead owns nutrition natively via the Nutrition model family (§17.7); there is no separate connection-state model for it. Header preserved for audit trail only.

### 10.3 HealthKitState

Source: `Models/Integrations/HealthKitState.swift` → `HealthKitState`. **IMPLEMENTED.**

`authorizedReadTypesJSON`/`authorizedWriteTypesJSON` (Data, with `@Transient` `[String]` accessors), `lastBackgroundDelivery`, `authorizationRequested`.

---

## 11. Query Patterns Per Screen

> **Status: PARTIAL.** `@Query` / `FetchDescriptor` are used across ~20 view files (`Views/Training/WorkoutHistoryView.swift`, `ExerciseLibraryView.swift`, `ProgressChartsView.swift`, `Views/Accountability/StreakCalendarView.swift`, `LockdownMainView.swift`, `FocusHistoryView.swift`, etc.). The iOS-17 constraint holds: predicates inline date math or use `FetchDescriptor`; date keys are normalized to `startOfDay` at insert in model inits (e.g. `DailySnapshot`).

> **Divergence from original spec:** The §11.1–11.13 per-screen predicate table is **not verified one-to-one against code**. The query mechanism is implemented in spirit; exact predicate conformance per documented screen is not exhaustively confirmed and should not be treated as ground truth. Read the view file's `@Query` declaration directly when the precise predicate matters.

---

## 12. Indexes & Performance

> **Status: conformant by design.** No `#Index` declarations exist (grep `#Index` → none). The spec explicitly says **do not** add `#Index` for iOS-17 targets and rely on `@Attribute(.unique)` instead — every date/id key carries `.unique`, so this is conformant, not a gap.

Prefetching / batch-size / perf guidance (§12.2–12.4) is advisory only; there is no central enforcement point. Date normalization at insert is implemented in model initializers.

---

## 13. Sync Conflict Resolution

> **Status: NOT IMPLEMENTED (real coordinator).** `SyncCoordinatorProtocol.swift` defines `SyncConflict`, `SyncResolution`, and `protocol SyncCoordinatorProtocol` (`syncAll`/`uploadPending`/`downloadUpdates`/`resolveConflicts`). The **only** implementation is `MockSyncCoordinator` (`Services/Sync/MockSyncCoordinator.swift`): `syncAll`/`uploadPending`/`downloadUpdates` just log; `resolveConflicts` does a naive `remoteUpdatedAt > localUpdatedAt ? .keepRemote : .keepLocal` over the conflict list.
>
> The spec's §13.2 per-model strategy table and §13.3 field-level `mergeDailySnapshot` are entirely absent (grep `mergeDailySnapshot` → none). There is no real sync coordinator, no per-model merge, no field-level last-writer-wins. `SyncState`/`PendingSync` models persist but nothing real consumes them yet.

---

## 14. Data Lifecycle & Cleanup

> **Status: NOT IMPLEMENTED.** No retention/cleanup/purge service exists (grep `retention`/`cleanup`/`purge`/`CleanupService` in `Services/` → none). The spec's §14.1 retention policies and §14.2 scheduled cleanup job are not built. The only lifecycle mechanism present is `NonNegotiable.isActive` (soft-delete flag on the model) — there is no scheduled job that acts on it or prunes old `DailySnapshot`/`ExerciseHistory`/`XPEvent` rows.

---

## 15. Thread Safety & ModelContext Patterns

> **Status: PARTIAL.** No `@ModelActor` or explicit background-`ModelContext` pattern exists anywhere. The spec's §15.2 `actor SyncService` / `actor AggregationService` examples are not implemented (consistent with §13 — no real background sync). `BackgroundSyncService.swift` is `@unchecked Sendable` but does not run a background SwiftData context. DTOs (29 `toDTO`/`apply` pairs) are value-type `Codable` and satisfy the Sendable boundary rule. Main-context `@Query` usage in views conforms to the single-context principle.

---

## 16. Migration Strategy

> **Status: NOT IMPLEMENTED — intentional, documented divergence.** There is no `TempoSchemaV2`, no `TempoMigrationPlan: SchemaMigrationPlan`, no `MigrationStage`, and no `migrationPlan:` argument on the `ModelContainer` (grep → only `TempoSchemaV1`).

The original spec defined `TempoSchemaV2` (placeholder), `TempoMigrationPlan` with a `migrateV1toV2` lightweight stage, and wired `migrationPlan:` into the container. **None of that exists.** The app deliberately evolves `TempoSchemaV1` in place. The decision and its rationale are recorded in `TempoModelContainer.create`'s source comment (V2 would require its own duplicated `@Model` classes, and there is no shipped data to migrate pre-launch). A real V2 + migration plan is deferred to the first post-launch breaking schema change. Sections 16.1–16.4 of the original spec (V1→V2 plan, lightweight vs custom, custom-migration template, migration testing) describe infrastructure that does not currently exist.

---

## 17. Undocumented As-Built Model Families

These `@Model` classes are registered in `TempoSchemaV1` and persist, but were never in the original DATA_MODELS spec. Documented here so the census is complete (50 schema models total).

### 17.1 UserDailyPlanProfile (+ ClassBlock, WorkBlock)

Source: `Models/User/UserDailyPlanProfile.swift`.

`UserDailyPlanProfile` — `wakeTimeMinutes`, `sleepTargetHours`, `chronotypeRaw`, `trainingTimePreferenceRaw`, eating-window minutes + `eatingWindowPresetRaw`, `breakfastSkipped`, `postWorkoutMandatory`, `studySessionLengthMinutes`, `weekendDifferentialRaw`, `termStartDate`/`termEndDate`, `examScheduleMigratedAt`, `updatedAt`. Cascade relationships to `classBlocks` and `workBlocks`. `@Transient` enum accessors + nested `DTO`/`ClassBlockDTO`/`WorkBlockDTO`.

`ClassBlock` — `weekday`, `startMinuteOfDay`/`endMinuteOfDay`, `courseCode`, `courseName?`, `location?`, nullify `profile`.
`WorkBlock` — `weekday`, `startMinuteOfDay`/`endMinuteOfDay`, `label`, nullify `profile`.

### 17.2 DayPlan (+ TimeBlock)

Source: `Models/Schedule/DayPlan.swift`.

`DayPlan` — unique `date`, `generatedAt`, cascade `blocks: [TimeBlock]`.
`TimeBlock` — `kindRaw` (`TimeBlockKind`), `startMinuteOfDay`/`endMinuteOfDay`, `title`, `copy?`, `sourceId?`, nullify `plan`; `@Transient` `kind`, `durationMinutes`.

### 17.3 SetFeedback

Source: `Models/Training/SetFeedback.swift`. `capturedAt`, nullify `plannedSet`, `setID`, `rpe`, `breathDifficultyRaw` (`BreathDifficulty`), `formQualityRaw` (`FormQuality`), `note?`; `@Transient` `breathDifficulty`, `formQuality`. Per-set training feedback capture.

### 17.4 DailyScoreEntry

Source: `Models/Dashboard/DailyScoreEntry.swift`. Minimal: unique `id`, unique `date`, `score: Int`, `updatedAt`. A persisted daily-score history row, distinct from `DailySnapshot.dailyScore`.

### 17.5 ActivityEvent

Source: `Models/Arena/ActivityEvent.swift`. `timestamp`, `eventTypeRaw` (`ActivityEventType`), `title`, `subtitle?`, `xpAwarded`, `iconName`; `@Transient` `eventType`, `timeAgo`. Arena activity-feed entries.

### 17.6 Nutrition Family (17 @Model classes)

Source: `Models/Nutrition/*.swift`. This is the app's native nutrition layer — it replaces the spec's NutriTrack-proxy assumption (§10.2) entirely.

| Model | Source | Key fields |
|-------|--------|-----------|
| `MealLog` | `MealLog.swift` | `mealTypeRaw`, `loggedAt`, `photoData?`, total kcal/P/C/F/fiber, `sourceRaw`, `syncedToHealthKit`/`syncedToBackend`, `dayDate`; cascade `items` |
| `MealFoodItem` | `MealFoodItem.swift` | name/brand/barcode, serving size+label+quantity, per-serving macros, `dataSourceRaw`, `usdaFdcId?`/`offProductCode?`; nullify `mealLog` |
| `NutritionTarget` | `NutritionTarget.swift` | calorie+macro targets, `mealsPerDay`, `effectiveFrom`, `isActive` |
| `CachedFood` | `CachedFood.swift` | **`id: String`** (unique), name/brand, serving, macros, `sourceRaw`, `searchKeywords`, `cachedAt`, `useCount` |
| `DietaryProfile` | `DietaryProfile.swift` | allergen/diet booleans, `cookingSkillRaw`, allergies/disliked JSON, `primaryGoalRaw`, body metrics, `biologicalSexRaw`, `skillLevelRaw`, `isActive` |
| `WeeklyMealPlan` | `WeeklyMealPlan.swift` | `startDate`/`endDate`, `dayTypeAssignmentsJSON`, `isActive`, `generatedAt`; cascade `meals` |
| `PlannedMeal` | `PlannedMeal.swift` | `dayDate`, `mealNumber`, `mealName`, `scheduledTime`, `foodsJSON`, totals, `statusRaw`, `linkedMealLogID?`, `actualEatenAt?`, `eatDurationMinutes`; nullify `mealPlan`, cascade `recipe` |
| `MealPreset` | `MealPreset.swift` | `name`, `foodItemsJSON`, totals, `mealTypeRaw`, `useCount`, `lastUsedAt?` |
| `MealFeedback` | `MealFeedback.swift` | nullify `plannedMeal`, `recipeID?`/`recipeName?`, `mealNumber`, `rating?`, notes, `mealFeelRaw?`, substitute fields, `ingredientNotesJSON` |
| `PantryItem` | `PantryItem.swift` | `canonicalName`/`displayName`, `quantity`, `unitRaw`, `storageLocationRaw`, `isCooked`/`isPrepped`/`preppedOn?`, purchase + best-before/use-by, `isArchived` |
| `Receipt` | `Receipt.swift` | store/location, `purchaseDate`, `totalAmount`, OCR status/provider/raw, `userReviewed`; cascade `lineItems` |
| `ReceiptLineItem` | `ReceiptLineItem.swift` | nullify `receipt`, raw+canonical+display name, quantity/unit/grams, pricing, `onSale`, `confidence`, `userConfirmed`, `linkedPantryItemID?` |
| `Recipe` | `Recipe.swift` | name/slug/description/cuisine, `mealTypeRaw`, servings, prep/cook minutes, difficulty/skill, equipment+dietary JSON, totals, source, `timesCooked`, `userRating?`, `isFavorite`/`isArchived`; cascade `ingredients`+`steps` |
| `RecipeIngredient` | `Recipe.swift` | nullify `recipe`, `orderIndex`, canonical+display name, `quantityGrams`, optional macros, `isOptional`, `isCollected`, `substitutesJSON`, `storageLocationRaw?`, `defrostLeadTimeHours`, `expiryDate?` |
| `RecipeStep` | `Recipe.swift` | nullify `recipe`, `orderIndex`, `instruction`, `durationMinutes?`, `temperature?`, `equipment?`, `isComplete` |
| `GroceryList` | `GroceryList.swift` | `weekStartDate`, `sourceMealPlanID?`, `generatedAt`, `exportedToReminders`/`exportedAt?`; cascade `items` |
| `GroceryListItem` | `GroceryList.swift` | nullify `list`, canonical+display name, `quantity`, `unitRaw`, `category`, `isChecked`, `notes?` |

> **Note:** `Models/Nutrition/MealPlanIntake.swift` and `WizardLaunchSnapshot.swift` define **value-type structs** (wizard intake DTOs / launch snapshots), not `@Model` classes — they are not persisted and are excluded from the model census.

> **Divergence from original spec:** The entire nutrition domain is native SwiftData (17 persisted models + value-type wizard DTOs), not an external NutriTrack proxy with a single `NutriTrackConnection` record. `RecipeIngredient.storageLocation`/`defrostLeadTimeHours`/`expiryDate` and `PlannedMeal.eatDurationMinutes`/`recipe` are exactly the fields cited in the §16 V1-in-place rationale.

---

## Appendix A: Model Census

50 `@Model` classes registered in `TempoSchemaV1`:

- **Documented & implemented (25):** UserProfile, UserSettings, DailySnapshot, WorkoutPlan, PlannedExercise, PlannedSet, Exercise, ExerciseHistory, PersonalRecord, RunSession, NonNegotiable, DailyAccountability, NonNegotiableProgress, StudySession, Streak, DailyRecovery, DailyPrescription, RecoveryInsight, XPEvent, Achievement, ChallengeLocal, SyncState, PendingSync, WhoopConnection, HealthKitState. *(11 of these are supersets — see §3,5,6,7,10.)*
- **Documented but missing (1):** NutriTrackConnection (§10.2).
- **Undocumented in original spec, present in code (25):** UserDailyPlanProfile, ClassBlock, WorkBlock, DayPlan, TimeBlock, SetFeedback, DailyScoreEntry, ActivityEvent, MealLog, MealFoodItem, NutritionTarget, CachedFood, DietaryProfile, WeeklyMealPlan, PlannedMeal, MealPreset, MealFeedback, PantryItem, Receipt, ReceiptLineItem, Recipe, RecipeIngredient, RecipeStep, GroceryList, GroceryListItem.

Census math: 26 spec models − 1 missing (NutriTrackConnection) + 25 undocumented = 50 registered.

## Appendix B: Delete Rule Summary

Cascade owners: `UserProfile→settings`, `UserDailyPlanProfile→classBlocks/workBlocks`, `DayPlan→blocks`, `Exercise→plannedExercises/history/personalRecords`, `WorkoutPlan→exercises`, `PlannedExercise→sets`, `NonNegotiable→progressEntries`, `DailyAccountability→nonNegotiableProgress/studySessions`, `DailyRecovery→prescription`, `WeeklyMealPlan→meals`, `MealLog→items`, `PlannedMeal→recipe`, `Receipt→lineItems`, `Recipe→ingredients/steps`, `GroceryList→items`. All inverse/child links use `.nullify`.

## Appendix C: Storage

No storage-estimate enforcement exists in code; estimates from the original spec are design notes only. Retention is unbounded (see §14).
