# Tempo Documentation Suite -- Master Index

> **Version:** 1.0
> **Created:** 2026-03-24
> **Maintainer:** Nicola Debbia
> **Purpose:** Single entry point to all Tempo documentation. Open this first.

---

## 1. Documentation Overview

### At a Glance

| Metric | Value |
|--------|-------|
| **Total documents** | 20 (19 specification docs + this index) |
| **Total lines** | ~58,300 across all specification docs |
| **Total file size** | ~2.6 MB of Markdown |
| **Created** | 2026-03-24 (all documents, version 1.0) |
| **Stack covered** | iOS (SwiftUI/SwiftData), Vapor backend (Swift), PostgreSQL, Redis, Claude AI, Whoop API, HealthKit, EventKit |

### What This Documentation Covers

| Domain | Documents | Scope |
|--------|-----------|-------|
| **Product / UX** | 5 module specs, onboarding, sound/haptics | Every screen, every interaction, every edge case for all 5 Tempo modules |
| **Design** | Design system, accessibility | Complete visual language -- colors, typography, spacing, motion, components |
| **Engineering** | Data models, backend API, integrations, performance, testing | Full implementation specs -- Swift models, REST endpoints, sync architecture, optimization targets |
| **AI / Intelligence** | AI engine spec | Claude API integration, prompt templates, cost management, caching |
| **Business** | Monetization, analytics | Market analysis, pricing, App Store strategy, event tracking, funnel definitions |
| **Quality** | Testing, security/privacy, cross-doc audit, accessibility | Testing pyramid, GDPR/HIPAA compliance, penetration testing, WCAG 2.2 AA |
| **Platform** | Apple Watch app | WatchOS companion -- complications, workout logging, haptics, communication |

### How to Use This Documentation

Each document is designed to be **self-contained**: a developer should be able to implement the feature described in any single doc without asking questions. However, documents reference each other heavily. Use the Cross-Reference Table (Section 4) and Quick Links (Section 5) to navigate dependencies.

**Important:** The CROSS_DOC_AUDIT.md documents 47 known inconsistencies between docs. Before implementing any feature that touches multiple documents, check the audit for conflicts in that area.

---

## 2. Reading Order by Role

### Solo Developer (Nicola) -- Full Context Build

| Order | Document | Why |
|-------|----------|-----|
| 1 | DESIGN_SYSTEM.md | Establishes every visual token -- all modules reference these |
| 2 | DATA_MODELS_IOS.md | The data layer everything is built on |
| 3 | BACKEND_API.md | Server-side contracts the app talks to |
| 4 | INTEGRATION_SPECS.md | How Whoop, HealthKit, NutriTrack, and Calendar connect |
| 5 | MODULE_DASHBOARD.md | The home screen -- ties all modules together |
| 6 | MODULE_RECOVERY.md | Whoop-powered recovery prescriptions (feeds into training) |
| 7 | MODULE_TRAINING.md | Workout system -- depends on recovery data |
| 8 | MODULE_ACCOUNTABILITY.md | Daily non-negotiables and drill-sergeant notifications |
| 9 | MODULE_ARENA.md | XP, leaderboards, social gamification |
| 10 | AI_INTELLIGENCE_ENGINE.md | Claude API for insights, coaching, and content generation |
| 11 | ONBOARDING_AND_NOTIFICATIONS.md | First-run experience and push notification system |
| 12 | SOUND_AND_HAPTICS.md | Audio-haptic feedback layer |
| 13 | APPLE_WATCH_APP.md | WatchOS companion |
| 14 | PERFORMANCE_OPTIMIZATION.md | Performance budgets and profiling |
| 15 | TESTING_STRATEGY.md | Test architecture and CI/CD |
| 16 | SECURITY_AND_PRIVACY.md | Compliance, encryption, App Store review prep |
| 17 | ACCESSIBILITY.md | WCAG 2.2 AA, VoiceOver, Dynamic Type |
| 18 | ANALYTICS_AND_METRICS.md | Event tracking, funnels, PostHog setup |
| 19 | MONETIZATION_STRATEGY.md | Pricing, paywall, go-to-market |
| 20 | CROSS_DOC_AUDIT.md | Known inconsistencies to resolve before shipping |

### New iOS Developer Joining

| Order | Document | Why |
|-------|----------|-----|
| 1 | DESIGN_SYSTEM.md | Visual language and component library |
| 2 | DATA_MODELS_IOS.md | SwiftData models, query patterns, migrations |
| 3 | MODULE_DASHBOARD.md | Start with the home screen to understand app structure |
| 4 | PERFORMANCE_OPTIMIZATION.md | SwiftUI and SwiftData optimization patterns |
| 5 | TESTING_STRATEGY.md | Unit/integration/UI test expectations |
| 6 | ACCESSIBILITY.md | VoiceOver, Dynamic Type -- quality standards |
| 7 | Then: whichever module you are assigned (RECOVERY, TRAINING, ACCOUNTABILITY, ARENA) |
| 8 | INTEGRATION_SPECS.md | When working on Whoop/HealthKit/NutriTrack features |
| 9 | CROSS_DOC_AUDIT.md | Before implementing any cross-module feature |

### New Backend Developer Joining

| Order | Document | Why |
|-------|----------|-----|
| 1 | BACKEND_API.md | Vapor routes, database schema, caching, auth, deployment |
| 2 | DATA_MODELS_IOS.md | Understand the client-side models the API serves |
| 3 | INTEGRATION_SPECS.md | Whoop OAuth proxy, NutriTrack proxy, sync architecture |
| 4 | SECURITY_AND_PRIVACY.md | Auth, encryption, GDPR, API security |
| 5 | AI_INTELLIGENCE_ENGINE.md | Claude API integration (backend routes AI requests) |
| 6 | TESTING_STRATEGY.md | Vapor unit/integration test patterns |
| 7 | PERFORMANCE_OPTIMIZATION.md | Backend performance targets and caching |
| 8 | ANALYTICS_AND_METRICS.md | Server-side event tracking |

### Designer Reviewing

| Order | Document | Why |
|-------|----------|-----|
| 1 | DESIGN_SYSTEM.md | The single source of truth for all visual decisions |
| 2 | SOUND_AND_HAPTICS.md | Audio-haptic identity and interaction feedback |
| 3 | MODULE_DASHBOARD.md | Home screen layout and quadrant design |
| 4 | MODULE_ARENA.md | Gamification UX, XP animations, leaderboard design |
| 5 | MODULE_ACCOUNTABILITY.md | Drill-sergeant personality, notification UX |
| 6 | ONBOARDING_AND_NOTIFICATIONS.md | First-run flow and notification copy |
| 7 | ACCESSIBILITY.md | Color contrast, Dynamic Type, motion reduction |
| 8 | APPLE_WATCH_APP.md | Wrist-optimized design constraints |
| 9 | CROSS_DOC_AUDIT.md | Known color/spacing/animation conflicts |

