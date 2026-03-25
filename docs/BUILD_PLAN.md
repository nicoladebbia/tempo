# Tempo — Exhaustive Dependency-Ordered Build Plan

> **Version:** 1.0.0
> **Created:** 2026-03-24
> **Author:** Build Engineering
> **Purpose:** Every step in this plan depends ONLY on things built in previous steps. A developer can pick up any step, read the referenced docs, and build it without asking a single question.
> **Invariant:** If step X.Y needs something, that something was built in a prior step. No exceptions.

---

## How to Use This Plan

1. **Work sequentially within each phase.** Steps within a phase are ordered by dependency.
2. **Parallelizable phases are marked in the Dependency Graph** at the end of this document.
3. **Each step is 1-4 hours.** If it takes longer, something is wrong — re-read the referenced docs.
4. **Acceptance criteria are binary.** Either the criteria is met or it is not. No "mostly done."
5. **File paths are relative to the project root** (`Tempo/` for iOS, `tempo-backend/` for Vapor).

---

## Phase 0: Project Scaffolding

**Prerequisites:** None — this is the starting point.
**Docs to reference:** `docs/XCODE_PROJECT_STRUCTURE.md`, `docs/VAPOR_PROJECT_STRUCTURE.md`, `docs/DEPENDENCIES.md`

---

### 0.1 Initialize Git Repository and Branch Strategy

**Time estimate:** 30 minutes
**Prerequisites:** None
**Docs:** `docs/XCODE_PROJECT_STRUCTURE.md` Section 2 (folder structure), `docs/CI_CD_PIPELINE.md` Section 1 (Git Workflow — branch naming, trunk-based development)
**What to build:**
- Create the root project directory `~/Projects/tempo/`
- Initialize a git repository with `git init`
- Create `.gitignore` with entries for: `.DS_Store`, `*.xcuserstate`, `DerivedData/`, `*.xcworkspace/xcuserdata/`, `.build/`, `Packages/`, `.env`, `Secrets.xcconfig`, `*.p8`, `node_modules/`
- Create initial branch: `main`
- Create development branch: `git checkout -b develop`
- Commit the gitignore and any existing docs

**Acceptance criteria:**
- `git status` runs cleanly in the repo root
- `.gitignore` excludes all listed patterns
- `develop` branch exists and is checked out
- Existing `docs/` directory is tracked

**Files created/modified:**
- `.gitignore`

---

### 0.2 Create Xcode Project with Correct Settings

**Time estimate:** 1 hour
**Prerequisites:** 0.1
**Docs:** `docs/XCODE_PROJECT_STRUCTURE.md` Section 1 (Project Creation), `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 4 (SwiftData Concerns — iOS 17.4+ minimum), `docs/ARCHITECTURE_DECISIONS.md` ADR-001 to ADR-003 (background reading — why native iOS, SwiftUI, SwiftData)
**What to build:**
- Open Xcode 16+ → File → New → Project → iOS App
- Product Name: `Tempo`
- Organization Identifier: `app.tempo`
- Bundle Identifier: `app.tempo.Tempo`
- Interface: SwiftUI
- Language: Swift
- Storage: SwiftData
- Include Tests: Yes (Unit + UI)
- Set iOS Deployment Target to `17.4` (per `TECHNICAL_FEASIBILITY_AUDIT.md` Section 4.1 — avoids buggiest SwiftData versions)
- Set Swift Language Version to Swift 6
- Set Strict Concurrency Checking to Complete

**Acceptance criteria:**
- Project builds and runs on iOS 17.4+ simulator with the default "Hello World" template
- Bundle ID is `app.tempo.Tempo`
- Swift 6 and strict concurrency are enabled (verify in Build Settings)
- Both `TempoTests` and `TempoUITests` targets exist

**Files created/modified:**
- `Tempo/Tempo.xcodeproj`
- `Tempo/TempoApp.swift`
- `Tempo/ContentView.swift`

---

### 0.3 Create Folder Structure (iOS)

**Time estimate:** 1 hour
**Prerequisites:** 0.2
**Docs:** `docs/XCODE_PROJECT_STRUCTURE.md` Section 2 (Complete File/Folder Structure)
**What to build:**
Create every folder as a Group in Xcode (mirrored on disk). Do NOT create any Swift files yet — just the directory tree:

```
Tempo/
├── Configuration/
├── App/
├── Models/
│   ├── Schema/
│   ├── Enums/
│   ├── SharedTypes/
│   ├── User/
│   ├── Dashboard/
│   ├── Training/
│   ├── Accountability/
│   ├── Recovery/
│   ├── Arena/
│   ├── Sync/
│   ├── Integrations/
│   └── DTOs/
├── Services/
│   ├── Network/
│   ├── Auth/
│   ├── Health/
│   ├── Integrations/
│   ├── Sync/
│   ├── Notifications/
│   └── Engines/
├── Views/
│   ├── Dashboard/
│   ├── Training/
│   ├── Accountability/
│   ├── Recovery/
│   ├── Arena/
│   ├── Onboarding/
│   └── Shared/
│       ├── Components/
│       ├── Modifiers/
│       └── Styles/
├── ViewModels/
├── Utilities/
│   ├── Extensions/
│   ├── Helpers/
│   └── Constants/
├── Resources/
│   ├── Assets.xcassets/
│   │   └── Colors/
│   ├── Sounds/
│   └── (Exercises.json placeholder)
├── Preview Content/
├── TempoTests/
│   ├── Engines/
│   ├── Services/
│   ├── Models/
│   ├── Mocks/
│   └── Helpers/
├── TempoUITests/
└── TempoSnapshotTests/
```

**Acceptance criteria:**
- Every folder listed above exists in both Xcode's project navigator and on disk
- Project still builds without errors
- Folders are yellow (group folders), not blue (folder references)

**Files created/modified:**
- All directories listed above (empty)

---

### 0.4 Configure Entitlements

**Time estimate:** 30 minutes
**Prerequisites:** 0.2
**Docs:** `docs/XCODE_PROJECT_STRUCTURE.md` Section 4 (Capabilities & Entitlements)
**What to build:**
In Xcode Target → Signing & Capabilities → `+ Capability`, add:
1. **HealthKit** (do NOT check Clinical Health Records)
2. **Push Notifications**
3. **Sign in with Apple**
4. **Background Modes** — check exactly: Background fetch, Remote notifications, Background processing
5. **App Groups** — add group: `group.app.tempo`
6. **Keychain Sharing** — access group: `$(TeamIdentifierPrefix)app.tempo.shared`
7. **In-App Purchase**

**Acceptance criteria:**
- `Tempo.entitlements` file exists with all 7 capabilities
- HealthKit entitlement present WITHOUT clinical health records
- Background Modes has exactly 3 modes checked
- App Group identifier is `group.app.tempo`
- Project still builds

**Files created/modified:**
- `Tempo/Tempo.entitlements`

---

### 0.5 Set Up Build Configurations (Debug/Staging/Release)

**Time estimate:** 1 hour
**Prerequisites:** 0.2
**Docs:** `docs/XCODE_PROJECT_STRUCTURE.md` Section 3 (Build Configurations)
**What to build:**
1. In Xcode Project → Info → Configurations, duplicate Debug to create "Staging"
2. Create four xcconfig files:
   - `Tempo/Configuration/Development.xcconfig` — localhost API, debug flags, bundle ID `app.tempo.Tempo.dev`
   - `Tempo/Configuration/Staging.xcconfig` — staging API, bundle ID `app.tempo.Tempo.staging`
   - `Tempo/Configuration/Production.xcconfig` — production API, bundle ID `app.tempo.Tempo`
   - `Tempo/Configuration/Secrets.xcconfig` — placeholder for future keys, git-ignored
3. Assign xcconfigs to configurations in Project → Info
4. Add `TEMPO_API_BASE_URL` and `TEMPO_ENVIRONMENT` to Info.plist
5. Create `Tempo/Utilities/Constants/AppConstants.swift` that reads these values from the bundle

**Acceptance criteria:**
- Three build configurations exist: Debug, Staging, Release
- Each xcconfig file exists with correct values (copy exactly from doc)
- `AppConstants.apiBaseURL` returns the correct URL for each configuration
- `Secrets.xcconfig` is in `.gitignore`
- Building with Debug scheme uses `app.tempo.Tempo.dev` bundle ID

**Files created/modified:**
- `Tempo/Configuration/Development.xcconfig`
- `Tempo/Configuration/Staging.xcconfig`
- `Tempo/Configuration/Production.xcconfig`
- `Tempo/Configuration/Secrets.xcconfig`
- `Tempo/Utilities/Constants/AppConstants.swift`
- `Tempo/Info.plist` (add TEMPO_ keys)

---

### 0.6 Add SPM Dependencies (iOS)

**Time estimate:** 30 minutes
**Prerequisites:** 0.2
**Docs:** `docs/DEPENDENCIES.md` Section 2.17 (iOS Dependency Summary)
**What to build:**
In Xcode → File → Add Package Dependencies, add exactly three packages:
1. **PostHog iOS SDK** — `https://github.com/PostHog/posthog-ios` (latest 3.x)
2. **Firebase iOS SDK** — `https://github.com/firebase/firebase-ios-sdk` (latest 11.x) → add ONLY `FirebaseCrashlytics` product
3. **Lottie** — `https://github.com/airbnb/lottie-ios` (latest 4.x)
4. **swift-snapshot-testing** — `https://github.com/pointfreeco/swift-snapshot-testing` (latest 1.x) → add to **TempoSnapshotTests** target ONLY

**Acceptance criteria:**
- All four packages resolve and build
- Only `FirebaseCrashlytics` from Firebase (not Analytics, not Remote Config)
- `swift-snapshot-testing` linked only to test target, not main target
- Total third-party binary budget: ~6.8MB (under 15MB cap)
- Project builds without errors

**Files created/modified:**
- `Tempo.xcodeproj/project.pbxproj` (package references added)

---

### 0.7 Set Up SwiftLint + SwiftFormat

**Time estimate:** 30 minutes
**Prerequisites:** 0.2
**Docs:** `docs/XCODE_PROJECT_STRUCTURE.md` Section 7 (Build Phases), Section 12 (Coding Standards)
**What to build:**
1. Install SwiftLint: `brew install swiftlint`
2. Create `.swiftlint.yml` at project root with rules matching Swift 6 strict concurrency (disable `trailing_comma`, enable `force_cast`, `force_unwrapping`)
3. Add a Run Script Build Phase in Xcode: `swiftlint lint --config ../.swiftlint.yml` (runs on every build)
4. Create `.swiftformat` config at project root (indent: 4 spaces, `--swiftversion 6.0`)

**Acceptance criteria:**
- `swiftlint lint` runs without configuration errors
- Build Phase appears in Xcode and runs on build
- `.swiftlint.yml` and `.swiftformat` exist at project root
- No lint errors on the empty project

**Files created/modified:**
- `.swiftlint.yml`
- `.swiftformat`
- Build phase in Xcode project

---

### 0.8 Create Vapor Backend Project

**Time estimate:** 1 hour
**Prerequisites:** 0.1
**Docs:** `docs/VAPOR_PROJECT_STRUCTURE.md` Sections 1-3 (Project Creation, File Structure, Package.swift)
**What to build:**
1. `vapor new tempo-backend --fluent.db postgres --no-leaf`
2. Replace the auto-generated `Package.swift` with the exact one from the doc (includes Vapor, Fluent, FluentPostgresDriver, JWT, Redis, Queues, QueuesRedisDriver, VaporAPNS)
3. Create the folder structure from `docs/VAPOR_PROJECT_STRUCTURE.md` Section 2:
   - `Sources/App/Controllers/`
   - `Sources/App/Models/`
   - `Sources/App/Migrations/`
   - `Sources/App/DTOs/`
   - `Sources/App/Services/`
   - `Sources/App/Middleware/`
   - `Sources/App/Jobs/`
   - `Sources/App/Extensions/`
   - `Tests/AppTests/Helpers/`
   - `Tests/AppTests/Stubs/`
   - `Resources/Seed/`
4. Create `entrypoint.swift` from the doc (Section 4)
5. Create placeholder `configure.swift` and `routes.swift`
6. Create `.env.example` with all required environment variables

**Acceptance criteria:**
- `swift build` succeeds in the `tempo-backend/` directory
- All packages resolve (Vapor, Fluent, PostgreSQL driver, JWT, Redis, Queues, APNs)
- Folder structure matches doc exactly
- `.env.example` lists all required keys (DATABASE_URL, JWT_SECRET, WHOOP_*, NUTRITRACK_*, ANTHROPIC_API_KEY, APNS_*)

**Files created/modified:**
- `tempo-backend/Package.swift`
- `tempo-backend/Sources/App/entrypoint.swift`
- `tempo-backend/Sources/App/configure.swift`
- `tempo-backend/Sources/App/routes.swift`
- `tempo-backend/.env.example`
- All subdirectories listed above

---

### 0.9 Set Up Docker Compose (PostgreSQL + Redis)

**Time estimate:** 30 minutes
**Prerequisites:** 0.8
**Docs:** `docs/VAPOR_PROJECT_STRUCTURE.md` Section 10 (Docker Setup)
**What to build:**
1. Create `tempo-backend/docker-compose.yml` with:
   - PostgreSQL 16 service (port 5432, user: `tempo`, password: `tempo_dev`, db: `tempo`)
   - Redis 7 service (port 6379)
   - Volume mounts for data persistence
2. Create `tempo-backend/Dockerfile` for building the Vapor app
3. Create `tempo-backend/.dockerignore`
4. Create `tempo-backend/.env` (copy from `.env.example`, fill dev values)
5. Add `.env` to `.gitignore`

**Acceptance criteria:**
- `docker compose up -d db redis` starts both services
- `docker compose exec db pg_isready` returns success
- `docker compose exec redis redis-cli ping` returns PONG
- Vapor app can connect to PostgreSQL: run `swift run` and verify it starts (even if no routes work yet)

**Files created/modified:**
- `tempo-backend/docker-compose.yml`
- `tempo-backend/Dockerfile`
- `tempo-backend/.dockerignore`
- `tempo-backend/.env`

---

### 0.10 Create Shared Enums and Constants (iOS)

**Time estimate:** 2 hours
**Prerequisites:** 0.3
**Docs:** `docs/DATA_MODELS_IOS.md` Section 2 (Enums & Shared Types), `docs/EXERCISE_SCIENCE.md` Section 10 (Glossary of Terms — background reading for enum naming)
**What to build:**
Create all enum files with the exact definitions from the doc:
1. `Tempo/Models/Enums/WorkoutEnums.swift` — `WorkoutType`, `WorkoutStatus`, `MuscleGroup`, `Equipment`, `MovementPattern`, `PRType`
2. `Tempo/Models/Enums/AccountabilityEnums.swift` — `NonNegotiableType`, `TrackingMethod`, `StudySessionType`, `StreakType`
3. `Tempo/Models/Enums/RecoveryEnums.swift` — `RecoveryZone`, `RecoveryInsightType`
4. `Tempo/Models/Enums/ArenaEnums.swift` — `XPSource`, `AchievementCategory`, `AchievementRarity`
5. `Tempo/Models/Enums/SyncEnums.swift` — `SyncAction`
6. `Tempo/Models/SharedTypes/WeightUnit.swift` — `WeightUnit` with conversion
7. `Tempo/Models/SharedTypes/TrainingSplit.swift` — `TrainingSplit`
8. `Tempo/Models/SharedTypes/ActiveDays.swift` — `ActiveDays` bitmask struct

All enums must conform to `String, Codable, CaseIterable`. Include all computed properties (`displayName`, `isGymWorkout`, `defaultIcon`, `color`, `xpMultiplier`, etc.) exactly as specified in the doc.

**Acceptance criteria:**
- All 8 files exist and compile
- Every enum case matches the doc (verify against DATA_MODELS_IOS.md Section 2)
- `WeightUnit.kg.convert(100, to: .lbs)` returns `220.462`
- `ActiveDays.weekdays.isActive(on: 2)` returns `true` (Monday)
- All enums serialize/deserialize via Codable round-trip (write a quick test)

**Files created/modified:**
- `Tempo/Models/Enums/WorkoutEnums.swift`
- `Tempo/Models/Enums/AccountabilityEnums.swift`
- `Tempo/Models/Enums/RecoveryEnums.swift`
- `Tempo/Models/Enums/ArenaEnums.swift`
- `Tempo/Models/Enums/SyncEnums.swift`
- `Tempo/Models/SharedTypes/WeightUnit.swift`
- `Tempo/Models/SharedTypes/TrainingSplit.swift`
- `Tempo/Models/SharedTypes/ActiveDays.swift`

---

## Phase 1: Data Models (iOS)

**Prerequisites:** Phase 0 (specifically 0.2, 0.3, 0.10)
**Docs to reference:** `docs/DATA_MODELS_IOS.md` (all sections)

---

### 1.1 User Models (UserProfile, UserSettings)

**Time estimate:** 2 hours
**Prerequisites:** 0.10 (enums needed for UserProfile fields)
**Docs:** `docs/DATA_MODELS_IOS.md` Section 3 (User & Settings Models)
**What to build:**
1. `Tempo/Models/User/UserProfile.swift` — `@Model` class with all fields: id, appleID, username, displayName, avatarURL, timezone, weightKg, heightCm, age, trainingSplitRaw, footballDaysRaw, equipmentJSON, weightUnitRaw, createdAt, updatedAt. Include all `@Transient` computed properties and the DTO extension.
2. `Tempo/Models/User/UserSettings.swift` — `@Model` class with notification preferences, weight unit preference, theme, notification intensity level, bedtime target, wake time target, and other settings.

Copy the exact model definitions from the doc. Do not deviate.

**Acceptance criteria:**
- Both files compile with no errors under strict concurrency
- `UserProfile` has validation (`validate()` method) that enforces username 3-30 chars, display name 1-50 chars, weight 30-300kg, height 100-250cm, age 13-100
- `UserProfile.toDTO()` produces a valid Codable struct
- `UserProfile.apply(dto:)` updates the model from a DTO
- `@Transient` properties (`trainingSplit`, `footballDays`, `equipment`, `weightUnit`, `estimatedBMR`) work correctly

**Files created/modified:**
- `Tempo/Models/User/UserProfile.swift`
- `Tempo/Models/User/UserSettings.swift`

---

### 1.2 Dashboard Models (DailySnapshot)

**Time estimate:** 1 hour
**Prerequisites:** 0.10
**Docs:** `docs/DATA_MODELS_IOS.md` Section 4 (Dashboard Models), `ARCHITECTURE.md` (DailySnapshot definition)
**What to build:**
`Tempo/Models/Dashboard/DailySnapshot.swift` — `@Model` class aggregating all daily metrics:
- Body: recoveryScore, hrv, rhr, sleepHours, sleepScore, strain
- Fuel: caloriesConsumed, calorieTarget, proteinG, carbsG, fatG, mealsLogged, mealsPlanned
- Mind: studyMinutes, studyTarget, examCountdown
- Move: steps, activeCalories, workoutCompleted, workoutType
- Score: dailyScore (0-100), nonNegotiablesCompleted, nonNegotiablesTotal
- Timestamps and sync metadata

Include a computed `completionPercentage` and a `date` attribute with `@Attribute(.unique)` (one snapshot per day).

**Acceptance criteria:**
- File compiles
- `@Attribute(.unique)` on the date field (enforces one snapshot per calendar day)
- All optional fields (recovery, HRV, etc.) are properly optional
- All non-optional fields have sensible defaults in the initializer

**Files created/modified:**
- `Tempo/Models/Dashboard/DailySnapshot.swift`

---

### 1.3 Training Models

**Time estimate:** 3 hours
**Prerequisites:** 0.10 (WorkoutType, MuscleGroup, Equipment, etc.)
**Docs:** `docs/DATA_MODELS_IOS.md` Section 5 (Training Models)
**What to build:**
1. `Tempo/Models/Training/Exercise.swift` — `@Model` with name, muscleGroup, equipment, isCompound, movementPattern, instructions, personalBest. Include `@Relationship` to ExerciseHistory.
2. `Tempo/Models/Training/WorkoutPlan.swift` — `@Model` with date, type, recoveryAdjustment, status, notes. `@Relationship(.cascade)` to PlannedExercise array.
3. `Tempo/Models/Training/PlannedExercise.swift` — `@Model` with exercise reference, order, supersetGroup. `@Relationship(.cascade)` to PlannedSet array.
4. `Tempo/Models/Training/PlannedSet.swift` — `@Model` with targetReps, targetWeight, actualReps, actualWeight, rpe, completed, setType (warmup/working/dropset/amrap).
5. `Tempo/Models/Training/ExerciseHistory.swift` — `@Model` tracking historical performance: date, exercise reference, totalVolume, estimated1RM, bestSetWeight, bestSetReps.
6. `Tempo/Models/Training/PersonalRecord.swift` — `@Model` with exercise reference, prType, value, date, previousValue.
7. `Tempo/Models/Training/RunSession.swift` — `@Model` with date, distance, duration, avgPace, avgHeartRate, route (optional encoded CLLocationCoordinate2D array).

**Acceptance criteria:**
- All 7 files compile
- Cascade delete: deleting a WorkoutPlan deletes its PlannedExercises, which delete their PlannedSets
- WorkoutPlan.status uses `WorkoutStatus` enum (from 0.10)
- Exercise has proper relationship to ExerciseHistory (inverse relationship)
- All models have Codable DTO counterparts for API sync

**Files created/modified:**
- `Tempo/Models/Training/Exercise.swift`
- `Tempo/Models/Training/WorkoutPlan.swift`
- `Tempo/Models/Training/PlannedExercise.swift`
- `Tempo/Models/Training/PlannedSet.swift`
- `Tempo/Models/Training/ExerciseHistory.swift`
- `Tempo/Models/Training/PersonalRecord.swift`
- `Tempo/Models/Training/RunSession.swift`

