# Tempo -- Exhaustive Testing Strategy

> **Version:** 1.0.0
> **Last Updated:** 2026-03-24
> **Author:** QA Architecture Team
> **Audience:** All engineers contributing to Tempo iOS app and Vapor backend

---

## Table of Contents

1. [Testing Philosophy](#1-testing-philosophy)
2. [Unit Tests -- iOS](#2-unit-tests----ios)
3. [Unit Tests -- Backend (Vapor)](#3-unit-tests----backend-vapor)
4. [Integration Tests](#4-integration-tests)
5. [UI Tests (XCUITest)](#5-ui-tests-xcuitest)
6. [Snapshot Tests](#6-snapshot-tests)
7. [Performance Tests](#7-performance-tests)
8. [API Contract Tests](#8-api-contract-tests)
9. [Edge Case Tests](#9-edge-case-tests)
10. [Accessibility Tests](#10-accessibility-tests)
11. [CI/CD Pipeline](#11-cicd-pipeline)
12. [Test Data & Mocks](#12-test-data--mocks)
13. [Manual Testing Checklist](#13-manual-testing-checklist)

---

## 1. Testing Philosophy

### 1.1 Testing Pyramid

Tempo follows a strict testing pyramid. The ratio of tests by category:

```
          /  E2E (UI)  \          ~10%   (~40 tests)
         / Integration  \         ~20%   (~80 tests)
        /   Unit Tests   \        ~70%   (~300+ tests)
       /___________________\
```

- **Unit tests (~70%):** Fast, isolated, no I/O. Every engine, service method, and data transformation has dedicated unit tests. Target execution: full suite under 15 seconds.
- **Integration tests (~20%):** Verify the seams between components -- API client to mock server, HealthKit queries against mock stores, SwiftData migrations, Vapor controller to database.
- **E2E / UI tests (~10%):** XCUITest flows that exercise full user journeys through the running app. Slow, expensive, reserved for critical happy paths and regression-prone flows.

### 1.2 What to Test

**Always test:**
- Every public method on every Engine (`TrainingEngine`, `RecoveryEngine`, `ScoringEngine`)
- Every state transition (locked/unlocked, streak increment/reset, XP gain/penalty)
- Every boundary condition in algorithms (recovery zone thresholds at 33/34, 66/67)
- Data transformations between API responses and local models
- Error paths: network failures, missing permissions, corrupt data, nil optionals
- Notification scheduling logic (time calculations, tier selection, suppression)

**Never test:**
- SwiftUI view layout (use snapshot tests instead of asserting on frames)
- Apple framework internals (do not test that `HKHealthStore.requestAuthorization` calls Apple's servers)
- Auto-generated SwiftData CRUD (test your queries and predicates, not `insert`/`delete`)
- Third-party library internals (trust Vapor's routing, Alamofire's networking -- test your usage of them)

### 1.3 Test Naming Convention

All test methods follow this pattern:

```
test_<methodOrBehavior>_<scenario>_<expectedResult>
```

Examples:
```swift
func test_generateWorkout_greenRecovery_fullVolumeReturned()
func test_calculateDailyScore_noWhoopData_usesHealthKitFallback()
func test_applyStreakFreeze_noFreezesRemaining_streakResets()
func test_refreshToken_replayDetected_allSessionsRevoked()
```

### 1.4 Test Organization (Folder Structure)

```
TempoTests/
├── Unit/
│   ├── Engines/
│   │   ├── TrainingEngineTests.swift
│   │   ├── RecoveryEngineTests.swift
│   │   └── ScoringEngineTests.swift
│   ├── Services/
│   │   ├── HealthKitServiceTests.swift
│   │   ├── WhoopServiceTests.swift
│   │   ├── NutriTrackServiceTests.swift
│   │   ├── CalendarServiceTests.swift
│   │   ├── NotificationServiceTests.swift
│   │   └── SyncServiceTests.swift
│   └── Models/
│       ├── DailySnapshotTests.swift
│       ├── WorkoutPlanTests.swift
│       └── XPCalculationTests.swift
├── Integration/
│   ├── WhoopIntegrationTests.swift
│   ├── NutriTrackIntegrationTests.swift
│   ├── HealthKitIntegrationTests.swift
│   ├── SwiftDataMigrationTests.swift
│   └── SyncCoordinatorTests.swift
├── Snapshot/
│   ├── DashboardSnapshotTests.swift
│   ├── TrainingSnapshotTests.swift
│   ├── AccountabilitySnapshotTests.swift
│   ├── RecoverySnapshotTests.swift
│   ├── ArenaSnapshotTests.swift
│   └── OnboardingSnapshotTests.swift
├── Mocks/
│   ├── MockHealthKitStore.swift
│   ├── MockWhoopAPI.swift
│   ├── MockNutriTrackAPI.swift
│   ├── MockNotificationCenter.swift
│   ├── MockCalendarStore.swift
│   └── Factories/
│       ├── DailySnapshotFactory.swift
│       ├── WorkoutPlanFactory.swift
│       ├── ExerciseFactory.swift
│       ├── UserFactory.swift
│       └── XPEventFactory.swift
└── Helpers/
    ├── DateHelpers.swift
    ├── AssertionHelpers.swift
    └── TestConstants.swift

TempoUITests/
├── Flows/
│   ├── OnboardingFlowTests.swift
│   ├── DashboardFlowTests.swift
│   ├── TrainingFlowTests.swift
│   ├── AccountabilityFlowTests.swift
│   ├── RecoveryFlowTests.swift
│   └── ArenaFlowTests.swift
├── Helpers/
│   ├── XCUIElementExtensions.swift
│   └── TestLaunchArguments.swift
└── Pages/
    ├── DashboardPage.swift
    ├── TrainingPage.swift
    ├── LockdownPage.swift
    ├── RecoveryPage.swift
    └── ArenaPage.swift

tempo-backend/Tests/
├── Unit/
│   ├── Controllers/
│   │   ├── AuthControllerTests.swift
│   │   ├── ArenaControllerTests.swift
│   │   ├── WhoopControllerTests.swift
│   │   ├── NutriTrackControllerTests.swift
│   │   └── SyncControllerTests.swift
│   ├── Services/
│   │   ├── WhoopServiceTests.swift
│   │   ├── NutriTrackServiceTests.swift
│   │   ├── PushNotificationServiceTests.swift
│   │   └── AIServiceTests.swift
│   └── Middleware/
│       ├── JWTMiddlewareTests.swift
│       └── RateLimitMiddlewareTests.swift
├── Integration/
│   ├── DatabaseMigrationTests.swift
│   ├── WhoopOAuthFlowTests.swift
│   └── FullSyncFlowTests.swift
└── Mocks/
    ├── MockWhoopClient.swift
    ├── MockNutriTrackClient.swift
    └── MockAPNsClient.swift
```

---

## 2. Unit Tests -- iOS

### 2.1 HealthKitService Tests

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| HK-001 | `test_requestAuthorization_allTypes_callsHealthStore` | MockHealthKitStore injected | Call `requestAuthorization()` | Store receives request for all read types (stepCount, activeEnergyBurned, heartRate, heartRateVariabilitySDNN, restingHeartRate, sleepAnalysis, workoutType) and write types (dietaryEnergyConsumed, workoutType) |
| HK-002 | `test_requestAuthorization_userDeniesAll_returnsPermissionDenied` | Mock returns authorization denied | Call `requestAuthorization()` | Method returns `.permissionDenied` error; no data queries are attempted |
| HK-003 | `test_queryStepCount_withMockData_returnsCorrectTotal` | Mock store seeded with 3 step samples: 2000, 3500, 1500 for today | Call `fetchStepCount(for: today)` | Returns 7000 steps |
| HK-004 | `test_queryStepCount_noData_returnsZero` | Mock store has no step samples for today | Call `fetchStepCount(for: today)` | Returns 0, not nil |
| HK-005 | `test_queryStepCount_futureDate_returnsZero` | Mock store has data only for today | Call `fetchStepCount(for: tomorrow)` | Returns 0 |
| HK-006 | `test_queryHeartRate_permissionDenied_returnsEmptyArray` | Mock store returns authorization status `.sharingDenied` for heart rate | Call `fetchHeartRateSamples(for: today)` | Returns empty array, no error thrown |
| HK-007 | `test_queryHeartRate_withMockData_returnsSortedSamples` | Mock store seeded with 5 HR samples at different timestamps | Call `fetchHeartRateSamples(for: today)` | Returns 5 samples sorted ascending by timestamp |
| HK-008 | `test_queryWorkouts_multipleSources_returnsAll` | Mock store seeded with 2 Apple Watch workouts and 1 Whoop workout | Call `fetchWorkouts(for: today)` | Returns 3 workouts, each with correct source identifier |
| HK-009 | `test_queryWorkouts_filterByType_returnsOnlyMatching` | Mock store has running and strength workouts | Call `fetchWorkouts(for: today, type: .running)` | Returns only running workouts |
| HK-010 | `test_querySleep_withStages_returnsAllStages` | Mock store seeded with awake, light, deep, REM samples | Call `fetchSleepAnalysis(for: lastNight)` | Returns all 4 stage types with correct durations |
| HK-011 | `test_backgroundDelivery_registration_enabledForRequiredTypes` | MockHealthKitStore injected | Call `enableBackgroundDelivery()` | Background delivery enabled for stepCount, workoutType, and sleepAnalysis with `.immediate` frequency |
| HK-012 | `test_backgroundDelivery_alreadyEnabled_doesNotReRegister` | Background delivery previously enabled | Call `enableBackgroundDelivery()` twice | Second call is a no-op; no duplicate registrations |
| HK-013 | `test_writeWorkout_validData_savesToStore` | MockHealthKitStore writable | Call `saveWorkout(type: .traditionalStrengthTraining, start: t0, end: t1, calories: 350)` | Workout saved to mock store with correct metadata |
| HK-014 | `test_writeWorkout_writePermissionDenied_throwsError` | Mock store denies write permission | Call `saveWorkout(...)` | Throws `HealthKitError.writePermissionDenied` |
| HK-015 | `test_queryActiveEnergy_returnsKilocalories` | Mock store has energy samples in different units | Call `fetchActiveEnergy(for: today)` | Returns total in kilocalories regardless of source unit |

### 2.2 TrainingEngine Tests

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| TE-001 | `test_generateWorkout_greenRecovery_fullVolumeReturned` | Recovery score = 82% (green zone) | Call `generateWorkout(for: today, recovery: .green(82))` | Workout has `recoveryAdjustment == 1.0`; all exercises have standard volume |
| TE-002 | `test_generateWorkout_yellowRecovery_reducedVolume` | Recovery score = 55% (yellow zone) | Call `generateWorkout(for: today, recovery: .yellow(55))` | `recoveryAdjustment` between 0.75-0.85; total sets reduced by ~20% from baseline |
| TE-003 | `test_generateWorkout_redRecovery_mobilitySubstituted` | Recovery score = 25% (red zone) | Call `generateWorkout(for: today, recovery: .red(25))` | `type == .mobility`; no heavy compound movements; volume reduced 30-40% |
| TE-004 | `test_generateWorkout_redRecoveryVeryLow_restDayReturned` | Recovery score = 12% | Call `generateWorkout(for: today, recovery: .red(12))` | `type == .rest`; no exercises |
| TE-005 | `test_generateWorkout_noHeavyLegsBeforeFootball` | Tomorrow has a football calendar event | Call `generateWorkout(for: today)` where `today` is day before football | Workout type is NOT `.legs`; no squats, deadlifts, or leg press in exercise list |
| TE-006 | `test_generateWorkout_footballDay_restOrUpperMobility` | Today has a football calendar event | Call `generateWorkout(for: today)` where football is today | `type` is `.rest` or `.mobility` or upper-body-only; no lower body movements |
| TE-007 | `test_generateWorkout_pplSplit_correctRotation` | Last 3 workouts were Push, Pull, Legs | Call `generateWorkout(for: today)` | Returns Push workout (rotation resets) |
| TE-008 | `test_generateWorkout_missedDay_doesNotSkipInRotation` | Rotation = Push next, but yesterday was rest | Call `generateWorkout(for: today)` | Returns Push (does not skip to Pull) |
| TE-009 | `test_progressiveOverload_twoOfThreeSuccessful_triggersIncrease` | Exercise history: 80kg x 8 (success), 80kg x 8 (success), 80kg x 6 (fail -- 2 of 3 recent sessions hit target) | Call `calculateNextWeight(for: benchPress)` | Returns 82.5kg (2.5kg increment for upper body compound) |
| TE-010 | `test_progressiveOverload_oneOfThreeSuccessful_maintainsWeight` | Exercise history: 80kg x 8 (success), 80kg x 6 (fail), 80kg x 5 (fail) | Call `calculateNextWeight(for: benchPress)` | Returns 80kg (no change) |
| TE-011 | `test_progressiveOverload_allThreeSuccessful_triggersIncrease` | Exercise history: 100kg x 5 (hit), 100kg x 5 (hit), 100kg x 5 (hit) | Call `calculateNextWeight(for: squat)` | Returns 105kg (5kg increment for lower body compound) |
| TE-012 | `test_deloadWeek_triggeredAfterFourWeeks` | 4 consecutive weeks of training without deload; progressive overload stalling on 2+ exercises | Call `shouldDeload(weekNumber: 5)` | Returns `true`; generated workout has all weights at ~60% of working weight |
| TE-013 | `test_deloadWeek_notTriggeredWeekThree` | 3 weeks into mesocycle, progression normal | Call `shouldDeload(weekNumber: 3)` | Returns `false` |
| TE-014 | `test_exerciseSubstitution_equipmentUnavailable` | User marked "no cable machine" in settings | Call `generateWorkout(for: today)` for push day | Cable fly replaced with dumbbell fly or pec deck; all equipment-specific exercises substituted |
| TE-015 | `test_exerciseSubstitution_maintainsMuscleGroup` | User requests substitution for bench press | Call `substituteExercise(benchPress, reason: .preference)` | Replacement targets same primary muscle group (chest) and is compound |
| TE-016 | `test_supersetGrouping_pairsAntagonists` | Push day workout generated | Inspect exercise list for superset groupings | Supersets pair antagonist muscles (e.g., tricep pushdown + bicep curl) or non-competing movements (e.g., cable fly + lateral raise) |
| TE-017 | `test_supersetGrouping_assignsCorrectGroupIds` | Workout with 2 superset pairs | Inspect `supersetGroup` on exercises | Superset pairs share the same `supersetGroup` ID; non-superset exercises have `nil` |
| TE-018 | `test_volumeCalculation_totalSetsPerMuscle` | Generated push workout | Call `calculateVolume(for: workout)` | Returns dictionary: `{chest: 12, shoulders: 6, triceps: 6}` sets (example) |
| TE-019 | `test_volumeCalculation_weeklyTotal` | 6 workouts completed this week | Call `calculateWeeklyVolume()` | Returns per-muscle-group weekly totals; verifies chest has 15-20 sets/week |
| TE-020 | `test_oneRMEstimation_epleyFormula` | User logged 100kg x 8 | Call `estimateOneRM(weight: 100, reps: 8)` | Returns 125kg (Epley: `weight * (1 + reps / 30)` = 100 * 1.267 = ~126.7, but verify exact formula) |
| TE-021 | `test_oneRMEstimation_singleRep_returnsWeight` | User logged 140kg x 1 | Call `estimateOneRM(weight: 140, reps: 1)` | Returns 140kg exactly |
| TE-022 | `test_oneRMEstimation_zeroReps_returnsNil` | Invalid input | Call `estimateOneRM(weight: 100, reps: 0)` | Returns nil (invalid input) |
| TE-023 | `test_restTimerDuration_compoundExercise_longerRest` | Exercise is bench press (compound, heavy) | Call `recommendedRestTime(for: benchPress, intensity: .heavy)` | Returns 180 seconds (3 min) |
| TE-024 | `test_restTimerDuration_isolationExercise_shorterRest` | Exercise is lateral raise (isolation, moderate) | Call `recommendedRestTime(for: lateralRaise, intensity: .moderate)` | Returns 60-90 seconds |
| TE-025 | `test_workoutDurationEstimate_accountsForRestAndTransitions` | Workout with 6 exercises, 24 total sets | Call `estimateDuration(for: workout)` | Returns value between 45-65 minutes; calculation includes set time + rest time + transition time per exercise |
| TE-026 | `test_generateWorkout_recoveryBoundary67_isGreen` | Recovery score = 67% (exact boundary) | Call `generateWorkout(for: today, recovery: .green(67))` | Treated as green zone, full volume |
| TE-027 | `test_generateWorkout_recoveryBoundary66_isYellow` | Recovery score = 66% | Call `generateWorkout(for: today, recovery: .yellow(66))` | Treated as yellow zone, reduced volume |
| TE-028 | `test_generateWorkout_recoveryBoundary34_isYellow` | Recovery score = 34% | Call `generateWorkout(for: today, recovery: .yellow(34))` | Treated as yellow zone |
| TE-029 | `test_generateWorkout_recoveryBoundary33_isRed` | Recovery score = 33% | Call `generateWorkout(for: today, recovery: .red(33))` | Treated as red zone |

### 2.3 RecoveryEngine Tests

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| RE-001 | `test_prescription_greenRecovery_fullSendTraining` | Recovery = 78%, sleep = 7.5h, HRV trending up | Call `generatePrescription(recovery: 78, ...)` | `trainingRec` == "Full send"; no warnings |
| RE-002 | `test_prescription_yellowRecovery_moderateTraining` | Recovery = 52%, sleep = 6.5h | Call `generatePrescription(recovery: 52, ...)` | `trainingRec` contains "Moderate"; meal timing recommendation included |
| RE-003 | `test_prescription_redRecovery_restOrMobility` | Recovery = 28%, sleep = 4.5h, HRV dropping | Call `generatePrescription(recovery: 28, ...)` | `trainingRec` is "Rest" or "Easy/mobility"; warnings include HRV drop |
| RE-004 | `test_bedtimeCalculation_noSleepDebt_standardBedtime` | Sleep debt = 0h, next day starts at 8 AM | Call `calculateBedtime(sleepDebt: 0, wakeTarget: 8AM)` | Returns ~11:30 PM (8h before wake) |
| RE-005 | `test_bedtimeCalculation_withSleepDebt_earlierBedtime` | Sleep debt = 3h, next day starts at 8 AM | Call `calculateBedtime(sleepDebt: 3, wakeTarget: 8AM)` | Returns earlier than no-debt case (e.g., ~10:30 PM); capped at 1.5h earlier max |
| RE-006 | `test_bedtimeCalculation_largeSleepDebt_cappedAdjustment` | Sleep debt = 10h | Call `calculateBedtime(sleepDebt: 10, ...)` | Adjustment capped; bedtime does not go earlier than 9 PM |
| RE-007 | `test_caffeineCutoff_standardBedtime` | Target bedtime = 11 PM | Call `calculateCaffeineCutoff(bedtime: 11PM)` | Returns 1 PM (10h before bedtime) |
| RE-008 | `test_caffeineCutoff_earlyBedtime` | Target bedtime = 9:30 PM | Call `calculateCaffeineCutoff(bedtime: 9:30PM)` | Returns 11:30 AM |
| RE-009 | `test_hydrationTarget_70kgBodyWeight_normalStrain` | Body weight = 70kg, strain = 10 (moderate) | Call `calculateHydrationTarget(weight: 70, strain: 10)` | Returns ~2800-3200 mL (base: 35-40 mL/kg + strain adjustment) |
| RE-010 | `test_hydrationTarget_90kgBodyWeight_highStrain` | Body weight = 90kg, strain = 18 (high) | Call `calculateHydrationTarget(weight: 90, strain: 18)` | Returns higher than 70kg case; strain adds 500-1000 mL |
| RE-011 | `test_hydrationTarget_lowWeight_minimumFloor` | Body weight = 50kg, strain = 5 | Call `calculateHydrationTarget(weight: 50, strain: 5)` | Returns at least 2000 mL (minimum floor) |
| RE-012 | `test_nutritionAdjustment_highStrainDay_extraCarbs` | Yesterday's strain = 18 (high), recovery = green | Call `generateNutritionRec(strain: 18, ...)` | Recommendation includes extra carbs or increased calorie target |
| RE-013 | `test_nutritionAdjustment_restDay_reducedCalories` | Today is rest day, strain = 3 | Call `generateNutritionRec(strain: 3, ...)` | Recommendation suggests maintenance or slightly reduced calorie target |
| RE-014 | `test_warnings_hrvDroppingThreeDays_warningGenerated` | HRV trend: [65, 58, 52] over last 3 days | Call `generatePrescription(...)` with HRV trend data | `warnings` array contains "HRV dropping 3 days straight" |
| RE-015 | `test_warnings_sleepDebtOverFourHours_warningGenerated` | Sleep debt = 5h | Call `generatePrescription(...)` | `warnings` array contains message about sleep debt > 4h |
| RE-016 | `test_prescription_missingWhoopData_usesDefaults` | No Whoop data available | Call `generatePrescription(recovery: nil, ...)` | Returns a safe default prescription (moderate recommendation); `warnings` contains "No recovery data" |
| RE-017 | `test_recoveryZone_exactBoundary67_isGreen` | Recovery = 67.0% | Call `classifyRecoveryZone(67.0)` | Returns `.green` |
| RE-018 | `test_recoveryZone_exactBoundary34_isYellow` | Recovery = 34.0% | Call `classifyRecoveryZone(34.0)` | Returns `.yellow` |
| RE-019 | `test_recoveryZone_exactBoundary33_isRed` | Recovery = 33.0% | Call `classifyRecoveryZone(33.0)` | Returns `.red` |

### 2.4 ScoringEngine Tests

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| SE-001 | `test_dailyScore_allDataPresent_calculatesCorrectly` | DailySnapshot with all fields populated (recovery, meals, study, workout, sleep) | Call `calculateDailyScore(snapshot)` | Returns score 0-100; all quadrants contribute proportionally |
| SE-002 | `test_dailyScore_noWhoopData_usesHealthKitFallback` | DailySnapshot with `recoveryScore == nil`, but HealthKit has sleep and HR data | Call `calculateDailyScore(snapshot)` | Returns a valid score; Body quadrant uses HealthKit data instead of Whoop |
| SE-003 | `test_dailyScore_noDataAtAll_returnsZero` | DailySnapshot with all optional fields nil | Call `calculateDailyScore(snapshot)` | Returns 0 |
| SE-004 | `test_xpCalculation_workoutCompleted_returns100BaseXP` | User completed a full workout | Call `calculateXP(event: .workoutCompleted, ...)` | Returns 100 XP base |
| SE-005 | `test_xpCalculation_workoutWithGreenRecovery_bonusApplied` | Workout completed + recovery green | Call `calculateXP(event: .workoutCompleted, recovery: .green)` | Returns 100 + 50 = 150 XP |
| SE-006 | `test_xpCalculation_workoutWithYellowRecovery_bonusApplied` | Workout completed + recovery yellow | Call `calculateXP(event: .workoutCompleted, recovery: .yellow)` | Returns 100 + 30 = 130 XP |
| SE-007 | `test_xpCalculation_workoutWithRedRecovery_bonusApplied` | Workout completed + recovery red (still trained) | Call `calculateXP(event: .workoutCompleted, recovery: .red)` | Returns 100 + 20 = 120 XP |
| SE-008 | `test_xpPenalty_missedWorkout_minus50` | Workout was scheduled but not completed, no rest day flag | Call `calculatePenalties(for: today)` | Returns -50 XP penalty for skipped workout |
| SE-009 | `test_xpPenalty_missedWorkout_redRecovery_noPenalty` | Workout was scheduled, not completed, recovery is red | Call `calculatePenalties(for: today)` | Returns 0 penalty (auto-excused by red recovery) |
| SE-010 | `test_xpPenalty_missedStudy_under50Percent_minus30` | Study target = 2h, actual study = 45 min (<50%) | Call `calculatePenalties(for: today)` | Returns -30 XP for missed study |
| SE-011 | `test_xpPenalty_missedStudy_over50Percent_noPenalty` | Study target = 2h, actual = 1h 15m (>50%) | Call `calculatePenalties(for: today)` | No study penalty (threshold is below 50%) |
| SE-012 | `test_xpPenalty_dailyFloor_neverBelowZero` | Multiple penalties totaling -200 XP, daily earnings = 50 XP | Call `calculateNetXP(for: today)` | Returns 0, not negative (daily floor) |
| SE-013 | `test_xpPenalty_totalPenaltyCap_minus150` | Worst possible day: missed workout (-50), missed study (-30), missed all meals (-40), streak broken (-100) | Call `calculatePenalties(for: today)` | Total penalty capped at -150 XP |
| SE-014 | `test_streakMultiplier_7DayStreak_25XPBonus` | Current streak = 7 days | Call `calculateStreakBonus(streak: 7)` | Returns +25 XP per day |
| SE-015 | `test_streakMultiplier_30DayStreak_50XPBonus` | Current streak = 30 days | Call `calculateStreakBonus(streak: 30)` | Returns +50 XP per day |
| SE-016 | `test_levelCalculation_fromXP_correctLevel` | Total XP = 2500 | Call `calculateLevel(totalXP: 2500)` | Returns level 9 (cumulative XP for level 10 is 2655) |
| SE-017 | `test_levelCalculation_exactBoundary` | Total XP = 2655 | Call `calculateLevel(totalXP: 2655)` | Returns level 10 exactly |
| SE-018 | `test_levelCalculation_zeroXP_levelOne` | Total XP = 0 | Call `calculateLevel(totalXP: 0)` | Returns level 1 |
| SE-019 | `test_levelCalculation_veryHighXP` | Total XP = 30288 | Call `calculateLevel(totalXP: 30288)` | Returns level 50 |
| SE-020 | `test_streakFreeze_applied_streakPreserved` | Streak = 14 days, user has 1 freeze available, missed non-negotiables today | Call `applyStreakFreeze(streak: 14)` | Streak remains 14; freeze count decremented by 1 |
| SE-021 | `test_streakFreeze_noFreezesRemaining_streakResets` | Streak = 14 days, 0 freezes available, missed non-negotiables | Call `applyStreakFreeze(streak: 14)` | Streak resets to 0; -100 XP penalty applied (streak was >= 7) |
| SE-022 | `test_xpStepTiers_notCumulative_onlyHighest` | User has 12,000 steps | Call `calculateStepXP(steps: 12000)` | Returns 50 XP (10,000 tier), NOT 20 + 35 + 50 |
| SE-023 | `test_xpStepTiers_exactly8000_returns35` | User has exactly 8,000 steps | Call `calculateStepXP(steps: 8000)` | Returns 35 XP |
| SE-024 | `test_xpStepTiers_below5000_returnsZero` | User has 4,999 steps | Call `calculateStepXP(steps: 4999)` | Returns 0 XP |
| SE-025 | `test_perfectDay_allCriteriaMet_200XPBonus` | Workout done + study target hit + all meals logged + all non-negotiables done + sleep logged | Call `calculateDailyBonuses(for: snapshot)` | Includes +200 XP perfect day bonus |
| SE-026 | `test_nearPerfectDay_fourOfFive_75XPBonus` | 4 of 5 perfect day criteria met (missed sleep logging) | Call `calculateDailyBonuses(for: snapshot)` | Includes +75 XP near-perfect day bonus |
| SE-027 | `test_xpPenalty_weekendStudy_exemptByDefault` | Saturday, study target not met, user has NOT enabled weekend study | Call `calculatePenalties(for: saturday)` | No study penalty |
| SE-028 | `test_xpPenalty_weekendStudy_enabledByUser_applies` | Saturday, study target not met, user enabled weekend study | Call `calculatePenalties(for: saturday)` | -30 XP study penalty applies |
| SE-029 | `test_xpPenalty_restDayFlagBeforeNoon_noPenalty` | User set "Rest Day" flag at 10 AM, workout not completed | Call `calculatePenalties(for: today)` | No workout penalty |
| SE-030 | `test_xpPenalty_restDayFlagAfterNoon_penaltyApplies` | User set "Rest Day" flag at 1 PM | Call `calculatePenalties(for: today)` | -50 XP workout penalty applies (flag was set too late) |

### 2.5 NotificationService Tests

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| NS-001 | `test_tierSelection_2PM_incompleteTasksExist_gentleTier` | Time = 2:00 PM, 3 tasks remaining | Call `selectNotificationTier(time: 2PM, remainingTasks: 3)` | Returns `.gentle` tier with message like "3 tasks left today. You've got this." |
| NS-002 | `test_tierSelection_5PM_incompleteTasksExist_firmTier` | Time = 5:00 PM, 2 tasks remaining | Call `selectNotificationTier(time: 5PM, remainingTasks: 2)` | Returns `.firm` tier |
| NS-003 | `test_tierSelection_630PM_studyIncomplete_urgentTier` | Time = 6:30 PM, study not done | Call `selectNotificationTier(time: 6:30PM, ...)` | Returns `.urgent` tier with specific study time remaining |
| NS-004 | `test_tierSelection_7PM_aggressive` | Time = 7:00 PM, tasks incomplete | Call `selectNotificationTier(time: 7PM, ...)` | Returns `.aggressive` tier with "No PS5 until it's done" language |
| NS-005 | `test_tierSelection_8PM_final` | Time = 8:00 PM, tasks incomplete | Call `selectNotificationTier(time: 8PM, ...)` | Returns `.final` tier; includes option to salvage with partial work |
| NS-006 | `test_notification_allTasksComplete_congratulatory` | All non-negotiables completed | Call `generateCompletionNotification()` | Returns message confirming PS5/leisure is earned |
| NS-007 | `test_quietHours_suppressionDuringSleep` | Time = 11:30 PM, user bedtime = 11 PM | Call `shouldSendNotification(at: 11:30PM)` | Returns `false` (suppressed during quiet hours) |
| NS-008 | `test_quietHours_earlyMorning_suppressed` | Time = 6:00 AM, user wake time = 7 AM | Call `shouldSendNotification(at: 6AM)` | Returns `false` |
| NS-009 | `test_escalation_onlyEscalatesIfPreviousTierSent` | Current time = 7 PM, but 5 PM notification was never sent | Call `selectNotificationTier(...)` | Sends the 5 PM tier first, not the 7 PM tier (fills gap) |
| NS-010 | `test_deduplication_sameMessageWithin30Min_blocked` | Identical notification sent 20 min ago | Call `shouldSendNotification(content: sameContent)` | Returns `false` (dedup window = 30 min) |
| NS-011 | `test_examMode_notificationsIncreaseStudyFocus` | User is in exam mode | Call `generateNotifications(examMode: true)` | Notifications emphasize study; training notifications are suppressed or softened |
| NS-012 | `test_notification_weekendMode_relaxedTiming` | Saturday, user has weekend mode enabled | Call `selectNotificationTier(time: 2PM, ...)` on Saturday | First notification is delayed to 4 PM (weekend schedule) |
| NS-013 | `test_notification_recoveryRedDay_noTrainingNag` | Recovery is red, training task incomplete | Call `generateNotifications(...)` | No notification nagging about training (auto-excused by red recovery) |
| NS-014 | `test_notification_schedulesBatchCorrectly` | 5 notifications scheduled for the day | Call `scheduleAllNotifications(for: today)` | 5 local notifications registered with `UNUserNotificationCenter` at correct times |

---

## 3. Unit Tests -- Backend (Vapor)

### 3.1 AuthController Tests

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| BA-001 | `test_appleAuth_validToken_createsUserAndReturnsJWT` | Valid identity token, authorization code, nonce | POST `/v1/auth/apple` with valid body | 200 OK; response contains `access_token`, `refresh_token`, `user.is_new_user == true` |
| BA-002 | `test_appleAuth_returningUser_loginSuccessful` | User already exists in DB | POST `/v1/auth/apple` with same Apple User ID | 200 OK; `user.is_new_user == false`; `last_login_at` updated |
| BA-003 | `test_appleAuth_expiredToken_returns401` | Identity token has `exp` in the past | POST `/v1/auth/apple` | 401; error code 1006 |
| BA-004 | `test_appleAuth_wrongAudience_returns401` | Identity token `aud` does not match bundle ID | POST `/v1/auth/apple` | 401; error code 1005 |
| BA-005 | `test_appleAuth_malformedToken_returns400` | Identity token is not valid JWT | POST `/v1/auth/apple` with garbage token | 400; error code 1002 |
| BA-006 | `test_appleAuth_nonceMismatch_returns400` | Client nonce does not match token nonce | POST `/v1/auth/apple` | 400; error code 1003 |
| BA-007 | `test_appleAuth_invalidAuthorizationCode_returns400` | Authorization code already used or invalid | POST `/v1/auth/apple` | 400; error code 1004 |
| BA-008 | `test_appleAuth_missingFields_returns400` | Body missing `identity_token` | POST `/v1/auth/apple` | 400; validation error with field-level detail |
| BA-009 | `test_appleAuth_rateLimited_returns429` | 11th request within 1 minute from same IP | POST `/v1/auth/apple` | 429; `Retry-After` header present |
| BA-010 | `test_jwtGeneration_containsCorrectClaims` | User created | Inspect generated JWT | Contains `sub` (user ID), `iss` (api.tempo.app), `aud` (app bundle ID), `exp` (15 min from now), `iat` |
| BA-011 | `test_jwtGeneration_signedWithES256` | JWT generated | Decode JWT header | `alg` == `ES256` |
| BA-012 | `test_refreshToken_validToken_returnsNewPair` | Valid refresh token in DB | POST `/v1/auth/refresh` | 200 OK; new `access_token` + new `refresh_token`; old refresh token revoked |
| BA-013 | `test_refreshToken_rotation_oldTokenInvalidated` | Refresh token used once | Use same refresh token again | 401; error code 1011 (replay detected); ALL refresh tokens for user revoked |
| BA-014 | `test_refreshToken_expired_returns401` | Refresh token past expiry | POST `/v1/auth/refresh` | 401; error code 1009 |
| BA-015 | `test_refreshToken_deviceIdMismatch_returns401` | Refresh token from device A, request from device B | POST `/v1/auth/refresh` with different `X-Device-Id` | 401; error code 1012 |
| BA-016 | `test_logout_revokesAllTokens` | User has 3 active refresh tokens across devices | POST `/v1/auth/logout` | All 3 refresh tokens revoked; subsequent refresh attempts fail |

### 3.2 ArenaController Tests

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| AR-001 | `test_createXPEvent_validData_returnsCreatedEvent` | Authenticated user | POST `/v1/arena/xp` with `{source: "workout", amount: 100, date: "2026-03-24"}` | 201 Created; event stored in DB with correct user_id |
| AR-002 | `test_createXPEvent_negativeAmount_acceptedAsPenalty` | Authenticated user | POST `/v1/arena/xp` with `{source: "streak_break", amount: -100, ...}` | 201 Created; negative XP recorded |
| AR-003 | `test_createXPEvent_duplicateIdempotencyKey_returnsOriginal` | Same idempotency key sent twice | POST `/v1/arena/xp` twice with same `Idempotency-Key` | Second request returns same response without creating duplicate |
| AR-004 | `test_leaderboard_weeklyCalculation_correctRanking` | 3 users with XP: Alice=500, Bob=750, Charlie=300 this week | GET `/v1/arena/leaderboard?period=weekly` | Returns ordered list: Bob (rank 1, 750 XP), Alice (rank 2, 500 XP), Charlie (rank 3, 300 XP) |
| AR-005 | `test_leaderboard_tiedScores_sameRank` | 2 users with identical weekly XP | GET `/v1/arena/leaderboard` | Both users have same rank; next rank skips (1, 1, 3) |
| AR-006 | `test_leaderboard_onlyShowsFriends` | User has 2 friends and there are 10 total users | GET `/v1/arena/leaderboard` | Returns only the user + their 2 friends (3 entries) |
| AR-007 | `test_friendRequest_send_createsPendingFriendship` | User A sends request to User B | POST `/v1/arena/friends/request` with user B's ID | Friendship created with status `pending` |
| AR-008 | `test_friendRequest_accept_activatesFriendship` | Pending request from A to B | POST `/v1/arena/friends/accept` from user B | Friendship status changes to `accepted`; bidirectional |
| AR-009 | `test_friendRequest_decline_removesFriendship` | Pending request from A to B | POST `/v1/arena/friends/decline` from user B | Friendship row deleted |
| AR-010 | `test_friendRequest_duplicate_returns409` | A already sent request to B (pending) | POST `/v1/arena/friends/request` again | 409 Conflict |
| AR-011 | `test_friendRequest_toSelf_returns400` | User tries to friend themselves | POST `/v1/arena/friends/request` with own ID | 400 Bad Request |
| AR-012 | `test_challengeCreation_validData_returnsChallenge` | Authenticated user with friends | POST `/v1/arena/challenges` with valid challenge data | 201 Created; creator auto-added as participant |
| AR-013 | `test_challengeCreation_endDateBeforeStart_returns400` | Invalid dates | POST `/v1/arena/challenges` with `end_date < start_date` | 400 validation error |
| AR-014 | `test_challengeScoring_updatesCorrectly` | Active challenge, user logs study hours | POST `/v1/arena/challenges/{id}/score` | Participant score updated; leaderboard reflects change |
| AR-015 | `test_challengeCompletion_winnerGets200XP` | Challenge ends, User A has highest score | Run end-of-challenge job | User A receives +200 XP event with source "challenge_win" |
| AR-016 | `test_achievementUnlock_firstWorkout_badgeGranted` | User completes first ever workout | POST XP event for workout | Achievement "First Blood" unlocked; returned in response |
| AR-017 | `test_achievementUnlock_noDuplicates` | User already has "First Blood" badge | POST another workout XP event | No duplicate achievement created |
| AR-018 | `test_achievementUnlock_streakBadges_correctThresholds` | Streak reaches 7, 30, 100 days | Process streak events | Badges: "Week Warrior" (7), "Iron Month" (30), "Centurion" (100) unlocked at correct thresholds |

### 3.3 WhoopController Tests

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| WH-001 | `test_oauthCallback_validCode_exchangesForTokens` | Mock Whoop token endpoint returns valid tokens | GET `/v1/whoop/callback?code=VALID_CODE` | Tokens stored in DB encrypted; user's `whoop_connected` = true |
| WH-002 | `test_oauthCallback_invalidCode_returns400` | Mock Whoop token endpoint returns error | GET `/v1/whoop/callback?code=BAD_CODE` | 400; error message about invalid authorization code |
| WH-003 | `test_oauthCallback_missingCode_returns400` | No code parameter | GET `/v1/whoop/callback` (no query params) | 400; missing `code` parameter |
| WH-004 | `test_webhookHMAC_validSignature_accepted` | Valid HMAC-SHA256 signature in header | POST `/v1/webhooks/whoop` with valid body + signature | 200 OK; webhook processed |
| WH-005 | `test_webhookHMAC_invalidSignature_returns401` | Wrong HMAC signature | POST `/v1/webhooks/whoop` with tampered body | 401; webhook rejected |
| WH-006 | `test_webhookHMAC_replayAttack_returns401` | Same webhook ID sent twice within 5 minutes | POST same webhook payload again | 401 or 409; duplicate webhook rejected (idempotency on webhook ID) |
| WH-007 | `test_webhookHMAC_missingSignatureHeader_returns401` | No `X-Whoop-Signature` header | POST `/v1/webhooks/whoop` | 401 |
| WH-008 | `test_tokenRefresh_expiredAccessToken_autoRefreshes` | Whoop access token expired, refresh token valid | Backend attempts Whoop API call | Automatically refreshes token; stores new tokens; retries original request |
| WH-009 | `test_tokenRefresh_bothExpired_marksDisconnected` | Both access and refresh tokens expired | Backend attempts Whoop API call | User's Whoop connection marked as disconnected; push notification sent to reconnect |
| WH-010 | `test_dataSync_recoveryWebhook_updatesUserData` | Valid recovery webhook received | POST `/v1/webhooks/whoop` with recovery payload | User's daily recovery data updated in DB; iOS push notification sent for sync |
| WH-011 | `test_dataSync_sleepWebhook_updatesUserData` | Valid sleep webhook received | POST `/v1/webhooks/whoop` with sleep payload | Sleep data (stages, duration, debt, efficiency) stored correctly |
| WH-012 | `test_dataSync_malformedPayload_returns400` | Webhook body has missing required fields | POST `/v1/webhooks/whoop` with incomplete JSON | 400; error logged; no data corruption |
| WH-013 | `test_dataSync_rateLimited429_retriesWithBackoff` | Whoop API returns 429 | Backend calls Whoop API | Retries up to 3 times with exponential backoff (1s, 2s, 4s) |

---

## 4. Integration Tests

### 4.1 Whoop API Integration

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| WI-001 | `test_fullOAuthFlow_mockWhoopServer_tokenStored` | Mock Whoop OAuth server running | 1. Generate auth URL; 2. Simulate redirect with code; 3. Exchange code for tokens | Tokens encrypted and stored in DB; user profile fetched |
| WI-002 | `test_dataSync_realisticRecoveryPayload_parsedCorrectly` | Mock Whoop returns full recovery JSON (all fields) | Call `/v2/recovery` via backend proxy | Recovery score, HRV, RHR, respiratory rate all parsed and stored with correct types |
| WI-003 | `test_dataSync_realisticSleepPayload_allStagesParsed` | Mock Whoop returns sleep with stages breakdown | Call `/v2/activity/sleep` via backend proxy | Awake, light, deep, REM durations parsed; sleep efficiency calculated |
| WI-004 | `test_rateLimit429_backsOffAndRetries` | Mock Whoop returns 429 on first call, 200 on second | Backend makes Whoop API call | First call gets 429; backoff applied; second call succeeds; data returned |
| WI-005 | `test_rateLimit429_exhaustedRetries_returnsError` | Mock Whoop returns 429 on all calls | Backend makes Whoop API call with 3 retries | After 3 retries, returns appropriate error to iOS client |
| WI-006 | `test_expiredToken_autoRefreshAndRetry` | Mock returns 401 on first call, new token on refresh, 200 on retry | Backend makes Whoop API call | Token refreshed automatically; original request retried; data returned |
| WI-007 | `test_webhookProcessing_endToEnd` | Mock webhook with valid HMAC | POST webhook to backend; verify iOS receives push | Webhook parsed, data stored, push notification sent, iOS app receives updated data on next sync |
| WI-008 | `test_multipleWebhooksRapidFire_noDataCorruption` | 10 webhooks sent within 1 second | POST 10 webhooks concurrently | All processed without DB constraint violations; final state is consistent |

### 4.2 NutriTrack Integration

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| NI-001 | `test_proxyRequest_mockFlask_returnsTransformedData` | Mock NutriTrack Flask server running | GET `/v1/nutritrack/today` via Tempo backend | NutriTrack response transformed to Tempo's data format; macros and meal data present |
| NI-002 | `test_authentication_pinBasedSession_maintained` | Mock NutriTrack requires PIN auth | First request authenticates; subsequent requests use session cookie | Session cookie stored and reused; no re-auth on every call |
| NI-003 | `test_nutritrackDown_returns503WithFallback` | Mock NutriTrack server returns connection timeout | GET `/v1/nutritrack/today` | 503 returned to iOS; cached data served if available; error logged |
| NI-004 | `test_nutritrackDown_cachedDataReturned` | NutriTrack unreachable; Redis has cached response from 30 min ago | GET `/v1/nutritrack/today` | Returns cached data with `X-Cache: HIT` header and `stale: true` field |
| NI-005 | `test_dataTransformation_macroFormats_normalized` | NutriTrack returns macros as floats with varying precision | Process response | Protein/carbs/fat rounded to 1 decimal; calories as integers |
| NI-006 | `test_proxyRequest_allEndpoints_correctRouting` | Mock NutriTrack | Request `/v1/nutritrack/weekly-report`, `/v1/nutritrack/macro-balance`, etc. | Each proxies to the correct NutriTrack endpoint with correct path mapping |

### 4.3 HealthKit Integration

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| HI-001 | `test_readSteps_fromTestStore_correctAggregation` | HealthKit test environment with known step data | Query steps for a 24-hour period | Returns sum of all step samples for the period |
| HI-002 | `test_writeWorkout_andReadBack_dataPreserved` | HealthKit test environment writable | Save a strength workout, then query workouts for the day | Saved workout returned with matching type, duration, and calorie data |
| HI-003 | `test_backgroundDelivery_stepUpdate_callbackFires` | Background delivery enabled for steps | Add step sample to test store | Observer query callback fires; new data processed by app |
| HI-004 | `test_multipleSources_deduplication` | HealthKit has step data from Apple Watch AND iPhone for same period | Query steps | Returns deduplicated total (HealthKit handles this, verify our query does not double-count) |
| HI-005 | `test_noPermission_gracefulDegradation` | HealthKit authorization denied for heart rate | Query heart rate | Returns empty result; no crash; dashboard shows "Not Available" for that metric |

---

## 5. UI Tests (XCUITest)

All UI tests use the Page Object pattern. Each screen has a corresponding `Page` class with element queries and action methods. Tests use launch arguments to inject mock data and bypass authentication.

### 5.1 Onboarding Flow

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| UO-001 | `test_onboarding_completeFromScratch_allSteps` | Fresh install, no user data | 1. Launch app; 2. Verify welcome screen; 3. Tap "GET STARTED"; 4. Complete Sign in with Apple (mock); 5. Set display name and username; 6. Complete body stats; 7. Grant HealthKit permissions; 8. Connect Whoop (or skip); 9. Connect NutriTrack (or skip); 10. Grant Calendar access; 11. Set non-negotiables; 12. Grant notification permission | App navigates to Dashboard; all 12 progress segments filled; onboarding flag set |
| UO-002 | `test_onboarding_skipOptionalIntegrations` | Fresh install | 1. Complete steps 1-3; 2. Skip Whoop; 3. Skip NutriTrack; 4. Skip Calendar; 5. Complete remaining steps | Dashboard loads with "Connect Whoop" prompts in recovery section; NutriTrack shows placeholder data |
| UO-003 | `test_onboarding_resumeAfterKill` | Kill app at step 5 (body stats) | 1. Complete steps 1-4; 2. Force quit app; 3. Relaunch | App resumes at step 5, not step 1; previously entered data preserved |
| UO-004 | `test_onboarding_backNavigation_preservesData` | At step 6 | 1. Enter data on step 6; 2. Tap back; 3. Verify step 5 data; 4. Tap forward | Step 6 data still present after back+forward navigation |
| UO-005 | `test_onboarding_usernameValidation_realtime` | At profile setup step | 1. Type "a" (too short); 2. Verify error; 3. Type "nicola.d"; 4. Verify availability check spinner; 5. Verify green checkmark | Real-time validation shows errors and availability correctly |

### 5.2 Dashboard

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| UD-001 | `test_dashboard_launchAndVerifyAllQuadrantsLoaded` | User authenticated, mock data seeded | 1. Launch app; 2. Wait for dashboard | All 4 quadrants visible: Body (recovery %), Fuel (macros), Mind (study time), Move (workout status) |
| UD-002 | `test_dashboard_pullToRefresh_updatesData` | Dashboard loaded with stale data; updated mock data available | 1. Pull down to trigger refresh; 2. Wait for refresh animation | Data updates to new values; refresh indicator dismisses |
| UD-003 | `test_dashboard_tapBodyQuadrant_expandsDetail` | Dashboard loaded | 1. Tap Body quadrant | Expands to show recovery %, HRV, RHR, sleep score; navigation to Recovery module available |
| UD-004 | `test_dashboard_tapFuelQuadrant_expandsDetail` | Dashboard loaded | 1. Tap Fuel quadrant | Expands to show calories, protein, carbs, fat with progress bars |
| UD-005 | `test_dashboard_tapMindQuadrant_expandsDetail` | Dashboard loaded | 1. Tap Mind quadrant | Expands to show study minutes, exam countdown, focus sessions count |
| UD-006 | `test_dashboard_tapMoveQuadrant_expandsDetail` | Dashboard loaded | 1. Tap Move quadrant | Expands to show steps, active calories, workout completion status |
| UD-007 | `test_dashboard_scoreRingAnimation_displaysCorrectly` | Daily score = 73 | 1. Launch; 2. Observe score ring | Ring animates to 73% fill; number displays "73" |
| UD-008 | `test_dashboard_noWhoopData_showsConnectPrompt` | No Whoop connection | 1. Launch | Body quadrant shows "Connect Whoop" prompt instead of recovery score |
| UD-009 | `test_dashboard_noNutriTrackData_showsPlaceholder` | No NutriTrack connection | 1. Launch | Fuel quadrant shows placeholder state with "Connect NutriTrack" |

### 5.3 Training

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| UT-001 | `test_training_viewTodaysWorkout_displaysAllExercises` | Push day workout generated with 6 exercises | 1. Navigate to Training tab | All 6 exercises visible with sets/reps/weight; recovery badge shows zone |
| UT-002 | `test_training_startWorkout_logThreeSets_finish` | Push day workout | 1. Tap "START WORKOUT"; 2. Tap first set done (weight + reps); 3. Complete 2 more sets; 4. Tap "Finish Workout" | Sets marked as completed with checkmarks; rest timer appears between sets; workout summary shown |
| UT-003 | `test_training_restTimer_countsDown` | Workout in progress, set just completed | 1. Complete a set; 2. Observe rest timer | Timer appears with recommended rest time; counts down to 0; vibration/haptic at end |
| UT-004 | `test_training_restTimer_skipButton` | Rest timer active | 1. Tap "Skip Rest" button | Timer dismissed; next set becomes active immediately |
| UT-005 | `test_training_swapExercise_alternativeShown` | Workout in progress | 1. Long press on exercise card; 2. Tap "Swap Exercise" | Bottom sheet shows alternatives for same muscle group; selecting one replaces the exercise |
| UT-006 | `test_training_progressChart_showsWeightOverTime` | 8 weeks of bench press history | 1. Navigate to Training; 2. Tap "Progress"; 3. Select Bench Press | Chart shows weight progression over 8 weeks with trend line |
| UT-007 | `test_training_weekPlanView_shows7Days` | Full week of workouts planned | 1. Tap calendar icon in Training nav bar | 7-day view showing each day's workout type; today highlighted |
| UT-008 | `test_training_recoveryBadge_greenState` | Recovery = 82% | 1. Open Today's Workout | Green recovery badge visible: "82% Recovery - Full Volume" |
| UT-009 | `test_training_recoveryBadge_redState_mobilityShown` | Recovery = 22% | 1. Open Today's Workout | Red recovery badge: "22% Recovery"; workout type changed to Mobility |
| UT-010 | `test_training_weightStepper_incrementsCorrectly` | Logging a set | 1. Tap weight field; 2. Use stepper to adjust weight | Weight increments by 2.5kg per tap (upper body) or 5kg per tap (lower body) |

### 5.4 Accountability

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| UA-001 | `test_lockdown_viewTodaysNonNegotiables_allDisplayed` | 4 non-negotiables configured | 1. Navigate to Lockdown tab | All 4 items visible with progress indicators; lock icon shows "LOCKED" |
| UA-002 | `test_lockdown_startFocusTimer_completeSession` | Study non-negotiable at 0/120 min | 1. Tap "Start Timer" on study task; 2. Wait for timer (or use mock clock); 3. Complete 25-min Pomodoro session | Study minutes increment by 25; progress bar updates; XP earned notification |
| UA-003 | `test_lockdown_checkOffManualTask` | Custom non-negotiable "Read 30 pages" (manual) | 1. Tap checkbox on manual task | Task marked complete with checkmark animation; progress ring updates |
| UA-004 | `test_lockdown_allComplete_leisureUnlocked` | 3 of 4 tasks complete, complete the 4th | 1. Complete final task | Lock icon animates to unlocked state; "PS5 EARNED" message; confetti or success animation |
| UA-005 | `test_lockdown_autoTracking_whoopConfirmsTraining` | Training non-negotiable is auto-tracked via Whoop | Mock Whoop reports completed workout | Training task automatically marked complete with "WHOOP" badge |
| UA-006 | `test_lockdown_autoTracking_nutritrackConfirmsMeals` | Meals non-negotiable auto-tracked via NutriTrack | Mock NutriTrack reports 3 meals logged | Meals task shows 3/3 with "NUTRITRACK" badge |
| UA-007 | `test_lockdown_streakView_heatmapDisplayed` | 30 days of accountability history | 1. Navigate to streak view | Calendar heatmap visible; completed days highlighted; current streak count displayed |
| UA-008 | `test_lockdown_focusTimer_pauseAndResume` | Timer running | 1. Tap pause; 2. Verify timer stops; 3. Tap resume | Timer pauses and resumes correctly; total time is sum of active segments |

### 5.5 Recovery

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| UR-001 | `test_recovery_todayView_scoreAndPrescription` | Recovery = 72%, mock prescription generated | 1. Navigate to Recovery tab | Score ring shows 72% in green; prescription cards visible (training rec, bedtime, caffeine cutoff, hydration) |
| UR-002 | `test_recovery_sleepDetail_showsStages` | Sleep data with all stages available | 1. Tap sleep card | Sleep detail view shows duration, stages breakdown (awake/light/deep/REM), sleep debt, consistency |
| UR-003 | `test_recovery_trends_7DayView` | 7 days of recovery history | 1. Tap "See Trends" | Line chart showing recovery % over 7 days; average displayed |
| UR-004 | `test_recovery_prescriptionTap_showsReasoning` | Prescription available | 1. Tap any prescription card | Bottom sheet shows reasoning behind the recommendation |
| UR-005 | `test_recovery_noWhoopConnected_showsConnectPrompt` | Whoop not connected | 1. Navigate to Recovery tab | Shows "Connect Whoop" prompt; no prescription generated |

### 5.6 Arena

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| UG-001 | `test_arena_viewLeaderboard_correctOrder` | User has 3 friends with varying XP | 1. Navigate to Arena tab | Leaderboard shows 4 entries (user + 3 friends) sorted by weekly XP descending |
| UG-002 | `test_arena_sendFriendRequest_pending` | Username to add known | 1. Tap "Add Friend"; 2. Enter username; 3. Tap "Send Request" | Request sent confirmation; friend appears in "Pending" section |
| UG-003 | `test_arena_createChallenge_allFieldsFilled` | At least 1 friend | 1. Tap "Create Challenge"; 2. Set name, metric (study hours), duration (7 days); 3. Invite friend; 4. Tap "Start" | Challenge created; appears in Active Challenges; friend receives notification |
| UG-004 | `test_arena_viewAchievements_badgesDisplayed` | User has 5 badges earned | 1. Navigate to Achievements | 5 badges shown with colored glow; remaining badges shown as locked/gray |
| UG-005 | `test_arena_xpAnimation_onCompletion` | User completes a workout (earning 100+ XP) | Complete workout and return to Arena | XP counter animates upward; "+150 XP" floats up with animation |
| UG-006 | `test_arena_levelUp_celebrationScreen` | User is 10 XP away from next level | Earn 50 XP from workout | Level-up celebration overlay shown with new level and title |

---

## 6. Snapshot Tests

Use a snapshot testing library (swift-snapshot-testing or similar). Every snapshot is captured at 1x resolution on iPhone 15 Pro (393x852 logical points) unless noted otherwise.

### 6.1 Screen States

For EVERY screen, capture snapshots in these states:

| State | Description |
|-------|-------------|
| Empty | No data loaded; first-time view |
| Loading | Skeleton/shimmer placeholders active |
| Error | Network error or data fetch failure displayed |
| Populated | Full data, typical use case |

**Dashboard (4 states x 1 screen):**
- `SS-DASH-001` Dashboard -- empty (new user, no integrations)
- `SS-DASH-002` Dashboard -- loading (shimmer placeholders for all 4 quadrants)
- `SS-DASH-003` Dashboard -- error (network failure banner, cached data below)
- `SS-DASH-004` Dashboard -- populated (all 4 quadrants with data)

**Training (4 states x 3 screens):**
- `SS-TRAIN-001` TodayWorkout -- empty (no workout programmed)
- `SS-TRAIN-002` TodayWorkout -- loading
- `SS-TRAIN-003` TodayWorkout -- populated (Push Day with 6 exercises)
- `SS-TRAIN-004` TodayWorkout -- error (recovery data unavailable)
- `SS-TRAIN-005` WorkoutLog -- in progress (2 of 6 exercises done)
- `SS-TRAIN-006` WorkoutLog -- rest timer active
- `SS-TRAIN-007` WorkoutSummary -- completed workout
- `SS-TRAIN-008` ProgressChart -- 12 weeks of data
- `SS-TRAIN-009` ProgressChart -- no history yet
- `SS-TRAIN-010` WeekPlan -- full week
- `SS-TRAIN-011` WeekPlan -- rest day highlighted

**Accountability (4 states x 3 screens):**
- `SS-LOCK-001` Lockdown -- no tasks configured (setup prompt)
- `SS-LOCK-002` Lockdown -- 4 tasks, 0 completed (locked)
- `SS-LOCK-003` Lockdown -- 4 tasks, 2 completed (partial)
- `SS-LOCK-004` Lockdown -- all tasks complete (unlocked)
- `SS-LOCK-005` FocusTimer -- idle
- `SS-LOCK-006` FocusTimer -- running (12:34 remaining)
- `SS-LOCK-007` FocusTimer -- session complete
- `SS-LOCK-008` StreakCalendar -- 45-day streak
- `SS-LOCK-009` StreakCalendar -- streak just broken

**Recovery (4 states x 3 screens):**
- `SS-REC-001` RecoveryToday -- green zone (82%)
- `SS-REC-002` RecoveryToday -- yellow zone (48%)
- `SS-REC-003` RecoveryToday -- red zone (22%)
- `SS-REC-004` RecoveryToday -- no Whoop connected
- `SS-REC-005` SleepDetail -- full sleep data
- `SS-REC-006` SleepDetail -- no sleep data
- `SS-REC-007` RecoveryTrends -- 30-day chart
- `SS-REC-008` RecoveryTrends -- insufficient data (<7 days)

**Arena (4 states x 3 screens):**
- `SS-ARENA-001` ArenaMain -- level 12, XP progress visible
- `SS-ARENA-002` ArenaMain -- level 1 (new user)
- `SS-ARENA-003` Leaderboard -- 5 friends
- `SS-ARENA-004` Leaderboard -- no friends yet
- `SS-ARENA-005` Challenges -- 2 active challenges
- `SS-ARENA-006` Challenges -- no challenges
- `SS-ARENA-007` Achievements -- 10 of 30 earned
- `SS-ARENA-008` Achievements -- none earned

**Onboarding (12 steps):**
- `SS-ONBOARD-001` through `SS-ONBOARD-012` -- one per onboarding step

### 6.2 Dark Mode

Every snapshot listed above is captured again in dark mode. Since Tempo is dark-mode-first, these serve as the primary reference. Light mode variants (if supported) get a `-light` suffix:

- `SS-DASH-004-light` Dashboard populated (light mode)
- etc.

### 6.3 Dynamic Type

For every screen, capture at 3 sizes:
- Default (Large)
- Accessibility Extra Large (AX3)
- Smallest (XS)

Naming convention: `SS-DASH-004-ax3`, `SS-DASH-004-xs`

### 6.4 Widget Snapshots

- `SS-WIDGET-001` Small widget -- daily score ring
- `SS-WIDGET-002` Medium widget -- score + top 2 non-negotiables
- `SS-WIDGET-003` Large widget -- full daily summary
- `SS-WIDGET-004` Small widget -- no data (prompt to open app)

### 6.5 Component Snapshots

Key reusable components in isolation:

- `SS-COMP-001` ScoreRing -- 0%, 25%, 50%, 75%, 100%
- `SS-COMP-002` QuadrantCard -- each variant (Body, Fuel, Mind, Move)
- `SS-COMP-003` RecoveryBadge -- green, yellow, red states
- `SS-COMP-004` ExerciseCard -- standard, superset, completed
- `SS-COMP-005` SetLoggingRow -- empty, in-progress, completed
- `SS-COMP-006` TrendChart -- upward, downward, flat trend
- `SS-COMP-007` StreakFlame -- active (gold), broken (gray)
- `SS-COMP-008` XPBadge -- positive, negative, level-up
- `SS-COMP-009` DrillSergeantAlert -- each escalation tier
- `SS-COMP-010` LockIcon -- locked, unlocked animation keyframe

---

## 7. Performance Tests

All performance tests use `XCTMetric` and `measure` blocks. Baselines are set on iPhone 15 Pro, iOS 17.4, Release build.

### 7.1 App Launch

| ID | Metric | Target | How to Measure |
|----|--------|--------|----------------|
| PF-001 | Time to first meaningful paint (Dashboard visible) | < 1.0 second (cold launch) | `measure(metrics: [XCTClockMetric()])` from `application(_:didFinishLaunchingWithOptions:)` to dashboard `onAppear` |
| PF-002 | Time to interactive (dashboard data loaded) | < 1.5 seconds (cold launch) | Measure until all 4 quadrants show data (not shimmer) |
| PF-003 | Warm launch (from background) | < 300ms | Measure from `sceneWillEnterForeground` to render |

### 7.2 Data Loading

| ID | Metric | Target | How to Measure |
|----|--------|--------|----------------|
| PF-004 | Dashboard full data load (all 4 quadrants) | < 300ms | Time from refresh trigger to UI update with 90 days of cached data |
| PF-005 | Workout generation (TrainingEngine) | < 100ms | Time to generate a full push day workout with 6 exercises |
| PF-006 | Recovery prescription generation | < 50ms | Time to run RecoveryEngine with full input data |
| PF-007 | XP calculation (full day) | < 20ms | Time to calculate all XP events for one day |
| PF-008 | Leaderboard fetch (10 friends) | < 500ms round-trip | Backend response time for leaderboard query |

### 7.3 Workout Logging

| ID | Metric | Target | How to Measure |
|----|--------|--------|----------------|
| PF-009 | Set complete to next set ready | < 100ms | Time from tap "Done" to rest timer appearing and next set becoming tappable |
| PF-010 | Weight stepper increment latency | < 16ms (1 frame) | Haptic + UI update must happen within a single frame |
| PF-011 | Exercise swap response | < 200ms | Time from selecting alternative exercise to UI update |

### 7.4 Database Performance

| ID | Metric | Target | How to Measure |
|----|--------|--------|----------------|
| PF-012 | SwiftData query: fetch 365 daily snapshots | < 100ms | `measure` block around predicate query for 1 year of data |
| PF-013 | SwiftData query: fetch all workouts in date range (90 days) | < 80ms | Query 90 days of workout history with exercises and sets |
| PF-014 | SwiftData insert: save 1 workout with 6 exercises and 24 sets | < 50ms | Single transaction insert |
| PF-015 | PostgreSQL: weekly leaderboard query (1000 users) | < 200ms | Backend load test with 1000 users, 7 days of XP events |

### 7.5 Memory and Battery

| ID | Metric | Target | How to Measure |
|----|--------|--------|----------------|
| PF-016 | Memory during 1-hour workout session | < 150 MB peak | Profile with Instruments; log sets every 90 seconds for 1 hour |
| PF-017 | Memory with 1 year of data loaded | < 200 MB | Launch app with 365 daily snapshots + workout history |
| PF-018 | Battery drain during 1-hour focus timer | < 3% (screen on), < 1% (screen off) | Monitor battery level over 1-hour Pomodoro session with screen dimmed |
| PF-019 | Background sync energy impact | LOW rating | Run Instruments Energy Log during 1 hour of background operation |

---

## 8. API Contract Tests

### 8.1 Request/Response Schema Validation

For EVERY backend endpoint, validate:

| ID | Test Case | Expected Result |
|----|-----------|-----------------|
| AC-001 | `POST /v1/auth/apple` -- missing `identity_token` field | 400 with `fields.identity_token` error |
| AC-002 | `POST /v1/auth/apple` -- extra unknown fields in body | Ignored; 200 OK (tolerant reader) |
| AC-003 | `POST /v1/auth/refresh` -- `refresh_token` is integer instead of string | 400 type validation error |
| AC-004 | `GET /v1/arena/leaderboard` -- response always has `ok`, `data`, `meta` envelope | Validate JSON schema for every response |
| AC-005 | `GET /v1/arena/leaderboard` -- paginated response has `pagination.cursor`, `pagination.has_more`, `pagination.count` | All pagination fields present and correctly typed |
| AC-006 | `POST /v1/arena/xp` -- `amount` exceeds max daily XP (>1500) | 400 validation error |
| AC-007 | `POST /v1/arena/challenges` -- all date fields in ISO 8601 UTC format | Validate date string parsing |
| AC-008 | `GET /v1/whoop/recovery` -- response contains `recovery_score` as Double, `hrv_rmssd` as Double, `resting_hr` as Double | Type validation on all numeric fields |
| AC-009 | `POST /v1/webhooks/whoop` -- Whoop webhook payload matches documented schema | Validated against Whoop API v2 webhook schema |
| AC-010 | All error responses -- conform to standard error envelope format | `ok: false`, `error.code`, `error.message`, `error.detail` always present |

### 8.2 Backward Compatibility

| ID | Test Case | Expected Result |
|----|-----------|-----------------|
| AC-011 | Old iOS client (v1.0) sends request to v1 backend (v1.1) | All v1.0 features work; new fields are optional and absent from old client requests |
| AC-012 | New iOS client (v1.1) sends request to v1 backend (v1.0) | New fields ignored by old server; no errors; new client degrades gracefully for missing response fields |
| AC-013 | Server adds new optional field to response | Old clients ignore unknown fields (verify decoder uses `decodeIfPresent`) |
| AC-014 | Server deprecates a field | Field still present in response but `Deprecation` header added |

### 8.3 Error Response Consistency

| ID | Test Case | Expected Result |
|----|-----------|-----------------|
| AC-015 | Every 4xx error includes `error.code` (numeric) | Validate all error responses across all endpoints |
| AC-016 | Every 4xx error includes `error.message` (human-readable) | Never empty string |
| AC-017 | Every 429 response includes `Retry-After` header | Header present with integer seconds value |
| AC-018 | Every response includes `X-Request-Id` header | Present on all 2xx, 4xx, and 5xx responses |

---

## 9. Edge Case Tests

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| EC-001 | `test_timezoneChange_midDay_noDataLoss` | User in EST, daily snapshot in progress | Change device timezone to PST (3 hours back) | Daily snapshot not duplicated; date boundaries recalculated; non-negotiable progress preserved |
| EC-002 | `test_timezoneChange_crossesMidnight` | 11:30 PM EST, change to CST (10:30 PM) | Change timezone | Day does not prematurely end; midnight recalculated for new timezone |
| EC-003 | `test_appForceQuit_duringWorkout_recoversState` | Workout in progress, 3 of 6 exercises completed | Force quit app; relaunch | Workout state restored; 3 exercises marked complete; timer paused; prompt to resume or discard |
| EC-004 | `test_appForceQuit_duringFocusTimer_savesElapsedTime` | Focus timer at 18:42 of 25:00 | Force quit app; relaunch | 18 minutes of study time saved to today's total; timer reset to idle |
| EC-005 | `test_networkLoss_duringAPICall_retryOnReconnect` | API call in flight | Airplane mode toggled on | Call fails gracefully; cached data shown; when network returns, auto-retry queued |
| EC-006 | `test_networkLoss_offlineMode_localDataAccessible` | No network for extended period | Open app offline | Dashboard shows cached data with "Last updated X ago" banner; HealthKit data still live; no crashes |
| EC-007 | `test_swiftDataMigration_v1ToV2_noDataLoss` | SwiftData schema v1 with 90 days of data | Run migration to v2 schema | All 90 days of snapshots preserved; new fields have default values; app launches without crash |
| EC-008 | `test_swiftDataMigration_corruptStore_handledGracefully` | SwiftData store file corrupted | Launch app | Detects corruption; offers to reset local data; does not crash |
| EC-009 | `test_concurrentSync_multipleThreads_noRaceCondition` | Whoop webhook + HealthKit background delivery + manual refresh all trigger simultaneously | Trigger all 3 sync sources | No duplicate data; no SwiftData constraint violations; final state consistent |
| EC-010 | `test_dateRollover_midnight_activeTimer` | Focus timer running at 11:58 PM | Clock ticks past midnight | Timer continues uninterrupted; study minutes split between two days (58 min to old day, remaining to new day); new daily snapshot created |
| EC-011 | `test_dateRollover_midnight_activeWorkout` | Workout in progress at 11:55 PM | Clock ticks past midnight | Workout continues; completion time recorded as actual finish time; associated with the day it started |
| EC-012 | `test_leapYear_february29_correctDateHandling` | Feb 28, 2028 (leap year) | Day rolls over | Feb 29 exists; daily snapshot created; streak not broken; weekly calculation includes Feb 29 |
| EC-013 | `test_DST_springForward_duringActiveStreak` | March DST transition, streak active | Clock jumps from 1:59 AM to 3:00 AM | Streak preserved; daily boundary uses calendar day, not 24-hour window; no penalty for "missing" hour |
| EC-014 | `test_DST_fallBack_duringTimer` | November DST transition, focus timer running | Clock goes from 1:59 AM back to 1:00 AM | Timer uses monotonic clock (`Date.timeIntervalSinceReferenceDate` or `ContinuousClock`); duration not doubled |
| EC-015 | `test_veryLargeDataSet_365DaysWorkouts_noPerformanceDegradation` | 365 days of workout data (average 5 workouts/week = ~260 workouts with ~1500 exercises and ~6000 sets) | Load progress chart for any exercise | Chart renders within 500ms; no UI hang |
| EC-016 | `test_whoopDisconnects_midSync_gracefulRecovery` | Whoop OAuth token revoked during data sync | Backend attempts Whoop API call | Receives 401; marks Whoop as disconnected; sends push to reconnect; no crash or data corruption |
| EC-017 | `test_maxUsernameLength_20Characters_accepted` | Onboarding, username field | Enter exactly 20 characters | Accepted; no truncation |
| EC-018 | `test_unicodeDisplayName_accentedCharacters_storedCorrectly` | User name "Nicol\u00e0 Debbia" | Complete profile setup | Name stored and displayed correctly including accent |
| EC-019 | `test_xpOverflow_veryHighTotalXP_noIntegerOverflow` | User with 10M+ total XP (extreme edge) | Calculate level | No integer overflow; level calculation handles large numbers |
| EC-020 | `test_simultaneousSetLogging_rapidTaps_noDuplicates` | Workout active | Rapidly tap "Done" 3 times on same set | Set completed once; no duplicate set entries |

---

## 10. Accessibility Tests

### 10.1 VoiceOver Navigation

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| AX-001 | `test_voiceover_dashboard_allQuadrantsAccessible` | VoiceOver enabled | Swipe through dashboard elements | Each quadrant announces: label, value, and hint (e.g., "Body. Recovery 78 percent. Double tap to view details.") |
| AX-002 | `test_voiceover_training_exerciseCardReadsCompletely` | VoiceOver on Training screen | Navigate to exercise card | Announces: exercise name, muscle group, sets and reps, target weight, completion status |
| AX-003 | `test_voiceover_lockdown_progressAnnounced` | VoiceOver on Lockdown | Navigate to progress ring | Announces: "47 percent complete. 4 hours 32 minutes until leisure unlocked." |
| AX-004 | `test_voiceover_recovery_zoneAnnounced` | VoiceOver on Recovery | Navigate to recovery score | Announces: "Recovery 72 percent. Green zone. Training recommendation: Full send." |
| AX-005 | `test_voiceover_arena_leaderboardOrder` | VoiceOver on Arena | Navigate through leaderboard | Each entry announces: rank, name, XP total. Correct order preserved. |
| AX-006 | `test_voiceover_focusTimer_timeRemaining` | VoiceOver, timer running | Navigate to timer | Announces: "12 minutes 34 seconds remaining. Double tap to pause." Updated every 30 seconds. |
| AX-007 | `test_voiceover_onboarding_everyStepNavigable` | VoiceOver enabled, fresh install | Complete entire onboarding | Every step navigable; all buttons, inputs, and content accessible; no unlabeled elements |
| AX-008 | `test_voiceover_charts_summaryProvided` | VoiceOver on any chart | Navigate to chart element | Chart provides `.accessibilityLabel` with summary (e.g., "Recovery trend: increasing over last 7 days, average 68 percent") |

### 10.2 Dynamic Type

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| AX-009 | `test_dynamicType_default_allTextReadable` | System text size = Large (default) | Launch app; navigate all screens | All text renders at standard sizes; no truncation; layout intact |
| AX-010 | `test_dynamicType_extraLarge_noTruncation` | System text size = AX3 | Launch app; navigate all screens | All text scales up; cards expand vertically; horizontal layout becomes vertical where needed; no text clipped |
| AX-011 | `test_dynamicType_extraExtraLarge_scrollable` | System text size = AX5 | Launch app | Content scrollable; nothing hidden behind other elements; minimum touch targets maintained |
| AX-012 | `test_dynamicType_small_layoutNotBroken` | System text size = XS | Launch app | Layout not broken by smaller text; no excessive whitespace |

### 10.3 Reduce Motion

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| AX-013 | `test_reduceMotion_springAnimationsBecomeFade` | Reduce Motion enabled in Settings | Complete a workout set | No spring/bounce animations; transitions use 200ms ease-in-out crossfade |
| AX-014 | `test_reduceMotion_confettiDisabled` | Reduce Motion enabled | Trigger level-up or perfect day | Confetti particles not shown; static badge displayed instead |
| AX-015 | `test_reduceMotion_scoreRingNoAnimation` | Reduce Motion enabled | Launch dashboard | Score ring shows final value immediately; no fill animation |

### 10.4 Color and Contrast

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| AX-016 | `test_colorContrast_textOnDarkBackground_meetsWCAG` | Default dark mode | Audit all text elements | All text meets WCAG AA contrast ratio (4.5:1 for body text, 3:1 for large text) |
| AX-017 | `test_colorContrast_recoveryZones_haveIcons` | Default mode | View recovery badges | Green/yellow/red zones each have a distinct icon in addition to color (checkmark, warning triangle, X) |
| AX-018 | `test_highContrast_enabled_bordersVisible` | Increase Contrast enabled in Settings | Launch app | Card borders become visible (1pt solid); backgrounds shift for higher contrast |

### 10.5 Touch Targets

| ID | Test Case | Preconditions | Steps | Expected Result |
|----|-----------|---------------|-------|-----------------|
| AX-019 | `test_touchTargets_minimumSize_44pt` | Default mode | Audit all interactive elements | All buttons, toggles, steppers, and tappable areas are at least 44x44pt |
| AX-020 | `test_touchTargets_workoutLogging_expanded56pt` | Active workout | Audit set logging controls | During workout, all tap targets are at least 56x56pt (sweaty hands accommodation) |

---

## 11. CI/CD Pipeline

### 11.1 GitHub Actions Configuration

```yaml
# .github/workflows/tempo-ci.yml
name: Tempo CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    runs-on: macos-14
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: SwiftLint
        run: swiftlint lint --strict --reporter github-actions-logging
      - name: SwiftFormat Check
        run: swiftformat --lint .

  unit-tests-ios:
    runs-on: macos-14
    timeout-minutes: 20
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.0.app
      - name: Unit Tests
        run: |
          xcodebuild test \
            -project Tempo.xcodeproj \
            -scheme TempoTests \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.4' \
            -resultBundlePath TestResults/unit.xcresult \
            -enableCodeCoverage YES
      - name: Check Coverage
        run: |
          xcrun xccov view --report TestResults/unit.xcresult \
            --json | python3 scripts/check_coverage.py --threshold 80

  unit-tests-backend:
    runs-on: macos-14
    timeout-minutes: 15
    needs: lint
    services:
      postgres:
        image: postgres:16
        ports: ['5432:5432']
        env:
          POSTGRES_DB: tempo_test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
    steps:
      - uses: actions/checkout@v4
      - name: Backend Unit Tests
        working-directory: tempo-backend
        run: swift test --enable-code-coverage
      - name: Check Coverage
        run: |
          swift test --show-codecov-path | xargs \
            python3 scripts/check_coverage.py --threshold 80

  integration-tests:
    runs-on: macos-14
    timeout-minutes: 30
    needs: [unit-tests-ios, unit-tests-backend]
    services:
      postgres:
        image: postgres:16
        ports: ['5432:5432']
        env:
          POSTGRES_DB: tempo_test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
      redis:
        image: redis:7
        ports: ['6379:6379']
    steps:
      - uses: actions/checkout@v4
      - name: Integration Tests
        run: |
          xcodebuild test \
            -project Tempo.xcodeproj \
            -scheme TempoIntegrationTests \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.4' \
            -resultBundlePath TestResults/integration.xcresult

  snapshot-tests:
    runs-on: macos-14
    timeout-minutes: 20
    needs: [unit-tests-ios]
    steps:
      - uses: actions/checkout@v4
      - name: Snapshot Tests
        run: |
          xcodebuild test \
            -project Tempo.xcodeproj \
            -scheme TempoSnapshotTests \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.4' \
            -resultBundlePath TestResults/snapshots.xcresult
      - name: Upload Failed Snapshots
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: failed-snapshots
          path: TempoTests/Snapshot/__Snapshots__/

  ui-tests:
    runs-on: macos-14
    timeout-minutes: 45
    needs: [integration-tests, snapshot-tests]
    steps:
      - uses: actions/checkout@v4
      - name: UI Tests
        run: |
          xcodebuild test \
            -project Tempo.xcodeproj \
            -scheme TempoUITests \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.4' \
            -resultBundlePath TestResults/uitests.xcresult
      - name: Upload Test Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: ui-test-results
          path: TestResults/uitests.xcresult
```

### 11.2 Test Stages

```
Stage 1: Lint (SwiftLint + SwiftFormat)     ~2 min
    |
    v
Stage 2: Unit Tests (iOS + Backend)         ~8 min (parallel)
    |         |
    v         v
Stage 3: Snapshot Tests                     ~5 min
    |
    v
Stage 4: Integration Tests                 ~10 min
    |
    v
Stage 5: UI Tests                          ~15 min
    |
    v
Stage 6: Deploy to TestFlight (main only)  ~10 min
```

### 11.3 Coverage Thresholds

| Category | Minimum | Target | Enforced |
|----------|---------|--------|----------|
| Unit tests -- Engines | 90% | 95% | Yes (PR fails below 90%) |
| Unit tests -- Services | 80% | 90% | Yes (PR fails below 80%) |
| Unit tests -- Models | 70% | 85% | Yes (PR fails below 70%) |
| Integration tests | 60% | 75% | Yes (PR fails below 60%) |
| Overall iOS | 80% | 88% | Yes (PR fails below 80%) |
| Overall Backend | 80% | 88% | Yes (PR fails below 80%) |
| Views (SwiftUI) | Not measured | N/A | No (use snapshot tests instead) |

### 11.4 TestFlight Deployment

Automated on merge to `main`:

1. Increment build number (`agvtool next-version`)
2. Archive with Release configuration
3. Export IPA with App Store distribution profile
4. Upload to App Store Connect via `altool` or Xcode Cloud
5. Post to Slack channel with build number and changelog

### 11.5 App Store Submission

Manual trigger via GitHub Actions workflow dispatch:

1. Run full test suite (all stages)
2. Generate test report
3. Build Release archive
4. Submit to App Store Review
5. Post status to Slack

---

## 12. Test Data & Mocks

### 12.1 Mock Data Factories

Every SwiftData model has a corresponding factory that produces populated instances with sensible defaults and the ability to override any field.

```swift
// Example: DailySnapshotFactory
struct DailySnapshotFactory {
    static func make(
        date: Date = .now,
        recoveryScore: Double? = 72.0,
        hrvRmssd: Double? = 65.0,
        restingHR: Double? = 52.0,
        sleepHours: Double? = 7.5,
        sleepScore: Double? = 82.0,
        strain: Double? = 12.5,
        caloriesConsumed: Int? = 2200,
        calorieTarget: Int? = 2500,
        proteinG: Double? = 165.0,
        carbsG: Double? = 280.0,
        fatG: Double? = 70.0,
        mealsLogged: Int = 3,
        mealsPlanned: Int = 3,
        studyMinutes: Int = 120,
        studyTarget: Int = 120,
        examCountdown: Int? = 14,
        steps: Int? = 8500,
        activeCalories: Double? = 450.0,
        workoutCompleted: Bool = true,
        workoutType: String? = "Push",
        dailyScore: Int = 73,
        nonNegotiablesCompleted: Int = 4,
        nonNegotiablesTotal: Int = 4
    ) -> DailySnapshot { ... }
}
```

**Required factories:**
- `DailySnapshotFactory`
- `WorkoutPlanFactory` (with nested `PlannedExerciseFactory`, `PlannedSetFactory`)
- `ExerciseFactory` (with equipment and muscle group variants)
- `NonNegotiableFactory`
- `DailyAccountabilityFactory`
- `DailyPrescriptionFactory`
- `StudySessionFactory`
- `UserFactory` (backend)
- `XPEventFactory` (backend)
- `FriendshipFactory` (backend)
- `ChallengeFactory` (backend)
- `AchievementFactory` (backend)

### 12.2 Realistic Test Data Generation

For performance and integration tests, generate realistic long-term data:

| Data Set | Volume | Usage |
|----------|--------|-------|
| 30-day workout history | 20 workouts, 120 exercises, 480 sets | Progress chart tests, weekly volume calculations |
| 90-day recovery history | 90 daily snapshots with Whoop data | Recovery trend chart, pattern detection tests |
| 365-day full history | 365 snapshots, 260 workouts, 1560 exercises, 6240 sets | Performance benchmarks, database query tests |
| XP history (6 months) | ~180 days of XP events, ~1000 individual events | Level calculation, leaderboard performance |
| Study session history | 120 focus timer sessions, varying durations | Streak calculation, study analytics |

### 12.3 Mock API Responses

**Whoop API mocks:**
- `whoop_recovery_green.json` -- Recovery 82%, HRV 68ms, RHR 48bpm
- `whoop_recovery_yellow.json` -- Recovery 52%, HRV 42ms, RHR 56bpm
- `whoop_recovery_red.json` -- Recovery 22%, HRV 28ms, RHR 64bpm
- `whoop_sleep_full.json` -- 7.5h sleep, all stages, 85% efficiency
- `whoop_sleep_poor.json` -- 4.5h sleep, high awake time, 62% efficiency
- `whoop_workout.json` -- Strength training, 52 min, strain 14.2
- `whoop_cycle.json` -- Day strain 12.5, active HR zones breakdown
- `whoop_401_expired.json` -- Token expired error response
- `whoop_429_rate_limited.json` -- Rate limit response with Retry-After
- `whoop_webhook_recovery.json` -- Webhook payload for recovery update
- `whoop_webhook_sleep.json` -- Webhook payload for sleep update

**NutriTrack API mocks:**
- `nutritrack_today_full.json` -- 3 meals logged, all macros tracked, 2200/2500 cal
- `nutritrack_today_partial.json` -- 1 meal logged, breakfast only
- `nutritrack_today_empty.json` -- No meals logged
- `nutritrack_weekly_report.json` -- 7-day summary with averages
- `nutritrack_macro_balance.json` -- Current macro progress
- `nutritrack_503_down.json` -- Service unavailable

### 12.4 Mock HealthKit Store

A `MockHealthKitStore` that conforms to a `HealthKitStoreProtocol`:

```swift
protocol HealthKitStoreProtocol {
    func requestAuthorization(toShare: Set<HKSampleType>,
                               read: Set<HKObjectType>) async throws
    func execute(_ query: HKQuery)
    func save(_ sample: HKSample) async throws
    func enableBackgroundDelivery(for type: HKObjectType,
                                   frequency: HKUpdateFrequency) async throws
}

class MockHealthKitStore: HealthKitStoreProtocol {
    var authorizationStatus: HKAuthorizationStatus = .sharingAuthorized
    var samples: [HKSampleType: [HKSample]] = [:]
    var savedSamples: [HKSample] = []
    var backgroundDeliveryEnabled: [HKObjectType] = []
    // ...
}
```

### 12.5 Test User Personas

| Persona | Name | Description | Data Profile |
|---------|------|-------------|--------------|
| `activeNicola` | Active Nicola | Full data, all integrations connected, 90-day history | Whoop connected, NutriTrack connected, HealthKit full access, 3 friends, level 15, 45-day streak |
| `newUser` | New User | Just completed onboarding, no historical data | All integrations connected but 0 days of data; level 1; no friends |
| `whoopOnly` | Whoop Only | Only Whoop connected, no NutriTrack | Whoop data for 30 days; NutriTrack nil; HealthKit basic (steps only) |
| `disconnected` | Disconnected | No external integrations | No Whoop, no NutriTrack, HealthKit denied; only manual tracking |
| `powerUser` | Power User | 6 months of data, prestige 1, 100-day streak | Maximum data volume; all achievements unlocked; 10 friends; active challenges |
| `lowRecovery` | Low Recovery | Consistently red recovery | Recovery <34% for last 7 days; high sleep debt; HRV trending down |
| `examMode` | Exam Mode | In exam mode, study-heavy | Exam mode active; 6h/day study target; training reduced to 3x/week |

---

## 13. Manual Testing Checklist

Pre-release checklist for each TestFlight build. Organized by module. Each test case includes ID, description, device matrix, and pass/fail columns.

### 13.1 Device Matrix

| Device | Screen Size | Tested |
|--------|------------|--------|
| iPhone SE (3rd gen) | 4.7" | Required |
| iPhone 15 | 6.1" | Required |
| iPhone 15 Pro Max | 6.7" | Required |

| iOS Version | Tested |
|-------------|--------|
| iOS 17.4 (minimum) | Required |
| iOS 18.0 | Required |

### 13.2 Dashboard Manual Tests

| ID | Test Case | Steps | Expected Result | SE | 15 | 15PM |
|----|-----------|-------|-----------------|----|----|------|
| M-D-001 | App launches to dashboard | Cold launch app | Dashboard loads within 2 seconds; all 4 quadrants visible | [ ] | [ ] | [ ] |
| M-D-002 | Pull to refresh works | Pull down on dashboard | Refresh animation plays; data updates | [ ] | [ ] | [ ] |
| M-D-003 | Body quadrant shows recovery | View Body section | Recovery %, HRV, RHR visible; color matches zone | [ ] | [ ] | [ ] |
| M-D-004 | Fuel quadrant shows macros | View Fuel section | Calories, protein, carbs, fat with progress bars | [ ] | [ ] | [ ] |
| M-D-005 | Mind quadrant shows study | View Mind section | Study minutes and target visible; progress accurate | [ ] | [ ] | [ ] |
| M-D-006 | Move quadrant shows activity | View Move section | Steps, workout status, active calories | [ ] | [ ] | [ ] |
| M-D-007 | Score ring animates on load | Launch app | Score ring fills to correct percentage with smooth animation | [ ] | [ ] | [ ] |
| M-D-008 | Quadrant tap expands detail | Tap each quadrant | Expands with additional detail; smooth animation | [ ] | [ ] | [ ] |
| M-D-009 | Dashboard in dark mode | System dark mode | All text readable; no white flashes; colors correct | [ ] | [ ] | [ ] |
| M-D-010 | Dashboard with no data | New user, no integrations | Placeholder state for each quadrant; connect prompts visible | [ ] | [ ] | [ ] |

### 13.3 Training Manual Tests

| ID | Test Case | Steps | Expected Result | SE | 15 | 15PM |
|----|-----------|-------|-----------------|----|----|------|
| M-T-001 | View today's workout | Navigate to Training tab | Workout title, recovery badge, exercise list visible | [ ] | [ ] | [ ] |
| M-T-002 | Recovery badge correct color | Compare to Whoop recovery | Badge color matches Whoop zone (green/yellow/red) | [ ] | [ ] | [ ] |
| M-T-003 | Start workout flow | Tap "START WORKOUT" | Transitions to active workout; first exercise highlighted | [ ] | [ ] | [ ] |
| M-T-004 | Log a set with weight/reps | Enter weight and reps, tap Done | Set marked complete; checkmark animation; rest timer starts | [ ] | [ ] | [ ] |
| M-T-005 | Rest timer counts down | Complete a set | Timer appears with correct duration; counts to 0; haptic at end | [ ] | [ ] | [ ] |
| M-T-006 | Skip rest timer | Tap "Skip" during timer | Timer dismissed; next set active | [ ] | [ ] | [ ] |
| M-T-007 | Complete full workout | Log all sets for all exercises | Workout summary screen; XP earned; written to HealthKit | [ ] | [ ] | [ ] |
| M-T-008 | Swap exercise | Long press exercise > Swap | Alternatives shown for same muscle group; selection replaces exercise | [ ] | [ ] | [ ] |
| M-T-009 | Weight stepper increments | Tap +/- stepper | Weight changes by correct increment (2.5kg upper, 5kg lower) | [ ] | [ ] | [ ] |
| M-T-010 | View progress chart | Navigate to Progress, select exercise | Chart shows weight over time; trend line visible | [ ] | [ ] | [ ] |
| M-T-011 | Week plan view | Tap calendar icon | 7-day view with workout types; today highlighted | [ ] | [ ] | [ ] |
| M-T-012 | Superset display | View workout with supersets | Paired exercises show bracket connector with alternating colors | [ ] | [ ] | [ ] |

### 13.4 Accountability Manual Tests

| ID | Test Case | Steps | Expected Result | SE | 15 | 15PM |
|----|-----------|-------|-----------------|----|----|------|
| M-A-001 | View non-negotiables | Navigate to Lockdown tab | All configured tasks visible with progress indicators | [ ] | [ ] | [ ] |
| M-A-002 | Lock icon shows LOCKED | Tasks incomplete | Red lock icon, "LOCKED" text, time estimate to unlock | [ ] | [ ] | [ ] |
| M-A-003 | Start focus timer | Tap "Start Timer" on study task | Timer starts; countdown visible; screen stays on | [ ] | [ ] | [ ] |
| M-A-004 | Pause focus timer | Tap pause during active timer | Timer pauses; elapsed time preserved | [ ] | [ ] | [ ] |
| M-A-005 | Complete focus session (25 min) | Run timer to completion (use debug shortcut) | Session saved; study minutes increment; success haptic | [ ] | [ ] | [ ] |
| M-A-006 | Manual task check-off | Tap checkbox on custom task | Task marked complete; progress ring updates | [ ] | [ ] | [ ] |
| M-A-007 | All tasks complete - unlock | Complete final remaining task | Lock animates to unlocked; "PS5 EARNED" message; celebration | [ ] | [ ] | [ ] |
| M-A-008 | Auto-tracking via Whoop | Complete a workout (verified by Whoop) | Training task auto-completes with "WHOOP" badge | [ ] | [ ] | [ ] |
| M-A-009 | Auto-tracking via NutriTrack | Log 3 meals in NutriTrack | Meals task shows 3/3 with "NUTRITRACK" badge | [ ] | [ ] | [ ] |
| M-A-010 | Streak calendar heatmap | Navigate to streak view | Calendar shows completed days; streak count correct | [ ] | [ ] | [ ] |
| M-A-011 | Notification escalation received | Wait for scheduled notification time (or debug trigger) | Correct notification tier received matching time of day | [ ] | [ ] | [ ] |

### 13.5 Recovery Manual Tests

| ID | Test Case | Steps | Expected Result | SE | 15 | 15PM |
|----|-----------|-------|-----------------|----|----|------|
| M-R-001 | Recovery score display | Navigate to Recovery tab | Score ring with correct percentage and color | [ ] | [ ] | [ ] |
| M-R-002 | Prescription cards visible | View below score | Training rec, bedtime, caffeine cutoff, hydration all shown | [ ] | [ ] | [ ] |
| M-R-003 | Sleep detail view | Tap sleep card | Sleep stages, duration, debt, efficiency displayed | [ ] | [ ] | [ ] |
| M-R-004 | Recovery trends chart | Tap "See Trends" | 7-day trend line chart; average shown | [ ] | [ ] | [ ] |
| M-R-005 | Prescription reasoning | Tap any prescription card | Bottom sheet explains why this recommendation was made | [ ] | [ ] | [ ] |
| M-R-006 | Pull to refresh syncs Whoop | Pull down | Whoop data refreshes; "Synced X:XX AM/PM" timestamp updates | [ ] | [ ] | [ ] |
| M-R-007 | No Whoop state | Disconnect Whoop (or test persona) | "Connect Whoop" prompt shown; no crash | [ ] | [ ] | [ ] |
| M-R-008 | Stale data indicator | Wait >4 hours without sync | Sync icon turns yellow; "Stale - tap to sync" shown | [ ] | [ ] | [ ] |

### 13.6 Arena Manual Tests

| ID | Test Case | Steps | Expected Result | SE | 15 | 15PM |
|----|-----------|-------|-----------------|----|----|------|
| M-G-001 | XP and level display | Navigate to Arena tab | Current XP, level, title, and progress to next level visible | [ ] | [ ] | [ ] |
| M-G-002 | Weekly leaderboard loads | View leaderboard | Sorted by weekly XP; user's own row highlighted | [ ] | [ ] | [ ] |
| M-G-003 | Send friend request | Add Friend > enter username > Send | Confirmation shown; friend appears in Pending list | [ ] | [ ] | [ ] |
| M-G-004 | Accept friend request | Tap Accept on incoming request | Friend moved to Friends list; appears on leaderboard | [ ] | [ ] | [ ] |
| M-G-005 | Create challenge | Tap Create > fill form > Start | Challenge appears in Active Challenges; invited friend notified | [ ] | [ ] | [ ] |
| M-G-006 | View achievements | Navigate to Achievements | Earned badges with color; locked badges grayed out | [ ] | [ ] | [ ] |
| M-G-007 | XP animation on earn | Complete a task that earns XP | "+XX XP" floats upward with animation | [ ] | [ ] | [ ] |
| M-G-008 | Level up celebration | Earn enough XP to level up | Level-up overlay with new level and title | [ ] | [ ] | [ ] |

### 13.7 General / Cross-Module Manual Tests

| ID | Test Case | Steps | Expected Result | SE | 15 | 15PM |
|----|-----------|-------|-----------------|----|----|------|
| M-X-001 | Tab navigation | Tap each tab in sequence | Correct module loads; no lag; previous state preserved | [ ] | [ ] | [ ] |
| M-X-002 | Background to foreground | Background app for 5 min, reopen | Data refreshes; no blank screens; state preserved | [ ] | [ ] | [ ] |
| M-X-003 | Airplane mode behavior | Enable airplane mode; use app | Cached data shown; "Offline" indicator; no crashes | [ ] | [ ] | [ ] |
| M-X-004 | Orientation lock (portrait) | Rotate device | App stays portrait; no layout breaks | [ ] | [ ] | [ ] |
| M-X-005 | Memory warning handling | Simulate memory warning | Non-essential caches cleared; no crash; app remains functional | [ ] | [ ] | [ ] |
| M-X-006 | Deep link from notification | Tap an accountability notification | App opens directly to Lockdown tab with relevant task highlighted | [ ] | [ ] | [ ] |
| M-X-007 | Sign out and back in | Sign out > Sign in with Apple again | All cloud data restored; local data preserved; no duplicates | [ ] | [ ] | [ ] |
| M-X-008 | Dark mode toggle | Switch system appearance while app is open | Theme updates in real time; no flash of wrong colors | [ ] | [ ] | [ ] |
| M-X-009 | Low power mode | Enable Low Power Mode | App functional; background refreshes reduced; no crashes | [ ] | [ ] | [ ] |
| M-X-010 | Keyboard dismissal | Open any text field, then swipe down | Keyboard dismisses; no overlapping UI | [ ] | [ ] | [ ] |
| M-X-011 | Haptic feedback correctness | Perform actions mapped to haptics | Correct haptic type fires for each action (success, light, warning, etc.) | [ ] | [ ] | [ ] |
| M-X-012 | Large text accessibility | Set system text to largest | All screens remain usable; no truncation; scrollable where needed | [ ] | [ ] | [ ] |

---

## Summary

| Category | Test Count | Automated | Manual |
|----------|-----------|-----------|--------|
| Unit -- iOS (HealthKit, Training, Recovery, Scoring, Notifications) | ~95 | Yes | No |
| Unit -- Backend (Auth, Arena, Whoop) | ~47 | Yes | No |
| Integration | ~19 | Yes | No |
| UI Tests (XCUITest) | ~39 | Yes | No |
| Snapshot Tests | ~60+ | Yes | No |
| Performance Tests | ~19 | Yes | No |
| API Contract Tests | ~18 | Yes | No |
| Edge Case Tests | ~20 | Yes | No |
| Accessibility Tests | ~20 | Partial | Partial |
| Manual Tests | ~55 | No | Yes |
| **Total** | **~392** | **~315** | **~77** |

**Coverage targets on merge to main:** 80% unit, 60% integration, all snapshots passing, all UI tests green. No merge with failing tests.