### Investor / Stakeholder

| Order | Document | Why |
|-------|----------|-----|
| 1 | MONETIZATION_STRATEGY.md | Market analysis, pricing, revenue projections, go-to-market |
| 2 | ANALYTICS_AND_METRICS.md | KPIs, funnels, cohort analysis, retention metrics |
| 3 | MODULE_DASHBOARD.md (Sections 1-5 only) | Product overview via the home screen |
| 4 | MODULE_ARENA.md (Sections 1-4 only) | Social/viral mechanics and retention strategy |
| 5 | AI_INTELLIGENCE_ENGINE.md (Section 1 only) | AI feature overview |
| 6 | SECURITY_AND_PRIVACY.md (Sections 1-3 only) | Compliance posture |

---

## 3. Document Directory

### Core Architecture

#### DESIGN_SYSTEM.md
- **Path:** `docs/DESIGN_SYSTEM.md`
- **Description:** Single source of truth for every visual element -- colors, typography, spacing, elevation, icons, components, motion, dark mode.
- **Tags:** `colors` `typography` `spacing` `elevation` `icons` `components` `animation` `motion` `dark-mode` `layout-grid` `touch-feedback` `loading-states` `error-states`
- **Lines:** ~3,280
- **Dependencies:** None (this is the root design reference)
- **Status:** Complete

#### DATA_MODELS_IOS.md
- **Path:** `docs/DATA_MODELS_IOS.md`
- **Description:** Complete SwiftData model definitions, enums, query patterns, indexes, sync conflict resolution, migrations, and thread safety.
- **Tags:** `SwiftData` `models` `enums` `schema` `queries` `indexes` `sync` `migrations` `thread-safety` `ModelContainer`
- **Lines:** ~4,786
- **Dependencies:** None (foundational)
- **Status:** Complete

#### BACKEND_API.md
- **Path:** `docs/BACKEND_API.md`
- **Description:** Full Vapor backend specification -- REST endpoints, authentication, database schema, caching, WebSocket, background jobs, deployment, load testing.
- **Tags:** `Vapor` `REST` `PostgreSQL` `Redis` `JWT` `OAuth` `WebSocket` `APNs` `deployment` `migrations` `rate-limiting` `error-codes`
- **Lines:** ~4,576
- **Dependencies:** DATA_MODELS_IOS.md (client-side model counterparts)
- **Status:** Complete

#### INTEGRATION_SPECS.md
- **Path:** `docs/INTEGRATION_SPECS.md`
- **Description:** Every detail of data flow between Tempo and external systems: Whoop API (OAuth2), Apple HealthKit, NutriTrack (Flask proxy), Apple Calendar (EventKit).
- **Tags:** `Whoop` `OAuth2` `HealthKit` `NutriTrack` `EventKit` `sync` `background-refresh` `error-handling` `Swift-implementation`
- **Lines:** ~3,785
- **Dependencies:** BACKEND_API.md (proxy routes), DATA_MODELS_IOS.md (storage models)
- **Status:** Complete

### Module Specifications

#### MODULE_DASHBOARD.md
- **Path:** `docs/MODULE_DASHBOARD.md`
- **Description:** LifeOS home screen -- 4-quadrant view (Body/Fuel/Mind/Move), weekly reports, pattern detection, daily timeline, widgets, AI insights, drill-sergeant voice.
- **Tags:** `dashboard` `quadrants` `daily-score` `weekly-report` `AI-insights` `widgets` `deep-links` `offline-mode` `first-time-UX`
- **Lines:** ~2,631
- **Dependencies:** DESIGN_SYSTEM.md, DATA_MODELS_IOS.md, AI_INTELLIGENCE_ENGINE.md
- **Status:** Complete

#### MODULE_RECOVERY.md
- **Path:** `docs/MODULE_RECOVERY.md`
- **Description:** RecoverIQ module -- Whoop-powered recovery prescriptions, sleep/strain detail, trends, prescription algorithm, historical comparison.
- **Tags:** `recovery` `Whoop` `HRV` `RHR` `sleep` `strain` `prescription-engine` `recovery-zones` `trends` `notifications`
- **Lines:** ~2,546
- **Dependencies:** DESIGN_SYSTEM.md, INTEGRATION_SPECS.md (Whoop data), DATA_MODELS_IOS.md
- **Status:** Complete

#### MODULE_TRAINING.md
- **Path:** `docs/MODULE_TRAINING.md`
- **Description:** RepForge training module -- workout views, weight input, plate calculator, supersets, rest timer, exercise library (150+), progress charts, personal records, running/cardio, workout generation algorithm, progressive overload, recovery-based adjustments, football integration, deload weeks.
- **Tags:** `training` `workouts` `exercises` `1RM` `RPE` `progressive-overload` `deload` `rest-timer` `plate-calculator` `personal-records` `running` `football` `recovery-adjustment`
- **Lines:** ~5,116 (largest document)
- **Dependencies:** DESIGN_SYSTEM.md, MODULE_RECOVERY.md (recovery adjustments), DATA_MODELS_IOS.md, INTEGRATION_SPECS.md (HealthKit)
- **Status:** Complete

#### MODULE_ACCOUNTABILITY.md
- **Path:** `docs/MODULE_ACCOUNTABILITY.md`
- **Description:** Lockdown module -- daily non-negotiables, focus timer (Pomodoro), streak system, escalating notification system, drill-sergeant personality, weekend/exam modes, rest/sick day handling, weekly/monthly reviews.
- **Tags:** `non-negotiables` `focus-timer` `Pomodoro` `streaks` `drill-sergeant` `notifications` `weekend-mode` `exam-mode` `rest-day` `behavioral-psychology` `unlock-system`
- **Lines:** ~3,429
- **Dependencies:** DESIGN_SYSTEM.md, DATA_MODELS_IOS.md, ONBOARDING_AND_NOTIFICATIONS.md (notification system)
- **Status:** Complete

#### MODULE_ARENA.md
- **Path:** `docs/MODULE_ARENA.md`
- **Description:** ClutchTime arena -- XP economy (full simulation), level system, streaks, leaderboards, friends, challenges, achievements (108), social feed, anti-cheat, retention mechanics, league system, seasonal events.
- **Tags:** `XP` `levels` `streaks` `leaderboards` `friends` `challenges` `achievements` `badges` `social-feed` `anti-cheat` `leagues` `retention` `confetti` `gamification`
- **Lines:** ~4,144
- **Dependencies:** DESIGN_SYSTEM.md, DATA_MODELS_IOS.md, BACKEND_API.md (social endpoints), SOUND_AND_HAPTICS.md (celebration sounds)
- **Status:** Complete

