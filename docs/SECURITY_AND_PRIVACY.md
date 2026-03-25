# Tempo — Security, Privacy, and Compliance Specification

> **Version:** 2.0.0 (security audit hardening)
> **Last updated:** 2026-03-24
> **Author:** Security & Privacy Office
> **Status:** Authoritative reference for all security and compliance decisions
> **Scope:** iOS app (SwiftUI), Vapor backend, PostgreSQL, all third-party integrations

---

## Table of Contents

1. [App Store Review Preparation](#1-app-store-review-preparation)
2. [HealthKit Compliance](#2-healthkit-compliance)
3. [Data Classification](#3-data-classification)
4. [Authentication Security](#4-authentication-security) — includes multi-device sign-in, token blocklist
5. [Data Encryption](#5-data-encryption) — includes per-item Keychain access levels
6. [API Security](#6-api-security) — includes per-endpoint input validation, dual-scope rate limiting
7. [Third-Party Integration Security](#7-third-party-integration-security) — includes Whoop/Anthropic key compromise playbooks
8. [GDPR Compliance](#8-gdpr-compliance) — includes GDPR applicability analysis
9. [Social Features Security](#9-social-features-security)
10. [Push Notification Security](#10-push-notification-security)
11. [Incident Response Plan](#11-incident-response-plan) — includes Whoop and Anthropic key compromise playbooks
12. [Penetration Testing Checklist](#12-penetration-testing-checklist) — OWASP Mobile Top 10 (2024), BOLA, BFLA, Mass Assignment
13. [Privacy Policy](#13-privacy-policy) — includes CCPA/CPRA rights, Data Retention table, Anthropic data processing
14. [Terms of Service](#14-terms-of-service)

---

## 1. App Store Review Preparation

### 1.1 App Store Review Guidelines — Compliance Checklist

| Guideline # | Title | Tempo Compliance | Notes |
|-------------|-------|-----------------|-------|
| **1.1** | Objectionable Content | PASS | Fitness/productivity app, no user-generated content except usernames and challenge names. Report system in place for Arena. |
| **1.2** | User Generated Content | PASS | Limited UGC (usernames, challenge names). Moderation via report system. No free-form posts, images, or messages between users. |
| **2.1** | App Completeness | Ensure all features functional at review time. TestFlight builds must be feature-complete for the submitted scope. |
| **2.3.1** | Hidden or Undocumented Features | No hidden features. All integrations declared in review notes. |
| **2.5.1** | Software Requirements | Swift 6, iOS 17.4+ minimum (per Technical Feasibility Audit). No deprecated APIs. |
| **3.1.1** | In-App Purchase | Required if Tempo offers premium tiers. All digital goods/subscriptions must use StoreKit 2. No directing users to external payment. |
| **3.1.2** | Subscriptions | If subscription tier exists: clearly communicate what the user gets, offer free trial terms, use StoreKit 2 for management, honor cancellation immediately. |
| **4.0** | Design | Native SwiftUI, follows HIG. No web-view wrappers. |
| **4.2** | Minimum Functionality | App provides substantial value (5 modules, health integration, AI coaching). |
| **5.1** | Privacy — Data Collection and Storage | Full compliance. See Privacy Nutrition Label below. |
| **5.1.1** | Data Collection and Storage | Only collect data essential to functionality. All data collection disclosed. |
| **5.1.2** | Data Use and Sharing | Health data never sold or used for advertising. Sharing only with explicit consent. |
| **5.1.3** | Health and Health Research | HealthKit data handled per Section 27 guidelines. Not a medical device. No clinical claims. |
| **5.1.4** | Kids | Not targeted at children. Age gate not required (fitness app for adults). |
| **5.2** | Intellectual Property | No third-party IP issues. Whoop/NutriTrack integrations are via official APIs. |
| **5.3** | Sign in with Apple | REQUIRED. Tempo uses Sign in with Apple as the sole authentication method. Compliant. |
| **5.4** | Apple Pay | Not applicable. |
| **5.5** | Apple Developer Program | Valid membership required for HealthKit entitlement. |
| **27.1** | HealthKit — Apps Must Comply | See Section 2 below for full HealthKit compliance. |
| **27.2** | HealthKit — Accurate Data | Tempo reads/writes accurate HealthKit data. No fabricated entries. |
| **27.3** | HealthKit — Health Data Use | HealthKit data used solely to provide app features. Never for advertising or data mining. |
| **27.4** | HealthKit — Sharing | HealthKit data never shared with third parties without explicit user consent. Data sent to backend is health-adjacent (Whoop scores) not raw HealthKit samples. |
| **27.5** | HealthKit — Not to iCloud | HealthKit data is NOT stored in iCloud. SwiftData store for health-derived data does NOT use CloudKit. |
| **27.6** | HealthKit — Not Sold | HealthKit data is never sold, licensed, or otherwise distributed. |
| **27.7** | HealthKit — Not for Advertising | HealthKit data is never used for advertising or marketing purposes. |
| **27.8** | HealthKit — Disclosure | App's purpose and HealthKit data usage are clearly disclosed at first launch during onboarding. |

### 1.2 Sign in with Apple Requirements

Tempo uses Sign in with Apple as the **sole** authentication method.

- **Guideline 4.8:** Because Tempo does not offer any other third-party sign-in (Google, Facebook, etc.), Sign in with Apple is the only option — this is compliant.
- **Implementation:** Uses `ASAuthorizationAppleIDProvider` with `ASAuthorizationAppleIDButton`.
- **"Hide My Email" relay:** Fully supported. Backend stores Apple's relay email as the user's email. All system emails are sent to this relay address. The app never asks users to provide a "real" email.
- **Name handling:** Apple provides first/last name only on the FIRST authentication. Backend must persist this on the initial auth call. If lost, user can update display name in settings.
- **Credential revocation:** Backend listens for Apple's server-to-server credential revocation notifications. On receipt, the user's session is invalidated and the account is flagged for re-authentication.

### 1.3 In-App Purchase Requirements

If Tempo introduces a premium tier:

- **StoreKit 2** for all purchase flows (no legacy StoreKit 1).
- Subscription management screen must include a link to Apple's subscription management page.
- Free features must remain functional without purchase (Arena basic features, Dashboard, HealthKit integration).
- Restore purchases button must be accessible from Settings.
- Subscription terms displayed before purchase: price, billing period, free trial duration, auto-renewal terms.
- Server-side receipt validation using Apple's App Store Server API v2 (not the deprecated `/verifyReceipt`).

### 1.4 Privacy Nutrition Label

> **Cross-reference:** See also `docs/APP_STORE_COMPLIANCE.md` Section 3.1 for the complete
> Privacy Nutrition Label with third-party AI processing disclosure notes.

This is the EXACT declaration for App Store Connect.

#### Data Collected

| Data Type | Collected | Linked to Identity | Used for Tracking | Purpose |
|-----------|-----------|-------------------|-------------------|---------|
| **Name** (display name) | Yes | Yes | No | App Functionality |
| **Email Address** (Apple relay) | Yes | Yes | No | App Functionality |
| **User ID** (Apple User ID, internal UUID) | Yes | Yes | No | App Functionality |
| **Health & Fitness — Health** (heart rate, HRV, resting HR) | Yes | Yes | No | App Functionality |
| **Health & Fitness — Fitness** (workouts, steps, active energy, exercise data) | Yes | Yes | No | App Functionality |
| **Health & Fitness — Sleep** (sleep duration, sleep stages, sleep score) | Yes | Yes | No | App Functionality |
| **Health & Fitness — Nutrition** (calories, macros, meals logged) | Yes | Yes | No | App Functionality |
| **Health & Fitness — Body Measurements** (weight, body fat via Whoop) | Yes | Yes | No | App Functionality |
| **Usage Data — Product Interaction** (feature usage, screen views) | Yes | No | No | Analytics |
| **Diagnostics — Crash Data** | Yes | No | No | App Functionality |
| **Diagnostics — Performance Data** | Yes | No | No | App Functionality |
| **Identifiers — Device ID** (for push notifications) | Yes | No | No | App Functionality |
| **Contacts — Contacts** | No | — | — | — |
| **Location — Precise Location** | No | — | — | — |
| **Location — Coarse Location** | No | — | — | — |
| **Financial Info** | No | — | — | — |
| **Sensitive Info** | No | — | — | — |
| **Browsing History** | No | — | — | — |
| **Search History** | No | — | — | — |
| **Photos or Videos** | No | — | — | — |
| **Audio Data** | No | — | — | — |

#### Data NOT Collected
- Precise location
- Coarse location
- Contacts
- Photos or videos
- Audio data
- Browsing history
- Search history
- Financial information
- Sensitive information (political, religious, sexual orientation)

#### Tracking Declaration
**Tempo does NOT track users.** No data is shared with data brokers. No advertising SDKs. No cross-app tracking identifiers. `ATTrackingManager` is NOT integrated because it is not needed.

### 1.5 App Review Notes

Use this text verbatim in the "Notes for Reviewer" field in App Store Connect:

```
Tempo is a personal life management app that integrates health, fitness,
nutrition, academics, and social accountability features.

SIGN IN WITH APPLE:
Sign in with Apple is the sole authentication method. No demo account
is needed — the reviewer can create a fresh account using their Apple ID.

HEALTHKIT — WHY EACH DATA TYPE IS NEEDED:
Tempo reads the following HealthKit data types. Each is essential to
a specific app feature:

- Step Count (HKQuantityTypeIdentifierStepCount): Displayed in the
  "Move" quadrant of the daily LifeOS dashboard. Used to auto-complete
  the "steps" non-negotiable when the user's daily target is met.

- Active Energy Burned (HKQuantityTypeIdentifierActiveEnergyBurned):
  Displayed in the "Move" quadrant alongside step data. Provides
  caloric expenditure context for the nutrition/fuel quadrant.

- Heart Rate (HKQuantityTypeIdentifierHeartRate): Shown during active
  workouts in RepForge (training module) to display real-time exertion.
  Also used in the Recovery module when Whoop is not connected.

- Heart Rate Variability (HKQuantityTypeIdentifierHeartRateVariabilitySDNN):
  Used by the Recovery module (RecoverIQ) to compute daily recovery
  scores when Whoop is not connected. HRV is the primary input to
  recovery-adjusted training recommendations.

- Resting Heart Rate (HKQuantityTypeIdentifierRestingHeartRate):
  Displayed in the "Body" quadrant and used as a secondary recovery
  signal alongside HRV.

- Sleep Analysis (HKCategoryTypeIdentifierSleepAnalysis): Displayed
  in the "Body" quadrant. Sleep duration and quality feed into the
  daily recovery score computation and inform bedtime prescriptions.

- Workout Type (HKWorkoutType): Tempo reads existing workouts to
  avoid double-counting when the user also logs workouts in RepForge.
  Workout history is displayed on the training calendar.

Tempo writes the following data types back to HealthKit:

- Workouts (HKWorkoutType): Workouts completed in RepForge are
  written so the user's Apple Health record stays complete.

- Dietary Energy Consumed (HKQuantityTypeIdentifierDietaryEnergyConsumed):
  Calorie data synced from NutriTrack is written so the Health app
  shows complete nutrition data.

HealthKit data is used EXCLUSIVELY for the features described above.
It is never shared with third parties, never used for advertising,
never stored in iCloud, and raw HealthKit samples never leave the
device (see our privacy policy for details).

THE APP FUNCTIONS WITHOUT HEALTHKIT:
If the user denies HealthKit access entirely, every feature still
works. The dashboard shows "Enable in Settings" placeholders for
unavailable data. Training works with manual RPE input. Recovery
uses Whoop data (if connected) or shows a connect-Whoop prompt.
Non-negotiables that depend on step count require manual check-off.

WHOOP INTEGRATION:
Tempo connects to the Whoop API via OAuth 2.0 to fetch recovery scores,
sleep data, strain, and HRV. A Whoop account is OPTIONAL — the app
functions without it using HealthKit data alone. If the reviewer does
not have a Whoop device, the app gracefully degrades and shows
HealthKit-only data.

NUTRITRACK INTEGRATION:
Tempo connects to NutriTrack (a companion nutrition app) to display
meal and macro data. This integration is OPTIONAL — the app functions
without it. If not connected, the Fuel quadrant shows placeholder state.

NOTIFICATIONS:
Tempo sends local notifications for accountability reminders (e.g.,
study targets, workout reminders). These use the drill-sergeant tone
described in the app description.

SOCIAL FEATURES:
The Arena module allows users to add friends, compete on leaderboards,
and create challenges. All social features require mutual friend
acceptance. Blocking is fully supported.

AI FEATURES:
Weekly insight reports are generated using the Claude API (Anthropic).
Only aggregated, anonymized health scores are sent to the API — no
raw HealthKit data, no PII.

SUBSCRIPTIONS:
[If applicable: describe subscription tiers, or state "No in-app
purchases at launch."]
```

### 1.6 Required Privacy Policy Contents

The privacy policy (Section 13) must cover ALL of the following per Apple's requirements:

- [ ] What data is collected (every type from the Nutrition Label)
- [ ] How data is used (per-purpose breakdown)
- [ ] How data is shared and with whom (Anthropic for AI, Whoop for integration)
- [ ] How data is stored and protected
- [ ] Data retention periods
- [ ] User rights (access, deletion, correction)
- [ ] Contact information for privacy inquiries
- [ ] HealthKit-specific data handling disclosure
- [ ] Third-party service disclosure
- [ ] Children's privacy statement
- [ ] Changes notification process
- [ ] Effective date
- [ ] Applicable law / jurisdiction

The privacy policy must be accessible:
1. In the App Store listing (URL field in App Store Connect)
2. Within the app (Settings > Privacy Policy)
3. During onboarding before first data collection

### 1.7 Required Terms of Service Contents

See Section 14 for the full ToS. It must be accessible:
1. In the App Store listing
2. Within the app (Settings > Terms of Service)
3. During onboarding (agree before account creation)

### 1.8 TestFlight Beta Testing Requirements

- **Internal testing:** Up to 100 internal testers (team members with App Store Connect access). No review needed.
- **External testing:** Up to 10,000 external testers. Requires Beta App Review.
- Beta App Review requires:
  - App description
  - Feedback email
  - Privacy policy URL
  - Beta builds must not expire during review (build validity: 90 days)
- **TestFlight-specific requirements:**
  - Crash-free rate must exceed 99% before public TestFlight
  - All HealthKit permissions must degrade gracefully if denied
  - Whoop/NutriTrack disconnected states must be fully functional
  - Push notification opt-out must work correctly

---

## 2. HealthKit Compliance

### 2.1 HealthKit Entitlement

**Entitlement file:** `Tempo.entitlements`
```xml
<key>com.apple.developer.healthkit</key>
<true/>
<key>com.apple.developer.healthkit.access</key>
<array>
    <string>health-records</string>
</array>
<key>com.apple.developer.healthkit.background-delivery</key>
<true/>
```

**Capabilities in Xcode:**
- HealthKit (required)
- HealthKit Background Delivery (required for background step/workout/sleep updates)

### 2.2 Required Usage Description Strings

These appear in `Info.plist` and are shown to the user in the HealthKit authorization sheet.

```xml
<!-- Read access justification -->
<key>NSHealthShareUsageDescription</key>
<string>Tempo reads your health data (steps, heart rate, HRV, resting heart rate, active energy, sleep, and workouts) to build your daily LifeOS dashboard, adjust training recommendations based on recovery, and track your fitness progress. Your health data is never shared with advertisers or sold to third parties.</string>

<!-- Write access justification -->
<key>NSHealthUpdateUsageDescription</key>
<string>Tempo writes your completed workouts and nutrition data to HealthKit so your health record stays complete across all your apps. Only workouts you log in RepForge and meals synced from NutriTrack are written.</string>
```

**Other required Info.plist keys:**

```xml
<!-- Calendar access for study/football schedule -->
<key>NSCalendarsUsageDescription</key>
<string>Tempo reads your calendar to avoid scheduling workouts during classes and football practice, and to identify study blocks for your accountability targets.</string>

<!-- Push notifications -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
    <string>processing</string>
</array>
```

### 2.3 HealthKit Data Handling Rules (Apple's Mandates)

These are **non-negotiable** Apple requirements. Violation results in app rejection or removal.

| Rule | Implementation |
|------|---------------|
| **HealthKit data MUST NOT be used for advertising** | No ad SDKs in the app. No health data transmitted to any advertising platform. Enforced by code review and CI checks. |
| **HealthKit data MUST NOT be sold** | Terms of service and privacy policy explicitly state this. No data broker integrations. |
| **HealthKit data MUST NOT be stored in iCloud** | The SwiftData `ModelContainer` for health-derived models (`DailySnapshot`, `DailyPrescription`, `WorkoutPlan`, `RecoveryPrescription`) is configured with `cloudKitDatabase: .none`. This MUST be enforced at three levels: (1) the SwiftData `ModelConfiguration` uses `.none`; (2) a CI test asserts that the health-data `ModelConfiguration` never initializes with `.automatic` or `.private`; (3) code review checklist item: "Does this model contain HealthKit-derived data? If yes, verify `cloudKitDatabase: .none`." Only non-health data (settings, exercise library, user preferences) may sync via CloudKit. If CloudKit sync is added for ANY model in the future, a mandatory review must confirm the model contains zero health-derived fields. |
| **HealthKit data MUST NOT be shared with third parties without explicit consent** | No raw HealthKit samples leave the device. Derived scores (daily score, XP) are computed locally and only the composite score is synced to the backend for Arena features. |
| **HealthKit data read/write must be authorized by the user** | Authorization requested during onboarding via `HKHealthStore.requestAuthorization()`. Each data type is individually authorized. |
| **App must still function if HealthKit access is denied** | See graceful degradation spec below. |

### 2.4 Graceful Degradation When HealthKit Permission Is Denied

Users may deny HealthKit access entirely or grant partial access. Tempo MUST remain fully functional.

| HealthKit Type | If Denied |
|---------------|-----------|
| Step Count | Move quadrant shows "Steps unavailable — enable in Settings > Health > Tempo". Accountability non-negotiable for steps is disabled. |
| Heart Rate | No live HR during workouts. Training module still functions with manual RPE input. |
| HRV (SDNN) | Whoop HRV is used as primary source. If both denied, Recovery module shows Whoop-only data or "Connect Whoop for recovery data." |
| Resting Heart Rate | Same as HRV. Whoop is primary. |
| Active Energy Burned | Move quadrant shows workout-based estimates only. |
| Sleep Analysis | Whoop is primary sleep source. HealthKit sleep supplements but is not required. |
| Workout Type | User can still log workouts manually in RepForge. Auto-detection disabled. |
| Write: Dietary Energy | NutriTrack data stays in Tempo only. Not written to HealthKit. Silent failure. |
| Write: Workouts | RepForge workouts not written to HealthKit. Silent failure. |

**Critical rule:** Tempo MUST NOT repeatedly prompt the user to grant HealthKit access after initial denial. A single, non-modal "Enable Health Access" button in Settings is acceptable. The HealthKit authorization sheet can only be triggered once per data type — subsequent calls to `requestAuthorization()` are silently ignored by iOS.

#### Graceful Degradation for ALL Optional Integrations (Apple Requirement)

Apple requires that the app provides value without any optional integration. Here is the complete degradation matrix:

| Integration Denied/Disconnected | Dashboard | Training (RepForge) | Accountability (Lockdown) | Recovery (RecoverIQ) | Arena (ClutchTime) |
|--------------------------------|-----------|--------------------|--------------------------|--------------------|-------------------|
| **HealthKit fully denied** | Move quadrant: "Enable in Settings". Body quadrant: Whoop-only or placeholder. | Manual RPE input. No auto-detected workouts. | Steps non-negotiable requires manual check-off. | Whoop-only or "Connect Whoop" prompt. | XP still earnable from study, nutrition, manual workouts. |
| **Whoop not connected** | Body quadrant uses HealthKit HR/HRV/sleep. | No recovery-adjusted training (uses generic recommendations). | No impact. | HealthKit-only recovery data or "Connect a device" placeholder. | No impact. |
| **NutriTrack not connected** | Fuel quadrant: "Connect NutriTrack" placeholder. | No impact. | Meals non-negotiable requires manual check-off. | No impact. | No nutrition XP. |
| **Calendar denied** | Mind quadrant shows manual study blocks only. | No schedule-aware workout timing. | Study non-negotiable uses manual schedule. | No impact. | No impact. |
| **Notifications denied** | No impact on data display. | No workout reminders. | No accountability reminders (drill-sergeant disabled). | No bedtime/caffeine reminders. | No challenge/friend notifications. |
| **ALL integrations denied** | App shows placeholder states in all quadrants. User can still manually log workouts, check off non-negotiables, and use the focus timer. The app MUST remain functional as a manual accountability tracker. | Manual workout logging with exercise library. | Manual check-off for all non-negotiables. | "Connect a device for recovery data" screen. | XP from manual activities. Social features work. |

### 2.5 HealthKit Data on the Backend

**Rule: Raw HealthKit samples NEVER leave the device.**

The backend receives only:
- **Composite daily scores** (0-100) computed on-device from multiple data sources
- **XP events** ("+100 XP for workout") which contain no health data
- **Boolean flags** (e.g., `workoutCompleted: true`) with no biometric detail
- **Whoop data** fetched by the backend directly from the Whoop API (not from HealthKit)

This design means:
- The backend database contains NO HealthKit data
- If the backend is compromised, no health data is exposed
- Apple's HealthKit rules about server-side storage do not apply because we do not transmit HealthKit data server-side
- The Claude AI service receives only anonymized composite scores, never HealthKit samples

---

## 3. Data Classification

### 3.1 Classification Levels

#### HIGHLY SENSITIVE (Level 4)

Data whose exposure would cause significant harm. Subject to health data regulations.

| Data Item | Storage Location | Encryption at Rest | Encryption in Transit | Retention | Access Control |
|-----------|-----------------|-------------------|----------------------|-----------|---------------|
| Heart rate samples | iOS HealthKit store only | iOS Data Protection (Complete Protection) | N/A (never transmitted) | Managed by HealthKit | User-controlled via Health app |
| HRV (SDNN) samples | iOS HealthKit store only | iOS Data Protection (Complete Protection) | N/A (never transmitted) | Managed by HealthKit | User-controlled via Health app |
| Resting heart rate | iOS HealthKit store only | iOS Data Protection (Complete Protection) | N/A (never transmitted) | Managed by HealthKit | User-controlled via Health app |
| Sleep stage data | iOS HealthKit store only | iOS Data Protection (Complete Protection) | N/A (never transmitted) | Managed by HealthKit | User-controlled via Health app |
| Whoop OAuth tokens (access + refresh) | PostgreSQL backend | AES-256-GCM (application-layer) + RDS volume encryption | TLS 1.3 | Until user disconnects Whoop or deletes account | Backend WhoopService only |
| Whoop recovery/sleep/strain data | PostgreSQL backend (cached) | RDS volume encryption | TLS 1.3 (Whoop API to backend) | 90 days rolling cache, then aggregated | Backend WhoopService, user's own requests only |
| JWT refresh tokens | PostgreSQL backend | SHA-256 hash stored (not plaintext) | TLS 1.3 | Until rotation or 30-day expiry | AuthService only |
| Apple identity token | Memory only (transient) | N/A | TLS 1.3 | Discarded after validation | AuthController during sign-in only |
| NutriTrack PIN | PostgreSQL backend (.env at rest) | Environment variable, not in DB. Server memory only. | TLS 1.3 | Lifetime of integration | NutriTrackService only |

#### SENSITIVE (Level 3)

Data whose exposure would cause moderate harm or embarrassment.

| Data Item | Storage Location | Encryption at Rest | Encryption in Transit | Retention | Access Control |
|-----------|-----------------|-------------------|----------------------|-----------|---------------|
| Nutrition data (meals, macros, calories) | iOS SwiftData + backend cache | iOS Data Protection (Complete Until First User Authentication) | TLS 1.3 | Until account deletion | User's own requests only |
| Study session records | iOS SwiftData + backend sync | iOS Data Protection | TLS 1.3 | Until account deletion | User only (not visible to friends) |
| Non-negotiable progress | iOS SwiftData + backend sync | iOS Data Protection | TLS 1.3 | Until account deletion | User only |
| Workout history (exercises, weights, sets) | iOS SwiftData | iOS Data Protection | TLS 1.3 (if synced) | Until account deletion | User only |
| Daily composite scores (0-100) | iOS SwiftData + backend | iOS Data Protection / RDS encryption | TLS 1.3 | Until account deletion | User + friends (if Arena opted in) |
| Calendar events (class/exam schedule) | iOS EventKit (read-only) | iOS Data Protection | N/A (never transmitted) | Not stored by Tempo | CalendarService read-only |
| Body measurements (weight, body fat) | iOS SwiftData (from Whoop) | iOS Data Protection | TLS 1.3 | Until account deletion | User only |
| Daily prescriptions (bedtime, caffeine cutoff) | iOS SwiftData | iOS Data Protection | N/A (local only) | Until account deletion | User only |

#### PERSONAL (Level 2)

Personally identifiable information that is not health-related.

| Data Item | Storage Location | Encryption at Rest | Encryption in Transit | Retention | Access Control |
|-----------|-----------------|-------------------|----------------------|-----------|---------------|
| Username | PostgreSQL backend | RDS volume encryption | TLS 1.3 | Until account deletion | Public (visible to other users in Arena) |
| Display name | PostgreSQL backend | RDS volume encryption | TLS 1.3 | Until account deletion | Public (visible to friends) |
| Email address (Apple relay) | PostgreSQL backend | RDS volume encryption | TLS 1.3 | Until account deletion | Backend only, never exposed to other users |
| Apple User ID (sub claim) | PostgreSQL backend | RDS volume encryption | TLS 1.3 | Until account deletion | Backend auth system only |
| Profile photo (if implemented) | Object storage (S3/R2) | Server-side encryption | TLS 1.3 | Until changed or account deletion | Public (if set) |
| Device tokens (APNs) | PostgreSQL backend | RDS volume encryption | TLS 1.3 | Until device unregistered or account deletion | PushNotificationService only |

#### PUBLIC (Level 1)

Data explicitly chosen by the user to be shared.

| Data Item | Storage Location | Encryption at Rest | Encryption in Transit | Retention | Access Control |
|-----------|-----------------|-------------------|----------------------|-----------|---------------|
| XP total and level | PostgreSQL backend | RDS volume encryption | TLS 1.3 | Until account deletion | Visible to friends; leaderboard rank visible to all participants |
| Leaderboard rank | PostgreSQL backend (materialized view) | RDS volume encryption | TLS 1.3 | Refreshed weekly | Visible to leaderboard participants |
| Achievement badges | PostgreSQL backend | RDS volume encryption | TLS 1.3 | Until account deletion | Visible to friends |
| Challenge participation + score | PostgreSQL backend | RDS volume encryption | TLS 1.3 | Until challenge ends + 30 days | Visible to challenge participants |
| Streak count (days) | PostgreSQL backend | RDS volume encryption | TLS 1.3 | Until account deletion | Visible to friends |

### 3.2 Data Flow Diagram — Classification Boundaries

```
┌──────────────────────────────────────────────────┐
│              iOS DEVICE (Trust Boundary 1)         │
│                                                    │
│  ┌─────────────────┐    ┌──────────────────┐      │
│  │  HealthKit Store │    │  iOS Keychain     │      │
│  │  [LEVEL 4]       │    │  [LEVEL 4]        │      │
│  │  HR, HRV, RHR,  │    │  JWT access token  │      │
│  │  Sleep, Steps    │    │  Backend URL       │      │
│  │  *** NEVER LEAVES│    └──────────────────┘      │
│  │      DEVICE ***  │                               │
│  └─────────────────┘    ┌──────────────────┐      │
│                          │  SwiftData Store  │      │
│  ┌─────────────────┐    │  [LEVEL 2-3]      │      │
│  │  EventKit        │    │  DailySnapshot    │      │
│  │  [LEVEL 3]       │    │  Workouts         │      │
│  │  Calendar events │    │  Nutrition cache  │      │
│  │  *** NEVER LEAVES│    │  Prescriptions    │      │
│  │      DEVICE ***  │    └──────────────────┘      │
│  └─────────────────┘                               │
└────────────────────┬─────────────────────────────┘
                     │ TLS 1.3
                     │ Only: composite scores, XP,
                     │ social data, sync payloads
                     │ NEVER: raw HealthKit, calendar
                     ▼
┌──────────────────────────────────────────────────┐
│          TEMPO BACKEND (Trust Boundary 2)          │
│                                                    │
│  ┌──────────────────┐   ┌──────────────────┐     │
│  │  PostgreSQL       │   │  Environment Vars │     │
│  │  [LEVEL 1-3]      │   │  [LEVEL 4]        │     │
│  │  Users, XP,       │   │  Whoop secret      │     │
│  │  Friendships,     │   │  NutriTrack PIN    │     │
│  │  Whoop tokens     │   │  Claude API key    │     │
│  │  (encrypted)      │   │  JWT signing key   │     │
│  └──────────────────┘   └──────────────────┘     │
└──────┬──────────┬──────────┬─────────────────────┘
       │          │          │
       ▼          ▼          ▼
   ┌────────┐ ┌────────┐ ┌────────┐
   │ Whoop  │ │NutriTrk│ │ Claude │
   │  API   │ │ (Flask)│ │  API   │
   │[LEVEL4]│ │[LEVEL3]│ │[LEVEL1]│
   └────────┘ └────────┘ └────────┘
```

---

## 4. Authentication Security

### 4.1 Sign in with Apple — Implementation Security

#### Identity Token Validation (Server-Side)

The Vapor backend MUST validate the Apple identity token on every initial authentication. Validation steps, in order:

1. **Decode JWT header** — Extract `kid` (Key ID) and `alg` (must be `RS256`). NOTE: Apple's identity tokens use RS256 — this is correct for *Apple's* tokens. Tempo's own access/refresh tokens use ES256. Do not confuse the two.
2. **Fetch Apple's public keys** — `GET https://appleid.apple.com/auth/keys`. Cache the JWKS for 24 hours. Rotate cache on `kid` mismatch.
3. **Verify signature** — Validate the JWT signature using the matching Apple public key.
4. **Verify issuer (`iss`)** — Must be exactly `https://appleid.apple.com`.
5. **Verify audience (`aud`)** — Must match Tempo's App ID (Bundle ID): `com.nicoladebbia.tempo`.
6. **Verify expiry (`exp`)** — Token must not be expired. Allow a 5-minute clock skew tolerance.
7. **Verify nonce** — The `nonce` claim in the token must match the SHA-256 hash of the nonce the iOS client generated and submitted. This prevents replay attacks.
8. **Extract subject (`sub`)** — This is the stable Apple User ID. Use this as the primary user identifier.

```swift
// Pseudo-code for Vapor backend
func validateAppleIdentityToken(_ token: String, expectedNonce: String) throws -> AppleTokenPayload {
    let jwks = try await fetchApplePublicKeys() // cached 24h
    let payload = try jwt.verify(token, using: jwks)

    guard payload.issuer == "https://appleid.apple.com" else { throw AuthError.invalidIssuer }
    guard payload.audience == "com.nicoladebbia.tempo" else { throw AuthError.invalidAudience }
    guard payload.expiration > Date().addingTimeInterval(-300) else { throw AuthError.tokenExpired }

    let expectedNonceHash = SHA256.hash(data: Data(expectedNonce.utf8)).hexString
    guard payload.nonce == expectedNonceHash else { throw AuthError.nonceMismatch }

    return payload
}
```

#### Nonce Generation (iOS Client)

```swift
// iOS client generates a cryptographically random nonce per auth attempt
func randomNonceString(length: Int = 32) -> String {
    var randomBytes = [UInt8](repeating: 0, count: length)
    _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
    return randomBytes.map { String(format: "%02x", $0) }.joined()
}
```

The nonce is:
1. Generated fresh for each sign-in attempt
2. Sent to Apple in the authorization request
3. Sent to the Tempo backend alongside the identity token
4. Verified server-side (SHA-256 hash must match the `nonce` claim in the JWT)

#### Server-Side Authorization Code Exchange

After validating the identity token, the backend exchanges the authorization code with Apple:

```
POST https://appleid.apple.com/auth/token
Content-Type: application/x-www-form-urlencoded

client_id=com.nicoladebbia.tempo
client_secret=<JWT signed with Apple private key>
code=<authorization_code from client>
grant_type=authorization_code
```

The response includes Apple's refresh token, which the backend stores encrypted for future credential validation and account revocation detection.

#### Handling Apple's "Hide My Email" Relay

- The email from Apple may be a relay address like `abc123@privaterelay.appleid.com`.
- Tempo treats this as the user's real email for all purposes.
- System emails (account notifications, weekly reports if email-enabled) are sent to the relay.
- The relay forwards to the user's real email. Tempo never sees or stores the real email.
- Email sending domain must be registered with Apple at `https://developer.apple.com/account/resources/identifiers/emails`.

### 4.2 JWT Security

#### Token Architecture

| Token | Algorithm | Lifetime | Storage (iOS) | Storage (Backend) |
|-------|-----------|----------|---------------|-------------------|
| Access Token | ES256 (ECDSA P-256 + SHA-256) | 15 minutes | iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) | Not stored (stateless) |
| Refresh Token | Opaque (random 256-bit, prefixed `rt_`) | 30 days | iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) | SHA-256 hash in `refresh_tokens` table |

#### Access Token Payload

```json
{
  "sub": "user_uuid_here",
  "iss": "tempo-api",
  "aud": "tempo-ios",
  "iat": 1711234567,
  "exp": 1711235467,
  "jti": "unique_token_id",
  "device_id": "device_uuid"
}
```

#### Why ES256 over RS256 for Tempo's Own JWTs

- **Smaller tokens:** ES256 signatures are ~64 bytes vs. ~256 bytes for RS256. Material savings on every API call.
- **Faster verification:** ECDSA verification is faster on mobile hardware with Secure Enclave support.
- **Modern standard:** ES256 (ECDSA P-256) is the NIST-recommended curve for new applications.
- **Clarification:** Apple's identity tokens use RS256 (we validate those). Tempo's own access tokens use ES256 (we sign those). These are separate key pairs and algorithms.

#### Key Rotation Schedule

| Key | Rotation Frequency | Procedure |
|-----|--------------------|-----------|
| JWT signing key (ES256 private key) | Every 90 days | Generate new key pair. Add new `kid` to active keys. Old key remains valid for verification until all tokens signed with it expire (max 30 days for refresh tokens). Old key removed 31 days after rotation. |
| Apple .p8 private key | As needed (Apple does not expire these) | Store in secure vault (AWS Secrets Manager or similar). Access restricted to deployment pipeline. |
| APNs .p8 key | As needed | Same as Apple .p8 key. |

#### Token Storage on iOS

**MANDATORY: All tokens stored in iOS Keychain. NEVER in UserDefaults, files, or SwiftData.**

```swift
// Keychain wrapper for token storage
final class TokenStorage {
    private static let service = "com.nicoladebbia.tempo"

    static func saveAccessToken(_ token: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "access_token",
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        // Delete existing, then add
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }
}
```

**Keychain access control:** `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- Available after first unlock (supports background sync)
- Not backed up to iCloud Keychain (device-only)
- Not available on other devices
- Protected by the device passcode and Secure Enclave

#### Refresh Token Rotation

1. Client sends refresh token to `POST /v1/auth/refresh`.
2. Backend looks up the SHA-256 hash of the token in `refresh_tokens` table.
3. If found and not expired:
   a. Mark the old refresh token as **used**.
   b. Generate a new access token + new refresh token.
   c. Store SHA-256 hash of the new refresh token.
   d. Return both to the client.
4. If the old refresh token was ALREADY marked as used (replay detected):
   a. **Revoke ALL refresh tokens for this user** (force re-auth on all devices).
   b. Return `401` with error code `1011` (replay detected).
   c. Log a security event.

#### Token Revocation

Tokens are revoked in these scenarios:
- **User signs out:** All refresh tokens for the user's device are revoked.
- **Password change / account compromise:** All refresh tokens for the user across all devices are revoked.
- **Apple credential revocation:** All tokens revoked, account flagged.
- **Admin action:** Individual user's tokens can be revoked via admin endpoint.

#### Multi-Device Sign-In and Token Isolation

When a user signs in on a new device:

1. A new refresh token is issued for the new device. It is stored with a `device_id` column in `refresh_tokens`.
2. **Old devices are NOT automatically invalidated.** The user may use Tempo on an iPhone and iPad simultaneously.
3. Each device has its own independent refresh token. Refresh token rotation is per-device: rotating device A's token does not affect device B.
4. If replay detection fires on device A (see Refresh Token Rotation above), ALL tokens for the user across ALL devices are revoked (nuclear option — attacker may have stolen tokens from any device).
5. Maximum 5 concurrent devices per user. Signing in on a 6th device automatically revokes the least-recently-used device's tokens.

**Database schema for device-scoped tokens:**

```sql
CREATE TABLE refresh_tokens (
    id              UUID PRIMARY KEY,
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    token_hash      TEXT NOT NULL UNIQUE,    -- SHA-256 of the refresh token
    device_id       TEXT NOT NULL,           -- iOS identifierForVendor or UUID generated at first launch
    device_name     TEXT,                    -- e.g., "iPhone 16 Pro"
    is_used         BOOLEAN DEFAULT FALSE,   -- Set true on rotation (replay detection)
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL,
    last_used_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);
```

#### Token Blocklist (for Compromised Access Tokens)

Access tokens are stateless (verified by signature only), which means a compromised access token remains valid until expiry (15 minutes). For scenarios requiring immediate invalidation:

1. **Blocklist in Redis:** When a token must be invalidated before expiry (e.g., user reports account compromise, admin action), add the token's `jti` claim to a Redis set with TTL equal to the token's remaining lifetime.
2. **JWT middleware check:** On every request, after signature verification, check if the `jti` is in the blocklist. If yes, return `401`.
3. **Size management:** Entries auto-expire from Redis when the token would have expired anyway. Maximum blocklist size is bounded by: (active users) x (compromises per 15-min window), which is negligible.
4. **When to blocklist:**
   - User explicitly signs out (blocklist the current access token's `jti`)
   - Admin forces sign-out
   - Apple credential revocation received
   - Refresh token replay detected (blocklist all `jti` values from the last 15 minutes for that user)

```swift
// Redis blocklist check in JWTMiddleware
func authenticate(request: Request) async throws {
    let payload = try request.jwt.verify(as: AccessTokenPayload.self)

    // Check blocklist
    let isBlocked = try await request.redis.get("blocked_jti:\(payload.jti)", as: Bool.self)
    if isBlocked == true {
        throw Abort(.unauthorized, reason: "Token has been revoked")
    }
    // ... continue with normal auth flow
}

// Blocklist a token
func blockToken(jti: String, remainingTTL: Int, on redis: RedisClient) async throws {
    try await redis.setex("blocked_jti:\(jti)", toJSON: true, expirationInSeconds: remainingTTL)
}
```

#### Handling Expired Tokens During Background Sync

When the iOS app performs a background sync (e.g., HealthKit background delivery triggers a data update):

1. `SyncService` attempts the API call with the current access token.
2. If `401` response, `SyncService` attempts a refresh using the refresh token.
3. If refresh succeeds, retry the original request with the new access token.
4. If refresh fails (token expired or revoked), schedule a local notification: "Tempo needs you to sign in again."
5. Do NOT show a blocking auth screen during background execution.

### 4.3 Biometric Unlock (Optional Security Feature)

Tempo offers optional Face ID / Touch ID to unlock the app (since it contains sensitive health data).

- **Implementation:** `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`
- **Fallback:** Device passcode if biometric fails 3 times.
- **Scope:** Biometric gate only protects app launch. Individual sensitive actions (e.g., deleting account) require re-authentication with Sign in with Apple.
- **Storage:** Biometric preference stored in SwiftData (`UserSettings.biometricLockEnabled`), NOT in Keychain (it's a preference, not a credential).
- **Info.plist key required:**
  ```xml
  <key>NSFaceIDUsageDescription</key>
  <string>Tempo uses Face ID to protect your health and fitness data from unauthorized access.</string>
  ```

---

## 5. Data Encryption

### 5.1 Encryption at Rest

#### iOS Device

**iOS Data Protection API** provides file-level encryption for all app data.

| Data Store | Protection Class | Behavior | Rationale |
|-----------|-----------------|----------|-----------|
| SwiftData `.store` file (health-derived data) | `NSFileProtectionCompleteUntilFirstUserAuthentication` | Encrypted at rest. Accessible after first unlock. Supports background delivery and background sync. | **NOT** `NSFileProtectionComplete` because Complete Protection makes the file inaccessible when the device is locked, which blocks HealthKit background delivery, background app refresh, and silent push sync. `CompleteUntilFirstUserAuthentication` is the correct choice: it keeps data encrypted at rest while allowing background operations after the user unlocks the device once per boot. |
| iOS Keychain — JWT access token | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | Available after first unlock. Not backed up to iCloud Keychain. | Background sync needs to attach JWTs to API calls. `ThisDeviceOnly` prevents token migration to new devices. |
| iOS Keychain — JWT refresh token | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | Same as access token. | Same rationale: background token refresh requires access while device is locked. |
| iOS Keychain — Whoop OAuth tokens (if cached on device) | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | Available after first unlock. Not synced to iCloud. | Whoop tokens are primarily stored on the backend, but if the iOS app caches them for direct API calls, they need background access. |
| iOS Keychain — Biometric auth flag | `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` | Only accessible when device has a passcode set AND is unlocked. Invalidated if passcode is removed. | Biometric unlock is a foreground-only operation. Using `WhenPasscodeSet` ties it to the device's security posture — if the user removes their passcode, the biometric gate is invalidated. |
| HealthKit store | Managed by Apple (`NSFileProtectionComplete`) | Inaccessible when device is locked. Tempo has no control over this. | Apple manages this. HealthKit background delivery callbacks fire after the device is unlocked, so `Complete` protection does not block background delivery. |
| EventKit store | Managed by Apple | Same as HealthKit. | Apple manages this. |

**SwiftData file protection configuration:**

```swift
// Set file protection on the SwiftData store directory
let storeURL = URL.applicationSupportDirectory.appending(path: "TempoLocal.store")
try FileManager.default.setAttributes(
    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
    ofItemAtPath: storeURL.path()
)
```

**SwiftData configuration for health data:**

```swift
let schema = Schema([DailySnapshot.self, WorkoutPlan.self, /* ... */])
let config = ModelConfiguration(
    "TempoLocal",
    schema: schema,
    isStoredInMemoryOnly: false,
    cloudKitDatabase: .none  // CRITICAL: No CloudKit for health-derived data
)
```

#### Backend (PostgreSQL)

| Layer | Method | Details |
|-------|--------|---------|
| **Volume encryption** | AWS RDS encryption (AES-256) or equivalent | Encrypts the entire EBS volume at rest. Managed by AWS. Uses AWS KMS customer-managed key (CMK). |
| **Application-layer encryption for tokens** | AES-256-GCM | Whoop OAuth tokens are encrypted at the application layer BEFORE storage in PostgreSQL. The encryption key is stored in AWS Secrets Manager, not in the database or environment variables. |
| **Refresh token hashing** | SHA-256 | Refresh tokens are stored as irreversible hashes. The plaintext token is never stored. |
| **Connection encryption** | TLS required (`sslmode=require`) | All connections between Vapor and PostgreSQL are encrypted. |

**Whoop token encryption implementation:**

```swift
// Backend: Encrypt Whoop tokens before storage
struct WhoopTokenEncryptor {
    private let key: SymmetricKey // loaded from Secrets Manager at boot

    func encrypt(token: String) throws -> (ciphertext: Data, nonce: Data, tag: Data) {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(
            Data(token.utf8),
            using: key,
            nonce: nonce
        )
        return (sealedBox.ciphertext, Data(nonce), Data(sealedBox.tag))
    }

    func decrypt(ciphertext: Data, nonce: Data, tag: Data) throws -> String {
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: ciphertext,
            tag: tag
        )
        let decrypted = try AES.GCM.open(sealedBox, using: key)
        return String(data: decrypted, encoding: .utf8)!
    }
}
```

**PostgreSQL schema for encrypted Whoop tokens:**

```sql
CREATE TABLE whoop_tokens (
    user_id         UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    access_token_ct BYTEA NOT NULL,       -- AES-256-GCM ciphertext
    access_token_iv BYTEA NOT NULL,       -- 12-byte nonce
    access_token_tag BYTEA NOT NULL,      -- 16-byte authentication tag
    refresh_token_ct BYTEA NOT NULL,
    refresh_token_iv BYTEA NOT NULL,
    refresh_token_tag BYTEA NOT NULL,
    token_type      TEXT NOT NULL DEFAULT 'Bearer',
    expires_at      TIMESTAMPTZ NOT NULL,
    scope           TEXT NOT NULL,
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);
```

### 5.2 Encryption in Transit

#### TLS Configuration

| Requirement | Specification |
|------------|---------------|
| **Minimum TLS version** | TLS 1.3 (TLS 1.2 accepted as fallback for compatibility, but 1.3 preferred) |
| **Cipher suites (TLS 1.3)** | `TLS_AES_256_GCM_SHA384`, `TLS_CHACHA20_POLY1305_SHA256`, `TLS_AES_128_GCM_SHA256` |
| **Certificate** | Let's Encrypt or AWS ACM. RSA 2048-bit minimum or ECDSA P-256. |
| **HSTS** | `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload` |
| **iOS App Transport Security (ATS)** | Default ATS settings (enforces TLS 1.2+ with forward secrecy). No ATS exceptions. |

#### Certificate Pinning

**Decision: Do NOT implement certificate pinning at launch.**

Rationale:
- Certificate pinning creates significant operational risk: if the certificate is rotated (or the pinning configuration is wrong), the app becomes completely unable to communicate with the backend until an app update is pushed and approved by Apple.
- Apple's ATS already validates the certificate chain against the system trust store.
- The threat model (man-in-the-middle on a consumer fitness app) does not justify the operational risk.
- **Future consideration:** If Tempo processes financial transactions or becomes a high-value target, implement pinning with a backup pin and a kill switch (remote config to disable pinning).

#### ATS Configuration

No `NSAppTransportSecurity` exceptions in `Info.plist`. Tempo communicates exclusively with HTTPS endpoints. The default ATS policy is sufficient:
- Requires TLS 1.2+
- Requires forward secrecy
- Requires certificates signed by a trusted CA

### 5.3 Key Management

| Key | Generation | Storage | Rotation | Access |
|-----|-----------|---------|----------|--------|
| JWT ES256 signing key | `openssl ecparam -genkey -name prime256v1` | AWS Secrets Manager | Every 90 days | Vapor backend at startup |
| Whoop token encryption key (AES-256) | `openssl rand -hex 32` | AWS Secrets Manager | Every 180 days (re-encrypt all tokens) | Vapor WhoopService |
| PostgreSQL volume encryption key | AWS KMS auto-generated | AWS KMS | Annual automatic rotation | AWS RDS service |
| Apple .p8 signing key | Generated by Apple Developer Console | AWS Secrets Manager | On compromise only | Vapor AuthController |
| APNs .p8 signing key | Generated by Apple Developer Console | AWS Secrets Manager | On compromise only | Vapor PushService |

**Key rotation procedure for JWT signing key:**

1. Generate new ES256 key pair with a new `kid`.
2. Add new key to the active key set in Secrets Manager.
3. Deploy backend update — new tokens are signed with new key. Old key is still accepted for verification.
4. After 31 days (max refresh token lifetime + 1 day), remove the old key.
5. Log the rotation event.

---

## 6. API Security

### 6.1 Authentication Enforcement

Every endpoint requires a valid JWT access token in the `Authorization` header, with these exceptions:

| Exception Endpoint | Reason |
|-------------------|--------|
| `GET /health` | Load balancer health check. Returns `{"status": "ok"}` only. |
| `POST /v1/auth/apple` | Initial authentication. |
| `POST /v1/auth/refresh` | Token refresh (refresh token is the credential). |
| `POST /v1/webhooks/whoop` | Whoop webhook (authenticated via HMAC signature, not JWT). |

**Middleware chain:**

```
Request → RateLimitMiddleware → JWTMiddleware → AuthorizationMiddleware → Controller
```

### 6.2 Authorization Model

Tempo uses a simple ownership-based authorization model.

| Resource | Owner Access | Friend Access | Public Access | Admin Access |
|----------|-------------|---------------|--------------|--------------|
| User profile (name, username) | Full CRUD | Read (display name, username, avatar) | None | Full CRUD |
| User email | Read | None | None | Read |
| Whoop tokens | Read/Refresh (automated) | None | None | None (not even admin) |
| Whoop health data (recovery, sleep, strain) | Full read | None | None | Anonymized aggregates only |
| Nutrition data | Full CRUD | None | None | None |
| Study sessions | Full CRUD | None | None | None |
| Non-negotiables | Full CRUD | None | None | None |
| Workout history | Full CRUD | None | None | None |
| Daily score | Read | Read (if friends) | None | Anonymized aggregates |
| XP / Level | Read | Read (if friends) | Leaderboard rank only | Read |
| Achievements | Read | Read (if friends) | None | Read |
| Challenge scores | Read | Read (if participant) | None | Read |
| Friend list | Read own list | None | None | Read |

**Critical authorization rules:**
- Every database query that returns user data MUST include a `WHERE user_id = $authenticated_user_id` clause (or equivalent scope).
- Friend-visible data requires a valid friendship record with `status = 'accepted'`.
- Blocked users see NO data about the blocking user, not even whether the account exists.

### 6.3 Input Validation

Every endpoint validates input before processing.

#### 6.3.1 Global Field Validation Rules

| Field Type | Validation Rules | Sanitization |
|-----------|-----------------|--------------|
| **Username** | 3-20 characters, alphanumeric + underscores only (`^[a-zA-Z0-9_]{3,20}$`), case-insensitive uniqueness, not in reserved list (admin, tempo, support, help, null, undefined, api, www, system, bot, official) | Trim whitespace. Lowercase for uniqueness check. |
| **Display name** | 1-50 characters, Unicode letters/numbers/spaces/hyphens only, no control characters (reject codepoints < 0x20 except space), no zero-width characters, no emoji modifiers | Trim whitespace. Normalize Unicode (NFC). Strip leading/trailing whitespace. |
| **UUID fields** | Valid UUID v4 format (`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`), case-insensitive | Lowercase before comparison. |
| **Date fields** | ISO 8601 format, not in the future (max +5 minutes for clock skew), not before 2024-01-01 | Parse to UTC. Reject ambiguous formats. |
| **Integer fields** | 64-bit signed integer, within per-field bounds (see below) | Reject floats, reject strings that look like numbers. |
| **Challenge names** | 1-100 characters, no control characters, no zero-width characters, profanity filter | Trim whitespace. Normalize Unicode (NFC). |
| **Challenge description** | 0-500 characters, optional, no control characters | Trim whitespace. |
| **Pagination cursor** | Base64-encoded, validated structure after decoding, max 256 characters encoded | Reject if decoding fails or structure is invalid. |
| **Nonce** | Exactly 64 hex characters (`^[0-9a-f]{64}$`) | Lowercase. |
| **Identity token** | Valid JWT structure (3 base64url segments separated by dots), max 4096 characters | No sanitization — reject if malformed. |
| **Refresh token** | Must start with `rt_`, 43-64 characters, alphanumeric + underscore only | No sanitization — reject if malformed. |
| **Search query** | 3-50 characters, alphanumeric + underscores only (matches username charset) | Trim whitespace. Escape for LIKE queries (Fluent handles this). |
| **Request body** | Must be valid JSON when `Content-Type: application/json`. Max depth: 5 levels. Max keys: 50. | Reject deeply nested or excessively large JSON structures. |

#### 6.3.2 Per-Endpoint Input Validation

| Endpoint | Method | Input Fields | Validation |
|----------|--------|-------------|------------|
| `/v1/auth/apple` | POST | `identity_token` (string, max 4096), `authorization_code` (string, max 512), `nonce` (string, exactly 64 hex), `first_name` (string, optional, max 50), `last_name` (string, optional, max 50) | All fields validated per type rules above. `first_name`/`last_name`: Unicode letters/spaces/hyphens only, no digits. |
| `/v1/auth/refresh` | POST | `refresh_token` (string, `rt_` prefix, 43-64 chars) | Exact format match. |
| `/v1/user/profile` | PATCH | `username` (string, 3-20, see rules), `display_name` (string, 1-50, see rules) | Both optional but at least one required. Rate limit: 5 profile updates per hour. |
| `/v1/user/data-export` | GET | None (user ID from JWT) | No input validation needed beyond JWT. |
| `/v1/user/account` | DELETE | `identity_token` (string, max 4096) — fresh Apple token for re-authentication | Must be a valid, non-expired Apple identity token for the authenticated user. |
| `/v1/sync` | POST | `daily_snapshot` (object), `xp_events` (array, max 50 items), `non_negotiable_completions` (array, max 20 items) | `daily_snapshot.score`: integer 0-100. `xp_events[].source`: enum from allowed list. `xp_events[].amount`: integer 0-400. Timestamps: valid ISO 8601, within last 48 hours. |
| `/v1/arena/friends/search` | GET | `q` (string, 3-50 chars, alphanumeric + underscore) | Min 3 chars to prevent enumeration. Rate limit: 10/min. |
| `/v1/arena/friends/request` | POST | `target_user_id` (UUID) | Must not be self. Must not be already friends. Must not be blocked. Max 20 pending outgoing. |
| `/v1/arena/friends/respond` | POST | `friendship_id` (UUID), `action` (enum: `accept`, `decline`) | Must be the target of the request. |
| `/v1/arena/challenges` | POST | `name` (string, 1-100), `description` (string, optional, 0-500), `metric` (enum: `study_minutes`, `xp`, `workouts`), `start_date` (ISO 8601, must be future), `end_date` (ISO 8601, must be after start, max 30 days duration), `invited_user_ids` (array of UUIDs, max 20) | All invited users must be accepted friends. Challenge duration: 1-30 days. |
| `/v1/arena/challenges/{id}/join` | POST | `challenge_id` (UUID in path) | User must be invited or challenge must be open. |
| `/v1/arena/report` | POST | `target_user_id` (UUID), `report_type` (enum: `inappropriate_username`, `cheating`, `harassment`, `spam`), `description` (string, optional, 0-1000) | Cannot report self. Max 10 reports per day per reporter (abuse prevention). |
| `/v1/whoop/sync` | POST | None (triggered by backend, not user input) | N/A — backend-to-Whoop API, no user input. |
| `/v1/webhooks/whoop` | POST | Raw body (validated by HMAC) | HMAC-SHA256 signature verification. Body max 100 KB. Event type must be in allowed list. |

#### 6.3.3 Vapor Implementation

```swift
struct CreateChallengeRequest: Content, Validatable {
    let name: String
    let description: String?
    let metric: ChallengeMetric
    let startDate: Date
    let endDate: Date
    let invitedUserIds: [UUID]

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(1...100) && !.empty)
        validations.add("description", as: String?.self, is: .nil || .count(...500), required: false)
        validations.add("metric", as: String.self, is: .in("study_minutes", "xp", "workouts"))
        validations.add("invitedUserIds", as: [UUID].self, is: .count(...20))
        // Custom: endDate must be after startDate, max 30 days
        // Custom: startDate must be in the future
        // Custom: name must not contain control characters
    }
}

// Global input sanitization middleware
struct InputSanitizationMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Reject requests with Content-Length > route-specific maximum
        // Reject non-UTF-8 string payloads
        // Reject JSON nesting depth > 5
        // Strip null bytes from string fields
        return try await next.respond(to: request)
    }
}
```

### 6.4 Request Size Limits

| Endpoint Category | Max Request Body | Rationale |
|------------------|-----------------|-----------|
| Authentication | 10 KB | Identity token + auth code + nonce |
| Data sync | 1 MB | Daily snapshot + workout data |
| Profile update | 100 KB (JSON) / 5 MB (avatar upload) | Username/display name / profile photo |
| Challenge creation | 10 KB | Challenge metadata |
| Webhook (Whoop) | 100 KB | Whoop event payload |
| Default | 100 KB | Safety limit |

**Vapor configuration:**

```swift
app.routes.defaultMaxBodySize = "100kb"
// Override per-route where needed
app.on(.POST, "v1", "sync", body: .collect(maxSize: "1mb")) { req in ... }
```

### 6.5 Content-Type Enforcement

- All API endpoints accept ONLY `application/json` (except avatar upload which accepts `multipart/form-data`).
- Requests with incorrect `Content-Type` receive `415 Unsupported Media Type`.
- Responses always include `Content-Type: application/json; charset=utf-8`.

### 6.6 Rate Limiting

Rate limits are enforced by `RateLimitMiddleware` using Redis as the backing store (sliding window algorithm).

**Unauthenticated endpoints** (rate limited by IP only — no user identity available):

| Category | Limit | Window | Scope | Response on Exceed |
|----------|-------|--------|-------|--------------------|
| **`POST /v1/auth/apple`** (authentication) | 10 requests | 1 minute | Per IP | `429` + `Retry-After` header. Log the IP hash. |
| **`POST /v1/auth/refresh`** (token refresh) | 20 requests | 1 minute | Per IP | `429`. If > 50/min from same IP, block IP for 15 minutes. |
| **`GET /health`** (health check) | 60 requests | 1 minute | Per IP | `429` (prevents abuse of the only unauthenticated GET). |
| **`POST /v1/webhooks/whoop`** (webhook) | 100 requests | 1 minute | Per IP (Whoop's egress IPs) | `429`. Allowlist Whoop's IP ranges if available. |

**Authenticated endpoints** (rate limited by user ID AND per-IP as a secondary):

| Category | Per-User Limit | Per-IP Limit | Window | Response on Exceed |
|----------|---------------|-------------|--------|--------------------|
| **Whoop proxy** | 60 requests | 300 requests | 1 minute | `429` (protects Whoop's rate limit too) |
| **NutriTrack proxy** | 30 requests | 150 requests | 1 minute | `429` |
| **Arena (leaderboard, friends)** | 120 requests | 600 requests | 1 minute | `429` |
| **Friend search** | 10 requests | 50 requests | 1 minute | `429` (enumeration protection) |
| **Data sync** | 30 requests | 150 requests | 1 minute | `429` |
| **AI insights** | 5 requests | 25 requests | 1 hour | `429` (cost control) |
| **Profile updates** | 5 requests | 25 requests | 1 hour | `429` |
| **Reports** | 10 requests | 30 requests | 1 day | `429` (report spam prevention) |
| **Global (authenticated)** | 500 requests | 1000 requests | 1 minute | `429` |

**Why both per-user AND per-IP?** Per-user prevents a single account from abusing rate limits. Per-IP prevents an attacker from creating many accounts behind one IP to multiply their effective rate. The per-IP limit for authenticated endpoints is set higher (assumes shared NAT/VPN scenarios) but still caps total throughput from any single source.

**Response headers on every request:**

```
X-RateLimit-Limit: 120
X-RateLimit-Remaining: 85
X-RateLimit-Reset: 1711235467
```

### 6.7 CORS Policy

CORS is minimally configured since Tempo is an iOS app, not a web app:

```swift
let corsConfig = CORSMiddleware.Configuration(
    allowedOrigin: .none,  // No browser origins allowed
    allowedMethods: [],
    allowedHeaders: []
)
```

If a web dashboard is added later, restrict CORS to the specific dashboard domain:

```swift
allowedOrigin: .custom("https://dashboard.tempo.app")
allowedMethods: [.GET, .POST, .PUT, .DELETE, .OPTIONS]
allowedHeaders: [.authorization, .contentType, .accept, .xRequestedWith]
```

### 6.8 Security Headers

All responses include:

```
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Content-Security-Policy: default-src 'none'
X-Request-Id: req_<unique_id>
Cache-Control: no-store
Referrer-Policy: no-referrer
```

### 6.9 SQL Injection Prevention

Tempo uses Fluent ORM (Vapor's built-in ORM) which parameterizes all queries by default. **Raw SQL is prohibited except where explicitly justified below.**

Rules:
- All database queries MUST use Fluent's query builder or model methods. Fluent uses parameterized prepared statements under the hood — user input is never interpolated into SQL strings.
- Any raw SQL query MUST be reviewed and approved in code review with explicit justification. The PR must include the tag `[RAW-SQL]` in the title.
- **Known raw SQL exceptions (exhaustive list):**
  1. `REFRESH MATERIALIZED VIEW weekly_leaderboard` — executed by a scheduled Queues job, no user input, no parameters.
  2. `REFRESH MATERIALIZED VIEW challenge_rankings` — same as above.
- Any new raw SQL addition requires: (a) security review, (b) proof that Fluent cannot express the query, (c) parameterization of ALL dynamic values using `\(bind: value)`.
- **CI enforcement:** A linting rule scans for `.raw(` calls in the codebase. Any new occurrence triggers a mandatory security review label on the PR.
- **Fluent `.filter(.custom(...))` usage:** Treat `.custom()` filters the same as raw SQL — they bypass Fluent's parameterization. Require review.

**Verification test:**
```swift
// Integration test: verify parameterization
func testSearchQueryIsParameterized() async throws {
    // This should NOT return all users — if it does, SQL injection is possible
    let response = try await app.sendRequest(.GET, "/v1/arena/friends/search?q=' OR '1'='1")
    XCTAssertEqual(response.status, .badRequest) // Rejected by input validation before reaching DB
}
```

### 6.10 Request/Response Logging

#### What IS Logged

| Field | Example |
|-------|---------|
| Request ID | `req_abc123def456` |
| Timestamp | `2026-03-24T10:30:00.123Z` |
| HTTP method + path | `POST /v1/auth/apple` |
| Response status code | `200`, `401`, `429` |
| Response time (ms) | `45` |
| User ID (if authenticated) | `user_uuid` |
| IP address (hashed) | `sha256(ip)` — for rate limiting correlation only |
| User-Agent | `Tempo/1.2.3 iOS/17.4` |
| Rate limit status | `120/120 remaining` |
| Error codes (on failure) | `1005: Apple token verification failed` |

#### What is NEVER Logged

| Field | Reason |
|-------|--------|
| Request/response bodies | May contain health data, tokens, PII |
| Authorization header value | Contains JWT token |
| Refresh tokens | Credential |
| Whoop OAuth tokens | Credential |
| NutriTrack PIN | Credential |
| Claude API key | Credential |
| Health data values (HR, HRV, sleep, etc.) | HIPAA/GDPR sensitive |
| Identity token from Apple | Contains PII |
| IP address (plaintext) | PII — only store hashed for abuse detection |

### 6.11 Dependency Vulnerability Scanning

| Tool | Scope | Frequency | Action on Finding |
|------|-------|-----------|-------------------|
| `swift package audit` (when available) / Dependabot | Swift backend dependencies | On every PR + weekly automated scan | Critical/High: block merge. Medium: fix within 7 days. Low: fix within 30 days. |
| Xcode dependency analysis | iOS Swift Package Manager dependencies | On every build | Same severity-based response. |
| GitHub Dependabot alerts | All repositories | Continuous | Auto-create PRs for security patches. |
| OWASP Dependency-Check | Transitive dependencies | Monthly | Report reviewed in security standup. |

---

## 7. Third-Party Integration Security

### 7.1 Whoop OAuth Security

#### Client Secret Management

- **Whoop client secret:** Stored as an environment variable on the backend server. NEVER in source code, iOS app bundle, or Git history.
- **Production storage:** AWS Secrets Manager or equivalent. Injected into the Vapor process at deployment time.
- **Access:** Only `WhoopService` reads the client secret. No other service or controller has access.

#### Token Encryption at Rest

- Whoop access and refresh tokens are encrypted with AES-256-GCM before storage (see Section 5.1).
- The encryption key is in AWS Secrets Manager, separate from the database.
- Even if the database is dumped, tokens are unreadable without the encryption key.

#### Token Refresh Flow Security

```
1. WhoopService detects access token is expired (or receives 401 from Whoop API).
2. Decrypt the stored refresh token from PostgreSQL.
3. POST https://api.prod.whoop.com/oauth/oauth2/token
   - grant_type=refresh_token
   - refresh_token=<decrypted_refresh_token>
   - client_id=<whoop_client_id>
   - client_secret=<whoop_client_secret>
4. Receive new access_token + refresh_token.
5. Encrypt both new tokens.
6. Update PostgreSQL within a transaction (atomic swap).
7. If refresh fails with invalid_grant: mark Whoop connection as disconnected.
   - Notify user via push: "Your Whoop connection needs to be refreshed. Tap to reconnect."
   - Do NOT automatically retry more than 3 times.
```

#### Handling Whoop API Downtime/Errors

| Scenario | Response |
|----------|----------|
| Whoop API returns 5xx | Retry with exponential backoff: 1s, 2s, 4s, 8s, 16s. Max 5 retries. Log the incident. Serve cached data to iOS client. |
| Whoop API returns 429 (rate limited) | Respect `Retry-After` header. Queue pending requests. Do not retry immediately. |
| Whoop API returns 401 (token expired) | Trigger token refresh flow. If refresh fails, mark disconnected. |
| Whoop API unreachable (network error) | Same as 5xx. Circuit breaker after 10 consecutive failures in 5 minutes — stop all Whoop requests for 5 minutes, then probe. |
| Whoop token revoked by user | Mark disconnected. Clean up stored tokens. Notify user to reconnect. |

#### Webhook HMAC Verification

Whoop sends webhook events signed with an HMAC signature.

```swift
// Vapor webhook handler
func handleWhoopWebhook(req: Request) async throws -> HTTPStatus {
    // 1. Extract signature from header
    guard let signature = req.headers.first(name: "X-Whoop-Signature") else {
        throw Abort(.unauthorized, reason: "Missing webhook signature")
    }

    // 2. Read raw body
    guard let body = req.body.data else {
        throw Abort(.badRequest, reason: "Empty body")
    }

    // 3. Compute expected HMAC-SHA256
    let secret = Environment.get("WHOOP_WEBHOOK_SECRET")!
    let key = SymmetricKey(data: Data(secret.utf8))
    let expectedMAC = HMAC<SHA256>.authenticationCode(
        for: body,
        using: key
    )

    // 4. Constant-time comparison — use CryptoKit's isValidAuthenticationCode,
    //    NOT string ==. String == may short-circuit on first differing byte,
    //    leaking timing information about the expected signature.
    guard let signatureData = Data(hexString: signature) else {
        throw Abort(.unauthorized, reason: "Invalid webhook signature format")
    }
    let isValid = HMAC<SHA256>.isValidAuthenticationCode(
        signatureData,
        authenticating: body,
        using: key
    )
    guard isValid else {
        req.logger.warning("Whoop webhook signature mismatch",
                          metadata: ["ip": "\(req.peerAddress?.description ?? "unknown")"])
        throw Abort(.unauthorized, reason: "Invalid webhook signature")
    }

    // 5. Process the webhook
    // ... parse body and handle event
    return .ok
}
```

**Critical:** Use constant-time comparison for HMAC validation to prevent timing attacks. Swift's `==` on strings is NOT guaranteed to be constant-time — it may short-circuit on the first differing byte. Always use `HMAC<SHA256>.isValidAuthenticationCode()` from CryptoKit, which performs constant-time comparison internally.

### 7.2 NutriTrack Integration Security

#### PIN Transmission Security

- NutriTrack uses a 6-digit PIN for authentication (single-user app).
- The PIN is transmitted from the Tempo backend to NutriTrack's Flask server ONLY over HTTPS.
- The PIN is stored as an environment variable on the Tempo backend. It is NOT stored in PostgreSQL.
- The PIN is transmitted as part of a session cookie flow — the backend authenticates once and maintains a session.

#### Credential Storage on Backend

```
NUTRITRACK_BASE_URL=https://nutritrack.example.com
NUTRITRACK_PIN=123456
```

- Stored in environment variable, loaded at boot.
- In production: stored in AWS Secrets Manager, injected by deployment pipeline.
- The PIN is sent to NutriTrack only during session initialization.
- Session cookies are stored in-memory on the Vapor backend (not persisted to disk).

#### If NutriTrack Server Is Compromised

Threat model: an attacker gains access to the NutriTrack Flask server.

| Impact | Mitigation |
|--------|-----------|
| Attacker can read nutrition data | Nutrition data is NOT health-regulated (not HealthKit). Impact is moderate (Level 3 data). |
| Attacker can modify nutrition data | Tempo caches NutriTrack data locally. Anomaly detection: if macro values change by >50% between syncs, flag for review. |
| Attacker can use NutriTrack to pivot to Tempo backend | NutriTrack has NO credentials to Tempo backend. The connection is one-way (Tempo calls NutriTrack, never the reverse). |
| Attacker can see the Tempo backend's IP | Use a proxy/VPN for NutriTrack requests to avoid exposing the backend's direct IP. |
| Attacker can return malicious data | All NutriTrack responses are validated before use. Integer fields clamped to reasonable ranges (calories: 0-10000, protein: 0-500g). HTML/script injection impossible because responses are consumed as JSON, never rendered as HTML. |

**Incident response:** If NutriTrack compromise is detected, immediately:
1. Rotate the NutriTrack PIN.
2. Invalidate the session cookie.
3. Disable the NutriTrack proxy until the issue is resolved.
4. Notify the user that nutrition sync is temporarily unavailable.

### 7.3 Claude API Security

#### What User Data Is Sent to Claude

**Principle: minimize data sent to Claude. Anonymize everything.**

| Data Sent | Data NOT Sent |
|-----------|--------------|
| Anonymized daily scores (e.g., "recovery: 72%") | User's name, email, Apple ID |
| Aggregated weekly averages (e.g., "avg study: 2.3h/day") | Raw HealthKit samples |
| Streak counts (e.g., "current streak: 12 days") | Whoop tokens or any credentials |
| Workout completion flags (e.g., "trained 5/7 days") | IP address or device identifiers |
| Macro compliance % (e.g., "protein target hit 6/7 days") | Specific food items or meal details |
| Non-negotiable completion rates | Usernames or social graph |

#### Data Anonymization Before Sending

```swift
// Backend: Construct Claude prompt with anonymized data
func buildWeeklyInsightPrompt(weekData: WeeklyAggregates) -> String {
    // NO PII in the prompt. Use generic identifiers only.
    return """
    Analyze this weekly data for a fitness app user and provide actionable insights:

    Recovery scores: \(weekData.recoveryScores) (0-100 scale)
    Sleep hours: \(weekData.sleepHours)
    Study minutes per day: \(weekData.studyMinutes)
    Workout completion: \(weekData.workoutsCompleted)/\(weekData.workoutsPlanned)
    Nutrition compliance: \(weekData.nutritionCompliancePercent)%
    Current streak: \(weekData.streakDays) days

    Provide 3 specific, actionable insights.
    """
}
```

#### Claude API Key Storage and Rotation

- **Storage:** AWS Secrets Manager. Injected as environment variable `ANTHROPIC_API_KEY`.
- **Rotation:** Every 90 days. Generate new key in Anthropic Console, update Secrets Manager, deploy.
- **Access:** Only `AIService` reads the key. No other service or controller has access.
- **Backend-only:** The Claude API key NEVER touches the iOS app. All Claude requests are made from the Vapor backend.

#### Cost Controls to Prevent Abuse

| Control | Implementation |
|---------|---------------|
| **Per-user rate limit** | Max 5 AI insight requests per hour per user. |
| **Token budget per request** | Max 2000 input tokens + 1000 output tokens per request. |
| **Monthly spending cap** | Set in Anthropic Console. Alert at 80% of budget. Hard stop at 100%. |
| **Request validation** | Only the backend's `AIService` can make Claude requests. No user-supplied prompts — all prompts are templates filled with anonymized data. |
| **No prompt injection vector** | User data is inserted into templates as data values, not as part of the instruction. Numeric values only (no free-text user input sent to Claude). |

---

## 8. GDPR Compliance

### 8.1 Legal Basis for Processing

| Data Category | Legal Basis | Justification |
|---------------|-------------|---------------|
| Account data (email, username, Apple ID) | **Contract (Art. 6(1)(b))** | Necessary to provide the service |
| Health data (Whoop biometrics, HealthKit data) | **Explicit consent (Art. 9(2)(a))** | Health data requires explicit consent under GDPR. Collected during onboarding with clear explanation. |
| Nutrition data | **Explicit consent (Art. 9(2)(a))** | Health-adjacent data, treated as health data for safety |
| Social data (friends, XP, leaderboard) | **Contract (Art. 6(1)(b))** | Necessary for Arena features the user opts into |
| Analytics / crash data | **Legitimate interest (Art. 6(1)(f))** | Improving app stability and performance. Anonymized. |
| Push notification tokens | **Consent (Art. 6(1)(a))** | User explicitly grants notification permission |

### 8.2 Right to Access (Art. 15)

**Endpoint:** `GET /v1/user/data-export`

**Implementation:**
1. User requests data export from Settings > Privacy > Export My Data.
2. iOS sends `GET /v1/user/data-export` with JWT.
3. Backend compiles ALL user data into a JSON file:
   - Account info (username, display name, email, creation date)
   - XP history (all XP events with dates and sources)
   - Friend list (usernames of accepted friends)
   - Challenge history (participation and scores)
   - Achievement list
   - Whoop data cache (recovery scores, sleep data — what the backend has)
   - Nutrition sync history (cached from NutriTrack)
   - Daily scores
4. Backend returns a signed download URL (expires in 1 hour).
5. iOS downloads the JSON and presents it via `UIActivityViewController` (share sheet).

**Timeline:** Export ready within 5 minutes for typical accounts. Maximum 72 hours for large datasets (background job with push notification on completion).

**Note:** HealthKit data is NOT included in the export because it is not stored on the backend. Users can export HealthKit data directly from the Apple Health app.

### 8.3 Right to Deletion (Art. 17)

**Endpoint:** `DELETE /v1/user/account`

**Implementation:**
1. User requests account deletion from Settings > Account > Delete Account.
2. iOS shows a confirmation dialog: "This will permanently delete your account and all associated data. This cannot be undone. Your HealthKit data will not be affected."
3. User must re-authenticate with Sign in with Apple to confirm.
4. iOS sends `DELETE /v1/user/account` with JWT + fresh Apple identity token.
5. Backend initiates deletion:

**Immediate actions (within 1 minute):**
- Revoke all refresh tokens (logout all devices)
- Revoke Whoop OAuth token (call Whoop's revocation endpoint)
- Delete APNs device tokens
- Mark account as `pending_deletion`

**Deferred actions (within 30 days):**
- Delete user record and all associated data:
  - `users` row
  - `xp_events` rows
  - `friendships` rows (both directions)
  - `challenge_participants` rows
  - `achievements` rows
  - `whoop_tokens` row
  - `refresh_tokens` rows
  - Any cached Whoop/NutriTrack data
- Remove from all leaderboard materialized views
- Delete profile photo from object storage
- Purge from database backups within 90 days (backup retention policy)

**iOS client actions:**
- Clear iOS Keychain entries
- Delete SwiftData store
- Clear UserDefaults
- Show "Account deleted" confirmation
- Return to onboarding screen

**Cooling-off period:** 7 days. During this period:
- Account is deactivated (cannot log in)
- Data is retained but inaccessible
- User can contact support to cancel deletion
- After 7 days, deletion is irreversible

### 8.4 Right to Rectification (Art. 16)

Users can correct their personal data:
- **Username:** Settings > Profile > Edit Username
- **Display name:** Settings > Profile > Edit Display Name
- **Profile photo:** Settings > Profile > Change Photo
- **Whoop connection:** Disconnect and reconnect to refresh data
- **NutriTrack connection:** Disconnect and reconnect

**Endpoint:** `PATCH /v1/user/profile`

Health data cannot be "corrected" through Tempo — it comes from Whoop/HealthKit and must be corrected at the source.

### 8.5 Data Processing Agreements (DPAs)

Tempo must have DPAs in place with all sub-processors:

| Sub-Processor | Data Processed | DPA Required | Status |
|---------------|---------------|-------------|--------|
| **Anthropic (Claude API)** | Anonymized aggregate health scores, no PII | Yes | [TO BE SIGNED] |
| **Whoop** | User's Whoop health data (accessed via user's OAuth consent) | Whoop's existing ToS covers user-authorized access | Review Whoop developer terms |
| **AWS (hosting)** | All backend data | Yes (AWS DPA available at aws.amazon.com/compliance/gdpr-center) | [TO BE SIGNED] |
| **Apple (Sign in with Apple, APNs, HealthKit)** | Auth tokens, push tokens, health data | Apple's developer agreement covers this | Covered by Apple Developer Agreement |
| **Let's Encrypt (TLS certificates)** | Domain name only | Not required (no user data processed) | N/A |

### 8.6 Consent Management

#### Where Consent Is Collected

| Consent Point | When | What | Revocable? | How to Revoke |
|---------------|------|------|-----------|---------------|
| **Terms of Service + Privacy Policy** | Account creation (onboarding) | Legal agreement for service use | Yes (delete account) | Settings > Account > Delete Account |
| **HealthKit access** | Onboarding step 2 | Read/write specific health data types | Yes | iOS Settings > Health > Tempo |
| **Whoop connection** | Onboarding step 3 (optional) | OAuth consent for Whoop data access | Yes | Settings > Integrations > Disconnect Whoop |
| **NutriTrack connection** | Onboarding step 4 (optional) | Access to NutriTrack nutrition data | Yes | Settings > Integrations > Disconnect NutriTrack |
| **Calendar access** | Onboarding step 5 (optional) | Read calendar events | Yes | iOS Settings > Tempo > Calendars |
| **Push notifications** | Onboarding step 6 | Send notifications | Yes | iOS Settings > Tempo > Notifications |
| **Arena participation** | First use of Arena module | Share scores with friends | Yes | Settings > Arena > Leave Arena |

**Consent records:** The backend stores a timestamped consent log:

```sql
CREATE TABLE consent_records (
    id          UUID PRIMARY KEY,
    user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
    consent_type TEXT NOT NULL,  -- 'tos', 'privacy', 'healthkit', 'whoop', 'nutritrack', 'calendar', 'notifications', 'arena'
    granted     BOOLEAN NOT NULL,
    granted_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ,
    ip_hash     TEXT,           -- SHA-256 of IP for audit trail
    app_version TEXT NOT NULL
);
```

### 8.7 Data Breach Notification (Art. 33, Art. 34)

#### GDPR Applicability for Tempo

**Tempo is developed by Nicola Debbia (Italy).** As an Italian national, the developer is within GDPR jurisdiction regardless of where the servers are hosted. Additionally, if the app is available on the EU App Store (which it will be), GDPR applies to all EU/EEA user data under Article 3(2) — the app offers services to data subjects in the EU.

**Conclusion: GDPR fully applies.** The 72-hour breach notification obligation is binding.

**Lead supervisory authority:** Garante per la Protezione dei Dati Personali (Italian DPA), since the developer is established in Italy.

**Timeline:**
- **Discovery → Assessment:** Within 1 hour. Determine scope and severity.
- **Assessment → Authority notification:** Within 72 hours of discovery. Notify the Garante per la Protezione dei Dati Personali. If users in other EU member states are affected, notify those DPAs as well (or rely on the lead authority mechanism under Art. 56).
- **Authority notification → User notification:** "Without undue delay" if the breach is likely to result in a high risk to individuals (Art. 34). For health data, the threshold is LOW — any breach involving health data is presumed high-risk.

**Notification content (to authorities):**
1. Nature of the breach (what data, how many users)
2. Contact details of the data protection officer / responsible person
3. Likely consequences
4. Measures taken or proposed to address the breach
5. Categories of data subjects affected and approximate number

**Notification content (to users):**
1. Plain-language description of the breach
2. What data was affected
3. What we are doing about it
4. What the user should do (e.g., reconnect Whoop, monitor accounts)
5. Contact information for questions

See Section 11 (Incident Response) for detailed procedures.

---

## 9. Social Features Security

### 9.1 Username Enumeration Prevention

**Threat:** An attacker could use the friend search endpoint to determine whether a specific person uses Tempo.

**Mitigations:**
- Username search (`GET /v1/arena/friends/search?q=username`) requires authentication (no anonymous searches).
- Search requires a minimum of 3 characters.
- Rate limited: 10 searches per minute per user.
- Response is identical whether 0 results or no results — `{"data": [], "pagination": ...}`.
- The "User not found" response for friend requests is identical in timing and structure to "Request sent" — `{"ok": true, "message": "If the user exists, your friend request has been sent."}`.
- No timing side-channels: both paths execute the same database query (search for user, then either insert friendship or no-op).

### 9.2 Friend Request Spam Prevention

| Control | Implementation |
|---------|---------------|
| **Pending request limit** | Max 20 outgoing pending friend requests per user. After 20, must wait for acceptance/decline. |
| **Rate limit** | Max 10 friend requests per hour. |
| **Cooldown after decline** | If user B declines user A's request, user A cannot send another request to user B for 30 days. |
| **Block terminates** | Blocking a user automatically declines any pending requests and prevents future requests. |
| **Report on request** | Friend request UI includes a "Report" option. |

### 9.3 Blocking

When user A blocks user B:

| Feature | Behavior |
|---------|----------|
| **Friendship** | Immediately dissolved (both directions). |
| **Friend requests** | All pending requests between A and B are cancelled. B cannot send new requests to A. |
| **Search** | B does not appear in A's search results. A does not appear in B's search results. |
| **Leaderboard** | B is hidden from A's leaderboard view. A is hidden from B's leaderboard view. |
| **Challenges** | If in a shared challenge, they cannot see each other's scores. If A created a challenge and B is a participant (or vice versa), the blocked user is removed from the challenge. |
| **Profile** | B cannot view A's profile. A cannot view B's profile. API returns `404 Not Found` (not `403 Forbidden` — to avoid confirming the account exists). |
| **Notifications** | No notifications from B to A or A to B (friend activity, challenge invites, etc.). |
| **Unblocking** | A can unblock B. This does NOT restore the friendship — B must send a new friend request. |

**Database implementation:**

```sql
CREATE TABLE blocks (
    blocker_id  UUID REFERENCES users(id) ON DELETE CASCADE,
    blocked_id  UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (blocker_id, blocked_id)
);

-- All social queries must check: WHERE NOT EXISTS (SELECT 1 FROM blocks WHERE ...)
```

### 9.4 Report System

#### Report Types

| Report Type | Description | Auto-Action |
|------------|-------------|-------------|
| `inappropriate_username` | Offensive username or display name | Flag for review. If 3+ reports, auto-hide username until reviewed. |
| `cheating` | Suspected XP manipulation or fake data | Flag for review. Log the reporter and reportee's recent XP events. |
| `harassment` | Abusive behavior via challenge names or social features | Flag for review. If 3+ reports from different users, temporarily restrict social features. |
| `spam` | Mass friend requests or spam challenge invites | Auto-restrict: block friend requests for 24h if 5+ reports. |

#### Handling Procedure

1. Report submitted via `POST /v1/arena/report` with report type, target user ID, and optional description.
2. Stored in `reports` table with reporter ID, timestamp, and status.
3. Reporter receives confirmation: "Thank you for your report. We'll review it."
4. Auto-actions triggered if threshold met (see above).
5. Manual review within 48 hours for all reports.
6. Outcomes: no action, warning issued, temporary restriction, permanent ban.
7. Reporter is NOT notified of the outcome (to prevent weaponization of the report system).

### 9.5 Challenge Fairness / Anti-Cheat

| Cheat Vector | Detection | Response |
|-------------|-----------|----------|
| **Fabricated workout XP** | Cross-reference with HealthKit workout data (if available) and Whoop strain. Workouts without any biometric confirmation are flagged. | Flag for review. XP capped at manual workout limits. |
| **Study time inflation** | Focus timer must be active (app in foreground) to count. Background timer limited to 25-minute Pomodoro blocks. Max 16 hours/day. | Auto-cap at reasonable maximum. |
| **Multiple account abuse** | Same Apple ID can only have one account. Device fingerprint as secondary check. | Prevent creation. |
| **API manipulation** | All XP events are computed server-side from raw data. iOS client NEVER sends XP amounts — only raw events (e.g., "workout completed"). | Server rejects pre-computed XP. |

### 9.6 Data Visibility Matrix

|  | Self | Accepted Friend | Challenge Participant (not friend) | Blocked User | Unauthenticated |
|--|------|-----------------|-----------------------------------|-------------|-----------------|
| Username | Yes | Yes | Yes (in challenge context) | NO | NO |
| Display name | Yes | Yes | Yes (in challenge context) | NO | NO |
| Profile photo | Yes | Yes | Yes (in challenge context) | NO | NO |
| XP / Level | Yes | Yes | Rank only | NO | NO |
| Daily score | Yes | Yes | NO | NO | NO |
| Streak count | Yes | Yes | NO | NO | NO |
| Achievement badges | Yes | Yes | NO | NO | NO |
| Workout details | Yes | NO | NO | NO | NO |
| Nutrition data | Yes | NO | NO | NO | NO |
| Study sessions | Yes | NO | NO | NO | NO |
| Non-negotiables | Yes | NO | NO | NO | NO |
| Recovery data | Yes | NO | NO | NO | NO |
| Sleep data | Yes | NO | NO | NO | NO |
| Heart rate / HRV | Yes | NO | NO | NO | NO |
| Email address | Yes | NO | NO | NO | NO |
| Friend list | Yes | Mutual friends only | NO | NO | NO |

### 9.7 Group Privacy

If group challenges are implemented:
- Leaving a challenge immediately removes access to all challenge data.
- Challenge creator can remove participants.
- Removed participants lose access to the challenge leaderboard and other participants' scores.
- Challenge data is retained for remaining participants; the removed user's scores remain visible to others (but the removed user cannot see the challenge).
- Challenge-specific data is deleted 30 days after the challenge ends.

---

## 10. Push Notification Security

### 10.1 APNs Key Management

- **APNs authentication:** Token-based authentication (`.p8` key), NOT certificate-based.
- **Key storage:** AWS Secrets Manager. Injected as environment variable `APNS_KEY_PATH` pointing to a mounted secret file.
- **Key ID and Team ID:** Environment variables `APNS_KEY_ID` and `APNS_TEAM_ID`.
- **Key rotation:** APNs keys do not expire. Rotate only on compromise. Max 2 active keys per team.

### 10.2 Device Token Storage and Cleanup

```sql
CREATE TABLE device_tokens (
    id          UUID PRIMARY KEY,
    user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
    token       TEXT NOT NULL UNIQUE,
    platform    TEXT NOT NULL DEFAULT 'ios',
    app_version TEXT,
    last_used   TIMESTAMPTZ DEFAULT NOW(),
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

**Cleanup rules:**
- When APNs returns status `410 Gone` (device token is no longer active), delete the token immediately.
- When APNs returns status `400 BadDeviceToken`, delete the token.
- Tokens not updated in 90 days are deleted by a nightly cleanup job.
- On user account deletion, all device tokens are deleted immediately.
- On user sign-out from a specific device, only that device's token is deleted.

### 10.3 Notification Content Security

**Rule: NEVER include sensitive data in the push notification payload.**

Push notifications are visible on the lock screen, notification center, and potentially on paired Apple Watch — all without authentication.

| Notification Type | Payload Content | What is NOT Included |
|------------------|----------------|---------------------|
| Accountability reminder | "You have 2 tasks remaining today." | Specific task names, health data |
| Workout reminder | "Time to train. Your body is ready." | Recovery score, HRV values |
| Meal reminder | "Don't forget to log your next meal." | Macro targets, calorie numbers |
| Friend request | "You have a new friend request." | Requester's username (privacy) |
| Challenge update | "Check the leaderboard — you've moved up!" | Specific XP amounts, rank numbers |
| Whoop sync | "Your recovery data is ready." | Recovery score, sleep hours |
| Weekly report | "Your weekly insights are ready." | Any health data |
| Study reminder | "Study block starts in 15 minutes." | Subject, exam details |

**Silent push for data sync:**
- `content-available: 1` in the push payload triggers a background app refresh.
- No user-visible notification. Used to trigger Whoop data sync, NutriTrack sync.
- Maximum 2-3 silent pushes per hour (iOS throttles more aggressively).

### 10.4 Notification Actions

For notification actions that involve data (e.g., "Start Workout" from a notification):
- The action opens the app to the relevant screen.
- If biometric lock is enabled, the user must authenticate before seeing any data.
- No sensitive action (account changes, data export, etc.) is triggered directly from a notification action.

---

## 11. Incident Response Plan

### 11.1 Incident Classification

| Severity | Description | Examples | Response Time | Resolution Target |
|----------|-------------|----------|--------------|-------------------|
| **P1 — Critical** | Active data breach, complete service outage, or security vulnerability being actively exploited | Database breach, Whoop token leak, authentication bypass, backend down | 15 minutes | 4 hours |
| **P2 — High** | Significant security vulnerability discovered (not yet exploited), partial service degradation, data integrity issue | SQL injection found in code review, Whoop API returning incorrect data for wrong users, token refresh broken | 1 hour | 24 hours |
| **P3 — Medium** | Minor security issue, single-user data exposure, non-critical feature broken | Rate limiting bypass, one user can see another's XP history, push notifications failing | 4 hours | 72 hours |
| **P4 — Low** | Security hardening opportunity, minor policy violation, informational finding | Dependency with known low-severity CVE, logging too much data, missing security header | 24 hours | 2 weeks |

### 11.2 Response Procedures

#### Data Breach Response

```
DISCOVERY
  │
  ├─ Confirm the breach (not a false alarm)
  │   - Check logs for unauthorized access patterns
  │   - Identify affected data and users
  │   - Determine attack vector
  │
  ├─ CONTAIN (within 1 hour)
  │   - Revoke compromised credentials (API keys, tokens)
  │   - Block the attack vector (IP ban, endpoint disable)
  │   - Rotate all secrets if scope is unclear
  │   - Take affected systems offline if necessary
  │
  ├─ ASSESS (within 4 hours)
  │   - Determine: what data, how many users, what timeframe
  │   - Classify the breach severity
  │   - Determine GDPR notification requirements
  │
  ├─ NOTIFY (within 72 hours of discovery)
  │   - Supervisory authority (if GDPR applies)
  │   - Affected users (if high risk to individuals)
  │   - Apple (if App Store listing is affected)
  │   - Whoop (if Whoop tokens were compromised)
  │   - Anthropic (if Claude API key was compromised)
  │
  ├─ REMEDIATE
  │   - Patch the vulnerability
  │   - Restore from clean backups if data was corrupted
  │   - Force password reset / re-authentication for affected users
  │   - Re-encrypt tokens with new keys if encryption keys were compromised
  │
  └─ POST-INCIDENT REVIEW (within 7 days)
      - Timeline of events
      - Root cause analysis
      - What worked, what didn't
      - Action items to prevent recurrence
      - Update this security specification
```

#### API Key Compromise

| Compromised Key | Immediate Action | Recovery |
|----------------|-----------------|----------|
| **JWT signing key** | Rotate key immediately. All users forced to re-authenticate. | Deploy new key. Old tokens become invalid instantly. |
| **Whoop client secret** | Rotate in Whoop developer console. Update backend env. | All existing Whoop tokens remain valid (they don't depend on the client secret for API calls). |
| **Claude API key** | Revoke in Anthropic Console immediately. | Generate new key. Update backend env. AI features down until deployed. |
| **NutriTrack PIN** | Change PIN in NutriTrack app. Update backend env. | Session invalidated. Re-authenticate with new PIN. |
| **APNs key** | Revoke in Apple Developer Console. Generate new key. | Push notifications down until new key deployed. |
| **Database credentials** | Rotate PostgreSQL password. Update connection string. | Brief backend downtime during rotation. |

#### Detailed Playbook: Whoop Client Secret Compromised

A leaked Whoop client secret allows an attacker to exchange authorization codes and refresh tokens on behalf of Tempo. This is a P1 incident.

```
MINUTE 0: Discovery
  - Source: security researcher report, credential scanner alert, or internal discovery

MINUTE 0-15: Contain
  1. Log in to Whoop Developer Portal (https://developer.whoop.com)
  2. Rotate the client secret. This generates a new secret and invalidates the old one.
  3. Update AWS Secrets Manager with the new client secret.
  4. Deploy the backend with the new secret. Use rolling deployment — zero downtime.

MINUTE 15-30: Assess Impact
  5. Check Whoop developer dashboard for unusual API activity:
     - Unexpected spikes in token exchange requests
     - Token exchanges for authorization codes Tempo did not generate
     - Requests from IP addresses outside Tempo's backend IPs
  6. If suspicious activity found: the attacker may have obtained user Whoop tokens.
     - Enumerate which users' tokens may be compromised (Whoop may provide logs)
     - For affected users: force-refresh their Whoop tokens using the new client secret
     - Notify affected users: "Your Whoop connection has been refreshed for security."

MINUTE 30-60: Verify
  7. Verify Whoop data sync is working with the new secret.
  8. Monitor error rates for WhoopService for 1 hour.

POST-INCIDENT:
  9. Determine HOW the secret leaked (code commit, log file, employee device, etc.)
  10. Remediate the leak source.
  11. Contact Whoop security team (security@whoop.com) to report the incident.
  12. If user Whoop data was accessed by an attacker, this is a GDPR-notifiable breach
      (health data). Trigger the 72-hour notification timeline.
```

#### Detailed Playbook: Anthropic API Key Compromised

A leaked Anthropic API key allows an attacker to make Claude API calls billed to Tempo's account. This is a P2 incident (no user data exposure — the key only grants API access, and Tempo's prompts contain only anonymized data).

```
MINUTE 0: Discovery
  - Source: Anthropic billing alert, unexpected usage spike, credential scanner, or report

MINUTE 0-5: Contain
  1. Log in to Anthropic Console (https://console.anthropic.com)
  2. Revoke the compromised API key immediately.
  3. Generate a new API key.
  4. Update AWS Secrets Manager with the new key.
  5. Deploy the backend. AI features (weekly insights) are DOWN between revocation
     and deployment — this is acceptable (non-critical feature).

MINUTE 5-30: Assess Impact
  6. Review Anthropic usage dashboard:
     - Check for unusual request volume or patterns
     - Check for requests with non-Tempo prompts (attacker using key for their own purposes)
  7. Estimate financial impact (unauthorized API charges).
  8. Contact Anthropic support to report the compromised key and dispute unauthorized charges.

MINUTE 30-60: Verify
  9. Verify AI insight generation works with the new key.
  10. Monitor for 1 hour.

POST-INCIDENT:
  11. Determine how the key leaked.
  12. Remediate the leak source.
  13. No GDPR notification required (no user data was exposed — the attacker gets API
      access but Tempo's prompts contain only anonymized scores, no PII).
  14. However, if the attacker replayed requests and obtained AI-generated insights
      about users (even anonymized), assess whether the combination of data points
      could re-identify a user. If yes, escalate to P1.
```

#### Account Takeover

1. Immediately revoke all refresh tokens for the affected user.
2. Sign out all sessions.
3. Revoke Whoop OAuth token (prevent health data access).
4. Flag account for manual review.
5. Notify the user via their Apple relay email: "Your Tempo account may have been accessed by someone else. We've signed out all sessions. Please sign in again with your Apple ID."
6. If the attacker changed the username or display name, revert to the last known good values.
7. Audit XP events for anomalies and reverse any fraudulent XP.

#### DDoS

1. Enable CDN/WAF protection (Cloudflare, AWS Shield).
2. Increase rate limiting aggressiveness.
3. If backend is overwhelmed, enable maintenance mode (return `503` with `Retry-After`).
4. iOS app handles `503` gracefully: show cached data with "Server is temporarily busy" banner.
5. Scale backend horizontally if possible.
6. Log attack patterns for post-incident analysis.

### 11.3 Communication Plan

| Audience | Channel | When |
|----------|---------|------|
| Affected users | Push notification + in-app banner + email | Within 72 hours of confirmed breach |
| All users (if widespread) | App Store release notes + in-app banner | Within 1 week |
| Supervisory authority | Written report | Within 72 hours (GDPR) |
| Apple App Review | Email to app review team if app update needed | As needed |
| Third-party partners (Whoop, Anthropic) | Direct email to security contacts | Immediately if their data/keys are affected |

### 11.4 Post-Incident Review

Every P1 and P2 incident triggers a post-incident review within 7 days:

1. **Timeline:** Minute-by-minute reconstruction of events.
2. **Root cause:** The underlying vulnerability or process failure.
3. **Impact:** Exact data affected, exact users affected, duration.
4. **Response evaluation:** What went well, what could be faster.
5. **Action items:** Specific, assigned, with deadlines.
6. **Documentation update:** This security spec is updated with new controls.

---

## 12. Penetration Testing Checklist

### 12.1 OWASP Mobile Top 10 (2024) — Tempo-Specific Tests

> Reference: OWASP Mobile Top 10 2024 (https://owasp.org/www-project-mobile-top-10/)
> The 2024 version reorganizes categories compared to the 2016 version. All 10 categories are covered below.

| # | Category (2024) | Test ID | Test Description | Expected Result | Tempo-Specific Notes |
|---|----------------|---------|-----------------|----------------|---------------------|
| **M1** | Improper Credential Usage | M1-01 | Check if API keys, secrets, or signing keys are embedded in the iOS app binary | No secrets in binary. All API keys are backend-only. | Use `strings` and `class-dump` on the .ipa. Search for "sk-", "key", "secret", base64 patterns. |
| **M1** | Improper Credential Usage | M1-02 | Check if JWT tokens are stored outside the Keychain (UserDefaults, plist, SwiftData, files) | Tokens ONLY in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | Inspect app sandbox on a jailbroken device or simulator. |
| **M1** | Improper Credential Usage | M1-03 | Verify Keychain items use `ThisDeviceOnly` (not synced to iCloud Keychain) | All Keychain items have `ThisDeviceOnly` | Dump Keychain with `security` tool on test device. |
| **M1** | Improper Credential Usage | M1-04 | Check if refresh tokens are logged or appear in crash reports | No tokens in logs | Review Crashlytics and console output. |
| **M2** | Inadequate Supply Chain Security | M2-01 | Audit all third-party dependencies for known CVEs | No critical/high CVEs | Run `swift package audit` and check GitHub Dependabot alerts. Only 3 iOS deps: PostHog, Crashlytics, Lottie. |
| **M2** | Inadequate Supply Chain Security | M2-02 | Verify dependency integrity (checksums in Package.resolved) | All checksums match published versions | Check that Package.resolved is committed and checksums are pinned. |
| **M2** | Inadequate Supply Chain Security | M2-03 | Check for typosquatting or malicious packages | All packages from official sources | Verify each dependency's GitHub org is legitimate. |
| **M3** | Insecure Authentication/Authorization | M3-01 | Attempt to access any API endpoint without JWT | `401 Unauthorized` | Test every endpoint in the route table. |
| **M3** | Insecure Authentication/Authorization | M3-02 | Attempt to use an expired JWT (>15 min old) | `401 Unauthorized` | Craft a token with `exp` in the past. |
| **M3** | Insecure Authentication/Authorization | M3-03 | Attempt to use JWT signed with a different key | `401 Unauthorized` | Sign a valid-looking token with a random ES256 key. |
| **M3** | Insecure Authentication/Authorization | M3-04 | Send JWT with `alg: none` | Rejected | Must not accept unsigned tokens. |
| **M3** | Insecure Authentication/Authorization | M3-05 | Send JWT with `alg: HS256` (algorithm confusion attack) | Rejected (only ES256 accepted) | Backend must reject any algorithm other than ES256. |
| **M3** | Insecure Authentication/Authorization | M3-06 | Attempt refresh token replay (reuse a rotated token) | All user tokens revoked (nuclear option) | Verify the replay detection mechanism works. |
| **M3** | Insecure Authentication/Authorization | M3-07 | Access another user's data by substituting `user_id` in requests | `403` or `404` | BOLA test — see Section 12.2.1. |
| **M4** | Insufficient Input/Output Validation | M4-01 | SQL injection via friend search: `q=' OR 1=1--` | `400 Bad Request` (rejected by input validation) | Input validation rejects before reaching Fluent. |
| **M4** | Insufficient Input/Output Validation | M4-02 | XSS payload in username: `<script>alert(1)</script>` | Rejected by username regex (alphanumeric + underscore only) | Username stored as-is but never rendered as HTML. |
| **M4** | Insufficient Input/Output Validation | M4-03 | Unicode normalization attack in display name | Normalized (NFC) and validated | Test homoglyph attacks and zero-width characters. |
| **M4** | Insufficient Input/Output Validation | M4-04 | Oversized request body (10 MB) | `413 Payload Too Large` | Test each endpoint's size limit. |
| **M4** | Insufficient Input/Output Validation | M4-05 | Invalid JSON structure (deeply nested, 100 levels) | `400 Bad Request` | JSON depth limit: 5 levels. |
| **M4** | Insufficient Input/Output Validation | M4-06 | Send negative XP amount in sync payload | Rejected (integer bounds: 0-400) | Server validates all numeric ranges. |
| **M5** | Insecure Communication | M5-01 | Man-in-the-middle with Charles Proxy/Burp Suite | All traffic encrypted. Certificate validation prevents interception. | No ATS exceptions. TLS 1.2+ enforced by ATS. |
| **M5** | Insecure Communication | M5-02 | Check for ATS exceptions in Info.plist | No `NSAppTransportSecurity` exceptions | Inspect Info.plist directly. |
| **M5** | Insecure Communication | M5-03 | Verify TLS 1.3 is preferred (1.2 fallback acceptable) | Server negotiates TLS 1.3 with modern clients | Test with `nmap --script ssl-enum-ciphers`. |
| **M5** | Insecure Communication | M5-04 | Check for sensitive data in URL query parameters | No tokens, PII, or health data in URLs | All sensitive data in POST bodies or headers. |
| **M6** | Inadequate Privacy Controls | M6-01 | Verify no HealthKit data in SwiftData CloudKit sync | `cloudKitDatabase: .none` for health-derived models | Inspect `ModelConfiguration` in code. CI test enforces this. |
| **M6** | Inadequate Privacy Controls | M6-02 | Verify HealthKit authorization is per-type, not blanket | Each HealthKit type authorized individually | Inspect `requestAuthorization(toShare:read:)` call. |
| **M6** | Inadequate Privacy Controls | M6-03 | Check if health data appears in iOS task switcher snapshots | App obscures content when entering background | Launch app, background it, check task switcher. |
| **M6** | Inadequate Privacy Controls | M6-04 | Verify analytics events contain no PII or health data | No names, emails, health values in PostHog events | Review PostHog event stream for a test user session. |
| **M6** | Inadequate Privacy Controls | M6-05 | Verify push notification payloads contain no sensitive data | Generic messages only (e.g., "You have tasks remaining") | Intercept push payloads with a proxy. |
| **M6** | Inadequate Privacy Controls | M6-06 | Check if Whoop health data is written to app logs | No health data in console/file logs | Review `os_log` output during Whoop sync. |
| **M7** | Insufficient Binary Protections | M7-01 | Verify app uses standard iOS code signing | Valid signature, no re-signing possible without Apple cert | `codesign -dv --verbose=4 Tempo.app` |
| **M7** | Insufficient Binary Protections | M7-02 | Check for debug symbols in release build | Symbols stripped. dSYMs uploaded to Crashlytics only. | `nm` on release binary should show stripped. |
| **M7** | Insufficient Binary Protections | M7-03 | Check for debug/development entitlements in release build | No `get-task-allow` in release profile | Inspect entitlements with `codesign`. |
| **M8** | Security Misconfiguration | M8-01 | Check for debug endpoints in production backend | No `/debug`, `/test`, `/admin` routes | Enumerate routes with fuzzing. |
| **M8** | Security Misconfiguration | M8-02 | Check for default/test accounts in production database | No test accounts | Query users table. |
| **M8** | Security Misconfiguration | M8-03 | Verify HSTS, X-Content-Type-Options, X-Frame-Options headers | All security headers present on every response | `curl -I` against production API. |
| **M8** | Security Misconfiguration | M8-04 | Check for verbose error messages exposing stack traces | Production errors return generic messages, no stack traces | Trigger 500 errors and inspect response bodies. |
| **M9** | Insecure Data Storage | M9-01 | Inspect SwiftData store file on-device for encryption | File encrypted by iOS Data Protection (`CompleteUntilFirstUserAuthentication`) | Access file on jailbroken device while locked — should be unreadable. |
| **M9** | Insecure Data Storage | M9-02 | Check for sensitive data in iOS backups | Health data and tokens NOT included in unencrypted backups | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` items are excluded from non-encrypted backups. |
| **M9** | Insecure Data Storage | M9-03 | Check for sensitive data in pasteboard | App never copies tokens, health data, or PII to pasteboard | Monitor UIPasteboard during app usage. |
| **M9** | Insecure Data Storage | M9-04 | Verify Whoop tokens are encrypted in PostgreSQL | AES-256-GCM ciphertext, not plaintext | Direct DB query should return binary data, not readable tokens. |
| **M9** | Insecure Data Storage | M9-05 | Verify refresh tokens are hashed in PostgreSQL | SHA-256 hash stored, not plaintext | Direct DB query shows 64-char hex hash. |
| **M10** | Insufficient Cryptography | M10-01 | Verify ES256 signature validation rejects tampering | Modified payload with valid header/signature is rejected | Tamper with `sub` claim in a valid JWT. |
| **M10** | Insufficient Cryptography | M10-02 | Verify AES-256-GCM for Whoop token encryption uses unique nonces | Each encryption operation uses a fresh 12-byte nonce | Inspect nonce columns in DB — all should be unique. |
| **M10** | Insufficient Cryptography | M10-03 | Verify HMAC-SHA256 for webhook validation uses constant-time comparison | No timing side-channel | Use `MessageAuthenticationCode.isValidAuthenticationCode()` from CryptoKit, not string `==`. |

### 12.2 API Security Testing

#### General API Tests

| Test | Method | Expected Result |
|------|--------|----------------|
| **Large payload** | `POST` with 10MB body | `413 Payload Too Large` |
| **Content-Type mismatch** | Send XML body with `Content-Type: application/json` | `400 Bad Request` |
| **Missing Content-Type** | Send request without Content-Type header | `415 Unsupported Media Type` |
| **Rate limit bypass (IP rotation)** | Send 200 requests from multiple IPs in 1 minute | Per-user limit still triggers `429` regardless of IP |
| **Rate limit bypass (multiple accounts)** | Create multiple accounts behind one IP | Per-IP limit triggers `429` regardless of account |
| **JWT algorithm confusion** | Send JWT with `alg: none` | Rejected |
| **JWT algorithm switch** | Send JWT with `alg: HS256` (symmetric) | Rejected (only ES256 accepted) |
| **Expired token handling** | Send request with 1-day-old access token | `401 Unauthorized` |
| **Blocked token (blocklist)** | Send request with a blocklisted `jti` | `401 Unauthorized` |
| **Webhook forgery** | Send Whoop webhook without valid HMAC signature | `401 Unauthorized` |
| **Webhook replay** | Send same Whoop webhook twice (same event ID) | Idempotent (processed once) |
| **HTTP verb tampering** | Send DELETE to a GET-only endpoint | `405 Method Not Allowed` |
| **Path traversal** | `GET /v1/user/../../etc/passwd` | `404` or `400` |

#### 12.2.1 BOLA — Broken Object Level Authorization (OWASP API #1)

BOLA (also known as IDOR) is the single most critical API vulnerability. Every endpoint that takes a resource ID must verify the authenticated user owns or has access to that resource.

| Test ID | Endpoint | Attack | Expected Result |
|---------|----------|--------|----------------|
| BOLA-01 | `GET /v1/user/{id}/profile` | User A requests User B's full profile | `404` (not `403` — avoid confirming existence) |
| BOLA-02 | `GET /v1/user/{id}/whoop` | User A requests User B's Whoop health data | `404` |
| BOLA-03 | `GET /v1/user/{id}/daily-scores` | User A requests User B's daily scores (not friends) | `404` |
| BOLA-04 | `GET /v1/user/{id}/daily-scores` | User A requests User B's daily scores (friends) | `200` with score only (not workout/health details) |
| BOLA-05 | `PATCH /v1/user/{id}/profile` | User A updates User B's username | `403` or `404` |
| BOLA-06 | `DELETE /v1/user/{id}/account` | User A deletes User B's account | `403` or `404` |
| BOLA-07 | `GET /v1/arena/friends/{id}/stats` | User A requests non-friend's stats | `404` |
| BOLA-08 | `GET /v1/arena/challenges/{id}` | User A requests a challenge they're not part of | `404` |
| BOLA-09 | `DELETE /v1/arena/challenges/{id}` | User A deletes a challenge created by User B | `403` |
| BOLA-10 | `GET /v1/user/{id}/data-export` | User A exports User B's data | `403` or `404` |
| BOLA-11 | `POST /v1/arena/xp` | User A sends fabricated XP event | Rejected (XP events are server-generated, not accepted via API) |
| BOLA-12 | UUID enumeration: iterate sequential UUIDs | Attacker tries to discover valid user IDs | UUIDs are v4 (random) — enumeration is infeasible. No sequential patterns. |

**Implementation requirement:** Every controller method MUST extract `user_id` from the JWT (not from the request body or URL) and use it as the primary authorization context. The URL parameter `{id}` is the target resource, NOT the authenticated user.

#### 12.2.2 BFLA — Broken Function Level Authorization (OWASP API #5)

BFLA tests verify that users cannot access functions they should not have access to.

| Test ID | Endpoint/Function | Attack | Expected Result |
|---------|-------------------|--------|----------------|
| BFLA-01 | Admin endpoints (if any exist) | Regular user calls admin-only endpoint | `403` or `404` (endpoints should not be discoverable) |
| BFLA-02 | `POST /v1/arena/challenges/{id}/remove-user` | Non-creator tries to remove a participant | `403` |
| BFLA-03 | `POST /v1/arena/friends/respond` | User A responds to a friend request sent TO User B | `403` (only the request target can respond) |
| BFLA-04 | `PATCH /v1/user/profile` | Set `is_admin: true` in request body | Field ignored. Admin status is not settable via API. |
| BFLA-05 | `POST /v1/sync` | Include XP amount in sync payload | XP field ignored. Server computes XP from raw events only. |
| BFLA-06 | Direct DB ID manipulation | Replace UUID in request with known admin/system user UUID | `403` or `404`. System user IDs should not be accessible. |
| BFLA-07 | HTTP method override | `X-HTTP-Method-Override: DELETE` on a GET request | Header ignored. Vapor does not support method override. |

#### 12.2.3 Mass Assignment

| Test ID | Endpoint | Attack | Expected Result |
|---------|----------|--------|----------------|
| MASS-01 | `PATCH /v1/user/profile` | Include `xp_total`, `level`, `is_admin` fields | Extra fields ignored. Only `username` and `display_name` are writable. |
| MASS-02 | `POST /v1/arena/challenges` | Include `winner_id` or `status: completed` | Extra fields ignored. These are server-computed. |
| MASS-03 | `POST /v1/sync` | Include `user_id` field in body (different from JWT) | Body `user_id` ignored. JWT `sub` is authoritative. |

### 12.3 Authorization Boundary Tests

| Test | Actors | Expected |
|------|--------|----------|
| User A reads User B's daily scores | A (not friend of B) | Denied |
| User A reads User B's daily scores | A (friend of B) | Allowed (score only, not details) |
| User A reads User B's daily scores | A (blocked by B) | Denied (404) |
| User A adds XP to User B | A | Denied |
| User A removes User B from challenge | A (not challenge creator) | Denied |
| User A removes User B from challenge | A (challenge creator) | Allowed |
| User A exports User B's data | A | Denied (can only export own data) |
| User A deletes User B's account | A | Denied |

### 12.4 Jailbreak/Root Detection

**Decision: Do NOT implement jailbreak detection at launch.**

Rationale:
- Jailbreak detection is a cat-and-mouse game with diminishing returns.
- Tempo is a fitness app, not a banking app. The threat model does not justify blocking jailbroken devices.
- Jailbreak detection can cause false positives, frustrating legitimate users.
- Apple's own data protection and Keychain security work on jailbroken devices (with limitations).
- **Future consideration:** If cheat abuse becomes prevalent in Arena, implement basic jailbreak detection as a signal (not a blocker) for anti-cheat analysis.

---

## 13. Privacy Policy

**Effective Date:** [Insert date before App Store submission]
**Last Updated:** [Insert date]

---

### Privacy Policy for Tempo

#### Introduction

Tempo ("we," "our," or "the app") is a personal life management application developed by Nicola Debbia. This Privacy Policy explains how we collect, use, store, and protect your information when you use the Tempo iOS application and its associated backend services.

We take your privacy seriously. Tempo handles sensitive health and fitness data, and we are committed to processing this data transparently and securely.

#### 1. Information We Collect

##### 1.1 Account Information
When you create a Tempo account using Sign in with Apple, we collect:
- **Apple User ID:** A unique, stable identifier provided by Apple for authentication.
- **Email address:** Your Apple ID email or Apple's private relay email address (if you choose "Hide My Email"). We never see your real email address if you use the relay.
- **Name:** Your first and last name, if you choose to share it with Tempo during sign-in. This is optional.

##### 1.2 Health and Fitness Data
Tempo accesses health and fitness data from the following sources, with your explicit permission:

**From Apple HealthKit (with your authorization):**
- Step count
- Active energy burned (calories)
- Heart rate
- Heart rate variability (HRV)
- Resting heart rate
- Sleep analysis (duration and stages)
- Workout records

**From Whoop (if you connect your Whoop account):**
- Recovery score
- Sleep performance and duration
- Strain score
- Heart rate variability (HRV)
- Resting heart rate
- Body measurements (weight, body fat percentage)
- Workout data

**From NutriTrack (if you connect your NutriTrack account):**
- Meals logged
- Calorie intake
- Macronutrient breakdown (protein, carbohydrates, fat)
- Meal timing

##### 1.3 Academic and Productivity Data
- Study session records (duration, timestamps) — logged manually through Tempo's focus timer.
- Non-negotiable task completion — tracked within Tempo.

##### 1.4 Calendar Data
If you grant calendar access, Tempo reads your calendar events (class schedules, exam dates, practice times) to optimize workout scheduling. Calendar data is read locally and is never transmitted to our servers.

##### 1.5 Social and Gamification Data
If you use Arena (social) features:
- Username and display name (chosen by you)
- Friend connections
- XP (experience points) and level
- Challenge participation and scores
- Achievement badges earned

##### 1.6 Device and Usage Data
- Device token for push notifications
- App version and build number
- Device model and iOS version
- Crash reports and performance diagnostics (anonymized, via Firebase Crashlytics)
- Feature usage patterns and screen views (anonymized, via PostHog — self-hosted or PostHog Cloud)
- Session duration and frequency
- Locale and timezone (for analytics segmentation, not location tracking)

#### 2. How We Use Your Information

| Purpose | Data Used | Legal Basis |
|---------|-----------|-------------|
| Provide core app functionality (dashboard, training, recovery, accountability) | Health data, fitness data, nutrition data, study data | Your explicit consent (for health data) and contract performance |
| Display personalized training recommendations | Whoop recovery data, HealthKit workout data, calendar events | Your explicit consent |
| Generate AI-powered weekly insights | Anonymized, aggregated health and productivity scores (NOT raw data) | Your explicit consent |
| Enable social features (Arena) | Username, XP, level, achievements | Contract performance |
| Send accountability notifications | Non-negotiable completion status (no health details) | Your consent (notification permission) |
| Improve app stability and performance | Anonymized crash/performance data | Legitimate interest |
| Authenticate your account | Apple User ID, email | Contract performance |

#### 3. How We Share Your Information

**We do NOT sell your data. We do NOT use your data for advertising.**

| Recipient | Data Shared | Purpose | Your Control |
|-----------|-------------|---------|-------------|
| **Whoop** | Your Whoop OAuth authorization grants Tempo read access to: recovery scores, sleep performance/duration, strain scores, HRV, resting heart rate, body measurements, and workout data. Tempo's backend fetches this data from Whoop's API on your behalf and caches it for up to 90 days. Your Whoop account credentials (username/password) are never shared with Tempo — only an OAuth token that you can revoke at any time. | To display recovery, sleep, and strain data in the app and adjust training recommendations | Disconnect in Settings > Integrations (this revokes the OAuth token) |
| **Anthropic (Claude AI)** | Anonymized aggregate scores only (e.g., "recovery: 72%", "study: 2.3h/day"). NO names, emails, Apple IDs, usernames, or any identifiable information. Data is sent via Anthropic's API; per Anthropic's API Terms (as of 2026), API inputs and outputs are NOT used to train Anthropic's models. Data is processed transiently — Anthropic does not retain API inputs/outputs beyond 30 days (for trust & safety purposes). Tempo uses Claude Haiku 4.5 for real-time features, Claude Sonnet 4.6 for weekly analysis, and Claude Opus 4.6 for pattern detection. **App Store Guideline 5.1.2(i) compliance:** AI data sharing requires SEPARATE, EXPLICIT user consent obtained during onboarding on a dedicated screen that names "Anthropic" and "Claude" specifically. Users can decline AI features without losing core app functionality. Consent is revocable anytime in Settings > Privacy > AI Features. See `docs/APP_STORE_COMPLIANCE.md` Section 1 for the full consent flow specification. | Generate weekly insights, pattern detection, and real-time coaching | AI features require explicit opt-in consent. Can be disabled in Settings > Privacy > AI Features. |
| **Apple** | Authentication tokens, push notification tokens | Sign in with Apple, push notifications | Managed by Apple's privacy controls |
| **Other Tempo users** | Username, display name, XP, level, achievements (to friends only) | Arena social features | Leave Arena in Settings. Adjust visibility in Arena Settings. |
| **Law enforcement** | As required by law | Legal obligation | N/A |

**We do NOT share data with:**
- Advertising networks
- Data brokers
- Analytics companies (we use only first-party, anonymized analytics)
- Insurance companies
- Employers
- Any other third party not listed above

#### 4. HealthKit Data

Tempo's use of Apple HealthKit data is governed by Apple's strict requirements:
- HealthKit data is **never** used for advertising or marketing.
- HealthKit data is **never** sold to any third party.
- HealthKit data is **never** stored in iCloud.
- HealthKit data is **never** shared with third parties without your explicit, informed consent.
- Raw HealthKit data (heart rate samples, sleep stage data, etc.) **never leaves your device**. Only composite scores computed locally on your device may be synced to our servers for Arena features.

#### 5. Data Storage and Security

- **On your device:** Health data is stored using Apple's iOS Data Protection API with hardware-backed encryption. Credentials are stored in the iOS Keychain, protected by the Secure Enclave.
- **On our servers:** Data is encrypted in transit (TLS 1.3) and at rest (AES-256). Whoop tokens are additionally encrypted at the application layer. Passwords and tokens are hashed, never stored in plaintext.
- **Data residency:** Our servers are hosted on [AWS region — to be determined based on primary user base. EU region (eu-west-1) preferred for GDPR compliance].

For full technical details, see our Security Specification (available upon request).

#### 6. Data Retention

| Data Type | Where Stored | Retention Period | Deletion Trigger | Deletion Method |
|-----------|-------------|-----------------|-----------------|----------------|
| **Account data** (username, display name, email, Apple User ID) | PostgreSQL backend | Until account deletion | User deletes account or 30-day post-deletion cleanup | Hard delete from `users` table. Backups purged within 90 days. |
| **Whoop health data** (recovery, sleep, strain, HRV, RHR) | PostgreSQL backend (cache) | 90-day rolling window | Automatic nightly job prunes records older than 90 days. All data deleted on account deletion or Whoop disconnect. | Hard delete. Aggregated (non-identifiable) statistics may be retained. |
| **Whoop OAuth tokens** (access + refresh) | PostgreSQL backend (AES-256-GCM encrypted) | Until user disconnects Whoop or deletes account | User disconnects Whoop, Whoop revokes token, or account deletion | Hard delete + Whoop revocation API call. |
| **Daily composite scores** (0-100) | PostgreSQL backend + iOS SwiftData | Until account deletion | Account deletion | Backend: hard delete. iOS: SwiftData store wiped on sign-out/deletion. |
| **Nutrition data** (cached from NutriTrack) | PostgreSQL backend + iOS SwiftData | Until account deletion or NutriTrack disconnect | Account deletion or NutriTrack disconnect | Hard delete. |
| **Workout history** | iOS SwiftData (local only) | Until account deletion | Account deletion or manual deletion | SwiftData store wiped. Not on backend. |
| **Study sessions and non-negotiable progress** | PostgreSQL backend + iOS SwiftData | Until account deletion | Account deletion | Hard delete from both stores. |
| **XP events and achievements** | PostgreSQL backend | Until account deletion | Account deletion | Hard delete. Leaderboard materialized views refreshed to remove user. |
| **Friend connections** | PostgreSQL backend | Until unfriended, blocked, or account deletion | Any of the three triggers | Hard delete from `friendships` table (both directions). |
| **Challenge data** | PostgreSQL backend | 30 days after challenge ends, OR until account deletion (whichever is sooner) | Nightly cleanup job for expired challenges. Account deletion. | Hard delete. |
| **Push notification device tokens** | PostgreSQL backend | Until device unregistered, app uninstalled, sign-out, or account deletion | APNs `410 Gone` response, 90-day inactivity cleanup, or explicit deletion | Hard delete from `device_tokens` table. |
| **JWT refresh tokens** | PostgreSQL backend (SHA-256 hashed) | 30 days (max lifetime) or until sign-out | Expiry, sign-out, or revocation | Hard delete. |
| **Consent records** | PostgreSQL backend | 5 years after last consent action (legal retention requirement) | Automated cleanup after 5 years. NOT deleted on account deletion (legal obligation). | Hard delete after retention period. |
| **Anonymized analytics events** | PostHog (self-hosted or cloud) | 12 months | Automated retention policy in PostHog | Automatic purge. |
| **Crash reports** | Firebase Crashlytics | 90 days (Firebase default) | Automatic | Managed by Firebase. |
| **Server access logs** | Log aggregation service | 30 days | Automatic rotation | Automatic purge. |
| **Database backups** | AWS S3 (encrypted) | 90 days | Automatic lifecycle policy | Automatic deletion. Note: a deleted user's data may persist in backups for up to 90 days after deletion. |
| **HealthKit data on device** | iOS HealthKit store | Managed by user and iOS | User manages via Apple Health app | Tempo does not delete HealthKit data — it is Apple's store. |
| **Calendar data** | iOS EventKit (read-only, never stored by Tempo) | Not stored | N/A | N/A — Tempo reads but never persists calendar data. |
| **AI prompt/response data at Anthropic** | Anthropic's infrastructure | Up to 30 days (Anthropic's trust & safety retention) | Automatic per Anthropic's API Terms | Managed by Anthropic. Not under Tempo's control. |

#### 7. Your Rights

Depending on your jurisdiction, you may have the following rights:

- **Right to access:** Export all your data in JSON format from Settings > Privacy > Export My Data.
- **Right to deletion:** Delete your account and all associated data from Settings > Account > Delete Account. Deletion is processed within 30 days. A 7-day cooling-off period allows cancellation.
- **Right to rectification:** Correct your personal data (username, display name) in Settings > Profile.
- **Right to portability:** Your data export is provided in a standard, machine-readable JSON format.
- **Right to restrict processing:** You can disconnect integrations (Whoop, NutriTrack) and disable features (Arena, AI insights) without deleting your account.
- **Right to withdraw consent:** Revoke HealthKit access in iOS Settings > Health > Tempo. Disconnect Whoop/NutriTrack in Tempo Settings. Disable notifications in iOS Settings.
- **Right to object:** Contact us to object to specific data processing.

#### 7A. California Privacy Rights (CCPA/CPRA)

While Tempo is developed in Italy and the primary developer is not based in California, we extend the following rights to California residents as a best practice and in anticipation of future user growth:

- **Right to Know:** You can request a list of the categories and specific pieces of personal information we have collected about you, the sources of that information, the business purpose for collecting it, and the categories of third parties with whom we share it. Use Settings > Privacy > Export My Data or email privacy@tempo.app.
- **Right to Delete:** You can request deletion of your personal information. Use Settings > Account > Delete Account. See Section 7 above for the deletion process and timeline.
- **Right to Opt-Out of Sale:** **Tempo does NOT sell personal information.** We have never sold personal information and have no plans to do so. No opt-out mechanism is needed because no sale occurs.
- **Right to Non-Discrimination:** We will not discriminate against you for exercising your CCPA rights. You will not receive a different level of service or pricing.
- **Shine the Light (Cal. Civ. Code Section 1798.83):** Tempo does not disclose personal information to third parties for their direct marketing purposes.

**Verification:** To verify your identity for a CCPA request, we require you to authenticate via Sign in with Apple (which proves you own the Apple ID associated with the account). For requests made via email, we will ask you to verify from the Apple relay email address on file.

**Authorized Agents:** You may designate an authorized agent to make CCPA requests on your behalf. We require the agent to provide written authorization from you and will verify your identity directly.

**Categories of Personal Information Collected (CCPA Categories):**

| CCPA Category | Collected | Examples |
|---------------|-----------|---------|
| A. Identifiers | Yes | Apple User ID, email (relay), username, device token |
| B. Personal information (Cal. Civ. Code 1798.80) | Yes | Name (if provided) |
| C. Protected classification characteristics | No | — |
| D. Commercial information | No | — |
| E. Biometric information | No | (Biometrics are in HealthKit on-device, not collected by Tempo's servers) |
| F. Internet or network activity | Yes | Feature usage analytics (anonymized), crash data |
| G. Geolocation data | No | — |
| H. Sensory data | No | — |
| I. Professional or employment information | No | — |
| J. Non-public education information | No | — |
| K. Inferences drawn | Yes | Daily composite scores (0-100), AI-generated insights |

#### 8. Children's Privacy

Tempo is not directed at children under the age of 13 (or 16 in the EU). We do not knowingly collect personal information from children. If we learn that we have collected data from a child, we will delete it promptly.

#### 9. International Data Transfers

If our servers are located outside your country of residence, your data may be transferred internationally. We ensure appropriate safeguards are in place, including Standard Contractual Clauses (SCCs) where applicable.

#### 10. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. We will notify you of material changes by:
- Displaying an in-app notification
- Updating the "Last Updated" date at the top
- For significant changes, requesting renewed consent

#### 11. Contact Us

For privacy inquiries, data access requests, or concerns:

- **Email:** privacy@tempo.app
- **In-app:** Settings > Privacy > Contact Us

If you believe your data protection rights have been violated, you have the right to lodge a complaint with your local supervisory authority.

---

## 14. Terms of Service

**Effective Date:** [Insert date before App Store submission]
**Last Updated:** [Insert date]

---

### Terms of Service for Tempo

#### 1. Acceptance of Terms

By downloading, installing, or using Tempo ("the App"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, do not use the App.

#### 2. Description of Service

Tempo is a personal life management application that integrates fitness tracking, nutrition monitoring, academic accountability, recovery analysis, and social gamification features. Tempo is NOT a medical device and does NOT provide medical advice. See Section 12 (Health Disclaimers) for important limitations.

#### 3. Account Registration

##### 3.1 Eligibility
You must be at least 13 years of age (or 16 in the EU) to use Tempo. By creating an account, you represent that you meet this requirement.

##### 3.2 Sign in with Apple
Account creation and authentication is handled exclusively through Sign in with Apple. You are responsible for maintaining the security of your Apple ID.

##### 3.3 Account Information
- You may choose a username and display name.
- Your username must be unique, 3-20 characters, and contain only letters, numbers, and underscores.
- You may not use a username that is offensive, misleading, impersonates another person, or violates these Terms.
- We reserve the right to reclaim or change usernames that violate these Terms.

#### 4. Acceptable Use

##### 4.1 You Agree To:
- Provide accurate information when setting up your profile.
- Use the App for personal fitness, nutrition, and productivity purposes.
- Respect other users in social features (Arena).
- Report violations of these Terms through the in-app report system.

##### 4.2 You Agree NOT To:
- Create multiple accounts.
- Manipulate XP, scores, leaderboards, or challenge results through any automated, fraudulent, or deceptive means.
- Harass, abuse, or send unsolicited communications to other users.
- Use offensive, discriminatory, or inappropriate usernames or challenge names.
- Attempt to access other users' data or accounts.
- Reverse engineer, decompile, or disassemble the App.
- Use the App to collect data about other users.
- Circumvent any security measures or access controls.
- Use bots, scripts, or automated tools to interact with the App.

#### 5. XP, Levels, and Arena Rules

##### 5.1 XP System
- XP (experience points) is earned through completing workouts, study sessions, meals, and other tracked activities.
- XP values are determined solely by Tempo's scoring system and may be adjusted at any time.
- XP has no monetary value and cannot be transferred, sold, or exchanged.

##### 5.2 Leaderboards
- Leaderboards display XP rankings among friends for the current week.
- Rankings are computed server-side and are final.
- We reserve the right to remove users from leaderboards for violations of these Terms.

##### 5.3 Challenges
- Challenges are time-limited competitions between participants.
- Challenge creators set the metric, start date, and end date.
- Results are computed server-side from tracked data and are final.
- We reserve the right to void or modify challenge results if cheating is detected.

##### 5.4 Fair Play
- All XP and challenge scores must be earned through genuine activity.
- Fabricating workouts, inflating study time, or manipulating data to gain unfair advantage is prohibited.
- Detection of cheating may result in: XP reversal, challenge disqualification, temporary restriction, or permanent account termination.

#### 6. Third-Party Integrations

##### 6.1 Whoop
- Connecting your Whoop account is optional.
- By connecting, you authorize Tempo to access your Whoop data as described in our Privacy Policy.
- Tempo is not affiliated with, endorsed by, or sponsored by Whoop.
- Whoop data accuracy is dependent on Whoop's systems and hardware. Tempo is not responsible for inaccurate Whoop data.

##### 6.2 NutriTrack
- Connecting your NutriTrack account is optional.
- By connecting, you authorize Tempo to access your NutriTrack nutrition data.
- NutriTrack data accuracy is your responsibility.

##### 6.3 Apple HealthKit
- HealthKit integration is optional but recommended.
- By granting HealthKit access, you authorize Tempo to read and write the specific health data types described during the authorization prompt.
- You can revoke HealthKit access at any time in iOS Settings > Health > Tempo.

#### 7. Intellectual Property

##### 7.1 Our Property
The App, including its design, code, features, content, trademarks, and branding, is owned by Nicola Debbia and is protected by intellectual property laws. You receive a limited, non-exclusive, non-transferable license to use the App for personal, non-commercial purposes.

##### 7.2 Your Content
You retain ownership of any content you create (usernames, challenge names). By using the App, you grant us a non-exclusive license to display your username, display name, XP, achievements, and challenge participation to other users as part of the Arena features.

#### 8. Privacy

Your privacy is important to us. Our collection and use of personal information is governed by our Privacy Policy, which is incorporated into these Terms by reference. By using the App, you consent to our Privacy Policy.

#### 9. Account Termination

##### 9.1 By You
You may delete your account at any time from Settings > Account > Delete Account. Account deletion is subject to a 7-day cooling-off period, after which all data is permanently deleted within 30 days.

##### 9.2 By Us
We may suspend or terminate your account if you:
- Violate these Terms of Service
- Engage in cheating, harassment, or abuse
- Receive multiple verified reports from other users
- Attempt to compromise the security of the App or other users' data

Before termination, we will make reasonable efforts to notify you and provide an opportunity to export your data, unless the violation is severe or poses a risk to other users.

#### 10. Subscription Terms

[If applicable:]

##### 10.1 Pricing
- Subscription prices are displayed in the App before purchase.
- Prices may vary by region and are determined by the App Store.

##### 10.2 Billing
- Subscriptions are billed through your Apple ID account.
- Payment is charged at confirmation of purchase.
- Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period.

##### 10.3 Cancellation
- You can manage and cancel subscriptions in iOS Settings > [Your Name] > Subscriptions.
- Cancellation takes effect at the end of the current billing period.
- No refunds for partial billing periods.

##### 10.4 Free Features
The following features remain free regardless of subscription status: [define free tier features].

#### 11. Disclaimers and Limitations of Liability

##### 11.1 "As Is" Service
THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.

##### 11.2 No Guarantee of Accuracy
We do not guarantee the accuracy, completeness, or reliability of:
- Health and fitness data from Whoop, HealthKit, or NutriTrack
- AI-generated insights and recommendations
- Training recommendations and recovery prescriptions
- Daily scores and XP calculations

##### 11.3 Limitation of Liability
TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL NICOLA DEBBIA, TEMPO, OR ITS AFFILIATES BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO LOSS OF DATA, LOSS OF PROFITS, OR PERSONAL INJURY, ARISING OUT OF OR IN CONNECTION WITH YOUR USE OF THE APP.

OUR TOTAL LIABILITY FOR ALL CLAIMS ARISING OUT OF OR RELATING TO THE APP SHALL NOT EXCEED THE AMOUNT YOU PAID FOR THE APP IN THE 12 MONTHS PRECEDING THE CLAIM, OR EUR 50, WHICHEVER IS GREATER.

#### 12. Health Disclaimers

**TEMPO IS NOT A MEDICAL DEVICE.**

- Tempo does not provide medical advice, diagnosis, or treatment.
- Training recommendations, recovery prescriptions, and nutrition suggestions are for informational purposes only and should not replace professional medical advice.
- Heart rate, HRV, and sleep data displayed in Tempo are sourced from consumer devices (Whoop, Apple Watch) and may not be medically accurate.
- If you have a medical condition, consult your healthcare provider before following any training or nutrition recommendations.
- If you experience chest pain, dizziness, or other symptoms during exercise, stop immediately and seek medical attention.
- Tempo's "recovery prescriptions" are algorithm-generated suggestions based on consumer biometric data. They are NOT medical prescriptions.

#### 13. Dispute Resolution

##### 13.1 Governing Law
These Terms are governed by the laws of Italy, without regard to conflict of law principles.

##### 13.2 Informal Resolution
Before initiating any formal dispute resolution, you agree to contact us at support@tempo.app and attempt to resolve the dispute informally for at least 30 days.

##### 13.3 Jurisdiction
Any disputes that cannot be resolved informally shall be subject to the exclusive jurisdiction of the courts of [Nicola's province], Italy.

#### 14. Changes to Terms

We may modify these Terms at any time. Material changes will be communicated via:
- In-app notification at least 30 days before the changes take effect
- Updated "Last Updated" date

Continued use of the App after changes take effect constitutes acceptance of the revised Terms. If you disagree with changes, you may delete your account.

#### 15. Miscellaneous

##### 15.1 Severability
If any provision of these Terms is found to be unenforceable, the remaining provisions remain in full force and effect.

##### 15.2 Entire Agreement
These Terms, together with the Privacy Policy, constitute the entire agreement between you and Tempo regarding the use of the App.

##### 15.3 Waiver
Our failure to enforce any right or provision of these Terms does not constitute a waiver of that right or provision.

##### 15.4 Assignment
We may assign our rights and obligations under these Terms. You may not assign yours.

#### 16. Contact Information

- **Support:** support@tempo.app
- **Privacy:** privacy@tempo.app
- **Developer:** Nicola Debbia
- **Website:** [tempo.app — to be established]

---

## Appendix A: Compliance Checklist Summary

Use this checklist before each App Store submission:

- [ ] Privacy policy published and accessible at a public URL
- [ ] Privacy policy linked in App Store Connect
- [ ] Privacy policy accessible within the app (Settings > Privacy Policy)
- [ ] Terms of service published and accessible at a public URL
- [ ] Terms of service linked in App Store Connect
- [ ] Terms of service accessible within the app (Settings > Terms of Service)
- [ ] App Store privacy nutrition label matches this specification exactly
- [ ] HealthKit entitlement enabled in provisioning profile
- [ ] HealthKit usage descriptions in Info.plist (read + write)
- [ ] Face ID usage description in Info.plist
- [ ] Calendar usage description in Info.plist
- [ ] No ATS exceptions in Info.plist
- [ ] SwiftData health models configured with `cloudKitDatabase: .none`
- [ ] No HealthKit data transmitted to backend (verify with network proxy)
- [ ] No sensitive data in push notification payloads
- [ ] All tokens stored in iOS Keychain (not UserDefaults)
- [ ] No API keys or secrets in iOS app binary
- [ ] Sign in with Apple credential revocation listener registered
- [ ] Account deletion flow functional and tested
- [ ] Data export flow functional and tested
- [ ] All rate limits configured and tested
- [ ] WHAC webhook HMAC verification tested
- [ ] JWT ES256 signing key rotated within last 90 days
- [ ] Dependency vulnerability scan clean (no critical/high issues)
- [ ] App Review notes updated with current feature set
- [ ] TestFlight external testing approved before public release

## Appendix B: Security Contact

For responsible disclosure of security vulnerabilities:
- **Email:** security@tempo.app
- **Response time:** Acknowledgment within 24 hours, initial assessment within 72 hours.
- **Scope:** All Tempo services (iOS app, backend API, integrations).
- **Out of scope:** Third-party services (Whoop, Apple, Anthropic) — report to those vendors directly.

---

*This document is the single source of truth for all security, privacy, and compliance decisions in Tempo. Any code, configuration, or process that contradicts this document is a bug.*
