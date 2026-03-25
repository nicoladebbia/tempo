# Tempo — Data Flow Architecture

> **Version:** 1.0.0
> **Last Updated:** 2026-03-24
> **Author:** Nicola Debbia
> **Status:** Definitive Reference
> **Purpose:** Pin this to the wall. Every "where does this data come from?" question should be answered here.

---

## Table of Contents

1. [System-Level Data Flow Diagram](#1-system-level-data-flow-diagram)
2. [Per-Module Data Flow](#2-per-module-data-flow)
3. [Integration Data Flows](#3-integration-data-flows-detailed)
4. [Real-Time Data Flows](#4-real-time-data-flows)
5. [Daily Data Lifecycle](#5-daily-data-lifecycle)
6. [Sync Architecture](#6-sync-architecture)
7. [Data Aggregation Pipelines](#7-data-aggregation-pipelines)
8. [Notification Data Flow](#8-notification-data-flow)
9. [Data Deletion Flow (GDPR)](#9-data-deletion-flow-gdpr)
10. [Data Size Estimates](#10-data-size-estimates)

---

## 1. System-Level Data Flow Diagram

```
                            EXTERNAL DATA SOURCES
    ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
    │   Whoop Cloud   │  │  Apple HealthKit │  │ NutriTrack Flask │  │ Apple Calendar   │
    │   (REST API)    │  │  (On-Device DB)  │  │ (Self-Hosted)    │  │ (EventKit/Local) │
    └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘
             │                    │                    │                    │
             │ HTTPS              │ HealthKit API      │ HTTPS              │ EventKit API
             │ + Webhooks         │ (Local framework)  │ (via backend       │ (Local framework)
             │                    │                    │  proxy)            │
    ─────────┼────────────────────┼────────────────────┼────────────────────┼─────────────────
             │                    │                    │                    │
             ▼                    │                    │                    │
    ┌─────────────────────────────┼────────────────────┼────────────────────┼──────────────┐
    │                TEMPO BACKEND (Vapor 4 + PostgreSQL + Redis)          │              │
    │                                                                      │              │
    │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │              │
    │  │ Whoop Sync   │  │ NutriTrack   │  │ Auth Service │               │              │
    │  │ Service      │  │ Proxy        │  │ (Apple+JWT)  │               │              │
    │  │  - OAuth2    │  │  - PIN auth  │  │              │               │              │
    │  │  - Webhooks  │  │  - Caching   │  │              │               │              │
    │  │  - Polling   │  │  - Polling   │  │              │               │              │
    │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘               │              │
    │         │                 │                  │                       │              │
    │         ▼                 ▼                  ▼                       │              │
    │  ┌─────────────────────────────────────────────────┐                │              │
    │  │              PostgreSQL 16                       │                │              │
    │  │  users, whoop_*, nutritrack_*, daily_snapshots,  │                │              │
    │  │  manual_workouts, study_sessions, xp_events,     │                │              │
    │  │  achievements, challenges, friendships, insights │                │              │
    │  └─────────────────────────────────────────────────┘                │              │
    │         │                                                           │              │
    │         │  ┌─────────────────────┐  ┌──────────────────┐           │              │
    │         ├──│ Redis 7             │  │ Background Jobs  │           │              │
    │         │  │  - Cache (TTL)      │  │  - WhoopSync     │           │              │
    │         │  │  - Idempotency      │  │  - Reconciliation│           │              │
    │         │  │  - Rate limiting    │  │  - XP Calc       │           │              │
    │         │  │  - Webhook dedup    │  │  - AI Insights   │           │              │
    │         │  │  - Session/state    │  │  - Notifications │           │              │
    │         │  └─────────────────────┘  └──────────────────┘           │              │
    │         │                                                           │              │
    │  ┌──────┴────────────────────────────────────────────────────┐      │              │
    │  │  REST API (HTTPS)          │  WebSocket (/v1/ws)         │      │              │
    │  │  /v1/auth/*                │  - leaderboard.update       │      │              │
    │  │  /v1/whoop/*               │  - challenge.score_update   │      │              │
    │  │  /v1/nutritrack/*          │  - achievement.earned       │      │              │
    │  │  /v1/sync/batch            │  - xp.earned                │      │              │
    │  │  /v1/workouts              │  - friend.request           │      │              │
    │  │  /v1/xp/*                  │                             │      │              │
    │  │  /v1/leaderboard/*         │                             │      │              │
    │  │  /v1/insights/*            │                             │      │              │
    │  └──────┬──────────────────────┬────────────────────────────┘      │              │
    │         │                      │                                    │              │
    │         │ APNs ────────────────┼────────────────────────────────────┘              │
    │         │ (Push Notifications) │                                                   │
    └─────────┼──────────────────────┼───────────────────────────────────────────────────┘
              │                      │
              │ HTTPS / APNs         │ WebSocket / HTTPS
              │                      │
    ──────────┼──────────────────────┼───────────────────────────────────────────────────
              │                      │
              ▼                      ▼
    ┌─────────────────────────────────────────────────────────────────────────────────────┐
    │                        TEMPO iOS APP (SwiftUI + SwiftData)                          │
    │                                                                                     │
    │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐        │
    │  │  APIClient    │  │ HealthKit     │  │ CalendarSvc   │  │ SyncService   │        │
    │  │  (HTTPS)      │  │ Service       │  │ (EventKit)    │  │               │        │
    │  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘        │
    │          │                  │                   │                  │                 │
    │          │    ┌─────────────┼───────────────────┼──────────────────┘                 │
    │          │    │             │                   │                                    │
    │          ▼    ▼             ▼                   ▼                                    │
    │  ┌──────────────────────────────────────────────────────┐                           │
    │  │              SwiftData (ModelContainer)               │                           │
    │  │  group.app.tempo (shared with Watch + Widgets)        │                           │
    │  │                                                       │                           │
    │  │  UserProfile, UserSettings, DailySnapshot,            │                           │
    │  │  WorkoutPlan, Exercise, ExerciseHistory,               │                           │
    │  │  NonNegotiable, DailyAccountability, StudySession,    │                           │
    │  │  DailyRecovery, DailyPrescription, RecoveryInsight,   │                           │
    │  │  XPEvent, Achievement, ChallengeLocal,                │                           │
    │  │  SyncState, PendingSync, WhoopConnection,             │                           │
    │  │  NutriTrackConnection, HealthKitState                 │                           │
    │  └────────────────────────┬──────────────────────────────┘                           │
    │                           │                                                          │
    │                           ▼                                                          │
    │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐         │
    │  │ Dashboard   │ │ Training   │ │ Account-   │ │ Recovery   │ │ Arena      │         │
    │  │ (LifeOS)   │ │ (RepForge) │ │ ability    │ │ (RecoverIQ)│ │ (ClutchTime│         │
    │  │            │ │            │ │ (Lockdown) │ │            │ │            │         │
    │  └────────────┘ └────────────┘ └────────────┘ └────────────┘ └────────────┘         │
    │                                                                                      │
    │  ┌─────────────────────────────────────────────────────────────────────────┐         │
    │  │ Additional Local Storage                                                │         │
    │  │  - Keychain: JWT tokens, device UUID                                    │         │
    │  │  - UserDefaults: feature flags, onboarding state, last sync timestamps  │         │
    │  │  - FileManager (Cache): avatar images, chart snapshots                  │         │
    │  └─────────────────────────────────────────────────────────────────────────┘         │
    └─────────────────────────────────────────────────────────────────────────────────────┘
```

### Data Path Legend

| Arrow Style | Protocol | Direction |
|---|---|---|
| `──▶` | HTTPS REST | One-way (request/response) |
| `◀──▶` | WebSocket | Bidirectional |
| `──▶` (dashed) | APNs Push | Server to device |
| `──▶` HealthKit | Local framework API | On-device read/write |
| `──▶` EventKit | Local framework API | On-device read-only |

### Data Direction Summary

| Source | Direction | Destination | Protocol | Data Types |
|---|---|---|---|---|
| Whoop Cloud | --> | Backend | HTTPS + Webhooks | Recovery, sleep, strain, workouts, body |
| Backend | --> | Whoop Cloud | HTTPS (OAuth2) | Token refresh, data fetch requests |
| Backend | --> | iOS App | HTTPS REST | All synced data, insights, social |
| iOS App | --> | Backend | HTTPS REST | Workouts, study, snapshots, XP events |
| Backend | --> | iOS App | APNs | Recovery alerts, accountability, social |
| Backend | <-> | iOS App | WebSocket | Leaderboard, challenges, achievements |
| HealthKit | --> | iOS App | Local API | Steps, HR, sleep, energy, workouts |
| iOS App | --> | HealthKit | Local API | RepForge workouts, NutriTrack meals |
| NutriTrack | --> | Backend | HTTPS | Meals, macros, calories, streaks |
| Calendar | --> | iOS App | Local API | Events (classes, football, exams) |
| Claude API | --> | Backend | HTTPS | Weekly reports, pattern insights |

---

## 2. Per-Module Data Flow

### 2.1 Dashboard (LifeOS)

The Dashboard is a pure **consumer** -- it reads from every other module and every integration but writes nothing to external systems. It is the aggregation point.

```
                     ┌─────────────────────────────────────┐
                     │         DASHBOARD (LifeOS)           │
                     │                                      │
    BODY Quadrant    │  ◄── Whoop (recovery, HRV, RHR,     │
    (recovery color) │       sleep, strain)                 │
                     │  ◄── HealthKit (HR, sleep fallback)  │
                     │                                      │
    FUEL Quadrant    │  ◄── NutriTrack (calories, macros,   │
    (nutrition ring) │       meals logged/planned)           │
                     │                                      │
    MIND Quadrant    │  ◄── Local (study minutes, target,   │
    (study progress) │       focus sessions)                 │
                     │                                      │
    MOVE Quadrant    │  ◄── HealthKit (steps, active kcal)  │
    (steps + workout)│  ◄── Local (workout completion)      │
                     │  ◄── Whoop (workout strain)          │
                     │                                      │
    Non-Negotiables  │  ◄── Accountability module           │
                     │                                      │
    Daily Score      │  ◄── DailySnapshot (computed)        │
                     │                                      │
    AI Insights      │  ◄── Backend (Claude-generated)      │
                     └─────────────────────────────────────┘
```

**What Dashboard READS:**

| Data | Source | Frequency | Format |
|---|---|---|---|
| Recovery score (0-100) | Whoop via backend | On foreground + pull-to-refresh + 15min background | `DailySnapshot.recoveryScore` |
| HRV (ms, RMSSD) | Whoop via backend | Same as recovery | `DailySnapshot.hrv` |
| Resting HR (bpm) | Whoop preferred, HealthKit fallback | Same as recovery | `DailySnapshot.rhr` |
| Sleep hours + score | Whoop via backend | Same as recovery | `DailySnapshot.sleepHours/sleepScore` |
| Day strain (0-21) | Whoop via backend, polled every 15 min | Every 15min daytime | `DailySnapshot.strain` |
| Calories consumed/target | NutriTrack via backend | On foreground + 15min | `DailySnapshot.caloriesConsumed/calorieTarget` |
| Macros (P/C/F actual + target) | NutriTrack via backend | Same as calories | `DailySnapshot.protein*/carbs*/fat*` |
| Meals logged/planned | NutriTrack via backend | Same as calories | `DailySnapshot.mealsLogged/mealsPlanned` |
| Study minutes + target | Local SwiftData | Immediate (SwiftData observation) | `DailySnapshot.studyMinutes/studyTarget` |
| Steps | HealthKit | HKObserverQuery (hourly background) | `DailySnapshot.steps` |
| Active calories | HealthKit | HKObserverQuery (hourly background) | `DailySnapshot.activeCalories` |
| Workout completed | Local SwiftData | Immediate | `DailySnapshot.workoutCompleted` |
| Non-negotiable progress | Local SwiftData | Immediate | `DailySnapshot.nonNegotiablesCompleted/Total` |
| AI insight banner | Backend (Claude) | Weekly (Sunday), cached | `RecoveryInsight` model |

**What Dashboard WRITES:**

| Data | Destination | Trigger |
|---|---|---|
| `DailySnapshot` (full aggregation) | SwiftData local | Every data source update |
| `DailySnapshot.DTO` | Backend via `/v1/sync/batch` | App background, periodic, manual |

**What Dashboard DERIVES:**

| Computation | Inputs | Output |
|---|---|---|
| Daily Score (0-100) | Recovery (25%), nutrition compliance (25%), study compliance (25%), move compliance (25%) | `DailySnapshot.dailyScore` |
| Calorie compliance | caloriesConsumed / calorieTarget | 0.0-1.0+ ratio |
| Protein compliance | proteinActual / proteinTarget | 0.0-1.0+ ratio |
| Study compliance | studyMinutes / studyTarget | 0.0-1.0+ ratio |
| Recovery zone | recoveryScore thresholds | green (>=67), yellow (34-66), red (<34) |
| Staleness status | Per-source `lastSync` vs threshold | fresh / stale / critical |

---

### 2.2 Training (RepForge)

```
    INPUTS                              REPFORGE                          OUTPUTS
    ──────                              ────────                          ───────

    Whoop recovery score ────────►  ┌───────────────────┐  ────────► SwiftData
    (via DailyRecovery)             │  Workout Generation │           (WorkoutPlan, PlannedExercise,
                                    │  Algorithm          │            PlannedSet, ExerciseHistory,
    Calendar events ─────────────►  │  - Recovery adjust  │            PersonalRecord)
    (football days, exams)          │  - Football avoid   │
                                    │  - Deload detect    │  ────────► HealthKit
    Exercise library ────────────►  │  - Progressive      │           (HKWorkout + HR samples
    (150+ exercises, SwiftData)     │    overload         │            + energy burned)
                                    └───────────┬─────────┘
    HealthKit heart rate ────────►              │              ────────► Backend
    (live during workout,                      │              (/v1/sync/batch with workouts)
     HKAnchoredObjectQuery)                    │
                                               │              ────────► Accountability module
    User settings ───────────────►             │              (workoutCompleted flag)
    (training split, football                  │
     days, equipment)                          │              ────────► Arena module
                                               │              (XP: workout +100, PR +75,
                                               ▼               recovery-adjusted +20-50)
                                    ┌───────────────────┐
                                    │  Active Workout    │
                                    │  - Set logging     │
                                    │  - Rest timer      │
                                    │  - PR detection    │
                                    │  - Live HR display │
                                    └───────────────────┘
```

**What Training READS:**

| Data | Source | Frequency | Purpose |
|---|---|---|---|
| Recovery score + zone | Whoop via `DailyRecovery` | On workout screen open | Adjust volume/intensity |
| Calendar events | EventKit via `CalendarService` | On week plan generation | Avoid scheduling on football days/exams |
| Exercise library | Local SwiftData `Exercise` table | On plan generation | Exercise selection |
| Exercise history | Local SwiftData `ExerciseHistory` | On plan generation + active workout | Progressive overload, PR detection |
| Heart rate (live) | HealthKit `HKAnchoredObjectQuery` | Real-time during workout | Display, calorie estimation |
| User training config | Local SwiftData `UserProfile` | On plan generation | Split type, football days, equipment |

**What Training WRITES:**

| Data | Destination | Trigger |
|---|---|---|
| Completed sets (weight, reps) | SwiftData `ExerciseHistory` | Each set completion |
| Personal records | SwiftData `PersonalRecord` | New max detected |
| Workout session | HealthKit (HKWorkoutBuilder) | Workout completion |
| Workout data | Backend `/v1/sync/batch` | Next sync cycle |
| `workoutCompleted` flag | `DailySnapshot` | Workout finish |
| XP events (workout, PR) | `XPEvent` in SwiftData + backend | Workout finish |

---

### 2.3 Accountability (Lockdown)

```
    INPUTS                           LOCKDOWN                           OUTPUTS
    ──────                           ────────                           ───────

    NutriTrack meals ──────────►  ┌───────────────────┐  ────────► SwiftData
    (eaten count vs target)       │  Daily Non-Negotiable│          (DailyAccountability,
                                  │  Tracker             │           NonNegotiableProgress)
    Whoop workout detection ───►  │  - Auto-tracking    │
    (via HealthKit observer)      │  - Manual check     │  ────────► Arena module
                                  │  - Timer sessions   │          (XP: per-NN +10,
    HealthKit steps ───────────►  │  - PS5 gate logic   │           all-complete +60)
    (vs step target)              │                     │
                                  └───────────┬─────────┘  ────────► Backend
    Study session timer ───────►              │           (/v1/accountability/today,
    (local focus timer)                       │            escalation tier tracking)
                                              │
    UserSettings ──────────────►              │           ────────► Notification engine
    (PS5 time, wake time,                     │           (escalation tiers 1-4,
     notification intensity)                  ▼            drill sergeant copy)
                                  ┌───────────────────┐
                                  │  Leisure Gate      │  ────────► Dashboard
                                  │  (PS5 earned?)     │          (non-negotiable summary
                                  │  - Check all       │           on main screen)
                                  │    required NNs    │
                                  │  - Unlock/lock UI  │
                                  └───────────────────┘
```

**What Accountability READS:**

| Data | Source | Frequency | Purpose |
|---|---|---|---|
| Meals eaten count | NutriTrack via backend (cached) | Every 15 min poll | Auto-complete meal NN |
| Workout completion | HealthKit observer + local flag | Immediate on workout end | Auto-complete training NN |
| Steps | HealthKit `HKObserverQuery` | Hourly background | Auto-complete steps NN |
| Study session minutes | Local `StudySession` | Immediate on timer stop | Auto-complete study NN |
| Recovery score | Whoop via `DailyRecovery` | On morning load | Context for rest day excuse |
| PS5 time / wake time / intensity | `UserSettings` | On view appear | Escalation timing |

**What Accountability WRITES:**

| Data | Destination | Trigger |
|---|---|---|
| `NonNegotiableProgress` | SwiftData | Each NN status change |
| `DailyAccountability` | SwiftData | NN completion / day rollover |
| `StudySession` | SwiftData | Timer stop |
| Accountability status | Backend `/v1/accountability/today` | Sync cycle |
| XP events | Arena module | NN completion |
| Notification requests | Local UNUserNotificationCenter + Backend APNs | Escalation tier thresholds |

---

### 2.4 Recovery (RecoverIQ)

```
    INPUTS                          RECOVERIQ                          OUTPUTS
    ──────                          ─────────                          ───────

    Whoop recovery ────────────►  ┌───────────────────┐  ────────► SwiftData
    (score, HRV, RHR, SpO2,      │  Prescription      │          (DailyRecovery,
     skin temp)                   │  Engine             │           DailyPrescription,
                                  │  - Training adjust  │           RecoveryInsight)
    Whoop sleep ───────────────►  │  - Sleep Rx         │
    (stages, performance,         │  - Nutrition Rx     │  ────────► Training module
     efficiency, debt)            │  - Activity Rx      │          (recovery-adjusted
                                  │                     │           workout intensity)
    Whoop strain ──────────────►  │  - Trend analysis   │
    (day strain, workout strain)  │  - Pattern detect   │  ────────► Dashboard
                                  └───────────┬─────────┘          (BODY quadrant data)
    NutriTrack macros ─────────►              │
    (protein intake, calorie                  │           ────────► Notifications
     balance)                                 │           (morning recovery push,
                                              │            prescription alerts)
    HealthKit sleep ───────────►              │
    (fallback if no Whoop)                    │           ────────► Backend
                                              ▼           (/v1/insights/weekly input,
                                  ┌───────────────────┐    pattern analysis data)
                                  │  Trend Calculation │
                                  │  - 7/14/30-day avg│
                                  │  - vs personal avg │
                                  │  - sparkline data  │
                                  └───────────────────┘
```

**What Recovery READS:**

| Data | Source | Frequency | Purpose |
|---|---|---|---|
| Recovery score + metrics | Whoop via backend | Webhook-triggered + 30min poll | Primary recovery data |
| Sleep stages + scores | Whoop via backend | Webhook-triggered + 30min poll | Sleep analysis |
| Day strain | Whoop via backend | 15min poll (daytime) | Strain context |
| Protein/calorie intake | NutriTrack via backend | 15min poll | Recovery nutrition |
| Sleep (fallback) | HealthKit | On recovery screen if no Whoop | Fallback sleep data |
| Historical snapshots | SwiftData `DailySnapshot` (30-90 days) | On trend view | Trend calculations |

**What Recovery DERIVES:**

| Computation | Inputs | Output |
|---|---|---|
| Daily prescription | Recovery zone + sleep debt + strain + nutrition | `DailyPrescription` (training intensity, bedtime Rx, nutrition Rx) |
| Recovery trend | 7/14/30-day recovery scores | Sparkline data, average, delta vs prior period |
| Recovery insight | 30-90 day pattern analysis via Claude API | `RecoveryInsight` (correlations, recommendations) |
| Sleep debt | sleepNeededBaseline - actualSleep (cumulative) | Hours owed |

---

### 2.5 Arena (ClutchTime)

```
    INPUTS                           CLUTCHTIME                         OUTPUTS
    ──────                           ──────────                         ───────

    All module XP events ──────►  ┌───────────────────┐  ────────► SwiftData
    (workout, study, meals,       │  Scoring Engine     │          (XPEvent, Achievement,
     sleep, steps, NNs,           │  - XP calculation   │           ChallengeLocal)
     perfect day, streak)         │  - Streak tracking  │
                                  │  - Multipliers      │  ────────► Backend
    Backend social data ───────►  │  - Anti-cheat       │          (/v1/xp/events,
    (friends, challenge           │  - Penalty system   │           /v1/achievements/check)
     standings, leaderboard)      │                     │
                                  └───────────┬─────────┘  ────────► WebSocket
    WebSocket events ──────────►              │           (leaderboard updates,
    (leaderboard.update,                      │            challenge scores)
     challenge.score_update,                  │
     achievement.earned)                      │           ────────► Notifications
                                              │           (leaderboard rank change,
                                              │            achievement unlock,
                                              ▼            streak at risk)
                                  ┌───────────────────┐
                                  │  Leaderboard +     │  ────────► Dashboard
                                  │  Profile Display   │          (XP + level badge)
                                  │  - Weekly/monthly  │
                                  │  - Friend ranking  │
                                  └───────────────────┘
```

**What Arena READS:**

| Data | Source | Frequency | Purpose |
|---|---|---|---|
| Workout XP events | Training module | On workout complete | +100-205 XP |
| Study XP events | Accountability module | On study session end | +30-310 XP/day |
| Nutrition XP events | NutriTrack poll detection | On meal count change | +15-100 XP/day |
| Sleep/Recovery XP | Whoop webhook-triggered | On new recovery score | +20-60 XP/day |
| Step milestones | HealthKit observer | Hourly | +20-75 XP (highest tier) |
| NN completions | Accountability module | On NN complete | +10 each, +60 all-complete |
| Leaderboard data | Backend `/v1/leaderboard/:period` | On Arena tab open + WebSocket | Rankings display |
| Challenge standings | Backend `/v1/challenges/:id` + WebSocket | Real-time | Challenge progress |
| Achievement catalog | Backend `/v1/achievements/available` | On profile view, ETag cached | Progress tracking |
| Friend list + stats | Backend `/v1/friends` | On social tab open | Social features |

**What Arena WRITES:**

| Data | Destination | Trigger |
|---|---|---|
| XP events | SwiftData `XPEvent` + Backend `/v1/xp/events` | Each XP-earning action |
| Achievement checks | Backend `/v1/achievements/check` | Post XP-event |
| Challenge joins/leaves | Backend `/v1/challenges/:id/join` | User action |
| Friend requests | Backend `/v1/friends/request` | User action |

---

### Module Dependency Graph

```
    ┌──────────────┐
    │  Dashboard   │◄────────────── Reads from ALL modules
    └──────────────┘
           ▲ ▲ ▲ ▲
           │ │ │ │
    ┌──────┘ │ │ └──────┐
    │        │ │        │
    │  ┌─────┘ └─────┐  │
    │  │             │  │
    ▼  ▼             ▼  ▼
┌────────┐ ┌──────────┐ ┌────────┐ ┌────────┐
│Training│ │Accounta- │ │Recovery│ │ Arena  │
│        │ │bility    │ │        │ │        │
└───┬────┘ └────┬─────┘ └───┬────┘ └───▲────┘
    │           │            │          │
    │           │            │          │
    └───────────┼────────────┘          │
                │                       │
                └───────────────────────┘
                  All modules emit XP events
                  to Arena
```

**Cross-module data dependencies:**

| From | To | Data | Path |
|---|---|---|---|
| Recovery | Training | Recovery zone | `DailyRecovery.recoveryZone` read by workout generation algorithm |
| Recovery | Dashboard | BODY quadrant | `DailySnapshot.recoveryScore/hrv/rhr/sleepHours/strain` |
| Training | Accountability | Workout completed flag | `DailySnapshot.workoutCompleted` triggers NN auto-check |
| Training | Arena | Workout XP + PR XP | `XPEvent` created on workout finish |
| Accountability | Dashboard | NN progress | `DailySnapshot.nonNegotiablesCompleted/Total` |
| Accountability | Arena | NN XP | `XPEvent` created on each NN and all-complete |
| NutriTrack | Accountability | Meal count | `nutriData.meals.filter { $0.status == "eaten" }.count` |
| NutriTrack | Recovery | Protein/calorie intake | Prescription nutrition recommendations |
| NutriTrack | Dashboard | FUEL quadrant | `DailySnapshot.calories*/protein*/carbs*/fat*` |
| Calendar | Training | Football days, exam periods | Week plan generation avoids conflicts |
| HealthKit | Accountability | Steps count | Auto-complete steps NN |
| HealthKit | Dashboard | MOVE quadrant | `DailySnapshot.steps/activeCalories` |
| All modules | Arena | XP events | Every scoreable action flows to Arena |

---

## 3. Integration Data Flows (Detailed)

### 3.1 Whoop Integration

#### Inbound Data Flow (Whoop to User's Screen)

```
    Whoop Strap             Whoop App           Whoop Cloud         Tempo Backend
    ──────────             ─────────           ───────────         ─────────────
    Sensor data ──BLE──►  Syncs via  ──HTTPS──► Stores &  ──Webhook──► Receives
    (HR, accel,           Bluetooth             calculates │          POST /v1/webhooks/whoop
     temp, SpO2)                                scores     │
                                                           │  ◄──Poll──  Also polls
                                                           │   GET /v1/recovery (every 30m)
                                                           │   GET /v1/cycles   (every 15m)
                                                           ▼

    Tempo Backend                    iOS App                         User's Screen
    ─────────────                    ───────                         ─────────────
    1. Verify webhook signature      5. Receive silent push          8. SwiftData
       (HMAC-SHA256)                    or foreground fetch             @Query updates
    2. Dedup via trace_id (Redis)    6. GET /v1/whoop/recovery          view automatically
    3. Enqueue background job        7. Parse JSON response
    4. Fetch from Whoop API             into DailyRecovery model     9. Dashboard BODY
       using stored OAuth token         → save to SwiftData             quadrant re-renders
       → transform & store in PG                                        with new values
       → send silent push to iOS
       → send visible push if
         morning recovery
```

**Hop-by-hop data transformation:**

| Hop | Location | Transformation |
|---|---|---|
| 1. Whoop API response | Whoop Cloud | Raw JSON: `score.recovery_score: 78.0`, `score.hrv_rmssd_milli: 65.4` |
| 2. Backend storage | PostgreSQL `whoop_recovery` | Upsert by `whoop_cycle_id`. `updated_at` comparison for conflict. AES-256-GCM encrypted tokens. |
| 3. Backend API response | `/v1/whoop/recovery` | Envelope: `{ ok: true, data: { recovery_score: 78, hrv_rmssd_milli: 65.4, ... } }` |
| 4. iOS model | SwiftData `DailyRecovery` | `recoveryScore: Double`, `hrvRmssd: Double`, `recoveryZone: .green` (derived) |
| 5. Dashboard display | `BodyQuadrantView` | "78%" with green color, "65 ms" HRV, "52 bpm" RHR |

**Sync triggers:**

| Trigger | Source | Action |
|---|---|---|
| Webhook `recovery.updated` | Whoop server | Immediate fetch + silent push |
| Webhook `sleep.updated` | Whoop server | Immediate fetch + silent push |
| Webhook `workout.updated` | Whoop server | Immediate fetch + XP award + silent push |
| Webhook `cycle.updated` | Whoop server | Immediate fetch + silent push |
| Scheduled poll (recovery) | Backend cron | Every 30min (6AM-10PM), every 60min (10PM-6AM) |
| Scheduled poll (strain/cycle) | Backend cron | Every 15min (6AM-10PM), every 60min (10PM-6AM) |
| Reconciliation job | Backend cron (3AM UTC) | Full 3-day backfill for all users |
| App foreground | iOS `scenePhase` | Fetch latest via backend API |
| Pull-to-refresh | User action | Fetch latest via backend API |

**Caching at each layer:**

| Layer | What | TTL | Invalidation |
|---|---|---|---|
| Whoop API | N/A (source of truth) | N/A | N/A |
| Backend Redis | Recovery response | 120s | Webhook-triggered fetch overwrites |
| Backend Redis | Sleep response | 120s | Webhook-triggered fetch overwrites |
| Backend Redis | Cycle/strain response | 120s | Poll overwrites |
| Backend PostgreSQL | Full recovery/sleep/cycle records | Permanent | Upsert by Whoop ID |
| iOS SwiftData | `DailyRecovery` model | Permanent (1 per day) | Overwritten on newer `updatedAt` |
| iOS in-memory | `DashboardState.body` | Until next refresh | Any Whoop data update |

---

### 3.2 HealthKit Integration

#### Inbound Data Flow (HealthKit to Tempo)

```
    Apple Watch / iPhone Sensors
    ────────────────────────────
    Pedometer, accelerometer,
    optical HR, GPS
            │
            ▼
    ┌──────────────────────┐
    │  Apple HealthKit DB  │  (System-level, on-device)
    │  - stepCount         │
    │  - heartRate         │
    │  - restingHeartRate  │
    │  - heartRateVariability │
    │  - sleepAnalysis     │
    │  - workoutType       │
    │  - activeEnergyBurned│
    │  - dietaryProtein    │  (written by NutriTrack via Tempo)
    └──────────┬───────────┘
               │
     ┌─────────┼──────────────┐
     │         │              │
     ▼         ▼              ▼
    HKObserver   HKStatistics   HKAnchoredObject
    Query        Query          Query
    (background) (on-demand)    (real-time HR)
     │         │              │
     ▼         ▼              ▼
    ┌──────────────────────────┐
    │  HealthKitService (iOS)  │
    │  - fetchTodaySteps()     │
    │  - fetchRestingHeartRate()│
    │  - fetchSleep(for:)      │
    │  - fetchWorkouts(...)    │
    │  - observeHeartRate()    │
    │  - fetchTodayActiveEnergy()│
    └──────────┬───────────────┘
               │
               ▼
    ┌──────────────────────────┐
    │  SwiftData DailySnapshot │
    │  .steps                  │
    │  .activeCalories         │
    │  .sleepHours (fallback)  │
    └──────────────────────────┘
```

#### Outbound Data Flow (Tempo to HealthKit)

```
    RepForge Workout Complete              NutriTrack Meal Logged
    ─────────────────────────              ────────────────────────
    WorkoutPlan + ExerciseHistory          Calories, protein, carbs, fat
            │                                       │
            ▼                                       ▼
    HKWorkoutBuilder                       HKCorrelation (.food)
    - activityType mapped                  - HKQuantitySamples for each macro
    - start/end dates                      - metadata: "TempoSource": "NutriTrack"
    - energy burned (kcal)                 - dedup check before write
    - HR samples attached
            │                                       │
            ▼                                       ▼
    ┌──────────────────────────────────────────────────┐
    │             Apple HealthKit Database              │
    │  (Available to Apple Health app, other apps)     │
    └──────────────────────────────────────────────────┘
```

**Source priority for overlapping data:**

| Metric | Priority 1 | Priority 2 | Priority 3 |
|---|---|---|---|
| Resting HR | Whoop API | HealthKit (Apple Watch) | -- |
| HRV | Whoop API | HealthKit (Apple Watch) | -- |
| Sleep | Whoop API (full stages + scores) | HealthKit (basic stages) | -- |
| Workout HR (live) | HealthKit (Apple Watch wrist) | Whoop (forearm) | -- |
| Steps | HealthKit (auto-deduped) | -- | -- |
| Active energy | HealthKit (auto-deduped) | -- | -- |
| Workouts (detection) | RepForge (manual) | Whoop API | HealthKit (Apple Watch) |

**Deduplication rule for workouts:** If time overlap > 50% between Whoop-detected, HealthKit, and RepForge workouts, treat as the same workout. RepForge data wins for exercise details; Whoop wins for strain/HR zones.

**Background delivery schedule:**

| Data Type | Delivery Frequency | Background Task |
|---|---|---|
| Steps | Hourly | HKObserverQuery + BGAppRefreshTask |
| Workouts | Immediate | HKObserverQuery |
| Sleep | Immediate | HKObserverQuery |
| Active energy | Hourly | HKObserverQuery + BGAppRefreshTask |

---

### 3.3 NutriTrack Integration

#### Inbound Data Flow (NutriTrack to Tempo)

```
    NutriTrack Flask Server                Tempo Backend                   iOS App
    ───────────────────────               ─────────────                   ───────
    /api/today                            /v1/nutritrack/today
    /api/today/macro-balance              /v1/nutritrack/macros
    /api/week/:date                       /v1/nutritrack/week/:date
    /api/progress/streaks                 /v1/nutritrack/streaks
    /api/intelligence/training/readiness  /v1/nutritrack/training-readiness
    /api/export                           /v1/nutritrack/export

    NutriTrack                  Backend Proxy                    iOS App
    ─────────                   ─────────────                    ───────
                   ┌──── PIN auth (AES-256-GCM encrypted) ──►
                   │    session cookie cached
    ◄── HTTP ──────┘    + add session cookie to request
    Response JSON ──────► Cache in Redis (2-5 min TTL)
                         Transform to Tempo format ─────────► GET /v1/nutritrack/today
                                                              Parse into NutriTrackToday
                                                              → Update DailySnapshot
                                                              → Write to HealthKit (meals)
                                                              → Check meal NN
                                                              → Award meal XP if new meal
```

**Polling cadence (no webhooks available):**

| Trigger | Action | Detection |
|---|---|---|
| App foreground | Fetch `/v1/nutritrack/today` | Compare `meals_logged` count with cached value |
| Every 15 minutes (timer) | Same fetch | If count increased, new meal detected |
| Pull-to-refresh | Force fetch (bypass cache) | Full comparison |
| Background app refresh | BGAppRefreshTask every 15min | Lightweight count check |

**Field mapping: NutriTrack to Tempo**

| NutriTrack Field | Tempo DailySnapshot Field | Transform |
|---|---|---|
| `calories_consumed` | `caloriesConsumed` | Direct (Int) |
| `target_calories` | `calorieTarget` | Direct (Int) |
| `protein_g` | `proteinActual` | Direct (Double) |
| `carbs_g` | `carbsActual` | Direct (Double) |
| `fat_g` | `fatActual` | Direct (Double) |
| `target_protein` | `proteinTarget` | Direct (Double) |
| `target_carbs` | `carbsTarget` | Direct (Double) |
| `target_fat` | `fatTarget` | Direct (Double) |
| `meals[].status == "eaten"` count | `mealsLogged` | Count filter |
| `meals` array length | `mealsPlanned` | Array count |

**Caching at each layer:**

| Layer | What | TTL | Invalidation |
|---|---|---|---|
| NutriTrack Flask | N/A (source of truth) | N/A | N/A |
| Backend Redis | `/api/today` response | 2 min | New fetch overwrites |
| Backend Redis | `/api/today/macro-balance` | 2 min | New fetch overwrites |
| Backend Redis | `/api/week/:date` | 10 min | New fetch overwrites |
| iOS SwiftData | `DailySnapshot` nutrition fields | Permanent | Overwritten on each sync |
| iOS in-memory | `NutriTrackService.cachedToday` | Until next sync | Any nutrition update |

---

### 3.4 Calendar (EventKit) Integration

#### Data Flow (Read-Only)

```
    Apple Calendar (System)              CalendarService                  Tempo Modules
    ───────────────────────             ───────────────                  ─────────────
    User's calendars                     fetchUpcomingEvents()
    - University schedule                (3-week window)
    - Football practice                          │
    - Exam dates                                 │
    - Personal events                            ▼
            │                            categorize(event)
            │                            ┌─────────────┐
            │ EventKit API               │ Categories:  │
            └───────────────────────────►│ .lecture     │──► Training: avoid scheduling on
                                         │ .exam        │    football days, reduce volume
                                         │ .football    │    before exams
                                         │ .social      │
                                         │ .work        │──► Accountability: exam mode
                                         │ .other       │    detection, study targets
                                         └─────────────┘
```

**Calendar categorization keywords:**

| Category | Keywords (title/location/notes) |
|---|---|
| Exam | "exam", "esame", "test", "final", "midterm", "appello" |
| Lecture | "lecture", "lezione", "class", "corso", "lab", "tutorial" |
| Football | "football", "calcio", "soccer", "training", "match", "partita" |
| Social | "dinner", "party", "birthday", "aperitivo", "bar" |

**No outbound flow.** Tempo reads the calendar but never writes to it.

---

## 4. Real-Time Data Flows

### 4.1 Active Workout Flow

```
    Time  Event                     Data Path
    ────  ─────                     ─────────
    0:00  User taps "Start Workout"
          │
          ├──► SwiftData: WorkoutPlan.status = .inProgress
          ├──► HealthKit: Start HKWorkoutSession
          ├──► HealthKit: Begin HKAnchoredObjectQuery (live HR)
          └──► Live Activity: Create workout activity (lock screen)

    0:01  First HR sample arrives
          │
          HealthKit ──► HealthKitService.observeHeartRate() callback
                        ──► ActiveWorkoutViewModel.currentHR = 142
                        ──► UI: Heart rate display updates (< 300ms)

    0:05  User completes Set 1 (80kg x 8 reps)
          │
          ├──► SwiftData: PlannedSet.actualWeight = 80, .actualReps = 8, .isCompleted = true
          ├──► SwiftData: ExerciseHistory append (for progressive overload)
          ├──► PR Detection: Compare vs ExerciseHistory → no PR
          ├──► Haptic: .success
          ├──► Rest Timer: Start (90 seconds)
          └──► UI: Set row slides to "completed" state

    0:45  PR Detected! (New 1RM on bench press)
          │
          ├──► SwiftData: PersonalRecord created (type: .oneRepMax, weight: 95.2kg estimated)
          ├──► Haptic: .success x3 rapid + delay + .success x2
          ├──► Animation: Gold confetti burst (2000ms)
          ├──► XPEvent: +75 XP created locally
          └──► UI: PR badge pops onto exercise card

    1:15  User taps "Finish Workout"
          │
          ├──► HealthKit: End HKWorkoutSession
          ├──► HealthKit: HKWorkoutBuilder.finishWorkout()
          │    (workout + energy + HR samples saved to HealthKit)
          ├──► SwiftData: WorkoutPlan.status = .completed
          ├──► SwiftData: DailySnapshot.workoutCompleted = true
          ├──► SwiftData: XPEvent +100 (workout) + +50 (green recovery) + +30 (heavy)
          ├──► Live Activity: End
          ├──► PendingSync: Queue workout data for backend upload
          └──► UI: Workout summary screen

    1:16  Background sync fires
          │
          ├──► Backend: POST /v1/sync/batch (workout + XP events)
          ├──► Backend: Processes XP → updates user.xp_total, checks level-up
          ├──► Backend: Checks achievements (e.g., "100 workouts")
          ├──► Backend: Updates leaderboard materialized view
          └──► WebSocket: Sends xp.earned to connected friends
                          Sends leaderboard.update if rank changed

    1:17  Friend receives WebSocket event
          │
          └──► Friend's iOS: leaderboard.update → UI refresh
               (If friend was ahead and is now behind → push notification)
```

### 4.2 Focus Timer Flow

```
    Time  Event                     Data Path
    ────  ─────                     ─────────
    0:00  User taps "Start Study Timer" (25 min Pomodoro)
          │
          ├──► SwiftData: StudySession created (status: .active, startedAt: now)
          ├──► Live Activity: Create focus timer activity
          ├──► Haptic: .heavy
          └──► UI: Timer countdown begins

    Every 1s  Timer tick
          │
          ├──► Local state: remainingSeconds -= 1
          ├──► Live Activity: Update progress (every 60s to save battery)
          └──► Accountability: Update studyMinutes in DailySnapshot

    15:00  Study NN threshold reached (e.g., 30 min target)
          │
          ├──► SwiftData: NonNegotiableProgress.isCompleted = true
          ├──► SwiftData: DailySnapshot.nonNegotiablesCompleted += 1
          ├──► XPEvent: +10 (study NN complete)
          ├──► PS5 Gate Check: Are all required NNs done? → Update leisure status
          └──► Haptic: .success (if NN completed)

    25:00  Pomodoro complete
          │
          ├──► SwiftData: StudySession.endedAt = now, .durationMinutes = 25
          ├──► XPEvent: +30 (study session)
          ├──► Live Activity: End
          ├──► Haptic: .success + .rigid
          ├──► Notification: "Session complete. 5 min break, then back at it."
          └──► UI: Break timer starts (5 min)
```

### 4.3 Whoop Webhook Flow (Recovery Update)

```
    Time  Event                     Data Path
    ────  ─────                     ─────────
    T+0   Whoop strap detects user woke up
          Whoop cloud calculates recovery score

    T+5m  Whoop sends webhook to Tempo
          │
          POST https://api.tempo.app/v1/webhooks/whoop
          Headers: X-Whoop-Signature, X-Whoop-Timestamp
          Body: { type: "recovery.updated", user_id: 12345, id: 123456789 }
          │
          ├──► Backend: Verify HMAC-SHA256 signature
          ├──► Backend: Check replay (timestamp < 5 min old)
          ├──► Backend: Dedup check (trace_id in Redis, 24h TTL)
          ├──► Backend: Return 200 OK immediately
          └──► Backend: Enqueue WhoopWebhookJob

    T+5.5m  Background job processes
          │
          ├──► Backend: Get valid access token (refresh if needed)
          ├──► Backend: GET Whoop recovery API (last 3 days)
          ├──► Backend: Upsert into whoop_recovery table (compare updated_at)
          ├──► Backend: Cache in Redis (120s TTL)
          ├──► Backend: Send visible push notification
          │    { title: "Good morning! Recovery: 78%",
          │      body: "You're in the green. Time to push it.",
          │      deep_link: "tempo://recovery/2026-03-24" }
          └──► Backend: Send silent push { type: "whoop_recovery_updated" }

    T+6m  iOS receives push notifications
          │
          ├──► (If app in foreground) Silent push triggers API fetch
          │    GET /v1/whoop/recovery → parse → save to SwiftData DailyRecovery
          │    → DailySnapshot.recoveryScore updated
          │    → Dashboard BODY quadrant re-renders
          │    → Recovery module prescription recalculated
          │    → Training module adjusts today's workout
          │
          └──► (If app in background) Visible push appears on lock screen
               User taps → deep link → Recovery Today View opens
```

---

## 5. Daily Data Lifecycle

A complete hour-by-hour view of how data flows through a typical weekday.

```
    TIME     EVENT                                    DATA FLOW
    ────     ─────                                    ─────────

    05:00    [Backend] Reconciliation cron             Backend fetches 3-day history from
             (3 AM UTC = 5 AM CET)                    Whoop API for all users. Upserts
                                                      recovery, sleep, workouts, cycles.

    06:30    [Whoop] User wakes up                    Whoop strap → Whoop app (BLE sync)
             Recovery score calculated                 → Whoop cloud → webhook to backend.

    06:35    [Backend] Webhook received               Backend fetches recovery (78%), sleep
             recovery.updated                          (7.2h, 88% performance), stores in PG.
                                                      Sends push: "Recovery: 78% — green."

    06:36    [iOS] Push notification delivered         Notification appears on lock screen.
                                                      Silent push wakes HealthKit observers.

    07:00    [iOS] User opens Tempo                   App enters foreground. SyncService:
                                                      1. GET /v1/whoop/recovery → DailyRecovery
                                                      2. GET /v1/nutritrack/today → nutrition
                                                      3. HealthKit.fetchTodaySteps() → 0
                                                      4. HealthKit.fetchSleep() → (Whoop wins)
                                                      5. EventKit.fetchUpcomingEvents() → calendar
                                                      All 5 fetches run in parallel (async let).
                                                      DailySnapshot created/updated.
                                                      Dashboard renders 4 quadrants.

    07:15    [iOS] User checks Recovery tab           RecoverIQ loads DailyRecovery.
                                                      Prescription generated:
                                                      - "Green zone. Full training today."
                                                      - "Sleep: 7.2h vs 8h target. Aim earlier."
                                                      7-day trend sparklines from SwiftData.

    08:00    [iOS] User starts gym workout            RepForge: WorkoutPlan loaded.
                                                      Recovery-adjusted (green = full volume).
                                                      HKWorkoutSession started.
                                                      HKAnchoredObjectQuery for live HR.
                                                      Live Activity created.

    08:05    [iOS] Set 1 completed                    ExerciseHistory appended to SwiftData.
             (Bench press: 80kg x 8)                   PR detection: no PR. Rest timer starts.

    08:45    [iOS] Workout finished                   HKWorkoutBuilder.finishWorkout() →
                                                      HealthKit gets workout + HR + energy.
                                                      DailySnapshot.workoutCompleted = true.
                                                      XPEvents: +100 workout + +50 green recovery
                                                      + +30 heavy intensity = +180 XP.
                                                      Accountability: "Train" NN auto-completed.
                                                      PendingSync: workout queued for backend.

    08:46    [iOS→Backend] Sync fires                 POST /v1/sync/batch with workout + XP.
                                                      Backend: xp_total updated, level check,
                                                      achievement check, leaderboard refresh.

    08:47    [Whoop] Workout detected                 Whoop webhook: workout.updated.
             (Whoop also tracked the gym session)     Backend fetches workout strain (12.5).
                                                      DailySnapshot.strain updated.
                                                      Dedup: 80% time overlap with RepForge
                                                      workout → same workout, merge strain data.

    09:00    [HealthKit] Steps observer fires         HealthKit background delivery: 2,400 steps.
                                                      DailySnapshot.steps = 2400.

    09:30    [NutriTrack] User logs breakfast          NutriTrack Flask records meal.
             in NutriTrack web app                     (Tempo doesn't know yet — no webhook.)

    09:45    [iOS] 15-min NutriTrack poll             GET /v1/nutritrack/today →
                                                      mealsLogged went from 0 to 1.
                                                      DailySnapshot.mealsLogged = 1.
                                                      DailySnapshot.caloriesConsumed = 520.
                                                      Write meal to HealthKit (HKCorrelation).
                                                      XPEvent: +15 (log breakfast before 11).

    10:00    [iOS] User starts study timer            Accountability: StudySession created.
             (25 min Pomodoro)                         Live Activity shows timer.

    10:25    [iOS] Pomodoro complete                  StudySession saved (25 min).
                                                      DailySnapshot.studyMinutes += 25.
                                                      XPEvent: +30 (study session).
                                                      Break timer starts (5 min).

    11:30    [iOS] Study target reached (120 min)     DailySnapshot.studyMinutes = 120.
             After 4 Pomodoro sessions                 Study NN auto-completed.
                                                      XPEvent: +10 (study NN).
                                                      XPEvent: +80 (hit daily study target).

    12:15    [NutriTrack] Lunch logged                Next poll at 12:30 detects new meal.
                                                      mealsLogged = 2. Macros updated.
                                                      HealthKit write for lunch nutrition.
                                                      XPEvent: +15 (log lunch before 15:00).

    13:00    [HealthKit] Steps observer               Steps = 6,200. XPEvent: +20 (5K tier).
                                                      DailySnapshot.steps = 6200.

    14:00    [Whoop] Cycle strain updates             Backend poll: strain now 10.8.
                                                      DailySnapshot.strain = 10.8.

    15:00    [HealthKit] Steps observer               Steps = 8,500. XPEvent: +35 (8K tier,
                                                      replaces 5K reward — net +15).

    18:30    [NutriTrack] Dinner logged               Poll detects meal 3.
                                                      mealsLogged = 3. All meals target hit!
                                                      Meals NN auto-completed.
                                                      XPEvent: +15 (dinner) + +10 (meals NN).

    19:00    [iOS] All required NNs complete           PS5 Gate: train ✓, study ✓, meals ✓,
             (train + study + meals)                    recovery ✓ (checked this morning).
                                                      "PS5 EARNED!" — lock icon unlocks.
                                                      XPEvent: +60 (all NNs complete).
                                                      Haptic: .success x3.

    20:00    [HealthKit] Steps observer               Steps = 10,200. XPEvent: +50 (10K tier,
                                                      replaces 8K — net +15).

    21:00    [Backend] Leaderboard refresh            Materialized view refreshes.
                                                      User moved from #3 to #2 this week.
                                                      WebSocket: leaderboard.update to friends.
                                                      Push to friend who was #2:
                                                      "Nicola just passed you! +40 XP to reclaim."

    22:30    [iOS] Bedtime approaching                Backend cron checks bedtime target (23:00).
                                                      30-min warning push: "Wind down.
                                                      Tomorrow's recovery depends on tonight."

    23:30    [Backend] End-of-day XP calculation      Daily composite check:
                                                      - Workout ✓ Study ✓ Meals ✓ Sleep (pending)
                                                        NNs ✓ → Near-Perfect Day (+75 XP).
                                                      Total day XP: ~680 XP (before multipliers).

    23:59    [Backend] Day rollover                   DailySnapshot finalized.
                                                      Streak checked: day 15 continues.
                                                      POST /v1/sync/batch: final snapshot upload.
                                                      Tomorrow's DailySnapshot created (empty).

    00:30    [Whoop] Sleep starts                     Whoop begins tracking sleep.
                                                      No data flows until wake-up.
```

---

## 6. Sync Architecture

### 6.1 App Launch Sync Sequence

```
    iOS App                              Backend                         External
    ───────                              ───────                         ────────
    │
    │  scenePhase == .active
    │
    ├──► Check network (NWPathMonitor)
    │    If offline → show cached data + offline banner
    │    If online ↓
    │
    ├──► [Parallel] ─────────────────────────────────────────────────────────────
    │    │
    │    ├──► GET /v1/sync/status ───────► Returns last_sync timestamps ──────►│
    │    │                                  for all data types                  │
    │    ├──► GET /v1/whoop/recovery ────► Redis cache hit (120s) ─────────────►│
    │    │    (if Whoop connected)          or fetch from PG                    │
    │    │                                                                     │
    │    ├──► GET /v1/nutritrack/today ──► Redis cache hit (2min) ─────────────►│
    │    │    (if NutriTrack connected)     or proxy to NutriTrack Flask        │
    │    │                                                                     │
    │    ├──► HealthKit.fetchTodaySteps() ──► Local HealthKit DB ──────────────►│
    │    │                                                                     │
    │    ├──► HealthKit.fetchTodayActiveEnergy() ──► Local ──────────────────►│
    │    │                                                                     │
    │    ├──► HealthKit.fetchSleep(for: today) ──► Local ──────────────────────►│
    │    │                                                                     │
    │    └──► CalendarService.fetchUpcomingEvents() ──► EventKit ──────────────►│
    │                                                                          │
    ├──► [Sequential after parallel completes] ────────────────────────────────┘
    │    │
    │    ├──► Merge all data into DailySnapshot
    │    ├──► Calculate dailyScore
    │    ├──► Save to SwiftData
    │    ├──► Check for pending PendingSync items
    │    │    If any → POST /v1/sync/batch ──► Backend processes
    │    └──► Update UI (Dashboard, Accountability, etc.)
    │
    └──► Schedule next background sync (BGAppRefreshTask, 15 min)
```

### 6.2 Background Sync Sequence

```
    System wakes app for BGAppRefreshTask
    │
    ├──► HealthKit batch query:
    │    async let steps, energy, sleep = fetch...
    │    → Update DailySnapshot
    │
    ├──► Check PendingSync queue:
    │    If items → POST /v1/sync/batch
    │    On success → clear PendingSync items
    │    On failure → keep in queue, increment retryCount
    │
    ├──► NutriTrack poll (lightweight):
    │    GET /v1/nutritrack/today
    │    Compare meals_logged with cached → detect changes
    │
    └──► Schedule next BGAppRefreshTask (15 min)
         task.setTaskCompleted(success: true)
```

### 6.3 Webhook-Triggered Sync

```
    Whoop Server ──webhook──► Tempo Backend ──silent push──► iOS App
                                    │
                                    ├── Process webhook (verify, dedup, enqueue)
                                    ├── Background job fetches Whoop data
                                    ├── Stores in PostgreSQL
                                    ├── Caches in Redis
                                    └── Sends silent push to iOS
                                              │
                                              ▼
                                    iOS receives silent push
                                    ├── If app in foreground:
                                    │   Fetch latest data from backend
                                    │   Update SwiftData + UI
                                    └── If app in background:
                                        Schedule fetch for next foreground
```

### 6.4 Pull-to-Refresh Sync

```
    User pulls down on Dashboard
    │
    ├──► Same parallel fetch as App Launch Sync
    │    (but all caches bypassed — force fresh)
    │
    ├──► Backend: If data < 5 min old, return cached
    │    (NutriTrack: skip if last sync < 3 min ago)
    │
    ├──► Merge + save + UI update
    │
    └──► Animation: recovery ring spins, then settles
```

### 6.5 Conflict Resolution Decision Tree

```
    Data arrives from two sources for the same record
    │
    ├──► Same entity? (matched by ID or time overlap > 50%)
    │    │
    │    ├──► YES: Compare updated_at timestamps
    │    │    │
    │    │    ├──► Remote newer → overwrite local
    │    │    ├──► Local newer → keep local, queue for upload
    │    │    └──► Same time → remote wins (server is authority)
    │    │
    │    └──► NO: Both records are kept (different entities)
    │
    ├──► Whoop vs HealthKit overlap?
    │    │
    │    ├──► Recovery/HRV/RHR: Whoop API always wins
    │    ├──► Sleep: Whoop API wins (richer data)
    │    ├──► Steps: HealthKit always wins (Apple pedometer)
    │    ├──► Workout: Check time overlap
    │    │    └──► > 50% overlap → merge (RepForge details + Whoop strain)
    │    └──► Active energy: HealthKit always wins
    │
    └──► Backend vs Local conflict?
         │
         ├──► User-created data (workouts, study): local wins, upload to backend
         ├──► Integration data (Whoop, NutriTrack): backend wins, overwrite local
         └──► Social data (XP, leaderboard, friends): backend always wins
```

### 6.6 Offline Queue Processing

```
    ┌──────────────────────────────────┐
    │  PendingSync Queue (SwiftData)   │
    │                                  │
    │  id: UUID                        │
    │  entityType: String              │  ("workout", "study_session", "xp_event",
    │  entityId: UUID                  │   "snapshot", "accountability")
    │  action: SyncAction              │  (.create, .update, .delete)
    │  payload: Data (JSON)            │
    │  createdAt: Date                 │
    │  retryCount: Int                 │
    │  lastAttempt: Date?              │
    │  error: String?                  │
    └──────────────────────────────────┘

    Processing rules:
    1. On every sync opportunity (foreground, background, pull-to-refresh):
       a. Fetch all PendingSync items ordered by createdAt ASC
       b. Batch into POST /v1/sync/batch (max 50 items per request)
       c. On success: delete PendingSync items
       d. On partial success: delete succeeded, keep failed
       e. On network error: increment retryCount, set lastAttempt
    2. Retry backoff: 1min, 5min, 15min, 1hr, 6hr
    3. Max retries: 10 (then mark as permanently failed, surface to user)
    4. Idempotency: each PendingSync generates a stable Idempotency-Key
       from (entityType + entityId + action), so retries are safe
```

---

## 7. Data Aggregation Pipelines

### 7.1 Daily Snapshot Aggregation

```
    Individual Data Points                           DailySnapshot
    ──────────────────────                           ─────────────

    Whoop recovery webhook ──────────────────────┐
    Whoop sleep webhook ─────────────────────────┤
    Whoop cycle poll ────────────────────────────┤
                                                 │
    NutriTrack /api/today poll ──────────────────┤
                                                 ├──► DailySnapshot
    HealthKit steps observer ────────────────────┤    (1 per day per user)
    HealthKit active energy observer ────────────┤    Saved to SwiftData
    HealthKit sleep observer ────────────────────┤    on every data change
                                                 │
    RepForge workout completion ─────────────────┤
    Accountability NN completions ───────────────┤
    StudySession timer stops ────────────────────┘

    Aggregation trigger: Any data source update
    Frequency: Potentially dozens of times per day
    Storage: Upsert by date (1 row per calendar day)
```

### 7.2 Weekly Report Generation

```
    Input                          Processing                        Output
    ─────                          ──────────                        ──────

    7 DailySnapshots ────────────►  Backend job                      WeeklyReport
    (Mon-Sun)                       POST /v1/insights/weekly         (cached forever)
                                    │
                                    ├── Collect: 7 snapshots
                                    ├── Calculate averages:
                                    │   - recovery avg, sleep avg
                                    │   - workout count, total strain
                                    │   - calorie/macro adherence
                                    │   - study hours, NN compliance
                                    │   - XP earned, streak status
                                    ├── Compare vs prior week
                                    ├── Build Claude prompt:
                                    │   (no PII, only metrics)
                                    │   - System: "You are a performance coach..."
                                    │   - User: aggregated weekly stats
                                    ├── Call Claude API (sonnet 4):
                                    │   max 2000 output tokens
                                    │   $0.003-0.01 per report
                                    ├── Parse sections + action items
                                    └── Store in insights table
                                        Cache key: insight:{user_id}:weekly:{week_start}

    Trigger: Sunday 20:00 user's timezone (background job)
    Also: on-demand via POST /v1/insights/weekly
    Rate limit: 3 per day per user
```

### 7.3 Pattern Detection Pipeline

```
    Input                          Processing                        Output
    ─────                          ──────────                        ──────

    30-90 DailySnapshots ────────►  Backend job                      RecoveryInsight
    (user-selected range)           POST /v1/insights/pattern        (stored in PG)
                                    │
                                    ├── Collect snapshots for range
                                    ├── Calculate correlations:
                                    │   - sleep hours vs next-day recovery
                                    │   - strain vs next-day HRV
                                    │   - protein intake vs recovery
                                    │   - study hours vs sleep quality
                                    │   - late bedtime vs recovery drop
                                    ├── Build Claude prompt with
                                    │   correlation matrix + user question
                                    ├── Call Claude API
                                    └── Parse into RecoveryInsight model
                                        { type: .correlation,
                                          title: "Sleep timing drives recovery",
                                          body: "When you sleep before 23:00..." }

    Trigger: User asks question in Recovery Trends view
    Rate limit: 5 per day per user
    Monthly budget: $50 total across all users
```

### 7.4 XP Calculation Pipeline

```
    Module Event                    ScoringEngine                      Outputs
    ────────────                    ─────────────                      ───────

    workout.completed ──────────►  ┌─────────────────┐
    study.session_ended ─────────► │  Calculate base  │  ──► XPEvent (SwiftData)
    meal.logged ─────────────────► │  XP from rules   │      { source: .workout,
    sleep.logged ────────────────► │  table            │        amount: 100,
    steps.threshold_crossed ─────► │                   │        multiplier: 1.5,
    nn.completed ────────────────► │  Apply streak     │        finalAmount: 150,
    nn.all_completed ────────────► │  multiplier:      │        earnedAt: Date() }
    perfect_day.achieved ────────► │  3-6 days: 1.1x  │
                                   │  7-13 days: 1.25x│  ──► Backend /v1/xp/events
                                   │  14-29 days: 1.5x│      (batched in /v1/sync/batch)
                                   │  30+ days: 2.0x  │
                                   │                   │  ──► users.xp_total updated
                                   │  Check daily caps │      Level check:
                                   │  Check anti-farm  │      if xp_total >= next_level_xp
                                   │  rules            │      → level_up event
                                   └─────────────────┘
                                                          ──► Achievement check
                                                              POST /v1/achievements/check
                                                              → scan criteria_json
                                                              → award if met

                                                          ──► Leaderboard update
                                                              Materialized view refresh
                                                              (every 5 min)
                                                              WebSocket push if rank changed
```

---

## 8. Notification Data Flow

### 8.1 Complete Notification Pipeline

```
    EVENT OCCURS
    │
    ▼
    ┌───────────────────────────────────────────────────┐
    │  NOTIFICATION DECISION ENGINE                      │
    │                                                    │
    │  1. Should we notify?                              │
    │     ├── User notification preferences check        │
    │     ├── Quiet hours check (sleep time)             │
    │     ├── Duplicate suppression (same type < 1hr)    │
    │     └── Rate limit (max 8 pushes/day)              │
    │                                                    │
    │  2. Which tier / intensity?                         │
    │     ├── User setting: 1=gentle, 2=firm, 3=drill    │
    │     └── Event urgency: low/medium/high              │
    │                                                    │
    │  3. Which copy?                                     │
    │     ├── Drill sergeant personality if intensity=3   │
    │     ├── Random from copy pool (avoid repetition)    │
    │     └── Personalized with user data                 │
    │                                                    │
    │  4. Local or Push?                                  │
    │     ├── App in foreground → in-app banner (local)   │
    │     └── App in background → APNs push               │
    └─────────────────────┬─────────────────────────────┘
                          │
            ┌─────────────┼─────────────┐
            ▼                           ▼
    LOCAL NOTIFICATION              PUSH NOTIFICATION
    (UNUserNotificationCenter)      (APNs via Backend)
    │                               │
    │  UNMutableNotificationContent │  Backend constructs APNs payload:
    │  - title, subtitle, body      │  { aps: { alert, sound, badge,
    │  - sound (.caf file)          │          category, thread-id },
    │  - categoryIdentifier         │    tempo: { type, data, deep_link } }
    │  - threadIdentifier           │
    │  - userInfo (deep link)       │  Backend sends via APNs HTTP/2:
    │                               │  POST api.push.apple.com/3/device/{token}
    │  UNNotificationRequest        │
    │  - trigger: .timeInterval     │  Delivery:
    │    or .calendar               │  - Standard priority for info
    │                               │  - High priority for time-sensitive
    └───────────┬───────────────────┘
                │
                ▼
    USER INTERACTION
    │
    ├──► Notification tap
    │    ├── Extract deep_link from userInfo / tempo payload
    │    ├── Parse URL: tempo://recovery/2026-03-24
    │    ├── Route to correct tab + screen
    │    └── Load specific date's data
    │
    ├──► Notification action button
    │    ├── "Start Workout" → Training tab + today's workout
    │    ├── "Log Meal" → Deep link to NutriTrack
    │    └── "Snooze 30m" → Reschedule local notification
    │
    └──► Dismiss (no action tracked)
```

### 8.2 Notification Types and Triggers

| Type | Source | Delivery | Trigger | Deep Link |
|---|---|---|---|---|
| `recovery_morning` | Whoop webhook | APNs push | recovery.updated event | `tempo://recovery/{date}` |
| `accountability_tier1` | Backend cron | APNs push | 2h after wake time | `tempo://accountability` |
| `accountability_tier2` | Backend cron | APNs push | 4h after wake time | `tempo://accountability` |
| `accountability_tier3` | Backend cron | APNs push | 3h before midnight | `tempo://accountability` |
| `accountability_tier4` | Backend cron | APNs push | 00:01 user's TZ | `tempo://accountability` |
| `leaderboard_change` | Leaderboard refresh | APNs push | Rank change detected | `tempo://arena/leaderboard` |
| `challenge_invite` | Challenge creation | APNs push | Immediate | `tempo://arena/challenges/{id}` |
| `challenge_update` | Backend cron | APNs push | 24h and 1h before end | `tempo://arena/challenges/{id}` |
| `achievement_unlock` | Achievement check | APNs push | Immediate | `tempo://arena/achievements` |
| `weekly_summary` | Backend cron | APNs push | Sunday 20:00 user TZ | `tempo://dashboard/weekly` |
| `bedtime_reminder` | Local schedule | UNNotification | 30 min before bedtime target | `tempo://recovery` |
| `whoop_disconnected` | Token refresh failure | APNs push | Refresh token revoked | `tempo://settings/integrations` |
| `nutritrack_auth_failed` | Proxy 401 detection | APNs push | PIN expired | `tempo://settings/integrations` |

---

## 9. Data Deletion Flow (GDPR)

### Complete Deletion Sequence

```
    ┌─────────────────────────────────────────────────────────────────────┐
    │  USER REQUESTS DELETION                                             │
    │  (Settings → Account → Delete Account)                              │
    └────────────────────┬────────────────────────────────────────────────┘
                         │
                         ▼
    ┌─────────────────────────────────────────────────────────────────────┐
    │  iOS APP                                                            │
    │  1. Confirm dialog: "This will permanently delete all your data.    │
    │     You have 7 days to change your mind."                           │
    │  2. POST /v1/users/me/delete                                        │
    │  3. Receive confirmation + cooling-off period end date               │
    │  4. Sign out locally                                                 │
    └────────────────────┬────────────────────────────────────────────────┘
                         │
                         ▼
    ┌─────────────────────────────────────────────────────────────────────┐
    │  BACKEND: MARK FOR DELETION (Day 0)                                 │
    │                                                                     │
    │  - users.deleted_at = NOW()                                         │
    │  - Revoke all refresh tokens                                        │
    │  - Invalidate all Redis sessions                                    │
    │  - Stop all background jobs for user                                │
    │  - Stop Whoop webhook processing                                    │
    │  - Stop NutriTrack polling                                          │
    │  - Return 401 on all subsequent authenticated requests              │
    │  - User can POST /v1/auth/recover within 7 days to cancel           │
    └────────────────────┬────────────────────────────────────────────────┘
                         │
                         │  7-day cooling-off period
                         │
                         ▼
    ┌─────────────────────────────────────────────────────────────────────┐
    │  BACKEND: PERMANENT DELETION (Day 7 — background job)               │
    │                                                                     │
    │  PostgreSQL (CASCADE from users table):                             │
    │  ├── users row                                                      │
    │  ├── user_preferences                                               │
    │  ├── refresh_tokens                                                 │
    │  ├── apple_auth                                                     │
    │  ├── whoop_integrations (encrypted tokens destroyed)                │
    │  ├── whoop_recovery, whoop_sleep, whoop_workouts, whoop_cycles     │
    │  ├── nutritrack_integrations (encrypted PIN destroyed)              │
    │  ├── daily_snapshots (all partitions)                               │
    │  ├── manual_workouts                                                │
    │  ├── study_sessions                                                 │
    │  ├── xp_events                                                      │
    │  ├── user_achievements                                              │
    │  ├── challenge_participants (+ challenge_daily_scores)              │
    │  ├── friendships                                                    │
    │  ├── friend_requests                                                │
    │  ├── device_tokens                                                  │
    │  └── insights                                                       │
    │                                                                     │
    │  Redis:                                                             │
    │  ├── All keys matching user_id pattern                              │
    │  ├── Rate limit counters                                            │
    │  ├── Cached responses                                               │
    │  └── Idempotency keys                                               │
    │                                                                     │
    │  S3:                                                                │
    │  ├── Avatar images (avatars/usr_abc123def456_*.webp)               │
    │  └── Generated reports (reports/usr_abc123def456_*.json)           │
    │                                                                     │
    │  Third-party:                                                       │
    │  ├── Whoop: Revoke OAuth token (POST .../oauth2/revoke)            │
    │  ├── NutriTrack: No action needed (PIN-based, no permanent link)   │
    │  └── PostHog: Call deletion API for user's distinct_id              │
    └────────────────────┬────────────────────────────────────────────────┘
                         │
                         ▼
    ┌─────────────────────────────────────────────────────────────────────┐
    │  iOS APP: LOCAL CLEANUP (on next launch if account deleted)          │
    │                                                                     │
    │  SwiftData:                                                         │
    │  └── Delete entire ModelContainer (TempoStore)                      │
    │                                                                     │
    │  Keychain:                                                          │
    │  ├── JWT access token                                               │
    │  ├── JWT refresh token                                              │
    │  └── Device UUID                                                    │
    │                                                                     │
    │  UserDefaults:                                                      │
    │  └── Clear all keys in app group (group.app.tempo)                  │
    │                                                                     │
    │  FileManager:                                                       │
    │  └── Clear caches directory                                         │
    │                                                                     │
    │  HealthKit:                                                         │
    │  └── CANNOT DELETE. Apple controls HealthKit data.                   │
    │      Data written by Tempo persists in Apple Health.                 │
    │      User must manually delete in Health app if desired.             │
    │                                                                     │
    │  EventKit:                                                          │
    │  └── No data to delete (read-only integration).                     │
    └─────────────────────────────────────────────────────────────────────┘
```

---

## 10. Data Size Estimates

### Per-Record Sizes

| Data Type | Size Per Record | Records Per Day | Records Per Week | Records Per Month |
|---|---|---|---|---|
| DailySnapshot | ~2 KB | 1 | 7 | 30 |
| DailyRecovery | ~500 B | 1 | 7 | 30 |
| SleepRecord (main) | ~800 B | 1 | 7 | 30 |
| SleepRecord (nap) | ~400 B | 0-2 | 0-14 | 0-60 |
| WorkoutPlan | ~3 KB | 0-1 | 3-5 | 15-20 |
| PlannedExercise | ~500 B | 0-8 | 15-40 | 60-160 |
| PlannedSet | ~200 B | 0-32 | 60-160 | 250-650 |
| ExerciseHistory | ~300 B | 0-32 | 60-160 | 250-650 |
| PersonalRecord | ~200 B | 0-3 | 0-10 | 0-30 |
| StudySession | ~300 B | 2-6 | 10-30 | 40-120 |
| NonNegotiableProgress | ~200 B | 4-6 | 28-42 | 120-180 |
| DailyAccountability | ~1 KB | 1 | 7 | 30 |
| XPEvent | ~200 B | 10-25 | 70-175 | 300-750 |
| Achievement (earned) | ~300 B | 0-2 | 0-5 | 0-15 |
| RecoveryInsight | ~1 KB | 0-1 | 1-3 | 4-12 |
| PendingSync | ~500 B | Transient | -- | -- |
| ChallengeLocal | ~1 KB | 0 | 0-2 | 0-5 |

### Storage Projections

#### iOS Local Storage (SwiftData)

| Time Period | Estimated Size | Notes |
|---|---|---|
| 1 day | ~25-40 KB | All models for one active day |
| 1 week | ~175-280 KB | 7 days of full data |
| 1 month | ~750 KB - 1.2 MB | 30 days of full data |
| 6 months | ~4.5-7 MB | Normal growth |
| 1 year | ~9-14 MB | Before any cleanup |
| 1 year (with exercise library) | ~12-18 MB | 150+ exercise definitions cached |

**Cleanup thresholds:**

| Trigger | Action |
|---|---|
| App storage > 50 MB | Archive DailySnapshots older than 90 days (keep summary row, delete detail) |
| Exercise history > 1 year old | Aggregate to monthly summaries, delete individual sets |
| PendingSync items > 10 days old | Mark as permanently failed, notify user |
| RecoveryInsights > 6 months old | Delete (re-generatable from snapshots) |

#### Backend Storage (PostgreSQL, per user)

| Time Period | Estimated Size | Notes |
|---|---|---|
| 1 day | ~10-15 KB | Snapshots + Whoop data + events |
| 1 month | ~300-450 KB | Full month with all integrations |
| 6 months | ~1.8-2.7 MB | Normal growth |
| 1 year | ~3.5-5.5 MB | Before partitioned cleanup |
| 1 year (with JSON columns) | ~5-8 MB | JSONB columns (exercises, preferences) |

**Partitioned cleanup:** `daily_snapshots` table is partitioned by quarter. Partitions older than 2 years can be archived to cold storage (S3) or dropped.

#### Backend Total Storage (at scale)

| Users | 1 Year Total (PG) | Redis Peak | S3 (avatars + reports) |
|---|---|---|---|
| 100 users | ~500 MB - 800 MB | ~50-100 MB | ~500 MB |
| 1,000 users | ~5-8 GB | ~200-500 MB | ~5 GB |
| 10,000 users | ~50-80 GB | ~1-3 GB | ~50 GB |

#### Growth Rate Indicators

| Metric | Daily Growth Per User | Annual Growth Per User |
|---|---|---|
| DailySnapshot rows | 1 | 365 |
| XPEvent rows | 10-25 | 3,650-9,125 |
| ExerciseHistory rows | 0-32 | 0-11,680 |
| StudySession rows | 2-6 | 730-2,190 |
| Whoop data rows (all types) | 3-5 | 1,095-1,825 |

#### When Archival Is Needed

| Data Type | Archive After | Reason |
|---|---|---|
| DailySnapshots (backend) | 2 years | Partition drop or S3 archive |
| ExerciseHistory (iOS) | 1 year | Aggregate to monthly PR summaries |
| XPEvents (iOS) | 6 months | Only totals matter for display; details for audit |
| XPEvents (backend) | 1 year | Aggregate to monthly totals |
| Whoop raw data (backend) | 1 year | Keep summary in DailySnapshot, drop raw |
| Insights (backend) | 6 months | Re-generatable from snapshots |
| PendingSync (iOS) | 30 days | Failed syncs are irrecoverable after a month |
| Redis cache | Self-expiring (TTL) | No manual cleanup needed |

---

## Quick Reference: "Where Does This Data Come From?"

| If you see this on screen... | It came from... | Via this path... |
|---|---|---|
| Recovery score "78%" | Whoop strap → cloud → webhook → backend → iOS | `DailySnapshot.recoveryScore` |
| HRV "65 ms" | Whoop strap (during sleep) → same as above | `DailySnapshot.hrv` |
| Sleep "7.2h" | Whoop strap → cloud → webhook → backend → iOS | `DailySnapshot.sleepHours` |
| Day strain "10.8" | Whoop strap → cloud → poll → backend → iOS | `DailySnapshot.strain` |
| Calories "1850 / 2400" | NutriTrack web app → Flask → backend proxy → iOS | `DailySnapshot.caloriesConsumed/Target` |
| Protein "145g" | Same as calories | `DailySnapshot.proteinActual` |
| Meals "2 / 3" | Same as calories (meal count) | `DailySnapshot.mealsLogged/Planned` |
| Study "90 / 120 min" | Focus timer on iOS (local) | `DailySnapshot.studyMinutes/Target` |
| Steps "8,500" | iPhone/Watch pedometer → HealthKit → iOS | `DailySnapshot.steps` |
| Active calories "420 kcal" | Apple Watch → HealthKit → iOS | `DailySnapshot.activeCalories` |
| Workout "Push Day - Done" | RepForge module (local) + HealthKit write | `DailySnapshot.workoutCompleted` |
| XP "680 today" | All modules → ScoringEngine → XPEvent | Sum of `XPEvent.finalAmount` for today |
| Level "8 - Optimizer" | Backend `users.xp_total` → level thresholds | `/v1/xp/level` |
| Leaderboard rank "#2" | Backend materialized view, refreshed every 5 min | `/v1/leaderboard/weekly` |
| Weekly insight | Backend → Claude API → `insights` table | `/v1/insights/weekly` |
| Calendar conflicts | Apple Calendar → EventKit API (local) | `CalendarService.fetchUpcomingEvents()` |
| "PS5 Earned!" | Accountability module (local NN completion check) | All required NNs `.isCompleted == true` |