### AI and Intelligence

#### AI_INTELLIGENCE_ENGINE.md
- **Path:** `docs/AI_INTELLIGENCE_ENGINE.md`
- **Description:** CortexAI engine -- all AI-powered features, Claude API configuration (Haiku 3.5 + Sonnet 4), prompt templates, data pipeline, cost management, caching, quality assurance, offline fallback, privacy.
- **Tags:** `Claude-API` `Haiku` `Sonnet` `prompts` `AI-coaching` `morning-briefing` `weekly-report` `pattern-detection` `cost-management` `caching` `offline-fallback`
- **Lines:** ~2,253
- **Dependencies:** BACKEND_API.md (AI routes), MODULE_DASHBOARD.md (where insights display), MODULE_RECOVERY.md (data source)
- **Status:** Complete

### Onboarding and Notifications

#### ONBOARDING_AND_NOTIFICATIONS.md
- **Path:** `docs/ONBOARDING_AND_NOTIFICATIONS.md`
- **Description:** Complete onboarding flow (App Store listing through first week hour-by-hour), push notification architecture, all notification channels with full copy bank (4 intensity levels), timing engine, re-engagement sequences, localization.
- **Tags:** `onboarding` `App-Store` `ASO` `notifications` `APNs` `push` `copy-bank` `intensity-levels` `timing-engine` `re-engagement` `first-week` `localization`
- **Lines:** ~4,577
- **Dependencies:** MODULE_ACCOUNTABILITY.md (drill-sergeant copy), BACKEND_API.md (push infrastructure)
- **Status:** Complete

### Platform Extensions

#### APPLE_WATCH_APP.md
- **Path:** `docs/APPLE_WATCH_APP.md`
- **Description:** WatchOS companion app -- complications, watch screens, haptics, Watch-iPhone communication (WatchConnectivity), performance targets, live activities, workout logging from wrist.
- **Tags:** `Apple-Watch` `WatchOS` `complications` `WatchConnectivity` `haptics` `live-activities` `workout-logging` `rest-timer`
- **Lines:** ~1,604
- **Dependencies:** MODULE_TRAINING.md (workout logging), MODULE_ACCOUNTABILITY.md (non-negotiable check-off), SOUND_AND_HAPTICS.md
- **Status:** Complete

### Quality and Polish

#### SOUND_AND_HAPTICS.md
- **Path:** `docs/SOUND_AND_HAPTICS.md`
- **Description:** Complete sound design and haptic specification -- sonic brand identity, sound effect catalog, ambient sound library, haptic catalog, AHAP patterns, audio-haptic sync, sound settings.
- **Tags:** `sound` `haptics` `AHAP` `Core-Haptics` `audio-identity` `ambient` `sync` `sound-settings`
- **Lines:** ~2,115
- **Dependencies:** DESIGN_SYSTEM.md (brand personality alignment)
- **Status:** Complete

#### ACCESSIBILITY.md
- **Path:** `docs/ACCESSIBILITY.md`
- **Description:** WCAG 2.2 AA compliance -- VoiceOver screen-by-screen audit, Dynamic Type, color accessibility, motor accessibility, Switch Control, Reduce Motion, cognitive accessibility, testing checklist.
- **Tags:** `WCAG` `VoiceOver` `Dynamic-Type` `Switch-Control` `Voice-Control` `Reduce-Motion` `color-contrast` `motor-accessibility` `Braille` `localization`
- **Lines:** ~1,748
- **Dependencies:** DESIGN_SYSTEM.md (color contrast values), all module docs (screen-by-screen audit references every module)
- **Status:** Complete

#### PERFORMANCE_OPTIMIZATION.md
- **Path:** `docs/PERFORMANCE_OPTIMIZATION.md`
- **Description:** Performance budgets and optimization -- app launch, SwiftUI rendering, SwiftData queries, network, HealthKit, chart rendering, timer performance, app size, profiling playbook, regression testing.
- **Tags:** `performance` `budgets` `SwiftUI` `SwiftData` `Instruments` `profiling` `app-size` `launch-time` `chart-rendering` `network`
- **Lines:** ~2,656
- **Dependencies:** DATA_MODELS_IOS.md (query optimization), BACKEND_API.md (network targets)
- **Status:** Complete

#### TESTING_STRATEGY.md
- **Path:** `docs/TESTING_STRATEGY.md`
- **Description:** Testing pyramid -- unit tests (iOS + Vapor), integration tests, XCUITest, snapshot tests, performance tests, API contract tests, edge case tests, accessibility tests, CI/CD pipeline, test data and mocks.
- **Tags:** `unit-tests` `integration-tests` `XCUITest` `snapshot-tests` `performance-tests` `CI-CD` `mocks` `test-data` `edge-cases`
- **Lines:** ~1,209
- **Dependencies:** DATA_MODELS_IOS.md, BACKEND_API.md (API contract tests)
- **Status:** Complete

#### SECURITY_AND_PRIVACY.md
- **Path:** `docs/SECURITY_AND_PRIVACY.md`
- **Description:** Security and compliance -- App Store review checklist, HealthKit compliance, data classification, authentication, encryption, API security, GDPR, social features security, incident response, penetration testing, privacy policy, terms of service.
- **Tags:** `security` `privacy` `GDPR` `HealthKit-compliance` `App-Store-review` `encryption` `JWT` `OAuth` `OWASP` `incident-response` `penetration-testing` `privacy-policy` `terms-of-service`
- **Lines:** ~2,087
- **Dependencies:** BACKEND_API.md (auth implementation), INTEGRATION_SPECS.md (third-party security)
- **Status:** Complete

### Business and Growth

#### MONETIZATION_STRATEGY.md
- **Path:** `docs/MONETIZATION_STRATEGY.md`
- **Description:** Business strategy -- competitive landscape (14 competitors analyzed), monetization models, free vs premium feature split, paywall design, StoreKit 2 subscription infrastructure, revenue projections, cost structure, go-to-market, growth levers, retention, legal.
- **Tags:** `monetization` `pricing` `StoreKit` `subscriptions` `paywall` `revenue` `competitors` `go-to-market` `retention` `growth` `legal`
- **Lines:** ~1,257
- **Dependencies:** ANALYTICS_AND_METRICS.md (conversion funnels)
- **Status:** Complete

