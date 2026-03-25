# Tempo — Architecture Plan

> Your Life Operating System. Native iOS + Swift Backend.

## Overview

Tempo is a native iOS app that unifies fitness, nutrition, recovery, academics, and accountability into one system. It integrates with Whoop, Apple HealthKit, NutriTrack, and Apple Calendar to give users a complete picture of their day — and a drill-sergeant to keep them on track.

**Target:** Public release on the App Store.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    TEMPO iOS APP                         │
│                  (SwiftUI + SwiftData)                   │
│                                                          │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐             │
│  │ Dashboard  │ │ Training  │ │ Recovery  │             │
│  │  (LifeOS)  │ │(RepForge) │ │(RecoverIQ)│             │
│  └───────────┘ └───────────┘ └───────────┘             │
│  ┌───────────┐ ┌───────────┐                            │
│  │Accountab. │ │   Arena   │                            │
│  │(Lockdown) │ │(ClutchTime)│                           │
│  └───────────┘ └───────────┘                            │
│                                                          │
│  ┌──────────────────────────────────────────────┐       │
│  │              SERVICE LAYER                    │       │
│  │  HealthKitService │ WhoopService │ NutriSync │       │
│  │  CalendarService  │ NotifService │ AIEngine  │       │
│  └──────────────────────────────────────────────┘       │
│                                                          │
│  ┌──────────────────────────────────────────────┐       │
│  │          LOCAL PERSISTENCE (SwiftData)         │       │
│  │  Workouts │ DailyScores │ Goals │ StudySessions│      │
│  └──────────────────────────────────────────────┘       │
└─────────────────┬───────────────────────────────────────┘
                  │ HTTPS
                  ▼
┌─────────────────────────────────────────────────────────┐
│                 TEMPO BACKEND (Vapor)                     │
│                                                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐ │
│  │  Auth    │ │  Whoop   │ │  Arena   │ │ NutriTrack │ │
│  │ (JWT +  │ │  Proxy   │ │Leaderboard│ │   Proxy   │ │
│  │  Apple) │ │ (OAuth)  │ │  + XP    │ │           │ │
│  └──────────┘ └──────────┘ └──────────┘ └───────────┘ │
│                                                          │
│  ┌──────────────────────────────────────────────┐       │
│  │           PostgreSQL Database                  │       │
│  │  Users │ Friendships │ XP/Scores │ WhoopTokens│       │
│  └──────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────┘
                  │
    ┌─────────────┼──────────────┐
    ▼             ▼              ▼
┌────────┐  ┌─────────┐  ┌──────────┐
│ Whoop  │  │NutriTrack│  │  Apple   │
│  API   │  │  (Flask) │  │ Calendar │
│ (v2)   │  │  Server  │  │  (local) │
└────────┘  └─────────┘  └──────────┘
```

---

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| **iOS App** | SwiftUI + Swift 6 | Native performance, HealthKit access, real push notifications |
| **Local DB** | SwiftData | Apple's modern persistence, automatic CloudKit sync possible |
| **Backend** | Vapor (Swift) | Full-stack Swift, type safety end-to-end, performant |
| **Database** | PostgreSQL | Relational, proven, great for leaderboards/social features |
| **Auth** | Sign in with Apple + JWT | Apple requirement for App Store, clean UX |
| **Push** | APNs (Apple Push Notification service) | Native iOS notifications, required for drill-sergeant alerts |
| **AI** | Claude API (Anthropic) | Pattern detection, coaching insights, weekly reports |

---

## Module Architecture

### Module 1: Dashboard (LifeOS)

The home screen. Shows everything at a glance.

**Data Sources:**
- Whoop API → Recovery %, HRV, RHR, Sleep score, Strain
- HealthKit → Steps, Active Energy, Heart Rate, Workouts
- NutriTrack API → Meals logged, Macros (cal/protein/carbs/fat), Meal status
- Local → Study sessions, Non-negotiable progress, Daily score

**Screens:**
- `DashboardView` — 4-quadrant layout: Body / Fuel / Mind / Move
- `WeeklyReportView` — AI-generated weekly insights with trend charts
- `PatternView` — Correlation analysis (sleep vs meals vs study)

**Key Data Model:**
```swift
@Model
class DailySnapshot {
    var date: Date