---

### 1.4 Accountability Models

**Time estimate:** 2 hours
**Prerequisites:** 0.10 (NonNegotiableType, TrackingMethod, StudySessionType, StreakType)
**Docs:** `docs/DATA_MODELS_IOS.md` Section 6 (Accountability Models)
**What to build:**
1. `Tempo/Models/Accountability/NonNegotiable.swift` — `@Model` with name, type, targetValue, unit, trackingMethod, integrationSource, icon, isActive, sortOrder.
2. `Tempo/Models/Accountability/DailyAccountability.swift` — `@Model` with date, leisureUnlocked, leisureUnlockedAt, totalStudyMinutes, score. `@Relationship(.cascade)` to NonNegotiableProgress array.
3. `Tempo/Models/Accountability/NonNegotiableProgress.swift` — `@Model` with nonNegotiable reference, currentValue, isCompleted, completedAt, autoTrackedAt.
4. `Tempo/Models/Accountability/StudySession.swift` — `@Model` with date, type (pomodoro/deepWork/custom), durationMinutes, subject, focusScore, interruptionCount, startedAt, endedAt.
5. `Tempo/Models/Accountability/Streak.swift` — `@Model` with type (overall/study/training/meals), currentLength, longestLength, lastActiveDate, freezesRemaining, freezesUsed.

**Acceptance criteria:**
- All 5 files compile
- DailyAccountability has cascade delete to NonNegotiableProgress
- NonNegotiable is a template (user-defined requirement), NonNegotiableProgress is the daily instance
- Streak model tracks both current and longest streak with freeze mechanics
- StudySession stores start/end times for duration calculation

**Files created/modified:**
- `Tempo/Models/Accountability/NonNegotiable.swift`
- `Tempo/Models/Accountability/DailyAccountability.swift`
- `Tempo/Models/Accountability/NonNegotiableProgress.swift`
- `Tempo/Models/Accountability/StudySession.swift`
- `Tempo/Models/Accountability/Streak.swift`

---

### 1.5 Recovery Models

**Time estimate:** 1.5 hours
**Prerequisites:** 0.10 (RecoveryZone, RecoveryInsightType)
**Docs:** `docs/DATA_MODELS_IOS.md` Section 7 (Recovery Models)
**What to build:**
1. `Tempo/Models/Recovery/DailyRecovery.swift` — `@Model` with date, recoveryScore, recoveryZone (computed from score), hrvRmssd, restingHR, spo2, skinTemp, sleepHours, sleepScore, sleepDebt, sleepEfficiency, sleepConsistency, strain, dayStrain, source (whoop/healthkit/manual).
2. `Tempo/Models/Recovery/DailyPrescription.swift` — `@Model` with date, recoveryZone, trainingRecommendation, mealTimingRecommendation, bedtimeRecommendation, hydrationTargetMl, caffeineCutoff, warnings (JSON-encoded string array), wasFollowed.
3. `Tempo/Models/Recovery/RecoveryInsight.swift` — `@Model` with type (correlation/pattern/recommendation), title, body, dateRange, confidence, relatedMetrics.

**Acceptance criteria:**
- All 3 files compile
- DailyRecovery has `@Attribute(.unique)` on date
- RecoveryZone is computed from recoveryScore using the thresholds: green >= 67, yellow 34-66, red < 34
- DailyPrescription stores warnings as JSON-encoded array of strings
- RecoveryInsight has a confidence score (0.0-1.0)

**Files created/modified:**
- `Tempo/Models/Recovery/DailyRecovery.swift`
- `Tempo/Models/Recovery/DailyPrescription.swift`
- `Tempo/Models/Recovery/RecoveryInsight.swift`

---

### 1.6 Arena Models

**Time estimate:** 1.5 hours
**Prerequisites:** 0.10 (XPSource, AchievementCategory, AchievementRarity)
**Docs:** `docs/DATA_MODELS_IOS.md` Section 8 (Arena Models)
**What to build:**
1. `Tempo/Models/Arena/XPEvent.swift` — `@Model` with id, source (XPSource), amount (positive or negative), reason (human-readable string), date, createdAt. Accumulated XP calculated from queries, not stored.
2. `Tempo/Models/Arena/Achievement.swift` — `@Model` with id, definitionKey (maps to Achievements.json), category, rarity, earnedAt, isNew (for unread badge).
3. `Tempo/Models/Arena/ChallengeLocal.swift` — `@Model` caching server-side challenge state: id, name, description, metric, startDate, endDate, creatorUsername, myScore, leaderPosition, participantCount, status (active/completed/cancelled).

**Acceptance criteria:**
- All 3 files compile
- XPEvent.amount can be negative (for penalties)
- Achievement.definitionKey is a string that maps to the JSON definitions file
- ChallengeLocal is a cache model (server is authoritative) with a `lastSyncedAt` field

**Files created/modified:**
- `Tempo/Models/Arena/XPEvent.swift`
- `Tempo/Models/Arena/Achievement.swift`
- `Tempo/Models/Arena/ChallengeLocal.swift`

---

### 1.7 Sync Models

**Time estimate:** 1 hour
**Prerequisites:** 0.10 (SyncAction)
**Docs:** `docs/DATA_MODELS_IOS.md` Section 9 (Sync Models)
**What to build:**
1. `Tempo/Models/Sync/SyncState.swift` — `@Model` with entityType (string, e.g. "workout_plan"), lastSyncedAt, lastServerTimestamp, etag (for conditional requests).
2. `Tempo/Models/Sync/PendingSync.swift` — `@Model` with id, entityType, entityID (UUID), action (create/update/delete), payload (JSON Data), createdAt, retryCount, lastAttemptAt, error (last failure reason).

**Acceptance criteria:**
- Both files compile
- PendingSync acts as an offline queue: items are created when offline, processed when connectivity returns
- PendingSync.retryCount increments on failure, items are dropped after 5 retries
- SyncState tracks per-entity-type sync timestamps

**Files created/modified:**
- `Tempo/Models/Sync/SyncState.swift`
- `Tempo/Models/Sync/PendingSync.swift`

---

### 1.8 Integration State Models

**Time estimate:** 1 hour
**Prerequisites:** 0.10
**Docs:** `docs/DATA_MODELS_IOS.md` Section 10 (Integration State Models)
**What to build:**
1. `Tempo/Models/Integrations/WhoopConnection.swift` — `@Model` with connectionState (disconnected/connecting/connected/error), lastSyncAt, whoopUserID, membershipType, errorMessage.
2. `Tempo/Models/Integrations/NutriTrackConnection.swift` — `@Model` with connectionState, lastSyncAt, nutriTrackBaseURL, errorMessage.
3. `Tempo/Models/Integrations/HealthKitState.swift` — `@Model` with authorizationStatus per type (steps, heartRate, HRV, sleep, etc.), lastQueryTimestamps per type.

**Acceptance criteria:**
- All 3 files compile
- WhoopConnection tracks the full OAuth state (disconnected through connected)
- HealthKitState stores per-type authorization status to avoid re-querying HKHealthStore on every launch
- NutriTrackConnection stores the base URL for the Flask proxy

**Files created/modified:**
- `Tempo/Models/Integrations/WhoopConnection.swift`
- `Tempo/Models/Integrations/NutriTrackConnection.swift`
- `Tempo/Models/Integrations/HealthKitState.swift`

---

### 1.9 ModelContainer Configuration + Migration Setup

**Time estimate:** 1.5 hours
**Prerequisites:** 1.1 through 1.8 (all models must exist)
**Docs:** `docs/DATA_MODELS_IOS.md` Section 1 (Schema Configuration & ModelContainer)
**What to build:**
1. `Tempo/Models/Schema/TempoSchemaV1.swift` — `VersionedSchema` listing ALL 27 model types
2. `Tempo/Models/Schema/TempoSchemaV2.swift` — Placeholder for future migrations
3. `Tempo/Models/Schema/TempoMigrationPlan.swift` — `SchemaMigrationPlan` with lightweight V1→V2 stage
4. `Tempo/Models/Schema/TempoModelContainer.swift` — Factory with `create(inMemory:)` and `preview()` methods. Uses `group.app.tempo` for App Groups. CloudKit disabled.
5. Update `Tempo/TempoApp.swift` to use `TempoModelContainer.create()` and inject `.modelContainer(container)`

**Acceptance criteria:**
- App launches on simulator without SwiftData crash
- `TempoSchemaV1.models` contains exactly 27 types (count them)
- Preview container works with `inMemory: true`
- ModelContainer uses `group.app.tempo` group container
- CloudKit is explicitly disabled (`cloudKitDatabase: .none`)

**Files created/modified:**
- `Tempo/Models/Schema/TempoSchemaV1.swift`
- `Tempo/Models/Schema/TempoSchemaV2.swift`
- `Tempo/Models/Schema/TempoMigrationPlan.swift`
- `Tempo/Models/Schema/TempoModelContainer.swift`
- `Tempo/TempoApp.swift` (modified)

---

### 1.10 Exercise Library Seed Data

**Time estimate:** 3 hours
**Prerequisites:** 1.3 (Exercise model)
**Docs:** `docs/DATA_MODELS_IOS.md` Section 5, `ARCHITECTURE.md` (exercise library reference), `docs/EXERCISE_SCIENCE.md`
**What to build:**
1. `Tempo/Resources/Exercises.json` — JSON file with 132+ exercises, each containing:
   - `name`, `muscleGroup`, `secondaryMuscles`, `equipment`, `movementPattern`, `isCompound`, `defaultSets`, `defaultReps`, `restSeconds`, `instructions`, `tips`
2. `Tempo/Services/Engines/ExerciseLibraryLoader.swift` — Service that loads `Exercises.json` and inserts into SwiftData on first launch (check if exercise count > 0 before inserting)

Exercises must cover: Chest (bench press, incline DB, cable fly, dips, etc.), Back (deadlift, rows, pullups, lat pulldown, etc.), Shoulders (OHP, lateral raise, face pull, etc.), Arms (curl variations, tricep extensions, etc.), Legs (squat, leg press, RDL, lunges, leg curl, leg extension, calf raise, etc.), Core (plank, cable crunch, hanging leg raise, etc.), and Cardio/Conditioning entries.

**Acceptance criteria:**
- `Exercises.json` parses without error
- At least 132 exercises across all muscle groups
- Every exercise has valid `muscleGroup`, `equipment`, and `movementPattern` values that match the enums from 0.10
- `ExerciseLibraryLoader` is idempotent (running twice does not duplicate exercises)
- On first app launch, exercises appear in SwiftData

**Files created/modified:**
- `Tempo/Resources/Exercises.json`
- `Tempo/Services/Engines/ExerciseLibraryLoader.swift`

---

## Phase 2: Service Layer Stubs (iOS)

**Prerequisites:** Phase 1 (models must exist for service interfaces to reference them)
**Docs to reference:** `docs/INTEGRATION_SPECS.md`, `docs/DATA_FLOW_ARCHITECTURE.md`, `docs/XCODE_PROJECT_STRUCTURE.md` Section 2 (Services folder)

All services in this phase follow the same pattern: define a protocol, create a stub/mock implementation that returns hardcoded data, and create the real class shell. Views built in Phase 4 will use these stubs.

---

### 2.1 Network Client (APIClient)

**Time estimate:** 2 hours
**Prerequisites:** 0.5 (AppConstants for base URL), 0.10
**Docs:** `docs/DEPENDENCIES.md` Section 2.1 (Networking), `docs/XCODE_PROJECT_STRUCTURE.md` (Services/Network), `docs/ERROR_RECOVERY_FLOWS.md` Sections 7-8 (Error Severity Classification, Global Retry Policy)
**What to build:**
1. `Tempo/Services/Network/APIClient.swift` — URLSession-based HTTP client with:
   - Generic `request<T: Decodable>` method (GET, POST, PUT, DELETE, PATCH)
   - JWT token injection via `Authorization: Bearer` header
   - Automatic token refresh on 401 (call AuthService to refresh, then retry)
   - Retry with exponential backoff (3 attempts, 1s/2s/4s)
   - ETag caching support
   - Request/response logging in DEBUG
   - `X-Client-Version`, `X-Device-Id`, `Idempotency-Key` headers
2. `Tempo/Services/Network/APIEndpoints.swift` — Typed endpoint definitions (path, HTTP method, body type)
3. `Tempo/Services/Network/APIError.swift` — Typed error enum with user-facing messages
4. `Tempo/Services/Network/AuthInterceptor.swift` — JWT refresh logic and token storage coordination

**Acceptance criteria:**
- `APIClient` compiles and can be instantiated
- A GET request to a test endpoint succeeds (use a mock URLProtocol in tests)
- 401 triggers a token refresh flow (stubbed for now)
- ETag header is sent when cached
- Retry logic retries up to 3 times with backoff
- All API errors map to user-facing messages

**Files created/modified:**
- `Tempo/Services/Network/APIClient.swift`
- `Tempo/Services/Network/APIEndpoints.swift`
- `Tempo/Services/Network/APIError.swift`
- `Tempo/Services/Network/AuthInterceptor.swift`

---

### 2.2 Auth Service + Keychain

**Time estimate:** 2 hours
**Prerequisites:** 2.1 (APIClient)
**Docs:** `docs/XCODE_PROJECT_STRUCTURE.md` (Services/Auth), `docs/DEPENDENCIES.md` Section 2.4 (Keychain)
**What to build:**
1. `Tempo/Services/Auth/KeychainService.swift` — Thin wrapper (~50 lines) around Security framework: `save(key:data:)`, `load(key:)`, `delete(key:)`, `deleteAll()`. Uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
2. `Tempo/Services/Auth/AuthService.swift` — `@Observable` class with:
   - `authState`: `.unauthenticated`, `.authenticated(userID: UUID)`, `.expired`
   - `signInWithApple()` — placeholder that stores a mock JWT
   - `refreshToken()` — placeholder
   - `signOut()` — clears Keychain, resets state
   - Reads/writes JWT access token and refresh token to Keychain

**Acceptance criteria:**
- `KeychainService.save` and `KeychainService.load` round-trip Data correctly
- `AuthService` can transition between all three states
- `signOut()` clears both tokens from Keychain
- `AuthService.authState` is `@Observable` and triggers view updates

**Files created/modified:**
- `Tempo/Services/Auth/KeychainService.swift`
- `Tempo/Services/Auth/AuthService.swift`

---

### 2.3 HealthKit Service (Protocol + Stub)

**Time estimate:** 1.5 hours
**Prerequisites:** 1.2 (DailySnapshot), 1.5 (DailyRecovery)
**Docs:** `docs/INTEGRATION_SPECS.md` Section 2 (Apple HealthKit Integration)
**What to build:**
1. `Tempo/Services/Health/HealthKitServiceProtocol.swift` — Protocol defining:
   - `requestAuthorization() async throws`
   - `fetchSteps(for date: Date) async throws -> Int`
   - `fetchActiveEnergy(for date: Date) async throws -> Double`
   - `fetchHeartRate(for date: Date) async throws -> [HeartRateSample]`
   - `fetchHRV(for date: Date) async throws -> Double?`
   - `fetchRestingHeartRate(for date: Date) async throws -> Double?`
   - `fetchSleepAnalysis(for date: Date) async throws -> SleepData`
   - `fetchWorkouts(for date: Date) async throws -> [WorkoutSample]`
   - `writeWorkout(_:) async throws`
   - `writeNutrition(_:) async throws`
   - `enableBackgroundDelivery() async throws`
2. `Tempo/Services/Health/MockHealthKitService.swift` — Returns hardcoded data (8,432 steps, 342 kcal active energy, 68 bpm RHR, 42ms HRV, 7.5h sleep, etc.)

**Acceptance criteria:**
- Protocol compiles with all methods
- MockHealthKitService returns consistent, realistic stub data
- Mock can be injected into any view or service that depends on HealthKit
- No `import HealthKit` in the mock (it returns plain Swift types)

**Files created/modified:**
- `Tempo/Services/Health/HealthKitServiceProtocol.swift`
- `Tempo/Services/Health/MockHealthKitService.swift`

---

### 2.4 Whoop Service (Protocol + Stub)

**Time estimate:** 1 hour
**Prerequisites:** 1.5 (DailyRecovery), 1.8 (WhoopConnection)
**Docs:** `docs/INTEGRATION_SPECS.md` Section 1 (Whoop API Integration)
**What to build:**
1. `Tempo/Services/Integrations/WhoopServiceProtocol.swift` — Protocol:
   - `connectionState: WhoopConnectionState { get }`
   - `connect() async throws`
   - `disconnect() async throws`
   - `fetchRecovery(for date: Date) async throws -> WhoopRecoveryData`
   - `fetchSleep(for date: Date) async throws -> WhoopSleepData`
   - `fetchWorkouts(for date: Date) async throws -> [WhoopWorkoutData]`
   - `fetchCycle(for date: Date) async throws -> WhoopCycleData`
   - `syncAll() async throws`
2. `Tempo/Services/Integrations/MockWhoopService.swift` — Returns hardcoded Whoop-like data (recovery: 72%, HRV: 48ms, RHR: 62bpm, sleep: 7.2h, strain: 12.4)

**Acceptance criteria:**
- Protocol and mock compile
- Mock returns data consistent with a "yellow zone" recovery day
- `connectionState` observable property works in SwiftUI previews

**Files created/modified:**
- `Tempo/Services/Integrations/WhoopServiceProtocol.swift`
- `Tempo/Services/Integrations/MockWhoopService.swift`

---

### 2.5 NutriTrack Service (Protocol + Stub)

**Time estimate:** 1 hour
**Prerequisites:** 1.2 (DailySnapshot — fuel fields)
**Docs:** `docs/INTEGRATION_SPECS.md` Section 3 (NutriTrack Integration)
**What to build:**
1. `Tempo/Services/Integrations/NutriTrackServiceProtocol.swift` — Protocol:
   - `connectionState: NutriTrackConnectionState { get }`
   - `connect(baseURL: URL, pin: String) async throws`
   - `disconnect()`
   - `fetchTodayMeals() async throws -> NutriTrackDayData`
   - `fetchMacroBalance() async throws -> MacroBalance`
   - `fetchWeeklyReport() async throws -> NutriTrackWeeklyReport`
2. `Tempo/Services/Integrations/MockNutriTrackService.swift` — Returns: 2100/2400 kcal, 165g protein, 240g carbs, 72g fat, 3/4 meals logged

**Acceptance criteria:**
- Protocol and mock compile
- Mock data represents a realistic mid-day nutrition state
- NutriTrackDayData includes per-meal breakdown

**Files created/modified:**
- `Tempo/Services/Integrations/NutriTrackServiceProtocol.swift`
- `Tempo/Services/Integrations/MockNutriTrackService.swift`

---

### 2.6 Calendar Service (Protocol + Stub)

**Time estimate:** 1 hour
**Prerequisites:** 0.10
**Docs:** `docs/INTEGRATION_SPECS.md` Section 4 (Apple Calendar/EventKit)
**What to build:**
1. `Tempo/Services/Integrations/CalendarServiceProtocol.swift` — Protocol:
   - `requestAuthorization() async throws`
   - `fetchEvents(for dateRange: DateInterval) async throws -> [CalendarEvent]`
   - `detectFootballDays(in range: DateInterval) -> [Date]`
   - `detectExamDates(in range: DateInterval) -> [CalendarExam]`
   - `detectClassSchedule(for date: Date) -> [CalendarClass]`
2. `Tempo/Services/Integrations/MockCalendarService.swift` — Returns: football on Tue/Thu, exam in 14 days, classes MWF 9-12

**Acceptance criteria:**
- Protocol and mock compile
- CalendarEvent is a plain struct (not an EKEvent dependency)
- Mock football/exam/class detection returns reasonable data

**Files created/modified:**
- `Tempo/Services/Integrations/CalendarServiceProtocol.swift`
- `Tempo/Services/Integrations/MockCalendarService.swift`

---

### 2.7 Notification Service (Protocol + Stub)

**Time estimate:** 1 hour
**Prerequisites:** 0.10
**Docs:** `docs/ONBOARDING_AND_NOTIFICATIONS.md`, `docs/STATE_MACHINES.md` Section 11 (Push Notification Escalation)
**What to build:**
1. `Tempo/Services/Notifications/NotificationServiceProtocol.swift` — Protocol:
   - `requestAuthorization() async throws -> Bool`
   - `scheduleMorningBriefing(for date: Date, content: BriefingContent)`
   - `scheduleAccountabilityEscalation(tier: EscalationTier, time: Date, content: String)`
   - `scheduleMealReminder(mealName: String, time: Date)`
   - `scheduleBedtimeReminder(time: Date)`
   - `cancelAll()`
   - `cancelCategory(_ category: String)`
2. `Tempo/Services/Notifications/MockNotificationService.swift` — Logs all scheduled notifications to console, stores in array for inspection

**Acceptance criteria:**
- Protocol and mock compile
- Mock accumulates scheduled notifications in a `scheduledNotifications` array (useful for testing)
- EscalationTier enum: gentle, firm, urgent, critical

**Files created/modified:**
- `Tempo/Services/Notifications/NotificationServiceProtocol.swift`
- `Tempo/Services/Notifications/MockNotificationService.swift`

---

### 2.8 Training Engine (Protocol + Stub)