#### ANALYTICS_AND_METRICS.md
- **Path:** `docs/ANALYTICS_AND_METRICS.md`
- **Description:** Analytics instrumentation -- PostHog architecture, core KPIs, complete event catalog, funnel definitions, cohort analysis, A/B testing framework, metrics dashboard, user segmentation, privacy compliance for analytics.
- **Tags:** `PostHog` `analytics` `KPIs` `events` `funnels` `cohorts` `A/B-testing` `segmentation` `retention` `Firebase-Crashlytics`
- **Lines:** ~3,831
- **Dependencies:** MONETIZATION_STRATEGY.md (business metrics alignment), SECURITY_AND_PRIVACY.md (analytics privacy)
- **Status:** Complete

### Meta / Audit

#### CROSS_DOC_AUDIT.md
- **Path:** `docs/CROSS_DOC_AUDIT.md`
- **Description:** Cross-document consistency audit -- 47 issues found (12 critical, 19 major, 16 minor). Covers color hex conflicts, token naming mismatches, missing fields, boundary ambiguities, notification tier conflicts, animation duration conflicts.
- **Tags:** `audit` `conflicts` `inconsistencies` `color-hex` `tokens` `boundaries` `notifications` `animations` `spacing`
- **Lines:** ~707
- **Dependencies:** All other documents (this audits the entire suite)
- **Status:** Complete

---

## 4. Cross-Reference Table

This table maps key concepts to every document where they are defined, specified, or referenced. The **primary** document is listed first in bold.

