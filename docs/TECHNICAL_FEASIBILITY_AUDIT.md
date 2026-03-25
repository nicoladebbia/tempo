# Tempo -- Technical Feasibility Audit

> **Auditor Perspective:** Principal iOS Engineer, 15 years shipping apps
> **Date:** 2026-03-24
> **Scope:** Every feature in the Tempo specification, assessed for real-world technical feasibility
> **Verdict Format:** Each item rated as one of:
> - **Straightforward** -- Build it, no surprises expected
> - **Tricky** -- Achievable, but document the challenge and plan for it
> - **Problematic** -- Will not work as specified; alternative proposed

---

## Table of Contents

1. [HealthKit Limitations](#1-healthkit-limitations)
2. [Whoop API Limitations](#2-whoop-api-limitations)
3. [Notification Limitations](#3-notification-limitations)
4. [SwiftData Concerns](#4-swiftdata-concerns)
5. [Vapor Backend Concerns](#5-vapor-backend-concerns)
6. [Feature-Specific Risks](#6-feature-specific-risks)
7. [App Store Review Risks](#7-app-store-review-risks)
8. [Performance Feasibility](#8-performance-feasibility)
9. [Scalability Concerns](#9-scalability-concerns)
10. [Proposed Alternatives Summary](#10-proposed-alternatives-summary)
11. [MVP vs V2 Recommendation](#11-mvp-vs-v2-recommendation)
12. [Unknown Unknowns -- Prototyping Required](#12-unknown-unknowns----prototyping-required)

---

## 1. HealthKit Limitations

### 1.1 Whoop Data via HealthKit

**Rating: Tricky**

The spec correctly uses Whoop's own API for recovery, sleep, and strain data. However, the spec also reads heart rate, HRV, and resting HR from HealthKit, which may overlap with Whoop-written data.

**Challenges:**
- Whoop writes to HealthKit only when the Whoop app is open and synced. If the user hasn't opened Whoop today, HealthKit has zero Whoop data. The spec handles this via the backend Whoop API sync, which is correct.
- When both Apple Watch and Whoop write HR/HRV, HealthKit's source prioritization is opaque and undocumented. You cannot control which source wins for a given time window.
- Whoop does NOT write `restingHeartRate` to HealthKit -- only raw heart rate samples. The `restingHeartRate` type is only written by Apple Watch. If the user has no Apple Watch, the spec's `fetchRestingHeartRate()` from HealthKit will return nil unless Whoop API data is used instead.

**Alternative:** Always prefer Whoop API data for recovery metrics. Use HealthKit as a fallback only when Whoop is not connected. The spec already does this for recovery/sleep/strain, but the HealthKit heart rate observation (`observeHeartRate`) will not work as a "live HR during workout" feature without an Apple Watch.

### 1.2 Background Delivery Reliability

**Rating: Tricky**

The spec uses `enableBackgroundDelivery(for:frequency:)` with `.hourly` for steps/sleep and `.immediate` for workouts.

**Challenges:**
- Background delivery is NOT guaranteed when the app is terminated (force-quit by user). Apple's documentation explicitly states: "If the user has force quit the application, the system will not relaunch it for observation queries." This means if the user swipe-kills Tempo, background delivery stops entirely until the user reopens the app.
- `.immediate` frequency does not mean instant. Apple throttles background launches. In practice, `.immediate` can take 5-30 minutes on iOS 17/18, especially if Low Power Mode is active.
- `.hourly` often fires with 15-60 minute variance. It is a hint, not a guarantee.
- Battery impact: enabling background delivery for workouts (`.immediate`) causes iOS to launch your app in the background on every workout sample. If the user has an Apple Watch logging continuous workout HR, this can be dozens of launches per workout.

**Alternative:** The spec already has server-side polling as a fallback, which is good. But set user expectations: "Data updates when you open the app or within an hour" rather than promising real-time sync. For workout completion detection, combine background delivery with checking on `scenePhase` changes (app coming to foreground).

### 1.3 Writing NutriTrack Nutrition Data to HealthKit

**Rating: Straightforward**

Writing dietary data (calories, protein, carbs, fat, fiber, sugar, sodium) to HealthKit is fully supported and Apple approves this for nutrition-tracking apps. The write types in the spec are all standard `HKQuantityType` dietary types.

**One caveat:** Each nutrition write needs a proper `HKCorrelation` of type `.food` wrapping the individual quantity samples. Writing individual quantities without a correlation is technically allowed but results in a worse user experience in the Health app. The spec does not mention using `HKCorrelation`, which should be added.

### 1.4 Sleep Data from Multiple Sources

**Rating: Tricky**

The spec reads `HKCategoryType(.sleepAnalysis)` from HealthKit while simultaneously getting sleep data from Whoop's API.

**Challenges:**
- If both Whoop and Apple Watch write sleep data to HealthKit, the user sees duplicate entries in the Health app. HealthKit does NOT automatically deduplicate sleep from different sources.
- The spec wisely uses Whoop's API as the primary sleep source and HealthKit as fallback, but the `sleepAnalysis` category type changed format in iOS 16 (from `.inBed`/`.asleep` to granular stages: `.asleepREM`, `.asleepCore`, `.asleepDeep`). The spec should handle both old and new category values.
- Whoop writes `.asleepUnspecified` to HealthKit, not granular stages. Only Apple Watch writes `.asleepREM`/`.asleepCore`/`.asleepDeep`. If using HealthKit as the sleep source (no Whoop), you only get granular stages from Apple Watch.

**Alternative:** The architecture is sound -- use Whoop API as primary, HealthKit as fallback. Just ensure the fallback path handles both granular and non-granular sleep data gracefully.

### 1.5 Real-Time Heart Rate During Workout (Without Apple Watch)

**Rating: Problematic**

The spec's `observeHeartRate()` function uses `HKAnchoredObjectQuery` to observe heart rate samples.

**Problem:** Without an Apple Watch, iPhones do not passively record heart rate. The iPhone has no wrist HR sensor. Heart rate data in HealthKit comes from either:
1. Apple Watch (continuous during workouts)
2. Whoop (via Whoop app writing to HealthKit, with significant delay)
3. Third-party Bluetooth HR chest straps (requires separate pairing)

If the user has a Whoop but no Apple Watch, Whoop writes HR to HealthKit only after the workout is processed (not in real-time during the workout). The "live HR" feature in the workout view will show nothing for iPhone-only + Whoop users.

**Alternative:** Show live HR only when Apple Watch is paired. For Whoop users, show "HR will appear after Whoop syncs" during the workout, then populate retroactively from Whoop API data post-workout. The spec's Apple Watch companion app (which can read HR directly from HealthKit on-wrist) is the correct long-term solution for live HR.

---

## 2. Whoop API Limitations

### 2.1 Developer Mode 10-User Limit

**Rating: Problematic**

Whoop's developer API has a 10-user limit in development mode. To go beyond 10 users, you must apply for production access.

**Problem:** Whoop's production access approval process is opaque. Based on community reports:
- Applications require a working demo, privacy policy, and terms of service.
- Approval timelines range from 2 weeks to 3+ months. Some apps have reported never receiving a response.
- Whoop can revoke access at any time if they feel the integration competes with their own product offerings.
- There is no SLA or guaranteed approval process.

**Alternative:** Design Tempo so Whoop is a premium add-on, not a core dependency. The Apple Watch companion app spec already hints at this -- Apple Watch + HealthKit can provide recovery estimation (HRV, RHR, sleep stages) without Whoop. For MVP, launch with HealthKit-only recovery estimation and add Whoop as an enhancement. This also dramatically increases your addressable market (Apple Watch: ~100M users vs Whoop: ~1M).

### 2.2 Webhook Reliability

**Rating: Tricky**

The spec has a solid webhook processing pipeline with HMAC verification, idempotency via Redis, and a daily reconciliation cron job.

**Challenges:**
- Whoop's webhook delivery is not guaranteed. Community reports indicate 5-15% webhook failure rates during peak hours.
- Whoop does not provide a webhook delivery log or retry mechanism that you can inspect.
- The reconciliation cron runs at 3:00 AM UTC, which means up to 24 hours of stale data if a webhook is missed and the user doesn't open the app.

**Alternative:** The reconciliation cron is the right idea but should run more frequently (every 4-6 hours, not once daily). Additionally, trigger a sync on every app foreground event, not just on a schedule. The polling fallback (every 15-30 min) is already specified and is essential -- do not remove it even if webhooks seem reliable during testing.

### 2.3 No Day Strain Webhook -- Polling Required

**Rating: Straightforward**

The spec correctly identifies that cycles (strain) have no webhook and must be polled. Polling every 15 minutes during waking hours and every 60 minutes overnight is reasonable.

**One concern:** At 1,000 users, polling every 15 minutes means 96 API calls per user per day = 96,000 calls/day. Whoop's rate limits are not publicly documented for production apps. Build in adaptive polling: if the user hasn't moved (strain unchanged for 3 consecutive polls), back off to 30-minute intervals.

### 2.4 Token Refresh Race Conditions

**Rating: Straightforward**

The actor-based `WhoopTokenManager` with per-user task deduplication is the correct pattern. Swift actors provide the necessary serialization. The implementation in the spec is sound.

**One minor risk:** If the Vapor server has multiple instances (the spec shows `numReplicas = 2`), two instances could both attempt to refresh the same user's token simultaneously. The actor only protects within a single process.

**Alternative:** Use a Redis distributed lock (`SET key NX EX 30`) before refreshing a token. Check if a refresh is in progress before starting one. This is a 10-line addition and prevents cross-instance races.

### 2.5 Data Actually Available vs Assumed

**Rating: Tricky**

The spec assumes Whoop provides: recovery score, HRV (RMSSD), resting HR, SpO2, skin temperature, sleep stages (light/deep/REM), strain, workout HR zones, and body measurements.

**What is actually available in Whoop API v2:**
- Recovery: score, RHR, HRV RMSSD, SpO2, skin temp -- **all available**
- Sleep: stage durations, sleep need, performance/consistency/efficiency scores -- **all available**
- Workouts: strain, avg/max HR, zones, distance -- **all available**
- Cycles: strain, kilojoules, HR -- **all available**
- Body measurements: height, weight, max HR, body fat -- **available**
- Profile: basic user info -- **available**

**What is NOT available:**
- Real-time heart rate stream -- Whoop API does not provide live HR data. Only post-processed samples.
- Respiratory rate trend (only available in sleep records, not separately)
- Journal entries -- Whoop 4.0+ has journal data, but the API does not expose it.

The spec correctly avoids relying on data Whoop doesn't provide. No issues here beyond the live HR point addressed in Section 1.5.

---

## 3. Notification Limitations

### 3.1 Local Notification 64 Pending Limit

**Rating: Tricky**

The spec mentions the iOS 64-notification limit and says to "prioritize by time proximity." However, the notification system defines 11+ notification categories with multiple daily triggers per category. On a busy day:

- Morning briefing: 1
- Accountability escalation tiers (4 tiers, potentially 2 notifications each): 8
- Meal reminders (3 meals): 3
- Training reminder: 1
- Bedtime reminder: 1
- Streak warning: 1
- Rest timer notifications during workout: 5-10
- Focus timer session end notifications: 4-8

That is 24-32 notifications for a single day. Across 2-3 days of pre-scheduling, you could easily hit 64.

**Alternative:** The spec's strategy of recalculating on every state change is correct, but implement a priority queue:
1. Always schedule today's notifications first (all of them).
2. Schedule tomorrow's morning briefing and first accountability tier.
3. Fill remaining slots with tomorrow's remaining notifications.
4. Never pre-schedule more than 48 hours out for local notifications.
5. Rest timer notifications should be scheduled one-at-a-time (not all rest timers for all exercises upfront).

### 3.2 Critical Alerts Entitlement

**Rating: Problematic**

The spec plans to use Critical Alerts for the "Final Warning" accountability notification that bypasses Do Not Disturb.

**Problem:** Apple's Critical Alerts entitlement (`com.apple.developer.usernotifications.critical-alerts`) is reserved for:
- Health & safety apps (medical devices, emergency alerts)
- Home security apps
- Public safety apps

Apple explicitly states in their documentation: "Critical alerts are intended for apps whose primary purpose is health, medical, or safety related." A productivity/accountability app will almost certainly be rejected for this entitlement. The justification in the spec ("helps student-athletes maintain daily health accountability") is a stretch -- it is not the same as alerting a diabetic about glucose levels.

**Alternative:** Use `.timeSensitive` interruption level instead. Time Sensitive notifications:
- Break through Scheduled Summary
- Appear immediately on the lock screen
- Stay visible for 1 hour
- Work without any special entitlement

This achieves 90% of the goal. For users who want the full "drill sergeant" experience, instruct them to enable "Always Deliver" for Tempo in Settings > Notifications, which bypasses Focus modes entirely (user-controlled, no entitlement needed).

### 3.3 Time Sensitive Notification Approval

**Rating: Straightforward**

Using `UNNotificationContent.interruptionLevel = .timeSensitive` for morning briefings, firm accountability reminders, and bedtime reminders is appropriate and does not require a special entitlement. Apple approves this for time-relevant content in productivity and health apps.

**One caveat:** If a user has Time Sensitive notifications disabled in Settings > Tempo > Notifications, your `.timeSensitive` notifications are downgraded to `.active`. Handle this gracefully.

### 3.4 Dynamic Island for Focus Timer

**Rating: Straightforward**

Live Activities with Dynamic Island support are well-documented since iOS 16.1. The spec's approach is correct:
- Use `ActivityKit` to start/update/end the activity
- Use `Text(timerInterval:)` for system-rendered countdown (zero battery cost for seconds ticking)
- Update only on state changes (pause/resume/complete), not every second

**Constraints to note:**
- Maximum 4 hours for a Live Activity before the system ends it. The spec mentions this for workouts but should also handle it for the "accountability countdown" Live Activity that starts at 5 PM. If the user's tasks span 5 PM to midnight, that is 7 hours -- exceeding the limit.
- Only iPhone 14 Pro and later have Dynamic Island. Older iPhones show the Live Activity only on the lock screen.
- Maximum 1 active Live Activity per app at a time (as of iOS 17). If a focus timer and workout are running simultaneously, only one can be shown. iOS 18 relaxed this to multiple, but iOS 17 users will be affected.

**Alternative for the 4-hour limit:** End the accountability Live Activity after 4 hours with a final update showing current status. If tasks are still incomplete, fire a regular notification.

### 3.5 Live Activity Update Frequency and Battery

**Rating: Straightforward**

The spec correctly limits updates to once per minute for the focus timer and only on state changes for workouts. `Text(timerInterval:)` handles the visual countdown without any app involvement. Battery impact is minimal.

**Hard limit:** ActivityKit allows approximately 10-15 updates per hour. Beyond that, the system throttles and may delay updates. The spec's cadence is well within this budget.

### 3.6 Background Notification Scheduling

**Rating: Tricky**

The spec reschedules all local notifications at midnight via `BGAppRefreshTaskRequest`.

**Challenge:** `BGAppRefreshTaskRequest` is NOT guaranteed to fire at midnight. The system schedules it at its discretion, influenced by battery level, charging state, and usage patterns. A midnight refresh could fire anywhere from midnight to 6 AM.

**Alternative:** Schedule the next day's critical notifications (morning briefing, first accountability tier) at the END of the current day's usage session (when the user last closes the app in the evening). Use the BGTask as a safety net, not the primary mechanism. Additionally, the push-based morning briefing (sent by the backend) eliminates the need for a local midnight reschedule for that specific notification.

---

## 4. SwiftData Concerns

### 4.1 SwiftData Maturity (iOS 17)

**Rating: Tricky**

SwiftData shipped with iOS 17.0 in September 2023 and had significant bugs:
- iOS 17.0-17.1: Crashes on complex relationship graphs, especially with `@Relationship(.cascade)` delete rules.
- iOS 17.0-17.2: `@Query` macro performance issues with predicates containing optionals.
- iOS 17.0-17.3: Background context saves occasionally silently failing.
- iOS 17.4+: Most critical bugs fixed.
- iOS 18.0+: Substantially improved, added `#Expression` macro, better migration support.

The spec targets iOS 17.0+, which includes the buggiest SwiftData versions.

**Alternative:** Raise minimum to iOS 17.4 (still covers >90% of iPhones in 2026). This eliminates the worst SwiftData bugs while keeping a broad user base. Alternatively, use Core Data with the SwiftData-like wrapper pattern -- more verbose but battle-tested. Given the app's complexity (27 model types, relationships, background contexts), Core Data is the safer bet for v1.

### 4.2 Performance with 1 Year of Data

**Rating: Tricky**

The spec has 27 `@Model` types. A year of data means:
- 365 `DailySnapshot` records
- ~200 `WorkoutPlan` records
- ~3,000 `PlannedSet` records
- 365 `DailyAccountability` records
- ~1,000 `StudySession` records
- 365 `DailyRecovery` records
- ~5,000 `XPEvent` records

That is roughly 10,000-15,000 records total. SwiftData/Core Data can handle this easily in terms of raw storage, but:
- Fetching 365 `DailySnapshot` records with all their relationships (each has nested objects) for a year chart could be slow without careful fetch optimization.
- The spec's `< 200ms` budget for a 90-day snapshot fetch is achievable only with proper indexes and batch fetching.
- The `@Transient` computed properties on models will be recalculated every time the object is accessed, which is fine for display but expensive in loops.

**Mitigation:** The spec already defines indexes on `date` fields, which is correct. Add `.fetchBatchSize` to all `@Query` macros and use `FetchDescriptor` with `.propertiesToFetch` to avoid loading entire object graphs when only specific fields are needed.

### 4.3 Migration Reliability

**Rating: Tricky**

The spec uses `VersionedSchema` with a lightweight migration from V1 to V2. SwiftData's lightweight migration is a wrapper around Core Data's lightweight migration, which supports:
- Adding new models
- Adding new optional properties with defaults
- Renaming properties (with mapping)
- Adding/removing indexes

It does NOT support:
- Changing property types (e.g., `String` to `Int`)
- Removing non-optional properties without defaults
- Complex relationship changes
- Data transformations

**Challenge:** With 27 models, the likelihood of needing a non-lightweight migration within the first year is high. SwiftData's custom migration (`MigrationStage.custom`) is poorly documented and has known issues in iOS 17.

**Alternative:** Plan for migration failures. Implement a "nuclear option" migration handler that:
1. Attempts the lightweight migration.
2. On failure, backs up the SQLite file.
3. Creates a fresh store.
4. Re-syncs all data from the backend.

This requires the backend to be the authoritative data source, which the spec's sync architecture already supports.

### 4.4 CloudKit Sync with SwiftData

**Rating: Not Applicable (Correct Decision)**

The spec explicitly disables CloudKit (`cloudKitDatabase: .none`) and uses a custom Vapor backend for sync. This is the right call. SwiftData + CloudKit has severe limitations:
- No server-side logic (can't run AI, can't process webhooks)
- Conflict resolution is basic (last-write-wins)
- No support for social features (leaderboards, challenges)
- No control over sync timing

### 4.5 Concurrent Access with @ModelActor

**Rating: Tricky**

The spec mentions thread safety and `@ModelActor` for background work. `@ModelActor` was introduced in iOS 17 and creates a `ModelContext` bound to a specific actor.

**Challenge:** `@ModelActor` works correctly for isolated background work, but passing `PersistentModel` objects between the main context and a `@ModelActor` context is a common source of crashes. You must pass `PersistentIdentifier` values (not model objects) across context boundaries.

**Mitigation:** The spec's architecture of using in-memory view models (like `WorkoutLogViewModel`) with debounced persistence is the correct pattern. Just ensure all SwiftData writes go through a single `@ModelActor` service, and the main thread only reads via `@Query`.

---

## 5. Vapor Backend Concerns

### 5.1 Ecosystem Size

**Rating: Tricky**

Vapor has a smaller package ecosystem than Express.js or FastAPI. As of 2026:
- PostgreSQL driver (Fluent): Mature, production-ready
- Redis: Mature (`redis` package)
- JWT: Mature (`jwt-kit`)
- APNs: `apnswift` exists and is maintained by the Vapor team -- mature
- WebSocket: Built into Vapor -- production-ready
- Background jobs: `queues` package with Redis driver -- works but less feature-rich than Celery or BullMQ
- Email sending: Limited options. `mailgun` driver exists but raw SMTP is DIY.
- S3: `soto` (AWS SDK for Swift) works but is heavier than `aws-sdk` in Node.

**Missing vs Express/FastAPI:**
- No equivalent of Prisma's introspection or migration generation
- No Bull-style job dashboard (you'll need to build monitoring yourself)
- Smaller Stack Overflow / community knowledge base
- Fewer deployment guides and troubleshooting resources

**Why Vapor is still correct for Tempo:** Having the backend in Swift means shared models, shared business logic, and a single language across the entire stack. For a solo developer, this eliminates context-switching cost. The ecosystem gaps are manageable.

### 5.2 Deployment Options and Costs

**Rating: Straightforward**

The spec targets Railway or Fly.io, both of which support Docker deployments.

| Platform | Vapor Support | Cost (2 instances + DB + Redis) | Pros | Cons |
|----------|--------------|------|------|------|
| Railway | Docker: Yes | ~$20-40/mo | Simple, good DX | Less control, auto-scaling limited |
| Fly.io | Docker: Yes | ~$20-50/mo | Global regions, built-in Postgres | More complex config |
| Render | Docker: Yes | ~$25-45/mo | Managed Postgres | Cold starts on free tier |
| AWS ECS | Docker: Yes | ~$30-60/mo | Full control | Complex setup |

For an MVP with <1,000 users, Railway at ~$25/month is the pragmatic choice.

### 5.3 WebSocket Support

**Rating: Straightforward**

Vapor has first-class WebSocket support built into its HTTP server (based on SwiftNIO). It handles upgrade, ping/pong, and binary/text frames. The spec's use case (real-time leaderboard and challenge updates) is well within Vapor's capabilities.

**At scale concern:** A single Vapor instance can handle ~10,000 concurrent WebSocket connections (depends on memory -- each connection uses ~50KB). For 10K users, not all will be connected simultaneously. Expect ~500-1,000 concurrent connections at peak, which is fine for 1-2 instances.

### 5.4 APNs Integration

**Rating: Straightforward**

`apnswift` (maintained by the Vapor/SwiftNIO team) is production-ready and used by major apps. It supports:
- Token-based authentication (P8 key)
- HTTP/2 multiplexing
- Silent push, alert push, background push
- Payload customization

The spec's APNs usage is standard.

### 5.5 Database Migration Tooling (Fluent)

**Rating: Tricky**

Fluent (Vapor's ORM) has migration support, but it is more manual than Alembic or Prisma:
- Migrations are written in Swift (no auto-generation from schema changes)
- No `diff` command to compare current DB state with model definitions
- No rollback verification at development time
- Migration ordering is based on array position, not timestamps

**Mitigation:** This is manageable for a solo project. Write each migration as a separate file, test it against a staging database before deploying, and always keep a backup before migrating production.

---

## 6. Feature-Specific Risks

### 6.1 Plate Calculator

**Rating: Straightforward**

Simple arithmetic: `(target_weight - bar_weight) / 2`, then greedy algorithm to fill with available plates. The spec defines a fixed plate set (25, 20, 15, 10, 5, 2.5, 1.25 kg).

**Edge cases to handle (all minor):**
- Target weight less than bar weight (20kg bar, user enters 15kg) -- show "Weight is less than the bar"
- Target weight not achievable with available plates (e.g., 21.5kg per side) -- show nearest achievable weight
- Non-standard bars (e.g., EZ curl bar at 10kg, trap bar at 25kg) -- allow configurable bar weight
- Imperial unit users need a separate plate set (45, 35, 25, 10, 5, 2.5 lbs)

### 6.2 Focus Score via Screen Time API

**Rating: Problematic**

The spec mentions `DeviceActivityMonitor` (Screen Time API / Family Controls framework) as a Phase 2 enhancement for automatic distraction detection.

**Problem:** The `DeviceActivityMonitor` and `ManagedSettings` APIs are part of the Family Controls framework, which has severe restrictions:
- Requires Family Controls capability, which Apple gates behind a review process
- Designed for parental controls and enterprise MDM, NOT general productivity apps
- Apple has explicitly rejected apps that use Family Controls for non-parental-control purposes
- The API cannot tell you WHICH app the user switched to (only that screen time limits were exceeded)
- It requires the device to be in Managed mode (MDM) or use Family Sharing

**Alternative:** The spec's current approach (manual distraction tap button) is actually the right design. If you want automatic detection, use a simpler heuristic: detect when the app goes to background during a focus session (`scenePhase` change to `.inactive`/`.background`) and auto-count that as a potential distraction. This requires zero special APIs and is 100% App Store safe.

### 6.3 Anti-Cheat Gyroscope/Accelerometer Monitoring

**Rating: Tricky**

The spec uses gyroscope + touch event monitoring to detect if the phone is being used during study sessions, and accelerometer data to detect if the phone is in a car during "study" time.

**Challenges:**
- **Battery drain:** Continuous accelerometer/gyroscope monitoring uses 2-5% battery per hour. During a 2-hour study session, that is 4-10% additional drain just for anti-cheat.
- **False positives:** Phone face-down on a table with book open is the most common legitimate study setup. The phone will have zero touch events and zero gyroscope movement. The anti-cheat would flag this as "no interaction for 30+ min" -- penalizing the behavior you WANT.
- **Background limitations:** When the app is backgrounded, you cannot continuously read CoreMotion data. You only get updates via `CMMotionActivityManager` (which gives walk/run/drive classification, not raw accelerometer) or by starting a background location session (which drains battery and requires location permission).

**Alternative:**
- Drop gyroscope monitoring entirely. The battery and false positive costs outweigh the benefit.
- Use `CMMotionActivityManager.startActivityUpdates()` to detect automotive vs walking vs stationary. This is battery-efficient (uses the motion coprocessor, not the main CPU) and can flag "user was driving during study" without continuous sensor access.
- For "phone not used" detection, track screen-off time via `scenePhase`. If the app has been in background for 30+ minutes during a "running" study session, flag it. This is zero-cost and accurate.
- Accept that some users will game the system. The XP caps (6 sessions/day, 1500 XP/day hard cap) already limit the damage.

### 6.4 Ambient Sounds During Focus Timer

**Rating: Tricky**

The spec uses `AVAudioSession` with `.ambient` category to play rain, white noise, etc. during study sessions.

**Challenges:**
- **Phone calls:** When a phone call comes in, iOS interrupts the audio session. After the call, the ambient sound does not automatically resume. You must observe `AVAudioSession.interruptionNotification` and re-start playback. The spec mentions ducking for notification sounds but not full interruption handling.
- **Other app audio:** `.ambient` category mixes with other audio, which is correct. But if the user is playing Spotify, the ambient sound volume needs to be independently controllable -- the spec has this (independent volume slider at 30%).
- **Audio files size:** 6 ambient sound files (60-90 second loops in CAF format) at decent quality will be 3-6 MB total. This is fine for app size but should use AAC compression within CAF containers.
- **Background audio:** When the app is backgrounded during a focus session, ambient audio will stop unless you enable the `audio` background mode in Info.plist. BUT: if you enable `audio` background mode, Apple will scrutinize whether your app actually needs it. A focus timer that plays ambient sounds is a legitimate use case, so this should be approved.

**Mitigation:** Add `audio` background mode, implement proper interruption handling, and ensure the audio session is deactivated when the timer ends (otherwise it blocks other apps from using audio).

### 6.5 Calendar Event Categorization

**Rating: Tricky**

The spec uses keyword matching on calendar event titles to detect exams: "exam", "test", "final", "midterm", "quiz", "assessment".

**Challenges:**
- **Italian keywords:** The user (Nicola) speaks Italian. Italian exam-related keywords include "esame", "compito", "verifica", "prova", "interrogazione." The spec only lists English keywords.
- **False positives:** "Eye test appointment", "COVID test", "Test drive at BMW" would all be flagged as exams.
- **Calendar structure:** Some universities use structured calendar feeds (ICS) where the event title is just a course code ("CS 301") and the event type is in the description or location field.

**Alternative:** Use a two-step approach:
1. Keyword match on title (both English and Italian keywords).
2. Show the user a confirmation prompt: "Found 'Calculus II Exam' on March 28. Add as exam?" (the spec already does this).
3. Learn from confirmations and rejections -- if the user ignores "Eye test appointment" twice, stop suggesting events with "eye" in the title.

### 6.6 AI Cost at Scale

**Rating: Tricky**

The spec estimates $0.83/user/month for AI features using Claude Haiku and Sonnet.

| Users | Monthly AI Cost | Monthly Revenue (estimated) |
|-------|----------------|----------------------------|
| 100 | $83 | $40-200 (low conversion) |
| 500 | $415 | $200-1,000 |
| 1,000 | $830 | $400-2,000 |
| 10,000 | $8,300 | $4,000-20,000 |

**Concern:** At $0.83/user/month, AI costs are $10/user/year -- which is significant for a $39.99/year subscription. That is 25% of revenue going to AI costs alone, before hosting, Apple's 30% cut, and other costs.

**Alternative:**
- Use Haiku exclusively for v1. Replace all Sonnet calls with Haiku. This cuts costs by ~60% to ~$0.33/user/month.
- Cache common patterns. If 50 users have similar recovery profiles, generate one insight template and personalize with string interpolation rather than a full LLM call per user.
- Make AI insights a Pro-only feature. Free users get rule-based insights ("Your HRV is 15% below your 7-day average"), Pro users get LLM-generated insights.
- Implement the budget enforcement system (already in the spec) and set aggressive per-user daily caps.

### 6.7 Offline Queue Replay and Conflict Resolution

**Rating: Tricky**

The spec's offline queue replays operations in order when connectivity returns. But conflict resolution for multi-day offline scenarios is underspecified.

**Scenarios:**
- User logs sets offline for 3 days. Reconnects. Server already has Whoop-detected workouts for those days. Which workout data wins?
- User completes non-negotiables offline. Server's daily reset cron already created new `DailyAccountability` entries. Replaying old completions targets the wrong day's record.
- XP events from 3 days ago are replayed. Leaderboard positions have already been calculated without them.

**Alternative:** The offline queue must include timestamps and use `client_id` fields for idempotency (the spec already has `client_id` for workouts). For non-negotiables, the replay must include the `date` field to ensure completions apply to the correct day. For XP, use idempotent UUID-based submission (already in the spec). For workout deduplication with Whoop, use the time-overlap detection (also already in the spec). The architecture is sound in principle but needs explicit conflict resolution rules documented for each queued operation type.

### 6.8 Apple Watch Workout Logging

**Rating: Tricky**

The spec uses `WCSession.sendMessage` for real-time Watch-to-iPhone communication during workouts.

**Challenges:**
- `sendMessage` only works when the iPhone is reachable (within Bluetooth range and the iPhone app is at least suspended). If the user leaves their phone in a locker, the Watch cannot communicate.
- `transferUserInfo` is queued and delivered when possible, but not real-time. Logging a set on the Watch might not appear on the iPhone for minutes.
- WatchConnectivity message size is limited to ~262KB per transfer. Workout data is small, so this is not an issue.

**The spec handles this correctly:** iPhone is the source of truth, Watch holds only the latest snapshot, and if the Watch is unreachable, actions are queued locally. The key risk is user confusion: "I logged a set on my Watch but it didn't show on my phone immediately." Clear UI messaging is needed.

---

## 7. App Store Review Risks

### 7.1 HealthKit Usage Justification

**Rating: Tricky**

The spec requests 17 read types and 8 write types. Apple will scrutinize each one.

**Likely approved:**
- Steps, active energy, distance (fitness app -- obvious)
- Heart rate, resting HR, HRV (recovery tracking -- justified)
- Sleep analysis (recovery module -- justified)
- Workouts (training module -- obvious)
- Body mass, height (training calculations -- justified)
- Dietary data write (NutriTrack integration -- justified)

**Potentially questioned:**
- `basalEnergyBurned` -- Apple may ask why a fitness app needs basal (resting) metabolic rate data
- `dietaryFiber`, `dietarySugar`, `dietarySodium` -- very granular nutrition writes. Apple may ask if users actually input this level of detail

**Alternative:** Request only the types you actively use in v1. If you're not displaying basal energy on any screen, don't request it. You can always request additional permissions later (HealthKit allows incremental authorization). Requesting fewer permissions also improves the user experience (shorter permission sheet).

### 7.2 Push Notification Frequency

**Rating: Tricky**

A fully-configured user with Drill Sergeant mode could receive 8-12 notifications per day: morning briefing, 4 accountability tiers, meal reminders, training reminder, bedtime reminder, and streak warnings.

**Concern:** Apple does not have a specific notification frequency limit, but they do reject apps that are "spammy" in notification behavior. 8-12 notifications is aggressive but defensible if:
- The user explicitly configures their notification intensity (the spec has 4 intensity levels)
- Each notification is contextually relevant and actionable
- The user can easily reduce frequency in settings

**Mitigation:** Default to "Gentle Coach" intensity (fewest notifications) during onboarding. Let users opt UP to Drill Sergeant, not down from it.

### 7.3 Gamification + Health Data

**Rating: Straightforward**

Using health data (workouts, study sessions) to award XP and display on leaderboards does not violate Apple's guidelines, provided:
- Health data is not shared with other users in identifiable form (the spec shares only XP scores, not raw health data)
- The app does not make medical claims
- Gamification does not encourage unhealthy behavior (e.g., "earn XP for skipping meals" would be rejected)

The spec is clean on all these points.

### 7.4 Subscription with Backend Dependency

**Rating: Straightforward**

Apple requires that subscription features remain available. If the server goes down, the app must still function in a degraded mode.

The spec's offline-first architecture (SwiftData local storage, offline queue, cached data) satisfies this requirement. The app works without network, with the backend providing sync, social features, and AI insights as enhancements.

### 7.5 Sign in with Apple Edge Cases

**Rating: Straightforward**

The spec uses Sign in with Apple with JWT on the backend. Known edge cases:
- **Anonymous ID relay:** Apple provides a stable user identifier that persists across sign-ins on the same device. If the user signs in on a new device, the identifier is the same (tied to Apple ID). No issues.
- **Email privacy relay:** If the user chooses "Hide My Email," you receive a relay address (e.g., `abc123@privaterelay.appleid.com`). The spec should not send marketing emails to this address.
- **Token revocation:** If the user revokes Sign in with Apple for your app (in Settings), you must handle the revocation notification (`server-to-server` notification from Apple). The spec should implement the Apple credential revocation endpoint.

### 7.6 Third-Party API Dependency (Whoop)

**Rating: Straightforward**

Apple does not reject apps for depending on third-party APIs. However, the app must be functional without the third-party service. The spec's architecture (Whoop is optional, HealthKit works standalone) satisfies this.

---

## 8. Performance Feasibility

### 8.1 Dashboard Loading 4 Data Sources in <300ms

**Rating: Tricky**

The dashboard loads: DailySnapshot (SwiftData), HealthKit data (steps, energy), Whoop data (cached), and NutriTrack data (cached).

**Analysis:**
- SwiftData fetch for today's `DailySnapshot`: 10-50ms (realistic with index)
- HealthKit `HKStatisticsQuery` for steps: 50-100ms
- HealthKit `HKStatisticsQuery` for active energy: 50-100ms
- Cached Whoop/NutriTrack data (from SwiftData): 10-30ms

Total sequential: 120-280ms. Within budget if run in parallel.

**Risk:** HealthKit queries are async but can stall if HealthKit's background daemon is busy (e.g., processing a large workout import from Apple Watch). In rare cases, a single HealthKit query can take 500ms+.

**Alternative:** The spec already specifies showing skeleton UI within 800ms and hydrating data in the background. This is the correct approach. Show cached data first, then refresh from live sources. Never block the UI on a HealthKit query.

### 8.2 Chart Rendering with 365 Data Points

**Rating: Straightforward**

Using Swift Charts (the spec avoids third-party chart libraries) with 365 data points and Canvas for dense charts.

**Performance:**
- Swift Charts handles 365 points in a line chart easily (<100ms render)
- The spec's decimation strategy (365 -> ~100 points for year view) is correct
- `Canvas` rendering for custom heatmaps (365 cells) at 60fps is achievable

No concerns here. Swift Charts is GPU-accelerated and designed for this scale.

### 8.3 SwiftData Queries for 90-Day Correlations

**Rating: Tricky**

The spec mentions trend analysis and pattern detection that requires querying 90 days of data across multiple model types (DailySnapshot, DailyRecovery, StudySession, etc.).

**Challenge:** SwiftData does not support SQL joins. Fetching 90 days of DailySnapshot + 90 days of DailyRecovery + 90 days of StudySession requires 3 separate fetches. Correlating them in memory is fast (these are small objects), but the fetches themselves can be 50-200ms each.

**Alternative:** For the AI pattern detection (which runs weekly), perform the fetches in a background `@ModelActor` context and cache the aggregated results. For real-time chart correlations, pre-compute aggregate scores in `DailySnapshot` (which the spec already does with `bodyScore`, `fuelScore`, `mindScore`, `moveScore`).

### 8.4 Background Sync Every 15 Minutes -- Battery Impact

**Rating: Tricky**

The spec uses HealthKit background delivery (hourly for steps, immediate for workouts) and backend polling for Whoop strain (every 15 minutes).

**Clarification:** The 15-minute Whoop polling happens on the backend, not the iOS app. The iOS app is only woken by:
- HealthKit background delivery (hourly + on workout end)
- Silent push notifications from the backend (when Whoop data updates)
- `BGAppRefreshTaskRequest` (system-scheduled, typically 1-4 times per day)

This is acceptable for battery. The `< 3% per hour` background budget in the spec is achievable as long as:
- The app does not use continuous location
- The app does not use continuous CoreMotion (see anti-cheat discussion)
- Background audio is only active during focus timer sessions

---

## 9. Scalability Concerns

### 9.1 PostgreSQL Materialized View for Leaderboards

**Rating: Straightforward**

The spec refreshes leaderboard materialized views every 5 minutes with a Redis cache of 300s TTL.

At 10K users:
- `REFRESH MATERIALIZED VIEW CONCURRENTLY` on a leaderboard view with 10K rows and a few JOINs: <500ms
- Redis cache means the DB is only hit once per 5 minutes
- This is well within PostgreSQL's capabilities even on a small instance

No concerns.

### 9.2 WebSocket Connections at Scale

**Rating: Tricky**

At 10K users with ~10% concurrent connection rate = ~1,000 WebSocket connections.

- Each WebSocket connection: ~50KB memory overhead
- 1,000 connections: ~50MB memory
- Vapor on a 1GB instance can handle this

**Challenge:** If you scale to 2+ Vapor instances (load-balanced), WebSocket connections are pinned to a specific instance. A leaderboard update must be broadcast to all connected clients, but some are on Instance A and some on Instance B.

**Alternative:** Use Redis Pub/Sub to broadcast events across instances. When Instance A receives an XP event, it publishes to a Redis channel. Instance B subscribes and broadcasts to its connected clients. This is a standard pattern and well-supported by Vapor's Redis integration.

### 9.3 Claude API Rate Limits at 10K Users

**Rating: Tricky**

At 10K users with ~$8,300/month in API costs, you would be making approximately:
- Morning briefings: 10K * 30 = 300K calls/month = ~10K/day = ~7/minute
- Weekly reports: 10K * 4 = 40K calls/month
- Total: ~350K+ calls/month, peaking at ~10-20 requests/minute

Anthropic's rate limits for the API tier:
- Haiku: 4,000 requests/minute (no issue)
- Sonnet: 4,000 requests/minute (no issue)
- Token throughput limits may apply at high concurrency

**Mitigation:** Stagger morning briefings over a 2-hour window (7-9 AM) rather than firing all 10K at 7:00 AM. The spec's budget enforcement system handles cost, and the rate limits are not a concern at this scale.

### 9.4 APNs at Scale

**Rating: Straightforward**

Apple's APNs infrastructure handles millions of push notifications. At 10K users with 5-10 pushes/day, that is 50K-100K pushes/day -- trivial for APNs.

The `apnswift` library handles connection pooling and HTTP/2 multiplexing. Token management (refreshing P8-based tokens every 55 minutes) is handled automatically by the library.

---

## 10. Proposed Alternatives Summary

| Issue | Spec Approach | Alternative |
|-------|--------------|-------------|
| Critical Alerts entitlement | Apply to Apple | Use `.timeSensitive` + instruct users to enable "Always Deliver" |
| Live HR without Apple Watch | HealthKit observation | Show "HR available after sync" for Whoop-only users |
| Screen Time API focus detection | `DeviceActivityMonitor` | Detect `scenePhase` changes (app backgrounded = distraction) |
| Anti-cheat gyroscope monitoring | Continuous sensor access | Use `CMMotionActivityManager` (battery-efficient) for drive detection only |
| SwiftData on iOS 17.0 | Target iOS 17.0+ | Target iOS 17.4+ minimum |
| Whoop as core dependency | Required for recovery | Make Whoop optional; Apple Watch + HealthKit as primary |
| AI cost at scale ($0.83/user) | Haiku + Sonnet mix | Haiku-only for v1; cache common patterns; AI is Pro-only |
| 64 local notification limit | Priority by time | Today-first scheduling; never pre-schedule >48h |
| Live Activity 4-hour limit | Accountability countdown 5PM-midnight | End after 4h, fire regular notification for remainder |
| Cross-instance token refresh race | Actor-based (single process) | Add Redis distributed lock |
| Webhook reconciliation | Daily at 3 AM | Every 4-6 hours |
| Calendar keyword matching | English only | Add Italian keywords + learning from user confirmations |

---

## 11. MVP vs V2 Recommendation

### MVP (Phases 1-4): Ship These

| Feature | Feasibility | Notes |
|---------|-------------|-------|
| SwiftUI + SwiftData foundation | Straightforward | Target iOS 17.4+ |
| HealthKit read (steps, energy, workouts, sleep) | Straightforward | Core biometric bus |
| HealthKit write (nutrition, workouts) | Straightforward | Standard APIs |
| Sign in with Apple + JWT auth | Straightforward | |
| Dashboard with 4 quadrants | Straightforward | Cached-first, background refresh |
| Whoop OAuth2 + backend proxy | Tricky | Apply for production access NOW; have HealthKit fallback ready |
| Recovery module (Whoop-powered) | Straightforward | With HealthKit-only fallback |
| Training module (workout logging) | Straightforward | Core feature |
| Plate calculator | Straightforward | |
| Accountability (non-negotiables) | Straightforward | Core feature |
| Focus timer with Pomodoro | Straightforward | |
| Ambient sounds (4-5 sounds for v1) | Tricky | Implement audio interruption handling |
| Live Activity for timers | Straightforward | Use `Text(timerInterval:)` |
| Local notifications (gentle + firm tiers) | Straightforward | Stay under 64 limit |
| Push notifications (morning briefing, recovery) | Straightforward | |
| Offline queue with replay | Tricky | Needs explicit conflict rules |
| NutriTrack integration via backend proxy | Straightforward | |
| EventKit calendar integration | Straightforward | English + Italian keywords |
| Weekly AI insights (Haiku only) | Straightforward | Budget-capped |
| Vapor backend (auth, sync, Whoop proxy, push) | Straightforward | Railway deployment |

### Defer to V2: Too Risky or Too Complex for MVP

| Feature | Risk | Reason to Defer |
|---------|------|-----------------|
| **Arena (XP, leaderboards, challenges)** | Complexity | Social features require server infrastructure, anti-cheat, moderation. Ship single-player first. |
| **Anti-cheat system** | Battery + false positives | Gyroscope monitoring is impractical. Defer until Arena launches and cheating is actually observed. |
| **Screen Time API focus detection** | App Store rejection | Apple will reject Family Controls usage. Use scenePhase detection instead. |
| **Critical Alerts** | Entitlement rejection | Will not be approved for a productivity app. Use `.timeSensitive` in v1. |
| **Apple Watch companion app** | Development time | Separate watchOS target, WatchConnectivity, complications. Massive scope. Ship iPhone-first. |
| **WebSocket real-time updates** | Premature | Only needed for Arena. Use polling + push notifications for v1. |
| **108 achievements** | Content volume | Ship with 20-30 core achievements. Add more post-launch as users hit them. |
| **Exam Mode (auto-detect from calendar)** | Edge cases | Manual exam entry works fine. Auto-detection adds complexity for marginal benefit. |
| **Import/Export system** | Niche | Users don't have existing data to import at launch. Build this when users ask for it. |
| **Accountability Live Activity (5PM countdown)** | 4-hour limit | Workout and focus timer Live Activities are sufficient for v1. |
| **AI morning briefing (daily)** | Cost | Start with weekly AI insights. Daily briefings at scale burn budget fast. Make daily an upgrade from weekly in a later version. |
| **Friend challenges** | Requires Arena | Cannot ship without the social infrastructure. |
| **Workout generation algorithm** | Algorithm complexity | Ship with manual workout plans first. Add AI-generated plans in v2 when you have user training data. |
| **Multiple ambient sound files (8)** | App size | Ship with 4 (Rain, White Noise, Brown Noise, Fireplace). Add more later. |

---

## 12. Unknown Unknowns -- Prototyping Required

These cannot be answered from documentation alone. Each requires building a proof-of-concept and testing on real hardware.

### Must Test Before Committing

1. **HealthKit background delivery reliability on iOS 17.4/18.** Build a minimal app that subscribes to workout completion background delivery. Run it for 1 week on a daily-driver phone. Measure: how often does the background delivery fire within 5 minutes? Within 30 minutes? Does it fire at all when the app is force-quit?

2. **SwiftData performance with 27 model types and 10K+ records.** Create a synthetic dataset with 1 year of data. Measure: DailySnapshot fetch with relationships (<50ms budget), 90-day history fetch (<200ms budget), set completion write latency (<10ms budget). Test on the oldest supported device (iPhone XS).

3. **SwiftData migration from V1 to V2 with a non-trivial schema change.** Add a new required field to DailySnapshot in V2. Run the lightweight migration on a 1-year dataset. Measure: success rate, migration duration, data integrity.

4. **Whoop API production access approval timeline.** Submit the application NOW with a working demo, privacy policy, and terms. Track how long approval takes. Have the HealthKit-only fallback ready as a hedge.

5. **Vapor cold start time on Railway.** Swift binaries are large (~50-100MB). Measure: cold start from container spin-up to first HTTP response. If >5 seconds, pre-warm instances.

6. **Live Activity + Focus Timer background behavior.** Start a 25-minute focus timer, lock the phone, and leave it for 25 minutes. Verify: does the timer notification fire on time? Does the Live Activity update correctly? Does the ambient sound continue playing? Test with Do Not Disturb enabled.

7. **64 local notification limit under real-world conditions.** Simulate a full day: morning briefing triggers, 4 accountability tiers, 3 meal reminders, training reminder, bedtime reminder, and a 4-session Pomodoro. Count total scheduled notifications. Verify they all fire. Verify that rescheduling (after a task completion) correctly clears old and schedules new notifications without exceeding 64.

8. **Audio session behavior with ambient sounds + phone call + notification.** Play ambient rain sound, receive a phone call, end the call. Does the ambient sound resume automatically? Play ambient sound, receive a notification with custom sound. Does ducking work correctly? Play ambient sound, Siri activation. What happens?

9. **WatchConnectivity latency for set logging.** On a real Apple Watch + iPhone pair: tap "Complete Set" on the Watch. Measure time until the iPhone's UI updates. Test with phone in pocket (Bluetooth) and phone across the room (Wi-Fi relay). Target: <1 second.

10. **Concurrent SwiftData access pattern.** Run the debounced workout save (500ms delay, background `@ModelActor`) while the main thread reads via `@Query`. Verify no crashes, no stale data, no merge conflicts. Test for 100 consecutive set completions.

11. **APNs silent push wake-up reliability.** Send a silent push to the app. Measure: does the app wake up and process the payload? Test with app in background, app suspended, and app terminated. iOS throttles silent pushes aggressively -- test how many can be delivered per hour.

12. **Real-world battery impact of the full feature set.** Run the app for a full day with all features active: HealthKit background delivery, ambient sound during 2h of study sessions, Live Activity for focus timer, 8 push notifications. Measure total battery consumed. Target: <15% for passive use, <25% for active use.

---

## Final Verdict

The Tempo spec is **ambitious but architecturally sound**. The biggest risks are:

1. **SwiftData on iOS 17.0** -- raise minimum to 17.4 or consider Core Data.
2. **Critical Alerts entitlement** -- will be rejected. Use `.timeSensitive`.
3. **Screen Time API** -- will be rejected. Use `scenePhase` detection.
4. **Whoop production access** -- approval is not guaranteed. Ship with HealthKit fallback.
5. **Anti-cheat gyroscope monitoring** -- impractical. Use simpler heuristics.
6. **Arena social features in MVP** -- too much scope. Defer to V2.
7. **AI costs at scale** -- switch to Haiku-only and make it Pro-exclusive.

The core loop -- dashboard, training, accountability, recovery -- is technically feasible with straightforward-to-tricky ratings across the board. Ship that first. Everything else is a V2 feature that should be earned by having real users who ask for it.

---

## Remediation Status

> **Date:** 2026-03-24
> **All critical and important issues from this audit have been remediated in the module docs.**

| # | Issue | Rating | Remediation | Files Modified | Status |
|---|-------|--------|-------------|----------------|--------|
| 1 | **Critical Alerts entitlement** (Section 3.2) | Problematic | Replaced ALL references to Critical Alerts with Time Sensitive (`.timeSensitive`) notifications. Added "Always Deliver" user instruction for Drill Sergeant/Savage modes. Removed Critical Alert entitlement, justification text, and fallback logic. | `MODULE_ACCOUNTABILITY.md`, `ONBOARDING_AND_NOTIFICATIONS.md`, `SOUND_AND_HAPTICS.md`, `STATE_MACHINES.md` | REMEDIATED |
| 2 | **Screen Time API / DeviceActivityMonitor** (Section 6.2) | Problematic | Replaced all `DeviceActivityMonitor` / Family Controls references with `scenePhase`-based detection (app background = distraction). Removed Screen Time API toggle from settings UI. Focus Score now uses: distraction taps (35%), pause frequency (25%), pause duration (20%), session completion (20%), plus automatic scenePhase detection. | `MODULE_ACCOUNTABILITY.md` | REMEDIATED |
| 3 | **Live HR without Apple Watch** (Section 1.5) | Problematic | Added feasibility notes clarifying: live HR requires Apple Watch; Whoop HR arrives post-workout only. Dashboard and integration code now show three paths: Apple Watch (live), Whoop-only (post-sync), no wearable (empty state). | `MODULE_DASHBOARD.md`, `INTEGRATION_SPECS.md` | REMEDIATED |
| 4 | **iOS minimum version 17.0 -> 17.4** (Section 4.1) | Tricky | Changed all deployment target references from iOS 17.0 to iOS 17.4 to avoid SwiftData bugs in 17.0-17.3. | `ARCHITECTURE_DECISIONS.md`, `XCODE_PROJECT_STRUCTURE.md`, `ONBOARDING_AND_NOTIFICATIONS.md`, `SECURITY_AND_PRIVACY.md`, `TESTING_STRATEGY.md`, `RELEASE_CHECKLIST.md`, `CI_CD_PIPELINE.md`, `MODULE_ARENA.md` | REMEDIATED |
| 5 | **64 local notification limit** (Section 3.1) | Tricky | Added detailed scheduling strategy: today-first scheduling, never pre-schedule >48h, rest timers one-at-a-time, re-schedule on foreground, log pending count. | `ONBOARDING_AND_NOTIFICATIONS.md`, `MODULE_ACCOUNTABILITY.md` | REMEDIATED |
| 6 | **Anti-cheat gyroscope monitoring** (Section 6.3) | Tricky | Replaced gyroscope + accelerometer monitoring with `CMMotionActivityManager` (motion coprocessor, battery-efficient) for drive detection and `scenePhase` for app-backgrounded detection. Added Whoop strain cross-validation. | `MODULE_ARENA.md` | REMEDIATED |
| 7 | **AI costs at scale** (Section 6.6) | Tricky | Added prominent note: all AI features must be Pro-only. Free users get rule-based insights. Use Haiku exclusively for v1. Cache common patterns. Reference to MONETIZATION_STRATEGY.md added. | `AI_INTELLIGENCE_ENGINE.md` | REMEDIATED |
| 8 | **Whoop dev mode 10-user limit** (Section 2.1) | Problematic | Added prominent warning block at top of Whoop API section: apply for production access NOW, ship beta with HealthKit-only fallback, gate Whoop features until approved. | `INTEGRATION_SPECS.md` | REMEDIATED |
