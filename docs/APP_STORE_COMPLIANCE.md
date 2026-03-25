# App Store Compliance -- Exhaustive Checklist

**App:** Tempo (iOS, SwiftUI)
**Version:** 1.0
**Last Updated:** 2026-03-24
**Author:** App Store Compliance Office
**Status:** Pre-submission compliance authority. Every item must be verified before submitting for review.

> This document consolidates every Apple App Store requirement that applies to Tempo.
> It is organized by rejection risk. Address Section 1 and Section 2 first -- these are
> the most common rejection reasons for health + AI apps.

---

## Table of Contents

1. [AI Data Sharing Compliance (Guideline 5.1.2(i))](#1-ai-data-sharing-compliance-guideline-512i)
2. [HealthKit Compliance (Guideline 27.x)](#2-healthkit-compliance-guideline-27x)
3. [Privacy & Data](#3-privacy--data)
4. [App Review Preparation](#4-app-review-preparation)
5. [In-App Purchase / Subscription Compliance](#5-in-app-purchase--subscription-compliance)
6. [Content & Safety](#6-content--safety)
7. [Specific Rejection Risk Mitigation](#7-specific-rejection-risk-mitigation)
8. [Pre-Submission Checklist](#8-pre-submission-checklist)

---

## 1. AI Data Sharing Compliance (Guideline 5.1.2(i))

> **Guideline 5.1.2(i) (November 2025):** Apps that send user data to a third-party AI
> service must (a) explicitly name the AI provider, (b) obtain separate consent before
> transmitting any data, (c) allow the user to decline AI features without losing core
> functionality, and (d) not bundle AI consent with other permissions.

This is the highest-risk guideline for Tempo. Failure to comply results in immediate rejection.

### 1.1 Consent Flow Design

**Where it appears:** Onboarding Step 11 (after HealthKit and Whoop, before Notification permissions). This is a DEDICATED screen -- it does not share space with any other permission request.

**Consent is SEPARATE from:**
- Sign in with Apple (Step 2)
- HealthKit authorization (Step 8)
- Whoop OAuth (Step 6)
- Notification permission (Step 10)
- NutriTrack connection (Step 7)

**Consent screen mockup:**

```
+--------------------------------------+
|  [progress bar: 11/12]               |
|                                       |
|  [AI sparkle icon, animated]          |
|                                       |
|  AI-Powered Insights                  |
|                                       |
|  Tempo can use Anthropic's Claude AI  |
|  to generate personalized insights    |
|  from your data:                      |
|                                       |
|  - Weekly performance reports         |
|  - Pattern detection across your      |
|    training, sleep, and nutrition     |
|  - Recovery-aware coaching            |
|  - Personalized notification copy     |
|                                       |
|  HOW IT WORKS                         |
|  Your health metrics (recovery        |
|  scores, sleep hours, nutrition       |
|  data, study time) are sent to        |
|  Anthropic's Claude API to generate   |
|  insights. Data is anonymized -- we   |
|  NEVER send your name, email, Apple   |
|  ID, or any identifying information.  |
|                                       |
|  ANTHROPIC'S COMMITMENT               |
|  Per Anthropic's API Terms, your      |
|  data is NOT used to train AI         |
|  models. Data is retained for up to   |
|  30 days for safety monitoring only.  |
|                                       |
|  YOUR RIGHTS                          |
|  * You can disable AI anytime in      |
|    Settings > Privacy > AI Features   |
|  * The app works fully without AI     |
|  * AI insights are not medical advice |
|                                       |
|  [Learn more about Anthropic's        |
|   privacy practices]                  |
|                                       |
|  [ Enable AI Insights ]  (amber CTA)  |
|  [ Continue without AI ] (text btn)   |
|                                       |
|  You can change this anytime in       |
|  Settings > Privacy > AI Features.    |
+--------------------------------------+
```

**Critical copy requirements:**
- The words "Anthropic" and "Claude" MUST appear explicitly -- not "AI service" or "third-party AI."
- The consent screen MUST list what data categories are sent (recovery scores, sleep, nutrition, study time).
- The consent screen MUST state what data is NOT sent (name, email, Apple ID, device info).
- The two buttons MUST have equal visual weight -- "Continue without AI" cannot be hidden or de-emphasized to the point of being invisible.

**Button behavior:**
- "Enable AI Insights" --> Sets `aiConsent = true`, records consent timestamp, proceeds to next step.
- "Continue without AI" --> Sets `aiConsent = false`, proceeds to next step. No degradation in onboarding experience.

### 1.2 Every Screen/Feature That Sends Data to Claude API

| # | Feature | Module | Data Sent to Claude | Why | Consent Gate |
|---|---------|--------|---------------------|-----|-------------|
| 1 | Morning Briefing (fallback only) | Dashboard | Recovery score, streak, schedule, tasks | Generate briefing when template fails | `aiConsent == true` |
| 2 | Weekly Report Analysis | Dashboard | 7-day recovery, sleep, nutrition, study, strain, XP | Generate weekly performance narrative | `aiConsent == true` |
| 3 | Pattern/Correlation Detection | Dashboard | 30-90 day recovery, sleep, nutrition, study, strain | Detect multi-variable patterns | `aiConsent == true` |
| 4 | Training Program Generation | RepForge | Recovery history, workout history, strain, football schedule | Generate weekly training program | `aiConsent == true` |
| 5 | Training Program Adjustment | RepForge | Today's recovery, recent strain, upcoming schedule | Adjust current program for recovery | `aiConsent == true` |
| 6 | Recovery Prescription Generation | RecoverIQ | Recovery score, HRV, RHR, sleep data, strain | Generate daily recovery prescriptions | `aiConsent == true` |
| 7 | Drill Sergeant Notification Copy | Lockdown | Recovery zone, tasks status, streak, intensity preference | Generate notification copy | `aiConsent == true` |
| 8 | Meal Timing Recommendations | RecoverIQ/Fuel | Recovery, nutrition status, training schedule | Recommend optimal meal timing | `aiConsent == true` |
| 9 | Study Schedule Optimization | Lockdown/Mind | Exam dates, study history, recovery, schedule | Optimize study schedule | `aiConsent == true` |
| 10 | Achievement Celebrations | Arena | Milestone type, streak count, XP, level | Generate celebration copy | `aiConsent == true` |
| 11 | Dashboard Insights | Dashboard | Today's recovery, nutrition, study, training | Generate natural language insights | `aiConsent == true` |
| 12 | Notification Batch Pre-Generation | Lockdown | Recovery zones, tasks, schedule, intensity | Pre-generate 3 days of notification copy | `aiConsent == true` |

**Enforcement rule:** Every `AIService` method MUST check `UserConsentManager.aiConsentGranted` before making any API call. If false, the method MUST return the fallback response (Section 8 of AI_INTELLIGENCE_ENGINE.md). This check is enforced at the service layer -- individual features do not make direct API calls.

### 1.3 Fallback System (App Without AI)

When the user declines AI consent, the app MUST be fully functional:

| Feature | AI Version | Non-AI Fallback | User Experience Difference |
|---------|-----------|-----------------|---------------------------|
| Morning Briefing | Haiku-enhanced | Template engine (Section 8.1) | Slightly less personality; same data, same structure |
| Weekly Report | Sonnet narrative | Template with delta calculations (Section 8.2) | Bullet-point format instead of narrative |
| Pattern Detection | Opus cross-domain | Local Pearson correlations (Section 8.3) | Simpler patterns; no multi-variable insights |
| Training Program | Sonnet-generated | Rule-based engine in TrainingEngine.swift (Section 8.5) | Same exercises, less creative periodization |
| Recovery Prescriptions | Haiku prescriptions | Algorithmic zone-based rules (Section 8.6) | Same recommendations, less nuanced language |
| Notification Copy | Sonnet-crafted | Pre-written copy bank (Section 8.4) | Less variety; rotates through fixed pool |
| Meal Timing | Haiku recommendations | Rule-based timing (Section 8.7) | Same core recommendations |
| Dashboard Insights | Haiku insights | Rule-based pattern matching | Simpler language, fewer cross-domain connections |

**Verification:** Test the ENTIRE app with `aiConsent = false`. Every screen must render, every feature must function, every notification must fire. This is a required QA pass before submission.

### 1.4 Settings Toggle to Revoke AI Consent

**Location:** Settings > Privacy > AI Features

**Screen contents:**
- Toggle: "AI-Powered Insights" (on/off)
- Current status: "Enabled" or "Disabled"
- Description: "When enabled, your anonymized health data is processed by Anthropic's Claude AI to generate personalized insights, reports, and coaching."
- Link: "Learn more about Anthropic's privacy practices"
- When toggling OFF: Confirmation dialog: "Disable AI Insights? You can re-enable anytime. Your data will no longer be sent to Anthropic's Claude AI. The app will use standard recommendations instead."
- When toggling ON (if previously consented): Immediate re-enable, no re-consent needed.
- When toggling ON (if never consented): Show the full consent screen from onboarding.

### 1.5 Data Sent to Claude -- Detailed Breakdown

For every API call, the following data is NEVER included:

| Field | Sent? | Reason |
|-------|-------|--------|
| user_id | NEVER | No purpose in prompt |
| email | NEVER | No purpose in prompt |
| apple_id | NEVER | No purpose in prompt |
| device_id | NEVER | No purpose in prompt |
| location / GPS | NEVER | Not collected for AI |
| IP address | NEVER | Not included in prompt |
| full name | NEVER | No purpose in prompt |
| first name | OPT-IN ONLY | Notification personalization (separate consent) |
| friend first names | OPT-IN ONLY | Competitive notification copy (separate consent) |

Data that IS sent (all anonymized, no PII):
- Recovery scores (integer, 0-100)
- HRV (milliseconds)
- Resting heart rate (bpm)
- Sleep duration and stages (hours)
- Strain (0-21 scale)
- Nutrition totals (calories, protein g, carbs g, fat g)
- Study session duration (hours)
- Workout type and duration
- Streak counts and XP
- Timezone (for time-based recommendations)
- Exam names (low PII risk)

---

## 2. HealthKit Compliance (Guideline 27.x)

### 2.1 Every HealthKit Data Type Requested

**Read permissions:**

| HKQuantityType / HKCategoryType | Identifier | Justification (Apple will ask) | Feature That Uses It | Graceful Degradation If Denied |
|---|---|---|---|---|
| Step Count | `HKQuantityTypeIdentifierStepCount` | Displayed in Dashboard "Move" quadrant. Auto-completes the steps non-negotiable when daily target is met. | Dashboard, Lockdown | "Steps unavailable -- enable in Settings > Health > Tempo". Steps non-negotiable requires manual check-off. |
| Active Energy Burned | `HKQuantityTypeIdentifierActiveEnergyBurned` | Displayed in Dashboard "Move" quadrant for caloric expenditure context alongside nutrition data. | Dashboard | Move quadrant shows workout-based estimates only. |
| Heart Rate | `HKQuantityTypeIdentifierHeartRate` | Real-time exertion display during workouts in RepForge. Secondary recovery signal when Whoop is not connected. | RepForge, RecoverIQ | No live HR during workouts. Training uses manual RPE input. |
| Heart Rate Variability (SDNN) | `HKQuantityTypeIdentifierHeartRateVariabilitySDNN` | Primary input for daily recovery score computation when Whoop is not connected. | RecoverIQ | Whoop HRV is primary source. If both denied, Recovery module shows "Connect Whoop for recovery data." |
| Resting Heart Rate | `HKQuantityTypeIdentifierRestingHeartRate` | Displayed in Dashboard "Body" quadrant. Secondary recovery signal alongside HRV. | Dashboard, RecoverIQ | Same as HRV -- Whoop is primary source. |
| Sleep Analysis | `HKCategoryTypeIdentifierSleepAnalysis` | Displayed in Dashboard "Body" quadrant. Feeds into daily recovery score and bedtime prescriptions. | Dashboard, RecoverIQ | Whoop is primary sleep source. HealthKit sleep supplements but is not required. |
| Workout Type | `HKWorkoutType` | Read existing workouts to avoid double-counting with RepForge. Display workout history on training calendar. | RepForge | User can log workouts manually. Auto-detection disabled. |

**Write permissions:**

| HKQuantityType / HKWorkoutType | Identifier | Justification | Graceful Degradation If Denied |
|---|---|---|---|
| Workouts | `HKWorkoutType` | Write RepForge-completed workouts so the user's Apple Health record stays complete. | RepForge workouts not written to HealthKit. Silent failure. |
| Dietary Energy Consumed | `HKQuantityTypeIdentifierDietaryEnergyConsumed` | Write NutriTrack-synced calorie data so Health app shows complete nutrition data. | NutriTrack data stays in Tempo only. Silent failure. |

### 2.2 Data Storage Rules

**Rule: HealthKit data MUST NOT be stored in iCloud.**

SwiftData configuration enforcement:

```swift
// REQUIRED: All health-derived models use cloudKitDatabase: .none
let healthModelConfig = ModelConfiguration(
    "HealthData",
    schema: Schema([DailySnapshot.self, DailyPrescription.self,
                    WorkoutPlan.self, RecoveryPrescription.self]),
    cloudKitDatabase: .none  // CRITICAL: Never .automatic or .private
)
```

Three-layer enforcement:
1. **Code:** `ModelConfiguration` uses `cloudKitDatabase: .none` for all health-derived models.
2. **CI test:** Automated test asserts that any `ModelConfiguration` containing health model types never initializes with `.automatic` or `.private`.
3. **Code review checklist:** "Does this model contain HealthKit-derived data? If yes, verify `cloudKitDatabase: .none`."

**Rule: Raw HealthKit samples NEVER leave the device.**

The backend receives only:
- Composite daily scores (0-100) computed on-device
- XP events (contain no health data)
- Boolean flags (e.g., `workoutCompleted: true`)
- Whoop data fetched by the backend directly from the Whoop API (not from HealthKit)

### 2.3 Push Notification Payload Compliance

**Rule: Push notification `alert.body` MUST NOT contain health data visible on the lock screen.**

Per ONBOARDING_AND_NOTIFICATIONS.md Section "Lock Screen Safety":

The following MUST NOT appear in `alert.body`:
- Exact recovery score percentages (e.g., "Recovery: 34%")
- Exact HRV values
- Exact heart rate values
- Exact sleep hours (e.g., "4.2h of sleep")
- Calorie counts or macro numbers
- Body weight
- Supplement or medication references

**Safe alternatives for `alert.body`:**
- Recovery zones: "Green / Yellow / Red" without percentages
- Sleep quality: "Great sleep" / "Rough night" / "Sleep needs work"
- General language: "Your morning plan is ready" instead of "Recovery 34%, mobility only"

**Implementation:** Exact health values go in the `data` payload (not visible on lock screen). The `alert.body` uses zone-based, qualitative language only. Local notifications (on-device) may be more specific since the user has already granted access to their own data, but should still assume the lock screen is visible to others.

**IMPORTANT -- Morning Briefing Copy Templates:** The copy variations in ONBOARDING_AND_NOTIFICATIONS.md (lines 1729-2098) containing `{recovery_score}%`, `{sleep_hours}`, `{calories_current}`, etc. are for LOCAL notification rendering and in-app display ONLY. When these templates are used for PUSH notifications from the backend, the server MUST substitute zone-based language in the `alert.body` field and place exact values in the `data` payload.

### 2.4 Graceful Degradation Matrix

The app MUST function without HealthKit, without Whoop, without NutriTrack, without Calendar, without Notifications, and without ALL integrations simultaneously.

| All Integrations Denied | What Still Works |
|------------------------|-----------------|
| Dashboard | Placeholder states in all quadrants. User can manually log. |
| Training (RepForge) | Manual workout logging with exercise library. Manual RPE input. |
| Accountability (Lockdown) | Manual check-off for all non-negotiables. Focus timer works. |
| Recovery (RecoverIQ) | "Connect a device for recovery data" placeholder screen. |
| Arena (ClutchTime) | XP from manual activities. Social features work. |

---

## 3. Privacy & Data

### 3.1 Privacy Nutrition Label (App Store Connect)

These are the EXACT fields to enter in App Store Connect.

#### Data Collected

| Data Type | Collected | Linked to Identity | Used for Tracking | Purpose |
|-----------|-----------|-------------------|-------------------|---------|
| **Name** (display name) | Yes | Yes | No | App Functionality |
| **Email Address** (Apple relay) | Yes | Yes | No | App Functionality |
| **User ID** (Apple User ID, internal UUID) | Yes | Yes | No | App Functionality |
| **Health & Fitness -- Health** (heart rate, HRV, resting HR) | Yes | Yes | No | App Functionality |
| **Health & Fitness -- Fitness** (workouts, steps, active energy, exercise data) | Yes | Yes | No | App Functionality |
| **Health & Fitness -- Sleep** (sleep duration, sleep stages) | Yes | Yes | No | App Functionality |
| **Health & Fitness -- Nutrition** (calories, macros, meals logged) | Yes | Yes | No | App Functionality |
| **Health & Fitness -- Body Measurements** (weight, body fat via Whoop) | Yes | Yes | No | App Functionality |
| **Usage Data -- Product Interaction** (feature usage, screen views) | Yes | No | No | Analytics |
| **Diagnostics -- Crash Data** | Yes | No | No | App Functionality |
| **Diagnostics -- Performance Data** | Yes | No | No | App Functionality |
| **Identifiers -- Device ID** (for push notifications) | Yes | No | No | App Functionality |

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

#### Third-Party AI Processing Disclosure
The Privacy Nutrition Label should disclose that health data is processed by a third-party AI service (Anthropic) for generating insights, with no PII attached. In App Store Connect, this falls under "Data Linked to You -- Health & Fitness" with purpose "App Functionality." The consent flow (Section 1) ensures this processing is opt-in.

### 3.2 Privacy Policy Requirements

The privacy policy in SECURITY_AND_PRIVACY.md Section 13 MUST cover:

- [x] What data is collected (every type from the Nutrition Label)
- [x] How data is used (per-purpose breakdown)
- [x] How data is shared and with whom (Anthropic for AI, Whoop for integration)
- [x] How data is stored and protected
- [x] Data retention periods (detailed table in Section 6)
- [x] User rights (access, deletion, correction, portability, restriction, withdrawal, objection)
- [x] Contact information for privacy inquiries (privacy@tempo.app)
- [x] HealthKit-specific data handling disclosure (Section 4)
- [x] Third-party service disclosure (Anthropic, Whoop, Apple, NutriTrack)
- [x] Children's privacy statement (Section 8)
- [x] Changes notification process (Section 10)
- [x] Effective date
- [x] CCPA/CPRA rights (Section 7A)
- [x] Anthropic named explicitly as a data processor with description of what data is shared

**Accessibility of privacy policy:**
1. App Store listing (URL field in App Store Connect) -- REQUIRED
2. Within the app (Settings > Privacy Policy) -- REQUIRED
3. During onboarding before first data collection -- REQUIRED

### 3.3 GDPR Compliance

Tempo is developed by Nicola Debbia (Italy). GDPR fully applies under Article 3(2) since the app is available on the EU App Store.

Key GDPR requirements verified:
- [x] Lawful basis for processing identified for each data type (explicit consent for health data per Art. 9(2)(a))
- [x] Data Processing Agreement with Anthropic (TO BE SIGNED -- see SECURITY_AND_PRIVACY.md Section 8)
- [x] 72-hour breach notification obligation documented (Incident Response Plan)
- [x] Data Protection Impact Assessment needed (health data = high risk)
- [x] Right to erasure implemented (Settings > Account > Delete Account)
- [x] Right to data portability implemented (Settings > Privacy > Export My Data, JSON format)
- [x] Consent records stored for 5 years (legal retention requirement)
- [x] Data minimization principle applied to Claude API calls (only anonymized aggregate scores)

### 3.4 CCPA/CPRA Compliance

Extended to California residents as best practice:
- [x] Right to Know
- [x] Right to Delete
- [x] Right to Opt-Out of Sale (Tempo does NOT sell data -- no opt-out needed)
- [x] Right to Non-Discrimination
- [x] Verification via Sign in with Apple

---

## 4. App Review Preparation

### 4.1 Demo Account

**Not needed.** Sign in with Apple is the sole authentication method. The reviewer creates a fresh account using their Apple ID. This is stated in the App Review Notes.

### 4.2 App Review Notes

Use this text VERBATIM in the "Notes for Reviewer" field in App Store Connect:

```
Tempo is a personal life management app that integrates health, fitness,
nutrition, academics, and social accountability features.

SIGN IN WITH APPLE:
Sign in with Apple is the sole authentication method. No demo account
is needed -- the reviewer can create a fresh account using their Apple ID.

HEALTHKIT -- WHY EACH DATA TYPE IS NEEDED:
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
sleep data, strain, and HRV. A Whoop account is OPTIONAL -- the app
functions without it using HealthKit data alone. If the reviewer does
not have a Whoop device, the app gracefully degrades and shows
HealthKit-only data.

NUTRITRACK INTEGRATION:
Tempo connects to NutriTrack (a companion nutrition app) to display
meal and macro data. This integration is OPTIONAL -- the app functions
without it. If not connected, the Fuel quadrant shows placeholder state.

AI FEATURES (ANTHROPIC CLAUDE API):
Tempo uses Anthropic's Claude API to generate personalized weekly
insight reports, pattern detection, and coaching recommendations.
AI features require EXPLICIT, SEPARATE user consent during onboarding
(dedicated consent screen that names Anthropic and Claude specifically).
The user can decline AI features and use the full app with rule-based
fallback systems. Only anonymized, aggregate health scores are sent
to the API -- no raw HealthKit data, no PII, no names, no emails.
AI consent can be revoked anytime in Settings > Privacy > AI Features.

NOTIFICATIONS:
Tempo sends local notifications for accountability reminders (e.g.,
study targets, workout reminders). These use the drill-sergeant tone
described in the app description. Push notification payloads never
contain health data in the alert body -- only zone-based language
(e.g., "Green recovery" not "78% recovery").

SOCIAL FEATURES:
The Arena module allows users to add friends, compete on leaderboards,
and create challenges. All social features require mutual friend
acceptance. Blocking is fully supported.

SUBSCRIPTIONS:
[If applicable: describe subscription tiers, or state "No in-app
purchases at launch."]
```

### 4.3 What to Expect During Review

| Phase | Timeline | Notes |
|-------|----------|-------|
| Initial submission | 24-48 hours for first response | Health + AI apps may get escalated to a specialist reviewer |
| HealthKit review | May take additional 1-2 days | Specialist reviews HealthKit justifications |
| AI/data sharing review | May require additional questions | Reviewer may ask for clarification on Anthropic data flow |
| Binary inspection | Automated | Checks for private APIs, embedded secrets, deprecated calls |
| Full review | 3-7 business days total | First submission of a new app typically takes longer |

### 4.4 Common Rejection Reasons and How Tempo Avoids Each

| Rejection Reason | How Tempo Avoids It |
|-----------------|-------------------|
| **Missing HealthKit justification** | Every data type justified in App Review Notes (Section 4.2). Each type maps to a specific feature. |
| **App does not work without HealthKit** | Full graceful degradation matrix tested (Section 2.4). App works as manual accountability tracker. |
| **AI data sharing without consent** | Dedicated consent screen names Anthropic/Claude, explains data flow, allows opt-out (Section 1.1). |
| **Health data in push notifications** | Lock-screen-safe copy uses zones not percentages. Exact values in `data` payload only (Section 2.3). |
| **Medical claims without evidence** | All disclaimers in place: "not medical advice", "consult a doctor", "not a medical device" (Section 6). |
| **Missing privacy policy** | Full privacy policy in SECURITY_AND_PRIVACY.md Section 13. URL provided in App Store Connect. |
| **Excessive HealthKit permissions** | Every type justified. No unnecessary types requested. |
| **iCloud storage of health data** | `cloudKitDatabase: .none` enforced at code, CI, and review levels (Section 2.2). |
| **Thin app / minimum functionality** | 5 feature-rich modules, HealthKit integration, AI coaching, social features. |

### 4.5 How to Respond If Rejected

1. **Read the rejection message carefully.** Apple cites specific guidelines. Address EXACTLY what they cite.
2. **Do not argue.** Fix the issue, even if you disagree. You can appeal later.
3. **Respond via Resolution Center** in App Store Connect. Be concise, specific, and show evidence of compliance.
4. **For HealthKit rejections:** Provide screenshots showing each data type in use within the app. Record a screen video if needed.
5. **For AI/consent rejections:** Provide screenshots of the consent flow, the settings toggle, and the fallback behavior.
6. **For privacy rejections:** Provide the privacy policy URL, highlight the relevant section.
7. **Resubmit quickly.** Each rejection adds 1-2 days to the review cycle.
8. **If rejected twice for the same reason:** Request a phone call with the App Review team via the Resolution Center.

---

## 5. In-App Purchase / Subscription Compliance

### 5.1 StoreKit 2 Requirements

If Tempo introduces a premium tier:

- [ ] Use **StoreKit 2** for all purchase flows (no legacy StoreKit 1)
- [ ] Use `Product.purchase()` and `Transaction.currentEntitlements`
- [ ] Server-side receipt validation using Apple's **App Store Server API v2** (not the deprecated `/verifyReceipt`)
- [ ] Handle `Transaction.updates` for server-side status changes
- [ ] Support `AppStore.sync()` for restore purchases

### 5.2 Subscription Disclosure Requirements

Before any purchase screen:
- [ ] Display price, billing period (monthly/yearly)
- [ ] Display free trial duration if applicable (e.g., "7-day free trial, then $X.XX/month")
- [ ] Display auto-renewal terms: "Subscription automatically renews unless cancelled at least 24 hours before the end of the current period."
- [ ] Display that payment will be charged to the Apple ID account at confirmation of purchase

### 5.3 "Manage Subscription" Link

- [ ] Settings screen MUST include a link to Apple's subscription management page
- [ ] Implementation: `URL(string: "https://apps.apple.com/account/subscriptions")`
- [ ] Label: "Manage Subscription" -- clearly visible in Settings, not buried

### 5.4 Restore Purchases

- [ ] "Restore Purchases" button accessible from Settings
- [ ] Must work for users who reinstall the app or switch devices

### 5.5 Free Trial Disclosure

If offering a free trial:
- [ ] Trial duration stated clearly BEFORE the user initiates purchase
- [ ] What happens when the trial ends (auto-converts to paid subscription)
- [ ] How to cancel before being charged
- [ ] Apple requires: "Payment will be charged to your Apple ID account at the confirmation of purchase. Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period."

### 5.6 Price Localization

- [ ] Prices set per-territory in App Store Connect
- [ ] Use `Product.displayPrice` (StoreKit 2) to show localized prices in the app
- [ ] Never hardcode price strings

---

## 6. Content & Safety

### 6.1 Medical Disclaimer Requirements

Tempo gives fitness, nutrition, sleep, and recovery recommendations. These are NOT medical advice.

**Required disclaimers (already in MODULE_RECOVERY.md Section 1):**

1. **General disclaimer:** "Tempo is a wellness and fitness tool, not a medical device. All recovery prescriptions are informational and educational. They do not constitute medical advice, diagnosis, or treatment."

2. **Supplement disclaimer:** "Any mention of dietary supplements is for informational purposes only. These statements have not been evaluated by the FDA. Consult a healthcare provider before starting any supplement regimen."

3. **Wearable data disclaimer:** "Recovery scores, HRV readings, and sleep metrics from Whoop are estimates derived from optical sensor data -- they are not clinical-grade measurements."

**Where disclaimers MUST appear:**
- Recovery module footer (always visible at bottom of Recovery Today View)
- Every PrescriptionCard's "Why this recommendation?" sheet
- Terms of Service Section 12 (Health Disclaimers)
- App Store description (implicit -- "not a medical device")
- Recovery Trends View footer

### 6.2 "Consult a Doctor" Triggers

The app MUST display a persistent advisory banner recommending professional consultation when:

1. Recovery is red (<34%) for 7+ consecutive days
2. Resting heart rate is >10 bpm above 30-day baseline for 3+ consecutive days
3. Sleep duration is <5 hours for 5+ consecutive nights
4. The user cannot complete any prescribed workout for 2+ consecutive weeks

**Banner text:** "Your recovery has been consistently low for [X] days. While this can happen during stressful periods, prolonged patterns like this may warrant a check-in with a doctor or sports medicine professional. This is not an emergency -- just a smart precaution."

This banner persists until the condition resolves or the user dismisses with acknowledgment.

### 6.3 Age Rating Justification

**Recommended rating: 4+**

- No objectionable content
- No user-generated content beyond usernames and challenge names
- No violence, gambling, or mature themes
- Gamification (XP, levels) does not constitute gambling
- Health data display is informational
- "Drill sergeant" tone is motivational, not abusive
- No medical device claims

### 6.4 No Medical Device Claims

The following phrases MUST NEVER appear in the app, marketing, or App Store listing:
- "Diagnose" / "diagnosis"
- "Treat" / "treatment" (when referring to medical conditions)
- "Prescribe" (in a medical context -- "recovery prescription" is acceptable as it is clearly fitness-focused)
- "Cure" / "prevent disease"
- "Medical-grade" / "clinical accuracy"
- "FDA approved" / "FDA cleared"

---

## 7. Specific Rejection Risk Mitigation

### 7.1 Guideline 4.2 -- Minimum Functionality

**Risk: LOW**

Tempo has 5 feature-rich modules (Dashboard, Training, Accountability, Recovery, Arena), HealthKit integration, Whoop OAuth, NutriTrack integration, AI coaching, social features with leaderboards and challenges, and a notification system with 4 intensity levels. This is a substantial, unique app.

**Status: COMPLIANT**

### 7.2 Guideline 4.3 -- Spam

**Risk: NONE**

Tempo is a unique app, not a clone or template. It has custom UI, proprietary algorithms, and original design.

**Status: COMPLIANT**

### 7.3 Guideline 5.1.2(i) -- AI Data Sharing

**Risk: HIGH (if consent flow is missing)**

Mitigations:
- Dedicated consent screen during onboarding (Section 1.1)
- Names Anthropic and Claude explicitly
- Separate from all other permissions
- Opt-out preserves full functionality (Section 1.3)
- Settings toggle to revoke consent (Section 1.4)

**Status: COMPLIANT (when consent flow is implemented per this document)**

### 7.4 Guideline 27.x -- HealthKit

**Risk: MEDIUM (common rejection category for health apps)**

Mitigations:
- Every data type justified in App Review Notes (Section 4.2)
- Graceful degradation for every permission denial (Section 2.4)
- No iCloud storage of health data (Section 2.2)
- No health data in push notification alert bodies (Section 2.3)
- Raw HealthKit samples never leave the device

**Status: COMPLIANT**

### 7.5 Guideline 3.1.1 -- In-App Purchase

**Risk: LOW (only relevant when subscriptions are added)**

Mitigations:
- StoreKit 2 for all purchases
- Subscription terms displayed before purchase
- Manage Subscription link in Settings
- Restore Purchases accessible

**Status: COMPLIANT (pending subscription implementation)**

### 7.6 Guideline 5.1.1 -- Data Collection and Storage

**Risk: LOW**

Mitigations:
- Privacy Nutrition Label accurately reflects all data collection (Section 3.1)
- Privacy policy covers all required disclosures (Section 3.2)
- No tracking, no ad SDKs, no data brokers

**Status: COMPLIANT**

---

## 8. Pre-Submission Checklist

Complete every item before clicking "Submit for Review" in App Store Connect.

### Code & Build

- [ ] App compiles with zero warnings in Release configuration
- [ ] All deprecated API usage removed
- [ ] No private API usage (run `nm` and `strings` on the binary to verify)
- [ ] No API keys, secrets, or tokens embedded in the iOS binary (all keys are backend-only)
- [ ] Minimum deployment target: iOS 17.4
- [ ] App icon provided for all required sizes
- [ ] Launch screen configured (no black screen on cold start)

### HealthKit

- [ ] `com.apple.developer.healthkit` entitlement enabled
- [ ] `com.apple.developer.healthkit.background-delivery` entitlement enabled
- [ ] `NSHealthShareUsageDescription` in Info.plist (read justification)
- [ ] `NSHealthUpdateUsageDescription` in Info.plist (write justification)
- [ ] Every requested HealthKit type has a corresponding feature in the app
- [ ] App functions fully without HealthKit (tested with all permissions denied)
- [ ] App functions with PARTIAL HealthKit permissions (tested with each type individually denied)
- [ ] `cloudKitDatabase: .none` for all health-derived SwiftData models
- [ ] CI test verifies no health model uses `.automatic` or `.private` CloudKit
- [ ] Raw HealthKit samples never leave the device (verified via network proxy)
- [ ] No health data in push notification `alert.body` (verified via payload inspection)

### AI Consent (Guideline 5.1.2(i))

- [ ] Dedicated AI consent screen in onboarding (NOT bundled with other permissions)
- [ ] Consent screen names "Anthropic" and "Claude" explicitly
- [ ] Consent screen lists what data categories are sent
- [ ] Consent screen lists what data is NOT sent (name, email, Apple ID)
- [ ] "Continue without AI" button has equal visual weight to "Enable AI Insights"
- [ ] AI features are OFF by default until user enables them
- [ ] ALL AI features work in fallback mode when consent is declined (full QA pass)
- [ ] Settings > Privacy > AI Features toggle works (enable/disable/re-enable)
- [ ] No data is sent to Anthropic when consent is declined (verified via network proxy)
- [ ] Link to Anthropic's privacy policy is functional
- [ ] Consent timestamp is recorded and stored

### Privacy

- [ ] Privacy Nutrition Label in App Store Connect matches actual data collection
- [ ] Privacy policy URL entered in App Store Connect
- [ ] Privacy policy accessible in-app (Settings > Privacy Policy)
- [ ] Privacy policy shown during onboarding
- [ ] Privacy policy names Anthropic as a data processor
- [ ] GDPR data export works (Settings > Privacy > Export My Data)
- [ ] Account deletion works (Settings > Account > Delete Account, 30-day processing)
- [ ] No `ATTrackingManager` (not needed -- no tracking)
- [ ] PostHog events contain no PII or health values

### App Store Connect

- [ ] App name: "Tempo"
- [ ] Subtitle (30 chars max): "Your Life Operating System"
- [ ] Primary category: Health & Fitness
- [ ] Secondary category: Productivity
- [ ] Age rating: 4+
- [ ] Copyright: correct year and entity
- [ ] App Review Notes filled in (use Section 4.2 verbatim)
- [ ] All 6 screenshots uploaded (6.7" iPhone 15 Pro Max)
- [ ] App description filled in (4000 chars max)
- [ ] Keywords filled in (100 chars max)
- [ ] Support URL provided
- [ ] Privacy policy URL provided
- [ ] Marketing URL provided (if available)

### Subscriptions (if applicable)

- [ ] StoreKit 2 implementation verified
- [ ] Subscription terms displayed before purchase
- [ ] "Manage Subscription" link in Settings
- [ ] "Restore Purchases" button in Settings
- [ ] Price localization using `Product.displayPrice`
- [ ] Free trial terms clearly stated (if applicable)

### Content & Safety

- [ ] Medical disclaimers present in Recovery module footer
- [ ] Medical disclaimers present in every PrescriptionCard "Why?" sheet
- [ ] "Consult a doctor" banner triggers for persistent red recovery (7+ days)
- [ ] No medical device claims anywhere in the app or listing
- [ ] Savage Mode disclaimer shown during onboarding intensity selection
- [ ] No notification copy references mental health conditions, eating disorders, or self-harm
- [ ] Auto-softening to Gentle Coach when completion rate < 25% for 7+ days

### Testing

- [ ] Full QA pass with all integrations connected
- [ ] Full QA pass with all integrations denied/disconnected
- [ ] Full QA pass with AI consent declined
- [ ] Full QA pass with partial HealthKit permissions
- [ ] Push notification payload inspection (no health data in `alert.body`)
- [ ] Network proxy test: verify no PII sent to Anthropic
- [ ] Crash-free rate > 99% over last 100 sessions
- [ ] Memory usage within acceptable limits on oldest supported device (iPhone XS)

### Legal

- [ ] Privacy policy reviewed by legal counsel (recommended)
- [ ] Terms of Service reviewed
- [ ] Anthropic Data Processing Agreement signed
- [ ] Whoop API terms compliance verified
- [ ] NutriTrack API terms compliance verified

---

*This document is the authoritative pre-submission compliance reference for Tempo. Every item must be verified before submitting to the App Store. An App Store rejection costs a minimum of 1-2 weeks of delay.*