| Concept | Primary Document | Also Referenced In |
|---------|------------------|--------------------|
| **Recovery zones** (green/yellow/red) | **MODULE_RECOVERY.md** (algorithm, thresholds, prescriptions) | DESIGN_SYSTEM.md (color tokens), MODULE_TRAINING.md (workout adjustments), MODULE_DASHBOARD.md (quadrant display), AI_INTELLIGENCE_ENGINE.md (prompt context), DATA_MODELS_IOS.md (RecoveryZone enum), CROSS_DOC_AUDIT.md (boundary conflicts) |
| **Recovery zone colors** | **DESIGN_SYSTEM.md** (hex values, tokens) | MODULE_RECOVERY.md (usage), MODULE_DASHBOARD.md (quadrant colors), CROSS_DOC_AUDIT.md (5 conflicting definitions) |
| **XP system** | **MODULE_ARENA.md** (economy, simulation, sinks, spending) | BACKEND_API.md (XP endpoints), DATA_MODELS_IOS.md (XPTransaction model), ANALYTICS_AND_METRICS.md (XP events), MODULE_ACCOUNTABILITY.md (XP for non-negotiables), MODULE_TRAINING.md (XP for workouts), SOUND_AND_HAPTICS.md (XP gain sounds) |
| **Non-negotiables** | **MODULE_ACCOUNTABILITY.md** (full UX, setup, streaks, overrides) | DATA_MODELS_IOS.md (NonNegotiable model), BACKEND_API.md (CRUD endpoints), ONBOARDING_AND_NOTIFICATIONS.md (setup during onboarding), APPLE_WATCH_APP.md (quick check-off), MODULE_DASHBOARD.md (Mind quadrant) |
| **Whoop integration** | **INTEGRATION_SPECS.md** (OAuth2 flow, data sync, error handling) | MODULE_RECOVERY.md (data consumption), BACKEND_API.md (proxy routes, token storage), DATA_MODELS_IOS.md (WhoopSyncState model), SECURITY_AND_PRIVACY.md (third-party security), ONBOARDING_AND_NOTIFICATIONS.md (connection onboarding) |
| **HealthKit integration** | **INTEGRATION_SPECS.md** (permissions, queries, background delivery) | MODULE_RECOVERY.md (fallback when no Whoop), APPLE_WATCH_APP.md (Watch HealthKit), PERFORMANCE_OPTIMIZATION.md (query optimization), SECURITY_AND_PRIVACY.md (HealthKit compliance), DATA_MODELS_IOS.md (HealthKit-derived fields) |
| **NutriTrack integration** | **INTEGRATION_SPECS.md** (Flask proxy, PIN auth, caching) | BACKEND_API.md (proxy endpoints), MODULE_DASHBOARD.md (Fuel quadrant), AI_INTELLIGENCE_ENGINE.md (meal timing recommendations), MONETIZATION_STRATEGY.md (cross-product value) |
| **Daily score / DailySnapshot** | **DATA_MODELS_IOS.md** (model definition, fields) | MODULE_DASHBOARD.md (display logic), BACKEND_API.md (snapshot endpoints), AI_INTELLIGENCE_ENGINE.md (input to analysis), ANALYTICS_AND_METRICS.md (daily score events), CROSS_DOC_AUDIT.md (missing fields issue) |
| **Drill-sergeant personality** | **MODULE_ACCOUNTABILITY.md** (tone, copy, escalation) | ONBOARDING_AND_NOTIFICATIONS.md (notification copy bank), AI_INTELLIGENCE_ENGINE.md (Haiku generates copy), MODULE_DASHBOARD.md (voice system), DESIGN_SYSTEM.md (voice and tone) |
| **Streaks** | **MODULE_ARENA.md** (streak system, freeze, recovery) | MODULE_ACCOUNTABILITY.md (non-negotiable streaks), DATA_MODELS_IOS.md (streak fields), ANALYTICS_AND_METRICS.md (streak events), ONBOARDING_AND_NOTIFICATIONS.md (streak notifications), TESTING_STRATEGY.md (streak boundary tests) |
| **Leaderboards / leagues** | **MODULE_ARENA.md** (league system, ranking, psychology) | BACKEND_API.md (leaderboard endpoints), APPLE_WATCH_APP.md (position display), ANALYTICS_AND_METRICS.md (social events), SECURITY_AND_PRIVACY.md (social features security) |
| **Challenges** | **MODULE_ARENA.md** (templates, seasonal events, design) | BACKEND_API.md (challenge endpoints), DATA_MODELS_IOS.md (Challenge model), ONBOARDING_AND_NOTIFICATIONS.md (challenge notifications), APPLE_WATCH_APP.md (status badge) |
| **Achievements / badges** | **MODULE_ARENA.md** (108 achievements, unlock conditions) | DATA_MODELS_IOS.md (Achievement model), SOUND_AND_HAPTICS.md (unlock sounds), ANALYTICS_AND_METRICS.md (achievement events), AI_INTELLIGENCE_ENGINE.md (celebration copy) |
| **Focus timer / Pomodoro** | **MODULE_ACCOUNTABILITY.md** (timer UX, settings) | APPLE_WATCH_APP.md (wrist timer), SOUND_AND_HAPTICS.md (timer sounds), PERFORMANCE_OPTIMIZATION.md (timer accuracy), DATA_MODELS_IOS.md (FocusSession model) |
| **Workout logging** | **MODULE_TRAINING.md** (active workout, weight input, sets/reps) | APPLE_WATCH_APP.md (wrist logging -- primary gym UX), DATA_MODELS_IOS.md (WorkoutPlan, PlannedSet), BACKEND_API.md (workout endpoints), SOUND_AND_HAPTICS.md (set completion sounds) |
| **Progressive overload** | **MODULE_TRAINING.md** (algorithm, logic) | AI_INTELLIGENCE_ENGINE.md (AI-generated programs), DATA_MODELS_IOS.md (ExerciseHistory), TESTING_STRATEGY.md (algorithm tests) |
| **Rest timer** | **MODULE_TRAINING.md** (system, UX, auto-start) | APPLE_WATCH_APP.md (primary wrist use case), SOUND_AND_HAPTICS.md (timer sounds, haptics), PERFORMANCE_OPTIMIZATION.md (timer accuracy) |
| **Personal records (PR)** | **MODULE_TRAINING.md** (PR system, detection, display) | SOUND_AND_HAPTICS.md (PR celebration), MODULE_ARENA.md (XP for PRs), DATA_MODELS_IOS.md (PR fields), CROSS_DOC_AUDIT.md (confetti duration conflict) |
| **Workout generation algorithm** | **MODULE_TRAINING.md** (algorithm, recovery-based adjustments) | AI_INTELLIGENCE_ENGINE.md (Sonnet 4 for program generation), MODULE_RECOVERY.md (recovery data input), INTEGRATION_SPECS.md (HealthKit/Whoop data) |
| **Football schedule integration** | **MODULE_TRAINING.md** (match days, training around football) | INTEGRATION_SPECS.md (EventKit calendar), AI_INTELLIGENCE_ENGINE.md (schedule optimization), DATA_MODELS_IOS.md (calendar models) |
| **Deload weeks** | **MODULE_TRAINING.md** (deload specification, triggers) | AI_INTELLIGENCE_ENGINE.md (AI-triggered deload), MODULE_RECOVERY.md (recovery-triggered deload) |
| **Exercise library** | **MODULE_TRAINING.md** (150+ exercises, muscle groups) | DATA_MODELS_IOS.md (Exercise model), BACKEND_API.md (exercise endpoints) |
| **Morning briefing** | **AI_INTELLIGENCE_ENGINE.md** (generation, prompt, model) | MODULE_DASHBOARD.md (display), ONBOARDING_AND_NOTIFICATIONS.md (notification), ANALYTICS_AND_METRICS.md (engagement event) |
| **Weekly report** | **AI_INTELLIGENCE_ENGINE.md** (Sonnet 4 analysis) | MODULE_DASHBOARD.md (report view), ONBOARDING_AND_NOTIFICATIONS.md (Sunday notification), ANALYTICS_AND_METRICS.md (report events) |
| **Pattern / correlation detection** | **AI_INTELLIGENCE_ENGINE.md** (algorithm, prompt) | MODULE_DASHBOARD.md (pattern view), ANALYTICS_AND_METRICS.md (insight events) |
| **Claude API (Haiku / Sonnet)** | **AI_INTELLIGENCE_ENGINE.md** (configuration, cost, caching) | BACKEND_API.md (AI proxy routes), SECURITY_AND_PRIVACY.md (data sent to Claude), PERFORMANCE_OPTIMIZATION.md (response times) |
| **Onboarding flow** | **ONBOARDING_AND_NOTIFICATIONS.md** (step-by-step screens) | ANALYTICS_AND_METRICS.md (onboarding funnel), MODULE_ARENA.md (competitive onboarding), MONETIZATION_STRATEGY.md (paywall placement) |
| **Push notifications / APNs** | **ONBOARDING_AND_NOTIFICATIONS.md** (architecture, channels, copy) | BACKEND_API.md (push infrastructure), MODULE_ACCOUNTABILITY.md (escalation notifications), SECURITY_AND_PRIVACY.md (notification security), APPLE_WATCH_APP.md (watch notifications) |
| **Notification intensity levels** | **ONBOARDING_AND_NOTIFICATIONS.md** (4 tiers, copy bank) | MODULE_ACCOUNTABILITY.md (escalation), CROSS_DOC_AUDIT.md (3 vs 4 tier conflict) |
| **Design tokens** | **DESIGN_SYSTEM.md** (complete token architecture) | All module docs (local color palettes), CROSS_DOC_AUDIT.md (naming mismatches) |
| **Typography scale** | **DESIGN_SYSTEM.md** (sizes, weights, line heights) | MODULE_DASHBOARD.md (score display), ACCESSIBILITY.md (Dynamic Type), CROSS_DOC_AUDIT.md (conflicts) |
| **Animation / motion** | **DESIGN_SYSTEM.md** (curves, durations, choreography) | MODULE_ARENA.md (XP animations, confetti), SOUND_AND_HAPTICS.md (audio-haptic sync), ACCESSIBILITY.md (Reduce Motion), CROSS_DOC_AUDIT.md (duration conflicts) |
| **Components (buttons, cards, etc.)** | **DESIGN_SYSTEM.md** (component library) | All module docs (usage), ACCESSIBILITY.md (VoiceOver labels) |
| **Haptic patterns** | **SOUND_AND_HAPTICS.md** (AHAP files, catalog) | APPLE_WATCH_APP.md (watch haptics), DESIGN_SYSTEM.md (touch feedback), CROSS_DOC_AUDIT.md (pattern conflicts) |
| **Paywall / subscriptions** | **MONETIZATION_STRATEGY.md** (paywall design, StoreKit 2) | ONBOARDING_AND_NOTIFICATIONS.md (paywall placement), ANALYTICS_AND_METRICS.md (conversion funnel), SECURITY_AND_PRIVACY.md (IAP compliance) |
| **Free vs premium split** | **MONETIZATION_STRATEGY.md** (feature gating) | ANALYTICS_AND_METRICS.md (segmentation), MODULE_ARENA.md (premium features), MODULE_TRAINING.md (premium features) |
| **PostHog analytics** | **ANALYTICS_AND_METRICS.md** (architecture, SDK, events) | SECURITY_AND_PRIVACY.md (analytics privacy), PERFORMANCE_OPTIMIZATION.md (SDK overhead) |
| **Event tracking catalog** | **ANALYTICS_AND_METRICS.md** (complete event list) | TESTING_STRATEGY.md (event validation tests) |
| **A/B testing** | **ANALYTICS_AND_METRICS.md** (framework, feature flags) | ONBOARDING_AND_NOTIFICATIONS.md (onboarding experiments), MONETIZATION_STRATEGY.md (paywall experiments) |
| **App Store review** | **SECURITY_AND_PRIVACY.md** (compliance checklist) | MONETIZATION_STRATEGY.md (IAP guidelines), ONBOARDING_AND_NOTIFICATIONS.md (App Store listing) |
| **GDPR compliance** | **SECURITY_AND_PRIVACY.md** (full GDPR spec) | ANALYTICS_AND_METRICS.md (analytics privacy), BACKEND_API.md (data export/deletion endpoints) |
| **JWT authentication** | **SECURITY_AND_PRIVACY.md** (token security) | BACKEND_API.md (auth implementation), INTEGRATION_SPECS.md (token refresh) |
| **Sign in with Apple** | **SECURITY_AND_PRIVACY.md** (authentication) | BACKEND_API.md (auth endpoint), ONBOARDING_AND_NOTIFICATIONS.md (onboarding step) |
| **Watch complications** | **APPLE_WATCH_APP.md** (types, data, refresh) | MODULE_DASHBOARD.md (data source), DESIGN_SYSTEM.md (complication colors) |
| **Live Activities** | **APPLE_WATCH_APP.md** (watch live activities) | MODULE_TRAINING.md (workout live activity), MODULE_ACCOUNTABILITY.md (focus timer live activity) |
| **VoiceOver** | **ACCESSIBILITY.md** (screen-by-screen audit) | All module docs (accessibility labels), TESTING_STRATEGY.md (accessibility tests) |
| **Dynamic Type** | **ACCESSIBILITY.md** (AX1-AX5 sizing) | DESIGN_SYSTEM.md (typography scale), PERFORMANCE_OPTIMIZATION.md (layout recalculation) |
| **Performance budgets** | **PERFORMANCE_OPTIMIZATION.md** (exact targets) | MODULE_DASHBOARD.md (dashboard budget), TESTING_STRATEGY.md (performance regression tests) |
| **SwiftData optimization** | **PERFORMANCE_OPTIMIZATION.md** (query patterns, batch ops) | DATA_MODELS_IOS.md (indexes), TESTING_STRATEGY.md (performance tests) |
| **CI/CD pipeline** | **TESTING_STRATEGY.md** (pipeline definition) | PERFORMANCE_OPTIMIZATION.md (regression testing), SECURITY_AND_PRIVACY.md (security scanning) |
| **Weekend mode** | **MODULE_ACCOUNTABILITY.md** (relaxed schedule) | ONBOARDING_AND_NOTIFICATIONS.md (notification adjustments), AI_INTELLIGENCE_ENGINE.md (schedule awareness) |
| **Exam mode** | **MODULE_ACCOUNTABILITY.md** (study-focused mode) | AI_INTELLIGENCE_ENGINE.md (study schedule optimization), MODULE_TRAINING.md (reduced volume) |
| **Sync / offline** | **DATA_MODELS_IOS.md** (sync models, conflict resolution) | BACKEND_API.md (batch sync endpoints), INTEGRATION_SPECS.md (sync architecture), MODULE_DASHBOARD.md (stale data handling) |