    // Body (from Whoop + HealthKit)
    var recoveryScore: Double?      // Whoop 0-100
    var hrvRmssd: Double?           // Whoop HRV in ms
    var restingHR: Double?          // Whoop RHR
    var sleepHours: Double?         // Whoop sleep duration
    var sleepScore: Double?         // Whoop sleep performance %
    var strain: Double?             // Whoop 0-21

    // Fuel (from NutriTrack)
    var caloriesConsumed: Int?
    var calorieTarget: Int?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var mealsLogged: Int
    var mealsPlanned: Int

    // Mind (local)
    var studyMinutes: Int
    var studyTarget: Int
    var examCountdown: Int?         // days to next exam

    // Move (HealthKit + local)
    var steps: Int?
    var activeCalories: Double?
    var workoutCompleted: Bool
    var workoutType: String?        // "Push", "Pull", "Legs", "Football", "Run"

    // Score
    var dailyScore: Int             // 0-100 composite
    var nonNegotiablesCompleted: Int
    var nonNegotiablesTotal: Int
}
```

### Module 2: Training (RepForge)

AI-powered training programming that adapts to recovery and schedule.

**Core Logic:**
- Knows your football schedule (fixed days)
- Never programs heavy legs before football
- Adjusts volume/intensity based on Whoop recovery
- Tracks progressive overload across weeks
- Supports: PPL splits, running plans, football-specific conditioning

**Data Sources:**
- Whoop API → Recovery score determines training intensity
- HealthKit → Reads auto-detected workouts, heart rate zones
- Local → Exercise library, workout history, progression data

**Screens:**
- `TodayWorkoutView` — Today's prescribed workout with sets/reps/weight
- `WorkoutLogView` — Quick-tap logging during workout
- `ProgressView` — Charts for each exercise (weight over time)
- `WeekPlanView` — 7-day training overview
- `ExerciseLibraryView` — Searchable exercise database

**Key Data Models:**
```swift
@Model
class WorkoutPlan {
    var date: Date
    var type: WorkoutType           // push, pull, legs, upper, football, run, rest
    var recoveryAdjustment: Double  // 1.0 = normal, 0.8 = reduced, 1.1 = push
    var status: WorkoutStatus       // planned, inProgress, completed, skipped
    var exercises: [PlannedExercise]
    var notes: String?
}

enum WorkoutType: String, Codable {
    case push, pull, legs, upper, lower, fullBody
    case football, run, sprint, conditioning
    case mobility, rest
}

@Model
class PlannedExercise {
    var exercise: Exercise
    var sets: [PlannedSet]
    var order: Int
    var supersetGroup: Int?
}

@Model
class PlannedSet {
    var targetReps: Int
    var targetWeight: Double?       // kg
    var actualReps: Int?
    var actualWeight: Double?
    var rpe: Int?                   // Rate of Perceived Exertion 1-10
    var completed: Bool
}

@Model
class Exercise {
    var name: String
    var muscleGroup: MuscleGroup
    var equipment: Equipment
    var isCompound: Bool
    var personalBest: Double?       // 1RM estimate
}
```

**Recovery-Based Adjustment Algorithm:**
```
Recovery ≥ 80% (GREEN)  → Full volume, push for PRs
Recovery 50-79% (YELLOW) → Reduce volume 20%, maintain intensity
Recovery < 50% (RED)     → Reduce both 30-40%, or swap to mobility
Football tomorrow        → No heavy legs/deadlifts, upper focus
Football today           → Rest or light upper mobility
```

### Module 3: Accountability (Lockdown)

The drill sergeant. Daily non-negotiables that gate leisure time.

**Core Logic:**
- User sets daily non-negotiables (e.g., "Study 2h", "Eat 3 meals", "Train")
- Progress tracked via integrations (Whoop confirms training, NutriTrack confirms meals)
- Study time tracked with built-in focus timer
- PS5/leisure is "locked" until non-negotiables are done
- Escalating notification severity as evening approaches

**Screens:**
- `LockdownView` — Today's non-negotiables with progress bars
- `FocusTimerView` — Pomodoro-style study timer
- `StreakView` — Calendar heatmap of completed days
- `SettingsView` — Configure non-negotiables, notification intensity

**Notification Escalation System:**
```
Time-based escalation for incomplete non-negotiables:

2:00 PM  — Gentle:    "3 tasks left today. You've got this."
5:00 PM  — Firm:      "⚠️ 2 tasks incomplete. Evening approaching."
6:30 PM  — Urgent:    "🚨 Study not done. 90 min before dinner. DO IT NOW."
7:00 PM  — Aggressive: "You're about to waste another evening.
                         1h37m of study missing. No PS5 until it's done."
8:00 PM  — Final:     "Another day lost. Tomorrow's score starts at -10.
                         Or do 45 min right now and save it."

After completion: "✅ All clear. You earned your evening. Enjoy PS5."
```

**Key Data Models:**
```swift
@Model
class NonNegotiable {
    var name: String
    var type: NonNegotiableType     // study, train, meals, custom
    var targetValue: Double         // minutes for study, count for meals
    var currentValue: Double
    var isAutoTracked: Bool         // true if tracked via integration
    var integrationSource: String?  // "whoop", "nutritrack", "healthkit"
    var isCompleted: Bool
    var completedAt: Date?
}

enum NonNegotiableType: String, Codable {
    case study      // tracked via focus timer
    case train      // auto-detected via Whoop/HealthKit
    case meals      // auto-tracked via NutriTrack
    case custom     // manual check-off
}

@Model
class DailyAccountability {
    var date: Date
    var nonNegotiables: [NonNegotiable]
    var leisureUnlocked: Bool
    var leisureUnlockedAt: Date?
    var totalStudyMinutes: Int
    var score: Int                  // daily accountability score
}
```

### Module 4: Recovery (RecoverIQ)

Whoop-powered daily prescriptions.

**Core Logic:**
- Reads Whoop recovery, sleep, strain
- Generates actionable daily prescription
- Suggests meal timing and macro adjustments based on training load
- Recommends bedtime based on sleep debt
- Tracks recovery trends and identifies patterns

**Data Sources:**
- Whoop API → Recovery, Sleep (stages, debt, efficiency), Strain, HRV trend
- NutriTrack → Current day's nutrition plan
- HealthKit → Additional biometrics
- Local → Historical recovery data for trend analysis

**Screens:**
- `RecoveryTodayView` — Today's recovery score + prescription
- `SleepDetailView` — Sleep stages, debt, consistency
- `RecoveryTrendsView` — 7/30/90 day recovery trends
- `PrescriptionView` — Actionable recommendations

**Prescription Engine:**
```
INPUT: recovery_score, sleep_hours, sleep_debt, strain_yesterday, hrv_trend

OUTPUT:
- training_recommendation: "Full send" | "Moderate" | "Easy/mobility" | "Rest"
- meal_timing: "Eat protein within 1h of training" | "Extra carbs today"
- bedtime: calculated from sleep_debt + next_day_schedule
- hydration_target: adjusted for strain
- caffeine_cutoff: time based on target bedtime
- specific_warnings: ["HRV dropping 3 days straight", "Sleep debt > 4h"]
```

**Key Data Model:**
```swift
@Model
class DailyPrescription {
    var date: Date
    var recoveryScore: Double
    var recoveryZone: RecoveryZone  // green, yellow, red

    var trainingRec: String
    var mealTimingRec: String
    var bedtimeRec: Date
    var hydrationTargetMl: Int
    var caffeineCutoff: Date
    var warnings: [String]

    var wasFollowed: Bool?          // did user follow the prescription?
}