**Time estimate:** 1 hour
**Prerequisites:** 1.3 (Training models)
**Docs:** `docs/MODULE_TRAINING.md`, `ARCHITECTURE.md` (Recovery-Based Adjustment Algorithm)
**What to build:**
1. `Tempo/Services/Engines/TrainingEngineProtocol.swift` — Protocol:
   - `generateWorkout(for date: Date, recoveryScore: Double?, footballDays: ActiveDays, split: TrainingSplit) -> WorkoutPlan`
   - `adjustForRecovery(plan: WorkoutPlan, score: Double) -> WorkoutPlan`
   - `calculateProgressiveOverload(for exercise: Exercise, history: [ExerciseHistory]) -> (weight: Double, reps: Int)`
   - `detectPersonalRecord(exercise: Exercise, weight: Double, reps: Int) -> PersonalRecord?`
   - `generateWeekPlan(startDate: Date, recoveryScore: Double?, footballDays: ActiveDays, split: TrainingSplit) -> [WorkoutPlan]`
2. `Tempo/Services/Engines/MockTrainingEngine.swift` — Returns a hardcoded Push day workout with 5 exercises

**Acceptance criteria:**
- Protocol and mock compile
- Mock generates a realistic Push workout (bench press, incline DB, cable fly, tricep pushdown, lateral raise)
- Each exercise has 3-4 sets with target reps and weight

**Files created/modified:**
- `Tempo/Services/Engines/TrainingEngineProtocol.swift`
- `Tempo/Services/Engines/MockTrainingEngine.swift`

---

### 2.9 Recovery Engine (Protocol + Stub)

**Time estimate:** 1 hour
**Prerequisites:** 1.5 (Recovery models)
**Docs:** `docs/MODULE_RECOVERY.md`, `ARCHITECTURE.md` (Prescription Engine)
**What to build:**
1. `Tempo/Services/Engines/RecoveryEngineProtocol.swift` — Protocol:
   - `generatePrescription(recovery: DailyRecovery, schedule: [CalendarEvent]) -> DailyPrescription`
   - `classifyZone(score: Double) -> RecoveryZone`
   - `calculateSleepDebt(recentSleep: [Double], target: Double) -> Double`
   - `detectTrends(recoveries: [DailyRecovery], days: Int) -> [RecoveryInsight]`
2. `Tempo/Services/Engines/MockRecoveryEngine.swift` — Returns a yellow-zone prescription: "Moderate training, extra carbs, 10:30 PM bedtime"

**Acceptance criteria:**
- Protocol and mock compile
- Mock prescription includes all fields: training rec, meal timing, bedtime, hydration, caffeine cutoff, warnings

**Files created/modified:**
- `Tempo/Services/Engines/RecoveryEngineProtocol.swift`
- `Tempo/Services/Engines/MockRecoveryEngine.swift`

---

### 2.10 Scoring Engine + XP Engine (Protocol + Stub)

**Time estimate:** 1.5 hours
**Prerequisites:** 1.2 (DailySnapshot), 1.4 (DailyAccountability), 1.6 (XPEvent)
**Docs:** `ARCHITECTURE.md` (XP System), `docs/MODULE_ARENA.md`
**What to build:**
1. `Tempo/Services/Engines/ScoringEngineProtocol.swift` — Protocol:
   - `calculateDailyScore(snapshot: DailySnapshot, accountability: DailyAccountability) -> Int` (0-100)
   - `scoreBreakdown(snapshot: DailySnapshot) -> ScoreBreakdown` (body, fuel, mind, move components)
2. `Tempo/Services/Engines/XPEngineProtocol.swift` — Protocol:
   - `calculateXP(from snapshot: DailySnapshot, accountability: DailyAccountability) -> [XPEvent]`
   - `currentLevel(totalXP: Int) -> Int` (floor(sqrt(totalXP / 100)))
   - `xpToNextLevel(totalXP: Int) -> Int`
3. `Tempo/Services/Engines/MockScoringEngine.swift` — Returns score 78
4. `Tempo/Services/Engines/MockXPEngine.swift` — Returns 145 XP from 3 events

**Acceptance criteria:**
- All protocols and mocks compile
- Score breakdown sums to daily score
- Level calculation matches formula: `floor(sqrt(totalXP / 100))`
- XP events include source, amount, and reason

**Files created/modified:**
- `Tempo/Services/Engines/ScoringEngineProtocol.swift`
- `Tempo/Services/Engines/XPEngineProtocol.swift`
- `Tempo/Services/Engines/MockScoringEngine.swift`
- `Tempo/Services/Engines/MockXPEngine.swift`

---

### 2.11 Sync Service (Protocol + Stub)

**Time estimate:** 1 hour
**Prerequisites:** 2.1 (APIClient), 1.7 (SyncState, PendingSync)
**Docs:** `docs/DATA_FLOW_ARCHITECTURE.md` Section 6 (Sync Architecture), `docs/ERROR_RECOVERY_FLOWS.md` Section 9 (Offline Queue Architecture), `docs/STATE_MACHINES.md` Section 14 (App Sync Orchestrator)
**What to build:**
1. `Tempo/Services/Sync/SyncCoordinatorProtocol.swift` — Protocol:
   - `syncAll() async throws`
   - `uploadPending() async throws`
   - `downloadUpdates(since: Date) async throws`
   - `resolveConflicts(_: [SyncConflict]) -> [SyncResolution]`
2. `Tempo/Services/Sync/MockSyncCoordinator.swift` — No-op implementation, logs calls
3. `Tempo/Services/Sync/BackgroundSyncService.swift` — Placeholder for BGTaskScheduler registration

**Acceptance criteria:**
- Protocol and mock compile
- MockSyncCoordinator logs all sync operations for debugging
- BackgroundSyncService has placeholder `registerBackgroundTasks()` method

**Files created/modified:**
- `Tempo/Services/Sync/SyncCoordinatorProtocol.swift`
- `Tempo/Services/Sync/MockSyncCoordinator.swift`
- `Tempo/Services/Sync/BackgroundSyncService.swift`

---

### 2.12 App State + Dependency Container

**Time estimate:** 1.5 hours
**Prerequisites:** 2.1 through 2.11 (all service protocols)
**Docs:** `docs/XCODE_PROJECT_STRUCTURE.md` (App/AppState.swift)
**What to build:**
1. `Tempo/App/AppState.swift` — `@Observable` class managing:
   - `isOnboardingComplete: Bool` (persisted in UserDefaults)
   - `authState: AuthState` (from AuthService)
   - `activeTab: Tab` enum (dashboard, training, lockdown, recovery, arena)
   - `isOffline: Bool`
2. `Tempo/App/ServiceContainer.swift` — Central dependency injection:
   - Holds references to all service protocols (HealthKit, Whoop, NutriTrack, Calendar, Notification, Training, Recovery, Scoring, XP, Sync)
   - `static func mock()` factory returns container with all mock implementations
   - `static func live()` factory returns container with real implementations (stubs for now)
3. `Tempo/Utilities/Helpers/NetworkMonitor.swift` — NWPathMonitor wrapper that publishes connectivity state

**Acceptance criteria:**
- `ServiceContainer.mock()` provides all services for SwiftUI previews
- `AppState` observable properties trigger view updates
- `NetworkMonitor` correctly detects online/offline transitions
- All views can access services via environment or direct injection

**Files created/modified:**
- `Tempo/App/AppState.swift`
- `Tempo/App/ServiceContainer.swift`
- `Tempo/Utilities/Helpers/NetworkMonitor.swift`

---

## Phase 3: Design System Implementation

**Prerequisites:** Phase 0 (Xcode project exists)
**Docs to reference:** `docs/DESIGN_SYSTEM.md`

---

### 3.1 Color Tokens (Light + Dark Mode)