---

## 5. Quick Links by Feature

For each feature you are building, read these documents in the listed order.

### Dashboard (LifeOS Home Screen)
1. DESIGN_SYSTEM.md -- visual tokens and components
2. DATA_MODELS_IOS.md -- DailySnapshot, quadrant models
3. MODULE_DASHBOARD.md -- complete screen spec
4. AI_INTELLIGENCE_ENGINE.md -- morning briefing, insights
5. PERFORMANCE_OPTIMIZATION.md -- dashboard performance budget

### Training Module (RepForge)
1. MODULE_TRAINING.md -- all screens, algorithms, exercise library
2. MODULE_RECOVERY.md -- recovery-based workout adjustments
3. DATA_MODELS_IOS.md -- WorkoutPlan, Exercise, PlannedSet models
4. INTEGRATION_SPECS.md -- HealthKit workout data, EventKit for football schedule
5. SOUND_AND_HAPTICS.md -- set completion, PR celebration, rest timer sounds
6. APPLE_WATCH_APP.md -- wrist-based workout logging

### Recovery Module (RecoverIQ)
1. MODULE_RECOVERY.md -- prescription engine, all screens
2. INTEGRATION_SPECS.md -- Whoop API data flow, HealthKit fallback
3. DATA_MODELS_IOS.md -- recovery models, sync state
4. BACKEND_API.md -- Whoop proxy endpoints
5. AI_INTELLIGENCE_ENGINE.md -- recovery prescription generation

### Accountability Module (Lockdown)
1. MODULE_ACCOUNTABILITY.md -- non-negotiables, focus timer, drill-sergeant
2. ONBOARDING_AND_NOTIFICATIONS.md -- notification copy bank, escalation system
3. DATA_MODELS_IOS.md -- NonNegotiable, FocusSession, Streak models
4. BACKEND_API.md -- accountability endpoints
5. SOUND_AND_HAPTICS.md -- timer sounds, lock/unlock haptics
6. AI_INTELLIGENCE_ENGINE.md -- drill-sergeant copy generation

### Arena Module (ClutchTime)
1. MODULE_ARENA.md -- XP economy, leaderboards, challenges, achievements
2. DESIGN_SYSTEM.md -- animation system for XP and celebrations
3. DATA_MODELS_IOS.md -- Arena models (XPTransaction, Achievement, Challenge)
4. BACKEND_API.md -- social/arena endpoints, WebSocket for real-time
5. SOUND_AND_HAPTICS.md -- level-up, achievement, and leaderboard sounds
6. SECURITY_AND_PRIVACY.md -- social features security, anti-cheat

### Vapor Backend Setup
1. BACKEND_API.md -- complete API spec, schema, deployment
2. INTEGRATION_SPECS.md -- Whoop/NutriTrack proxy implementation
3. SECURITY_AND_PRIVACY.md -- auth, encryption, GDPR
4. AI_INTELLIGENCE_ENGINE.md -- Claude API routing
5. TESTING_STRATEGY.md -- Vapor unit/integration tests

### Onboarding Flow
1. ONBOARDING_AND_NOTIFICATIONS.md -- step-by-step screens, first week
2. DESIGN_SYSTEM.md -- components and animation
3. ANALYTICS_AND_METRICS.md -- onboarding funnel tracking
4. MONETIZATION_STRATEGY.md -- paywall placement in onboarding

### Push Notification System
1. ONBOARDING_AND_NOTIFICATIONS.md -- architecture, channels, copy bank
2. MODULE_ACCOUNTABILITY.md -- drill-sergeant escalation
3. BACKEND_API.md -- APNs infrastructure
4. AI_INTELLIGENCE_ENGINE.md -- AI-generated notification copy
5. CROSS_DOC_AUDIT.md -- notification intensity conflicts