enum RecoveryZone: String, Codable {
    case green  // ≥ 67%
    case yellow // 34-66%
    case red    // < 34%
}
```

### Module 5: Arena (ClutchTime)

Gamified accountability with social competition.

**Core Logic:**
- XP earned for completing non-negotiables, workouts, meal compliance
- XP lost for skipping tasks
- Weekly leaderboards with friends
- Achievements/badges for streaks and milestones
- Challenge system (e.g., "Most study hours this week")

**Data Sources:**
- All other modules → XP calculated from daily scores
- Backend → Leaderboards, friend data, challenges

**Screens:**
- `ArenaView` — Your XP, level, weekly leaderboard
- `FriendsView` — Add friends, view their stats
- `ChallengesView` — Active and available challenges
- `AchievementsView` — Badge collection

**XP System:**
```
DAILY XP SOURCES:
+50  Complete a workout
+40  All meals logged on time
+40  Study target hit
+20  All non-negotiables done (bonus)
+10  Sleep score ≥ 85%
+10  Steps ≥ 8,000
+5   Each meal logged

PENALTIES:
-20  Skip workout without rest day reason
-15  Miss study target
-10  Miss a meal

STREAKS:
+25/day  7-day non-negotiable streak
+50/day  30-day streak
+100     Monthly challenge winner

