# INTEGRATION_SPECS — External Data Integrations

> **Document**: Integration Specifications (Whoop, HealthKit, Calendar, Sync)
> **App**: Tempo — iOS (SwiftUI, iOS 17.4+) + Vapor backend
> **Version**: 3.0 — AS-BUILT
> **Last Updated**: 2026-05-19
> **Audience**: iOS + backend developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the code actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):

iOS:
- `Tempo/Tempo/Services/Integrations/WhoopService.swift` (`WhoopService`, `WhoopService.Constants`, `connect()`, `validAccessToken`, `whoopGet`)
- `Tempo/Tempo/Services/Integrations/CalendarService.swift` (`CalendarService`, `detectFootballDays`, `detectExamDates`, `detectClassSchedule`)
- `Tempo/Tempo/Services/Health/HealthKitService.swift` (`HealthKitService`, `requestAuthorization`, `fetchSleepAnalysis`, `writeNutrition`, `writeWorkout`)
- `Tempo/Tempo/Services/Health/HealthKitBackgroundDelivery.swift`
- `Tempo/Tempo/Utilities/Constants/HealthKitConstants.swift` (`readTypes`, `writeTypes`)
- `Tempo/Tempo/Services/Sync/BackgroundSyncService.swift`, `MockSyncCoordinator.swift`, `SyncCoordinatorProtocol.swift`, `DailyResetCoordinator.swift`
- `Tempo/Tempo/Services/Security/KeychainService.swift`

Backend (Vapor):
- `tempo-backend/Sources/App/Controllers/WhoopIntegrationController.swift` (OAuth proxy)
- `tempo-backend/Sources/App/Controllers/WhoopDataController.swift` (data proxy)
- `tempo-backend/Sources/App/Controllers/WhoopWebhookController.swift`, `Middleware/WhoopWebhookMiddleware.swift`
- `tempo-backend/Sources/App/Services/WhoopOAuthService.swift`, `WhoopAPIService.swift`, `EncryptionService.swift`
- `tempo-backend/Sources/App/routes.swift`
- `tempo-backend/Sources/App/Migrations/DropNutriTrackIntegrations.swift`

---

## Table of Contents