**Time estimate:** 1.5 hours
**Prerequisites:** 0.3 (Assets.xcassets/Colors/ folder exists)
**Docs:** `docs/DESIGN_SYSTEM.md` (Colors section)
**What to build:**
1. Create color sets in `Tempo/Resources/Assets.xcassets/Colors/` for every token:
   - Backgrounds: `tempo-bg-primary`, `tempo-bg-card`, `tempo-bg-elevated`
   - Accent: `tempo-accent` (Signal Red #E63946 light / #FF4D5A dark)
   - Semantic: `tempo-green` (#22C55E), `tempo-yellow` (#EAB308), `tempo-red` (#DC2626), `tempo-blue` (#007AFF), `tempo-orange` (#FF9500), `tempo-purple` (#AF52DE)
   - Text: `tempo-text-primary`, `tempo-text-secondary`, `tempo-text-tertiary`
   - Borders: `tempo-border`, `tempo-divider`
2. `Tempo/Utilities/Extensions/Color+Tempo.swift` — Static Color extensions for programmatic access:
   ```swift
   extension Color {
       static let tempoBgPrimary = Color("tempo-bg-primary")
       static let tempoAccent = Color("tempo-accent")
       // ... all tokens
   }
   ```

**Acceptance criteria:**
- Every color renders correctly in both light and dark mode (toggle in simulator)
- All colors accessible via `Color.tempoXxx` static properties
- No hardcoded hex values anywhere except in the asset catalog and the extension file
- Contrast ratios meet WCAG AA (4.5:1 for text) — spot-check primary text on primary background

**Files created/modified:**
- `Tempo/Resources/Assets.xcassets/Colors/` (all color sets)
- `Tempo/Utilities/Extensions/Color+Tempo.swift`

---

### 3.2 Typography Scale

**Time estimate:** 1 hour
**Prerequisites:** 0.3
**Docs:** `docs/DESIGN_SYSTEM.md` (Typography section)
**What to build:**
1. `Tempo/Utilities/Extensions/Font+Tempo.swift` — Font extension with the design system scale:
   - `.tempoLargeTitle` — SF Pro Display Bold 34pt
   - `.tempoTitle1` — SF Pro Display Bold 28pt
   - `.tempoTitle2` — SF Pro Display Semibold 22pt
   - `.tempoTitle3` — SF Pro Display Semibold 20pt
   - `.tempoHeadline` — SF Pro Text Semibold 17pt
   - `.tempoBody` — SF Pro Text Regular 17pt
   - `.tempoCallout` — SF Pro Text Regular 16pt
   - `.tempoSubheadline` — SF Pro Text Regular 15pt
   - `.tempoFootnote` — SF Pro Text Regular 13pt
   - `.tempoCaption1` — SF Pro Text Regular 12pt
   - `.tempoCaption2` — SF Pro Text Regular 11pt
   - Monospaced variants for numbers: `.tempoScoreDisplay` (SF Mono Bold 48pt), `.tempoTimerDisplay` (SF Mono Regular 32pt)

All fonts should use `.font(.system(...))` with Dynamic Type support (`.relativeTo(...)` text styles).

**Acceptance criteria:**
- All font tokens are accessible as static properties
- Fonts scale with Dynamic Type (test with Accessibility Inspector → larger sizes)
- Monospaced variants use SF Mono for aligned numbers
- No hardcoded font sizes anywhere in the project after this step

**Files created/modified:**
- `Tempo/Utilities/Extensions/Font+Tempo.swift`

---

### 3.3 Spacing + Layout Constants

**Time estimate:** 30 minutes
**Prerequisites:** 0.3
**Docs:** `docs/DESIGN_SYSTEM.md` (Spacing section)
**What to build:**
1. `Tempo/Utilities/Constants/DesignTokens.swift`:
   - Spacing scale: `xxs` (2pt), `xs` (4pt), `sm` (8pt), `md` (12pt), `lg` (16pt), `xl` (24pt), `xxl` (32pt), `xxxl` (48pt)
   - Corner radii: `small` (8pt), `medium` (12pt), `large` (16pt), `pill` (999pt)
   - Shadow definitions: `card` (y:2, blur:8, opacity:0.08), `elevated` (y:4, blur:16, opacity:0.12)
   - Animation durations: `fast` (0.15s), `normal` (0.25s), `slow` (0.4s)

**Acceptance criteria:**
- All spacing values accessible via `DesignTokens.Spacing.lg` etc.
- No magic numbers for padding/spacing in view code
- Shadow definitions include both light and dark mode opacities

**Files created/modified:**
- `Tempo/Utilities/Constants/DesignTokens.swift`

---

### 3.4 Shared Components: Buttons

**Time estimate:** 1.5 hours
**Prerequisites:** 3.1, 3.2, 3.3
**Docs:** `docs/DESIGN_SYSTEM.md` (Components → Buttons)
**What to build:**
1. `Tempo/Views/Shared/Styles/TempoButtonStyle.swift`:
   - `.tempoPrimary` — Signal Red background, white text, 16pt corner radius, full width
   - `.tempoSecondary` — Clear background, accent border, accent text
   - `.tempoGhost` — No background/border, accent text only
   - `.tempoDestructive` — Red background, white text (for disconnect/delete actions)
2. `Tempo/Views/Shared/Components/TempoFAB.swift` — Floating action button (56pt circle, shadow, SF Symbol icon)
3. `Tempo/Views/Shared/Components/TempoIconButton.swift` — Icon-only button with hit target (44pt minimum)

Include haptic feedback on tap for primary and FAB buttons.

**Acceptance criteria:**
- All button styles render correctly in light and dark mode
- Primary button has `UIImpactFeedbackGenerator(.medium)` on tap
- FAB has shadow and floats above content
- All buttons meet 44pt minimum touch target
- Buttons support disabled state with reduced opacity

**Files created/modified:**
- `Tempo/Views/Shared/Styles/TempoButtonStyle.swift`
- `Tempo/Views/Shared/Components/TempoFAB.swift`
- `Tempo/Views/Shared/Components/TempoIconButton.swift`

---

### 3.5 Shared Components: Cards

**Time estimate:** 2 hours
**Prerequisites:** 3.1, 3.2, 3.3
**Docs:** `docs/DESIGN_SYSTEM.md` (Components → Cards)
**What to build:**
1. `Tempo/Views/Shared/Modifiers/TempoCardModifier.swift` — ViewModifier applying card background, corner radius (12pt), shadow, padding
2. `Tempo/Views/Shared/Components/QuadrantCardView.swift` — Dashboard quadrant card: icon, title, main metric, subtitle, recovery zone color stripe on top edge
3. `Tempo/Views/Shared/Components/StatCardView.swift` — Small stat card: icon + value + label (for recovery metrics, XP stats)
4. `Tempo/Views/Shared/Components/WorkoutCardView.swift` — Workout preview card: workout type icon, exercise count, estimated duration, recovery badge
5. `Tempo/Views/Shared/Components/AchievementCardView.swift` — Achievement badge card: icon, name, rarity color, earned date
6. `Tempo/Views/Shared/Components/PrescriptionCardView.swift` — Recovery prescription card: icon, recommendation text, priority color

**Acceptance criteria:**
- All cards render in both light and dark mode
- `.tempoCard()` modifier can be applied to any view
- QuadrantCardView shows colored top stripe matching recovery zone (green/yellow/red)
- All cards use design system spacing, typography, and colors (no hardcoded values)

**Files created/modified:**
- `Tempo/Views/Shared/Modifiers/TempoCardModifier.swift`
- `Tempo/Views/Shared/Components/QuadrantCardView.swift`
- `Tempo/Views/Shared/Components/StatCardView.swift`
- `Tempo/Views/Shared/Components/WorkoutCardView.swift`
- `Tempo/Views/Shared/Components/AchievementCardView.swift`
- `Tempo/Views/Shared/Components/PrescriptionCardView.swift`

---

### 3.6 Shared Components: Progress Indicators

**Time estimate:** 2 hours
**Prerequisites:** 3.1, 3.3
**Docs:** `docs/DESIGN_SYSTEM.md` (Components → Progress)
**What to build:**
1. `Tempo/Views/Shared/Components/ScoreRingView.swift` — Animated circular progress ring (central score number, ring fills with animation, supports recovery zone colors). Used on Dashboard and Recovery.
2. `Tempo/Views/Shared/Components/LinearProgressBar.swift` — Horizontal progress bar with percentage, label, and color
3. `Tempo/Views/Shared/Components/CircularRingView.swift` — Thin circular ring (like Apple Watch activity rings) — for macros, steps, study progress
4. `Tempo/Views/Shared/Components/StreakDotsView.swift` — 7-dot row showing last 7 days (filled = complete, empty = missed, flame = streak active)

**Acceptance criteria:**
- ScoreRingView animates from 0 to target value with spring animation
- All progress indicators support 0-100% range
- Colors change based on thresholds (green/yellow/red for recovery)
- StreakDotsView shows fire emoji on active streak days
- All components are reusable with customizable size, color, and value

**Files created/modified:**
- `Tempo/Views/Shared/Components/ScoreRingView.swift`
- `Tempo/Views/Shared/Components/LinearProgressBar.swift`
- `Tempo/Views/Shared/Components/CircularRingView.swift`
- `Tempo/Views/Shared/Components/StreakDotsView.swift`

---

### 3.7 Shared Components: Charts

**Time estimate:** 2 hours
**Prerequisites:** 3.1, 3.3
**Docs:** `docs/DESIGN_SYSTEM.md` (Components → Charts), `docs/DEPENDENCIES.md` Section 2.3 (Charts)
**What to build:**
1. `Tempo/Views/Shared/Components/TempoLineChart.swift` — Wrapper around Swift Charts `LineMark` for 7/30/90 day trend lines. Supports multi-series. Interactive scrub gesture with value callout.
2. `Tempo/Views/Shared/Components/TempoBarChart.swift` — Wrapper around Swift Charts `BarMark` for weekly/monthly bar comparisons.
3. `Tempo/Views/Shared/Components/HeatmapCalendarView.swift` — 365-day heatmap using `Canvas` + `LazyVGrid` (not Swift Charts — too many data points). Color intensity maps to score.

**Acceptance criteria:**
- LineChart renders 90 data points without visible lag
- BarChart supports grouped bars (e.g., study vs training per day)
- HeatmapCalendar renders 365 cells using Canvas (test with `Instruments → Time Profiler` — should be < 16ms frame time)
- All charts use design system colors
- Charts have loading state (shimmer) when data is nil

**Files created/modified:**
- `Tempo/Views/Shared/Components/TempoLineChart.swift`
- `Tempo/Views/Shared/Components/TempoBarChart.swift`
- `Tempo/Views/Shared/Components/HeatmapCalendarView.swift`

---

### 3.8 Shared Components: Alerts and Feedback

**Time estimate:** 1 hour
**Prerequisites:** 3.1, 3.2
**Docs:** `docs/DESIGN_SYSTEM.md` (Components → Alerts), `docs/SOUND_AND_HAPTICS.md`
**What to build:**
1. `Tempo/Views/Shared/Components/TempoToast.swift` — Slide-in-from-top toast: icon, message, auto-dismiss after 3 seconds. Supports success/warning/error styles.
2. `Tempo/Views/Shared/Components/OfflineBannerView.swift` — Yellow sticky banner: "You're offline. Data may be stale."
3. `Tempo/Views/Shared/Components/DrillSergeantBubble.swift` — Speech bubble with drill-sergeant text, red accent, bold tone. Used for motivational/roast messages.
4. `Tempo/Views/Shared/Components/StaleDataIndicator.swift` — Amber dot indicator for stale data (> 15 min old)
5. `Tempo/Utilities/Helpers/HapticManager.swift` — Centralized haptic feedback: `.success`, `.warning`, `.error`, `.light`, `.medium`, `.heavy`, `.selection`

**Acceptance criteria:**
- Toast appears at top of screen with slide animation, auto-dismisses
- OfflineBanner sticks below navigation bar
- DrillSergeantBubble renders with bold typography and red accent
- HapticManager fires correct UIFeedbackGenerator patterns
- All components usable standalone in SwiftUI previews

**Files created/modified:**
- `Tempo/Views/Shared/Components/TempoToast.swift`
- `Tempo/Views/Shared/Components/OfflineBannerView.swift`
- `Tempo/Views/Shared/Components/DrillSergeantBubble.swift`
- `Tempo/Views/Shared/Components/StaleDataIndicator.swift`
- `Tempo/Utilities/Helpers/HapticManager.swift`

---

### 3.9 Shared Components: Inputs

**Time estimate:** 1 hour
**Prerequisites:** 3.1, 3.2, 3.3
**Docs:** `docs/DESIGN_SYSTEM.md` (Components → Inputs)
**What to build:**
1. `Tempo/Views/Shared/Components/TempoTextField.swift` — Styled text field with label, placeholder, validation error display
2. `Tempo/Views/Shared/Components/NumberStepperView.swift` — +/- stepper for weight input (configurable step size: 0.5kg, 1kg, 2.5kg, 5kg)
3. `Tempo/Views/Shared/Styles/TempoToggleStyle.swift` — Custom toggle with signal-red active color

**Acceptance criteria:**
- TextField shows validation error text below in red
- NumberStepper fires haptic on each tap
- Toggle uses accent red color when on
- All inputs meet 44pt minimum touch target

**Files created/modified:**
- `Tempo/Views/Shared/Components/TempoTextField.swift`
- `Tempo/Views/Shared/Components/NumberStepperView.swift`
- `Tempo/Views/Shared/Styles/TempoToggleStyle.swift`

---

### 3.10 Tab Bar + Navigation Structure

**Time estimate:** 1.5 hours
**Prerequisites:** 3.1, 3.2, 2.12 (AppState for activeTab)
**Docs:** `docs/XCODE_PROJECT_STRUCTURE.md` (ContentView.swift), `docs/MODULE_DASHBOARD.md`, `docs/WIREFRAMES.md` Section 1 (Tab Bar & Navigation)
**What to build:**
1. `Tempo/ContentView.swift` — Replace template with `TabView` containing 5 tabs:
   - Dashboard (house.fill) → `DashboardView()` placeholder
   - Training (dumbbell.fill) → `TrainingTabView()` placeholder
   - Lockdown (lock.shield.fill) → `LockdownTabView()` placeholder
   - Recovery (heart.text.square.fill) → `RecoveryTabView()` placeholder
   - Arena (trophy.fill) → `ArenaTabView()` placeholder
2. Create placeholder views for each tab (just Text("Module Name") centered)
3. Wire `AppState.activeTab` to the tab selection
4. Add custom tab bar styling (accent color, hide default labels if needed)
5. Conditionally show onboarding flow if `!appState.isOnboardingComplete`

**Acceptance criteria:**
- App launches showing 5-tab navigation
- Tapping each tab shows the correct placeholder
- Tab bar icons are correct SF Symbols
- Active tab uses Signal Red accent color
- If `isOnboardingComplete` is false, onboarding placeholder shows instead of tabs

**Files created/modified:**
- `Tempo/ContentView.swift` (rewritten)
- `Tempo/Views/Dashboard/DashboardView.swift` (placeholder)
- `Tempo/Views/Training/TrainingTabView.swift` (placeholder)
- `Tempo/Views/Accountability/LockdownTabView.swift` (placeholder)
- `Tempo/Views/Recovery/RecoveryTabView.swift` (placeholder)
- `Tempo/Views/Arena/ArenaTabView.swift` (placeholder)

---

### 3.11 Utility Extensions and Helpers

**Time estimate:** 1 hour
**Prerequisites:** 3.1, 3.2, 3.3
**Docs:** `docs/XCODE_PROJECT_STRUCTURE.md` (Utilities/Extensions), `docs/DEPENDENCIES.md` Section 2.10-2.11
**What to build:**
1. `Tempo/Utilities/Extensions/Date+Tempo.swift` — `isToday`, `startOfDay`, `endOfDay`, `dateString` (YYYY-MM-DD), `adding(days:)`, `timeAgo` (relative string)
2. `Tempo/Utilities/Extensions/View+Tempo.swift` — `.tempoCard()`, `.tempoShadow()`, `.shimmer()` view modifiers
3. `Tempo/Utilities/Extensions/Double+Formatting.swift` — Weight formatting (1 decimal for kg, 0 for lbs), percentage, duration (Xh Ym)
4. `Tempo/Utilities/Extensions/Logger+Tempo.swift` — Categorized `os.Logger` instances: `.networking`, `.healthkit`, `.whoop`, `.training`, `.recovery`, `.sync`, `.subscription`
5. `Tempo/Utilities/Helpers/DateFormatters.swift` — Shared, cached DateFormatter instances (ISO8601, time-only, date-only, relative)
6. `Tempo/Utilities/Helpers/WeightConverter.swift` — kg/lbs conversion with rounding rules per equipment type

**Acceptance criteria:**
- All extensions compile
- `Date().isToday` returns `true`
- `120.5.formattedWeight(unit: .kg)` returns "120.5 kg"
- Logger categories match the list from `docs/DEPENDENCIES.md`
- DateFormatters are static/cached (not created per call)

**Files created/modified:**
- `Tempo/Utilities/Extensions/Date+Tempo.swift`
- `Tempo/Utilities/Extensions/View+Tempo.swift`
- `Tempo/Utilities/Extensions/Double+Formatting.swift`
- `Tempo/Utilities/Extensions/Logger+Tempo.swift`
- `Tempo/Utilities/Helpers/DateFormatters.swift`
- `Tempo/Utilities/Helpers/WeightConverter.swift`

---

### 3.12 Loading, Empty, and Error State Views

**Time estimate:** 1 hour
**Prerequisites:** 3.1, 3.2, 3.4
**Docs:** `docs/DESIGN_SYSTEM.md` (States)
**What to build:**
1. `Tempo/Views/Shared/Components/LoadingStateView.swift` — Skeleton/shimmer placeholder matching card layout
2. `Tempo/Views/Shared/Components/EmptyStateView.swift` — Illustration (SF Symbol), title, subtitle, optional CTA button. Configurable per context ("No workouts yet", "Connect Whoop to see recovery", etc.)
3. `Tempo/Views/Shared/Components/ErrorStateView.swift` — Error icon, message, "Try Again" button with retry closure
4. `Tempo/Views/Shared/Modifiers/ShimmerModifier.swift` — Shimmer animation for loading states

**Acceptance criteria:**
- Loading shimmer animates continuously
- Empty state is configurable (icon, title, subtitle, optional action)
- Error state calls retry closure on button tap
- All three states look consistent with the design system

**Files created/modified:**
- `Tempo/Views/Shared/Components/LoadingStateView.swift`
- `Tempo/Views/Shared/Components/EmptyStateView.swift`
- `Tempo/Views/Shared/Components/ErrorStateView.swift`
- `Tempo/Views/Shared/Modifiers/ShimmerModifier.swift`

---

## Phase 4: Dashboard Module (Views — Using Stubs)

**Prerequisites:** Phase 3 (design system), Phase 2 (service stubs), Phase 1 (models)
**Docs to reference:** `docs/MODULE_DASHBOARD.md`, `docs/DATA_FLOW_ARCHITECTURE.md` Section 2.1

---

### 4.1 Dashboard ViewModel

**Time estimate:** 2 hours
**Prerequisites:** 2.12 (ServiceContainer), 1.2 (DailySnapshot)
**Docs:** `docs/MODULE_DASHBOARD.md`, `docs/DATA_FLOW_ARCHITECTURE.md` Section 2.1
**What to build:**
`Tempo/ViewModels/DashboardViewModel.swift` — `@Observable` class that:
- Holds a `DailySnapshot` for today
- Aggregates data from all service stubs (HealthKit, Whoop, NutriTrack)
- Provides computed properties for each quadrant (body metrics, fuel metrics, mind metrics, move metrics)
- Handles `refresh()` async method (pull-to-refresh)
- Manages loading/loaded/error state enum
- Formats all values for display (e.g., "7.5h" for sleep, "8,432" for steps)

**Acceptance criteria:**
- ViewModel compiles and initializes with mock services
- All four quadrant data sets populated from stubs
- `refresh()` simulates a 1-second delay then updates data
- Loading state transitions: `.loading` → `.loaded(snapshot)` or `.error(message)`
- Works in SwiftUI preview

**Files created/modified:**
- `Tempo/ViewModels/DashboardViewModel.swift`

---

### 4.2 DashboardView (4-Quadrant Layout)

**Time estimate:** 2 hours
**Prerequisites:** 4.1, 3.5 (QuadrantCardView), 3.6 (ScoreRingView), 3.10 (ContentView tab)
**Docs:** `docs/MODULE_DASHBOARD.md` Section 2 (Dashboard Home Screen), `docs/WIREFRAMES.md` Section 2 (Dashboard), `docs/UX_COPY_BIBLE.md` (dashboard strings)
**What to build:**
`Tempo/Views/Dashboard/DashboardView.swift`:
- Central score ring at top (daily score 0-100)
- Non-negotiable progress bar below score ring
- 2x2 grid of quadrant cards: Body (top-left), Fuel (top-right), Mind (bottom-left), Move (bottom-right)
- Pull-to-refresh with custom indicator
- Scroll view for content below the fold
- Uses `DashboardViewModel` for data
- Shows loading shimmer on first load, error state on failure

**Acceptance criteria:**
- Dashboard renders with stub data showing realistic values
- Score ring animates on appear
- Quadrant cards show correct icons and colors per module
- Pull-to-refresh triggers `viewModel.refresh()`
- Layout is correct on iPhone SE, iPhone 15, and iPhone 15 Pro Max (test all three)

**Files created/modified:**
- `Tempo/Views/Dashboard/DashboardView.swift`

---

### 4.3 Body Quadrant View

**Time estimate:** 1.5 hours
**Prerequisites:** 4.2, 3.5 (StatCardView), 3.6 (progress indicators)
**Docs:** `docs/MODULE_DASHBOARD.md` (Body Quadrant section)
**What to build:**
`Tempo/Views/Dashboard/BodyQuadrantDetailView.swift`:
- Recovery score ring (large, colored by zone)
- Stat row: HRV, RHR, Sleep Hours, Strain
- Recovery zone badge (green/yellow/red with label)
- 7-day recovery trend mini chart
- "No Whoop connected" empty state when data is nil
- Navigation to full Recovery module

**Acceptance criteria:**
- Shows realistic stub data: 72% recovery (yellow), 48ms HRV, 62bpm RHR, 7.2h sleep, 12.4 strain
- Recovery ring color matches zone (yellow for 72%)
- Empty state shows when Whoop not connected
- Tapping navigates to recovery detail (placeholder for now)

**Files created/modified:**
- `Tempo/Views/Dashboard/BodyQuadrantDetailView.swift`

---

### 4.4 Fuel Quadrant View

**Time estimate:** 1.5 hours
**Prerequisites:** 4.2, 3.6 (CircularRingView)
**Docs:** `docs/MODULE_DASHBOARD.md` (Fuel Quadrant section)
**What to build:**
`Tempo/Views/Dashboard/FuelQuadrantDetailView.swift`:
- Calorie ring (consumed/target)
- Macro bars: protein, carbs, fat (each with target)
- Meals logged indicator (e.g., "3/4 meals")
- "Connect NutriTrack" empty state when data is nil

**Acceptance criteria:**
- Shows stub data: 2100/2400 kcal, P: 165/180g, C: 240/260g, F: 72/80g
- Calorie ring fills proportionally (87.5%)
- Macro bars colored distinctly (protein blue, carbs orange, fat purple)
- Empty state shows when NutriTrack not connected

**Files created/modified:**
- `Tempo/Views/Dashboard/FuelQuadrantDetailView.swift`

---

### 4.5 Mind Quadrant View

**Time estimate:** 1.5 hours
**Prerequisites:** 4.2, 3.6 (progress indicators)
**Docs:** `docs/MODULE_DASHBOARD.md` (Mind Quadrant section)
**What to build:**
`Tempo/Views/Dashboard/MindQuadrantDetailView.swift`:
- Study progress ring (minutes/target)
- Exam countdown card (days until next exam)
- Today's study sessions list
- Streak indicator (current streak length)
- Focus timer quick-start button

**Acceptance criteria:**
- Shows stub data: 90/120 min studied, exam in 14 days, 5-day streak
- Exam countdown prominently displayed
- Focus timer button navigates to timer (placeholder)

**Files created/modified:**
- `Tempo/Views/Dashboard/MindQuadrantDetailView.swift`

---

### 4.6 Move Quadrant View

**Time estimate:** 1.5 hours
**Prerequisites:** 4.2, 3.6 (progress indicators)
**Docs:** `docs/MODULE_DASHBOARD.md` (Move Quadrant section)
**What to build:**
`Tempo/Views/Dashboard/MoveQuadrantDetailView.swift`:
- Steps progress ring (steps/target)
- Active calories burned
- Today's workout status (completed/planned/rest day)
- Workout type badge (e.g., "Push Day" with dumbbell icon)
- Week-at-a-glance: 7-day dot row (completed workouts)

**Acceptance criteria:**
- Shows stub data: 8,432/10,000 steps, 342 kcal, Push Day completed
- Workout badge shows correct type and completion status
- Steps ring fills proportionally

**Files created/modified:**
- `Tempo/Views/Dashboard/MoveQuadrantDetailView.swift`

---

### 4.7 Dashboard Loading, Empty, and Error States

**Time estimate:** 1 hour
**Prerequisites:** 4.2, 3.12 (state views)
**Docs:** `docs/MODULE_DASHBOARD.md` (Loading states), `docs/ERROR_RECOVERY_FLOWS.md` Sections 1, 3-4 (Network Errors, Data Errors, UX Errors), `docs/WIREFRAMES.md` Section 12 (Error & Offline States)
**What to build:**
Add state handling to `DashboardView`:
- **Loading:** Shimmer placeholders matching the quadrant layout (4 skeleton cards + score ring placeholder)
- **Empty:** First-day state — "Welcome to Tempo! Connect your services to get started" with setup CTAs
- **Error:** Network error with retry button
- **Partial data:** Individual quadrants show empty state independently (e.g., Fuel empty if NutriTrack not connected, but Body shows HealthKit data)

**Acceptance criteria:**
- Toggle ViewModel state to `.loading` → shimmer appears
- Toggle to `.error` → error view with retry
- Disconnect individual mock services → only that quadrant shows empty state
- No crashes when all data is nil

**Files created/modified:**
- `Tempo/Views/Dashboard/DashboardView.swift` (modified)
- `Tempo/Views/Dashboard/DashboardLoadingView.swift`

---

## Phase 5: HealthKit Integration (Real Implementation)

**Prerequisites:** Phase 2 (HealthKitServiceProtocol), Phase 4 (Dashboard to display data)
**Docs to reference:** `docs/INTEGRATION_SPECS.md` Section 2, `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Sections 1.1-1.5

---

### 5.1 HealthKit Authorization Flow

**Time estimate:** 2 hours
**Prerequisites:** 2.3 (protocol), 0.4 (HealthKit entitlement)
**Docs:** `docs/INTEGRATION_SPECS.md` Section 2 (Apple HealthKit), `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 1, `docs/APP_STORE_COMPLIANCE.md` Section 2 (HealthKit Compliance), `docs/ARCHITECTURE_DECISIONS.md` ADR-012 (HealthKit as unified biometric bus — background reading)
**What to build:**
`Tempo/Services/Health/HealthKitService.swift` — Real implementation:
- Create `HKHealthStore` instance
- Define read types: stepCount, activeEnergyBurned, heartRate, heartRateVariabilitySDNN, restingHeartRate, sleepAnalysis, workoutType
- Define write types: dietaryEnergyConsumed, dietaryProtein, dietaryCarbohydrates, dietaryFatTotal, workoutType
- Implement `requestAuthorization()` that requests all types
- Store authorization results in `HealthKitState` model
- Handle partial authorization (user may deny some types)

Also create `Tempo/Utilities/Constants/HealthKitConstants.swift` with all HKObjectType sets and BGTask identifiers.

**Acceptance criteria:**
- Running on a real device (or simulator with Health data) shows the HealthKit authorization sheet
- Authorization status is persisted in HealthKitState model
- Partial denial handled gracefully (no crash if HR denied but steps allowed)
- Logger.healthkit logs authorization results

**Files created/modified:**
- `Tempo/Services/Health/HealthKitService.swift`
- `Tempo/Utilities/Constants/HealthKitConstants.swift`

---

### 5.2 Read Steps + Active Energy

**Time estimate:** 1 hour
**Prerequisites:** 5.1
**Docs:** `docs/INTEGRATION_SPECS.md` Section 2
**What to build:**
Add to `HealthKitService`:
- `fetchSteps(for date: Date)` using `HKStatisticsQuery` with `.cumulativeSum`
- `fetchActiveEnergy(for date: Date)` using `HKStatisticsQuery` with `.cumulativeSum`
- Both queries scoped to `date.startOfDay...date.endOfDay`

**Acceptance criteria:**
- Steps and active energy return realistic values on simulator with pre-loaded Health data
- Returns 0 (not nil) when no data exists for the date
- Queries complete within 500ms (log timing)

**Files created/modified:**
- `Tempo/Services/Health/HealthKitService.swift` (modified)

---

### 5.3 Read Heart Rate + HRV + RHR

**Time estimate:** 1.5 hours
**Prerequisites:** 5.1
**Docs:** `docs/INTEGRATION_SPECS.md` Section 2, `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 1.1, 1.5
**What to build:**
Add to `HealthKitService`:
- `fetchHeartRate(for date: Date)` — Returns array of (timestamp, bpm) samples
- `fetchHRV(for date: Date)` — Returns latest SDNN value (or nil if no Apple Watch / Whoop hasn't written)
- `fetchRestingHeartRate(for date: Date)` — Returns RHR (only available from Apple Watch, nil otherwise per feasibility audit)

Per `TECHNICAL_FEASIBILITY_AUDIT.md` Section 1.1: Always prefer Whoop API data for HRV/RHR when available. HealthKit is fallback only.

**Acceptance criteria:**
- Functions return nil when no data available (not crash)
- HRV returns SDNN in milliseconds
- RHR may return nil on devices without Apple Watch (this is expected per feasibility audit)

**Files created/modified:**
- `Tempo/Services/Health/HealthKitService.swift` (modified)

---

### 5.4 Read Sleep Analysis

**Time estimate:** 1.5 hours
**Prerequisites:** 5.1
**Docs:** `docs/INTEGRATION_SPECS.md` Section 2, `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 1.4
**What to build:**
Add to `HealthKitService`:
- `fetchSleepAnalysis(for date: Date)` — Returns `SleepData` struct with total hours, stages (REM/core/deep if available), efficiency
- Handle both old format (`.inBed`/`.asleep`) and new format (`.asleepREM`, `.asleepCore`, `.asleepDeep`) per feasibility audit
- Deduplicate overlapping sources (if both Whoop and Apple Watch write sleep)

**Acceptance criteria:**
- Returns total sleep hours as primary metric
- Handles iOS 16+ granular sleep stages when available
- Falls back to basic `.asleep` duration when stages unavailable
- No crash when no sleep data exists

**Files created/modified:**
- `Tempo/Services/Health/HealthKitService.swift` (modified)

---

### 5.5 Read Workouts

**Time estimate:** 1 hour
**Prerequisites:** 5.1
**Docs:** `docs/INTEGRATION_SPECS.md` Section 2
**What to build:**
Add to `HealthKitService`:
- `fetchWorkouts(for date: Date)` — Returns array of `WorkoutSample` (type, duration, calories, start/end time, source app name)
- Map `HKWorkoutActivityType` to Tempo's display format

**Acceptance criteria:**
- Returns workouts logged by any app (Apple Workout, Whoop, third-party)
- Each workout includes source bundle identifier for attribution
- Empty array (not nil) when no workouts

**Files created/modified:**
- `Tempo/Services/Health/HealthKitService.swift` (modified)

---

### 5.6 Background Delivery Setup

**Time estimate:** 2 hours
**Prerequisites:** 5.1 through 5.5, 0.4 (Background Modes entitlement)
**Docs:** `docs/INTEGRATION_SPECS.md` Section 2, `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 1.2
**What to build:**
1. `Tempo/Services/Health/HealthKitBackgroundDelivery.swift`:
   - Enable background delivery for steps (`.hourly`), workouts (`.immediate`), sleep (`.hourly`)
   - Handle `HKObserverQuery` callbacks
   - On delivery: refresh the relevant DailySnapshot fields in SwiftData
   - Register `BGAppRefreshTask` for HealthKit data sync
2. Update `TempoApp.swift` to call `enableBackgroundDelivery()` on launch

Per feasibility audit: `.immediate` may take 5-30 minutes. Do not promise real-time to users.

**Acceptance criteria:**
- Background delivery registered for 3 types on app launch
- Observer queries fire when new data is written to HealthKit (test by adding data in Health app)
- DailySnapshot updated in background without user interaction
- No excessive battery drain (verify in Instruments → Energy Log)

**Files created/modified:**
- `Tempo/Services/Health/HealthKitBackgroundDelivery.swift`
- `Tempo/TempoApp.swift` (modified)

---

### 5.7 Write Workout Data to HealthKit

**Time estimate:** 1 hour
**Prerequisites:** 5.1
**Docs:** `docs/INTEGRATION_SPECS.md` Section 2
**What to build:**
Add to `HealthKitService`:
- `writeWorkout(type: HKWorkoutActivityType, start: Date, end: Date, calories: Double, metadata: [String: Any])` — Saves completed RepForge workouts to HealthKit
- Include Tempo as the source bundle identifier

**Acceptance criteria:**
- Written workout appears in Apple Health app under Workouts
- Correct activity type, duration, and calorie burn
- No duplicate writes (check if workout with same start time already exists)

**Files created/modified:**
- `Tempo/Services/Health/HealthKitService.swift` (modified)

---

### 5.8 Connect HealthKit Data to Dashboard

**Time estimate:** 1.5 hours
**Prerequisites:** 5.2 through 5.5, 4.1 (DashboardViewModel)
**Docs:** `docs/DATA_FLOW_ARCHITECTURE.md` Section 2.1
**What to build:**
Update `DashboardViewModel` to:
- Replace mock HealthKit data with real HealthKitService calls
- Populate DailySnapshot.steps, activeCalories from HealthKit on `refresh()`
- Populate DailySnapshot.sleepHours from HealthKit (when Whoop not connected)
- Populate DailySnapshot.workoutCompleted from HealthKit workout query
- Handle the case where HealthKit authorization was denied (show appropriate empty states per quadrant)

**Acceptance criteria:**
- Dashboard Body and Move quadrants show real HealthKit data on a device with Health data
- Steps, active calories, and workout status are real
- Sleep data shows from HealthKit when Whoop is not connected
- When HealthKit denied: quadrants show "Enable HealthKit in Settings" message

**Files created/modified:**
- `Tempo/ViewModels/DashboardViewModel.swift` (modified)

---

## Phase 6: Backend Foundation

**Prerequisites:** Phase 0 (0.8, 0.9 — Vapor project + Docker)
**Docs to reference:** `docs/VAPOR_PROJECT_STRUCTURE.md`, `docs/BACKEND_API.md`, `docs/SECURITY_AND_PRIVACY.md`

---

### 6.1 Vapor Configuration (configure.swift + routes.swift)

**Time estimate:** 2 hours
**Prerequisites:** 0.8, 0.9
**Docs:** `docs/VAPOR_PROJECT_STRUCTURE.md` Section 4 (Key Configuration Files)
**What to build:**
Complete `configure.swift` with:
- JSON encoder/decoder (ISO8601 dates, snake_case keys)
- PostgreSQL connection (from DATABASE_URL or individual env vars)
- Redis connection
- Queues (Redis driver) initialization
- APNs configuration (placeholder — keys not needed yet)
- CORS middleware (allow Tempo iOS bundle)
- Request logging middleware
- Max body size: 1MB JSON, 5MB multipart

Complete `routes.swift` with:
- Health check: `GET /health` returns `{ "status": "ok" }`
- API version group: `app.grouped("v1")` for all endpoints

**Acceptance criteria:**
- `swift run` starts Vapor server on port 8080
- `curl http://localhost:8080/health` returns `{"status":"ok"}`
- PostgreSQL connection succeeds (verify in logs)
- Redis connection succeeds (verify in logs)

**Files created/modified:**
- `tempo-backend/Sources/App/configure.swift` (completed)
- `tempo-backend/Sources/App/routes.swift` (completed)

---

### 6.2 PostgreSQL Models + Migrations (User, RefreshToken)

**Time estimate:** 2 hours
**Prerequisites:** 6.1
**Docs:** `docs/VAPOR_PROJECT_STRUCTURE.md` Sections 5-6 (Models, Migrations), `docs/BACKEND_API.md`
**What to build:**
1. `Sources/App/Models/User.swift` — Fluent model: id (UUID), appleID (unique), username (unique), displayName, avatarURL, timezone, weightKg, heightCm, dateOfBirth, createdAt, updatedAt, deletedAt (soft delete)
2. `Sources/App/Models/RefreshToken.swift` — Fluent model: id, userID (FK), token (hashed), expiresAt, createdAt, isRevoked
3. `Sources/App/Migrations/CreateUsers.swift` — Create users table with indexes on appleID, username
4. `Sources/App/Migrations/CreateRefreshTokens.swift` — Create refresh_tokens table with FK to users
5. Register migrations in `configure.swift`

**Acceptance criteria:**
- `swift run migrate` creates both tables in PostgreSQL
- `swift run migrate --revert` cleanly drops them
- User model has unique constraints on appleID and username
- Soft delete works (deletedAt field, not physical deletion)

**Files created/modified:**
- `tempo-backend/Sources/App/Models/User.swift`
- `tempo-backend/Sources/App/Models/RefreshToken.swift`
- `tempo-backend/Sources/App/Migrations/CreateUsers.swift`
- `tempo-backend/Sources/App/Migrations/CreateRefreshTokens.swift`
- `tempo-backend/Sources/App/configure.swift` (add migrations)

---

### 6.3 JWT Middleware (Issue + Verify + Refresh)

**Time estimate:** 2 hours
**Prerequisites:** 6.2
**Docs:** `docs/VAPOR_PROJECT_STRUCTURE.md` Section 8 (Middleware), `docs/BACKEND_API.md` (Auth)
**What to build:**
1. `Sources/App/Services/JWTService.swift` — Issue access tokens (15 min TTL) and refresh tokens (30 day TTL) using ES256 signing
2. `Sources/App/Middleware/JWTAuthMiddleware.swift` — Middleware that validates `Authorization: Bearer <token>`, extracts user ID, attaches to request
3. `Sources/App/Extensions/Request+Auth.swift` — `request.authenticatedUserID` convenience accessor
4. `Sources/App/DTOs/AuthDTO.swift` — Token response DTO: `{ access_token, refresh_token, expires_in }`

**Acceptance criteria:**
- JWT tokens can be created and verified
- Expired tokens are rejected with 401
- Middleware extracts user ID and makes it available to route handlers
- Token refresh endpoint works: old refresh token → new access + refresh tokens, old refresh revoked

**Files created/modified:**
- `tempo-backend/Sources/App/Services/JWTService.swift`
- `tempo-backend/Sources/App/Middleware/JWTAuthMiddleware.swift`
- `tempo-backend/Sources/App/Extensions/Request+Auth.swift`
- `tempo-backend/Sources/App/DTOs/AuthDTO.swift`

---

### 6.4 Sign in with Apple Endpoint

**Time estimate:** 2 hours
**Prerequisites:** 6.3
**Docs:** `docs/BACKEND_API.md` (Auth endpoints), `docs/INTEGRATION_SPECS.md`
**What to build:**
1. `Sources/App/Controllers/AuthController.swift`:
   - `POST /v1/auth/apple` — Accepts `{ identity_token, authorization_code, full_name }`, verifies with Apple's public keys, creates or fetches user, returns JWT pair
   - `POST /v1/auth/refresh` — Accepts `{ refresh_token }`, issues new token pair
   - `POST /v1/auth/logout` — Revokes all refresh tokens for user
2. `Sources/App/Services/AppleAuthService.swift` — Verifies Apple identity tokens (fetches Apple's JWKS, validates signature, checks claims)
3. Register routes in `routes.swift`

**Acceptance criteria:**
- `POST /v1/auth/apple` with a valid Apple identity token returns JWT access + refresh tokens
- New user is created on first sign-in, existing user returned on subsequent
- `POST /v1/auth/refresh` issues new tokens and revokes old refresh token
- `POST /v1/auth/logout` revokes all tokens (user must re-authenticate)
- Invalid/expired Apple tokens return 401

**Files created/modified:**
- `tempo-backend/Sources/App/Controllers/AuthController.swift`
- `tempo-backend/Sources/App/Services/AppleAuthService.swift`
- `tempo-backend/Sources/App/routes.swift` (add auth routes)

---

### 6.5 iOS Auth Flow (Sign in with Apple → Backend → Keychain)

**Time estimate:** 2 hours
**Prerequisites:** 6.4, 2.2 (AuthService + KeychainService)
**Docs:** `docs/INTEGRATION_SPECS.md`, `docs/XCODE_PROJECT_STRUCTURE.md` (Services/Auth)
**What to build:**
Complete `AuthService.swift`:
- `signInWithApple()` — Uses `ASAuthorizationAppleIDProvider`, presents the Apple Sign-In sheet, sends identity token to backend `POST /v1/auth/apple`, stores returned JWT pair in Keychain
- `refreshToken()` — Calls `POST /v1/auth/refresh`, stores new tokens
- `signOut()` — Calls `POST /v1/auth/logout`, clears Keychain, resets AppState
- Update `APIClient` AuthInterceptor to automatically refresh on 401

Also create `Tempo/Views/Onboarding/SignInWithAppleView.swift` — The actual Sign in with Apple button using `SignInWithAppleButton` from AuthenticationServices.

**Acceptance criteria:**
- Tapping "Sign in with Apple" shows the system sheet
- On success, JWT tokens stored in Keychain
- App transitions to authenticated state
- Subsequent API calls include `Authorization: Bearer` header
- 401 triggers automatic token refresh (transparent to the user)

**Files created/modified:**
- `Tempo/Services/Auth/AuthService.swift` (completed)
- `Tempo/Services/Network/AuthInterceptor.swift` (completed)
- `Tempo/Views/Onboarding/SignInWithAppleView.swift`

---

### 6.6 Rate Limiting Middleware

**Time estimate:** 1 hour
**Prerequisites:** 6.1 (Redis)
**Docs:** `docs/VAPOR_PROJECT_STRUCTURE.md` Section 8, `docs/BACKEND_API.md`
**What to build:**
`Sources/App/Middleware/RateLimitMiddleware.swift`:
- Per-user rate limiting using Redis sliding window
- Default: 60 requests/minute per user
- Auth endpoints: 10 requests/minute per IP
- Returns 429 Too Many Requests with `Retry-After` header

**Acceptance criteria:**
- 61st request within a minute returns 429
- `Retry-After` header is set correctly
- Rate limit counter resets after the window expires
- Different users have independent counters

**Files created/modified:**
- `tempo-backend/Sources/App/Middleware/RateLimitMiddleware.swift`
- `tempo-backend/Sources/App/configure.swift` (register middleware)

---

### 6.7 Envelope DTO + Error Handling

**Time estimate:** 1 hour
**Prerequisites:** 6.1
**Docs:** `docs/VAPOR_PROJECT_STRUCTURE.md` (DTOs), `docs/BACKEND_API.md`
**What to build:**
1. `Sources/App/DTOs/Envelope.swift` — Standard response wrapper: `{ ok: Bool, data: T?, error: ErrorDTO? }`
2. `Sources/App/DTOs/ErrorDTO.swift` — `{ code: Int, message: String, field: String? }`
3. `Sources/App/Extensions/Abort+TempoError.swift` — Custom error codes (1001-9999) mapped to HTTP status codes
4. `Sources/App/Middleware/RequestIdMiddleware.swift` — Adds `X-Request-Id` header to every response
5. `Sources/App/Middleware/SecurityHeadersMiddleware.swift` — Adds security headers (X-Content-Type-Options, X-Frame-Options, etc.)

**Acceptance criteria:**
- All API responses wrapped in `{ ok, data, error }` envelope
- Error responses include numeric error code and human-readable message
- Every response has a unique `X-Request-Id` header
- Security headers present on all responses

**Files created/modified:**
- `tempo-backend/Sources/App/DTOs/Envelope.swift`
- `tempo-backend/Sources/App/DTOs/ErrorDTO.swift`
- `tempo-backend/Sources/App/Extensions/Abort+TempoError.swift`
- `tempo-backend/Sources/App/Middleware/RequestIdMiddleware.swift`
- `tempo-backend/Sources/App/Middleware/SecurityHeadersMiddleware.swift`

---

## Phase 7: Whoop Integration

**Prerequisites:** Phase 6 (backend with auth, PostgreSQL, Redis)
**Docs to reference:** `docs/INTEGRATION_SPECS.md` Section 1, `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 2

---

### 7.1 Whoop OAuth Backend Endpoints

**Time estimate:** 3 hours
**Prerequisites:** 6.4 (auth), 6.3 (JWT)
**Docs:** `docs/INTEGRATION_SPECS.md` Section 1.1 (Authentication Flow), `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 2 (Whoop API Limitations — 10-user dev limit), `docs/COMPETITIVE_ANALYSIS.md` Section 1 (Whoop App — background reading), `docs/ARCHITECTURE_DECISIONS.md` ADR-010 (Whoop via both API and HealthKit — background reading)
**What to build:**
1. `Sources/App/Models/WhoopIntegration.swift` — Fluent model: userID (FK), accessToken (encrypted), refreshToken (encrypted), tokenExpiresAt, whoopUserID, scopes, connectedAt
2. `Sources/App/Migrations/CreateWhoopIntegrations.swift`
3. `Sources/App/Controllers/WhoopIntegrationController.swift`:
   - `GET /v1/integrations/whoop/authorize` — Constructs Whoop OAuth URL with CSRF state (stored in Redis with 10-min TTL)
   - `GET /v1/integrations/whoop/callback` — Receives code from Whoop, exchanges for tokens, encrypts and stores, redirects to `tempo://integrations/whoop/success`
   - `DELETE /v1/integrations/whoop` — Disconnects: revokes Whoop tokens, deletes stored tokens
   - `GET /v1/integrations/whoop/status` — Returns connection status
4. `Sources/App/Services/WhoopOAuthService.swift` — Token exchange, refresh, and revocation logic
5. `Sources/App/Services/EncryptionService.swift` — AES-256-GCM encryption for token storage

**Acceptance criteria:**
- `/authorize` returns a valid Whoop OAuth URL with state parameter
- `/callback` successfully exchanges code for tokens (test with Whoop developer account)
- Tokens are encrypted at rest in PostgreSQL (not plaintext)
- State parameter validated against Redis (CSRF protection)
- Disconnect revokes tokens and deletes the integration record
- `/status` returns `{ connected: true/false, last_sync: Date? }`

**Files created/modified:**
- `tempo-backend/Sources/App/Models/WhoopIntegration.swift`
- `tempo-backend/Sources/App/Migrations/CreateWhoopIntegrations.swift`
- `tempo-backend/Sources/App/Controllers/WhoopIntegrationController.swift`
- `tempo-backend/Sources/App/Services/WhoopOAuthService.swift`
- `tempo-backend/Sources/App/Services/EncryptionService.swift`

---

### 7.2 Whoop Data Proxy Endpoints

**Time estimate:** 2 hours
**Prerequisites:** 7.1
**Docs:** `docs/INTEGRATION_SPECS.md` Section 1, `ARCHITECTURE.md` (Whoop endpoints table)
**What to build:**
1. `Sources/App/Services/WhoopAPIService.swift` — HTTP client for Whoop API v2:
   - Automatic token refresh (actor-based deduplication per user)
   - `fetchRecovery(for userID: UUID, date: String)` → calls `GET /v2/recovery`
   - `fetchSleep(for userID: UUID, date: String)` → calls `GET /v2/activity/sleep`
   - `fetchWorkouts(for userID: UUID, date: String)` → calls `GET /v2/activity/workout`
   - `fetchCycle(for userID: UUID, date: String)` → calls `GET /v2/cycle`
2. `Sources/App/Controllers/WhoopDataController.swift`:
   - `GET /v1/whoop/recovery?date=YYYY-MM-DD`
   - `GET /v1/whoop/sleep?date=YYYY-MM-DD`
   - `GET /v1/whoop/workouts?date=YYYY-MM-DD`
   - `GET /v1/whoop/cycle?date=YYYY-MM-DD`
3. `Sources/App/DTOs/WhoopDTO.swift` — Response DTOs matching Whoop API v2 format
4. Redis caching: cache responses with 5-minute TTL

**Acceptance criteria:**
- All four data endpoints return Whoop data (test with a connected Whoop account)
- Expired tokens are automatically refreshed before making the Whoop API call
- Responses cached in Redis (second identical request within 5 min hits cache)
- Rate of Whoop API calls logged for monitoring

**Files created/modified:**
- `tempo-backend/Sources/App/Services/WhoopAPIService.swift`
- `tempo-backend/Sources/App/Controllers/WhoopDataController.swift`
- `tempo-backend/Sources/App/DTOs/WhoopDTO.swift`

---

### 7.3 Whoop Webhook Receiver

**Time estimate:** 2 hours
**Prerequisites:** 7.2
**Docs:** `docs/INTEGRATION_SPECS.md` Section 1 (Webhooks), `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 2.2
**What to build:**
1. `Sources/App/Controllers/WhoopWebhookController.swift`:
   - `POST /v1/webhooks/whoop` — Receives webhook payloads
   - HMAC-SHA256 verification using `WHOOP_WEBHOOK_SECRET`
   - Idempotency via Redis (store webhook ID for 24 hours, reject duplicates)
   - Handle event types: `workout.updated`, `sleep.updated`, `recovery.updated`
   - On receive: refresh cached data, queue push notification to user's device
2. `Sources/App/Middleware/WhoopWebhookMiddleware.swift` — HMAC verification middleware
3. Whoop data storage models: `WhoopRecovery`, `WhoopSleep`, `WhoopWorkout`, `WhoopCycle` (Fluent models to store historical data)
4. Corresponding migrations

**Acceptance criteria:**
- Webhook endpoint verifies HMAC signature (reject if invalid)
- Duplicate webhooks (same ID) are ignored (idempotency)
- Valid webhooks update the cached data for the user
- Invalid HMAC returns 401
- Webhook processing is async (respond 200 immediately, process in background)

**Files created/modified:**
- `tempo-backend/Sources/App/Controllers/WhoopWebhookController.swift`
- `tempo-backend/Sources/App/Middleware/WhoopWebhookMiddleware.swift`
- `tempo-backend/Sources/App/Models/WhoopRecovery.swift`
- `tempo-backend/Sources/App/Models/WhoopSleep.swift`
- `tempo-backend/Sources/App/Models/WhoopWorkout.swift`
- `tempo-backend/Sources/App/Models/WhoopCycle.swift`
- Corresponding migration files (4)

---

### 7.4 iOS Whoop Service (Real Implementation)

**Time estimate:** 2 hours
**Prerequisites:** 7.2 (backend endpoints), 2.4 (protocol), 2.1 (APIClient), 6.5 (auth flow)
**Docs:** `docs/INTEGRATION_SPECS.md` Section 1 (iOS side)
**What to build:**
Complete `Tempo/Services/Integrations/WhoopService.swift`:
- `connect()` — Calls backend `/v1/integrations/whoop/authorize`, opens `ASWebAuthenticationSession`, sends callback code to backend
- `disconnect()` — Calls `DELETE /v1/integrations/whoop`
- `fetchRecovery/Sleep/Workouts/Cycle` — Call backend proxy endpoints
- `syncAll()` — Fetch all data types and update local SwiftData models (DailyRecovery, DailySnapshot)
- Handle `tempo://` custom URL scheme callbacks
- Connection state management: disconnected → connecting → connected → error

**Acceptance criteria:**
- Full OAuth flow works end-to-end: tap Connect → Whoop login → authorize → tokens stored on backend → data flows
- Recovery, sleep, strain, and workout data populate local models
- Disconnect flow works (tokens revoked, local data cleared)
- Error states handled (network failure, user cancellation, Whoop server error)

**Files created/modified:**
- `Tempo/Services/Integrations/WhoopService.swift` (real implementation)

---

### 7.5 Connect Whoop Data to Dashboard Body Quadrant

**Time estimate:** 1.5 hours
**Prerequisites:** 7.4, 4.3 (Body quadrant view)
**Docs:** `docs/DATA_FLOW_ARCHITECTURE.md` Section 2.1
**What to build:**
Update `DashboardViewModel`:
- When Whoop is connected: populate recoveryScore, HRV, RHR, sleepHours, sleepScore, strain from Whoop data (prefer over HealthKit per feasibility audit)
- When Whoop not connected: fall back to HealthKit data
- Update Body quadrant to show data source indicator ("Whoop" badge vs "HealthKit" badge)

Update `BodyQuadrantDetailView`:
- Show all Whoop metrics when available
- Show "Connect Whoop for full recovery data" CTA when not connected

**Acceptance criteria:**
- With Whoop connected: full recovery data in Body quadrant
- Without Whoop: HealthKit fallback for sleep and HR (recovery score shows "N/A" or estimated)
- Data source badge visible
- Pull-to-refresh re-fetches Whoop data

**Files created/modified:**
- `Tempo/ViewModels/DashboardViewModel.swift` (modified)
- `Tempo/Views/Dashboard/BodyQuadrantDetailView.swift` (modified)

---

### 7.6 Whoop Connection Management UI

**Time estimate:** 1.5 hours
**Prerequisites:** 7.4
**Docs:** `docs/INTEGRATION_SPECS.md` Section 1
**What to build:**
`Tempo/Views/Recovery/WhoopConnectionView.swift`:
- "Connect Whoop" branded button (Whoop logo, black/green color scheme per Whoop brand guidelines)
- Connection status display (connected since, last sync time)
- "Disconnect" button with confirmation alert
- Error state with retry
- Loading state during OAuth flow

**Acceptance criteria:**
- Full connect/disconnect flow works from this view
- Shows connection status and last sync time when connected
- Disconnect shows confirmation dialog before proceeding
- Error messages are user-friendly

**Files created/modified:**
- `Tempo/Views/Recovery/WhoopConnectionView.swift`

---

## Phase 8: Recovery Module

**Prerequisites:** Phase 7 (Whoop data), Phase 5 (HealthKit), Phase 4 (Dashboard)
**Docs to reference:** `docs/MODULE_RECOVERY.md`, `docs/STATE_MACHINES.md` Section 13

---

### 8.1 Recovery Engine (Real Implementation)

**Time estimate:** 3 hours
**Prerequisites:** 2.9 (protocol), 1.5 (Recovery models), 7.4 (Whoop data available)
**Docs:** `docs/MODULE_RECOVERY.md` (Prescription Engine section), `ARCHITECTURE.md` (Prescription Engine), `docs/EXERCISE_SCIENCE.md` Sections 3, 5-7 (Recovery Science, Nutrition for Recovery, Recovery Zone Thresholds, Miami-Specific — background reading), `docs/COMPETITIVE_ANALYSIS.md` Sections 9-10 (Oura, Gentler Streak — background reading)
**What to build:**
Complete `Tempo/Services/Engines/RecoveryEngine.swift`:
- `generatePrescription()` — Algorithm taking recovery score, sleep data, strain, HRV trend, next day's schedule → outputs DailyPrescription with:
  - Training recommendation (Full send / Moderate / Easy/mobility / Rest)
  - Meal timing (protein within 1h of training, extra carbs on high strain)
  - Bedtime (calculated from sleep debt + tomorrow's schedule)
  - Hydration target (adjusted for strain)
  - Caffeine cutoff (8 hours before target bedtime)
  - Warnings array (HRV dropping, sleep debt > 4h, etc.)
- `detectTrends()` — Analyzes 7/30/90 day recovery data for patterns
- `calculateSleepDebt()` — Rolling 7-day sleep debt calculation

**Acceptance criteria:**
- Green zone (>= 67%) → "Full send" training rec
- Yellow zone (34-66%) → "Moderate" with 20% volume reduction
- Red zone (< 34%) → "Easy/mobility" or "Rest"
- Bedtime adjusts by 30 min for each hour of sleep debt
- Caffeine cutoff is always 8+ hours before target bedtime
- Warnings fire for: HRV dropping 3+ consecutive days, sleep debt > 4h, strain > 18 with yellow/red recovery

**Files created/modified:**
- `Tempo/Services/Engines/RecoveryEngine.swift` (real implementation)

---

### 8.2 Recovery ViewModel

**Time estimate:** 1.5 hours
**Prerequisites:** 8.1, 1.5
**Docs:** `docs/MODULE_RECOVERY.md`
**What to build:**
`Tempo/ViewModels/RecoveryViewModel.swift` — `@Observable` class:
- Fetches today's DailyRecovery and DailyPrescription from SwiftData
- Formats all metrics for display
- Manages tab state: Today / Sleep / Strain / Trends
- Provides 7/30/90 day recovery data arrays for charts
- Handles refresh from Whoop

**Acceptance criteria:**
- ViewModel populates from SwiftData on init
- All metrics formatted correctly (HRV: "48 ms", RHR: "62 bpm", etc.)
- Chart data arrays have correct length for selected time range

**Files created/modified:**
- `Tempo/ViewModels/RecoveryViewModel.swift`

---

### 8.3 RecoveryTodayView

**Time estimate:** 2 hours
**Prerequisites:** 8.2, 3.5 (PrescriptionCardView), 3.6 (ScoreRingView)
**Docs:** `docs/MODULE_RECOVERY.md` (RecoveryTodayView section), `docs/WIREFRAMES.md` Section 5 (Recovery), `docs/UX_COPY_BIBLE.md` (recovery strings)
**What to build:**
`Tempo/Views/Recovery/RecoveryTodayView.swift`:
- Large recovery score ring (top, with zone color)
- Recovery zone badge with label
- Key metrics row: HRV, RHR, Sleep, Strain
- Prescription cards section: training rec, bedtime, hydration, caffeine cutoff
- Warnings section (if any)
- "Powered by Whoop" attribution
- Pull-to-refresh

**Acceptance criteria:**
- Score ring color matches recovery zone
- All 4 key metrics displayed
- Prescription cards show actionable recommendations
- Warnings highlighted in red when present
- Empty state when no Whoop data

**Files created/modified:**
- `Tempo/Views/Recovery/RecoveryTodayView.swift`

---

### 8.4 SleepDetailView + StrainDetailView

**Time estimate:** 2 hours
**Prerequisites:** 8.2, 3.7 (charts)
**Docs:** `docs/MODULE_RECOVERY.md` (Sleep Detail, Strain Detail sections)
**What to build:**
1. `Tempo/Views/Recovery/SleepDetailView.swift`:
   - Sleep score, total hours, time in bed
   - Sleep stages bar (REM/deep/light/awake proportions)
   - Sleep debt indicator
   - Sleep efficiency percentage
   - 7-day sleep trend chart
2. `Tempo/Views/Recovery/StrainDetailView.swift`:
   - Day strain gauge (0-21 scale)
   - HR zone distribution (5 zones, horizontal bars)
   - Active calories
   - 7-day strain trend chart

**Acceptance criteria:**
- Sleep stages render as stacked horizontal bar with distinct colors
- Strain gauge shows colored gradient (green → yellow → red as strain increases)
- Trend charts show 7 days of data
- All values from Whoop data (or empty state if unavailable)

**Files created/modified:**
- `Tempo/Views/Recovery/SleepDetailView.swift`
- `Tempo/Views/Recovery/StrainDetailView.swift`

---

### 8.5 RecoveryTrendsView

**Time estimate:** 1.5 hours
**Prerequisites:** 8.2, 3.7 (TempoLineChart)
**Docs:** `docs/MODULE_RECOVERY.md` (Trends section)
**What to build:**
`Tempo/Views/Recovery/RecoveryTrendsView.swift`:
- Time range picker: 7 / 30 / 90 days
- Multi-line chart: recovery score, HRV, RHR overlaid (with toggles)
- Pattern insights cards below chart (from RecoveryEngine.detectTrends)
- Average values for selected range

**Acceptance criteria:**
- Chart renders smoothly with 90 data points
- Individual metrics can be toggled on/off
- Time range picker updates chart data
- Pattern insights show when enough data exists

**Files created/modified:**
- `Tempo/Views/Recovery/RecoveryTrendsView.swift`

---

### 8.6 Recovery Tab Container

**Time estimate:** 1 hour
**Prerequisites:** 8.3, 8.4, 8.5
**Docs:** `docs/MODULE_RECOVERY.md`
**What to build:**
Update `Tempo/Views/Recovery/RecoveryTabView.swift` (replace placeholder):
- Tab or segmented control: Today / Sleep / Strain / Trends
- Navigation to WhoopConnectionView from settings gear icon
- Recovery notification: morning recovery report (schedule via NotificationService)

**Acceptance criteria:**
- All sub-views accessible via tab/segment control
- Settings gear navigates to Whoop connection management
- Tab view updates Dashboard Body quadrant data on appear

**Files created/modified:**
- `Tempo/Views/Recovery/RecoveryTabView.swift` (completed)

---

## Phase 9: Training Module

**Prerequisites:** Phase 8 (recovery data for workout adjustments), Phase 5 (HealthKit), Phase 1 (1.3, 1.10 exercise data)
**Docs to reference:** `docs/MODULE_TRAINING.md`, `docs/STATE_MACHINES.md` Sections 1, 12, 16

---

### 9.1 Training Engine (Real Implementation)

**Time estimate:** 4 hours
**Prerequisites:** 2.8 (protocol), 1.3 (Training models), 1.10 (Exercise library), 8.1 (RecoveryEngine)
**Docs:** `docs/MODULE_TRAINING.md` (Workout Generation Algorithm, Progressive Overload, Football Rules), `docs/EXERCISE_SCIENCE.md` Sections 1-2, 4, 8 (Training Periodization, Progressive Overload Evidence, Football-Specific, Age-Specific — background reading), `docs/COMPETITIVE_ANALYSIS.md` Sections 2-4 (Strong, Hevy, Strava — background reading)
**What to build:**
Complete `Tempo/Services/Engines/TrainingEngine.swift`:
- `generateWorkout()` — Full workout generation:
  - Select workout type based on split, day of week, and recovery
  - Select exercises (compounds first, then accessories)
  - Set target reps/weight based on history + progressive overload
  - Apply recovery adjustment (green: full volume, yellow: -20%, red: -30-40% or swap to mobility)
- `generateWeekPlan()` — Full week planning with football awareness
- Football proximity rules: no heavy legs day before football, rest/light upper on football day
- Progressive overload: increase weight by smallest increment when all sets completed at target reps for 2 consecutive sessions
- Deload week detection: every 4th week, reduce volume 40%
- PR detection: compare set to historical bests

**Acceptance criteria:**
- PPL split generates correct rotation (Push → Pull → Legs → Push → ...)
- Football on Tuesday → Monday is not leg day, Tuesday is rest/light upper
- Yellow recovery (50%) → workout has ~20% fewer sets
- Red recovery (30%) → workout is mobility or rest
- Progressive overload: if last 2 sessions hit 3x10 at 80kg, new target is 3x10 at 82.5kg
- Deload week 4: volume reduced ~40%

**Files created/modified:**
- `Tempo/Services/Engines/TrainingEngine.swift` (real implementation)

---

### 9.2 Training ViewModel

**Time estimate:** 2 hours
**Prerequisites:** 9.1
**Docs:** `docs/MODULE_TRAINING.md`, `docs/STATE_MACHINES.md` Section 1 (Workout Session)
**What to build:**
`Tempo/ViewModels/TrainingViewModel.swift` — `@Observable` class managing:
- Today's WorkoutPlan (from SwiftData or generated)
- Active workout state machine (idle → warmup → exercise → cooldown → summary → saved)
- Current exercise index, current set index
- Rest timer (countdown)
- Workout elapsed time
- Volume tracking (total weight moved)
- PR detection during workout

**Acceptance criteria:**
- State machine transitions match `docs/STATE_MACHINES.md` Section 1 exactly
- Rest timer counts down and fires haptic on completion
- Volume calculated correctly (sum of weight x reps for all completed sets)
- Crash recovery: if app was killed during workout, state restored from SwiftData on relaunch

**Files created/modified:**
- `Tempo/ViewModels/TrainingViewModel.swift`

---

### 9.3 TodayWorkoutView

**Time estimate:** 2 hours
**Prerequisites:** 9.2, 3.5 (WorkoutCardView)
**Docs:** `docs/MODULE_TRAINING.md` (TodayWorkoutView section), `docs/WIREFRAMES.md` Section 3 (Training), `docs/UX_COPY_BIBLE.md` (training strings)
**What to build:**
`Tempo/Views/Training/TodayWorkoutView.swift`:
- Workout type header (e.g., "Push Day" with recovery badge)
- Recovery adjustment indicator (e.g., "Volume reduced 20% — Yellow recovery")
- Exercise list: each exercise shows name, sets x reps, target weight
- "Start Workout" button (transitions to ActiveWorkoutView)
- Rest day view when workout type is .rest
- Swap exercise action (long press → swap with alternative)

**Acceptance criteria:**
- Exercises listed with correct set/rep/weight targets
- Recovery badge shows current zone color
- Start button transitions to active workout state
- Rest day shows appropriate messaging

**Files created/modified:**
- `Tempo/Views/Training/TodayWorkoutView.swift`

---

### 9.4 ActiveWorkoutView (Set Logging)

**Time estimate:** 3 hours
**Prerequisites:** 9.2, 3.9 (NumberStepperView)
**Docs:** `docs/MODULE_TRAINING.md` (ActiveWorkoutView, Weight Input), `docs/STATE_MACHINES.md` Section 1, 16
**What to build:**
`Tempo/Views/Training/ActiveWorkoutView.swift`:
- Current exercise name + set counter (e.g., "Set 2 of 4")
- Weight input (NumberStepper, sticky from previous set)
- Reps input (NumberStepper)
- RPE selector (1-10 scale, optional)
- "Done" button → logs set, starts rest timer
- Rest timer overlay (large countdown, "Skip Rest" button)
- Exercise progress (completed sets checkmarks)
- "Finish Workout" button (available after all exercises or manual finish)
- Pause/resume functionality
- Elapsed workout time in navigation bar

Also create `Tempo/Views/Training/RestTimerView.swift` — Countdown rest timer between sets

**Acceptance criteria:**
- Weight pre-fills from previous set (sticky weight)
- Logging a set: weight and reps saved to PlannedSet, rest timer starts
- Rest timer counts down from configured duration (90-180s depending on exercise type)
- Haptic on timer completion
- All sets logged persisted to SwiftData in real-time (crash recovery)
- Pause freezes all timers, resume continues

**Files created/modified:**
- `Tempo/Views/Training/ActiveWorkoutView.swift`
- `Tempo/Views/Training/RestTimerView.swift`
- `Tempo/Views/Training/WeightInputView.swift`

---

### 9.5 WorkoutSummaryView

**Time estimate:** 1.5 hours
**Prerequisites:** 9.4
**Docs:** `docs/MODULE_TRAINING.md` (Post-Workout Summary)
**What to build:**
`Tempo/Views/Training/WorkoutSummaryView.swift`:
- Total duration, total volume (kg), total sets, total reps
- PR badges (if any PRs hit during the workout, show gold badge + celebration)
- Per-exercise summary (exercise name, best set, volume)
- "Save & Close" button → persist to SwiftData, write to HealthKit, sync to backend
- Confetti animation if PRs were achieved

**Acceptance criteria:**
- All workout stats calculated correctly
- PRs detected and highlighted with gold badge
- Save writes workout to HealthKit (via 5.7)
- Workout data persisted in SwiftData with status `.completed`

**Files created/modified:**
- `Tempo/Views/Training/WorkoutSummaryView.swift`

---

### 9.6 WeekPlanView

**Time estimate:** 1.5 hours
**Prerequisites:** 9.1 (generateWeekPlan)
**Docs:** `docs/MODULE_TRAINING.md` (WeekPlanView)
**What to build:**
`Tempo/Views/Training/WeekPlanView.swift`:
- 7-day horizontal grid (Mon-Sun)
- Each day shows: workout type, status (planned/completed/skipped/rest)
- Color coding: completed (green), today (accent), planned (gray), rest (subtle)
- Football days marked with football icon
- Tap to view day's workout detail

**Acceptance criteria:**
- All 7 days visible with correct workout types
- Football days visually distinct
- Completed days show green checkmark
- Current day highlighted

**Files created/modified:**
- `Tempo/Views/Training/WeekPlanView.swift`

---

### 9.7 Exercise Library + Detail Views

**Time estimate:** 2 hours
**Prerequisites:** 1.10 (Exercise library data)
**Docs:** `docs/MODULE_TRAINING.md` (Exercise Library)
**What to build:**
1. `Tempo/Views/Training/ExerciseLibraryView.swift`:
   - Search bar
   - Filter by muscle group, equipment
   - List of exercises with muscle group badge and equipment icon
2. `Tempo/Views/Training/ExerciseDetailView.swift`:
   - Exercise name, muscle group, equipment, instructions
   - Personal record display (1RM, rep maxes)
   - Progress chart (weight over time via ExerciseHistory)
   - Recent sessions list

**Acceptance criteria:**
- Search filters exercises by name in real-time
- Muscle group filter works (tap "Chest" → only chest exercises shown)
- Exercise detail shows historical data from ExerciseHistory
- Progress chart renders weight progression over time

**Files created/modified:**
- `Tempo/Views/Training/ExerciseLibraryView.swift`
- `Tempo/Views/Training/ExerciseDetailView.swift`

---

### 9.8 Training Tab Container + Dashboard Connection

**Time estimate:** 1.5 hours
**Prerequisites:** 9.3 through 9.7
**Docs:** `docs/MODULE_TRAINING.md`
**What to build:**
1. Update `Tempo/Views/Training/TrainingTabView.swift`:
   - Default view: TodayWorkoutView
   - Navigation to: WeekPlanView, ExerciseLibraryView, ProgressChartsView
   - Settings gear → training preferences (split selection, equipment, deload settings)
2. Connect training data to Dashboard Move quadrant:
   - Update DashboardViewModel to read today's workout status
   - Show workout type and completion in Move quadrant

**Acceptance criteria:**
- Training tab shows today's workout by default
- Navigation to all sub-views works
- Dashboard Move quadrant reflects today's workout status (planned/completed/rest)

**Files created/modified:**
- `Tempo/Views/Training/TrainingTabView.swift` (completed)
- `Tempo/Views/Training/ProgressChartsView.swift`
- `Tempo/Views/Training/TrainingSettingsView.swift`
- `Tempo/ViewModels/DashboardViewModel.swift` (modified)

---

## Phase 10: Accountability Module

**Prerequisites:** Phase 5 (HealthKit for auto-tracking), Phase 4 (Dashboard)
**Docs to reference:** `docs/MODULE_ACCOUNTABILITY.md`, `docs/STATE_MACHINES.md` Sections 2, 3, 6, 7

---

### 10.1 Accountability Engine

**Time estimate:** 2 hours
**Prerequisites:** 1.4 (Accountability models), 2.10 (ScoringEngine protocol)
**Docs:** `docs/MODULE_ACCOUNTABILITY.md`, `docs/STATE_MACHINES.md` Section 3, `docs/COMPETITIVE_ANALYSIS.md` Sections 5, 7 (Forest, Streaks — background reading)
**What to build:**
`Tempo/Services/Engines/AccountabilityEngine.swift`:
- Track non-negotiable progress throughout the day
- Determine leisure unlock status (all non-negotiables complete)
- Calculate daily accountability score (0-100)
- Implement state machine from STATE_MACHINES.md Section 3
- Rest day / sick day handling (reduced requirements)
- Weekend mode (adjusted targets)

**Acceptance criteria:**
- Leisure unlocks only when ALL active non-negotiables are marked complete
- Score weights each non-negotiable equally
- Rest day: training non-negotiable automatically satisfied
- State transitions match the formal state machine spec

**Files created/modified:**
- `Tempo/Services/Engines/AccountabilityEngine.swift`

---

### 10.2 Accountability ViewModel

**Time estimate:** 1.5 hours
**Prerequisites:** 10.1
**Docs:** `docs/MODULE_ACCOUNTABILITY.md`
**What to build:**
`Tempo/ViewModels/AccountabilityViewModel.swift`:
- Today's DailyAccountability and NonNegotiableProgress array
- Leisure unlock status
- Focus timer state (from STATE_MACHINES.md Section 2)
- Streak data
- Manual check-off methods

**Acceptance criteria:**
- ViewModel reflects current day's accountability state
- Manual completion updates progress in real-time
- Leisure unlock triggers haptic + sound

**Files created/modified:**
- `Tempo/ViewModels/AccountabilityViewModel.swift`

---

### 10.3 LockdownView (Non-Negotiable Cards)

**Time estimate:** 2 hours
**Prerequisites:** 10.2, 3.5 (cards), 3.6 (progress indicators)
**Docs:** `docs/MODULE_ACCOUNTABILITY.md` (LockdownView section), `docs/WIREFRAMES.md` Section 4 (Accountability), `docs/UX_COPY_BIBLE.md` (accountability strings)
**What to build:**
`Tempo/Views/Accountability/LockdownMainView.swift`:
- "LOCKDOWN" header with lock icon (locked/unlocked state)
- Non-negotiable cards: icon, name, progress bar, value/target, auto-tracked badge, manual check button
- Overall progress bar (N/M complete)
- Leisure unlock celebration (animation + "PS5 UNLOCKED" message when all done)
- Drill sergeant bubble with contextual message

**Acceptance criteria:**
- Lock icon animates from locked to unlocked when all non-negotiables complete
- Progress bars fill in real-time
- Auto-tracked items show source badge (Whoop/NutriTrack/HealthKit)
- Manual items have tap-to-complete button
- Drill sergeant message changes based on progress and time of day

**Files created/modified:**
- `Tempo/Views/Accountability/LockdownMainView.swift`

---

### 10.4 Focus Timer (Pomodoro)

**Time estimate:** 3 hours
**Prerequisites:** 10.2, 3.6 (CircularRingView)
**Docs:** `docs/MODULE_ACCOUNTABILITY.md` (Focus Timer), `docs/STATE_MACHINES.md` Section 2
**What to build:**
1. `Tempo/Views/Accountability/FocusTimerView.swift`:
   - Large countdown ring (25 min work / 5 min break, configurable)
   - Session counter (e.g., "Session 2 of 4")
   - Start / Pause / Resume / Stop buttons
   - Subject label (optional: "Studying: Linear Algebra")
   - Interruption counter
   - Sound effects: tick during last 10 seconds, completion chime
2. Live Activity for focus timer:
   - Dynamic Island shows remaining time
   - Lock screen shows timer + session count
   - Update on state changes (pause/resume), not every second
   - Use `Text(timerInterval:)` for system-rendered countdown

Per feasibility audit (Section 3.4): Live Activities max 4 hours. Focus timer sessions are 25 min, well within limit.

**Acceptance criteria:**
- Timer counts down from configured duration
- Auto-transitions between work and break sessions
- Pausing freezes the timer, resuming continues
- Live Activity shows on Dynamic Island (iPhone 14 Pro+) and lock screen
- StudySession created in SwiftData on completion with duration and interruption count
- Study minutes accumulate toward non-negotiable progress

**Files created/modified:**
- `Tempo/Views/Accountability/FocusTimerView.swift`
- (Live Activity target files — see Phase 17 for widget target setup; for now, implement without Live Activity)

---

### 10.5 NonNegotiable Setup/Edit Flow

**Time estimate:** 1.5 hours
**Prerequisites:** 10.3, 1.4
**Docs:** `docs/MODULE_ACCOUNTABILITY.md` (Setup)
**What to build:**
`Tempo/Views/Accountability/NonNegotiableSetupView.swift`:
- List of current non-negotiables with edit/delete
- Add new: name, type, target value, tracking method (auto/manual/timer)
- Reorder (drag and drop)
- Default templates: "Study 2h", "Train", "Eat 3 meals", "Sleep 7h"
- Maximum 7 non-negotiables (prevent overload)

**Acceptance criteria:**
- Create, edit, delete, reorder non-negotiables
- Auto-tracked items show which integration will track them
- Maximum 7 enforced with user-friendly message
- Changes persist to SwiftData immediately

**Files created/modified:**
- `Tempo/Views/Accountability/NonNegotiableSetupView.swift`

---

### 10.6 Streak Calendar + Streak Engine

**Time estimate:** 2 hours
**Prerequisites:** 10.1, 3.7 (HeatmapCalendarView)
**Docs:** `docs/MODULE_ACCOUNTABILITY.md` (Streaks), `docs/STATE_MACHINES.md` Section 7
**What to build:**
1. `Tempo/Views/Accountability/StreakCalendarView.swift`:
   - 365-day heatmap calendar (from HeatmapCalendarView)
   - Color intensity = daily score (higher = darker green)
   - Current streak count prominently displayed
   - Longest streak record
   - Streak freeze indicator (remaining freezes)
2. Implement streak logic in AccountabilityEngine:
   - Streak continues if all non-negotiables complete
   - Streak freeze: allows 1 missed day without breaking streak (max 2 freezes per month)
   - Streak broken: reset to 0 with "streak lost" notification

**Acceptance criteria:**
- Heatmap renders 365 days without lag (Canvas-based, not 365 SwiftUI views)
- Current streak and longest streak accurate
- Streak freeze deducts from monthly allowance
- Missing a day without freeze breaks the streak

**Files created/modified:**
- `Tempo/Views/Accountability/StreakCalendarView.swift`

---

### 10.7 Scoring Engine (Real Implementation)

**Time estimate:** 2 hours
**Prerequisites:** 10.1, 2.10 (protocol)
**Docs:** `docs/MODULE_ARENA.md` (XP System), `ARCHITECTURE.md` (Daily Score)
**What to build:**
Complete `Tempo/Services/Engines/ScoringEngine.swift`:
- `calculateDailyScore()` — Weighted composite:
  - Non-negotiable completion (40% weight)
  - Training compliance (20%)
  - Nutrition compliance (20%)
  - Recovery compliance (10%)
  - Steps/activity (10%)
- `scoreBreakdown()` — Returns individual component scores

Complete `Tempo/Services/Engines/XPEngine.swift`:
- XP from workouts (+50), meals (+5 each, +40 all logged), study target (+40), all non-negotiables bonus (+20), sleep score >= 85% (+10), steps >= 8000 (+10)
- Penalties: skip workout (-20), miss study (-15), miss meal (-10)
- Streak bonuses: 7-day (+25/day), 30-day (+50/day)
- Level calculation: `floor(sqrt(totalXP / 100))`

**Acceptance criteria:**
- Daily score is 0-100 and reflects actual completion
- XP events generated correctly for each accomplishment
- Penalties applied for missed items
- Level calculation matches formula
- Score updates in real-time as tasks are completed

**Files created/modified:**
- `Tempo/Services/Engines/ScoringEngine.swift` (real implementation)
- `Tempo/Services/Engines/XPEngine.swift` (real implementation)

---

### 10.8 Accountability Tab Container + Dashboard Connection

**Time estimate:** 1 hour
**Prerequisites:** 10.3 through 10.6
**Docs:** `docs/MODULE_ACCOUNTABILITY.md`
**What to build:**
1. Update `Tempo/Views/Accountability/LockdownTabView.swift`:
   - Default: LockdownMainView
   - Navigation to: FocusTimerView, StreakCalendarView, NonNegotiableSetupView
2. Connect to Dashboard Mind quadrant:
   - Study minutes, streak, exam countdown in Mind quadrant
3. Connect to Dashboard non-negotiable progress bar

**Acceptance criteria:**
- Lockdown tab shows today's non-negotiables
- Dashboard Mind quadrant shows real study data
- Dashboard non-negotiable bar reflects actual completion

**Files created/modified:**
- `Tempo/Views/Accountability/LockdownTabView.swift` (completed)
- `Tempo/ViewModels/DashboardViewModel.swift` (modified)

---

## Phase 11: NutriTrack Integration

**Prerequisites:** Phase 6 (backend)
**Docs to reference:** `docs/INTEGRATION_SPECS.md` Section 3

---

### 11.1 NutriTrack Backend Proxy

**Time estimate:** 2 hours
**Prerequisites:** 6.1 (Vapor configured)
**Docs:** `docs/INTEGRATION_SPECS.md` Section 3, `ARCHITECTURE.md` (NutriTrack endpoints), `docs/COMPETITIVE_ANALYSIS.md` Section 8 (MyFitnessPal — background reading), `docs/ARCHITECTURE_DECISIONS.md` ADR-011 (NutriTrack proxy through backend — background reading)
**What to build:**
1. `Sources/App/Models/NutriTrackIntegration.swift` — Stores user's NutriTrack base URL + encrypted PIN
2. `Sources/App/Migrations/CreateNutriTrackIntegrations.swift`
3. `Sources/App/Services/NutriTrackProxyService.swift` — HTTP client that authenticates with PIN, fetches data from NutriTrack Flask API
4. `Sources/App/Controllers/NutriTrackController.swift`:
   - `POST /v1/integrations/nutritrack/connect` — Store NutriTrack URL + PIN
   - `DELETE /v1/integrations/nutritrack` — Disconnect
   - `GET /v1/nutritrack/today` — Proxy to NutriTrack `/api/today`
   - `GET /v1/nutritrack/macro-balance` — Proxy to NutriTrack `/api/today/macro-balance`
   - `GET /v1/nutritrack/weekly-report` — Proxy to NutriTrack `/api/weekly-report`
5. Redis caching: cache NutriTrack responses with 5-minute TTL

**Acceptance criteria:**
- Connect endpoint stores NutriTrack credentials (encrypted)
- Proxy endpoints return NutriTrack data
- PIN never exposed in API responses
- Caching reduces NutriTrack Flask server load

**Files created/modified:**
- `tempo-backend/Sources/App/Models/NutriTrackIntegration.swift`
- `tempo-backend/Sources/App/Migrations/CreateNutriTrackIntegrations.swift`
- `tempo-backend/Sources/App/Services/NutriTrackProxyService.swift`
- `tempo-backend/Sources/App/Controllers/NutriTrackController.swift`

---

### 11.2 iOS NutriTrack Service (Real Implementation)

**Time estimate:** 1.5 hours
**Prerequisites:** 11.1, 2.5 (protocol)
**Docs:** `docs/INTEGRATION_SPECS.md` Section 3
**What to build:**
Complete `Tempo/Services/Integrations/NutriTrackService.swift`:
- `connect()` — Send base URL + PIN to backend
- `disconnect()` — Delete connection on backend
- `fetchTodayMeals()` — Call backend proxy, parse into NutriTrackDayData
- `fetchMacroBalance()` — Call backend proxy
- `syncToSwiftData()` — Update DailySnapshot fuel fields

**Acceptance criteria:**
- Connect/disconnect flow works end-to-end
- Today's meals, macros, and calorie data populate DailySnapshot
- Data refreshes on pull-to-refresh

**Files created/modified:**
- `Tempo/Services/Integrations/NutriTrackService.swift` (real implementation)

---

### 11.3 NutriTrack Connection UI + Dashboard Fuel Quadrant

**Time estimate:** 1.5 hours
**Prerequisites:** 11.2, 4.4 (Fuel quadrant)
**Docs:** `docs/INTEGRATION_SPECS.md` Section 3
**What to build:**
1. `Tempo/Views/Onboarding/NutriTrackConnectView.swift` — Connection form (NutriTrack URL + PIN input), test connection button, success/error states
2. Update Dashboard Fuel quadrant to use real NutriTrack data (calories, macros, meals logged)
3. Connect meal data to accountability auto-tracking (meals non-negotiable)

**Acceptance criteria:**
- NutriTrack connection flow works (enter URL, PIN, test, connect)
- Fuel quadrant shows real calories, macros, meals from NutriTrack
- Meal completion auto-tracked in accountability module

**Files created/modified:**
- `Tempo/Views/Onboarding/NutriTrackConnectView.swift`
- `Tempo/ViewModels/DashboardViewModel.swift` (modified)

---

## Phase 12: Notification System

**Prerequisites:** Phase 10 (accountability data), Phase 8 (recovery data), Phase 6 (backend for push)
**Docs to reference:** `docs/ONBOARDING_AND_NOTIFICATIONS.md`, `docs/STATE_MACHINES.md` Section 11, `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 3

---

### 12.1 APNs Setup (Backend + iOS)

**Time estimate:** 2 hours
**Prerequisites:** 6.1, 0.4 (Push entitlement)
**Docs:** `docs/VAPOR_PROJECT_STRUCTURE.md`, `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 5.4
**What to build:**
1. Backend: `Sources/App/Services/NotificationService.swift` — APNs client using VaporAPNS:
   - Configure with P8 key
   - `sendPush(to deviceToken: String, title: String, body: String, data: [String: String])`
   - Support for: alert push, silent push, time-sensitive push
2. Backend: `Sources/App/Controllers/DeviceController.swift`:
   - `POST /v1/devices/register` — Store APNs device token
   - `DELETE /v1/devices/:id` — Remove device token
3. Backend: `Sources/App/Models/DeviceToken.swift` + migration
4. iOS: `Tempo/Services/Notifications/PushRegistrationService.swift` — Register for remote notifications, send device token to backend

**Acceptance criteria:**
- iOS app registers for push notifications and sends token to backend
- Backend can send a test push notification to a registered device
- Time-sensitive push notifications break through Scheduled Summary (per feasibility audit: use `.timeSensitive`, NOT Critical Alerts)
- Silent pushes trigger background data refresh

**Files created/modified:**
- `tempo-backend/Sources/App/Services/NotificationService.swift`
- `tempo-backend/Sources/App/Controllers/DeviceController.swift`
- `tempo-backend/Sources/App/Models/DeviceToken.swift`
- `tempo-backend/Sources/App/Migrations/CreateDeviceTokens.swift`
- `Tempo/Services/Notifications/PushRegistrationService.swift`

---

### 12.2 Local Notification Scheduling Engine

**Time estimate:** 2 hours
**Prerequisites:** 2.7 (protocol)
**Docs:** `docs/ONBOARDING_AND_NOTIFICATIONS.md`, `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 3.1
**What to build:**
Complete `Tempo/Services/Notifications/NotificationService.swift`:
- Priority queue system (per feasibility audit Section 3.1): today's notifications first, then tomorrow's morning briefing, fill remaining 64 slots
- Notification categories with actions ("Mark as Done", "Snooze 30 min")
- Anti-spam logic: cancel notification if user opens the app
- Reschedule on app foreground (recalculate based on current progress)
- Never pre-schedule more than 48 hours out

**Acceptance criteria:**
- Never exceeds 64 pending local notifications (log count on each schedule)
- Categories registered with correct actions
- Opening the app cancels pending escalation notifications
- Notification scheduling works when called from background

**Files created/modified:**
- `Tempo/Services/Notifications/NotificationService.swift` (real implementation)

---

### 12.3 Accountability Escalation Tiers

**Time estimate:** 2 hours
**Prerequisites:** 12.2, 10.1
**Docs:** `docs/ONBOARDING_AND_NOTIFICATIONS.md` (Escalation), `docs/STATE_MACHINES.md` Section 11, `docs/UX_COPY_BIBLE.md`, `docs/WIREFRAMES.md` Section 11 (Notifications)
**What to build:**
Implement the 4-tier escalation system from the architecture doc:
1. **Gentle** (2 PM) — "3 tasks left today. You've got this."
2. **Firm** (5 PM) — "2 tasks incomplete. Evening approaching."
3. **Urgent** (6:30 PM) — "Study not done. 90 min before dinner. DO IT NOW."
4. **Critical** (7 PM) — "You're about to waste another evening."
5. **Completion** — "All clear. You earned your evening."

Time-sensitive interruption level for Firm and above (per feasibility audit: NOT Critical Alerts).

**Acceptance criteria:**
- Escalation fires at correct times (configurable per user settings)
- Each tier has progressively urgent tone
- Completing all non-negotiables cancels remaining escalation notifications
- Completion notification fires immediately when leisure unlocked
- Notification copy matches UX_COPY_BIBLE.md

**Files created/modified:**
- `Tempo/Services/Notifications/NotificationService.swift` (modified)

---

### 12.4 Morning Briefing + Other Notifications

**Time estimate:** 2 hours
**Prerequisites:** 12.1, 12.2, 8.1 (recovery data)
**Docs:** `docs/ONBOARDING_AND_NOTIFICATIONS.md`
**What to build:**
1. Morning briefing (backend-sent push): recovery score, today's workout type, non-negotiable count, drill-sergeant greeting
2. Recovery notifications: "Your recovery is RED today (32%). Consider rest or light mobility."
3. Meal reminders: scheduled around typical meal times
4. Bedtime reminder: based on DailyPrescription.bedtimeRecommendation
5. Streak warning: "Your 14-day streak is at risk! Complete 1 more task."
6. Backend: `Sources/App/Jobs/NotificationScheduleJob.swift` — Scheduled job that sends morning briefings at user's configured time

**Acceptance criteria:**
- Morning briefing delivered at user's wake time (configurable)
- Recovery notification fires for red/yellow zones
- Bedtime reminder fires at prescribed time minus 30 min
- All notifications respect user's intensity preference (gentle/moderate/drill-sergeant)

**Files created/modified:**
- `tempo-backend/Sources/App/Jobs/NotificationScheduleJob.swift`
- `Tempo/Services/Notifications/NotificationService.swift` (modified)

---

### 12.5 Notification Settings UI

**Time estimate:** 1.5 hours
**Prerequisites:** 12.2
**Docs:** `docs/ONBOARDING_AND_NOTIFICATIONS.md` (Settings), `docs/WIREFRAMES.md` Section 10 (Settings)
**What to build:**
Add notification settings to the existing Settings/Profile area:
- Notification intensity: Gentle / Moderate / Drill Sergeant
- Toggle per category: Morning briefing, Accountability, Recovery, Meals, Bedtime, Streak, Arena
- Quiet hours (no notifications between X and Y)
- Sound on/off

**Acceptance criteria:**
- All toggles persist to UserSettings model
- Disabling a category immediately cancels pending notifications in that category
- Intensity level affects notification tone/copy

**Files created/modified:**
- `Tempo/Views/Shared/NotificationSettingsView.swift`
- `Tempo/Models/User/UserSettings.swift` (modified to include notification prefs)

---

## Phase 13: Calendar Integration

**Prerequisites:** Phase 9 (Training needs football schedule), Phase 10 (Accountability needs exam detection)
**Docs to reference:** `docs/INTEGRATION_SPECS.md` Section 4

---

### 13.1 Calendar Service (Real Implementation)

**Time estimate:** 2 hours
**Prerequisites:** 2.6 (protocol)
**Docs:** `docs/INTEGRATION_SPECS.md` Section 4, `docs/ARCHITECTURE_DECISIONS.md` ADR-013 (Apple Calendar via EventKit — background reading)
**What to build:**
Complete `Tempo/Services/Integrations/CalendarService.swift`:
- `requestAuthorization()` using `EKEventStore.requestFullAccessToEvents()`
- `fetchEvents(for dateRange:)` — Returns all events in range as `CalendarEvent` structs
- Event categorization: detect football (keywords: "football", "calcio", "training", "practice"), exams ("exam", "esame", "test", "quiz"), classes ("lecture", "lab", "class", "lezione")
- `detectFootballDays()` — Returns dates with football events
- `detectExamDates()` — Returns upcoming exams with date and subject name

**Acceptance criteria:**
- Authorization flow works (shows system permission dialog)
- Football detection: events containing "football" or "calcio" in title recognized
- Exam detection: events containing "exam" or "esame" recognized
- Returns empty arrays (not errors) when calendar has no relevant events

**Files created/modified:**
- `Tempo/Services/Integrations/CalendarService.swift` (real implementation)

---

### 13.2 Connect Calendar to Training + Accountability + Dashboard

**Time estimate:** 1.5 hours
**Prerequisites:** 13.1, 9.1 (TrainingEngine), 10.1 (AccountabilityEngine)
**Docs:** `docs/INTEGRATION_SPECS.md` Section 4
**What to build:**
1. Training integration: Pass football days to TrainingEngine.generateWeekPlan() so it avoids heavy legs before football
2. Accountability integration: Exam detection activates "exam mode" — study non-negotiable target increases, study reminders more frequent
3. Dashboard Mind quadrant: Show exam countdown (days until next exam)

**Acceptance criteria:**
- Football on calendar → training plan avoids heavy legs the day before
- Upcoming exam detected → exam countdown appears in Dashboard Mind quadrant
- Exam within 7 days → study target increased by 50%

**Files created/modified:**
- `Tempo/Services/Engines/TrainingEngine.swift` (modified)
- `Tempo/Services/Engines/AccountabilityEngine.swift` (modified)
- `Tempo/ViewModels/DashboardViewModel.swift` (modified)

---

## Phase 14: Arena Module

**Prerequisites:** Phase 10 (XP from accountability), Phase 9 (XP from training), Phase 6 (backend for social)
**Docs to reference:** `docs/MODULE_ARENA.md`, `docs/STATE_MACHINES.md` Sections 8, 9

---

### 14.1 Arena Backend (Models + Migrations)

**Time estimate:** 3 hours
**Prerequisites:** 6.2
**Docs:** `docs/BACKEND_API.md` (Arena endpoints), `ARCHITECTURE.md` (Arena SQL schema), `docs/COMPETITIVE_ANALYSIS.md` Section 6 (Habitica — background reading), `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 6 (Feature-Specific Risks)
**What to build:**
Fluent models + migrations for:
1. `XPEvent` — user_id, source, amount, date, created_at
2. `Friendship` + `FriendRequest` — user_id, friend_id, status
3. `Challenge` + `ChallengeParticipant` + `ChallengeDailyScore`
4. `AchievementDefinition` + `UserAchievement`
5. Materialized view: `weekly_leaderboard` (refreshed by job)
6. `Sources/App/Migrations/SeedExerciseLibrary.swift` — Seed achievement definitions

**Acceptance criteria:**
- All migrations run cleanly
- Foreign key relationships correct
- Weekly leaderboard materialized view created
- 108 achievement definitions seeded

**Files created/modified:**
- Multiple model files in `tempo-backend/Sources/App/Models/`
- Multiple migration files in `tempo-backend/Sources/App/Migrations/`

---

### 14.2 Arena Backend Controllers

**Time estimate:** 3 hours
**Prerequisites:** 14.1
**Docs:** `docs/BACKEND_API.md` (Arena endpoints)
**What to build:**
1. `XPController.swift` — `POST /v1/xp/batch` (submit XP events), `GET /v1/xp/summary` (total XP, level, history)
2. `LeaderboardController.swift` — `GET /v1/leaderboard/weekly` (top N + user's rank), `GET /v1/leaderboard/friends`
3. `FriendController.swift` — `POST /v1/friends/request`, `POST /v1/friends/accept/:id`, `DELETE /v1/friends/:id`, `GET /v1/friends`
4. `ChallengeController.swift` — CRUD for challenges, `POST /v1/challenges/:id/join`, `POST /v1/challenges/:id/score`
5. `AchievementController.swift` — `GET /v1/achievements` (user's earned), `GET /v1/achievements/definitions` (all available)
6. `Sources/App/Jobs/LeaderboardRefreshJob.swift` — Refreshes materialized view every hour

**Acceptance criteria:**
- XP submission works and updates totals
- Leaderboard returns correct rankings
- Friend request → accept flow works
- Challenges can be created, joined, and scored
- Achievements can be earned and queried

**Files created/modified:**
- Multiple controller files in `tempo-backend/Sources/App/Controllers/`
- `tempo-backend/Sources/App/Jobs/LeaderboardRefreshJob.swift`

---

### 14.3 Arena ViewModel + iOS Views

**Time estimate:** 4 hours
**Prerequisites:** 14.2, 10.7 (XPEngine)
**Docs:** `docs/MODULE_ARENA.md`, `docs/WIREFRAMES.md` Section 6 (Arena), `docs/UX_COPY_BIBLE.md` (arena strings), `docs/APP_STORE_COMPLIANCE.md` Section 6 (Content & Safety — social features)
**What to build:**
1. `Tempo/ViewModels/ArenaViewModel.swift` — XP total, level, rank, friends, challenges, achievements
2. `Tempo/Views/Arena/ArenaMainView.swift` — XP summary, level badge, weekly leaderboard preview, streak indicator
3. `Tempo/Views/Arena/LeaderboardView.swift` — Full weekly leaderboard with friend rankings
4. `Tempo/Views/Arena/FriendSystemView.swift` — Add friend (by username), pending requests, friend list
5. `Tempo/Views/Arena/ChallengesView.swift` — Active challenges, create new, join existing
6. `Tempo/Views/Arena/AchievementsView.swift` — Grid of 108 achievements (earned: color, locked: grayscale)
7. Update `ArenaTabView` to contain all sub-views

**Acceptance criteria:**
- XP, level, and rank display correctly
- Leaderboard shows friends ranked by weekly XP
- Friend request flow works end-to-end
- Achievements grid renders all 108 (with earned/locked states)
- Achievement unlock shows celebration animation (Lottie)

**Files created/modified:**
- `Tempo/ViewModels/ArenaViewModel.swift`
- `Tempo/Views/Arena/ArenaMainView.swift`
- `Tempo/Views/Arena/LeaderboardView.swift`
- `Tempo/Views/Arena/FriendSystemView.swift`
- `Tempo/Views/Arena/ChallengesView.swift`
- `Tempo/Views/Arena/AchievementsView.swift`
- `Tempo/Views/Arena/ArenaTabView.swift` (completed)

---

## Phase 15: AI Intelligence Engine

**Prerequisites:** Phase 8-14 (data from all modules)
**Docs to reference:** `docs/AI_INTELLIGENCE_ENGINE.md`

---

### 15.1 Claude API Backend Service

**Time estimate:** 2 hours
**Prerequisites:** 6.1
**Docs:** `docs/AI_INTELLIGENCE_ENGINE.md`, `docs/APP_STORE_COMPLIANCE.md` Section 1 (AI Data Sharing Compliance — Guideline 5.1.2(i)), `docs/ARCHITECTURE_DECISIONS.md` ADR-018 (Claude API over on-device ML — background reading)
**What to build:**
1. `Sources/App/Services/InsightService.swift` — Claude API client:
   - Use Haiku for real-time (drill sergeant copy, quick insights)
   - Use Sonnet for deep analysis (weekly reports, pattern detection)
   - Prompt templates per context
   - Cost tracking (log tokens used per request)
   - Fallback: return algorithmic response when Claude unavailable
2. `Sources/App/Controllers/InsightController.swift`:
   - `GET /v1/insights/weekly-report` — Generate weekly report
   - `GET /v1/insights/patterns` — Detect correlations
   - `GET /v1/insights/drill-sergeant` — Generate contextual drill-sergeant copy
3. Rate limiting: max 10 AI requests per user per day

**Acceptance criteria:**
- Claude API called successfully with prompt
- Responses parsed and returned to iOS
- Fallback works when Claude API is down
- Token usage logged per request

**Files created/modified:**
- `tempo-backend/Sources/App/Services/InsightService.swift`
- `tempo-backend/Sources/App/Controllers/InsightController.swift`

---

### 15.2 Weekly Report + Drill Sergeant Copy

**Time estimate:** 2 hours
**Prerequisites:** 15.1
**Docs:** `docs/AI_INTELLIGENCE_ENGINE.md`
**What to build:**
1. `Sources/App/Jobs/WeeklySummaryJob.swift` — Sunday job that generates weekly reports for all users
2. iOS: `Tempo/Views/Dashboard/WeeklyReportView.swift` — Display weekly AI insights with charts
3. Drill sergeant copy generation: contextual motivational/roast messages based on current progress, streak status, time of day

**Acceptance criteria:**
- Weekly report summarizes: training consistency, nutrition compliance, recovery trends, study hours, streaks
- Drill sergeant copy is contextual and matches the app's tone
- Reports cached (generated once, served from cache)

**Files created/modified:**
- `tempo-backend/Sources/App/Jobs/WeeklySummaryJob.swift`
- `Tempo/Views/Dashboard/WeeklyReportView.swift`

---

## Phase 16: Onboarding

**Prerequisites:** All integrations (Phases 5-13) and all modules (Phases 8-14)
**Docs to reference:** `docs/ONBOARDING_AND_NOTIFICATIONS.md`, `docs/STATE_MACHINES.md` Section 10

---

### 16.1 Onboarding Flow Container

**Time estimate:** 3 hours
**Prerequisites:** All prior phases
**Docs:** `docs/ONBOARDING_AND_NOTIFICATIONS.md`, `docs/STATE_MACHINES.md` Section 10, `docs/WIREFRAMES.md` Section 7 (Onboarding), `docs/UX_COPY_BIBLE.md` (onboarding strings), `docs/APP_STORE_COMPLIANCE.md` Section 1 (AI consent flow during onboarding)
**What to build:**
1. `Tempo/ViewModels/OnboardingViewModel.swift` — State machine: welcome → signIn → profile → training → academic → goals → whoop → nutritrack → healthkit → notifications → arena → complete
2. `Tempo/Views/Onboarding/OnboardingContainerView.swift` — PageView-style container
3. Individual step views (creating only those not already built):
   - `WelcomeView.swift` — Hero screen: "Stop wasting your potential"
   - `ProfileSetupView.swift` — Name, weight, height
   - `TrainingSetupView.swift` — Split selection, football days, equipment
   - `AcademicSetupView.swift` — Exam schedule, study targets
   - `GoalSetupView.swift` — Non-negotiable initial configuration
   - `NotificationSetupView.swift` — Permission request + intensity selection
   - `OnboardingCompleteView.swift` — "Welcome to Tempo" with first day briefing

4. State persistence: if app killed during onboarding, resume from last completed step

**Acceptance criteria:**
- Full onboarding flow works end-to-end (12 steps)
- Each step validates before allowing "Next"
- Progress indicator shows current step
- State persisted in UserDefaults (resume on kill)
- Skip allowed for optional steps (Whoop, NutriTrack)
- On completion: `AppState.isOnboardingComplete = true`, shows main tab view

**Files created/modified:**
- `Tempo/ViewModels/OnboardingViewModel.swift`
- `Tempo/Views/Onboarding/OnboardingContainerView.swift`
- `Tempo/Views/Onboarding/WelcomeView.swift`
- `Tempo/Views/Onboarding/ProfileSetupView.swift`
- `Tempo/Views/Onboarding/TrainingSetupView.swift`
- `Tempo/Views/Onboarding/AcademicSetupView.swift`
- `Tempo/Views/Onboarding/GoalSetupView.swift`
- `Tempo/Views/Onboarding/NotificationSetupView.swift`
- `Tempo/Views/Onboarding/CalendarPermissionView.swift`
- `Tempo/Views/Onboarding/OnboardingCompleteView.swift`

---

## Phase 17: Widgets

**Prerequisites:** Phase 4 (Dashboard data), Phase 5 (HealthKit), 0.4 (App Groups)
**Docs to reference:** `docs/XCODE_PROJECT_STRUCTURE.md` Section 10

---

### 17.1 Widget Extension Target Setup

**Time estimate:** 1 hour
**Prerequisites:** 0.4 (App Groups entitlement)
**Docs:** `docs/XCODE_PROJECT_STRUCTURE.md` Section 10
**What to build:**
1. File → New → Target → Widget Extension → "TempoWidgets"
2. Add App Group: `group.app.tempo` (shared with main app)
3. Configure to access shared SwiftData container
4. Create `TempoWidgetBundle.swift` with all widget entries

**Acceptance criteria:**
- Widget extension target builds
- Shares data with main app via App Group
- Can read SwiftData models

**Files created/modified:**
- `TempoWidgets/` target directory
- `TempoWidgets/TempoWidgetBundle.swift`

---

### 17.2 Small + Medium + Large Widgets

**Time estimate:** 3 hours
**Prerequisites:** 17.1
**Docs:** `docs/MODULE_DASHBOARD.md` (Widgets), `docs/WIREFRAMES.md` Section 8 (Widgets)
**What to build:**
1. **Small widget:** Daily score ring + current streak count
2. **Medium widget:** 4 mini stats (recovery, calories, study, steps) in a row
3. **Large widget:** Mini dashboard — score ring + 4 quadrant summaries
4. Lock screen widget: Score number (circular complication style)

**Acceptance criteria:**
- All widget sizes render correctly
- Data updates via timeline (every 15 minutes)
- Deep link: tapping widget opens the relevant module
- Widgets use design system colors
- Lock screen widget readable at small size

**Files created/modified:**
- `TempoWidgets/SmallWidget.swift`
- `TempoWidgets/MediumWidget.swift`
- `TempoWidgets/LargeWidget.swift`
- `TempoWidgets/LockScreenWidget.swift`

---

## Phase 18: Apple Watch

**Prerequisites:** Phase 9 (Training), Phase 10 (Accountability)
**Docs to reference:** `docs/APPLE_WATCH_APP.md`, `docs/XCODE_PROJECT_STRUCTURE.md` Section 11

---

### 18.1 Watch App Target Setup

**Time estimate:** 1 hour
**Prerequisites:** 0.2
**Docs:** `docs/XCODE_PROJECT_STRUCTURE.md` Section 11, `docs/ARCHITECTURE_DECISIONS.md` ADR-028 (Apple Watch as companion app — background reading)
**What to build:**
1. File → New → Target → watchOS App → "Tempo Watch"
2. Set up WatchConnectivity framework in both iOS app and Watch app
3. Share relevant models via shared framework or App Group

**Acceptance criteria:**
- Watch target builds and runs on watchOS simulator
- WatchConnectivity session activates between iPhone and Watch

**Files created/modified:**
- `Tempo Watch/` target directory

---

### 18.2 Watch Workout Logging + Timer

**Time estimate:** 3 hours
**Prerequisites:** 18.1, 9.4
**Docs:** `docs/APPLE_WATCH_APP.md`
**What to build:**
1. Workout logging: current exercise, set counter, weight/reps display, "Done" button
2. Rest timer on wrist (haptic on completion)
3. Focus timer on wrist (start/pause/stop)
4. Watch complications: daily score, streak count

**Acceptance criteria:**
- Workout data syncs from iPhone to Watch and back
- Set logging on Watch updates iPhone's workout session
- Rest timer fires haptic on Watch wrist
- Focus timer works independently on Watch

**Files created/modified:**
- Multiple Watch view files

---

## Phase 19: Polish and Testing

**Prerequisites:** All features built (Phases 0-18)
**Docs to reference:** `docs/TESTING_STRATEGY.md`, `docs/ACCESSIBILITY.md`, `docs/PERFORMANCE_OPTIMIZATION.md`, `docs/SOUND_AND_HAPTICS.md`

---

### 19.1 Dark Mode + Dynamic Type Audit

**Time estimate:** 3 hours
**Prerequisites:** All views built
**Docs:** `docs/DESIGN_SYSTEM.md` (Dark Mode), `docs/ACCESSIBILITY.md`
**What to build:**
- Test every screen in dark mode, fix any color/contrast issues
- Test with Dynamic Type sizes: Default, XXL, AX3 (accessibility largest)
- Fix any truncation, overlap, or layout breaking at large text sizes

**Acceptance criteria:**
- Zero contrast issues in dark mode
- All text readable at XXL Dynamic Type
- No layout breaks at AX3

**Files created/modified:**
- Various view files (fixes)

---

### 19.2 Animation + Haptics + Sound Polish

**Time estimate:** 3 hours
**Prerequisites:** All views built
**Docs:** `docs/SOUND_AND_HAPTICS.md`, `docs/DESIGN_SYSTEM.md` (Motion)
**What to build:**
- Add micro-interactions: button press scales, card tap highlight, tab switch animation
- Integrate sound effects: timer tick, workout complete, PR achieved, XP gain, level up, streak fire, leisure unlock
- Verify haptics fire correctly throughout the app
- Add Lottie animations: streak flame, level-up burst, achievement unlock

**Acceptance criteria:**
- Sound effects play at correct moments
- Haptics match the interaction context
- Animations are smooth (60fps)
- Reduced Motion setting respected (disable animations when enabled)

**Files created/modified:**
- Various view files (adding animations/sounds/haptics)
- `Tempo/Resources/Sounds/` (sound files added)

---

### 19.3 Unit Tests

**Time estimate:** 4 hours
**Prerequisites:** All engines and services built
**Docs:** `docs/TESTING_STRATEGY.md`, `docs/EXERCISE_SCIENCE.md` Section 9 (Algorithm Validation — background reading for test thresholds), `docs/SECURITY_AND_PRIVACY.md` Section 12 (Penetration Testing Checklist)
**What to build:**
Unit tests for all engines:
- `ScoringEngineTests.swift` — Score calculation edge cases
- `TrainingEngineTests.swift` — Workout generation, progressive overload, recovery adjustment
- `RecoveryEngineTests.swift` — Prescription generation, zone classification
- `AccountabilityEngineTests.swift` — Leisure unlock logic, streak calculation
- `XPEngineTests.swift` — XP calculation, level formula

Unit tests for services:
- `APIClientTests.swift` — Token refresh, retry logic, error handling
- `HealthKitServiceTests.swift` — Data parsing (mock HKHealthStore)

**Acceptance criteria:**
- All engine tests pass
- Edge cases covered (0 recovery, nil data, all non-negotiables complete, empty workout)
- Tests run in < 30 seconds total

**Files created/modified:**
- `Tempo/TempoTests/Engines/*.swift`
- `Tempo/TempoTests/Services/*.swift`
- `Tempo/TempoTests/Mocks/*.swift`
- `Tempo/TempoTests/Helpers/XCTestCase+SwiftData.swift`

---

### 19.4 UI Tests + Snapshot Tests

**Time estimate:** 3 hours
**Prerequisites:** 19.3
**Docs:** `docs/TESTING_STRATEGY.md` Section 6, `docs/USER_JOURNEYS.md` (all journeys — use as end-to-end test scenarios), `docs/ACCESSIBILITY.md` Section 9 (Accessibility Testing Checklist)
**What to build:**
1. UI tests (XCUITest):
   - Onboarding flow completion
   - Dashboard navigation between quadrants
   - Start and complete a workout
   - Focus timer session
   - Friend request flow
2. Snapshot tests (swift-snapshot-testing):
   - Dashboard (all quadrant states)
   - Recovery today view
   - Lockdown view (locked and unlocked)
   - All shared components

**Acceptance criteria:**
- UI tests run end-to-end without flakiness
- Snapshot reference images generated for all screens
- Snapshots pass on both light and dark mode

**Files created/modified:**
- `Tempo/TempoUITests/*.swift`
- `Tempo/TempoSnapshotTests/*.swift`

---

### 19.5 Performance Profiling

**Time estimate:** 2 hours
**Prerequisites:** All features complete
**Docs:** `docs/PERFORMANCE_OPTIMIZATION.md`
**What to build:**
Profile with Instruments:
- Cold launch < 1 second
- Dashboard render < 200ms
- 90-day chart render < 300ms
- Heatmap calendar render < 16ms per frame
- Memory usage < 150MB during active workout
- No memory leaks (Instruments → Leaks)

Fix any violations.

**Acceptance criteria:**
- All performance budgets met
- No memory leaks detected
- No main thread hangs > 100ms (Instruments → Time Profiler)

**Files created/modified:**
- Various files (optimizations)

---

## Phase 20: Launch Preparation

**Prerequisites:** Phase 19 (polish complete)
**Docs to reference:** `docs/MONETIZATION_STRATEGY.md`, `docs/ANALYTICS_AND_METRICS.md`, `docs/SECURITY_AND_PRIVACY.md`, `docs/APP_STORE_STRATEGY.md`

---

### 20.1 Subscription Setup (StoreKit 2)

**Time estimate:** 3 hours
**Prerequisites:** 0.4 (In-App Purchase capability)
**Docs:** `docs/MONETIZATION_STRATEGY.md`, `docs/DEPENDENCIES.md` Section 2.15, `docs/APP_STORE_COMPLIANCE.md` Section 5 (In-App Purchase / Subscription Compliance), `docs/STATE_MACHINES.md` Section 15 (Subscription), `docs/COMPETITIVE_ANALYSIS.md` Sections 11-12 (Competitive Moat, Feature Priority — background reading)
**What to build:**
1. `Tempo/Services/SubscriptionService.swift` — StoreKit 2 implementation:
   - Two products: `com.tempo.pro.monthly` ($7.99), `com.tempo.pro.annual` ($59.99)
   - Listen for transaction updates
   - Verify entitlements
   - Handle upgrades, downgrades, cancellations
   - Server-side receipt validation via backend
2. `Tempo/Views/Shared/PaywallView.swift` — Paywall UI with feature comparison
3. Backend: subscription webhook handler for App Store Server Notifications v2

**Acceptance criteria:**
- Subscription purchase flow works in sandbox
- Entitlement check gates premium features (Arena social, AI insights, unlimited friends)
- Paywall shows with correct pricing
- Receipt validated server-side

**Files created/modified:**
- `Tempo/Services/SubscriptionService.swift`
- `Tempo/Views/Shared/PaywallView.swift`
- `tempo-backend/Sources/App/Controllers/SubscriptionController.swift`

---

### 20.2 Analytics Implementation

**Time estimate:** 2 hours
**Prerequisites:** 0.6 (PostHog dependency)
**Docs:** `docs/ANALYTICS_AND_METRICS.md`, `docs/ARCHITECTURE_DECISIONS.md` ADR-024, ADR-026 (PostHog, Feature Flags — background reading)
**What to build:**
1. `Tempo/Services/AnalyticsService.swift` — Wrapper around PostHog:
   - Lazy initialization (not in app init)
   - Track key events: onboarding steps, workout started/completed, focus session, XP earned, subscription events
   - Feature flag evaluation
   - User identification (after sign-in)
2. Add tracking calls to critical user journeys

**Acceptance criteria:**
- PostHog receives events in dashboard
- User identified after sign-in
- Feature flags evaluated and cached
- No analytics calls before user consent

**Files created/modified:**
- `Tempo/Services/AnalyticsService.swift`
- Various view files (add tracking calls)

---

### 20.3 Privacy Policy + App Store Listing

**Time estimate:** 2 hours
**Prerequisites:** All features finalized
**Docs:** `docs/SECURITY_AND_PRIVACY.md` (Sections 1, 8, 11, 13-14), `docs/APP_STORE_STRATEGY.md`, `docs/APP_STORE_COMPLIANCE.md` Section 3 (Privacy & Data), `docs/DATA_MODELS_IOS.md` Section 14 (Data Lifecycle & Cleanup), `docs/DATA_FLOW_ARCHITECTURE.md` Section 9 (Data Deletion Flow GDPR)
**What to build:**
1. Privacy policy (hosted webpage)
2. Terms of service (hosted webpage)
3. App Store description, keywords, screenshots
4. App privacy nutrition labels (data collection declarations)

**Acceptance criteria:**
- Privacy policy covers all data types collected (HealthKit, Whoop, NutriTrack, Calendar)
- App Store description highlights key features
- Screenshots prepared for iPhone 15 Pro Max and iPhone SE sizes
- Privacy labels accurately declare data collection

**Files created/modified:**
- External: hosted webpages
- App Store Connect configuration

---

### 20.4 CI/CD Pipeline + TestFlight

**Time estimate:** 2 hours
**Prerequisites:** All tests passing
**Docs:** `docs/CI_CD_PIPELINE.md`, `docs/DEPENDENCIES.md` Sections 7-8 (Dependency Update Strategy, Security Scanning), `docs/ARCHITECTURE_DECISIONS.md` ADR-025, ADR-027 (Cloud deployment, Crashlytics — background reading)
**What to build:**
1. GitHub Actions workflow: build → test → archive → upload to TestFlight
2. Backend: GitHub Actions → Docker build → deploy to Railway
3. TestFlight internal testing group
4. First TestFlight build distributed

**Acceptance criteria:**
- Push to `develop` triggers build + test
- Push to `main` triggers TestFlight upload
- Backend deploys automatically on merge to main
- TestFlight build installable on test devices

**Files created/modified:**
- `.github/workflows/ios.yml`
- `.github/workflows/backend.yml`

---

### 20.5 App Store Submission

**Time estimate:** 2 hours
**Prerequisites:** 20.1-20.4
**Docs:** `docs/APP_STORE_STRATEGY.md`, `docs/RELEASE_CHECKLIST.md`, `docs/APP_STORE_COMPLIANCE.md` Sections 4, 7-8 (App Review Preparation, Rejection Risk Mitigation, Pre-Submission Checklist), `docs/TECHNICAL_FEASIBILITY_AUDIT.md` Section 7 (App Store Review Risks), `docs/XCODE_PROJECT_STRUCTURE.md` Section 9 (Code Signing)
**What to build:**
1. Final QA pass against `docs/RELEASE_CHECKLIST.md`
2. Archive and upload to App Store Connect
3. Fill in all metadata
4. Submit for review

**Acceptance criteria:**
- App passes all pre-submission checks
- Submitted to Apple for review
- No rejected binary issues (entitlements, privacy descriptions, etc.)

---

## Dependency Graph

```
Phase 0: Project Scaffolding
├── 0.1 Git init
├── 0.2 Xcode project ──────────────────────────────────┐
├── 0.3 Folder structure (depends on 0.2) ───────────────┤
├── 0.4 Entitlements (depends on 0.2)                    │
├── 0.5 Build configs (depends on 0.2)                   │
├── 0.6 SPM dependencies (depends on 0.2)                │
├── 0.7 SwiftLint (depends on 0.2)                       │
├── 0.8 Vapor project (depends on 0.1) ─────────────┐    │
├── 0.9 Docker compose (depends on 0.8)              │    │
└── 0.10 Enums/constants (depends on 0.3) ──────┐   │    │
                                                 │   │    │
Phase 1: Data Models (depends on 0.10) ──────────┤   │    │
├── 1.1-1.8 All models (depend on 0.10)          │   │    │
├── 1.9 ModelContainer (depends on 1.1-1.8)      │   │    │
└── 1.10 Exercise seed data (depends on 1.3)     │   │    │
                                                 │   │    │
Phase 2: Service Stubs (depends on Phase 1) ─────┤   │    │
├── 2.1 APIClient (depends on 0.5)               │   │    │
├── 2.2 Auth (depends on 2.1)                    │   │    │
├── 2.3-2.11 All service stubs                   │   │    │
└── 2.12 AppState + Container (depends on 2.*)   │   │    │
                                                 │   │    │
Phase 3: Design System (depends on 0.2) ─────────┼───┼────┤
├── 3.1-3.3 Tokens (depend on 0.3)              │   │    │
├── 3.4-3.9 Components (depend on 3.1-3.3)      │   │    │
├── 3.10 Tab bar (depends on 3.1, 2.12)         │   │    │
├── 3.11 Utilities                               │   │    │
└── 3.12 State views                             │   │    │
                                                 │   │    │
Phase 4: Dashboard Views ────────────────────────┘   │    │
  (depends on Phase 1 + 2 + 3)                       │    │
                                                     │    │
Phase 5: HealthKit Real ─────────────────────────────│────┘
  (depends on Phase 2 + 4)                           │
                                                     │
Phase 6: Backend Foundation ─────────────────────────┘
  (depends on 0.8 + 0.9)
  │
  ├── Phase 7: Whoop Integration
  │     (depends on Phase 6)
  │     │
  │     └── Phase 8: Recovery Module
  │           (depends on Phase 7 + 5 + 4)
  │           │
  │           └── Phase 9: Training Module
  │                 (depends on Phase 8 + 5 + 1.10)
  │
  ├── Phase 11: NutriTrack Integration
  │     (depends on Phase 6)
  │
  └── Phase 12: Notification System
        (depends on Phase 6 + 10 + 8)

Phase 10: Accountability Module
  (depends on Phase 5 + 4)

Phase 13: Calendar Integration
  (depends on Phase 9 + 10)

Phase 14: Arena Module
  (depends on Phase 10 + 9 + 6)

Phase 15: AI Engine
  (depends on Phase 8-14 data)

Phase 16: Onboarding
  (depends on ALL integrations + modules)

Phase 17: Widgets ──── can START after Phase 5
  (depends on Phase 4 + 5 + App Groups)

Phase 18: Apple Watch ── can START after Phase 9
  (depends on Phase 9 + 10)

Phase 19: Polish + Testing
  (depends on ALL features)

Phase 20: Launch
  (depends on Phase 19)
```

### Parallelization Opportunities

These phase groups can be worked on simultaneously:

| Parallel Track A (iOS) | Parallel Track B (Backend) |
|------------------------|---------------------------|
| Phase 0.2-0.7 (iOS scaffold) | Phase 0.8-0.9 (Vapor scaffold) |
| Phase 1 (Data models) | Phase 6.1-6.4 (Backend foundation) |
| Phase 3 (Design system) | Phase 6.5-6.7 (Auth) |
| Phase 4 (Dashboard views) | Phase 7.1-7.3 (Whoop backend) |
| Phase 5 (HealthKit) | Phase 11.1 (NutriTrack backend) |
| Phase 10 (Accountability) | Phase 14.1-14.2 (Arena backend) |
| Phase 17 (Widgets) | Phase 15.1 (AI backend) |

### Critical Path (Longest Sequential Chain)

```
0.2 → 0.10 → 1.3 → 1.9 → 2.8 → 9.1 → 9.2 → 9.4 → 9.5
                                                        ↓
0.8 → 6.1 → 6.4 → 7.1 → 7.4 → 8.1 → 8.3 ────→ Phase 16 → 19 → 20
```

The critical path runs through: Project setup → Models → Training Engine → Workout views AND Backend → Auth → Whoop → Recovery. These two tracks converge at the Recovery-based workout adjustments and ultimately at onboarding and polish.

**Estimated total time:** 180-220 hours of focused development work (roughly 6-8 weeks full-time, or 10-14 weeks at 20h/week).