LEVELS:
Level = floor(sqrt(total_xp / 100))
```

**Key Data Models (Backend — PostgreSQL):**
```sql
-- Users table
CREATE TABLE users (
    id          UUID PRIMARY KEY,
    apple_id    TEXT UNIQUE NOT NULL,
    username    TEXT UNIQUE NOT NULL,
    display_name TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- XP Events
CREATE TABLE xp_events (
    id          UUID PRIMARY KEY,
    user_id     UUID REFERENCES users(id),
    source      TEXT NOT NULL,          -- 'workout', 'study', 'meal', 'streak'
    amount      INT NOT NULL,           -- positive or negative
    date        DATE NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Friendships
CREATE TABLE friendships (
    user_id     UUID REFERENCES users(id),
    friend_id   UUID REFERENCES users(id),
    status      TEXT DEFAULT 'pending', -- pending, accepted
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, friend_id)
);

-- Challenges
CREATE TABLE challenges (
    id          UUID PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT,
    metric      TEXT NOT NULL,           -- 'study_minutes', 'xp', 'workouts'
    start_date  DATE NOT NULL,
    end_date    DATE NOT NULL,
    created_by  UUID REFERENCES users(id)
);

-- Challenge participants
CREATE TABLE challenge_participants (
    challenge_id UUID REFERENCES challenges(id),
    user_id      UUID REFERENCES users(id),
    score        INT DEFAULT 0,
    PRIMARY KEY (challenge_id, user_id)
);

-- Achievements
CREATE TABLE achievements (
    id          UUID PRIMARY KEY,
    user_id     UUID REFERENCES users(id),
    badge       TEXT NOT NULL,
    earned_at   TIMESTAMPTZ DEFAULT NOW()
);

-- Weekly leaderboard (materialized view, refreshed daily)
CREATE MATERIALIZED VIEW weekly_leaderboard AS
SELECT
    user_id,
    SUM(amount) as weekly_xp,
    RANK() OVER (ORDER BY SUM(amount) DESC) as rank
FROM xp_events
WHERE date >= date_trunc('week', CURRENT_DATE)
GROUP BY user_id;
```

---

## Integration Details

### Whoop API Integration

**Auth Flow (requires backend):**
```
1. iOS: User taps "Connect Whoop"
2. iOS: Open ASWebAuthenticationSession → Whoop OAuth URL
3. Whoop: User authorizes → redirects to tempo://callback?code=XXX
4. iOS: Send authorization code to Tempo backend
5. Backend: Exchange code for tokens using client_secret
6. Backend: Store encrypted tokens in PostgreSQL
7. Backend: Return success to iOS
8. iOS: Start syncing Whoop data through backend proxy
```

**Scopes needed:** `read:recovery read:cycles read:workout read:sleep read:profile read:body_measurement offline`

**Sync Strategy:**
- Webhooks for real-time: `workout.updated`, `sleep.updated`, `recovery.updated`
- Polling for day strain/cycles: every 15 minutes during active hours
- Full sync on app launch
- Rate limit: 100 req/min, 10,000 req/day (plenty)

**Key Endpoints Used:**
| Endpoint | Used By | Frequency |
|----------|---------|-----------|
| `GET /v2/recovery` | Dashboard, Recovery, Training | On webhook + app launch |
| `GET /v2/activity/sleep` | Dashboard, Recovery | On webhook + app launch |
| `GET /v2/activity/workout` | Dashboard, Training | On webhook |
| `GET /v2/cycle` | Dashboard (strain) | Poll every 15 min |
| `GET /v2/user/measurement/body` | Profile | On app launch |

### NutriTrack Integration

**Auth:** PIN-based session cookie (NutriTrack is single-user).

**Strategy:** Tempo backend proxies to NutriTrack's Flask server. NutriTrack runs as a separate service (already deployed).

**Key Endpoints Used:**
| Endpoint | Used By | Data |
|----------|---------|------|
| `GET /api/today` | Dashboard | Today's meals, macros, progress |
| `GET /api/today/macro-balance` | Dashboard | Current macro progress |
| `GET /api/plan/<date>` | Dashboard | Specific day data |
| `GET /api/weekly-report` | Weekly Report | Week summary |
| `GET /api/whoop/status` | Recovery | Whoop sync status |
| `GET /api/recovery/predict` | Recovery | Recovery prediction |
| `GET /api/intelligence/training/readiness` | Training | Training readiness |
| `GET /api/progress/streaks` | Arena | Compliance streaks |

### Apple HealthKit

**Read Types:**
- `HKQuantityType(.stepCount)` — Dashboard steps
- `HKQuantityType(.activeEnergyBurned)` — Dashboard active cal
- `HKQuantityType(.heartRate)` — Live HR during workouts
- `HKQuantityType(.heartRateVariabilitySDNN)` — HRV (Whoop source)
- `HKQuantityType(.restingHeartRate)` — RHR (Whoop source)
- `HKCategoryType(.sleepAnalysis)` — Sleep stages
- `HKWorkoutType.workoutType()` — Auto-detected workouts

**Write Types:**
- `HKQuantityType(.dietaryEnergyConsumed)` — From NutriTrack meals
- `HKWorkoutType.workoutType()` — From RepForge logged workouts

**Background Delivery:** Enabled for steps, workouts, sleep — app updates even when not in foreground.

### Apple Calendar (EventKit)

**Read:** University class schedule, exam dates, football practice times.
**Purpose:** Training module avoids conflicts. Accountability knows when study blocks are possible.

---

## Backend Architecture (Vapor)

```
tempo-backend/
├── Sources/
│   └── App/
│       ├── configure.swift          # App setup, DB, middleware
│       ├── routes.swift             # Route registration
│       ├── Controllers/
│       │   ├── AuthController.swift       # Sign in with Apple, JWT
│       │   ├── WhoopController.swift      # OAuth proxy, webhook handler
│       │   ├── NutriTrackController.swift # Proxy to NutriTrack Flask
│       │   ├── ArenaController.swift      # XP, leaderboards, challenges
│       │   ├── SyncController.swift       # Data sync endpoint for iOS
│       │   └── WebhookController.swift    # Whoop webhook receiver
│       ├── Models/
│       │   ├── User.swift
│       │   ├── WhoopToken.swift
│       │   ├── XPEvent.swift
│       │   ├── Friendship.swift
│       │   ├── Challenge.swift
│       │   └── Achievement.swift
│       ├── Services/
│       │   ├── WhoopService.swift         # Whoop API client
│       │   ├── NutriTrackService.swift    # NutriTrack API client
│       │   ├── PushNotificationService.swift
│       │   └── AIService.swift            # Claude API for insights
│       └── Middleware/
│           ├── JWTMiddleware.swift
│           └── RateLimitMiddleware.swift
├── Tests/
├── Package.swift
└── docker-compose.yml               # PostgreSQL + Vapor
```

---

## iOS App Structure

```
Tempo/
├── TempoApp.swift                    # App entry point
├── Models/                           # SwiftData models
│   ├── DailySnapshot.swift
│   ├── WorkoutPlan.swift
│   ├── Exercise.swift
│   ├── NonNegotiable.swift
│   ├── DailyAccountability.swift
│   ├── DailyPrescription.swift
│   ├── StudySession.swift
│   └── UserSettings.swift
├── Services/                         # Business logic
│   ├── HealthKitService.swift        # HealthKit read/write
│   ├── WhoopService.swift            # Whoop data via backend
│   ├── NutriTrackService.swift       # NutriTrack data via backend
│   ├── CalendarService.swift         # EventKit integration
│   ├── NotificationService.swift     # Drill sergeant notifications
│   ├── TrainingEngine.swift          # Workout programming logic
│   ├── RecoveryEngine.swift          # Prescription generation
│   ├── ScoringEngine.swift           # Daily score + XP calculation
│   └── SyncService.swift             # Backend sync coordinator
├── Views/
│   ├── Dashboard/
│   │   ├── DashboardView.swift       # Main 4-quadrant view
│   │   ├── BodyQuadrant.swift
│   │   ├── FuelQuadrant.swift
│   │   ├── MindQuadrant.swift
│   │   └── MoveQuadrant.swift
│   ├── Training/
│   │   ├── TodayWorkoutView.swift
│   │   ├── WorkoutLogView.swift
│   │   ├── ProgressChartsView.swift
│   │   └── WeekPlanView.swift
│   ├── Accountability/
│   │   ├── LockdownView.swift
│   │   ├── FocusTimerView.swift
│   │   └── StreakCalendarView.swift
│   ├── Recovery/
│   │   ├── RecoveryTodayView.swift
│   │   ├── SleepDetailView.swift
│   │   └── RecoveryTrendsView.swift
│   ├── Arena/
│   │   ├── ArenaView.swift
│   │   ├── LeaderboardView.swift
│   │   ├── ChallengesView.swift
│   │   └── AchievementsView.swift
│   ├── Onboarding/
│   │   ├── OnboardingFlow.swift
│   │   ├── WhoopConnectView.swift
│   │   ├── NutriTrackConnectView.swift
│   │   ├── HealthKitPermissionView.swift
│   │   └── GoalSetupView.swift
│   └── Shared/
│       ├── ScoreRing.swift
│       ├── QuadrantCard.swift
│       ├── TrendChart.swift
│       └── DrillSergeantAlert.swift
├── Resources/
│   ├── Assets.xcassets
│   └── Exercises.json                # Exercise library seed data
└── TempoTests/
```

---

## Build Order (Phased Rollout)

### Phase 1: Foundation (Week 1)
**Goal:** App shell + HealthKit + basic dashboard

- [ ] Xcode project setup (SwiftUI, SwiftData, HealthKit entitlement)
- [ ] SwiftData models (DailySnapshot, UserSettings)
- [ ] HealthKitService — authorization + read steps/HR/workouts/sleep
- [ ] DashboardView — basic 4-quadrant layout with HealthKit data
- [ ] Tab bar navigation (Dashboard, Training, Lockdown, Recovery, Arena)
- [ ] Onboarding flow — HealthKit permissions

### Phase 2: Whoop + Recovery (Week 2)
**Goal:** Whoop connected, recovery prescriptions working

- [ ] Vapor backend project setup + PostgreSQL
- [ ] User model + Sign in with Apple
- [ ] WhoopController — OAuth proxy flow
- [ ] WhoopService (iOS) — fetch recovery/sleep/strain via backend
- [ ] RecoveryEngine — prescription generation logic
- [ ] RecoveryTodayView + SleepDetailView
- [ ] Dashboard updated with Whoop data

### Phase 3: Training (Week 3)
**Goal:** AI workout programming + logging

- [ ] Exercise library (seed data JSON)
- [ ] TrainingEngine — PPL split programming with recovery adjustment
- [ ] TodayWorkoutView — prescribed workout display
- [ ] WorkoutLogView — quick-tap set logging during workout
- [ ] WeekPlanView — 7-day training overview
- [ ] ProgressChartsView — exercise progression charts
- [ ] Calendar integration — read football/class schedule

### Phase 4: Accountability (Week 4)
**Goal:** Non-negotiables + drill sergeant notifications

- [ ] NonNegotiable model + DailyAccountability
- [ ] LockdownView — daily checklist with progress
- [ ] FocusTimerView — Pomodoro study timer
- [ ] NotificationService — escalating push notification system
- [ ] Auto-tracking integration (Whoop confirms training, NutriTrack confirms meals)
- [ ] StreakCalendarView — heatmap of completed days

### Phase 5: NutriTrack Integration (Week 4-5)
**Goal:** Nutrition data flowing into dashboard

- [ ] NutriTrackController (backend) — proxy to Flask API
- [ ] NutriTrackService (iOS) — fetch meals/macros
- [ ] FuelQuadrant updated with real NutriTrack data
- [ ] Meal timing alerts in Accountability module

### Phase 6: Arena (Week 5-6)
**Goal:** Social features, XP, leaderboards

- [ ] ArenaController (backend) — XP events, leaderboards, challenges
- [ ] Friend system — add by username, accept/decline
- [ ] ScoringEngine — XP calculation from all modules
- [ ] ArenaView — personal XP + level
- [ ] LeaderboardView — weekly rankings
- [ ] ChallengesView — create and join challenges
- [ ] AchievementsView — badge collection

### Phase 7: AI + Polish (Week 6-7)
**Goal:** Claude-powered insights, weekly reports, App Store readiness

- [ ] AIService (backend) — Claude API for pattern analysis
- [ ] Weekly report generation
- [ ] PatternView — correlation insights
- [ ] UI polish — animations, haptics, dark mode
- [ ] App Store assets — screenshots, description, privacy policy
- [ ] TestFlight beta

---

## Key Architectural Decisions

### 1. Why Vapor (Swift) over FastAPI (Python)?
- Full-stack Swift: shared types between iOS and backend
- Type safety end-to-end reduces bugs
- Vapor's async/await aligns with Swift concurrency model
- Growth opportunity: deepens Swift expertise
- Trade-off: smaller ecosystem than Python, but sufficient for our needs

### 2. Why SwiftData over Core Data?
- Modern Swift-native API with `@Model` macro
- Automatic CloudKit sync (future: multi-device)
- Simpler than Core Data, sufficient for our schema
- Trade-off: newer, fewer Stack Overflow answers, but well-documented

### 3. Why proxy NutriTrack through backend vs. direct iOS→Flask?
- Backend can cache NutriTrack responses (reduce load on Flask)
- Unified auth: one JWT for everything
- Backend can transform NutriTrack data to match Tempo's models
- NutriTrack's PIN auth doesn't work well from iOS natively

### 4. Why Sign in with Apple?
- Required by App Store if you offer any social login
- Zero-friction for iOS users
- Provides stable user ID for Arena features
- Privacy-friendly (aligns with app philosophy)

### 5. Offline-first design
- All daily data cached locally in SwiftData
- App works without internet (shows cached data)
- Sync when connection available
- HealthKit data always available locally
- Arena features require connection (leaderboards are server-side)

---

## Environment & API Keys Required

### iOS App
```
TEMPO_BACKEND_URL=https://api.tempo.app  (or localhost for dev)
```

### Backend (.env)
```
# Database
DATABASE_URL=postgresql://user:pass@localhost:5432/tempo

# Auth
APPLE_TEAM_ID=XXXXXXXXXX
APPLE_KEY_ID=XXXXXXXXXX
APPLE_PRIVATE_KEY_PATH=./AuthKey.p8
JWT_SECRET=<random-256-bit>

# Whoop
WHOOP_CLIENT_ID=<from developer.whoop.com>
WHOOP_CLIENT_SECRET=<from developer.whoop.com>
WHOOP_REDIRECT_URI=https://api.tempo.app/whoop/callback
WHOOP_WEBHOOK_SECRET=<for HMAC verification>

# NutriTrack
NUTRITRACK_BASE_URL=https://nutritrack.example.com
NUTRITRACK_PIN=<6-digit PIN>

# Claude (AI insights)
ANTHROPIC_API_KEY=<from console.anthropic.com>

# APNs
APNS_KEY_ID=XXXXXXXXXX
APNS_TEAM_ID=XXXXXXXXXX
APNS_KEY_PATH=./APNsKey.p8
```
