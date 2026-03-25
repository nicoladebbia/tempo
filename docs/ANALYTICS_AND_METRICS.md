# Tempo -- Analytics and Metrics Specification

**Version:** 1.0
**Last Updated:** 2026-03-24
**Author:** Growth & Analytics Specification
**App:** Tempo (iOS, SwiftUI)

> This document is the authoritative reference for all analytics instrumentation, business metrics, event tracking, funnel definitions, cohort analysis, A/B testing, and privacy compliance. A developer should be able to implement complete analytics tracking from this document alone without asking any questions.

---

## Table of Contents

1. [Analytics Architecture](#1-analytics-architecture)
2. [Core Business Metrics (KPIs)](#2-core-business-metrics-kpis)
3. [Event Catalog](#3-event-catalog)
4. [Funnel Definitions](#4-funnel-definitions)
5. [Cohort Analysis Definitions](#5-cohort-analysis-definitions)
6. [A/B Testing Framework](#6-ab-testing-framework)
7. [Dashboard for Metrics](#7-dashboard-for-metrics)
8. [User Segmentation](#8-user-segmentation)
9. [Privacy Compliance for Analytics](#9-privacy-compliance-for-analytics)

---

# 1. Analytics Architecture

## 1.1 Recommended Platform: PostHog (Self-Hosted or Cloud)

**Primary:** PostHog
**Secondary (crash/performance only):** Firebase Crashlytics

### Why PostHog Over Alternatives

| Criteria | PostHog | Mixpanel | Firebase Analytics | Amplitude |
|---|---|---|---|---|
| **Privacy control** | Self-hostable, EU data residency, full data ownership | Cloud only, US data centers | Google ecosystem, data shared with Google | Cloud only |
| **Cost at scale** | Free tier generous (1M events/mo cloud; unlimited self-hosted) | Expensive above 100K MTUs | Free but limited custom events (500 types) | Expensive above 10M events |
| **Feature flags / A/B testing** | Built-in, no extra tool needed | Requires separate tool | Requires Firebase Remote Config (limited) | Built-in but expensive |
| **Session replay** | Built-in (iOS SDK supports it) | Not available | Not available | Requires Digital Analytics add-on |
| **Funnels / retention / cohorts** | All built-in | All built-in | Basic, requires BigQuery export for depth | All built-in |
| **Health app suitability** | Full data control = easier HIPAA/GDPR story | Possible but harder to audit | Google data processing raises red flags for health apps | Possible but cloud-only |
| **iOS SDK** | Mature Swift SDK (`posthog-ios`) | Mature | Mature | Mature |

**Decision:** PostHog gives us feature flags, session replay, funnels, retention, and cohort analysis in one tool while keeping user data under our control. For a health-adjacent app that explicitly promises "We never sell your data," self-hosted PostHog on our existing infrastructure is the strongest privacy story we can tell.

**Firebase Crashlytics** remains for crash reporting only -- it is the industry standard for iOS crash symbolication and has zero viable self-hosted alternatives.

### Architecture Diagram

```
┌──────────────────────────────────────────────────────┐
│                   TEMPO iOS APP                       │
│                                                       │
│  ┌─────────────────────────────────────────────┐     │
│  │         AnalyticsService (Swift)             │     │
│  │                                              │     │
│  │  track(event:properties:)                    │     │
│  │  identify(userId:traits:)                    │     │
│  │  setUserProperties(_:)                       │     │
│  │  startSession() / endSession()               │     │
│  │  flush()                                     │     │
│  │                                              │     │
│  │  ┌──────────┐      ┌──────────────────┐     │     │
│  │  │ PostHog  │      │ Crashlytics      │     │     │
│  │  │ iOS SDK  │      │ (crashes only)   │     │     │
│  │  └────┬─────┘      └───────┬──────────┘     │     │
│  └───────┼────────────────────┼────────────────┘     │
│          │                    │                        │
└──────────┼────────────────────┼────────────────────────┘
           │ HTTPS              │ HTTPS
           ▼                    ▼
┌──────────────────┐   ┌──────────────────┐
│  PostHog Cloud   │   │ Firebase/Google   │
│  (or self-hosted │   │ Crashlytics      │
│   on Tempo infra)│   └──────────────────┘
│                  │
│  - Events        │
│  - Feature Flags │
│  - Session Replay│
│  - Funnels       │
│  - Cohorts       │
│  - Dashboards    │
└──────────────────┘
```

### AnalyticsService Wrapper

All analytics calls go through a single `AnalyticsService` class. No module should import PostHog directly. This allows swapping the underlying provider without touching module code.

```swift
@Observable
final class AnalyticsService {
    static let shared = AnalyticsService()

    func track(_ event: String, properties: [String: Any] = [:]) { ... }
    func identify(userId: String, traits: [String: Any] = [:]) { ... }
    func setUserProperties(_ properties: [String: Any]) { ... }
    func startSession() { ... }
    func endSession() { ... }
    func flush() { ... }
    func isFeatureFlagEnabled(_ flag: String) -> Bool { ... }
    func getFeatureFlagPayload(_ flag: String) -> Any? { ... }
}
```

## 1.2 Event Naming Conventions

**Format:** `snake_case`, `verb_noun` pattern. Maximum 50 characters.

**Rules:**

| Rule | Example | Counter-Example |
|---|---|---|
| Always start with a verb | `workout_started` | `started_workout` -- wrong word order by exception for readability (allowed: `noun_verbed` when the noun is the subject) |
| Use past tense for completed actions | `workout_completed` | `workout_complete` |
| Use present tense for state views | `dashboard_viewed` | `dashboard_view` |
| Prefix with module for ambiguous events | `arena_leaderboard_viewed` | `leaderboard_viewed` (ambiguous -- which leaderboard?) |
| No abbreviations | `notification_received` | `notif_rcvd` |
| No camelCase, no dots, no hyphens | `focus_timer_started` | `focusTimer.started` |

**Module Prefixes (used only when event name would be ambiguous without context):**

| Module | Prefix | Example |
|---|---|---|
| Onboarding | `onboarding_` | `onboarding_step_viewed` |
| Dashboard | `dashboard_` | `dashboard_quadrant_tapped` |
| Training (RepForge) | `workout_` or `exercise_` | `workout_started` |
| Accountability (Lockdown) | `lockdown_` or `focus_` | `lockdown_viewed` |
| Recovery (RecoverIQ) | `recovery_` | `recovery_viewed` |
| Arena (ClutchTime) | `arena_` | `arena_leaderboard_viewed` |
| Notifications | `notification_` | `notification_opened` |
| System | `app_` or `sync_` or `error_` | `app_launched` |

## 1.3 Event Property Standards

### Required Properties on EVERY Event (Auto-Attached by AnalyticsService)

These are injected by `AnalyticsService.track()` automatically. Module code never sets these manually.

| Property | Type | Description | Example |
|---|---|---|---|
| `event_id` | `String` (UUID) | Unique identifier for this event instance | `"a1b2c3d4-..."` |
| `timestamp` | `String` (ISO 8601) | UTC timestamp when event fired | `"2026-03-24T14:32:05.123Z"` |
| `session_id` | `String` (UUID) | Current session identifier | `"e5f6g7h8-..."` |
| `app_version` | `String` | Semantic version of the app | `"1.2.0"` |
| `build_number` | `String` | Build number | `"47"` |
| `os_version` | `String` | iOS version | `"17.4.1"` |
| `device_model` | `String` | Device model identifier | `"iPhone16,2"` |
| `screen_name` | `String` | Currently visible screen | `"DashboardView"` |
| `locale` | `String` | User's locale | `"en_US"` |
| `timezone` | `String` | User's timezone | `"America/New_York"` |

### Property Type Rules

| Type | Format | Example |
|---|---|---|
| `String` | UTF-8, max 255 chars | `"Push"` |
| `Int` | 64-bit signed integer | `120` |
| `Double` | 64-bit float, max 2 decimal places | `72.5` |
| `Bool` | `true` / `false` | `true` |
| `Date` | ISO 8601 UTC string | `"2026-03-24T14:32:05Z"` |
| `Enum` | Lowercase snake_case string | `"green"`, `"push"`, `"manual"` |
| `Array` | JSON array (use sparingly, only when semantically necessary) | `["whoop", "healthkit"]` |

### Forbidden Property Values

- No `null` -- omit the property entirely if the value is unavailable.
- No empty strings `""` -- omit the property.
- No PII (name, email, phone, Apple ID, IP address) -- see Section 9.
- No health biometrics (heart rate, HRV, recovery score, weight, body fat) -- see Section 9.

## 1.4 User Properties (Set on Every Session)

Set via `AnalyticsService.identify()` on app launch after authentication.

| Property | Type | Description | Example |
|---|---|---|---|
| `user_id` | `String` | Anonymous hashed identifier (NOT Apple ID) | `"usr_8f3a..."` |
| `account_created_at` | `Date` | When the user created their account | `"2026-03-15T10:00:00Z"` |
| `days_since_signup` | `Int` | Days since account creation | `9` |
| `onboarding_completed` | `Bool` | Whether user finished all 12 onboarding steps | `true` |
| `onboarding_completion_step` | `Int` | Last completed onboarding step (1-12) | `12` |
| `has_whoop` | `Bool` | Whether Whoop is currently connected | `true` |
| `has_nutritrack` | `Bool` | Whether NutriTrack is currently connected | `false` |
| `has_healthkit` | `Bool` | Whether HealthKit permissions granted | `true` |
| `has_calendar` | `Bool` | Whether Calendar access granted | `true` |
| `integrations_count` | `Int` | Total integrations connected (0-4) | `3` |
| `notifications_enabled` | `Bool` | Whether push notifications are authorized | `true` |
| `notification_intensity` | `String` | User's notification intensity setting | `"drill_sergeant"` |
| `friend_count` | `Int` | Number of accepted friends | `4` |
| `current_streak` | `Int` | Current consecutive-day streak | `12` |
| `longest_streak` | `Int` | All-time longest streak | `30` |
| `xp_total` | `Int` | Total XP earned (all time) | `14520` |
| `level` | `Int` | Current Arena level | `12` |
| `primary_goal` | `String` | User's selected primary goal | `"muscle_gain"` |
| `training_days_per_week` | `Int` | Configured training frequency | `5` |
| `non_negotiable_count` | `Int` | Number of configured non-negotiables | `4` |
| `app_opens_last_7d` | `Int` | App opens in the past 7 days | `18` |
| `platform` | `String` | Always `"ios"` for now | `"ios"` |

## 1.5 Session Definition

A **session** begins when the app enters the foreground (cold launch or foregrounded from background) and ends when the app has been in the background for **5 minutes or more**.

- If the user backgrounds the app and returns within 5 minutes, the same session continues.
- If the user backgrounds the app for 5+ minutes, the previous session ends and a new session begins on foreground.
- A session has a unique `session_id` (UUID v4), `session_start` timestamp, and `session_end` timestamp.
- Session duration is calculated as `session_end - session_start`, excluding background time.

**Active workout exception:** If a workout is in progress (`workout_started` fired, `workout_completed` or `workout_abandoned` not yet fired), the session timeout extends to **30 minutes** to avoid splitting a gym session into multiple analytics sessions when the phone is locked between sets.

## 1.6 Privacy: What We Track vs. What We Don't

### WE TRACK (anonymized behavioral data):

- Which screens users visit and in what order
- Which buttons users tap
- How long users spend on each screen
- Which features users adopt and in what sequence
- Workout completion rates (completed vs. abandoned) -- NOT the exercises, weights, or reps
- Non-negotiable completion rates (completed vs. missed) -- NOT which non-negotiables
- Whether integrations are connected (yes/no) -- NOT the data from those integrations
- Notification delivery and open rates
- App performance metrics (launch time, sync duration)
- Crash reports (via Crashlytics)

### WE NEVER TRACK (health data and PII):

- Heart rate, HRV, RHR, or any Whoop biometric
- Recovery score, sleep score, strain score
- Calories, macros, protein, carbs, fat, or any nutrition data
- Body weight, body fat percentage, or body measurements
- Specific exercises performed, weights lifted, or reps completed
- Study subjects, exam names, or academic content
- User's real name, email, Apple ID, or phone number
- IP address (anonymized at ingestion -- see Section 9)
- Location data
- Calendar event contents (class names, exam names)
- Notification message content
- Any text the user types (usernames excepted for friend search -- but not logged)

**The bright line:** Analytics answers "what did the user do in the app?" Never "what is the user's health status?"

---

# 2. Core Business Metrics (KPIs)

## KPI 1: Active Users (DAU / WAU / MAU)

**Definition:**
- **DAU (Daily Active Users):** Unique users who opened the app and performed at least one meaningful action (not just a background wake) in a calendar day (user's local timezone).
- **WAU (Weekly Active Users):** Unique users with at least 1 active day in the trailing 7-day window.
- **MAU (Monthly Active Users):** Unique users with at least 1 active day in the trailing 28-day window (not calendar month -- rolling 28 days for consistency).

**"Meaningful action" definition:** Any of: viewed a screen for >2 seconds, tapped a button, completed a non-negotiable, started/completed a workout, started a focus timer, viewed the Arena.

**Formula:**
```
DAU = COUNT(DISTINCT user_id WHERE has_meaningful_action = true AND date = today)
WAU = COUNT(DISTINCT user_id WHERE has_meaningful_action = true AND date IN last_7_days)
MAU = COUNT(DISTINCT user_id WHERE has_meaningful_action = true AND date IN last_28_days)
```

**Derived Ratios:**
- **DAU/MAU (Stickiness):** Healthy range for health/fitness apps: 0.25-0.40. Target: **0.35** (meaning 35% of monthly users use the app on any given day).
- **DAU/WAU:** Target: **0.55** (more than half of weekly users come back daily).

**Segmentation:** By onboarding completeness, integrations connected, friend count, primary goal, streak status.

**Thresholds:**
| Metric | Green | Yellow | Red |
|---|---|---|---|
| DAU/MAU | >= 0.35 | 0.20 - 0.34 | < 0.20 |
| DAU/WAU | >= 0.55 | 0.35 - 0.54 | < 0.35 |
| WAU growth (week-over-week) | >= 5% | 0% - 4.9% | Negative |

---

## KPI 2: Retention (D1, D7, D30, D90)

**Definition:** The percentage of users who signed up on day X and returned to perform a meaningful action on day X+N.

**Formula:**
```
D{N} Retention = COUNT(users who signed up on day X AND were active on day X+N) /
                 COUNT(users who signed up on day X)
```

**Industry benchmarks for health/fitness apps (source: Adjust 2025 benchmarks):**

| Metric | Industry Average | Good | Excellent | Tempo Target |
|---|---|---|---|---|
| **D1** | 25-30% | 35% | 45%+ | **40%** |
| **D7** | 12-18% | 22% | 30%+ | **28%** |
| **D30** | 6-10% | 14% | 20%+ | **18%** |
| **D90** | 3-5% | 8% | 12%+ | **10%** |

**Why our targets are above industry average:** Tempo has three retention advantages most fitness apps lack: (1) the drill-sergeant notification system creates daily pull, (2) the accountability/lockdown mechanic creates loss aversion (streak protection), and (3) the Arena social competition creates social obligation. These compound into higher retention.

**Segmentation:**
- By onboarding completeness: users who completed all 12 steps vs. those who dropped off
- By integrations: 0 integrations vs. 1+ vs. 3+
- By notification state: notifications enabled vs. disabled
- By social: has friends vs. solo
- By platform entry: organic vs. referral vs. ASO

**Thresholds:**
| Metric | Green | Yellow | Red |
|---|---|---|---|
| D1 Retention | >= 40% | 30-39% | < 30% |
| D7 Retention | >= 28% | 18-27% | < 18% |
| D30 Retention | >= 18% | 10-17% | < 10% |
| D90 Retention | >= 10% | 6-9% | < 6% |

---

## KPI 3: Streak Retention

**Definition:** The percentage of users with an active streak (consecutive days of completing all non-negotiables) by week since signup.

**Formula:**
```
Streak Retention (Week N) = COUNT(users signed up in cohort AND have active streak on week N) /
                            COUNT(users signed up in cohort)
```

**Targets:**
| Week | Target |
|---|---|
| Week 1 | 50% of active users have a streak >= 3 days |
| Week 2 | 35% of active users have a streak >= 7 days |
| Week 4 | 20% of active users have a streak >= 14 days |
| Week 8 | 12% of active users have a streak >= 30 days |
| Week 12 | 8% of active users have a streak >= 60 days |

**Why this matters:** Streaks are Tempo's primary retention mechanic. A user who has built a 14-day streak has a 4x higher likelihood of being retained at D90 compared to a user with no streak. (Hypothesis to validate -- see A/B test #3.)

**Segmentation:** By notification intensity, by friend count (social pressure preserves streaks), by primary goal.

**Thresholds:**
| Metric | Green | Yellow | Red |
|---|---|---|---|
| % users with 7+ day streak (among W2+ users) | >= 35% | 20-34% | < 20% |
| Average streak length (active users) | >= 10 days | 5-9 days | < 5 days |
| Streak freeze usage rate (per week) | < 15% | 15-30% | > 30% (too easy) |

---

## KPI 4: Non-Negotiable Completion Rate

**Definition:** The percentage of configured non-negotiables that are marked complete each day, averaged across all active users.

**Formula:**
```
Daily Completion Rate = SUM(non_negotiables_completed across all users) /
                        SUM(non_negotiables_total across all users)
```

**Targets:**
| Metric | Target |
|---|---|
| Daily average completion rate (all users) | >= 65% |
| % of users completing 100% of non-negotiables on any given day | >= 30% |
| % of users completing 0% of non-negotiables (among active users) | < 10% |

**Segmentation:** By non-negotiable type (study, train, meals, custom), by day of week (weekday vs. weekend), by notification intensity, by recovery zone (green/yellow/red).

**Thresholds:**
| Metric | Green | Yellow | Red |
|---|---|---|---|
| Average daily completion rate | >= 65% | 50-64% | < 50% |
| 100% completion rate | >= 30% | 15-29% | < 15% |
| Zero completion rate (active users) | < 10% | 10-20% | > 20% |

---

## KPI 5: Integration Connection Rate

**Definition:** The percentage of users who have connected at least one external integration, and the breakdown by integration type.

**Formula:**
```
Integration Rate = COUNT(users with integrations_count >= 1) / COUNT(all users)
Per-Integration Rate = COUNT(users with {integration} connected) / COUNT(all users)
```

**Targets:**
| Integration | Target Connection Rate | Rationale |
|---|---|---|
| HealthKit | >= 85% | Requested during onboarding, minimal friction |
| Apple Calendar | >= 60% | Requested during onboarding, some users hesitant |
| Whoop | >= 25% | Requires owning a Whoop device (~$30/mo subscription) |
| NutriTrack | >= 15% | Requires separate app setup |
| Any 1+ integration | >= 90% | Should be near-universal |
| 3+ integrations | >= 20% | Power user indicator |

**Why this matters:** Users with 3+ integrations have 2.3x higher D30 retention than users with 0 (hypothesis to validate). Auto-tracked non-negotiables reduce friction and increase completion rates.

**Thresholds:**
| Metric | Green | Yellow | Red |
|---|---|---|---|
| Any 1+ integration | >= 90% | 75-89% | < 75% |
| HealthKit | >= 85% | 70-84% | < 70% |
| Whoop (among active users) | >= 25% | 15-24% | < 15% |

---

## KPI 6: Arena Engagement

**Definition:** The percentage of active users who engage with social features (Arena module) at least once per week.

**Formula:**
```
Arena Weekly Engagement = COUNT(users who performed any arena action in last 7 days) /
                          COUNT(WAU)
```

**Arena actions:** Viewed leaderboard, sent/accepted friend request, created/joined/completed challenge, reacted to activity, viewed social feed.

**Targets:**
| Metric | Target |
|---|---|
| Arena weekly engagement (% of WAU) | >= 40% |
| % of users with 1+ friend | >= 50% |
| % of users in active challenge | >= 15% |
| Average friends per social user | >= 3 |

**Segmentation:** By friend count (0, 1-3, 4-10, 10+), by level, by challenge participation.

**Thresholds:**
| Metric | Green | Yellow | Red |
|---|---|---|---|
| Arena weekly engagement | >= 40% | 25-39% | < 25% |
| Users with 1+ friend | >= 50% | 30-49% | < 30% |
| Challenge participation | >= 15% | 8-14% | < 8% |

---

## KPI 7: Session Length and Frequency

**Definition:**
- **Session length:** Median duration of a session in seconds (active time only, excluding background).
- **Session frequency:** Average number of sessions per DAU per day.

**Targets:**
| Metric | Target | Rationale |
|---|---|---|
| Median session length | 3-5 minutes | Tempo is a "check-in" app -- glance at dashboard, log progress, leave. Long sessions happen during workouts. |
| Average sessions per DAU per day | 3-5 | Morning briefing check, midday check, workout logging, evening review |
| Workout session length (when workout active) | 30-75 minutes | Normal gym session duration |
| Focus timer session length | 25-50 minutes | Pomodoro blocks |

**Segmentation:** By time of day, by day of week, by module entered first.

**Thresholds:**
| Metric | Green | Yellow | Red |
|---|---|---|---|
| Median session length | 3-5 min | 1-3 min OR 5-10 min | < 1 min (bounce) OR > 10 min (confused) |
| Sessions per DAU per day | 3-5 | 2-3 OR 5-8 | < 2 (disengaged) OR > 8 (obsessive) |

---

## KPI 8: Feature Adoption Funnel

**Definition:** The percentage of users who have tried each major module at least once within their first 14 days.

**"Tried" definitions:**
| Module | "Tried" Event |
|---|---|
| Dashboard | `dashboard_viewed` (automatic on first launch -- excluded from measurement; use `dashboard_quadrant_tapped` instead) |
| Training | `workout_started` |
| Accountability | `non_negotiable_completed` (any type) |
| Recovery | `recovery_prescription_viewed` |
| Arena | `arena_leaderboard_viewed` |
| Focus Timer | `focus_timer_started` |
| Weekly Report | `weekly_report_viewed` |

**Targets (within 14 days of signup):**
| Module | Target Adoption |
|---|---|
| Dashboard (quadrant tap) | >= 90% |
| Accountability (complete 1 non-negotiable) | >= 75% |
| Training (start 1 workout) | >= 60% |
| Focus Timer (start 1 session) | >= 55% |
| Recovery (view prescription) | >= 45% |
| Arena (view leaderboard) | >= 40% |
| Weekly Report | >= 35% (only available after day 7) |

**Formula:**
```
Module Adoption (D14) = COUNT(users who triggered {tried_event} within 14 days of signup) /
                        COUNT(users who signed up 14+ days ago)
```

**Thresholds:**
| Metric | Green | Yellow | Red |
|---|---|---|---|
| Users who tried 4+ modules (of 7) within D14 | >= 50% | 30-49% | < 30% |
| Users who tried 0-1 modules within D14 | < 15% | 15-30% | > 30% |

---

## KPI 9: Notification Effectiveness

**Definition:** How well push notifications drive user engagement.

**Metrics:**
| Metric | Formula | Target |
|---|---|---|
| **Delivery rate** | Notifications delivered / Notifications sent | >= 95% |
| **Open rate** | Notifications opened / Notifications delivered | >= 35% (health app benchmark: 25-30%) |
| **Action rate** | Notification action tapped / Notifications opened | >= 20% |
| **Dismissal rate** | Notifications dismissed / Notifications delivered | < 40% |
| **Disable rate** | Users who disable notifications per week / WAU | < 2% |

**Segmentation:** By notification channel (morning briefing, gentle reminder, firm warning, urgent warning, etc.), by time of day, by notification intensity setting, by streak status.

**Per-Channel Targets:**
| Channel | Expected Open Rate | Rationale |
|---|---|---|
| Morning Briefing | 45-55% | High-value, personalized daily start |
| Gentle Reminder (2 PM) | 25-35% | Less urgent, often at work/school |
| Firm Warning (5 PM) | 30-40% | Urgency increases attention |
| Urgent Warning (6:30 PM) | 35-45% | Loss aversion kicks in |
| Aggressive Warning (7 PM) | 30-40% | Some users numb by now |
| All Clear | 20-30% | Positive but no action needed |
| Streak at Risk | 50-60% | Highest urgency, loss aversion peak |
| Arena Updates | 20-25% | Social but not urgent |
| Weekly Report | 30-40% | Anticipated, meaningful content |

**Thresholds:**
| Metric | Green | Yellow | Red |
|---|---|---|---|
| Overall open rate | >= 35% | 20-34% | < 20% |
| Notification disable rate (weekly) | < 2% | 2-5% | > 5% (we are spamming) |
| Morning Briefing open rate | >= 45% | 30-44% | < 30% |

---

## KPI 10: Churn Prediction Signals

**Definition:** Early indicators that a user is about to churn, used to trigger re-engagement interventions.

**Churn Signals (ordered by predictive power):**

| Signal | Definition | Risk Level | Intervention |
|---|---|---|---|
| **Streak broken** | User had a 7+ day streak and it broke | High | Push: "Your [N]-day streak ended yesterday. Start a new one today -- the first 3 days are the hardest." |
| **3 consecutive days inactive** | No meaningful action for 3 days | High | Push: "We haven't seen you in 3 days. Your friends are pulling ahead." |
| **Notification disabled** | User turned off push notifications | Critical | In-app: Next time they open, show a card explaining notification value |
| **Session length declining** | Median session length dropped 50%+ over 7 days | Medium | Investigate: is a feature broken or is the user losing interest? |
| **Non-negotiable completion declining** | Completion rate dropped from >70% to <40% over 7 days | Medium | Push: Reduce difficulty suggestion ("Scale back to 2 non-negotiables this week?") |
| **Integration disconnected** | User disconnected Whoop or NutriTrack | Medium | In-app: "Reconnect Whoop to keep your recovery insights updated" |
| **Zero friends and low Arena engagement** | User has 0 friends after 14 days, never viewed Arena | Low-Medium | In-app: "Add a friend to unlock weekly challenges" |
| **Weekend-only usage** | User is active Sat/Sun but not weekdays for 2+ weeks | Low | Push: Adjust notification timing for weekday mornings |

**Churn Risk Score (0-100):**

```
churn_risk = 0

if days_since_last_activity >= 3: churn_risk += 30
elif days_since_last_activity >= 2: churn_risk += 15
elif days_since_last_activity >= 1: churn_risk += 5

if streak_broken_recently (last 7 days): churn_risk += 20
if notifications_disabled: churn_risk += 15
if completion_rate_7d < 0.40: churn_risk += 15
if session_count_7d < 3: churn_risk += 10
if integrations_count == 0: churn_risk += 5
if friend_count == 0 AND days_since_signup > 14: churn_risk += 5
if session_length_trend_7d < -0.50: churn_risk += 5

# Cap at 100
churn_risk = min(churn_risk, 100)
```

**Thresholds:**
| Risk Level | Score | Action |
|---|---|---|
| Low | 0-25 | No intervention |
| Medium | 26-50 | Automated re-engagement notification |
| High | 51-75 | Aggressive re-engagement sequence (3 notifications over 5 days) |
| Critical | 76-100 | Last-chance "we miss you" push + in-app win-back flow on next open |

---

# 3. Event Catalog

> Every event the app tracks. For each: event name, when it fires, properties, and an example JSON payload.

## 3.1 System Events

### `app_launched`

**When:** App enters foreground (both cold launch and warm return after session timeout).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `launch_type` | `String` | `"cold"` (fresh start) or `"warm"` (from background after session timeout) |
| `time_since_last_session` | `Int` | Seconds since last session ended. `0` for first launch. |
| `launch_duration_ms` | `Int` | Milliseconds from process start to first frame rendered (cold only). |

**Example:**
```json
{
  "event": "app_launched",
  "properties": {
    "launch_type": "cold",
    "time_since_last_session": 28800,
    "launch_duration_ms": 1243
  }
}
```

### `app_backgrounded`

**When:** App enters background.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `session_duration_seconds` | `Int` | Duration of current session so far |
| `screens_viewed` | `Int` | Number of distinct screens viewed in this session |

**Example:**
```json
{
  "event": "app_backgrounded",
  "properties": {
    "session_duration_seconds": 187,
    "screens_viewed": 4
  }
}
```

### `app_foregrounded`

**When:** App returns from background within the session timeout window (not a new session).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `background_duration_seconds` | `Int` | How long the app was in background |

**Example:**
```json
{
  "event": "app_foregrounded",
  "properties": {
    "background_duration_seconds": 45
  }
}
```

### `sync_completed`

**When:** A data sync with the backend or an integration finishes.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `sync_source` | `String` | `"backend"`, `"whoop"`, `"nutritrack"`, `"healthkit"` |
| `duration_ms` | `Int` | Sync duration in milliseconds |
| `records_synced` | `Int` | Number of records pulled/pushed |
| `success` | `Bool` | Whether sync completed without error |
| `error_type` | `String` | Error category if `success` is false. Omitted if success. |

**Example:**
```json
{
  "event": "sync_completed",
  "properties": {
    "sync_source": "whoop",
    "duration_ms": 892,
    "records_synced": 3,
    "success": true
  }
}
```

### `error_occurred`

**When:** An unhandled error or known error state occurs.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `error_type` | `String` | Category: `"network"`, `"auth"`, `"sync"`, `"parsing"`, `"healthkit"`, `"unknown"` |
| `error_message` | `String` | Non-PII error description (max 255 chars) |
| `screen_name` | `String` | Screen where error occurred |
| `is_fatal` | `Bool` | Whether the error crashed the app |

**Example:**
```json
{
  "event": "error_occurred",
  "properties": {
    "error_type": "network",
    "error_message": "Whoop API returned 503",
    "screen_name": "RecoveryTodayView",
    "is_fatal": false
  }
}
```

### `screen_viewed`

**When:** A new screen becomes visible (via navigation or tab switch). Fires after the view's `onAppear`.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `screen_name` | `String` | SwiftUI view name |
| `module` | `String` | `"dashboard"`, `"training"`, `"accountability"`, `"recovery"`, `"arena"`, `"onboarding"`, `"settings"` |
| `previous_screen` | `String` | The screen navigated from. Omitted on first screen. |

**Example:**
```json
{
  "event": "screen_viewed",
  "properties": {
    "screen_name": "RecoveryTodayView",
    "module": "recovery",
    "previous_screen": "DashboardView"
  }
}
```

---

## 3.2 Onboarding Events

### `onboarding_started`

**When:** User taps "GET STARTED" on Step 1 (Welcome).

**Properties:** None (all context is auto-attached).

**Example:**
```json
{
  "event": "onboarding_started",
  "properties": {}
}
```

### `onboarding_step_viewed`

**When:** Each onboarding step screen becomes visible.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `step_number` | `Int` | 1-12 |
| `step_name` | `String` | Human-readable step name |

**Valid `step_name` values:**

| Step | Name |
|---|---|
| 1 | `"welcome"` |
| 2 | `"sign_in_apple"` |
| 3 | `"profile_setup"` |
| 4 | `"training_setup"` |
| 5 | `"academics_setup"` |
| 6 | `"goals_setup"` |
| 7 | `"connect_whoop"` |
| 8 | `"connect_nutritrack"` |
| 9 | `"healthkit_permissions"` |
| 10 | `"notification_permissions"` |
| 11 | `"arena_setup"` |
| 12 | `"summary_briefing"` |

**Example:**
```json
{
  "event": "onboarding_step_viewed",
  "properties": {
    "step_number": 4,
    "step_name": "training_setup"
  }
}
```

### `onboarding_step_completed`

**When:** User successfully completes an onboarding step (taps continue/next and validation passes).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `step_number` | `Int` | 1-12 |
| `step_name` | `String` | Same enum as `onboarding_step_viewed` |
| `duration_seconds` | `Int` | Time spent on this step |

**Example:**
```json
{
  "event": "onboarding_step_completed",
  "properties": {
    "step_number": 3,
    "step_name": "profile_setup",
    "duration_seconds": 42
  }
}
```

### `onboarding_step_skipped`

**When:** User taps "Skip for now" on an optional step (Steps 7, 8, 11).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `step_number` | `Int` | Step that was skipped |
| `step_name` | `String` | Step name |

**Example:**
```json
{
  "event": "onboarding_step_skipped",
  "properties": {
    "step_number": 7,
    "step_name": "connect_whoop"
  }
}
```

### `onboarding_integration_connected`

**When:** User successfully connects an integration during onboarding.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `integration_type` | `String` | `"whoop"`, `"nutritrack"`, `"healthkit"`, `"calendar"` |
| `step_number` | `Int` | The onboarding step where it happened |
| `duration_seconds` | `Int` | Time from step entry to successful connection |

**Example:**
```json
{
  "event": "onboarding_integration_connected",
  "properties": {
    "integration_type": "whoop",
    "step_number": 7,
    "duration_seconds": 18
  }
}
```

### `onboarding_integration_skipped`

**When:** User skips connecting an integration during onboarding.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `integration_type` | `String` | `"whoop"`, `"nutritrack"`, `"healthkit"`, `"calendar"` |
| `step_number` | `Int` | Step number |

**Example:**
```json
{
  "event": "onboarding_integration_skipped",
  "properties": {
    "integration_type": "nutritrack",
    "step_number": 8
  }
}
```

### `onboarding_integration_failed`

**When:** An integration connection attempt fails during onboarding (OAuth error, permission denied, timeout).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `integration_type` | `String` | `"whoop"`, `"nutritrack"`, `"healthkit"`, `"calendar"` |
| `failure_reason` | `String` | `"oauth_cancelled"`, `"oauth_error"`, `"permission_denied"`, `"timeout"`, `"server_error"` |
| `step_number` | `Int` | Step number |

**Example:**
```json
{
  "event": "onboarding_integration_failed",
  "properties": {
    "integration_type": "whoop",
    "failure_reason": "oauth_cancelled",
    "step_number": 7
  }
}
```

### `onboarding_profile_configured`

**When:** User completes profile setup (Step 3).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `has_display_name` | `Bool` | Whether user set a display name |
| `has_username` | `Bool` | Whether user set a username |

**Example:**
```json
{
  "event": "onboarding_profile_configured",
  "properties": {
    "has_display_name": true,
    "has_username": true
  }
}
```

### `onboarding_training_configured`

**When:** User completes training setup (Step 4).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `training_days_per_week` | `Int` | Selected training frequency (1-7) |
| `split_type` | `String` | `"ppl"`, `"upper_lower"`, `"full_body"`, `"custom"` |
| `has_football` | `Bool` | Whether football schedule was added |
| `football_days_per_week` | `Int` | Number of football days (0 if no football) |

**Example:**
```json
{
  "event": "onboarding_training_configured",
  "properties": {
    "training_days_per_week": 5,
    "split_type": "ppl",
    "has_football": true,
    "football_days_per_week": 2
  }
}
```

### `onboarding_academics_configured`

**When:** User completes academics setup (Step 5).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `daily_study_target_minutes` | `Int` | Minutes of daily study target |
| `has_exam_date` | `Bool` | Whether user set a next exam date |
| `days_to_exam` | `Int` | Days until next exam. Omitted if no exam set. |

**Example:**
```json
{
  "event": "onboarding_academics_configured",
  "properties": {
    "daily_study_target_minutes": 120,
    "has_exam_date": true,
    "days_to_exam": 18
  }
}
```

### `onboarding_goals_configured`

**When:** User completes goals setup (Step 6).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `primary_goal` | `String` | `"muscle_gain"`, `"fat_loss"`, `"performance"`, `"health"`, `"academics"` |
| `non_negotiable_count` | `Int` | Number of non-negotiables configured |
| `non_negotiable_types` | `Array<String>` | Types configured, e.g. `["study", "train", "meals"]` |

**Example:**
```json
{
  "event": "onboarding_goals_configured",
  "properties": {
    "primary_goal": "muscle_gain",
    "non_negotiable_count": 4,
    "non_negotiable_types": ["study", "train", "meals", "custom"]
  }
}
```

### `onboarding_notification_permission_result`

**When:** User responds to the iOS notification permission dialog (Step 10).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `granted` | `Bool` | Whether permission was granted |

**Example:**
```json
{
  "event": "onboarding_notification_permission_result",
  "properties": {
    "granted": true
  }
}
```

### `onboarding_arena_configured`

**When:** User completes Arena setup (Step 11).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `chose_username` | `Bool` | Whether user created an Arena username |
| `invited_friends` | `Int` | Number of friend invitations sent |
| `skipped` | `Bool` | Whether user skipped Arena setup entirely |

**Example:**
```json
{
  "event": "onboarding_arena_configured",
  "properties": {
    "chose_username": true,
    "invited_friends": 2,
    "skipped": false
  }
}
```

### `onboarding_completed`

**When:** User reaches the end of onboarding (taps CTA on Step 12 summary screen).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `duration_seconds` | `Int` | Total onboarding time from step 1 start to completion |
| `steps_completed` | `Int` | Number of steps actually completed (not skipped) |
| `steps_skipped` | `Int` | Number of steps skipped |
| `integrations_connected` | `Int` | Total integrations connected during onboarding |
| `integration_types` | `Array<String>` | Which integrations were connected |

**Example:**
```json
{
  "event": "onboarding_completed",
  "properties": {
    "duration_seconds": 312,
    "steps_completed": 10,
    "steps_skipped": 2,
    "integrations_connected": 3,
    "integration_types": ["whoop", "healthkit", "calendar"]
  }
}
```

### `onboarding_abandoned`

**When:** User kills the app during onboarding and does not return within 24 hours. Fired by backend based on incomplete onboarding state.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `last_step_completed` | `Int` | Last step the user completed before abandoning |
| `last_step_name` | `String` | Name of the last completed step |
| `duration_seconds` | `Int` | Total time spent in onboarding before abandoning |
| `integrations_connected` | `Int` | How many integrations were connected before abandoning |

**Example:**
```json
{
  "event": "onboarding_abandoned",
  "properties": {
    "last_step_completed": 6,
    "last_step_name": "goals_setup",
    "duration_seconds": 180,
    "integrations_connected": 0
  }
}
```

### `onboarding_resumed`

**When:** User returns to onboarding after killing the app mid-flow.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `resume_step` | `Int` | Step they are resuming at |
| `hours_since_last_activity` | `Double` | Hours since they were last in onboarding |

**Example:**
```json
{
  "event": "onboarding_resumed",
  "properties": {
    "resume_step": 7,
    "hours_since_last_activity": 2.5
  }
}
```

---

## 3.3 Dashboard Events

### `dashboard_viewed`

**When:** DashboardView appears (tab selected or app launched to dashboard).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `has_whoop_data` | `Bool` | Whether Whoop data is populated today |
| `has_nutritrack_data` | `Bool` | Whether NutriTrack data is populated today |
| `non_negotiables_completed` | `Int` | Current count of completed non-negotiables |
| `non_negotiables_total` | `Int` | Total non-negotiables for today |

**Example:**
```json
{
  "event": "dashboard_viewed",
  "properties": {
    "has_whoop_data": true,
    "has_nutritrack_data": true,
    "non_negotiables_completed": 2,
    "non_negotiables_total": 4
  }
}
```

### `dashboard_quadrant_tapped`

**When:** User taps one of the four quadrants to drill into detail.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `quadrant` | `String` | `"body"`, `"fuel"`, `"mind"`, `"move"` |

**Example:**
```json
{
  "event": "dashboard_quadrant_tapped",
  "properties": {
    "quadrant": "body"
  }
}
```

### `dashboard_refreshed`

**When:** User performs a pull-to-refresh on the dashboard.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `time_since_last_refresh_seconds` | `Int` | Seconds since last refresh (manual or auto) |

**Example:**
```json
{
  "event": "dashboard_refreshed",
  "properties": {
    "time_since_last_refresh_seconds": 1800
  }
}
```

### `dashboard_score_viewed`

**When:** User taps to expand or view the daily score breakdown.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `score_visible` | `Bool` | Whether the score was already visible (tap to collapse) or newly expanded |

**Example:**
```json
{
  "event": "dashboard_score_viewed",
  "properties": {
    "score_visible": true
  }
}
```

### `weekly_report_viewed`

**When:** User opens the weekly report screen.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `report_week` | `String` | ISO week identifier, e.g. `"2026-W12"` |
| `source` | `String` | `"dashboard_card"`, `"notification"`, `"arena"` |

**Example:**
```json
{
  "event": "weekly_report_viewed",
  "properties": {
    "report_week": "2026-W12",
    "source": "dashboard_card"
  }
}
```

### `weekly_report_shared`

**When:** User taps share on the weekly report.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `report_week` | `String` | Week identifier |
| `share_method` | `String` | `"messages"`, `"instagram_story"`, `"copy_link"`, `"other"` |

**Example:**
```json
{
  "event": "weekly_report_shared",
  "properties": {
    "report_week": "2026-W12",
    "share_method": "instagram_story"
  }
}
```

### `pattern_viewed`

**When:** User opens the pattern/correlation analysis screen.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `pattern_type` | `String` | `"sleep_vs_training"`, `"nutrition_vs_recovery"`, `"study_vs_completion"`, `"overview"` |

**Example:**
```json
{
  "event": "pattern_viewed",
  "properties": {
    "pattern_type": "sleep_vs_training"
  }
}
```

### `widget_tapped`

**When:** User taps any widget/card on the dashboard (other than quadrants).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `widget_type` | `String` | `"streak_card"`, `"daily_score"`, `"xp_progress"`, `"next_workout"`, `"study_progress"`, `"meal_status"` |
| `quadrant` | `String` | Which quadrant the widget belongs to. `"global"` for non-quadrant widgets. |

**Example:**
```json
{
  "event": "widget_tapped",
  "properties": {
    "widget_type": "streak_card",
    "quadrant": "global"
  }
}
```

### `dashboard_date_changed`

**When:** User swipes or taps to view a different day on the dashboard.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `direction` | `String` | `"past"` or `"future"` |
| `days_from_today` | `Int` | How many days away from today |

**Example:**
```json
{
  "event": "dashboard_date_changed",
  "properties": {
    "direction": "past",
    "days_from_today": 2
  }
}
```

### `dashboard_tab_switched`

**When:** User switches to the Dashboard tab from another tab.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `from_tab` | `String` | `"training"`, `"accountability"`, `"recovery"`, `"arena"` |

**Example:**
```json
{
  "event": "dashboard_tab_switched",
  "properties": {
    "from_tab": "training"
  }
}
```

---

## 3.4 Training Events

### `workout_viewed`

**When:** User opens the TodayWorkoutView (today's prescribed workout).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `workout_type` | `String` | `"push"`, `"pull"`, `"legs"`, `"upper"`, `"lower"`, `"full_body"`, `"football"`, `"run"`, `"conditioning"`, `"mobility"`, `"rest"` |
| `exercise_count` | `Int` | Number of exercises in the workout |
| `is_recovery_adjusted` | `Bool` | Whether the workout was modified based on recovery |
| `recovery_zone` | `String` | `"green"`, `"yellow"`, `"red"`, `"unknown"` (if no Whoop data) |

**Example:**
```json
{
  "event": "workout_viewed",
  "properties": {
    "workout_type": "push",
    "exercise_count": 6,
    "is_recovery_adjusted": true,
    "recovery_zone": "yellow"
  }
}
```

### `workout_started`

**When:** User taps "Start Workout" and the active workout timer begins.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `workout_type` | `String` | Same enum as `workout_viewed` |
| `exercise_count` | `Int` | Total exercises planned |
| `is_recovery_adjusted` | `Bool` | Whether recovery-adjusted |
| `recovery_zone` | `String` | Recovery zone |
| `source` | `String` | `"today_workout"`, `"week_plan"`, `"quick_start"` |

**Example:**
```json
{
  "event": "workout_started",
  "properties": {
    "workout_type": "push",
    "exercise_count": 6,
    "is_recovery_adjusted": true,
    "recovery_zone": "yellow",
    "source": "today_workout"
  }
}
```

### `workout_set_completed`

**When:** User marks a single set as done during an active workout.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `set_number` | `Int` | Set number within the exercise (1-indexed) |
| `exercise_order` | `Int` | Exercise order in the workout (1-indexed) |
| `is_superset` | `Bool` | Whether this set is part of a superset |
| `met_target` | `Bool` | Whether user hit the target reps/weight |
| `has_rpe` | `Bool` | Whether user logged RPE |

**Example:**
```json
{
  "event": "workout_set_completed",
  "properties": {
    "set_number": 2,
    "exercise_order": 1,
    "is_superset": false,
    "met_target": true,
    "has_rpe": true
  }
}
```

### `workout_exercise_completed`

**When:** All sets for a single exercise are marked complete.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `exercise_order` | `Int` | Position in workout (1-indexed) |
| `sets_completed` | `Int` | Number of sets completed |
| `sets_planned` | `Int` | Number of sets that were planned |
| `duration_seconds` | `Int` | Time spent on this exercise (including rest) |

**Example:**
```json
{
  "event": "workout_exercise_completed",
  "properties": {
    "exercise_order": 3,
    "sets_completed": 4,
    "sets_planned": 4,
    "duration_seconds": 420
  }
}
```

### `workout_exercise_swapped`

**When:** User replaces a prescribed exercise with a different one.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `exercise_order` | `Int` | Position of the swapped exercise |
| `swap_reason` | `String` | `"equipment_unavailable"`, `"injury"`, `"preference"`, `"not_specified"` |

**Example:**
```json
{
  "event": "workout_exercise_swapped",
  "properties": {
    "exercise_order": 2,
    "swap_reason": "equipment_unavailable"
  }
}
```

### `workout_exercise_skipped`

**When:** User skips an exercise entirely (without swapping).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `exercise_order` | `Int` | Position of skipped exercise |

**Example:**
```json
{
  "event": "workout_exercise_skipped",
  "properties": {
    "exercise_order": 5
  }
}
```

### `workout_completed`

**When:** User finishes the entire workout (taps "Finish Workout" and confirms).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `workout_type` | `String` | Workout type |
| `duration_seconds` | `Int` | Total workout duration |
| `exercises_completed` | `Int` | Exercises fully completed |
| `exercises_planned` | `Int` | Exercises that were planned |
| `exercises_skipped` | `Int` | Exercises skipped |
| `exercises_swapped` | `Int` | Exercises swapped |
| `total_sets_completed` | `Int` | Total sets across all exercises |
| `prs_achieved` | `Int` | Number of personal records hit |
| `completion_percentage` | `Double` | exercises_completed / exercises_planned |

**Example:**
```json
{
  "event": "workout_completed",
  "properties": {
    "workout_type": "push",
    "duration_seconds": 3420,
    "exercises_completed": 5,
    "exercises_planned": 6,
    "exercises_skipped": 1,
    "exercises_swapped": 0,
    "total_sets_completed": 18,
    "prs_achieved": 1,
    "completion_percentage": 0.83
  }
}
```

### `workout_abandoned`

**When:** User exits an active workout without completing it (navigates away, kills app, or taps "Cancel Workout").

**Properties:**
| Property | Type | Description |
|---|---|---|
| `workout_type` | `String` | Workout type |
| `duration_seconds` | `Int` | Time elapsed before abandoning |
| `exercises_completed` | `Int` | Exercises fully completed before abandoning |
| `exercises_planned` | `Int` | Total planned exercises |
| `abandon_reason` | `String` | `"user_cancelled"`, `"app_killed"`, `"navigated_away"` |

**Example:**
```json
{
  "event": "workout_abandoned",
  "properties": {
    "workout_type": "legs",
    "duration_seconds": 1200,
    "exercises_completed": 2,
    "exercises_planned": 6,
    "abandon_reason": "user_cancelled"
  }
}
```

### `workout_rest_timer_started`

**When:** Rest timer begins between sets.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `rest_duration_seconds` | `Int` | Prescribed rest duration |
| `exercise_order` | `Int` | Current exercise |

**Example:**
```json
{
  "event": "workout_rest_timer_started",
  "properties": {
    "rest_duration_seconds": 90,
    "exercise_order": 2
  }
}
```

### `workout_rest_timer_skipped`

**When:** User skips the rest timer (taps "Skip Rest").

**Properties:**
| Property | Type | Description |
|---|---|---|
| `remaining_seconds` | `Int` | How many seconds were left on the rest timer |
| `exercise_order` | `Int` | Current exercise |

**Example:**
```json
{
  "event": "workout_rest_timer_skipped",
  "properties": {
    "remaining_seconds": 42,
    "exercise_order": 2
  }
}
```

### `exercise_searched`

**When:** User types in the exercise search bar.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `query_length` | `Int` | Number of characters in the search query |
| `results_count` | `Int` | Number of results returned |
| `selected_result` | `Bool` | Whether the user tapped a result |

**Example:**
```json
{
  "event": "exercise_searched",
  "properties": {
    "query_length": 5,
    "results_count": 8,
    "selected_result": true
  }
}
```

### `exercise_created`

**When:** User creates a custom exercise.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `muscle_group` | `String` | Selected muscle group |
| `is_compound` | `Bool` | Whether marked as compound |

**Example:**
```json
{
  "event": "exercise_created",
  "properties": {
    "muscle_group": "chest",
    "is_compound": false
  }
}
```

### `progress_chart_viewed`

**When:** User opens the progress charts screen.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `chart_type` | `String` | `"exercise_progress"`, `"volume_trend"`, `"frequency"`, `"body_part_split"` |
| `time_range` | `String` | `"7d"`, `"30d"`, `"90d"`, `"all_time"` |

**Example:**
```json
{
  "event": "progress_chart_viewed",
  "properties": {
    "chart_type": "exercise_progress",
    "time_range": "30d"
  }
}
```

### `pr_achieved`

**When:** User sets a new personal record during a workout.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `pr_type` | `String` | `"weight"`, `"reps"`, `"estimated_1rm"` |
| `is_first_pr` | `Bool` | Whether this is the user's very first PR in the app |

**Example:**
```json
{
  "event": "pr_achieved",
  "properties": {
    "pr_type": "weight",
    "is_first_pr": false
  }
}
```

### `running_session_started`

**When:** User starts a running or cardio session.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `run_type` | `String` | `"easy_run"`, `"tempo_run"`, `"intervals"`, `"sprints"`, `"free_run"` |
| `planned_duration_minutes` | `Int` | Planned duration. Omitted for free run. |

**Example:**
```json
{
  "event": "running_session_started",
  "properties": {
    "run_type": "easy_run",
    "planned_duration_minutes": 30
  }
}
```

### `running_session_completed`

**When:** User finishes a running session.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `run_type` | `String` | Run type |
| `duration_seconds` | `Int` | Actual duration |
| `completed_as_planned` | `Bool` | Whether the full planned session was completed |

**Example:**
```json
{
  "event": "running_session_completed",
  "properties": {
    "run_type": "easy_run",
    "duration_seconds": 1920,
    "completed_as_planned": true
  }
}
```

### `week_plan_viewed`

**When:** User opens the 7-day training plan overview.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `days_with_workouts` | `Int` | Number of days in the week with planned workouts |
| `has_football_days` | `Bool` | Whether any football days are in the plan |

**Example:**
```json
{
  "event": "week_plan_viewed",
  "properties": {
    "days_with_workouts": 5,
    "has_football_days": true
  }
}
```

### `week_plan_regenerated`

**When:** User requests a new weekly plan (taps "Regenerate Plan").

**Properties:**
| Property | Type | Description |
|---|---|---|
| `reason` | `String` | `"schedule_change"`, `"recovery_change"`, `"preference"`, `"not_specified"` |

**Example:**
```json
{
  "event": "week_plan_regenerated",
  "properties": {
    "reason": "schedule_change"
  }
}
```

### `training_settings_changed`

**When:** User modifies any training setting.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `setting_name` | `String` | `"training_days"`, `"split_type"`, `"football_schedule"`, `"rest_timer_default"`, `"auto_progression"` |
| `new_value` | `String` | New value (generic string representation) |

**Example:**
```json
{
  "event": "training_settings_changed",
  "properties": {
    "setting_name": "split_type",
    "new_value": "upper_lower"
  }
}
```

---

## 3.5 Accountability Events

### `lockdown_viewed`

**When:** User opens the Lockdown (accountability) main screen.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `non_negotiables_completed` | `Int` | Currently completed count |
| `non_negotiables_total` | `Int` | Total configured |
| `leisure_unlocked` | `Bool` | Whether leisure is currently unlocked |
| `current_streak` | `Int` | Current day streak |

**Example:**
```json
{
  "event": "lockdown_viewed",
  "properties": {
    "non_negotiables_completed": 2,
    "non_negotiables_total": 4,
    "leisure_unlocked": false,
    "current_streak": 12
  }
}
```

### `non_negotiable_completed`

**When:** A non-negotiable is marked as complete (either manually or auto-detected).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `type` | `String` | `"study"`, `"train"`, `"meals"`, `"custom"` |
| `tracking_method` | `String` | `"auto"` (integration detected) or `"manual"` (user tapped) |
| `completion_order` | `Int` | Which non-negotiable this was (1st, 2nd, 3rd, etc.) |
| `is_last` | `Bool` | Whether this was the final non-negotiable for the day |
| `time_of_day` | `String` | `"morning"` (before 12), `"afternoon"` (12-17), `"evening"` (17-21), `"night"` (after 21) |

**Example:**
```json
{
  "event": "non_negotiable_completed",
  "properties": {
    "type": "train",
    "tracking_method": "auto",
    "completion_order": 2,
    "is_last": false,
    "time_of_day": "afternoon"
  }
}
```

### `non_negotiable_missed`

**When:** End of day (midnight) with an incomplete non-negotiable.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `type` | `String` | `"study"`, `"train"`, `"meals"`, `"custom"` |
| `progress_percentage` | `Double` | How close the user got (0.0 - 1.0). E.g., 60 minutes of 120 minute target = 0.5 |

**Example:**
```json
{
  "event": "non_negotiable_missed",
  "properties": {
    "type": "study",
    "progress_percentage": 0.65
  }
}
```

### `leisure_unlocked`

**When:** All non-negotiables are complete and the "unlocked" state is triggered.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `unlock_time` | `String` | ISO 8601 time of unlock |
| `time_of_day` | `String` | `"morning"`, `"afternoon"`, `"evening"`, `"night"` |
| `non_negotiables_count` | `Int` | How many non-negotiables were completed |

**Example:**
```json
{
  "event": "leisure_unlocked",
  "properties": {
    "unlock_time": "2026-03-24T17:45:00Z",
    "time_of_day": "evening",
    "non_negotiables_count": 4
  }
}
```

### `focus_timer_started`

**When:** User starts a focus/study timer session.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `session_type` | `String` | `"pomodoro_25"`, `"pomodoro_50"`, `"custom"`, `"free"` |
| `planned_duration_minutes` | `Int` | Duration of the timer. `0` for free sessions. |
| `subject` | `Bool` | Whether a subject/label was set (NOT the subject name itself) |

**Example:**
```json
{
  "event": "focus_timer_started",
  "properties": {
    "session_type": "pomodoro_25",
    "planned_duration_minutes": 25,
    "subject": true
  }
}
```

### `focus_timer_completed`

**When:** Focus timer runs to completion (full duration elapsed).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `session_type` | `String` | Same enum as started |
| `duration_seconds` | `Int` | Actual duration |
| `distractions` | `Int` | Number of times user left the app during the session |
| `is_first_session_today` | `Bool` | Whether this is the first completed session today |

**Example:**
```json
{
  "event": "focus_timer_completed",
  "properties": {
    "session_type": "pomodoro_25",
    "duration_seconds": 1500,
    "distractions": 1,
    "is_first_session_today": true
  }
}
```

### `focus_timer_abandoned`

**When:** User stops the focus timer before it completes.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `session_type` | `String` | Timer type |
| `duration_seconds` | `Int` | How long before abandoning |
| `planned_duration_seconds` | `Int` | How long it was supposed to be |
| `completion_percentage` | `Double` | duration / planned_duration |

**Example:**
```json
{
  "event": "focus_timer_abandoned",
  "properties": {
    "session_type": "pomodoro_25",
    "duration_seconds": 780,
    "planned_duration_seconds": 1500,
    "completion_percentage": 0.52
  }
}
```

### `focus_timer_paused`

**When:** User pauses the focus timer.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `elapsed_seconds` | `Int` | Time elapsed before pausing |

**Example:**
```json
{
  "event": "focus_timer_paused",
  "properties": {
    "elapsed_seconds": 600
  }
}
```

### `focus_timer_resumed`

**When:** User resumes the focus timer after pausing.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `pause_duration_seconds` | `Int` | How long the timer was paused |

**Example:**
```json
{
  "event": "focus_timer_resumed",
  "properties": {
    "pause_duration_seconds": 120
  }
}
```

### `streak_achieved`

**When:** User hits a streak milestone (7, 14, 21, 30, 60, 90, 180, 365 days).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `streak_count` | `Int` | The milestone reached |
| `is_personal_best` | `Bool` | Whether this is their longest streak ever |

**Example:**
```json
{
  "event": "streak_achieved",
  "properties": {
    "streak_count": 30,
    "is_personal_best": true
  }
}
```

### `streak_lost`

**When:** User's streak resets to zero (failed to complete all non-negotiables and had no freeze available/used).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `streak_count_lost` | `Int` | The streak count that was lost |
| `reason` | `String` | `"non_negotiables_incomplete"`, `"no_activity"` |

**Example:**
```json
{
  "event": "streak_lost",
  "properties": {
    "streak_count_lost": 14,
    "reason": "non_negotiables_incomplete"
  }
}
```

### `streak_freeze_used`

**When:** A streak freeze is consumed to protect the streak.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `streak_count_protected` | `Int` | Current streak that was saved |
| `freezes_remaining` | `Int` | Remaining streak freezes after this use |
| `trigger` | `String` | `"auto"` (system used it) or `"manual"` (user activated it) |

**Example:**
```json
{
  "event": "streak_freeze_used",
  "properties": {
    "streak_count_protected": 22,
    "freezes_remaining": 1,
    "trigger": "auto"
  }
}
```

### `exam_mode_activated`

**When:** User activates exam mode.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `duration_days` | `Int` | Number of days exam mode will last |
| `days_to_exam` | `Int` | Days until the exam |

**Example:**
```json
{
  "event": "exam_mode_activated",
  "properties": {
    "duration_days": 7,
    "days_to_exam": 5
  }
}
```

### `exam_mode_deactivated`

**When:** Exam mode ends (either naturally or manually turned off).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `completed_naturally` | `Bool` | Whether it ran its full duration |
| `days_active` | `Int` | How many days exam mode was active |

**Example:**
```json
{
  "event": "exam_mode_deactivated",
  "properties": {
    "completed_naturally": true,
    "days_active": 7
  }
}
```

### `sick_day_activated`

**When:** User declares a sick day (reduces non-negotiable expectations).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `non_negotiables_reduced_to` | `Int` | New target non-negotiable count for the day |

**Example:**
```json
{
  "event": "sick_day_activated",
  "properties": {
    "non_negotiables_reduced_to": 1
  }
}
```

### `lockdown_settings_changed`

**When:** User changes a Lockdown setting.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `setting_name` | `String` | `"non_negotiable_added"`, `"non_negotiable_removed"`, `"non_negotiable_target_changed"`, `"weekend_mode"`, `"notification_intensity"` |

**Example:**
```json
{
  "event": "lockdown_settings_changed",
  "properties": {
    "setting_name": "non_negotiable_added"
  }
}
```

---

## 3.6 Recovery Events

### `recovery_viewed`

**When:** User opens the RecoveryTodayView.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `has_whoop_data` | `Bool` | Whether Whoop data is available |
| `recovery_zone` | `String` | `"green"`, `"yellow"`, `"red"`, `"unknown"` |

**Example:**
```json
{
  "event": "recovery_viewed",
  "properties": {
    "has_whoop_data": true,
    "recovery_zone": "yellow"
  }
}
```

### `recovery_prescription_viewed`

**When:** User views the daily prescription card (expanded view).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `recovery_zone` | `String` | Current zone |
| `has_training_rec` | `Bool` | Whether a training recommendation is present |
| `has_bedtime_rec` | `Bool` | Whether a bedtime recommendation is present |
| `has_caffeine_rec` | `Bool` | Whether a caffeine cutoff is present |

**Example:**
```json
{
  "event": "recovery_prescription_viewed",
  "properties": {
    "recovery_zone": "yellow",
    "has_training_rec": true,
    "has_bedtime_rec": true,
    "has_caffeine_rec": true
  }
}
```

### `recovery_prescription_feedback`

**When:** User gives feedback on the daily prescription (thumbs up/down).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `helpful` | `Bool` | `true` = thumbs up, `false` = thumbs down |
| `recovery_zone` | `String` | Zone at time of feedback |

**Example:**
```json
{
  "event": "recovery_prescription_feedback",
  "properties": {
    "helpful": true,
    "recovery_zone": "yellow"
  }
}
```

### `sleep_detail_viewed`

**When:** User opens the sleep detail screen.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `has_whoop_sleep_data` | `Bool` | Whether Whoop sleep data is available |

**Example:**
```json
{
  "event": "sleep_detail_viewed",
  "properties": {
    "has_whoop_sleep_data": true
  }
}
```

### `strain_detail_viewed`

**When:** User opens the strain detail screen.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `has_whoop_strain_data` | `Bool` | Whether Whoop strain data is available |

**Example:**
```json
{
  "event": "strain_detail_viewed",
  "properties": {
    "has_whoop_strain_data": true
  }
}
```

### `recovery_trends_viewed`

**When:** User opens the recovery trends screen.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `time_range` | `String` | `"7d"`, `"30d"`, `"90d"` |
| `trend_type` | `String` | `"recovery"`, `"sleep"`, `"strain"`, `"hrv"` |

**Example:**
```json
{
  "event": "recovery_trends_viewed",
  "properties": {
    "time_range": "30d",
    "trend_type": "recovery"
  }
}
```

### `whoop_connected`

**When:** Whoop OAuth flow completes successfully (outside of onboarding).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `source` | `String` | `"settings"`, `"recovery_prompt"`, `"dashboard_prompt"` |

**Example:**
```json
{
  "event": "whoop_connected",
  "properties": {
    "source": "settings"
  }
}
```

### `whoop_synced`

**When:** A Whoop data sync completes (webhook or poll).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `sync_type` | `String` | `"webhook"`, `"poll"`, `"manual"` |
| `data_types_updated` | `Array<String>` | `["recovery", "sleep", "strain", "workout"]` |

**Example:**
```json
{
  "event": "whoop_synced",
  "properties": {
    "sync_type": "webhook",
    "data_types_updated": ["recovery", "sleep"]
  }
}
```

### `whoop_disconnected`

**When:** User disconnects Whoop from settings.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `days_connected` | `Int` | How many days Whoop was connected |

**Example:**
```json
{
  "event": "whoop_disconnected",
  "properties": {
    "days_connected": 45
  }
}
```

### `recovery_historical_compared`

**When:** User views the historical comparison screen (compare today vs. past days).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `comparison_type` | `String` | `"vs_yesterday"`, `"vs_last_week"`, `"vs_personal_average"` |

**Example:**
```json
{
  "event": "recovery_historical_compared",
  "properties": {
    "comparison_type": "vs_last_week"
  }
}
```

---

## 3.7 Arena Events

### `arena_viewed`

**When:** User opens the Arena main screen.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `current_level` | `Int` | User's current level |
| `friend_count` | `Int` | Number of friends |
| `active_challenges` | `Int` | Number of active challenges |

**Example:**
```json
{
  "event": "arena_viewed",
  "properties": {
    "current_level": 8,
    "friend_count": 4,
    "active_challenges": 2
  }
}
```

### `arena_leaderboard_viewed`

**When:** User opens or switches the leaderboard.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `period` | `String` | `"daily"`, `"weekly"`, `"monthly"`, `"all_time"` |
| `user_rank` | `Int` | User's rank in the viewed leaderboard |
| `leaderboard_size` | `Int` | Total participants |

**Example:**
```json
{
  "event": "arena_leaderboard_viewed",
  "properties": {
    "period": "weekly",
    "user_rank": 3,
    "leaderboard_size": 8
  }
}
```

### `friend_request_sent`

**When:** User sends a friend request.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `source` | `String` | `"search"`, `"qr_code"`, `"share_link"`, `"suggestion"` |

**Example:**
```json
{
  "event": "friend_request_sent",
  "properties": {
    "source": "search"
  }
}
```

### `friend_request_accepted`

**When:** User accepts an incoming friend request.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `new_friend_count` | `Int` | Total friends after accepting |

**Example:**
```json
{
  "event": "friend_request_accepted",
  "properties": {
    "new_friend_count": 5
  }
}
```

### `friend_request_declined`

**When:** User declines a friend request.

**Properties:** None.

**Example:**
```json
{
  "event": "friend_request_declined",
  "properties": {}
}
```

### `friend_removed`

**When:** User removes a friend.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `remaining_friend_count` | `Int` | Friends remaining |

**Example:**
```json
{
  "event": "friend_removed",
  "properties": {
    "remaining_friend_count": 3
  }
}
```

### `challenge_created`

**When:** User creates a new challenge.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `metric` | `String` | `"xp"`, `"study_minutes"`, `"workouts"`, `"streak"`, `"steps"` |
| `duration_days` | `Int` | Challenge duration in days |
| `invited_count` | `Int` | Number of friends invited |

**Example:**
```json
{
  "event": "challenge_created",
  "properties": {
    "metric": "study_minutes",
    "duration_days": 7,
    "invited_count": 3
  }
}
```

### `challenge_joined`

**When:** User joins an existing challenge (via invitation or browse).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `metric` | `String` | Challenge metric |
| `source` | `String` | `"invitation"`, `"browse"`, `"notification"` |
| `participants_count` | `Int` | Total participants at time of joining |

**Example:**
```json
{
  "event": "challenge_joined",
  "properties": {
    "metric": "xp",
    "source": "invitation",
    "participants_count": 4
  }
}
```

### `challenge_completed`

**When:** A challenge the user is in finishes (end date reached).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `metric` | `String` | Challenge metric |
| `rank` | `Int` | User's final rank |
| `participants_count` | `Int` | Total participants |
| `won` | `Bool` | Whether the user won (rank == 1) |
| `duration_days` | `Int` | Challenge duration |

**Example:**
```json
{
  "event": "challenge_completed",
  "properties": {
    "metric": "study_minutes",
    "rank": 2,
    "participants_count": 4,
    "won": false,
    "duration_days": 7
  }
}
```

### `challenge_left`

**When:** User leaves a challenge before it ends.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `metric` | `String` | Challenge metric |
| `days_remaining` | `Int` | Days left in the challenge |
| `current_rank` | `Int` | Rank when leaving |

**Example:**
```json
{
  "event": "challenge_left",
  "properties": {
    "metric": "xp",
    "days_remaining": 3,
    "current_rank": 4
  }
}
```

### `achievement_earned`

**When:** User earns a new badge/achievement.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `badge_id` | `String` | Unique badge identifier |
| `category` | `String` | `"streak"`, `"workout"`, `"study"`, `"nutrition"`, `"social"`, `"recovery"`, `"milestone"` |
| `total_badges` | `Int` | User's total badge count after earning this one |

**Example:**
```json
{
  "event": "achievement_earned",
  "properties": {
    "badge_id": "streak_30",
    "category": "streak",
    "total_badges": 12
  }
}
```

### `achievement_viewed`

**When:** User taps on an achievement to view its detail.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `badge_id` | `String` | Badge identifier |
| `is_earned` | `Bool` | Whether user has this badge (vs. viewing a locked one) |

**Example:**
```json
{
  "event": "achievement_viewed",
  "properties": {
    "badge_id": "streak_30",
    "is_earned": true
  }
}
```

### `xp_earned`

**When:** User earns XP from any source.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `source` | `String` | `"workout"`, `"study"`, `"nutrition"`, `"recovery"`, `"steps"`, `"non_negotiable_bonus"`, `"streak_multiplier"`, `"challenge"`, `"pr"` |
| `amount` | `Int` | XP amount earned |
| `is_penalty` | `Bool` | Whether this is an XP deduction |

**Example:**
```json
{
  "event": "xp_earned",
  "properties": {
    "source": "workout",
    "amount": 150,
    "is_penalty": false
  }
}
```

### `level_up`

**When:** User reaches a new level.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `new_level` | `Int` | The new level |
| `total_xp` | `Int` | Total XP at time of level up |

**Example:**
```json
{
  "event": "level_up",
  "properties": {
    "new_level": 13,
    "total_xp": 16900
  }
}
```

### `social_feed_viewed`

**When:** User opens the social activity feed.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `feed_items_count` | `Int` | Number of items in the feed |

**Example:**
```json
{
  "event": "social_feed_viewed",
  "properties": {
    "feed_items_count": 15
  }
}
```

### `social_feed_scrolled`

**When:** User scrolls through the social feed (fires once per scroll session, not per pixel).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `items_viewed` | `Int` | Number of feed items that appeared on screen |
| `deepest_item_index` | `Int` | Furthest feed item index scrolled to |

**Example:**
```json
{
  "event": "social_feed_scrolled",
  "properties": {
    "items_viewed": 8,
    "deepest_item_index": 12
  }
}
```

### `activity_reacted`

**When:** User reacts to a friend's activity in the feed.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `reaction_type` | `String` | `"fire"`, `"clap"`, `"fist_bump"`, `"trophy"` |
| `activity_type` | `String` | `"workout"`, `"streak"`, `"pr"`, `"challenge_win"`, `"level_up"` |

**Example:**
```json
{
  "event": "activity_reacted",
  "properties": {
    "reaction_type": "fire",
    "activity_type": "pr"
  }
}
```

### `friend_profile_viewed`

**When:** User views a friend's profile.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `source` | `String` | `"leaderboard"`, `"feed"`, `"friend_list"`, `"challenge"` |

**Example:**
```json
{
  "event": "friend_profile_viewed",
  "properties": {
    "source": "leaderboard"
  }
}
```

### `arena_share_link_generated`

**When:** User generates a share link (for inviting friends to Tempo).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `share_type` | `String` | `"friend_invite"`, `"challenge_invite"`, `"achievement_brag"` |

**Example:**
```json
{
  "event": "arena_share_link_generated",
  "properties": {
    "share_type": "friend_invite"
  }
}
```

---

## 3.8 Notification Events

### `notification_received`

**When:** A push notification is delivered to the device (tracked via `UNNotificationServiceExtension`).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `channel` | `String` | `"morning_briefing"`, `"gentle_reminder"`, `"firm_warning"`, `"urgent_warning"`, `"aggressive_warning"`, `"final_warning"`, `"all_clear"`, `"streak_at_risk"`, `"arena_update"`, `"weekly_report"`, `"challenge_update"`, `"friend_activity"`, `"re_engagement"` |
| `notification_id` | `String` | Unique ID for this notification |
| `app_state` | `String` | `"foreground"`, `"background"`, `"terminated"` |

**Example:**
```json
{
  "event": "notification_received",
  "properties": {
    "channel": "morning_briefing",
    "notification_id": "notif_abc123",
    "app_state": "background"
  }
}
```

### `notification_opened`

**When:** User taps the notification to open the app.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `channel` | `String` | Notification channel |
| `notification_id` | `String` | Notification ID (links to `notification_received`) |
| `time_to_open_seconds` | `Int` | Seconds between delivery and tap |

**Example:**
```json
{
  "event": "notification_opened",
  "properties": {
    "channel": "morning_briefing",
    "notification_id": "notif_abc123",
    "time_to_open_seconds": 45
  }
}
```

### `notification_action_tapped`

**When:** User taps an action button on the notification (not just the notification body).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `channel` | `String` | Notification channel |
| `action` | `String` | `"view_day"`, `"start_workout"`, `"start_timer"`, `"view_leaderboard"`, `"open_lockdown"` |
| `notification_id` | `String` | Notification ID |

**Example:**
```json
{
  "event": "notification_action_tapped",
  "properties": {
    "channel": "morning_briefing",
    "action": "start_workout",
    "notification_id": "notif_abc123"
  }
}
```

### `notification_dismissed`

**When:** User swipes away or clears a notification without opening it (detectable via `UNUserNotificationCenter` delegate).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `channel` | `String` | Notification channel |
| `notification_id` | `String` | Notification ID |

**Example:**
```json
{
  "event": "notification_dismissed",
  "properties": {
    "channel": "firm_warning",
    "notification_id": "notif_def456"
  }
}
```

### `notification_settings_changed`

**When:** User changes notification settings in the app.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `channel` | `String` | Which channel was changed. `"all"` if global toggle. |
| `new_state` | `String` | `"enabled"`, `"disabled"` |
| `intensity` | `String` | `"gentle"`, `"firm"`, `"drill_sergeant"` (if intensity was changed) |

**Example:**
```json
{
  "event": "notification_settings_changed",
  "properties": {
    "channel": "aggressive_warning",
    "new_state": "disabled"
  }
}
```

### `notification_permission_changed`

**When:** User changes notification permission at the OS level (detected via `UNUserNotificationCenter` on app foreground).

**Properties:**
| Property | Type | Description |
|---|---|---|
| `new_status` | `String` | `"authorized"`, `"denied"`, `"provisional"`, `"ephemeral"` |
| `previous_status` | `String` | Previous permission status |

**Example:**
```json
{
  "event": "notification_permission_changed",
  "properties": {
    "new_status": "denied",
    "previous_status": "authorized"
  }
}
```

---

## 3.9 Integration Events

### `integration_connected`

**When:** An integration is connected outside of onboarding.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `integration_type` | `String` | `"whoop"`, `"nutritrack"`, `"healthkit"`, `"calendar"` |
| `source` | `String` | `"settings"`, `"prompt"`, `"recovery_module"`, `"dashboard"` |

**Example:**
```json
{
  "event": "integration_connected",
  "properties": {
    "integration_type": "nutritrack",
    "source": "settings"
  }
}
```

### `integration_disconnected`

**When:** An integration is disconnected.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `integration_type` | `String` | Integration type |
| `days_connected` | `Int` | How long it was connected |

**Example:**
```json
{
  "event": "integration_disconnected",
  "properties": {
    "integration_type": "whoop",
    "days_connected": 30
  }
}
```

### `integration_sync_failed`

**When:** An integration sync attempt fails.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `integration_type` | `String` | Integration type |
| `error_type` | `String` | `"auth_expired"`, `"server_error"`, `"timeout"`, `"rate_limited"` |
| `retry_count` | `Int` | Number of retries attempted |

**Example:**
```json
{
  "event": "integration_sync_failed",
  "properties": {
    "integration_type": "whoop",
    "error_type": "auth_expired",
    "retry_count": 3
  }
}
```

---

## 3.10 Settings Events

### `settings_viewed`

**When:** User opens the settings screen.

**Properties:** None.

### `settings_changed`

**When:** User changes any setting.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `setting_category` | `String` | `"profile"`, `"training"`, `"accountability"`, `"notifications"`, `"integrations"`, `"appearance"`, `"privacy"` |
| `setting_name` | `String` | Specific setting changed |

**Example:**
```json
{
  "event": "settings_changed",
  "properties": {
    "setting_category": "appearance",
    "setting_name": "dark_mode"
  }
}
```

### `account_deleted`

**When:** User deletes their account.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `days_since_signup` | `Int` | Account age in days |
| `total_xp` | `Int` | XP at time of deletion |

**Example:**
```json
{
  "event": "account_deleted",
  "properties": {
    "days_since_signup": 45,
    "total_xp": 8500
  }
}
```

### `feedback_submitted`

**When:** User submits in-app feedback.

**Properties:**
| Property | Type | Description |
|---|---|---|
| `feedback_type` | `String` | `"bug_report"`, `"feature_request"`, `"general"` |
| `source_screen` | `String` | Screen the feedback was submitted from |

**Example:**
```json
{
  "event": "feedback_submitted",
  "properties": {
    "feedback_type": "feature_request",
    "source_screen": "RecoveryTodayView"
  }
}
```

---

# 4. Funnel Definitions

## Funnel 1: Onboarding Funnel

**Goal:** Measure how many users who install the app become fully onboarded.

| Step | Event | Expected Conversion (step-to-step) | Expected Conversion (from Install) |
|---|---|---|---|
| 1. Install | (App Store download -- tracked via App Store Connect, not PostHog) | -- | 100% |
| 2. First Open | `app_launched` (first ever) | 85% of installs | 85% |
| 3. Start Onboarding | `onboarding_started` | 95% | 81% |
| 4. Sign in with Apple | `onboarding_step_completed` (step 2) | 85% | 69% |
| 5. Complete Profile | `onboarding_step_completed` (step 3) | 92% | 63% |
| 6. Complete Life Setup | `onboarding_step_completed` (step 6) | 80% | 50% |
| 7. Connect 1+ Integration | `onboarding_integration_connected` (any) | 70% | 35% |
| 8. Complete Onboarding | `onboarding_completed` | 85% | 30% |
| 9. Day 1 Activity | Any meaningful action on Day 1 after onboarding | 80% | 24% |

**Key Drop-off Points to Monitor:**
- Step 4 (Sign in): Users who refuse Apple sign-in. Mitigation: better value prop on step 2.
- Step 6 (Life Setup): 3-step configuration flow may feel long. Mitigation: pre-fill from HealthKit where possible.
- Step 7 (Integration): Users without Whoop may feel the app isn't for them. Mitigation: emphasize HealthKit-only mode works great.

**Alert:** If step 3-to-4 conversion drops below 75%, investigate immediately -- this likely means a sign-in bug.

---

## Funnel 2: Activation Funnel

**Goal:** Measure whether new users reach the "aha moment" within their first 7 days. Hypothesis: users who complete all four activation steps within 7 days have 3x higher D30 retention.

| Step | Event | Expected Completion (within D7) |
|---|---|---|
| 1. Day 1 active | Any meaningful action on Day 1 | 100% (base of funnel) |
| 2. Complete first non-negotiable | `non_negotiable_completed` | 70% |
| 3. Log first workout | `workout_completed` | 45% |
| 4. View first weekly report | `weekly_report_viewed` | 25% (only possible after D7) |

**Activation definition:** User is "activated" when they have completed steps 1-3. Step 4 is a bonus indicator.

**Target:** >= 40% of D1 users reach "activated" status by D7.

---

## Funnel 3: Workout Funnel

**Goal:** Measure the workout completion flow.

| Step | Event | Expected Conversion (step-to-step) |
|---|---|---|
| 1. View workout | `workout_viewed` | 100% (base) |
| 2. Start workout | `workout_started` | 65% |
| 3. Complete first exercise | `workout_exercise_completed` (exercise_order = 1) | 92% |
| 4. Complete workout | `workout_completed` | 80% |

**Abandonment tracking:** `workout_abandoned` with `exercises_completed` and `duration_seconds` tells us where users bail. If >20% of users abandon after completing 0 exercises, the workout prescription may be too intimidating.

---

## Funnel 4: Social Funnel

**Goal:** Measure social feature adoption from first view to sustained engagement.

| Step | Event | Expected Conversion (step-to-step) | Timeframe |
|---|---|---|---|
| 1. View Arena | `arena_viewed` | 100% (base) | -- |
| 2. Add first friend | `friend_request_sent` OR `friend_request_accepted` | 40% | Within 7 days of first Arena view |
| 3. Join first challenge | `challenge_joined` OR `challenge_created` | 50% of step 2 | Within 14 days |
| 4. Complete first challenge | `challenge_completed` | 70% of step 3 | Within 30 days |

**Key insight:** Users who add their first friend within 48 hours of first opening Arena have 2x the challenge completion rate. Optimize for speed-to-first-friend.

---

## Funnel 5: Retention Funnel (Cohort-Based)

**Goal:** Track week-over-week retention curves.

| Step | Definition | Target |
|---|---|---|
| Week 1 active | User had >= 3 active days in days 1-7 | 60% |
| Week 2 active | User had >= 3 active days in days 8-14 | 45% |
| Week 4 active | User had >= 3 active days in days 22-28 | 30% |
| Week 8 active | User had >= 3 active days in days 50-56 | 22% |
| Week 12 active | User had >= 3 active days in days 78-84 | 18% |

**The "smile" we want to see:** After an initial drop in weeks 1-4, the curve should flatten (indicating retained users are sticky). If the curve continues dropping linearly, core engagement mechanics are failing.

---

## Funnel 6: Focus Timer Funnel

**Goal:** Measure study session completion.

| Step | Event | Expected Conversion |
|---|---|---|
| 1. Start timer | `focus_timer_started` | 100% (base) |
| 2. Reach 50% | Derived from `focus_timer_completed` or `focus_timer_abandoned` with `completion_percentage` | 85% |
| 3. Complete timer | `focus_timer_completed` | 72% |

**Metric:** Focus timer completion rate. If < 65%, the default timer duration may be too long. Consider A/B testing shorter default sessions.

---

# 5. Cohort Analysis Definitions

## Cohort 1: By Onboarding Completeness

| Cohort | Definition | Expected D30 Retention |
|---|---|---|
| **Full Setup** | Completed all 12 onboarding steps, 0 skipped | 25% |
| **Partial Setup** | Completed onboarding but skipped 1-3 optional steps | 15% |
| **Minimal Setup** | Completed sign-in + profile but abandoned before step 7 | 8% |
| **Bounce** | Never completed sign-in (abandoned at step 1 or 2) | 2% |

**Action:** If Full Setup D30 retention is <2x Minimal Setup, the onboarding isn't adding enough value -- simplify it.

## Cohort 2: By Integrations Connected

| Cohort | Definition | Expected D30 Retention |
|---|---|---|
| **0 integrations** | No external data sources | 8% |
| **1 integration** | HealthKit only (most common) | 14% |
| **2 integrations** | HealthKit + one of (Whoop, NutriTrack, Calendar) | 20% |
| **3+ integrations** | Three or more connected | 28% |

**Action:** If 3+ integrations cohort shows dramatically better retention, invest in integration upsell prompts (e.g., "Connect Whoop to unlock Recovery module" shown after 3 days).

## Cohort 3: By Notification Intensity Setting

| Cohort | Definition |
|---|---|
| **Drill Sergeant** | Maximum notification intensity |
| **Firm** | Moderate notifications |
| **Gentle** | Minimal notifications |
| **Disabled** | All notifications off |

**Hypothesis:** Drill Sergeant users have 1.5x higher non-negotiable completion rate but may also have higher notification disable rates. Find the sweet spot.

## Cohort 4: By Primary Goal

| Cohort | Definition |
|---|---|
| **Muscle Gain** | Primary goal: muscle_gain |
| **Fat Loss** | Primary goal: fat_loss |
| **Performance** | Primary goal: performance |
| **Health** | Primary goal: health |
| **Academics** | Primary goal: academics |

**Purpose:** Different goals drive different feature usage patterns. Academics-first users may use Focus Timer heavily but Training lightly. Tailor recommendations and notifications by goal.

## Cohort 5: By Social Engagement

| Cohort | Definition |
|---|---|
| **Social Active** | Has 2+ friends AND participated in 1+ challenge in last 30 days |
| **Social Passive** | Has 1+ friend but no challenge activity in last 30 days |
| **Solo** | 0 friends |

**Hypothesis:** Social Active users have 2x D90 retention vs. Solo. If validated, prioritize friend-finding UX improvements.

## Cohort 6: By Activation Speed

| Cohort | Definition |
|---|---|
| **Fast Activators** | Completed activation (first non-negotiable + first workout) within 48 hours |
| **Slow Activators** | Completed activation within 7 days |
| **Never Activated** | Never completed activation criteria |

**Purpose:** Fast activators likely have the best retention. Understanding what drives fast activation helps optimize onboarding and D1 experience.

## Cohort 7: By Acquisition Source

| Cohort | Definition |
|---|---|
| **Organic** | No referral link, found via App Store search |
| **Friend Referral** | Came via a share link from an existing user |
| **Social** | Came from Instagram, TikTok, or other social platform |

**Purpose:** Referral users likely have higher retention (they know someone using it). Quantify the referral advantage to justify investing in referral mechanics.

---

# 6. A/B Testing Framework

## 6.1 Implementation: PostHog Feature Flags

All A/B tests are implemented via PostHog feature flags. The AnalyticsService wrapper exposes:

```swift
// Check if a feature flag is enabled for the current user
AnalyticsService.shared.isFeatureFlagEnabled("experiment_onboarding_short")

// Get the variant for a multi-variant test
AnalyticsService.shared.getFeatureFlagPayload("experiment_notification_timing") as? String
// Returns: "control", "variant_a", "variant_b"
```

**Rules:**
- All feature flag evaluations are **local** (flags are fetched on app launch and cached). No network call per evaluation.
- Flag changes take effect on next app launch (not mid-session).
- Every experiment automatically logs a `$feature_flag_called` event with the flag name and variant.

## 6.2 Statistical Standards

| Parameter | Value |
|---|---|
| **Significance threshold** | p < 0.05 (two-tailed) |
| **Minimum effect size** | 5% relative improvement (e.g., if control D7 retention is 28%, variant must show >= 29.4%) |
| **Power** | 0.80 (80% probability of detecting a true effect) |
| **Minimum sample size per variant** | Calculated per-test using the formula below |
| **Maximum test duration** | 28 days (to limit exposure to a potentially worse experience) |
| **Minimum test duration** | 7 days (to capture full weekly behavior cycles) |

**Sample size formula (for proportion metrics like retention):**

```
n = (Z_{alpha/2} + Z_{beta})^2 * (p1(1-p1) + p2(1-p2)) / (p1 - p2)^2

Where:
  Z_{alpha/2} = 1.96 (for alpha = 0.05)
  Z_{beta} = 0.84 (for power = 0.80)
  p1 = control rate
  p2 = expected variant rate
```

## 6.3 Ten Initial A/B Test Ideas

### Test 1: Short vs. Full Onboarding

**Hypothesis:** A 6-step onboarding (Welcome, Sign-in, Quick Profile, HealthKit, Notifications, Summary) will have higher completion rate than the full 12-step onboarding, without harming D7 retention.

**Variants:**
- Control: Full 12-step onboarding
- Variant A: 6-step onboarding (integration setup moved to post-onboarding prompts)

**Primary metric:** Onboarding completion rate
**Secondary metric:** D7 retention
**Guard-rail metric:** Integration connection rate at D7 (must not drop >20%)
**Sample size:** ~2,000 per variant (assuming 30% control completion, detecting 5% absolute lift)
**Duration:** 14 days

### Test 2: Notification Intensity Default

**Hypothesis:** Defaulting new users to "Firm" (medium) intensity will result in better D30 retention than defaulting to "Drill Sergeant" (maximum), because fewer users will disable notifications entirely.

**Variants:**
- Control: Default to Drill Sergeant
- Variant A: Default to Firm

**Primary metric:** D30 retention
**Secondary metric:** Notification disable rate at D14
**Sample size:** ~3,500 per variant
**Duration:** 30 days (need to measure D30)

### Test 3: Streak Freeze Availability

**Hypothesis:** Giving users 2 streak freezes per month (vs. 1) will increase D30 streak retention without reducing daily completion rates.

**Variants:**
- Control: 1 streak freeze per month
- Variant A: 2 streak freezes per month
- Variant B: 0 streak freezes (hardcore mode)

**Primary metric:** % of users with active streak at D30
**Secondary metric:** Non-negotiable daily completion rate
**Sample size:** ~2,500 per variant
**Duration:** 30 days

### Test 4: Social Prompt Timing

**Hypothesis:** Showing an "Add your first friend" prompt on Day 3 (after the user is comfortable with the app) will result in higher friend-add rates than showing it during onboarding (Step 11).

**Variants:**
- Control: Arena setup during onboarding (Step 11)
- Variant A: Skip Step 11, show in-app prompt on Day 3
- Variant B: Skip Step 11, show in-app prompt on Day 7

**Primary metric:** % of users with 1+ friend at D14
**Secondary metric:** Arena engagement rate at D14
**Sample size:** ~2,000 per variant
**Duration:** 21 days

### Test 5: Morning Briefing Personalization Depth

**Hypothesis:** Highly personalized morning briefings (mentioning specific numbers like "you need 97 more minutes of study") will have higher open rates than generic motivational ones.

**Variants:**
- Control: Current drill-sergeant copy (specific but number-heavy)
- Variant A: Simplified copy (motivational, fewer numbers)

**Primary metric:** Morning briefing open rate
**Secondary metric:** Non-negotiable completion rate on days when briefing is opened
**Sample size:** ~1,500 per variant
**Duration:** 14 days

### Test 6: Workout Difficulty Entry Point

**Hypothesis:** Showing a "Quick Start" workout option (no planning, just log exercises) alongside the AI-prescribed workout will increase workout starts among users who feel the prescribed workout is too rigid.

**Variants:**
- Control: Only AI-prescribed workout shown
- Variant A: AI-prescribed + "Quick Start" (free-form logging) option

**Primary metric:** `workout_started` events per user per week
**Secondary metric:** `workout_completed` rate
**Guard-rail metric:** AI-prescribed workout completion rate (must not drop >15%)
**Sample size:** ~2,000 per variant
**Duration:** 21 days

### Test 7: Focus Timer Default Duration

**Hypothesis:** A 25-minute default (Pomodoro) will have a higher completion rate than a 50-minute default, leading to more total study sessions per day.

**Variants:**
- Control: 25-minute default
- Variant A: 50-minute default
- Variant B: User chooses on first use (no default)

**Primary metric:** Focus timer completion rate
**Secondary metric:** Total study minutes per user per day
**Sample size:** ~1,500 per variant
**Duration:** 14 days

### Test 8: Leaderboard Visibility

**Hypothesis:** Showing a mini-leaderboard widget on the Dashboard (always visible) will increase Arena engagement vs. only showing it in the Arena tab.

**Variants:**
- Control: Leaderboard only in Arena tab
- Variant A: Mini-leaderboard widget on Dashboard (top 3 friends + user's rank)

**Primary metric:** Arena weekly engagement rate
**Secondary metric:** Sessions per day (does the widget increase app opens?)
**Guard-rail metric:** Dashboard bounce rate (does the widget make the dashboard feel cluttered?)
**Sample size:** ~2,000 per variant
**Duration:** 14 days

### Test 9: Re-engagement Notification Copy

**Hypothesis:** Loss-aversion copy ("Your 12-day streak is about to die") will be more effective at re-engaging lapsed users than positive copy ("Your friends miss you on the leaderboard").

**Variants:**
- Control: Loss-aversion copy
- Variant A: Social proof copy
- Variant B: Achievement copy ("You're 200 XP from Level 10")

**Primary metric:** Re-engagement notification open rate
**Secondary metric:** D1 retention after re-engagement (did they come back the next day too?)
**Sample size:** ~1,000 per variant (lapsed users are a smaller pool)
**Duration:** 21 days

### Test 10: Weekly Report Delivery Day

**Hypothesis:** Delivering the weekly report on Sunday evening (reflective mood) will have a higher open rate than Monday morning (action-oriented mood).

**Variants:**
- Control: Monday 7 AM
- Variant A: Sunday 8 PM
- Variant B: Saturday 10 AM

**Primary metric:** Weekly report notification open rate
**Secondary metric:** `weekly_report_viewed` rate
**Sample size:** ~1,500 per variant
**Duration:** 21 days (3 weekly report cycles)

---

# 7. Dashboard for Metrics

## 7.1 Internal Analytics Dashboard Layout

Built in PostHog dashboards (or Grafana if self-hosted). Three tiers of dashboards:

### Tier 1: Daily Command Center (Check every morning)

| Panel | Metric | Update Frequency |
|---|---|---|
| **DAU** | Today's DAU, 7-day trend line | Real-time |
| **New Users** | Signups today, onboarding completion rate today | Real-time |
| **D1 Retention** | Yesterday's D1 retention (users who signed up 2 days ago and came back yesterday) | Daily at 6 AM UTC |
| **Streak Health** | % of DAU with active streak, average streak length | Daily |
| **Non-Negotiable Completion** | Today's completion rate (updates throughout the day) | Real-time |
| **Crash-Free Rate** | % of sessions without crashes (Crashlytics) | Real-time |
| **Error Rate** | `error_occurred` events per 1K sessions | Real-time |

### Tier 2: Weekly Growth Board (Review every Monday)

| Panel | Metric | Update Frequency |
|---|---|---|
| **WAU and MAU** | Trailing 7-day and 28-day unique users, WoW change | Daily |
| **Stickiness** | DAU/MAU ratio, 7-day trend | Daily |
| **Retention Curves** | D1, D7, D30 by weekly cohort | Daily |
| **Onboarding Funnel** | Full funnel conversion rates, WoW change | Daily |
| **Feature Adoption** | % of D14 users who tried each module | Daily |
| **Notification Effectiveness** | Open rate by channel, disable rate | Daily |
| **Arena Health** | Friends per user distribution, challenge participation rate | Daily |
| **Active A/B Tests** | Current experiments with interim results (flagged if significance reached) | Daily |

### Tier 3: Monthly Deep Dive (Review first Monday of month)

| Panel | Metric |
|---|---|
| **Cohort Retention Matrix** | Full retention grid (D1 through D90) for each weekly signup cohort |
| **Cohort Comparison** | Retention by onboarding completeness, integrations, social engagement |
| **Churn Analysis** | Top churn signals, churn risk distribution |
| **Feature Engagement Depth** | Per-module usage frequency and session time |
| **Funnel Conversion Trends** | All 6 funnels over time |
| **A/B Test Results** | Completed tests with statistical analysis and recommendations |
| **User Segment Evolution** | How segment sizes are changing over time |

## 7.2 Real-Time vs. Daily Aggregation

| Data | Processing | Rationale |
|---|---|---|
| DAU, active users right now | **Real-time** | Need to spot outages immediately |
| Event counts, error rates | **Real-time** | Operational alerting |
| Crash-free rate | **Real-time** | Operational alerting |
| Retention (D1, D7, D30) | **Daily at 6 AM UTC** | Requires full-day data to be meaningful |
| Cohort analysis | **Daily** | Batch computation |
| Funnel conversions | **Daily** | Requires full-day data |
| A/B test significance | **Daily** | Frequent checks inflate false positive rate (p-hacking) |

## 7.3 Alert Thresholds

Alerts are sent via Slack webhook to a `#tempo-alerts` channel and email to the core team.

| Alert | Condition | Severity | Action |
|---|---|---|---|
| **D1 Retention Crash** | D1 retention drops below 25% for 2 consecutive days | Critical | Investigate: bad build? Onboarding broken? Server outage? |
| **Crash Spike** | Crash-free rate drops below 99.0% | Critical | Check Crashlytics for new crash cluster |
| **Onboarding Drop** | Step 2 (Sign-in) conversion drops below 75% | Critical | Apple Sign-in may be broken |
| **DAU Anomaly** | DAU drops >20% vs. same day last week | High | Investigate: server issue? App Store review rejection? |
| **Error Spike** | Error rate exceeds 50 per 1K sessions | High | Check error_type distribution |
| **Notification Disable Spike** | Notification disable rate exceeds 5% in a single day | Medium | Review notification frequency and copy |
| **Sync Failure Rate** | >10% of sync attempts failing | Medium | Check integration API status |
| **Streak Collapse** | Average streak length drops >20% WoW | Medium | Check if a bad build is breaking streak tracking |
| **Workout Abandonment Spike** | Workout abandonment rate exceeds 40% | Medium | Check for UX issue in workout logging |

---

# 8. User Segmentation

## Segment Definitions

### Power Users

**Definition:** Active on 6+ of the last 7 days AND average daily non-negotiable completion rate >= 80% AND have completed 3+ workouts in the last 7 days.

**Identification query:**
```sql
SELECT user_id FROM daily_activity
WHERE date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY user_id
HAVING
  COUNT(DISTINCT date) >= 6
  AND AVG(non_negotiables_completed::float / NULLIF(non_negotiables_total, 0)) >= 0.8
  AND SUM(CASE WHEN workout_completed THEN 1 ELSE 0 END) >= 3
```

**Expected size:** 8-12% of DAU
**Value:** These are the users to protect. High LTV, likely referrers. Never annoy them.
**Treatment:** Lighter notification frequency (they don't need the drill sergeant as much). Prioritize Arena features and challenges to keep them engaged.

### Casual Users

**Definition:** Active on 2-4 of the last 7 days AND average non-negotiable completion rate between 30-60%.

**Expected size:** 30-40% of WAU
**Value:** Largest opportunity for conversion to Power Users.
**Treatment:** Focus on habit formation -- streak mechanics, gentle-to-firm notification escalation, simplify their non-negotiable list if they have too many.

### At-Risk Users

**Definition:** Were active (DAU) at any point in the last 30 days but have had no activity for 3+ consecutive days AND are not in "sick day" or "exam mode."

**Expected size:** 15-20% of MAU
**Value:** Urgent re-engagement needed. Each day of inactivity reduces return probability by ~15%.
**Treatment:** Re-engagement notification sequence. If they return, show a "welcome back" flow that reduces friction (suggest fewer non-negotiables to rebuild the habit).

### Social Butterflies

**Definition:** 5+ friends AND sent 3+ reactions in the last 7 days AND active in at least 1 challenge.

**Expected size:** 5-8% of DAU
**Value:** Network multipliers. Each Social Butterfly likely keeps 2-3 friends retained through social pressure.
**Treatment:** Feed them challenge features, friend-invite rewards, and social achievements. They are your organic growth engine.

### Solo Warriors

**Definition:** 0 friends AND have been active for 14+ days AND average daily non-negotiable completion rate >= 70%.

**Expected size:** 10-15% of DAU
**Value:** High intrinsic motivation. They don't need social features to be retained but may churn if the app feels "too social."
**Treatment:** Never force social features on them. Optimize their experience around personal bests, progress charts, and self-competition. Occasionally (once per month) show a gentle "you might enjoy competing with friends" prompt, but respect a dismissal.

### Gym Rats

**Definition:** 4+ workouts in the last 7 days AND study target completion rate < 40% in the last 7 days.

**Expected size:** 5-10% of active users
**Value:** Training is their primary use case. Risk: if they don't see value in accountability, they may leave for a pure training app.
**Treatment:** Emphasize the training-recovery loop (Whoop integration). Frame study targets as "mental training." Use Arena challenges focused on training metrics to keep them engaged.

### Scholars

**Definition:** Study target completion rate >= 80% in the last 7 days AND 1 or fewer workouts in the last 7 days.

**Expected size:** 5-10% of active users
**Value:** Academics is their primary use case. Risk: if they don't train, they miss half the app's value.
**Treatment:** Use recovery data to recommend light workouts ("Even 20 minutes of walking improves focus"). Frame training as study enhancement, not a separate obligation. Consider suggesting a "Study + Walk" non-negotiable combo.

### New Users (First 7 Days)

**Definition:** Account created within the last 7 days.

**Expected size:** Variable (depends on acquisition)
**Value:** The most fragile segment. D1 and D7 decisions define their trajectory.
**Treatment:** Maximum onboarding attention. Celebrate every first action (first non-negotiable, first workout, first focus session). Suppress Arena/social features until Day 3-4 to avoid overwhelming.

### Churned Users

**Definition:** Were active at any point but have had no activity for 14+ consecutive days.

**Expected size:** Grows over time
**Value:** Win-back opportunity. Re-engagement gets exponentially harder after 30 days.
**Treatment:** Win-back push notification sequence at Day 14, Day 21, Day 30. After Day 30, reduce to monthly. After 90 days of no activity, stop sending notifications entirely (respect the user).

---

# 9. Privacy Compliance for Analytics

## 9.1 Data That NEVER Goes to Analytics

The following data categories are PROHIBITED from being included in any analytics event, user property, or metadata:

### Health Biometrics (NEVER)
- Heart rate (resting, active, max)
- Heart rate variability (HRV)
- Recovery score (Whoop percentage)
- Sleep score, sleep hours, sleep stages
- Strain score
- Calories consumed, protein, carbs, fat, macros
- Body weight, body fat percentage, body measurements
- Step count (the actual number -- we track "steps goal met" as a boolean but never the count)
- Blood oxygen, respiratory rate, or any HealthKit quantity

### Personally Identifiable Information (NEVER)
- Real name (first, last)
- Email address
- Phone number
- Apple ID or Apple user identifier
- IP address (anonymized at ingestion -- see 9.4)
- Physical address or location coordinates
- Date of birth or age (we may track age_range as a broad bucket if ever needed, but not exact age)
- Photos, profile pictures, or any image data
- Device IDFA / IDFV (we use our own anonymous user_id)

### Content Data (NEVER)
- Exercise names, specific weights, or specific rep counts (we track completion rates and counts, not the content)
- Study subjects, class names, or exam names
- Calendar event titles or descriptions
- Notification message body text
- Any free-text input the user types
- Chat messages or social feed content
- Username (we track friend_count, not which friends)

## 9.2 User Opt-Out Mechanism

### In-App Opt-Out

Settings > Privacy > Analytics

Three options:
1. **Full Analytics** (default) -- All behavioral tracking as described in this document.
2. **Essential Only** -- Only crash reports and error_occurred events. No behavioral tracking, no funnels, no session recording.
3. **None** -- No data sent to any analytics service. Crash reports still sent to Apple via standard iOS crash reporting (cannot be disabled by the app).

**Implementation:**
```swift
enum AnalyticsConsent: String, Codable {
    case full       // All events
    case essential  // Crashes + errors only
    case none       // Nothing sent
}

// Stored in UserDefaults, NOT synced to backend
// Default: .full (set during onboarding with explicit disclosure)
```

**When user changes setting:**
- Take effect immediately (no app restart required).
- If changed from `full` to `essential` or `none`, send one final event: `analytics_consent_changed` with `new_state` property, then stop all tracking.
- Do NOT retroactively delete already-sent events from PostHog (that's covered by GDPR deletion request -- see 9.3).

### App Tracking Transparency (ATT)

Tempo does NOT use IDFA, does NOT run ads, and does NOT perform cross-app tracking. Therefore:
- **ATT prompt is NOT required.** We do not need to show the "Allow app to track your activity" dialog.
- If Apple's review team questions this: our analytics use only a first-party anonymous identifier, no third-party advertising SDKs are present, and no data is shared with advertising networks.

## 9.3 GDPR Article 17 Compliance (Right to Erasure)

### User-Initiated Deletion

When a user deletes their account (Settings > Account > Delete Account):

1. **Backend:** Delete all user data from PostgreSQL (users, xp_events, friendships, challenges, achievements). Cascade delete.
2. **iOS:** Wipe all SwiftData models. Clear UserDefaults. Clear Keychain tokens.
3. **PostHog:** Send a `$delete` request via PostHog API to delete the user's distinct_id and all associated events.
   ```
   POST https://app.posthog.com/api/persons/{distinct_id}/delete/
   ```
4. **Crashlytics:** Firebase does not support per-user deletion. However, Crashlytics data is anonymous (no PII attached), so this is compliant.
5. **Timeline:** Deletion completes within **72 hours** (PostHog batch processing may take up to 48 hours).
6. **Confirmation:** User receives an in-app confirmation immediately. If they provided an email during Apple Sign-in (not hidden), send an email confirming deletion within 24 hours.

### Data Subject Access Request (DSAR)

If a user requests their data (Settings > Privacy > Request My Data):

1. Backend compiles a JSON export of all user data (profile, XP history, workout logs, study sessions, etc.).
2. Analytics data (PostHog events) is NOT included in the export because it contains no PII and is not meaningful to the user.
3. Export is available for download within 48 hours.
4. Export link expires after 7 days.

## 9.4 IP Anonymization

PostHog is configured to anonymize IP addresses at ingestion:

```python
# PostHog configuration (if self-hosted)
POSTHOG_IP_ANONYMIZE = True  # Zeroes out the last octet: 192.168.1.123 → 192.168.1.0
```

If using PostHog Cloud: enable "Anonymize IPs" in Project Settings. This strips the IP before it reaches PostHog's storage layer.

**Additionally:** The AnalyticsService wrapper on iOS sets `posthog.optOut = false` and configures:
```swift
let config = PostHogConfig(apiKey: "phc_xxx")
config.captureApplicationLifecycleEvents = true
config.sessionReplay = true
config.sessionReplayConfig.maskAllTextInputs = true  // Mask all text in session replays
config.sessionReplayConfig.maskAllImages = true       // Mask all images in session replays
```

## 9.5 Analytics Data Retention Policy

| Data Type | Retention Period | Rationale |
|---|---|---|
| Raw events | 12 months | Sufficient for year-over-year comparison. Older events are aggregated and raw data deleted. |
| Aggregated metrics (DAU, retention, funnels) | Indefinite | Small data footprint, needed for long-term trend analysis. |
| Session replays | 30 days | Large storage footprint. Only needed for debugging recent UX issues. |
| User properties | Until account deletion or 24 months of inactivity | Inactive users' properties are purged after 24 months. |
| A/B test event data | 6 months after test conclusion | Needed for post-analysis. Deleted after. |
| Crash reports (Crashlytics) | 90 days (Firebase default) | Sufficient for fixing crash regressions. |

**Automated purge:** A monthly cron job on the backend (or PostHog's built-in data management) deletes events older than the retention period.

## 9.6 Privacy Policy Requirements

The app's privacy policy (linked from App Store listing and accessible in-app at Settings > Privacy > Privacy Policy) must disclose:

1. We collect anonymous usage data to improve the app.
2. We never sell data to third parties.
3. We never share health data with analytics services.
4. Users can opt out of analytics at any time (Settings > Privacy > Analytics).
5. Users can request deletion of all data (GDPR Article 17).
6. Analytics data is retained for a maximum of 12 months.
7. IP addresses are anonymized at collection.
8. No cross-app tracking is performed.
9. Crash reports are collected via Firebase Crashlytics (Google) for app stability purposes only.

## 9.7 Third-Party Data Processing Agreements

| Service | Data Processed | DPA Required | Status |
|---|---|---|---|
| **PostHog (Cloud)** | Anonymous behavioral events, session replays (text/images masked) | Yes | Sign PostHog DPA before launch |
| **PostHog (Self-Hosted)** | N/A (data stays on our infrastructure) | No | Preferred option |
| **Firebase Crashlytics** | Crash stack traces, device model, OS version (no PII) | Yes (Google DPA) | Sign Google Cloud DPA |
| **Apple (App Store Connect)** | Install counts, App Store analytics | Covered by Apple Developer Agreement | Already signed |

---

# Appendix A: Event Name Quick Reference

A sorted list of every event name defined in this document for developer reference.

```
account_deleted
achievement_earned
achievement_viewed
activity_reacted
app_backgrounded
app_foregrounded
app_launched
arena_leaderboard_viewed
arena_share_link_generated
arena_viewed
challenge_completed
challenge_created
challenge_joined
challenge_left
dashboard_date_changed
dashboard_quadrant_tapped
dashboard_refreshed
dashboard_score_viewed
dashboard_tab_switched
dashboard_viewed
error_occurred
exam_mode_activated
exam_mode_deactivated
exercise_created
exercise_searched
feedback_submitted
focus_timer_abandoned
focus_timer_completed
focus_timer_paused
focus_timer_resumed
focus_timer_started
friend_profile_viewed
friend_removed
friend_request_accepted
friend_request_declined
friend_request_sent
integration_connected
integration_disconnected
integration_sync_failed
leisure_unlocked
level_up
lockdown_settings_changed
lockdown_viewed
non_negotiable_completed
non_negotiable_missed
notification_action_tapped
notification_dismissed
notification_opened
notification_permission_changed
notification_received
notification_settings_changed
onboarding_abandoned
onboarding_academics_configured
onboarding_arena_configured
onboarding_completed
onboarding_goals_configured
onboarding_integration_connected
onboarding_integration_failed
onboarding_integration_skipped
onboarding_notification_permission_result
onboarding_profile_configured
onboarding_resumed
onboarding_started
onboarding_step_completed
onboarding_step_skipped
onboarding_step_viewed
onboarding_training_configured
pattern_viewed
pr_achieved
progress_chart_viewed
recovery_historical_compared
recovery_prescription_feedback
recovery_prescription_viewed
recovery_trends_viewed
recovery_viewed
running_session_completed
running_session_started
screen_viewed
settings_changed
settings_viewed
sick_day_activated
sleep_detail_viewed
social_feed_scrolled
social_feed_viewed
strain_detail_viewed
streak_achieved
streak_freeze_used
streak_lost
sync_completed
training_settings_changed
week_plan_regenerated
week_plan_viewed
weekly_report_shared
weekly_report_viewed
whoop_connected
whoop_disconnected
whoop_synced
widget_tapped
workout_abandoned
workout_completed
workout_exercise_completed
workout_exercise_skipped
workout_exercise_swapped
workout_rest_timer_skipped
workout_rest_timer_started
workout_set_completed
workout_started
workout_viewed
xp_earned
```

**Total event count: 89 events.**

---

# Appendix B: Implementation Checklist

For developers implementing analytics tracking:

- [ ] Install PostHog iOS SDK (`posthog-ios`) via SPM
- [ ] Install Firebase Crashlytics via SPM
- [ ] Create `AnalyticsService.swift` wrapper with all methods from Section 1.1
- [ ] Configure PostHog with IP anonymization and session replay masking
- [ ] Implement session management (5-minute timeout, 30-minute workout extension)
- [ ] Add auto-attached properties to every event (Section 1.3)
- [ ] Set user properties on every `identify()` call (Section 1.4)
- [ ] Implement all 89 events from the Event Catalog (Section 3)
- [ ] Set up PostHog feature flags for A/B testing (Section 6.1)
- [ ] Implement analytics consent toggle (Settings > Privacy > Analytics)
- [ ] Verify no health biometric or PII data leaks into any event
- [ ] Set up PostHog dashboards (Section 7)
- [ ] Configure alert webhooks to Slack (Section 7.3)
- [ ] Test GDPR deletion flow end-to-end
- [ ] Review App Store privacy nutrition labels match actual data collection
- [ ] Sign PostHog DPA (if using Cloud)
- [ ] Sign Google Cloud DPA (for Crashlytics)
- [ ] Run privacy audit: review every event payload against Section 9.1 forbidden list