1. [Whoop API Integration](#1-whoop-api-integration)
2. [Apple HealthKit Integration](#2-apple-healthkit-integration)
3. [NutriTrack Integration](#3-nutritrack-integration--removed)
4. [Apple Calendar (EventKit) Integration](#4-apple-calendar-eventkit-integration)
5. [Sync Architecture](#5-sync-architecture)
6. [Error Recovery & Resilience](#6-error-recovery--resilience)

---

## 1. Whoop API Integration

> **Divergence from original spec — ARCHITECTURE IS INVERTED. Read this first.**
>
> The original spec mandated a **backend-proxy OAuth architecture**: the iOS app never touches raw Whoop tokens, the `client_secret` lives only server-side, and all Whoop API traffic flows through the Tempo backend. **The shipping iOS app does NOT do this.**
>
> Two parallel, disconnected stacks exist:
>
> 1. **Backend proxy (fully implemented, but UNUSED by the app).** `WhoopIntegrationController` + `WhoopOAuthService` + `WhoopAPIService` + `WhoopDataController` implement the spec'd proxy correctly: server-side `client_secret`, CSRF state in Redis, encrypted token storage, actor-based refresh, a `/v1/whoop/*` data proxy with caching. This code is real and works — the iOS client just never calls it.
> 2. **iOS direct OAuth (what actually ships).** `WhoopService` talks **directly to `api.prod.whoop.com`** (`WhoopService.Constants.authURL` / `tokenURL` / `apiBase = …/developer/v2`). The Whoop **`client_secret` is embedded in the app binary** (loaded from `KeychainService` under key `whoop.client_secret`, but provisioned into the client — not held server-side). Raw access/refresh tokens are stored locally in the iOS Keychain (`KeychainService`, `Keys.tokenBundle`). The OAuth callback scheme is `tempo://whoop/callback` pointed straight at Whoop, not the backend's `tempo://integrations/whoop/success`.
>
> **This violates the spec's core security premise.** The spec required the `client_secret` to never leave the server; in the shipped app it is extractable from the binary by anyone who unpacks the IPA. Documenting reality, not endorsing it. Sections below describe the **iOS direct path as the as-built behavior** and note the backend proxy as a separate, dormant implementation.

> **Note (still accurate from original spec):** Whoop Developer Mode has a **10-user hard limit**; production access requires Whoop approval (2 weeks–3+ months, revocable). Beta must work HealthKit-only. This operational constraint is unchanged.

### 1.1 Authentication Flow — Step by Step

**As-built (iOS direct path — what ships):** `WhoopService.connect()` runs OAuth entirely on-device:

1. Requires `clientID` + `clientSecret` present in Keychain (`WhoopService.hasCredentials`); both are provisioned into the client via `saveCredentials(clientID:clientSecret:)`.
2. Builds the Whoop authorize URL directly from `Constants.authURL` (`https://api.prod.whoop.com/oauth/oauth2/auth`) with `redirect_uri = tempo://whoop/callback` and a locally generated `state`.
3. Opens `ASWebAuthenticationSession` with `prefersEphemeralWebBrowserSession = true`, `callbackURLScheme = "tempo"`. Session is held as an instance property.
4. User authorizes on Whoop's page; Whoop redirects to `tempo://whoop/callback`.
5. iOS validates the returned `state` against the locally stored value.
6. iOS POSTs the code directly to `Constants.tokenURL` (`…/oauth/oauth2/token`) with `client_secret` from Keychain — **no backend involved**. No retry on this on-device exchange.
7. Tokens are written to the iOS Keychain via `KeychainService` (`Keys.tokenBundle`, with legacy split keys cleaned up).
8. `connectionState` → `.connected(lastSync:)`.

User-cancel (`canceledLogin`) is handled silently: `connectionState` resets to `.disconnected`, no error surfaced, no analytics.

> **Divergence from original spec:** Spec Steps 1–11 described a backend round-trip (`GET /v1/integrations/whoop/authorize` → backend builds URL with Redis CSRF state → browser → backend callback exchanges code, encrypts + stores tokens, redirects `tempo://integrations/whoop/success`). The shipping app skips all of it and does on-device OAuth against Whoop directly. The backend implementation of those steps exists and is correct (see §1.1-backend) but is dead code from the client's perspective.

#### 1.1-backend: Backend OAuth Proxy (implemented, unused by client)

For completeness — this matches the original spec and is fully built, just not called by the shipping app:

- `GET /v1/integrations/whoop/authorize` — builds the Whoop URL server-side, `state = randomHex(32)` stored in Redis with 600s TTL (`WhoopIntegrationController`, `WhoopOAuthService`). Returns the Whoop URL directly (no separate exchange step). Returns **409** if Whoop already connected.
- Callback handler validates `state`, exchanges the code (with `exchangeWithRetry`: up to 3 attempts, 2s sleep), encrypts tokens via `EncryptionService` (AES-GCM), stores them, and redirects `tempo://integrations/whoop/success` (or `…/error`).
- Route group: `protected.grouped("integrations", "whoop")` with a 10/min per-user rate limit.

> **Divergence from original spec:** Backend state lookup uses a Redis `SCAN` over all keys rather than keying by `user_id`. Functional but O(n) and a minor CSRF-isolation weakening vs. the spec. HKDF salt/info params from spec §9 not verified line-for-line against `EncryptionService`.

### 1.2 Token Management

**As-built (iOS direct path):** `WhoopService.validAccessToken` / `forceTokenRefresh` refreshes against `Constants.tokenURL` when the token is near/at expiry, with a single retry on a transient failure. There is **no actor-based per-user dedup** on the iOS side — concurrent callers are not guaranteed to coalesce into one refresh.

Failure handling is coarse: any refresh failure collapses the connection into an error state (`connectionState = .error`, "tap to reconnect"). There is **no per-status matrix**.

> **Divergence from original spec:** Spec §1.2 specified an actor with `refreshTasks` dedup and a detailed refresh-failure matrix: 401/400 → `token_revoked` + visible push + re-auth banner; 5xx → exponential backoff 2/4/8s + `degraded` state; 429 → `Retry-After`; timeout → 3×2s without revoke. **None of this granularity exists in the iOS client.** Only the coarse "refresh failed → error/reconnect" branch ships. No 5xx backoff, no `degraded` state, no 429 handling, no timeout-no-revoke path.
>
> The **backend** `WhoopAPIService` (an actor with `refreshTasks` dedup and `needsRefresh`) does match the spec's actor/dedup pattern — but it too collapses any refresh failure to `token_revoked` with no status discrimination, and it is unused by the client.

> **Status: NOT IMPLEMENTED (re-auth UX):** No visible `WHOOP_REAUTH` push is sent on token revocation. Only an in-app `connectionState = .error` ("tap to reconnect") exists. Backend `/status` returns `connected` / `lastSync` / `connectedSince` but not the `token_revoked` / `degraded` state strings the spec's launch-check switched on.

### 1.3 Data Sync Pipeline

**As-built (iOS direct path):** `WhoopService` fetches recovery / sleep / workouts / cycles **on demand** directly from `api.prod.whoop.com/developer/v2`, decoding the v2 response shapes. Data is fetched when the app needs today's data; there is no scheduled pipeline.

The **backend** `WhoopAPIService` + `WhoopDataController` independently implements the same fetch against `…/developer/v1` paths with a 120s Redis cache, exposed at `GET /v1/whoop/{recovery,sleep,workouts,cycles}` (route group `protected.grouped("whoop")`, 100/min rate limit). Functional but unused by the shipping client.

> **Divergence from original spec:** Spec §1.3 described a backend-orchestrated sync pipeline. As-built, the iOS client fetches v2 directly; the backend fetches v1. The **API version split (iOS v2 vs backend v1)** is an unresolved inconsistency between the two stacks.

> **Status: NOT IMPLEMENTED (initial history sync):** No `POST /v1/integrations/whoop/sync` route, no 30-day async backfill, no completion push. `routes.swift` only registers `authorize`/`callback`/`status`/`disconnect` + the `WhoopDataController` proxy. The iOS `triggerInitialSync` from spec §1.1 Step 11 does not exist; the app fetches today's data on demand.

### 1.4 Webhook Processing

**As-built (solid — document as real):** The backend webhook receiver is fully implemented and matches the spec's verification model:

- `POST /v1/webhooks/whoop` (`routes.swift`: `v1.grouped("webhooks", "whoop")`).
- `WhoopWebhookMiddleware`: HMAC-SHA256 signature verification, `X-Whoop-Timestamp` replay rejection (>300s window), timing-safe comparison.
- `WhoopWebhookController`: idempotency via `trace_id` with a 24h Redis dedup (`setex 86400`), dispatches async background work, returns `200` immediately.

> **Divergence from original spec:** The async webhook job only **invalidates the Redis cache + updates `lastSyncAt`**. The spec wanted `syncRecovery` / `syncSleep` / `syncWorkout` DB writes, `sendRecoveryPush`, `awardWorkoutXP`, `sendSilentPush`, plus `body_measurement.updated` and `*.deleted` soft-delete handling. Those event types fall through to the default "unhandled" branch. The job is a real, verified receiver but a no-op processor beyond cache invalidation.

> **Status: NOT IMPLEMENTED (reconciliation cron):** No daily 3 AM UTC re-fetch job. `Jobs/` contains DrillSergeant / Leaderboard / Notification / Cleanup / WeeklySummary only — no reconciliation/backfill job.

### 1.5 Whoop Data Edge Cases

> **Status: NOT IMPLEMENTED.** `score_state` is decoded into DTOs but never branched on. There is no handling for: UNSCORABLE / partial sleep, battery-gap staleness, recovery `PENDING` polling, cycle-vs-calendar-day mismatch, multiple Whoop devices, "Whoop app not synced" staleness, or `403 membership_expired`. The spec's entire edge-case UX layer is absent in both stacks.

---

## 2. Apple HealthKit Integration

This is the most solid integration alongside Calendar. Reads, background delivery, and observer queries work as built.

### 2.1 Authorization

**As-built:** `HealthKitService.requestAuthorization` requests `HealthKitConstants.writeTypes` (share) + `HealthKitConstants.readTypes` (read), guarded by `isHealthDataAvailable()` (graceful `.unavailable` on iPad/iPod).

`HealthKitConstants.readTypes` (verified against source):
- Activity: `stepCount`, `activeEnergyBurned`, `basalEnergyBurned`, `distanceWalkingRunning`, `appleExerciseTime`
- Heart: `heartRate`, `restingHeartRate`, `heartRateVariabilitySDNN`
- Sleep: `sleepAnalysis`
- Nutrition (read what other apps write): `dietaryEnergyConsumed`, `dietaryProtein`, `dietaryCarbohydrates`, `dietaryFatTotal`
- Body: `bodyMass`, `height`, `bodyFatPercentage`, `leanBodyMass`
- Workouts: `workoutType()` + `HKSeriesType.workoutRoute()` (iOS 17+ GPS)

`HealthKitConstants.writeTypes`: `workoutType()`, `dietaryEnergyConsumed`, `dietaryProtein`, `dietaryCarbohydrates`, `dietaryFatTotal` (and any additional dietary write types declared in the set).

`checkWriteAuthorizationStatus` maps per-type status → `fullAccess` / `partialAccess` / `denied`. `verifyPermissionsOnLaunch` (write-status revocation detection + a read-probe query) runs on every foreground (called from `TempoApp`). `openHealthSettings` deep-links to `x-apple-health://`.

> **Divergence from original spec:** Read set **adds** `bodyFatPercentage` + `leanBodyMass` (Withings scale sync) beyond the spec list, and **omits** `dietaryFiber` / `dietarySugar` / `dietarySodium` from reads. Write set is energy/protein/carbs/fat; the spec's `saveMealNutrition` also listed fiber/sugar/sodium writes — those are not written.

> **Status: NOT IMPLEMENTED (missing-data nag UI):** Only the `openHealthSettings` deep-link helper exists. The "no data 7+ days → inline banner, nag ≤1/day/type" logic is not in the service layer.

### 2.2 Read Operations

**As-built:**
- **Steps** (§2.2.1): `HKStatisticsQuery` `.cumulativeSum` with source dedup. IMPLEMENTED.
- **Heart rate / HRV / RHR** (§2.2.2): point reads `fetchHeartRate`, `fetchHRV`, `fetchRestingHeartRate`. Sample/HRV/RHR reads work.
- **Sleep** (§2.2.3): `fetchSleepAnalysis` with stage parsing, 6 PM→12 PM window, source priority Whoop > Apple (`selectPreferredSleepSource`: `com.whoop.Diamond` → `com.apple.health`). IMPLEMENTED.
- **Workouts** (§2.2.4): `fetchWorkouts` returns all sources, unfiltered.
- **Active energy** (§2.2.5): IMPLEMENTED.

> **Divergence from original spec (heart rate):** No `observeHeartRate` (`HKAnchoredObjectQuery` live stream), no `fetchAverageHeartRate` (`discreteAverage`), and no `getRestingHeartRate()` Whoop-source-preference wrapper. Live observation + source-priority composition for HR are missing; point reads only.

### 2.3 Write Operations

**As-built:**
- **Workouts** (§2.3.1): `writeWorkout` uses `HKWorkoutBuilder` with a duplicate-start-time check (dedup). IMPLEMENTED.
- **Nutrition** (§2.3.2): `writeNutrition` writes an `HKCorrelation(.food)` with energy/protein/carbs/fat. Source-tag metadata is `"TempoSource": "Tempo"`.

> **Divergence from original spec:** `writeNutrition` omits fiber/sugar/sodium, sets no `HKMetadataKeyFoodType` meal name, and performs **no dedup/delete-old-correlation on meal edit** (spec required edit-replace). The `"TempoSource"` tag is `"Tempo"` not `"NutriTrack"` — moot since NutriTrack is removed (§3).

### 2.4 Background Delivery

**As-built (solid):** `HealthKitBackgroundDelivery` enables background delivery (steps/energy hourly, workout/sleep immediate) and registers observer queries, each with a guaranteed `defer { completionHandler() }`. Both are wired from `TempoApp` at launch. IMPLEMENTED.

> **Divergence from original spec (BG refresh task):** The `BGAppRefreshTask "com.tempo.healthkit-sync"` is **registered** in `BackgroundSyncService` and reschedules itself, but `handleHealthKitSync` does **no work** — it calls `task.setTaskCompleted(success: true)` immediately. The spec's batched async-let steps/energy/sleep fetch + snapshot update is absent. Registration without work. (Live observer-query delivery in `HealthKitBackgroundDelivery` does function — that is the real background path.)

### 2.5 HealthKit + Whoop Data Reconciliation

> **Status: NOT IMPLEMENTED.** No `isWhoopSource()`, no `fetchNonWhoopWorkouts` filter. `fetchWorkouts` returns all sources unfiltered, so Whoop-originated workouts are not excluded from HealthKit workout reads. (Sleep source-priority Whoop > Apple **is** implemented — see §2.2.3 — but the explicit workout Whoop-source exclusion is not.)

---

## 3. NutriTrack Integration — REMOVED

> **Status: REMOVED (intentional, not a defect).** The entire NutriTrack integration (connection PIN flow, sync strategy, endpoint mapping, error handling — original §3.1–3.4) was deliberately removed and replaced by native nutrition.
>
> Evidence: `Migrations/DropNutriTrackIntegrations.swift` drops the table; `configure.swift` registers the drop migration; no NutriTrack routes in `routes.swift`; no iOS `NutriTrackService` (only `FoodCanonicalizer.swift` mentions the word). Replacement stack: native `NutritionAIService`, receipt structuring, meal-plan generation.
>
> The original `CreateNutriTrackIntegrations` migration is retained (committed migrations are never amended) and immediately reverted by the drop migration.

> **Divergence — dead spec text elsewhere:** §5 (Sync Architecture, original) still references a `nutriTrackService` and a NutriTrack tier in its conflict-resolution priority chain. Those references are **dead** — NutriTrack does not exist in the codebase. Treat any `nutriTrackService` / `Whoop>HK>NutriTrack>Local` text in surviving spec fragments as stale.

---

## 4. Apple Calendar (EventKit) Integration

The most faithful section — code closely matches the original spec.

### 4.1 Authorization

**As-built:** `CalendarService` authorizes via `requestFullAccessToEvents()` (iOS 17.4+) and checks status on launch. IMPLEMENTED.

### 4.2 Reading Calendar Data

**As-built:** Reads events for a date range and maps to `CalendarEvent`. Categorization is keyword-based with dual-language (EN + IT) keyword sets: `detectFootballDays`, `detectExamDates`, `detectClassSchedule`. Exceeds the spec with an `addExam()` write-back. IMPLEMENTED — keyword approach is per spec & feasibility audit §6.5.

### 4.3 Data Flow

**As-built (partial):** The service exposes the `detect*` detection APIs. Downstream consumer wiring into Training / Mind / Accountability modules was not verified in the integrations-services audit pass.

> **Divergence from original spec:** Service-side detection is complete; the spec's §4.3 module-level data-flow integration is unverified (out of audited scope — Services dir only). Not asserting it works or doesn't; it is unverified.

### 4.4 Edge Cases

**As-built:** `observeCalendarChanges` observes `.EKEventStoreChanged` and invalidates the cache. IMPLEMENTED. Multi-calendar, all-day vs timed, recurring-event, and timezone handling follow EventKit defaults as the spec described.

---

## 5. Sync Architecture

> **Status: NOT IMPLEMENTED — essentially absent.** This entire section was specified but never built. Only a mock and a protocol exist.
>
> What exists:
> - `Services/Sync/SyncCoordinatorProtocol.swift` — a protocol.
> - `Services/Sync/MockSyncCoordinator.swift` — a mock conforming to it.
> - `Services/Sync/BackgroundSyncService.swift` — registers three BG tasks (`com.tempo.healthkit-sync`, `com.tempo.data-sync`, `com.tempo.daily-reset`) and reschedules them; handlers (`handleHealthKitSync`, `handleDataSync`) are **empty stubs** that call `task.setTaskCompleted(success: true)` with no sync work. `handleDailyReset` delegates to `DailyResetCoordinator`.
> - `Services/Sync/DailyResetCoordinator.swift` — handles day rollover only; NOT the spec's sync/offline layer.
>
> What does NOT exist (all NOT IMPLEMENTED):
> - **§5.1** real `SyncService`/`SyncCoordinator` orchestrator (4-integration parallel fetch with per-source timeouts, `syncStates`); retry queue / exponential backoff / `processRetryQueue` (outside the mock).
> - **§5.1** `POST /v1/sync/snapshot` upload route — no `/sync` or `/snapshot` route in `routes.swift`.
> - **§5.2** conflict-resolution matrix + `DailySnapshotBuilder` merge (`buildDailySnapshot` / `determineWorkoutCompleted`). (Also depended on a NutriTrack priority tier that no longer exists — see §3.)
> - **§5.3** `DataFreshnessMonitor`, `staleThresholds`, `freshnessLabel`.
> - **§5.4–5.6** offline write-queue replay, complete data-flow diagram backing, integration-health dashboard service.

---

## 6. Error Recovery & Resilience

> **Status: NOT IMPLEMENTED — essentially absent.** No structured resilience layer ships. Only ad-hoc, scattered retries exist.
>
> What exists (ad-hoc only):
> - Backend code-exchange retry: up to 3× with 2s sleep (`WhoopIntegrationController.exchangeWithRetry`).
> - iOS token refresh: single retry on transient failure (`WhoopService.validAccessToken`).
> - iOS `whoopGet`: single retry on `401`.
>
> What does NOT exist (all NOT IMPLEMENTED):
> - **§6.1** retry-strategies table: no jitter, no `Retry-After` parsing, no per-status (5xx-degraded / 403-no-retry) backoff.
> - **§6.2** circuit breaker: no `CircuitBreaker` type anywhere (no closed/open/halfOpen, no per-integration thresholds).
> - **§6.3** user-notification strategy: no integration-failure push/banner orchestration, no 1-push/integration/hour rate limit. iOS only sets `connectionState = .error` strings. `APNsService` exists for other features but has no Whoop-revoked / data-stale / membership-expired wiring.
> - **§6.5** backend-vs-local conflict resolution: depends on §5.2, which is missing.

> **Divergence from original spec (§6.4 graceful degradation — PARTIAL):** Basic per-service gating exists: `WhoopService.connectionState` gates Whoop-dependent UI; `HealthKitService` returns `.unavailable` when HealthKit is absent. The spec's feature-by-feature degraded-UI matrix (moderate-intensity fallback, module-lock copy, stale indicators) is **not** centrally implemented — it depends on the §5 freshness layer, which is missing. Coarse on/off gating only.

---

> **End of AS-BUILT reconciliation.** Sections marked NOT IMPLEMENTED / REMOVED describe genuine absences in the 2026-05-19 codebase, not pending work commitments. The Whoop architecture inversion (§1) and the absence of §5/§6 are the largest gaps between this doc's predecessor and shipped reality.