### Apple Watch Companion
1. APPLE_WATCH_APP.md -- complete Watch spec
2. MODULE_TRAINING.md -- workout logging reference
3. MODULE_ACCOUNTABILITY.md -- non-negotiable check-off reference
4. SOUND_AND_HAPTICS.md -- watch haptic patterns

### Whoop Integration
1. INTEGRATION_SPECS.md -- OAuth2, sync, error handling
2. BACKEND_API.md -- proxy routes, token storage
3. MODULE_RECOVERY.md -- how recovery module consumes Whoop data
4. SECURITY_AND_PRIVACY.md -- third-party data security

### AI Features (CortexAI)
1. AI_INTELLIGENCE_ENGINE.md -- all features, prompts, cost management
2. BACKEND_API.md -- AI proxy endpoints
3. MODULE_DASHBOARD.md -- where insights are displayed
4. MODULE_TRAINING.md -- AI workout generation
5. MODULE_ACCOUNTABILITY.md -- AI drill-sergeant copy

### Paywall and Subscriptions
1. MONETIZATION_STRATEGY.md -- pricing, feature split, paywall design
2. ANALYTICS_AND_METRICS.md -- conversion funnels, A/B tests
3. SECURITY_AND_PRIVACY.md -- StoreKit compliance
4. ONBOARDING_AND_NOTIFICATIONS.md -- paywall placement in flow

### Accessibility Implementation
1. ACCESSIBILITY.md -- WCAG 2.2 AA requirements, screen-by-screen audit
2. DESIGN_SYSTEM.md -- color contrast, Dynamic Type support
3. SOUND_AND_HAPTICS.md -- audio accessibility
4. TESTING_STRATEGY.md -- accessibility test automation

### Analytics Instrumentation
1. ANALYTICS_AND_METRICS.md -- PostHog setup, event catalog, funnels
2. SECURITY_AND_PRIVACY.md -- analytics privacy compliance
3. BACKEND_API.md -- server-side events
4. MONETIZATION_STRATEGY.md -- business KPI definitions

### Security and App Store Submission
1. SECURITY_AND_PRIVACY.md -- full compliance checklist
2. BACKEND_API.md -- auth and API security
3. INTEGRATION_SPECS.md -- third-party security
4. MONETIZATION_STRATEGY.md -- IAP guidelines

---

## 6. Glossary

### Industry Standard Acronyms

| Term | Full Form | Context in Tempo |
|------|-----------|-----------------|
| **1RM** | One-Rep Maximum | Maximum weight a user can lift for one repetition. Used in progressive overload calculations. See MODULE_TRAINING.md. |
| **ADR** | Architecture Decision Record | Documented rationale for key technical choices. Referenced in engineering docs. |
| **AHAP** | Apple Haptic and Audio Pattern | File format for Core Haptics patterns. Tempo ships custom AHAP files for all interactions. See SOUND_AND_HAPTICS.md. |
| **APNs** | Apple Push Notification service | Apple's push notification infrastructure. Tempo uses APNs via the Vapor backend. See BACKEND_API.md, ONBOARDING_AND_NOTIFICATIONS.md. |
| **ASO** | App Store Optimization | Strategy for App Store search visibility. See ONBOARDING_AND_NOTIFICATIONS.md (App Store listing), MONETIZATION_STRATEGY.md. |
| **CI/CD** | Continuous Integration / Continuous Deployment | Automated build, test, and deploy pipeline. See TESTING_STRATEGY.md. |
| **CSCS** | Certified Strength and Conditioning Specialist | NSCA certification. MODULE_TRAINING.md is informed by CSCS training principles. |
| **DTO** | Data Transfer Object | Lightweight struct for API request/response payloads. See BACKEND_API.md, DATA_MODELS_IOS.md. |
| **GDPR** | General Data Protection Regulation | EU privacy law. Full compliance spec in SECURITY_AND_PRIVACY.md. |
| **HIG** | Human Interface Guidelines | Apple's design guidelines. Referenced in DESIGN_SYSTEM.md, ACCESSIBILITY.md. |
| **HIPAA** | Health Insurance Portability and Accountability Act | US health data law. Tempo is not HIPAA-regulated but follows best practices. See SECURITY_AND_PRIVACY.md. |
| **HRV** | Heart Rate Variability | Key recovery metric from Whoop. Higher HRV = better recovery. See MODULE_RECOVERY.md, INTEGRATION_SPECS.md. |
| **IAP** | In-App Purchase | StoreKit 2 subscription purchases. See MONETIZATION_STRATEGY.md. |
| **JWT** | JSON Web Token | Authentication token format. Tempo uses JWT for API auth. See BACKEND_API.md, SECURITY_AND_PRIVACY.md. |
| **KPI** | Key Performance Indicator | Business metrics tracked in PostHog. See ANALYTICS_AND_METRICS.md. |
| **LTTB** | Largest Triangle Three Buckets | Chart downsampling algorithm for rendering large datasets efficiently. See MODULE_DASHBOARD.md, PERFORMANCE_OPTIMIZATION.md. |
| **MTU** | Monthly Tracked Users | Analytics platform billing metric. See ANALYTICS_AND_METRICS.md. |
| **OAuth2** | Open Authorization 2.0 | Protocol for Whoop API authentication. See INTEGRATION_SPECS.md, BACKEND_API.md. |
| **OWASP** | Open Web Application Security Project | Security standard. Penetration testing follows OWASP guidelines. See SECURITY_AND_PRIVACY.md. |
| **PR** | Personal Record | New best performance on an exercise (heaviest weight, most reps). See MODULE_TRAINING.md. |
| **PWA** | Progressive Web App | Web app pattern. NutriTrack is a PWA. See INTEGRATION_SPECS.md. |
| **RHR** | Resting Heart Rate | Recovery metric from Whoop. Lower RHR generally indicates better cardiovascular fitness. See MODULE_RECOVERY.md. |
| **RPE** | Rate of Perceived Exertion | Subjective intensity scale (1-10) used in training. See MODULE_TRAINING.md. |
| **SDK** | Software Development Kit | Third-party libraries (PostHog SDK, Whoop SDK, etc.). |
| **WCAG** | Web Content Accessibility Guidelines | Accessibility standard. Tempo targets WCAG 2.2 AA. See ACCESSIBILITY.md. |
| **XP** | Experience Points | Gamification currency earned by completing activities. See MODULE_ARENA.md. |

### Tempo-Specific Terms

