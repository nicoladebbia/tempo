# Tempo iOS -- Xcode Project Setup Guide

> **Version:** 1.0.0
> **Last updated:** 2026-03-24
> **Author:** iOS Architecture
> **Goal:** From zero to running app in under 30 minutes. Zero guesswork.

---

## Table of Contents

1. [Project Creation](#1-project-creation)
2. [Complete File/Folder Structure](#2-complete-filefolder-structure)
3. [Build Configurations](#3-build-configurations)
4. [Capabilities & Entitlements](#4-capabilities--entitlements)
5. [Info.plist Configuration](#5-infoplist-configuration)
6. [SPM Dependencies](#6-spm-dependencies)
7. [Build Phases](#7-build-phases)
8. [Schemes](#8-schemes)
9. [Code Signing](#9-code-signing)
10. [Widget Extension](#10-widget-extension)
11. [Watch App Target](#11-watch-app-target)
12. [Coding Standards](#12-coding-standards)
13. [First Build Checklist](#13-first-build-checklist)

---

## 1. Project Creation

### Prerequisites

| Requirement | Value |
|-------------|-------|
| **Xcode** | 16.0+ (required for Swift 6, SwiftData improvements, watchOS 11 SDK) |
| **macOS** | Sequoia 15.0+ |
| **Apple Developer Account** | Paid ($99/year) -- required for HealthKit, Push Notifications, Sign in with Apple |

### New Project Settings

Open Xcode. File > New > Project.

| Setting | Value |
|---------|-------|
| Template | **App** (under iOS tab) |
| Product Name | `Tempo` |
| Team | Your Apple Developer team |
| Organization Identifier | `app.tempo` |
| Bundle Identifier | `app.tempo.Tempo` (auto-generated from org + product name) |
| Interface | **SwiftUI** |
| Language | **Swift** |
| Storage | **SwiftData** |
| Include Tests | **Yes** (check both Unit Tests and UI Tests) |

After creation, immediately change these in Build Settings:

| Setting | Value |
|---------|-------|
| iOS Deployment Target | **17.0** |
| Swift Language Version | **Swift 6** |
| Strict Concurrency Checking | **Complete** |

### Why `app.tempo` and not `com.tempo`

The `com.` prefix is conventionally reserved for companies with registered domains. Using `app.tempo` matches the production domain `tempo.app` (reverse-DNS of `app.tempo`). This is the correct convention and avoids any conflict with existing `com.tempo.*` identifiers on the App Store.

---

## 2. Complete File/Folder Structure

Create this structure inside the Xcode project. Every folder listed below is a **Group** in Xcode (yellow folder icon), mirrored on disk.

```
Tempo/
├── TempoApp.swift                          # @main App entry point, ModelContainer setup, BGTask registration
├── ContentView.swift                       # Root TabView with 5 tabs
├── Info.plist                              # Custom keys (HealthKit descriptions, BG tasks, URL types)
├── Tempo.entitlements                      # HealthKit, Push, App Groups, Sign in with Apple, etc.
│
├── Configuration/
│   ├── Development.xcconfig                # Dev API URL, debug flags
│   ├── Staging.xcconfig                    # Staging API URL, staging bundle suffix
│   ├── Production.xcconfig                 # Production API URL, release settings
│   └── Secrets.xcconfig                    # API keys (git-ignored, loaded per-environment)
│
├── App/
│   └── AppState.swift                      # Global app state: onboarding complete, auth status, active tab
│
├── Models/
│   ├── Schema/
│   │   ├── TempoSchemaV1.swift             # VersionedSchema with all model types
│   │   ├── TempoSchemaV2.swift             # Future schema version placeholder
│   │   ├── TempoMigrationPlan.swift        # SchemaMigrationPlan with staged migrations
│   │   └── TempoModelContainer.swift       # ModelContainer factory (production + preview)
│   │
│   ├── Enums/
│   │   ├── WorkoutEnums.swift              # WorkoutType, WorkoutStatus, MuscleGroup, Equipment, MovementPattern, PRType
│   │   ├── AccountabilityEnums.swift       # NonNegotiableType, TrackingMethod, StudySessionType, StreakType
│   │   ├── RecoveryEnums.swift             # RecoveryZone, RecoveryInsightType
│   │   ├── ArenaEnums.swift                # XPSource, AchievementCategory, AchievementRarity
│   │   └── SyncEnums.swift                 # SyncAction
│   │
│   ├── SharedTypes/
│   │   ├── WeightUnit.swift                # WeightUnit enum with conversion
│   │   ├── TrainingSplit.swift             # TrainingSplit enum
│   │   └── ActiveDays.swift               # Bitmask for day-of-week selection
│   │
│   ├── User/
│   │   ├── UserProfile.swift               # @Model: identity, biometrics, training config
│   │   └── UserSettings.swift              # @Model: notification prefs, units, theme
│   │
│   ├── Dashboard/
│   │   └── DailySnapshot.swift             # @Model: aggregated daily scores across all domains
│   │
│   ├── Training/
│   │   ├── WorkoutPlan.swift               # @Model: planned workout for a day
│   │   ├── PlannedExercise.swift           # @Model: exercise within a workout
│   │   ├── PlannedSet.swift                # @Model: individual set within an exercise
│   │   ├── Exercise.swift                  # @Model: exercise library entry (name, muscle group, equipment)
│   │   ├── ExerciseHistory.swift           # @Model: historical performance per exercise
│   │   ├── PersonalRecord.swift            # @Model: 1RM, rep max, volume records
│   │   └── RunSession.swift                # @Model: GPS run/cardio data
│   │
│   ├── Accountability/
│   │   ├── NonNegotiable.swift             # @Model: user-defined daily requirement
│   │   ├── DailyAccountability.swift       # @Model: today's completion state
│   │   ├── NonNegotiableProgress.swift     # @Model: per-item progress tracking
│   │   ├── StudySession.swift              # @Model: Pomodoro/deep work session
│   │   └── Streak.swift                    # @Model: streak tracking per category
│   │
│   ├── Recovery/
│   │   ├── DailyRecovery.swift             # @Model: Whoop recovery + HRV + RHR
│   │   ├── DailyPrescription.swift         # @Model: AI-generated daily prescription
│   │   └── RecoveryInsight.swift           # @Model: correlation/pattern insight
│   │
│   ├── Arena/
│   │   ├── XPEvent.swift                   # @Model: individual XP gain/loss event
│   │   ├── Achievement.swift               # @Model: unlocked achievement
│   │   └── ChallengeLocal.swift            # @Model: locally-cached challenge state
│   │
│   ├── Sync/
│   │   ├── SyncState.swift                 # @Model: last sync timestamps per entity type
│   │   └── PendingSync.swift               # @Model: queue of changes waiting for upload
│   │
│   ├── Integrations/
│   │   ├── WhoopConnection.swift           # @Model: Whoop OAuth connection state
│   │   ├── NutriTrackConnection.swift      # @Model: NutriTrack connection state
│   │   └── HealthKitState.swift            # @Model: HealthKit authorization status cache
│   │
│   └── DTOs/
│       ├── UserProfileDTO.swift            # Codable DTO for API sync
│       ├── WorkoutDTO.swift                # Codable DTO for workout sync
│       ├── RecoveryDTO.swift               # Codable DTO for recovery data from backend
│       └── ArenaDTO.swift                  # Codable DTO for leaderboard/challenge data
│
├── Services/
│   ├── Network/
│   │   ├── APIClient.swift                 # URLSession-based HTTP client, JWT injection, retry logic
│   │   ├── APIEndpoints.swift              # Typed endpoint definitions (path, method, body)
│   │   ├── APIError.swift                  # Typed API errors with user-facing messages
│   │   └── AuthInterceptor.swift           # JWT refresh, 401 retry, token storage
│   │
│   ├── Auth/
│   │   ├── AuthService.swift               # Sign in with Apple flow, JWT management
│   │   └── KeychainService.swift           # Keychain read/write for JWT tokens
│   │
│   ├── Health/
│   │   ├── HealthKitService.swift          # HKHealthStore wrapper, authorization, queries
│   │   └── HealthKitBackgroundDelivery.swift # Background observer queries, BGTask handlers
│   │
│   ├── Integrations/
│   │   ├── WhoopService.swift              # Whoop OAuth flow (ASWebAuthenticationSession), sync trigger
│   │   ├── NutriTrackService.swift         # NutriTrack proxy API calls via backend
│   │   └── CalendarService.swift           # EventKit wrapper, class/football schedule reading
│   │
│   ├── Sync/
│   │   ├── SyncCoordinator.swift           # Orchestrates upload/download, conflict resolution
│   │   └── BackgroundSyncService.swift     # BGAppRefreshTask scheduling and execution
│   │
│   ├── Notifications/
│   │   ├── NotificationService.swift       # UNUserNotificationCenter, local scheduling
│   │   └── PushRegistrationService.swift   # APNs device token registration with backend
│   │
│   └── Engines/
│       ├── ScoringEngine.swift             # Daily score calculation (0-100) from all domains
│       ├── TrainingEngine.swift            # Workout generation, progressive overload, recovery adjustment
│       ├── RecoveryEngine.swift            # Recovery zone classification, prescription generation
│       ├── AccountabilityEngine.swift      # Non-negotiable tracking, leisure unlock logic
│       └── XPEngine.swift                  # XP calculation, streak multipliers, anti-farm rules
│
├── Views/
│   ├── Dashboard/
│   │   ├── DashboardView.swift             # Main 4-quadrant view: Body/Fuel/Mind/Move
│   │   ├── QuadrantCardView.swift          # Reusable quadrant card component
│   │   ├── DailyScoreRingView.swift        # Central score ring animation
│   │   ├── WeeklyReportView.swift          # Weekly summary with charts
│   │   ├── PatternCorrelationView.swift    # AI-detected patterns
│   │   ├── DailyTimelineView.swift         # Chronological day view
│   │   └── QuickActionsView.swift          # Floating action shortcuts
│   │
│   ├── Training/
│   │   ├── TodayWorkoutView.swift          # Today's planned workout overview
│   │   ├── ActiveWorkoutView.swift         # In-progress workout logging (sets/reps/weight)
│   │   ├── WeightInputView.swift           # Precision weight input with haptics
│   │   ├── PlateCalculatorView.swift       # Visual barbell plate calculator
│   │   ├── RestTimerView.swift             # Countdown rest timer between sets
│   │   ├── WorkoutSummaryView.swift        # Post-workout summary with PRs
│   │   ├── WeekPlanView.swift              # Week-at-a-glance training plan
│   │   ├── ExerciseLibraryView.swift       # Searchable exercise database
│   │   ├── ExerciseDetailView.swift        # Single exercise history + charts
│   │   ├── ProgressChartsView.swift        # Volume, 1RM, frequency charts
│   │   ├── PersonalRecordsView.swift       # PR board with gold/silver badges
│   │   ├── RunSessionView.swift            # Running/cardio tracking
│   │   └── TrainingSettingsView.swift      # Split, equipment, deload preferences
│   │
│   ├── Accountability/
│   │   ├── LockdownMainView.swift          # Today's non-negotiables with progress
│   │   ├── FocusTimerView.swift            # Pomodoro/deep work timer
│   │   ├── NonNegotiableSetupView.swift    # Configure daily requirements
│   │   ├── StreakCalendarView.swift         # Streak heatmap calendar
│   │   ├── WeekendModeView.swift           # Weekend schedule adjustments
│   │   └── ExamModeView.swift              # Exam week configuration
│   │
│   ├── Recovery/
│   │   ├── RecoveryTodayView.swift         # Recovery score, zone, prescription cards
│   │   ├── SleepDetailView.swift           # Sleep stage breakdown
│   │   ├── StrainDetailView.swift          # Strain + activity breakdown
│   │   ├── RecoveryTrendsView.swift        # 7/30/90 day recovery trends
│   │   ├── PrescriptionDetailView.swift    # Expanded prescription reasoning
│   │   ├── WhoopConnectionView.swift       # Whoop OAuth connect/disconnect
│   │   └── HistoricalComparisonView.swift  # Compare two date ranges
│   │
│   ├── Arena/
│   │   ├── ArenaMainView.swift             # XP summary, level, streak, quick stats
│   │   ├── ProfileStatsView.swift          # Detailed profile card with stats
│   │   ├── LeaderboardView.swift           # Weekly leaderboard with friends
│   │   ├── FriendSystemView.swift          # Add/manage friends
│   │   ├── ChallengesView.swift            # Active and available challenges
│   │   ├── AchievementsView.swift          # Achievement grid (108 achievements)
│   │   ├── XPAnimationView.swift           # Floating XP gain animation overlay
│   │   ├── SocialFeedView.swift            # Friend activity feed
│   │   └── ArenaSettingsView.swift         # Competition preferences
│   │
│   ├── Onboarding/
│   │   ├── OnboardingContainerView.swift   # Page-based onboarding flow controller
│   │   ├── WelcomeView.swift               # "Stop wasting your potential" hero
│   │   ├── SignInWithAppleView.swift        # Apple auth button + flow
│   │   ├── HealthKitPermissionView.swift   # HealthKit authorization prompt
│   │   ├── WhoopSetupView.swift            # Optional Whoop connection
│   │   ├── ProfileSetupView.swift          # Name, weight, height, training split
│   │   ├── NonNegotiableSetupOnboardingView.swift  # Initial non-negotiable configuration
│   │   ├── CalendarPermissionView.swift    # EventKit authorization prompt
│   │   └── OnboardingCompleteView.swift    # "Welcome to Tempo" with drill-sergeant intro
│   │
│   └── Shared/
│       ├── Components/
│       │   ├── ScoreRingView.swift          # Reusable animated progress ring
│       │   ├── RecoveryZoneBadge.swift      # Green/Yellow/Red zone badge
│       │   ├── CountdownTimerView.swift     # Reusable countdown timer
│       │   ├── LoadingStateView.swift       # Skeleton/shimmer loading state
│       │   ├── ErrorStateView.swift         # Error with retry button
│       │   ├── EmptyStateView.swift         # "No data yet" placeholder
│       │   ├── OfflineBannerView.swift      # Yellow "offline" banner
│       │   ├── StaleDataIndicator.swift     # Amber dot for stale data
│       │   └── DrillSergeantBubble.swift    # Motivational/roast text bubble
│       │
│       ├── Modifiers/
│       │   ├── TempoCardModifier.swift      # Standard card style (shadow, radius, bg)
│       │   ├── ShimmerModifier.swift        # Loading shimmer effect
│       │   └── HapticModifier.swift         # Tap-to-haptic convenience
│       │
│       └── Styles/
│           ├── TempoButtonStyle.swift       # Primary/secondary/destructive button styles
│           └── TempoToggleStyle.swift       # Custom toggle with drill-sergeant red
│
├── ViewModels/
│   ├── DashboardViewModel.swift            # Dashboard data aggregation, refresh
│   ├── TrainingViewModel.swift             # Active workout state, set logging
│   ├── AccountabilityViewModel.swift       # Non-negotiable progress, timer state
│   ├── RecoveryViewModel.swift             # Recovery data, prescription display
│   ├── ArenaViewModel.swift                # XP, leaderboard, challenges
│   └── OnboardingViewModel.swift           # Onboarding flow state, step tracking
│
├── Utilities/
│   ├── Extensions/
│   │   ├── Date+Tempo.swift                # startOfDay, endOfDay, isToday, relative formatting
│   │   ├── Color+Tempo.swift               # Design system color tokens as static properties
│   │   ├── Font+Tempo.swift                # Design system typography tokens
│   │   ├── View+Tempo.swift                # Common view modifiers (tempoCard, tempoShadow)
│   │   ├── Double+Formatting.swift         # Weight formatting, percentage formatting
│   │   └── Logger+Tempo.swift              # Categorized os.Logger instances
│   │
│   ├── Helpers/
│   │   ├── HapticManager.swift             # UINotificationFeedbackGenerator + UIImpactFeedbackGenerator patterns
│   │   ├── NetworkMonitor.swift            # NWPathMonitor wrapper for connectivity state
│   │   ├── DateFormatters.swift            # Shared, cached DateFormatter instances
│   │   └── WeightConverter.swift           # kg/lbs conversion with rounding rules
│   │
│   └── Constants/
│       ├── AppConstants.swift              # API URLs, timeout values, animation durations
│       ├── HealthKitConstants.swift         # HKObjectType sets, bundle IDs for BG tasks
│       └── DesignTokens.swift              # Spacing, radius, shadow values from design system
│
├── Resources/
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset/            # 1024x1024 app icon
│   │   ├── AccentColor.colorset/          # Signal Red (#E63946 / #FF4D5A)
│   │   ├── Colors/                         # All design system color sets
│   │   │   ├── tempo-bg-primary.colorset/
│   │   │   ├── tempo-bg-card.colorset/
│   │   │   ├── tempo-accent.colorset/
│   │   │   ├── tempo-green.colorset/
│   │   │   ├── tempo-yellow.colorset/
│   │   │   ├── tempo-red.colorset/
│   │   │   ├── tempo-blue.colorset/
│   │   │   ├── tempo-orange.colorset/
│   │   │   ├── tempo-purple.colorset/
│   │   │   └── ... (all tokens from DESIGN_SYSTEM.md)
│   │   └── Images/
│   │       ├── whoop-logo.imageset/       # Whoop brand mark for connection screen
│   │       ├── nutritrack-logo.imageset/  # NutriTrack logo
│   │       ├── onboarding-hero.imageset/  # Onboarding hero illustration
│   │       └── empty-state-*.imageset/    # Empty state illustrations
│   │
│   ├── Sounds/
│   │   ├── timer-tick.wav                  # Focus timer tick
│   │   ├── timer-complete.wav              # Timer session complete
│   │   ├── workout-complete.wav            # Workout finished
│   │   ├── pr-achieved.wav                 # Personal record celebration
│   │   ├── xp-gain.wav                     # XP float sound
│   │   ├── level-up.wav                    # Level up fanfare
│   │   ├── streak-fire.wav                 # Streak continuation
│   │   └── unlock.wav                      # Leisure unlock sound
│   │
│   ├── Exercises.json                      # 150+ exercise library with metadata
│   ├── Achievements.json                   # 108 achievement definitions
│   ├── DrillSergeantCopy.json              # Motivational/roast text bank per context
│   ├── Localizable.strings                 # English strings (localization-ready)
│   └── Localizable.stringsdict             # Pluralization rules
│
├── Preview Content/
│   ├── PreviewData.swift                   # Factory methods for mock SwiftData models
│   └── Preview Assets.xcassets/            # Preview-only images
│
├── TempoTests/
│   ├── Engines/
│   │   ├── ScoringEngineTests.swift
│   │   ├── TrainingEngineTests.swift
│   │   ├── RecoveryEngineTests.swift
│   │   ├── AccountabilityEngineTests.swift
│   │   └── XPEngineTests.swift
│   ├── Services/
│   │   ├── APIClientTests.swift
│   │   ├── HealthKitServiceTests.swift
│   │   └── SyncCoordinatorTests.swift
│   ├── Models/
│   │   ├── UserProfileTests.swift
│   │   ├── WorkoutPlanTests.swift
│   │   └── StreakTests.swift
│   ├── Mocks/
│   │   ├── MockAPIClient.swift
│   │   ├── MockHealthStore.swift
│   │   └── MockModelContainer.swift
│   └── Helpers/
│       └── XCTestCase+SwiftData.swift      # Test helpers for in-memory ModelContainer
│
├── TempoUITests/
│   ├── OnboardingUITests.swift
│   ├── DashboardUITests.swift
│   ├── TrainingUITests.swift
│   ├── AccountabilityUITests.swift
│   └── ArenaUITests.swift
│
└── TempoSnapshotTests/
    ├── DashboardSnapshotTests.swift
    └── ComponentSnapshotTests.swift
```

### Folder Purpose Guide

| Folder | Purpose |
|--------|---------|
| `Configuration/` | xcconfig files for build-time environment switching. Never hardcode API URLs or keys. |
| `App/` | Global app state that does not belong to any single module. |
| `Models/Schema/` | SwiftData versioned schema, migration plans, and the ModelContainer factory. |
| `Models/Enums/` | All `String, Codable, CaseIterable` enums used by SwiftData models. |
| `Models/SharedTypes/` | Value types shared across multiple model domains (WeightUnit, ActiveDays). |
| `Models/User/` | User identity and settings models. |
| `Models/Dashboard/` | The `DailySnapshot` model that aggregates all domain scores. |
| `Models/Training/` | Every model related to workout planning, execution, and history. |
| `Models/Accountability/` | Non-negotiables, study sessions, streaks. |
| `Models/Recovery/` | Whoop-derived recovery data and AI prescriptions. |
| `Models/Arena/` | XP events, achievements, local challenge cache. |
| `Models/Sync/` | Offline-first sync queue and sync state tracking. |
| `Models/Integrations/` | Connection state models for Whoop, NutriTrack, HealthKit. |
| `Models/DTOs/` | Codable structs for API request/response bodies. Separate from @Model classes. |
| `Services/Network/` | HTTP client, typed endpoints, JWT interceptor. |
| `Services/Auth/` | Sign in with Apple and Keychain token storage. |
| `Services/Health/` | HealthKit authorization, queries, background delivery. |
| `Services/Integrations/` | Third-party service wrappers (Whoop OAuth, NutriTrack proxy, EventKit). |
| `Services/Sync/` | Background sync orchestration and conflict resolution. |
| `Services/Notifications/` | Local notification scheduling and APNs registration. |
| `Services/Engines/` | Pure business logic engines with no UI or I/O dependencies. Testable in isolation. |
| `Views/<Module>/` | SwiftUI views organized by the 5 app modules plus Onboarding and Shared. |
| `Views/Shared/Components/` | Reusable UI components used across multiple modules. |
| `Views/Shared/Modifiers/` | Custom ViewModifiers for consistent styling. |
| `Views/Shared/Styles/` | Custom ButtonStyle, ToggleStyle implementations. |
| `ViewModels/` | @Observable classes that bridge Services/Engines to Views. One per module. |
| `Utilities/Extensions/` | Swift type extensions grouped by the type they extend. |
| `Utilities/Helpers/` | Standalone utility classes (haptics, network monitoring, formatters). |
| `Utilities/Constants/` | Compile-time constants. No magic numbers in view code. |
| `Resources/` | All non-code assets: images, sounds, JSON data files, localization. |
| `Preview Content/` | Mock data and assets used only in SwiftUI previews. |
| `TempoTests/` | Unit tests organized to mirror the `Services/` and `Models/` structure. |
| `TempoUITests/` | XCUITest flows for critical user journeys. |
| `TempoSnapshotTests/` | Pixel-perfect screenshot regression tests. |

---

## 3. Build Configurations

### 3.1 Create Configurations

In Xcode: Project > Info > Configurations. By default you have Debug and Release. Add a third:

1. Click `+` under Configurations
2. Select "Duplicate Debug Configuration"
3. Name it `Staging`

You should now have three configurations:

| Configuration | Purpose |
|---------------|---------|
| **Debug** | Local development. Localhost API. Extra logging. |
| **Staging** | Staging server. TestFlight builds. |
| **Release** | Production App Store builds. |

### 3.2 xcconfig Files

Create the configuration files in `Tempo/Configuration/`. Then assign them in Project > Info > Configurations:

- Debug > `Development.xcconfig`
- Staging > `Staging.xcconfig`
- Release > `Production.xcconfig`

#### Development.xcconfig

```
// Development.xcconfig

#include? "Secrets.xcconfig"

PRODUCT_BUNDLE_IDENTIFIER = app.tempo.Tempo.dev
PRODUCT_NAME = Tempo Dev
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-Dev

TEMPO_API_BASE_URL = http:/$()/localhost:8080
TEMPO_ENVIRONMENT = development

// Debug-only flags
SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG DEVELOPMENT
OTHER_SWIFT_FLAGS = -DDEBUG
GCC_OPTIMIZATION_LEVEL = 0
SWIFT_OPTIMIZATION_LEVEL = -Onone
ENABLE_TESTABILITY = YES

// Debug logging
GCC_PREPROCESSOR_DEFINITIONS = $(inherited) DEBUG=1
```

#### Staging.xcconfig

```
// Staging.xcconfig

#include? "Secrets.xcconfig"

PRODUCT_BUNDLE_IDENTIFIER = app.tempo.Tempo.staging
PRODUCT_NAME = Tempo Staging
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon

TEMPO_API_BASE_URL = https:/$()/api-staging.tempo.app
TEMPO_ENVIRONMENT = staging

SWIFT_ACTIVE_COMPILATION_CONDITIONS = STAGING
GCC_OPTIMIZATION_LEVEL = s
SWIFT_OPTIMIZATION_LEVEL = -O
ENABLE_TESTABILITY = YES
```

#### Production.xcconfig

```
// Production.xcconfig

#include? "Secrets.xcconfig"

PRODUCT_BUNDLE_IDENTIFIER = app.tempo.Tempo
PRODUCT_NAME = Tempo
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon

TEMPO_API_BASE_URL = https:/$()/api.tempo.app
TEMPO_ENVIRONMENT = production

SWIFT_ACTIVE_COMPILATION_CONDITIONS = PRODUCTION
GCC_OPTIMIZATION_LEVEL = s
SWIFT_OPTIMIZATION_LEVEL = -O
ENABLE_TESTABILITY = NO

// Strip debug symbols for release
STRIP_INSTALLED_PRODUCT = YES
COPY_PHASE_STRIP = YES
```

#### Secrets.xcconfig (git-ignored)

```
// Secrets.xcconfig — DO NOT COMMIT

// No client-side secrets needed for Tempo.
// Whoop client_id and client_secret live on the backend only.
// This file exists for any future client-side keys (analytics, crash reporting).

// Example:
// SENTRY_DSN = https://abc@sentry.io/123
```

### 3.3 Accessing Configuration Values in Code

Add to Info.plist:

```xml
<key>TEMPO_API_BASE_URL</key>
<string>$(TEMPO_API_BASE_URL)</string>
<key>TEMPO_ENVIRONMENT</key>
<string>$(TEMPO_ENVIRONMENT)</string>
```

Then in `AppConstants.swift`:

```swift
enum AppConstants {
    static let apiBaseURL: URL = {
        guard let urlString = Bundle.main.infoDictionary?["TEMPO_API_BASE_URL"] as? String,
              let url = URL(string: urlString) else {
            fatalError("TEMPO_API_BASE_URL not set in xcconfig")
        }
        return url
    }()

    static let environment: String = {
        Bundle.main.infoDictionary?["TEMPO_ENVIRONMENT"] as? String ?? "development"
    }()

    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
```

---

## 4. Capabilities & Entitlements

### 4.1 Enable Capabilities

In Xcode: Target > Signing & Capabilities > `+ Capability`. Add each of the following:

| Capability | Why |
|-----------|-----|
| **HealthKit** | Read recovery, sleep, steps, HR, HRV. Write workouts and nutrition. |
| **Push Notifications** | Drill-sergeant notifications, Whoop sync complete, Arena updates. |
| **Sign in with Apple** | Primary (and only) authentication method. |
| **Background Modes** | Background fetch (HealthKit sync), remote notifications (silent push), background processing (data sync). |
| **App Groups** | Share data between main app and widget extension via `group.app.tempo`. |
| **Keychain Sharing** | Share JWT tokens between main app and extensions. Access group: `$(TeamIdentifierPrefix)app.tempo.shared`. |
| **In-App Purchase** | Premium subscription tier (StoreKit 2). |

For HealthKit: **do NOT** check "Clinical Health Records." Tempo reads fitness/wellness data only.

For Background Modes, check exactly these three:
- [x] Background fetch
- [x] Remote notifications
- [x] Background processing

### 4.2 Entitlements File

This file is auto-generated by Xcode when you add capabilities, but here is the complete expected content of `Tempo.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- HealthKit -->
    <key>com.apple.developer.healthkit</key>
    <true/>
    <key>com.apple.developer.healthkit.access</key>
    <array/>
    <!-- NOTE: Do NOT add "health-records" to the array above. We only need fitness data. -->

    <!-- Push Notifications -->
    <key>aps-environment</key>
    <string>development</string>
    <!-- Xcode automatically switches this to "production" for Release/Distribution builds. -->

    <!-- Sign in with Apple -->
    <key>com.apple.developer.applesignin</key>
    <array>
        <string>Default</string>
    </array>

    <!-- Background Modes -->
    <key>com.apple.developer.background-modes</key>
    <array>
        <string>fetch</string>
        <string>remote-notification</string>
        <string>processing</string>
    </array>

    <!-- App Groups (widget data sharing) -->
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.app.tempo</string>
    </array>

    <!-- Keychain Sharing (auth tokens between app + extensions) -->
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)app.tempo.shared</string>
    </array>
</dict>
</plist>
```

---

## 5. Info.plist Configuration

Every custom key that must be present. Add these in Xcode's Info tab or directly in the Info.plist XML.

### 5.1 Privacy Usage Descriptions

```xml
<!-- HealthKit Read -->
<key>NSHealthShareUsageDescription</key>
<string>Tempo reads your health data (steps, heart rate, HRV, sleep, workouts) to calculate your daily score, adapt your training plan to your recovery, and track your progress automatically.</string>

<!-- HealthKit Write -->
<key>NSHealthUpdateUsageDescription</key>
<string>Tempo writes your completed workouts and nutrition data to HealthKit so your health record stays complete across all your apps. Only workouts you log in RepForge and meals synced from NutriTrack are written.</string>

<!-- Calendar Read (iOS 17+: full access key) -->
<key>NSCalendarsFullAccessUsageDescription</key>
<string>Tempo reads your calendar to avoid scheduling workouts during classes and football practice, and to identify study blocks for your accountability targets.</string>
```

### 5.2 Background Task Identifiers

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.tempo.healthkit-sync</string>
    <string>com.tempo.data-sync</string>
    <string>com.tempo.daily-reset</string>
</array>
```

### 5.3 URL Types (Whoop OAuth Callback)

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>CFBundleURLName</key>
        <string>app.tempo.oauth</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>tempo</string>
        </array>
    </dict>
</array>
```

This registers the `tempo://` URL scheme used by the Whoop OAuth flow. The backend redirects to `tempo://integrations/whoop/success` or `tempo://integrations/whoop/error` after the OAuth exchange.

### 5.4 Supported Interface Orientations

```xml
<key>UISupportedInterfaceOrientations</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
</array>
<key>UISupportedInterfaceOrientations~ipad</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
</array>
```

iPhone: portrait only. iPad (if ever supported): portrait + landscape.

### 5.5 Configuration Values (from xcconfig)

```xml
<key>TEMPO_API_BASE_URL</key>
<string>$(TEMPO_API_BASE_URL)</string>
<key>TEMPO_ENVIRONMENT</key>
<string>$(TEMPO_ENVIRONMENT)</string>
```

---

## 6. SPM Dependencies

Tempo is intentionally lean on third-party dependencies. Every dependency must justify its inclusion. The SwiftUI + SwiftData + HealthKit stack provides most of what is needed natively.

### 6.1 Adding Packages

In Xcode: File > Add Package Dependencies. Add each package below.

| Package | URL | Version | Why |
|---------|-----|---------|-----|
| **swift-algorithms** | `https://github.com/apple/swift-algorithms.git` | `1.2.0` (Up to Next Major) | `chunked(by:)`, `uniqued()`, and other collection utilities for data processing in engines. |
| **swift-collections** | `https://github.com/apple/swift-collections.git` | `1.1.0` (Up to Next Major) | `OrderedDictionary`, `Deque` for leaderboard and sync queue data structures. |
| **KeychainAccess** | `https://github.com/kishikawakatsumi/KeychainAccess.git` | `4.2.2` (Up to Next Major) | Type-safe Keychain wrapper for JWT token storage. Simpler than raw Security framework. |
| **swift-snapshot-testing** | `https://github.com/pointfreeco/swift-snapshot-testing.git` | `1.17.0` (Up to Next Major) | Snapshot tests for UI regression. Test target only. |

### 6.2 Target Dependency Mapping

| Package Product | Added To Target |
|----------------|-----------------|
| `Algorithms` | Tempo (main app target) |
| `Collections` | Tempo (main app target) |
| `KeychainAccess` | Tempo (main app target) |
| `SnapshotTesting` | TempoSnapshotTests (test target only) |

### 6.3 Packages Explicitly NOT Included (and Why)

| Package | Reason for exclusion |
|---------|---------------------|
| **Alamofire** | URLSession with async/await (iOS 15+) handles all networking needs. Adding Alamofire is 15,000+ lines of code for zero benefit. |
| **Kingfisher/SDWebImage** | AsyncImage (iOS 15+) handles avatar loading. For caching, a 30-line URLCache wrapper suffices. |
| **SwiftLint (SPM plugin)** | SwiftLint is installed via Homebrew and run as a build phase script. The SPM plugin slows clean builds. |
| **Charts libraries** | Swift Charts (iOS 16+) is native and sufficient. No third-party charting needed. |
| **Firebase/Crashlytics** | Not yet. Will evaluate Sentry or TelemetryDeck for crash reporting post-MVP. Firebase SDK is 50MB+. |
| **Combine** | Not needed. Tempo uses `@Observable` (Observation framework) and async/await exclusively. |
| **RxSwift** | Not needed. Same as Combine. |

---

## 7. Build Phases

### 7.1 SwiftLint Run Script

Add a new Run Script Phase (Target > Build Phases > `+` > New Run Script Phase). Drag it **above** the "Compile Sources" phase.

**Name:** `SwiftLint`

**Shell:** `/bin/zsh`

**Script:**

```bash
if command -v swiftlint >/dev/null 2>&1; then
    swiftlint lint --config "${SRCROOT}/.swiftlint.yml" --quiet
else
    echo "warning: SwiftLint not installed. Run 'brew install swiftlint' to enable linting."
fi
```

**Settings:**
- [x] Based on dependency analysis (checked -- only runs when source files change)
- Input Files: leave empty
- Output Files: leave empty

### 7.2 SwiftFormat Run Script (Optional, Recommended)

Add another Run Script Phase. Position it after SwiftLint and before Compile Sources.

**Name:** `SwiftFormat`

**Shell:** `/bin/zsh`

**Script:**

```bash
if command -v swiftformat >/dev/null 2>&1; then
    swiftformat "${SRCROOT}/Tempo" --config "${SRCROOT}/.swiftformat" --lint --quiet
else
    echo "warning: SwiftFormat not installed. Run 'brew install swiftformat' to enable formatting."
fi
```

### 7.3 Build Number Auto-Increment

Add a Run Script Phase. Position it **after** Compile Sources.

**Name:** `Increment Build Number`

**Shell:** `/bin/zsh`

**Script:**

```bash
# Only increment for Release and Staging builds
if [ "${CONFIGURATION}" = "Release" ] || [ "${CONFIGURATION}" = "Staging" ]; then
    buildNumber=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${INFOPLIST_FILE}")
    buildNumber=$(($buildNumber + 1))
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "${INFOPLIST_FILE}"
    echo "Build number incremented to $buildNumber"
fi
```

**Settings:**
- [ ] Based on dependency analysis (UNchecked -- must run every build)
- Only apply to Release and Staging configurations by using the `if` guard.

---

## 8. Schemes

### 8.1 Create Schemes

Xcode creates a default "Tempo" scheme. Duplicate it to create environment-specific schemes.

Go to Product > Scheme > Manage Schemes.

| Scheme Name | Build Configuration | Purpose |
|-------------|-------------------|---------|
| **Tempo (Dev)** | Debug | Daily development on simulator/device. Localhost API. |
| **Tempo (Staging)** | Staging | TestFlight builds. Staging API. |
| **Tempo (Release)** | Release | App Store builds. Production API. |
| **Tempo Tests** | Debug | Run all test targets. |

### 8.2 Scheme Configuration Details

#### Tempo (Dev)

- **Build:** Tempo target
- **Run:**
  - Build Configuration: Debug
  - Environment Variables:
    - `TEMPO_MOCK_DATA` = `1` (enables mock data layer for development without backend)
    - `TEMPO_LOG_LEVEL` = `debug`
  - Launch Arguments:
    - `-com.apple.CoreData.SQLDebug 1` (logs SwiftData SQL queries)
    - `-com.apple.CoreData.Logging.stderr 1`
- **Test:**
  - Build Configuration: Debug
  - Test targets: TempoTests, TempoUITests, TempoSnapshotTests

#### Tempo (Staging)

- **Build:** Tempo target
- **Run:**
  - Build Configuration: Staging
  - Environment Variables:
    - `TEMPO_LOG_LEVEL` = `info`
- **Archive:**
  - Build Configuration: Staging

#### Tempo (Release)

- **Build:** Tempo target
- **Run:**
  - Build Configuration: Release
- **Archive:**
  - Build Configuration: Release
  - Post-action: Upload dSYMs to crash reporter (when configured)

#### Tempo Tests

- **Build:** Tempo target, TempoTests, TempoUITests, TempoSnapshotTests
- **Test:**
  - Build Configuration: Debug
  - All three test targets enabled
  - Code Coverage: ON (for Tempo target)
  - Parallel Testing: ON

---

## 9. Code Signing

### 9.1 Recommendation: Automatic Signing for Development

For a solo developer or small team, use **Automatic Signing** in Xcode. This is the simplest setup and handles certificate/profile management automatically.

- Target > Signing & Capabilities > check "Automatically manage signing"
- Select your team
- Xcode creates development certificates and provisioning profiles automatically

### 9.2 Distribution Signing

For TestFlight and App Store distribution, Xcode Cloud or manual archive + upload handles this automatically when using Automatic Signing.

### 9.3 Future: Fastlane Match (When Team Grows)

When the team grows beyond 1-2 developers, switch to Fastlane Match for certificate management:

```ruby
# Matchfile
git_url("git@github.com:nicola/tempo-certificates.git")
storage_mode("git")
type("appstore") # or "development", "adhoc"
app_identifier(["app.tempo.Tempo", "app.tempo.Tempo.widget", "app.tempo.Tempo.watchkitapp"])
username("nicola@tempo.app")
team_id("XXXXXXXXXX")
```

### 9.4 Provisioning Profile Types Needed

| Profile Type | Bundle ID | Purpose |
|-------------|-----------|---------|
| iOS Development | `app.tempo.Tempo.dev` | Development builds |
| iOS Development | `app.tempo.Tempo.staging` | Staging development |
| iOS Development | `app.tempo.Tempo` | Production development |
| iOS Distribution (App Store) | `app.tempo.Tempo` | App Store submission |
| iOS Distribution (Ad Hoc) | `app.tempo.Tempo.staging` | Staging TestFlight |
| watchOS App Development | `app.tempo.Tempo.watchkitapp` | Watch app development |
| watchOS App Distribution | `app.tempo.Tempo.watchkitapp` | Watch app distribution |
| Widget Extension Development | `app.tempo.Tempo.widget` | Widget development |
| Widget Extension Distribution | `app.tempo.Tempo.widget` | Widget distribution |

---

## 10. Widget Extension

### 10.1 Create Widget Extension Target

1. File > New > Target
2. Select "Widget Extension"
3. Product Name: `TempoWidget`
4. Bundle Identifier: `app.tempo.Tempo.widget` (auto-generated)
5. **Uncheck** "Include Configuration App Intent" (we use a simple static widget for v1)
6. **Uncheck** "Include Live Activity" (Live Activities are added in Phase 2)

### 10.2 Widget Target Configuration

| Setting | Value |
|---------|-------|
| Deployment Target | iOS 17.4 |
| App Group | `group.app.tempo` (must match main app) |
| Frameworks | SwiftUI, WidgetKit |

### 10.3 Widget Target Entitlements

Create `TempoWidgetExtension.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.app.tempo</string>
    </array>
</dict>
</plist>
```

### 10.4 Data Sharing via App Groups

The main app writes data to a shared UserDefaults suite. The widget reads from it.

```swift
// In main app — write after each score recalculation
let sharedDefaults = UserDefaults(suiteName: "group.app.tempo")
sharedDefaults?.set(dailyScore, forKey: "widget.dailyScore")
sharedDefaults?.set(recoveryZone.rawValue, forKey: "widget.recoveryZone")
sharedDefaults?.set(recoveryScore, forKey: "widget.recoveryScore")
sharedDefaults?.set(nextTaskName, forKey: "widget.nextTaskName")
sharedDefaults?.set(nnProgress, forKey: "widget.nnProgress") // "3/5"

// In widget — read
let sharedDefaults = UserDefaults(suiteName: "group.app.tempo")
let score = sharedDefaults?.integer(forKey: "widget.dailyScore") ?? 0
```

### 10.5 Widget File Structure

```
TempoWidget/
├── TempoWidgetBundle.swift          # @main WidgetBundle
├── TempoWidget.swift                # Main widget with TimelineProvider
├── TempoWidgetViews.swift           # Small, Medium, Large widget views
├── TempoWidgetEntryView.swift       # Entry view switching on widget family
├── TempoLiveActivity.swift          # Live Activity for active workout/timer (Phase 2)
└── Assets.xcassets/                 # Widget-specific assets
```

### 10.6 Timeline Provider

The widget refreshes when:
1. The main app calls `WidgetCenter.shared.reloadTimelines(ofKind: "TempoWidget")` after any score change
2. Timeline policy refreshes every 15 minutes as a fallback

---

## 11. Watch App Target

### 11.1 Create Watch App Target

1. File > New > Target
2. Select "watchOS" tab > "App"
3. Product Name: `TempoWatch`
4. Bundle Identifier: `app.tempo.Tempo.watchkitapp`
5. Interface: SwiftUI
6. Language: Swift
7. Watch Connectivity: check "Include Notification Scene"

### 11.2 Watch Target Configuration

| Setting | Value |
|---------|-------|
| watchOS Deployment Target | **10.0** |
| Supported: `WKApplication` | Yes |
| Companion: `WKCompanionAppBundleIdentifier` | `app.tempo.Tempo` |

### 11.3 Watch Capabilities & Entitlements

Create `TempoWatch.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- HealthKit (direct reads on Watch for HR, steps during workout) -->
    <key>com.apple.developer.healthkit</key>
    <true/>
    <key>com.apple.developer.healthkit.access</key>
    <array/>

    <!-- App Groups (shared data with iPhone app) -->
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.app.tempo</string>
    </array>
</dict>
</plist>
```

### 11.4 Watch File Structure

As specified in APPLE_WATCH_APP.md:

```
TempoWatch/
├── TempoWatchApp.swift                 # Watch app entry point
├── Models/
│   ├── WatchSnapshot.swift             # Lightweight daily data received from iPhone
│   ├── WatchWorkoutState.swift         # Current workout + set tracking
│   ├── WatchTimerState.swift           # Focus timer state
│   └── WatchQuickAction.swift          # Actions to send back to iPhone
├── Services/
│   ├── WatchConnectivityService.swift  # WCSession management
│   ├── WatchHapticService.swift        # WKInterfaceDevice haptic patterns
│   └── WatchHealthKitService.swift     # Direct HealthKit reads (HR, steps during workout)
├── Views/
│   ├── GlanceHomeView.swift            # Main watch screen (daily score, recovery, next task)
│   ├── WorkoutView.swift               # Active workout set logging
│   ├── FocusTimerView.swift            # Pomodoro timer
│   ├── QuickLogView.swift              # Quick non-negotiable check-off
│   ├── RecoveryView.swift              # Recovery summary
│   └── ArenaGlanceView.swift           # XP + leaderboard position
├── Complications/
│   ├── TempoComplicationProvider.swift # TimelineProvider for all complication families
│   └── ComplicationViews.swift         # Circular, Rectangular, Inline, Corner, ExtraLarge views
├── Notifications/
│   └── NotificationController.swift    # Actionable watch notifications
└── Resources/
    └── Assets.xcassets/                # Watch-specific assets (complication placeholder images)
```

### 11.5 Watch Connectivity Setup (iPhone Side)

In the main iPhone app, create `WatchConnectivityDelegate.swift` in `Services/Integrations/`:

```swift
import WatchConnectivity

final class PhoneWatchConnectivityService: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneWatchConnectivityService()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func pushSnapshot(_ snapshot: WatchSnapshot) {
        guard WCSession.default.isReachable else {
            // Use applicationContext for background delivery
            try? WCSession.default.updateApplicationContext(snapshot.toDictionary())
            return
        }
        // Use sendMessage for immediate delivery
        WCSession.default.sendMessage(snapshot.toDictionary(), replyHandler: nil)
    }

    // WCSessionDelegate methods...
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
```

### 11.6 Shared Code Strategy

The Watch app does NOT share a framework target with the iPhone app. This is intentional:

- The Watch receives a lightweight `WatchSnapshot` (a `Codable` struct) via Watch Connectivity
- The Watch has its own simple models (no SwiftData, no @Model -- pure structs)
- The iPhone is the source of truth; the Watch is a display + input terminal
- Shared enums (`RecoveryZone`, `WorkoutType`) are duplicated in the Watch target as simple enums (they are small and rarely change)

If enum duplication becomes a maintenance burden (unlikely before 10+ enums), extract a `TempoShared` Swift Package (local package, not SPM remote) containing only the shared types.

---

## 12. Coding Standards

### 12.1 SwiftLint Configuration

Create `.swiftlint.yml` at the project root:

```yaml
# .swiftlint.yml — Tempo iOS

# Only lint the main source directories
included:
  - Tempo
  - TempoWidget
  - TempoWatch

excluded:
  - Tempo/Preview Content
  - TempoTests
  - TempoUITests
  - TempoSnapshotTests
  - .build
  - DerivedData

# Rules
disabled_rules:
  - trailing_comma               # We allow trailing commas in multi-line collections
  - opening_brace                # SwiftFormat handles brace placement
  - todo                         # TODOs are fine during development

opt_in_rules:
  - array_init
  - closure_end_indentation
  - closure_spacing
  - collection_alignment
  - contains_over_filter_count
  - contains_over_first_not_nil
  - contains_over_range_nil_comparison
  - convenience_type
  - discouraged_optional_boolean
  - empty_collection_literal
  - empty_count
  - empty_string
  - enum_case_associated_values_count
  - explicit_init
  - fallthrough
  - fatal_error_message
  - file_name_no_space
  - first_where
  - flatmap_over_map_reduce
  - force_unwrapping
  - identical_operands
  - implicit_return
  - joined_default_parameter
  - last_where
  - legacy_multiple
  - legacy_random
  - literal_expression_end_indentation
  - lower_acl_than_parent
  - modifier_order
  - multiline_arguments
  - multiline_parameters
  - number_separator
  - operator_usage_whitespace
  - overridden_super_call
  - pattern_matching_keywords
  - prefer_self_in_static_references
  - prefer_self_type_over_type_of_self
  - prefer_zero_over_explicit_init
  - private_action
  - private_outlet
  - prohibited_super_call
  - reduce_into
  - redundant_nil_coalescing
  - redundant_type_annotation
  - sorted_first_last
  - strong_iboutlet
  - toggle_bool
  - unavailable_function
  - unneeded_parentheses_in_closure_argument
  - unowned_variable_capture
  - vertical_parameter_alignment_on_call
  - yoda_condition

# Rule configuration
line_length:
  warning: 140
  error: 200
  ignores_comments: true
  ignores_urls: true
  ignores_interpolated_strings: true

type_body_length:
  warning: 300
  error: 500

file_length:
  warning: 500
  error: 800
  ignore_comment_only_lines: true

function_body_length:
  warning: 50
  error: 80

function_parameter_count:
  warning: 6
  error: 8

type_name:
  min_length: 3
  max_length: 50

identifier_name:
  min_length:
    warning: 2
    error: 1
  max_length:
    warning: 50
    error: 60
  excluded:
    - id
    - x
    - y
    - w
    - h
    - i
    - j
    - db
    - hr
    - xp

nesting:
  type_level: 2
  function_level: 3

number_separator:
  minimum_length: 5

modifier_order:
  preferred_modifier_order:
    - acl
    - setterACL
    - override
    - dynamic
    - mutating
    - nonmutating
    - lazy
    - final
    - required
    - convenience
    - typeMethods
    - owned

force_unwrapping:
  severity: warning  # warning not error — sometimes needed for IB outlets or guaranteed casts

reporter: xcode
```

### 12.2 SwiftFormat Configuration

Create `.swiftformat` at the project root:

```
# .swiftformat — Tempo iOS

# File options
--swiftversion 6.0
--exclude DerivedData,.build,Preview Content

# Format options
--allman false
--binarygrouping 4,8
--closingparen balanced
--commas always
--decimalgrouping 3,6
--elseposition same-line
--guardelse next-line
--header "//\n// {file}\n// Tempo\n//\n// Created by Tempo on {created}.\n//\n"
--ifdef indent
--importgrouping alpha
--indent 4
--indentcase false
--linebreaks lf
--maxwidth 140
--octalgrouping 4,8
--operatorfunc spaced
--patternlet hoist
--ranges spaced
--self remove
--semicolons inline
--stripunusedargs closure-only
--tabwidth 4
--trimwhitespace always
--typeattributes prev-line
--varattributes prev-line
--wraparguments before-first
--wrapparameters before-first
--wrapcollections before-first
--wrapconditions preserve
--wrapreturntype preserve

# Rules
--enable isEmpty
--enable blankLineAfterImports
--enable blockComments
--enable docComments
--enable markTypes
--enable organizeDeclarations
--enable sortImports
--enable wrapConditionalBodies
--enable wrapEnumCases
--enable wrapSwitchCases

--disable acronyms
--disable sortedSwitchCases
```

### 12.3 File Header Template

Every Swift file in the project uses this header (auto-applied by SwiftFormat's `--header` rule):

```swift
//
// FileName.swift
// Tempo
//
// Created by Tempo on 2026-03-24.
//
```

### 12.4 Import Ordering Rules

Imports are sorted alphabetically by SwiftFormat. Group order:

```swift
import Foundation          // 1. Foundation/standard library
import SwiftData           // 2. Apple frameworks (alphabetical)
import SwiftUI
import HealthKit

import Algorithms          // 3. Third-party packages (alphabetical)
import Collections
import KeychainAccess
```

### 12.5 Access Control Conventions

| Scope | When to use |
|-------|-------------|
| `public` | Never within the app targets. Only in a shared framework if created. |
| `package` | Never. No multi-module package structure in v1. |
| `internal` | Default. Omit the keyword (Swift default is `internal`). |
| `fileprivate` | Properties/methods used only within the file but across types in the same file. |
| `private` | Properties/methods used only within the enclosing type. **Default choice for stored properties.** |
| `private(set)` | Properties readable externally but only writable within the type. Use for `@Observable` service state. |

### 12.6 Naming Conventions Specific to Tempo

| Category | Convention | Example |
|----------|-----------|---------|
| SwiftData models | PascalCase noun, no suffix | `WorkoutPlan`, `DailySnapshot` |
| DTOs | Model name + `DTO` suffix | `UserProfileDTO`, `WorkoutDTO` |
| Services | PascalCase + `Service` suffix | `HealthKitService`, `WhoopService` |
| Engines | PascalCase + `Engine` suffix | `ScoringEngine`, `TrainingEngine` |
| ViewModels | PascalCase + `ViewModel` suffix | `DashboardViewModel` |
| Views | PascalCase + `View` suffix | `DashboardView`, `ScoreRingView` |
| View Modifiers | PascalCase + `Modifier` suffix | `TempoCardModifier` |
| Enums | PascalCase, cases in camelCase | `RecoveryZone.green` |
| Constants | `static let` in caseless enum | `AppConstants.apiBaseURL` |
| Protocols | PascalCase, adjective or `-able`/`-ible` | `Syncable`, `ScoreCalculating` |
| Test files | Mirror source file + `Tests` suffix | `ScoringEngineTests` |

---

## 13. First Build Checklist

Follow these steps exactly. Estimated time: 20-25 minutes.

### Step 1: Clone the Repository (1 min)

```bash
git clone git@github.com:nicola/tempo-ios.git
cd tempo-ios
```

### Step 2: Install Tooling (3 min)

```bash
# Install SwiftLint and SwiftFormat
brew install swiftlint swiftformat
```

Verify:
```bash
swiftlint version    # Should print 0.56.0 or later
swiftformat --version # Should print 0.54.0 or later
```

### Step 3: Open the Project (1 min)

```bash
open Tempo.xcodeproj
```

If the project uses an `.xcworkspace` (it will if a Watch app target is added), open that instead:
```bash
open Tempo.xcworkspace
```

### Step 4: Configure Signing (2 min)

1. Select the **Tempo** target in the project navigator
2. Go to Signing & Capabilities
3. Select your Apple Developer Team from the dropdown
4. Xcode will auto-generate a development provisioning profile
5. Repeat for **TempoWidget** and **TempoWatch** targets

If you see a signing error about bundle identifier conflicts, change the bundle ID suffix for development (e.g., `app.tempo.Tempo.dev.yourname`).

### Step 5: Create Secrets.xcconfig (1 min)

```bash
# From project root
cp Tempo/Configuration/Secrets.xcconfig.template Tempo/Configuration/Secrets.xcconfig
```

If the template does not exist, create an empty file:

```bash
touch Tempo/Configuration/Secrets.xcconfig
echo "// Secrets.xcconfig -- DO NOT COMMIT" > Tempo/Configuration/Secrets.xcconfig
```

Verify `.gitignore` contains:
```
Secrets.xcconfig
```

### Step 6: Resolve SPM Packages (2 min)

Xcode resolves packages automatically on first open. If it does not:

1. File > Packages > Resolve Package Versions
2. Wait for all packages to download (progress bar in Xcode status area)

If resolution fails behind a corporate proxy, check Xcode > Settings > Accounts > Source Control for Git proxy settings.

### Step 7: Select Scheme and Destination (30 sec)

1. Select **Tempo (Dev)** scheme from the scheme selector (top-left toolbar)
2. Select **iPhone 16 Pro** simulator (or any iOS 17+ simulator)

### Step 8: Build (2 min)

Press `Cmd + B` to build. First build takes 1-3 minutes due to SPM compilation.

**Expected:** Build succeeds with zero errors. You may see SwiftLint warnings -- these are informational.

**If build fails:**
- "Missing module" errors: SPM did not resolve. Try File > Packages > Reset Package Caches, then resolve again.
- Signing errors: Ensure you selected a valid team in Step 4.
- Swift version errors: Ensure Swift Language Version is set to 6 in Build Settings.

### Step 9: Run on Simulator (1 min)

Press `Cmd + R`. The simulator launches.

**Expected behavior on first run:**

1. The app opens to the **Onboarding** flow (Sign in with Apple screen)
2. If mock data is enabled (`TEMPO_MOCK_DATA=1` in scheme), the app may skip onboarding and show the Dashboard with sample data

### Step 10: Verify HealthKit Permission Prompt (2 min)

If you proceed through onboarding:

1. Sign in with Apple (use "Sign in with Apple" button -- simulator uses a test Apple ID)
2. The app presents the HealthKit authorization sheet listing all requested data types
3. Toggle some on, tap "Allow"
4. The app continues to the next onboarding step

**On simulator:** HealthKit data is available but empty. The Health app on the simulator can be used to add sample data (open Health app > Browse > add data points manually).

### Step 11: Verify Dashboard Loads (2 min)

After completing onboarding (or if mock data is enabled):

1. The Dashboard (LifeOS) tab displays the 4-quadrant view
2. The daily score ring shows (0 or mock value)
3. The 4 quadrants (Body, Fuel, Mind, Move) render with their accent colors
4. Tapping a quadrant expands it
5. Tab bar shows all 5 tabs: Dashboard, Train, Lockdown, Recover, Arena

### Step 12: Run Tests (3 min)

```bash
# From terminal (or Cmd+U in Xcode)
xcodebuild test \
  -scheme "Tempo Tests" \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  -resultBundlePath TestResults.xcresult
```

Or simply press `Cmd + U` in Xcode with the "Tempo Tests" scheme selected.

**Expected:** All tests pass. Code coverage report is generated.

### Step 13: Verify Widget (2 min)

1. Build and run on simulator
2. Long-press the home screen
3. Tap `+` (top-left)
4. Search for "Tempo"
5. Add a small widget
6. The widget should display the daily score ring (0 or mock value)

---

## Quick Reference Card

| Item | Value |
|------|-------|
| Bundle ID (prod) | `app.tempo.Tempo` |
| Bundle ID (staging) | `app.tempo.Tempo.staging` |
| Bundle ID (dev) | `app.tempo.Tempo.dev` |
| Bundle ID (widget) | `app.tempo.Tempo.widget` |
| Bundle ID (watch) | `app.tempo.Tempo.watchkitapp` |
| App Group | `group.app.tempo` |
| Keychain Group | `$(AppIdentifierPrefix)app.tempo.shared` |
| URL Scheme | `tempo://` |
| iOS Deployment Target | 17.0 |
| watchOS Deployment Target | 10.0 |
| Swift Version | 6 |
| Xcode Version | 16.0+ |
| BG Task: HealthKit sync | `com.tempo.healthkit-sync` |
| BG Task: Data sync | `com.tempo.data-sync` |
| BG Task: Daily reset | `com.tempo.daily-reset` |
| API (prod) | `https://api.tempo.app` |
| API (staging) | `https://api-staging.tempo.app` |
| API (dev) | `http://localhost:8080` |