| Term | Definition | Primary Document |
|------|-----------|-----------------|
| **Arena** | The social gamification module. Contains XP, leaderboards, challenges, achievements. | MODULE_ARENA.md |
| **Body quadrant** | Dashboard section showing recovery data (Whoop/HealthKit). | MODULE_DASHBOARD.md |
| **ClutchTime** | Codename for the Arena module. | MODULE_ARENA.md |
| **CortexAI** | Codename for the AI Intelligence Engine. Uses Claude API (Haiku 3.5 + Sonnet 4). | AI_INTELLIGENCE_ENGINE.md |
| **DailySnapshot** | Core SwiftData model that captures all metrics for a single day. The data backbone of the dashboard. | DATA_MODELS_IOS.md |
| **DayForge** | Feature for building the daily schedule/plan. | MODULE_ACCOUNTABILITY.md |
| **Deload week** | Planned reduction in training volume/intensity for recovery. Triggered automatically or by AI. | MODULE_TRAINING.md |
| **Drill Sergeant** | The personality/voice of Tempo's notification and coaching system. Tough love, zero fluff. | MODULE_ACCOUNTABILITY.md, DESIGN_SYSTEM.md |
| **Exam mode** | Accountability mode that prioritizes study time and reduces training volume during exam periods. | MODULE_ACCOUNTABILITY.md |
| **Fuel quadrant** | Dashboard section showing nutrition data from NutriTrack integration. | MODULE_DASHBOARD.md |
| **League** | Weekly competitive bracket in the Arena (Bronze through Diamond). | MODULE_ARENA.md |
| **LifeOS** | Codename for the Dashboard module. The unified home screen. | MODULE_DASHBOARD.md |
| **Lockdown** | Codename for the Accountability module. | MODULE_ACCOUNTABILITY.md |
| **Mind quadrant** | Dashboard section showing study/focus time and non-negotiable completion. | MODULE_DASHBOARD.md |
| **Morning briefing** | AI-generated daily summary shown on the dashboard at wake time. | AI_INTELLIGENCE_ENGINE.md |
| **Move quadrant** | Dashboard section showing training/workout data. | MODULE_DASHBOARD.md |
| **Non-negotiable** | A daily task the user commits to completing. Tracked with streaks. The core unit of the Accountability module. | MODULE_ACCOUNTABILITY.md |
| **NutriTrack** | Nicola's separate nutrition PWA (Flask). Tempo integrates via backend proxy. | INTEGRATION_SPECS.md |
| **Prescription** | AI-generated daily recovery recommendation based on Whoop data (sleep, strain, HRV). | MODULE_RECOVERY.md |
| **RecoverIQ** | Codename for the Recovery module. | MODULE_RECOVERY.md |
| **Recovery zone** | Classification of daily recovery: Green (67-100), Yellow (34-66), Red (0-33). Drives training adjustments. | MODULE_RECOVERY.md |
| **RepForge** | Codename for the Training module. | MODULE_TRAINING.md |
| **Streak** | Consecutive days of completing a non-negotiable or maintaining Arena activity. | MODULE_ACCOUNTABILITY.md, MODULE_ARENA.md |
| **Streak freeze** | Arena item that protects a streak from breaking on a missed day. | MODULE_ARENA.md |
| **Tempo score** | Composite daily score (0-100) calculated from all four quadrants. Displayed prominently on the dashboard. | MODULE_DASHBOARD.md |
| **Weekend mode** | Accountability mode with relaxed non-negotiable requirements on Saturdays and Sundays. | MODULE_ACCOUNTABILITY.md |
| **XP sink** | Mechanism that removes XP from the economy to prevent inflation (cosmetic purchases, streak freezes). | MODULE_ARENA.md |

---

## 7. Document Maintenance Guide

### Keeping Docs in Sync

1. **Single source of truth rule.** Every concept has exactly one primary document (see Cross-Reference Table). When updating a value (color hex, threshold, algorithm), update the primary document first, then grep for the old value across all docs.

2. **Run the audit after changes.** After modifying any specification, re-check CROSS_DOC_AUDIT.md for affected areas. If your change introduces a new conflict, resolve it before merging.

3. **Use design tokens, not raw values.** When referencing colors, spacing, or typography in module docs, use the DESIGN_SYSTEM.md token name (e.g., `tempo.accent`) rather than a raw hex value. This reduces the surface area for conflicts.

### When to Update vs. Create New Docs

| Situation | Action |
|-----------|--------|
| Adding a screen to an existing module | Update the module doc |
| Changing an algorithm or threshold | Update the primary doc + grep for the old value |
| Adding a new integration (e.g., Spotify) | Add a new section to INTEGRATION_SPECS.md |
| Adding a new module (e.g., Social/Chat) | Create a new MODULE_*.md file and update this INDEX |
| Changing the data model | Update DATA_MODELS_IOS.md + BACKEND_API.md schema section |
| Adding new API endpoints | Update BACKEND_API.md |
| New platform (e.g., iPad, Android) | Create a new platform doc (IPAD_APP.md, ANDROID_APP.md) |

### Version Numbering

| Version | Meaning |
|---------|---------|
| **1.0** | Initial specification (current state -- all docs) |
| **1.x** | Minor updates: clarifications, bug fixes, small additions |
| **2.0** | Major revision: structural changes, new sections, algorithm overhauls |

Update the version number and "Last Updated" date in the document header whenever making changes. The BACKEND_API.md is already at v2.0.0; all others are at v1.0.

### Review Cadence

| Trigger | Action |
|---------|--------|
| **Before each build phase** | Review the docs relevant to that phase. Resolve any CROSS_DOC_AUDIT conflicts in that area. |
| **After completing a module** | Verify the implemented code matches the spec. Update the spec if intentional deviations were made during implementation. |
| **Monthly** | Quick scan of all docs for staleness. Mark any doc that no longer reflects reality as "Needs Update" in this INDEX. |
| **Before App Store submission** | Full review of SECURITY_AND_PRIVACY.md, ACCESSIBILITY.md, and MONETIZATION_STRATEGY.md for compliance. |
| **After each cross-doc audit** | Update this INDEX's Cross-Reference Table if new concepts were added. |

### Maintenance Checklist

- [ ] All docs have matching version numbers where they reference shared values
- [ ] CROSS_DOC_AUDIT.md has zero unresolved critical issues
- [ ] This INDEX reflects all documents in the `docs/` directory
- [ ] Every new concept added to any doc appears in the Cross-Reference Table
- [ ] Every new acronym or Tempo term appears in the Glossary
- [ ] Reading orders are still accurate for the current project state

---

> **Last updated:** 2026-03-24 | **Documents indexed:** 20 | **Total specification lines:** ~58,300
