# Tempo Backend API Specification

> **Version:** 3.0 — AS-BUILT
> **Last Updated:** 2026-05-19
> **Stack:** Vapor 4 (Swift) + PostgreSQL + Redis
> **Audience:** iOS + backend developers. This document is an **AS-BUILT description reconciled to the codebase on 2026-05-19**. It describes what the Vapor backend actually does, not the original aspirational spec. Original spec intent is preserved inline in `> **Divergence from original spec:**` and `> **Status: NOT IMPLEMENTED.**` callouts so nothing is lost. The code is ground truth; if this doc and the code disagree, the code wins and this doc is the bug.

Primary source files referenced throughout (cited by file + symbol, never line number — lines drift):
- `tempo-backend/Sources/App/routes.swift` (`routes(_:)` — the authoritative route table)
- `tempo-backend/Sources/App/configure.swift` (`configure(_:)` — middleware, JWT signer, migration list)
- `tempo-backend/Sources/App/Controllers/*.swift` (each `boot(routes:)`)
- `tempo-backend/Sources/App/DTOs/Envelope.swift`, `DTOs/ErrorDTO.swift`
- `tempo-backend/Sources/App/Middleware/*.swift`
- `tempo-backend/Sources/App/Migrations/*.swift`

**Reality summary:** 16 controllers are registered. **68 routes** are actually reachable. The original spec documented ~95 endpoints across 31 sections; roughly half have no backend at all. Entire subsystems (Training, Study, Snapshots, Accountability, Sync, Outbound Webhooks, Reports, Search, Admin, App Config, WebSocket) were never built. The NutriTrack proxy was built and then deliberately deleted (`DropNutriTrackIntegrations` migration) and replaced by a Receipt/NutritionAI pipeline that the original spec never documented. See §32 for the reverse-drift endpoints that exist in code but were absent from this doc.

---

## Table of Contents

1. [API Overview](#1-api-overview)
2. [Authentication](#2-authentication)
3. [User Management](#3-user-management)
4. [User Preferences & Settings](#4-user-preferences--settings)
5. [Whoop Integration](#5-whoop-integration)
6. [NutriTrack Proxy](#6-nutritrack-proxy)
7. [Training & Workouts](#7-training--workouts)
8. [Study Sessions](#8-study-sessions)
9. [Daily Snapshots & History](#9-daily-snapshots--history)
10. [Arena / Social Endpoints](#10-arena--social-endpoints)
11. [Non-Negotiables & Accountability](#11-non-negotiables--accountability)
12. [Sync & Batch Operations](#12-sync--batch-operations)
13. [Push Notifications](#13-push-notifications)
14. [Outbound Webhooks](#14-outbound-webhooks)
15. [AI Insights](#15-ai-insights)
16. [Reports & Data Export](#16-reports--data-export)
17. [Search](#17-search)
18. [Admin Endpoints](#18-admin-endpoints)
19. [App Configuration](#19-app-configuration)
20. [Real-Time (WebSocket)](#20-real-time-websocket)
21. [Database Schema](#21-database-schema)
22. [Caching Strategy](#22-caching-strategy)
23. [Error Codes](#23-error-codes)
24. [Security](#24-security)
25. [Rate Limiting](#25-rate-limiting)
26. [Background Jobs](#26-background-jobs)
27. [Observability](#27-observability)
28. [Deployment](#28-deployment)
29. [Migration Strategy](#29-migration-strategy)
30. [API Versioning & Deprecation](#30-api-versioning--deprecation)
31. [Load Testing & Capacity Planning](#31-load-testing--capacity-planning)
32. [Undocumented Endpoints That Exist (Reverse Drift)](#32-undocumented-endpoints-that-exist-reverse-drift)

---

## 1. API Overview

**Status: IMPLEMENTED (partial).** Source: `routes.swift`, `DTOs/Envelope.swift`, `DTOs/ErrorDTO.swift`, `Middleware/TempoErrorMiddleware.swift`.

### 1.1 Base URL

All versioned endpoints are under the `v1` route group (`routes.swift` — `app.grouped("v1")`). The unversioned health check (`GET /health`) sits outside `/v1`.

Base URLs (production/staging hostnames are deployment config, not in code):
```
Development: http://localhost:8080
```

### 1.2 Content Type

JSON in/out. Vapor `Content` codables. The NutritionAI vision proxy raises its body limit to 5 MB; the text proxy to 256 KB (`NutritionAIController.boot`).

### 1.3 Standard Response Envelope

Defined in `DTOs/Envelope.swift`:
```
Envelope<T>: { ok: Bool, data: T, pagination: PaginationMeta?, meta: ResponseMeta }
ResponseMeta: { requestID: String, timestamp: Date }
PaginationMeta: { cursor: String?, hasMore: Bool, count: Int }
```

> **Divergence from original spec:** The original spec described a richer envelope and per-field examples per endpoint. The real envelope is the four-field `Envelope<T>` above; concrete `data` shapes are the controller return types, not the JSON blobs the old spec inlined. Read the controller + its DTO for ground-truth shape.

### 1.4 Standard Error Response

Defined in `DTOs/ErrorDTO.swift`, produced by `Middleware/TempoErrorMiddleware`:
```
ErrorEnvelope: { ok: Bool, error: ErrorDTO, meta: ResponseMeta }
ErrorDTO: { code: Int, message: String, detail: String?, field: String? }
```
`TempoErrorMiddleware` preserves `Abort.identifier` as a stable `code` so iOS can distinguish error kinds (e.g. `subscription_required` vs `ai_consent_required`) without parsing reason strings.

### 1.5 Pagination

`PaginationQuery: { cursor: String?, limit: Int?, direction: String? }` exists in `Envelope.swift`. Cursor pagination is available where a controller opts into it; there is **no** globally enforced pagination contract.

### 1.6 Standard Headers

`X-Request-Id` is set on every response by `RequestIdMiddleware` (outermost middleware, `configure.swift`) and is in the CORS exposed-headers list.

### 1.7 Idempotency

> **Status: NOT IMPLEMENTED.** No idempotency-key middleware exists. Spec §1.7 is aspirational.

### 1.8 Date/Time Format

ISO-8601 via Vapor's default `Date` JSON coding.

### 1.9 ETag Support

> **Status: NOT IMPLEMENTED.** No ETag middleware. Conditional GET / `If-None-Match` is not handled. Caching is ad-hoc per-controller via Redis (see §22).

---

## 2. Authentication

**Status: IMPLEMENTED (diverged token spec).** Source: `Controllers/AuthController.swift`, `Middleware/JWTAuthMiddleware.swift`, `configure.swift`, `Services/JWTService.swift`. Registered at `routes.swift` under `v1/auth`, rate-limited 10 req/min per IP.

Registered routes (the only three that exist):

| Method | Path | Handler | Auth |
|--------|------|---------|------|
| POST | `/v1/auth/apple` | `signInWithApple` | none |
| POST | `/v1/auth/refresh` | `refreshToken` | none (refresh token in body) |
| POST | `/v1/auth/logout` | `logout` | JWT (sub-group inside controller) |

### 2.1 Sign in with Apple

`POST /v1/auth/apple` — `AuthController.signInWithApple`. Verifies the Apple identity token (`Services/AppleAuthService.swift`), upserts the `User`, issues a token pair.

### 2.2 Token Refresh

`POST /v1/auth/refresh` — `AuthController.refreshToken`. Rotates the refresh token (`RefreshToken` model, `Services/JWTService.verifyRefreshToken` / `revokeRefreshToken`).

### 2.3 JWT Specification

> **Divergence from original spec:** Spec §2.3 specified **ES256 asymmetric JWT with a JWKS endpoint**. The implementation signs/verifies with **symmetric HMAC-SHA256 (HS256)** in *all* environments — `configure.swift` adds `app.jwt.keys.add(hmac:digestAlgorithm:.sha256)` using the `JWT_SECRET` env var (production hard-fails if `JWT_SECRET` is unset; it does not switch to ES256). There is no P-256 key, no JWKS, no key rotation endpoint.

> **Code-vs-code contradiction (flagged):** `Services/JWTService.swift`'s header comment claims "ES256 JWT issuing and verification per VAPOR_PROJECT_STRUCTURE.md §8". This comment is **stale and wrong** — the actual signer configured in `configure.swift` is HMAC-SHA256, and `JWTService` signs against that key. `configure.swift` is ground truth; the `JWTService` comment is the bug. (The original audit did not catch this; it inferred HMAC from `configure.swift` only.)

### 2.4 Logout

`POST /v1/auth/logout` — JWT-protected (sub-group inside `AuthController.boot`). Revokes refresh tokens.

### 2.5 Token Rotation on Suspected Compromise

> **Status: NOT IMPLEMENTED.** No `/v1/auth/rotate` route exists.

### 2.6 JWKS Endpoint

> **Status: NOT IMPLEMENTED.** No `/.well-known/jwks.json` route. Not applicable to an HMAC scheme anyway (see §2.3).

### 2.7 JWT Middleware

`Middleware/JWTAuthMiddleware` is real and applied to the `protected` group (`routes.swift`). It verifies HMAC tokens, not ES256. The protected chain is `JWTAuthMiddleware → ToSGateMiddleware` (the ToS gate returns 451 until `tos_accepted_at` is set, with carve-outs for `/v1/user/me`, `/v1/user/accept-tos`, `DELETE /v1/user/me`, `/v1/auth/logout`).

---

## 3. User Management

**Status: IMPLEMENTED (path drift + reduced surface).** Source: `Controllers/UserController.swift`, registered at `routes.swift` under group `user` (NOT `users`), rate-limited 20/min per user.

> **Divergence from original spec:** Spec used `/v1/users/...`. Real base path is **`/v1/user/...`** (singular). Most documented user endpoints (update, avatar, get-by-id, search) do not exist.

Registered routes (the only six that exist):

| Method | Path | Handler | Spec § | Status |
|--------|------|---------|--------|--------|
| GET | `/v1/user/me` | `me` | 3.1 | IMPLEMENTED (path drift `user` vs `users`; narrower response) |
| DELETE | `/v1/user/me` | `deleteMe` | 3.8 | IMPLEMENTED (cascades deletes) |
| POST | `/v1/user/ai-consent` | `setAIConsent` | — | reverse-drift (§32) |
| POST | `/v1/user/accept-tos` | `acceptToS` | — | reverse-drift (§32) |
| PUT | `/v1/user/daily-plan-profile` | `setDailyPlanProfile` | — | reverse-drift (§32) |
| GET | `/v1/user/daily-plan-profile` | `getDailyPlanProfile` | — | reverse-drift (§32) |

### 3.1 Get Current User

`GET /v1/user/me`. Returns tier/consent/displayName subset, not the full documented user object.

### 3.2 Update Current User
> **Status: NOT IMPLEMENTED.** No `PATCH /v1/user/me`.

### 3.3–3.5 Upload Avatar (presign / confirm / direct)
> **Status: NOT IMPLEMENTED.** No avatar routes; no object storage wired.

### 3.6 Get User by ID
> **Status: NOT IMPLEMENTED.** No `/v1/users/:id`.

### 3.7 Search Users
> **Status: NOT IMPLEMENTED.** No user search (see also §17).

### 3.8 Delete Account

`DELETE /v1/user/me` — `UserController.deleteMe`. Implemented; cascades related deletes. ToS-gate carve-out applies.

### 3.9 Recover Deleted Account
> **Status: NOT IMPLEMENTED.** No `/v1/auth/recover` or recover route. (`AuthController` only mentions recovery in an error string.)

---

## 4. User Preferences & Settings

> **Status: NOT IMPLEMENTED.** No preferences routes, no `PreferencesController`, no `preferences` table. The nearest real surface is `PUT|GET /v1/user/daily-plan-profile` (`UserController`, `UserDailyPlanProfile` model) — a different contract documented in §32, not the spec's preferences object.

---

## 5. Whoop Integration

**Status: IMPLEMENTED.** Source: `Controllers/WhoopIntegrationController.swift`, `Controllers/WhoopDataController.swift`, `Controllers/WhoopWebhookController.swift`. Registered at `routes.swift`.

Registered routes:

| Method | Path | Handler | Group / RL |
|--------|------|---------|------------|
| GET | `/v1/integrations/whoop/authorize` | `authorize` | `integrations/whoop`, 10/min user |
| GET | `/v1/integrations/whoop/callback` | `callback` | same |
| GET | `/v1/integrations/whoop/status` | `status` | same |
| DELETE | `/v1/integrations/whoop` | `disconnect` | same |
| GET | `/v1/whoop/recovery` | `getRecovery` | `whoop`, 100/min user |
| GET | `/v1/whoop/sleep` | `getSleep` | same |
| GET | `/v1/whoop/workouts` | `getWorkouts` | same |
| GET | `/v1/whoop/cycles` | `getCycles` | same |
| POST | `/v1/webhooks/whoop` | `handleWebhook` | HMAC-verified, no JWT |

OAuth via `Services/WhoopOAuthService.swift`; API pull via `Services/WhoopAPIService.swift`. Whoop data endpoints use Redis `setex` caching (see §22). Webhook is HMAC-SHA256 verified by `Middleware/WhoopWebhookMiddleware`.

### 5.5 Trigger Full Sync
> **Status: NOT IMPLEMENTED.** No `POST /v1/integrations/whoop/sync` route. Sync happens passively via the webhook + background jobs, not an on-demand endpoint.

### 5.10 Get Whoop Profile / 5.11 Get Body Measurements
> **Status: NOT IMPLEMENTED.** No `/v1/whoop/profile` or `/v1/whoop/body` routes.

---

## 6. NutriTrack Proxy

> **Status: DELETED / REMOVED.** This subsystem was built (`CreateNutriTrackIntegrations` migration) and then **deliberately removed by the `DropNutriTrackIntegrations` migration** (both registered in order in `configure.swift`). No `nutritrack` routes are registered anywhere. Spec §6.1–6.8 and §11.5 (`PATCH /v1/integrations/nutritrack/credentials`) are dead.

> **Divergence from original spec:** NutriTrack was superseded by an in-house **Receipt scan + NutritionAI** pipeline that the original spec never documented:
> - `POST/GET /v1/nutrition/receipts`, `GET|DELETE /v1/nutrition/receipts/:receiptID`, `PATCH /v1/nutrition/receipts/:receiptID/line-items/:lineID`, `POST /v1/nutrition/receipts/structure` (Pro-only Claude Haiku Vision) — `Controllers/ReceiptController.swift`.
> - `POST /v1/nutrition/ai/explain-adjustment | suggest-meal | meal-timing`, `POST /v1/nutrition/ai/proxy/text`, `POST /v1/nutrition/ai/proxy/vision` — `Controllers/NutritionAIController.swift` (whole group Pro-gated by `SubscriptionMiddleware`).
>
> These are documented in full in §32.

---

## 7. Training & Workouts

> **Status: NOT IMPLEMENTED.** No exercise, workout, or workout-plan controllers, routes, or tables exist. The only training-adjacent code is the AI generator `POST /v1/insights/training-program` (`InsightController`), which produces a program but is not the documented CRUD. The `WhoopWorkout` model is passive Whoop-synced data, not user-authored workouts. Spec §7.1–7.7d are entirely unbuilt.

---

## 8. Study Sessions

> **Status: NOT IMPLEMENTED.** No study-session routes, controller, or table. The only study-adjacent code is the AI generator `POST /v1/insights/study-schedule` (`InsightController`). Spec §8.1–8.3 unbuilt.

---

## 9. Daily Snapshots & History

> **Status: NOT IMPLEMENTED.** No snapshot routes, controller, or table. Spec §9.1–9.3 unbuilt.

---

## 10. Arena / Social Endpoints

**Status: IMPLEMENTED (mostly).** Source: `Controllers/XPController.swift`, `LeaderboardController.swift`, `FriendController.swift`, `ChallengeController.swift`, `AchievementController.swift`. Registered at `routes.swift`.

Registered routes:

| Method | Path | Handler | Spec § | Status |
|--------|------|---------|--------|--------|
| POST | `/v1/xp/events` | `recordEvents` | 10.1 | IMPLEMENTED |
| GET | `/v1/xp/today` | `today` | 10.2 | IMPLEMENTED |
| GET | `/v1/xp/history` | `history` | 10.3 | IMPLEMENTED |
| GET | `/v1/xp/level` | `level` | 10.4 | IMPLEMENTED |
| GET | `/v1/leaderboards/:period` | `leaderboard` | 10.5 | IMPLEMENTED |
| GET | `/v1/leaderboards/friends` | `friendsLeaderboard` | 10.5 | IMPLEMENTED |
| POST | `/v1/friends/requests` | `sendRequest` | 10.6 | IMPLEMENTED |
| GET | `/v1/friends/requests` | `listRequests` | 10.6 | IMPLEMENTED |
| POST | `/v1/friends/requests/:requestID/accept` | `acceptRequest` | 10.6 | IMPLEMENTED |
| POST | `/v1/friends/requests/:requestID/decline` | `declineRequest` | 10.6 | IMPLEMENTED |
| GET | `/v1/friends` | `listFriends` | 10.6 | IMPLEMENTED |
| DELETE | `/v1/friends/:friendshipID` | `removeFriend` | 10.6 | IMPLEMENTED |
| POST | `/v1/challenges` | `create` | 10.7 | IMPLEMENTED |
| GET | `/v1/challenges` | `list` | 10.7 | IMPLEMENTED |
| GET | `/v1/challenges/:challengeID` | `detail` | 10.7 | IMPLEMENTED |
| POST | `/v1/challenges/:challengeID/join` | `join` | 10.7 | IMPLEMENTED |
| POST | `/v1/challenges/:challengeID/leave` | `leave` | 10.7 | IMPLEMENTED |
| GET | `/v1/achievements` | `earned` | 10.8 | IMPLEMENTED |
| GET | `/v1/achievements/available` | `available` | 10.8 | IMPLEMENTED |
| POST | `/v1/achievements/check` | `check` | 10.8 | IMPLEMENTED |
| POST | `/v1/achievements/:achievementID/pin` | `pin` | — | reverse-drift (§32) |
| DELETE | `/v1/achievements/:achievementID/pin` | `unpin` | — | reverse-drift (§32) |

> **Note (route ordering):** `GET /v1/leaderboards/friends` is registered after `GET /v1/leaderboards/:period`; Vapor's router prefers the static `friends` segment over the `:period` parameter so both resolve correctly. `GET /v1/achievements` (no subpath) is the "earned" list — not a documented `/earned` subpath.

> **Divergence from original spec:** Leaderboard is split into `/:period` + a static `/friends`, not a single documented `/leaderboards/:period` enum. `GET /v1/achievements` carries the earned list at the group root.

### 10.6 Friendships — partial
> **Status: NOT IMPLEMENTED.** `GET /v1/friends/:id/stats` (spec §10.6) has no route.

### 10.7 Challenges — partial
> **Status: NOT IMPLEMENTED.** `GET /v1/challenges/history` (spec §10.7) has no route.

---

## 11. Non-Negotiables & Accountability

> **Status: NOT IMPLEMENTED.** No accountability routes, controller, or table. Spec §11.1–11.4 unbuilt.
>
> §11.5 (`PATCH /v1/integrations/nutritrack/credentials`) — dead with NutriTrack (see §6).
>
> §11.6 (`GET /v1/rate-limits` status) — **NOT IMPLEMENTED**. `RateLimitMiddleware` enforces limits but exposes no introspection endpoint.

---

## 12. Sync & Batch Operations

> **Status: NOT IMPLEMENTED.** No `/v1/sync/batch` or `/v1/sync/status` routes or controller. Spec §12.1–12.2 unbuilt.

---

## 13. Push Notifications

**Status: IMPLEMENTED (path drift).** Source: `Controllers/DeviceController.swift`, `Services/APNsService.swift`, `Jobs/*`. Registered at `routes.swift` under `devices`, 10/min per user.

Registered routes:

| Method | Path | Handler | Spec § | Status |
|--------|------|---------|--------|--------|
| POST | `/v1/devices/register` | `register` | 13.1 | IMPLEMENTED (path drift: spec said `POST /v1/devices`) |
| DELETE | `/v1/devices/:deviceID` | `remove` | 13.2 | IMPLEMENTED |
| POST | `/v1/devices/test-push` | `testPush` | — | reverse-drift (§32) |

> **Divergence from original spec:** Registration path is `/v1/devices/register`, not `/v1/devices`.

### 13.3–13.4 Notification Types / Payloads
Delivery is real via `Services/APNsService.swift` and the notification background jobs (`Jobs/NotificationScheduleJob`, `DrillSergeantBatchJob`, `WeeklySummaryJob`, `MorningBriefingService`). APNs uses Time Sensitive interruption level (not Critical Alerts), per the feasibility audit.

---

## 14. Outbound Webhooks

> **Status: NOT IMPLEMENTED.** No outbound webhook routes, controller, DLQ, or retry machinery. Only the *inbound* Whoop webhook (§5) exists. Spec §14.1–14.6 unbuilt.

---

## 15. AI Insights

**Status: IMPLEMENTED (method/path drift; far larger surface than documented).** Source: `Controllers/InsightController.swift` (+ `InsightController+Section7.swift`), services in `Services/` (`InsightService`, `DashboardInsightsService`, `RecoveryPrescriptionService`, `TrainingAdjustmentService`, `TrainingProgramService`, `StudyScheduleService`, `MorningBriefingService`, `AchievementCopyService`). Registered at `routes.swift` under `insights`, 20/min per user, **whole group Pro-gated** by `SubscriptionMiddleware`.

Registered routes (all 10):

| Method | Path | Handler | Spec § | Status |
|--------|------|---------|--------|--------|
| GET | `/v1/insights/weekly-report` | `weeklyReport` | 15.1 | DIVERGED (spec said `POST /v1/insights/weekly`) |
| GET | `/v1/insights/patterns` | `patterns` | 15.2 | DIVERGED (spec said `POST /v1/insights/pattern`) |
| GET | `/v1/insights/drill-sergeant` | `drillSergeant` | — | reverse-drift (§32) |
| POST | `/v1/insights/recovery-prescription` | `recoveryPrescription` | — | reverse-drift (§32) |
| GET | `/v1/insights/morning-briefing` | `morningBriefing` | — | reverse-drift (§32) |
| POST | `/v1/insights/training-adjustment` | `trainingAdjustment` | — | reverse-drift (§32) |
| POST | `/v1/insights/dashboard` | `dashboardInsights` | — | reverse-drift (§32) |
| POST | `/v1/insights/training-program` | `trainingProgram` | — | reverse-drift (§32) |
| POST | `/v1/insights/study-schedule` | `studySchedule` | — | reverse-drift (§32) |
| POST | `/v1/insights/achievement-copy` | `achievementCopy` | — | reverse-drift (§32) |

> **Divergence from original spec:** Spec §15.1/§15.2 used `POST /weekly` and `POST /pattern`; the code uses `GET /weekly-report` and `GET /patterns`. Eight further insight endpoints exist that the spec never mentioned (see §32).

### 15.3 Get Insight History
> **Status: NOT IMPLEMENTED.** No `/v1/insights/history` route.

### 15.4 Cost Control / 15.5 Privacy
Real: AI spend is tracked per `Services/AIBudgetTracker.swift` + `AIMonthlySpend` model; responses cached via `Services/AICache.swift` + `CachedAIResponse` model; AI consent gated via `AddAIConsentToUsers` migration + `POST /v1/user/ai-consent`. A per-user daily AI request cap is enforced inside the controller.

---

## 16. Reports & Data Export

> **Status: NOT IMPLEMENTED.** No reports or exports routes/controller. No `POST /v1/reports`, `POST /v1/exports/gdpr`, or `GET /v1/exports/:id`. Spec §16.1–16.4 unbuilt.

---

## 17. Search

> **Status: NOT IMPLEMENTED.** No search routes or controller. Spec §17.1–17.3 unbuilt.

---

## 18. Admin Endpoints

> **Status: NOT IMPLEMENTED.** No admin routes or controller. Spec §18.1–18.4 unbuilt.

---

## 19. App Configuration

> **Status: NOT IMPLEMENTED.** No `GET /v1/config` route or controller. Spec §19.1 unbuilt.

---

## 20. Real-Time (WebSocket)

> **Status: NOT IMPLEMENTED.** No WebSocket route, no SSE, no heartbeat. Spec §20.1–20.3 unbuilt. All client updates are request/response or push (§13).

---

## 21. Database Schema

**Status: IMPLEMENTED (partial — ~half the documented schema).** Source: `Migrations/*`, registered in order in `configure.swift`.

Tables that actually exist (migration → purpose):

| Migration | Table / change |
|-----------|----------------|
| `CreateUsers` | `users` |
| `AddAIConsentToUsers` | `users.ai_consent_*` |
| `AddToSAcceptedToUsers` | `users.tos_accepted_at` |
| `CreateProcessedAppStoreNotifications` | App Store notif dedupe |
| `CreateRefreshTokens` | `refresh_tokens` |
| `CreateWhoopIntegrations` | `whoop_integrations` |
| `CreateWhoopRecovery` / `Sleep` / `Workouts` / `Cycles` | Whoop data tables |
| `CreateNutriTrackIntegrations` → `DropNutriTrackIntegrations` | created then **dropped** |
| `CreateReceipts` / `CreateReceiptLineItems` | receipt pipeline |
| `CreateDeviceTokens` | `device_tokens` |
| `CreateUserSubscriptions` | `user_subscriptions` |
| `CreateAIMonthlySpend` / `CreateAIResponseCache` | AI budget + cache |
| `CreateUserDailyPlanProfiles` | `user_daily_plan_profiles` |
| `CreateXPEvents` / `CreateFriendships` / `CreateChallenges` / `CreateAchievements` / `CreateWeeklyLeaderboard` / `SeedAchievements` | Arena |

> **Divergence from original spec:** Tables for preferences, snapshots, workouts/exercises/workout_plans, study_sessions, accountability/non_negotiables, outbound_webhooks, audit_log, and reports/exports **do not exist**. The NutriTrack table was created and dropped in the same migration list.

---

## 22. Caching Strategy

**Status: IMPLEMENTED (ad-hoc, not centralized).** Source: `WhoopDataController` (Redis `setex` TTLs), `InsightController` (Redis-backed insight cache), `Services/AICache.swift` + `CachedAIResponse`.

> **Divergence from original spec:** There is no centralized cache middleware or declarative per-endpoint TTL table. Caching is per-controller and only on implemented endpoints (Whoop data, AI insights).

---

## 23. Error Codes

**Status: IMPLEMENTED (mechanism), partial (catalog).** Source: `DTOs/ErrorDTO.swift`, `Extensions/Abort+TempoError.swift`, `Middleware/TempoErrorMiddleware.swift`.

The `{code, message, detail?, field?}` error envelope is real and stable. The full numbered 1xxx–5xxx taxonomy from the spec is not exhaustively wired; only codes for features that exist can be emitted. `Abort.identifier` strings (e.g. `subscription_required`, `ai_consent_required`) are the load-bearing machine-readable signals.

---

## 24. Security

**Status: IMPLEMENTED (partial; token spec diverges).** Source: `Middleware/SecurityHeadersMiddleware`, `CORSMiddleware` (`configure.swift`), `Services/EncryptionService.swift`, `Middleware/RateLimitMiddleware`.

Real: security headers middleware (HSTS, X-Content-Type-Options), CORS (`allowedOrigin: .all`, credentials allowed, `X-Request-Id` exposed), encryption-at-rest service, per-group rate limiting, IDOR ownership checks in controllers.

> **Divergence from original spec:** §24.7 token security and §24.10 key rotation assume ES256 + rotating asymmetric keys. Real auth is HMAC-SHA256 with a static `JWT_SECRET` (see §2.3). No documented brute-force lockout or key-rotation schedule is implemented.

---

## 25. Rate Limiting

**Status: IMPLEMENTED.** Source: `Middleware/RateLimitMiddleware`, applied per-group in `routes.swift`.

Actual per-group limits: auth 10/min per IP; whoop-integration 10/min user; whoop-data 100/min user; devices 10/min user; receipts 30/min user; nutrition-ai 20/min user; xp 60/min user; leaderboards 60/min user; friends 20/min user; challenges 60/min user; achievements 60/min user; insights 20/min user; subscription 30/min user; user 20/min user.

> **Status: NOT IMPLEMENTED.** The `GET /v1/rate-limits` status endpoint (spec §11.6) does not exist.

---

## 26. Background Jobs

**Status: IMPLEMENTED.** Source: `Jobs/*`, scheduled in `configure.swift`.

Real jobs: `WeeklySummaryJob`, `LeaderboardRefreshJob`, `NotificationScheduleJob`, `ProcessedNotificationsCleanupJob`, `DrillSergeantBatchJob` (+ `MorningBriefingService`).

> **Divergence from original spec:** Job names differ from the spec's catalog, but the scheduled-job infrastructure is real and substantial.

---

## 27. Observability

**Status: IMPLEMENTED (partial; health path drift).** Source: `routes.swift` (`app.get("health")`), `Middleware/RequestIdMiddleware`.

> **Divergence from original spec:** The health check is `GET /health` (unversioned), **not** `GET /v1/health`. It returns `{"status":"ok"}`.

> **Status: NOT IMPLEMENTED.** `/v1/health/ready` and `/v1/health/live` readiness/liveness probes do not exist. No metrics or distributed-tracing endpoints. `RequestIdMiddleware` provides per-request correlation IDs.

---

## 28. Deployment

> **Infrastructural — not audited against code in this pass.** Deployment topology (Dockerfile, compose, hosting) is environment config, not application routes, and is out of scope for this as-built route reconciliation. Treat the original §28 content as unverified.

## 29. Migration Strategy

> **Infrastructural — not audited against code in this pass.** Migrations exist via Fluent and are registered in order in `configure.swift` (auto-migrate in development); §21 lists the real tables. The original §29 narrative is unverified against code beyond that.

## 30. API Versioning & Deprecation

> **Infrastructural — not audited against code in this pass.** A single `/v1` prefix exists (`routes.swift`); no deprecation-header or version-gating machinery was found, but the policy text is out of scope here. Treat original §30 as unverified.

## 31. Load Testing & Capacity Planning

> **Infrastructural — not audited against code in this pass.** No load-test or capacity artifacts in the application source. Treat original §31 as unverified.

---

## 32. Undocumented Endpoints That Exist (Reverse Drift)

These routes are registered and reachable but were **absent from the original spec**. They are real and must be treated as part of the API contract.

### 32.1 Subscription (StoreKit) — `Controllers/SubscriptionController.swift`

Registered at `routes.swift` under `v1/subscription`, 30/min per user.

| Method | Path | Handler | Auth |
|--------|------|---------|------|
| POST | `/v1/subscription/verify` | `verifyReceipt` | JWT (sub-group in controller) |
| GET | `/v1/subscription/status` | `subscriptionStatus` | JWT (sub-group in controller) |
| POST | `/v1/subscription/webhook` | `handleWebhook` | none — Apple App Store Server Notifications, JWS-verified (`Services/AppStoreNotificationVerifier.swift`) |

Backed by `UserSubscription` model + `ProcessedAppStoreNotification` dedupe. `Middleware/SubscriptionMiddleware` reads this tier to Pro-gate the nutrition-ai and insights groups.

### 32.2 Receipt Scan Pipeline — `Controllers/ReceiptController.swift`

Registered under `v1/nutrition/receipts`, 30/min per user. Replaces NutriTrack §6.

| Method | Path | Handler | Gate |
|--------|------|---------|------|
| POST | `/v1/nutrition/receipts/structure` | `structure` | Pro-only (`SubscriptionMiddleware` on this handler only) — Claude Haiku Vision |
| POST | `/v1/nutrition/receipts` | `create` | JWT |
| GET | `/v1/nutrition/receipts` | `list` | JWT |
| GET | `/v1/nutrition/receipts/:receiptID` | `fetch` | JWT |
| DELETE | `/v1/nutrition/receipts/:receiptID` | `delete` | JWT |
| PATCH | `/v1/nutrition/receipts/:receiptID/line-items/:lineID` | `updateLine` | JWT |

The Pro gate is scoped to `/structure` only (not the group) so downgraded users can still list/fetch existing receipts. Backed by `Receipt` + `ReceiptLineItem` models, `Services/ReceiptStructuringService.swift`.

### 32.3 Nutrition AI — `Controllers/NutritionAIController.swift`

Registered under `v1/nutrition/ai`, 20/min per user, **whole group Pro-gated** by `SubscriptionMiddleware`.

| Method | Path | Handler | Body limit |
|--------|------|---------|------------|
| POST | `/v1/nutrition/ai/explain-adjustment` | `explainAdjustment` | default |
| POST | `/v1/nutrition/ai/suggest-meal` | `suggestMeal` | default |
| POST | `/v1/nutrition/ai/meal-timing` | `mealTiming` | default |
| POST | `/v1/nutrition/ai/proxy/text` | `proxyText` | 256 KB |
| POST | `/v1/nutrition/ai/proxy/vision` | `proxyVision` | 5 MB |

Backed by `Services/NutritionAIService.swift`, `NutritionClaudeProxyService.swift`, `MealTimingService.swift`.

### 32.4 User extras — `Controllers/UserController.swift`

`POST /v1/user/ai-consent`, `POST /v1/user/accept-tos` (ToS-gate carve-out), `PUT|GET /v1/user/daily-plan-profile` (`UserDailyPlanProfile` model). See §3 table.

### 32.5 Insights extras — `Controllers/InsightController.swift`

Eight endpoints beyond the two diverged spec ones: `GET /drill-sergeant`, `POST /recovery-prescription`, `GET /morning-briefing`, `POST /training-adjustment`, `POST /dashboard`, `POST /training-program`, `POST /study-schedule`, `POST /achievement-copy`. All Pro-gated (group-level `SubscriptionMiddleware`). See §15 table.

### 32.6 Achievements / Devices extras

`POST /v1/achievements/:achievementID/pin`, `DELETE /v1/achievements/:achievementID/pin` (`AchievementController`). `POST /v1/devices/test-push` (`DeviceController`).

---

## Appendix A — Route Inventory (ground truth, 68 routes)

| # | Method | Path |
|---|--------|------|
| 1 | GET | `/health` |
| 2 | POST | `/v1/auth/apple` |
| 3 | POST | `/v1/auth/refresh` |
| 4 | POST | `/v1/auth/logout` |
| 5 | GET | `/v1/integrations/whoop/authorize` |
| 6 | GET | `/v1/integrations/whoop/callback` |
| 7 | GET | `/v1/integrations/whoop/status` |
| 8 | DELETE | `/v1/integrations/whoop` |
| 9 | GET | `/v1/whoop/recovery` |
| 10 | GET | `/v1/whoop/sleep` |
| 11 | GET | `/v1/whoop/workouts` |
| 12 | GET | `/v1/whoop/cycles` |
| 13 | POST | `/v1/devices/register` |
| 14 | DELETE | `/v1/devices/:deviceID` |
| 15 | POST | `/v1/devices/test-push` |
| 16 | POST | `/v1/nutrition/receipts/structure` |
| 17 | POST | `/v1/nutrition/receipts` |
| 18 | GET | `/v1/nutrition/receipts` |
| 19 | GET | `/v1/nutrition/receipts/:receiptID` |
| 20 | DELETE | `/v1/nutrition/receipts/:receiptID` |
| 21 | PATCH | `/v1/nutrition/receipts/:receiptID/line-items/:lineID` |
| 22 | POST | `/v1/nutrition/ai/explain-adjustment` |
| 23 | POST | `/v1/nutrition/ai/suggest-meal` |
| 24 | POST | `/v1/nutrition/ai/meal-timing` |
| 25 | POST | `/v1/nutrition/ai/proxy/text` |
| 26 | POST | `/v1/nutrition/ai/proxy/vision` |
| 27 | POST | `/v1/xp/events` |
| 28 | GET | `/v1/xp/today` |
| 29 | GET | `/v1/xp/history` |
| 30 | GET | `/v1/xp/level` |
| 31 | GET | `/v1/leaderboards/:period` |
| 32 | GET | `/v1/leaderboards/friends` |
| 33 | POST | `/v1/friends/requests` |
| 34 | GET | `/v1/friends/requests` |
| 35 | POST | `/v1/friends/requests/:requestID/accept` |
| 36 | POST | `/v1/friends/requests/:requestID/decline` |
| 37 | GET | `/v1/friends` |
| 38 | DELETE | `/v1/friends/:friendshipID` |
| 39 | POST | `/v1/challenges` |
| 40 | GET | `/v1/challenges` |
| 41 | GET | `/v1/challenges/:challengeID` |
| 42 | POST | `/v1/challenges/:challengeID/join` |
| 43 | POST | `/v1/challenges/:challengeID/leave` |
| 44 | GET | `/v1/achievements` |
| 45 | GET | `/v1/achievements/available` |
| 46 | POST | `/v1/achievements/check` |
| 47 | POST | `/v1/achievements/:achievementID/pin` |
| 48 | DELETE | `/v1/achievements/:achievementID/pin` |
| 49 | GET | `/v1/insights/weekly-report` |
| 50 | GET | `/v1/insights/patterns` |
| 51 | GET | `/v1/insights/drill-sergeant` |
| 52 | POST | `/v1/insights/recovery-prescription` |
| 53 | GET | `/v1/insights/morning-briefing` |
| 54 | POST | `/v1/insights/training-adjustment` |
| 55 | POST | `/v1/insights/dashboard` |
| 56 | POST | `/v1/insights/training-program` |
| 57 | POST | `/v1/insights/study-schedule` |
| 58 | POST | `/v1/insights/achievement-copy` |
| 59 | POST | `/v1/subscription/verify` |
| 60 | GET | `/v1/subscription/status` |
| 61 | POST | `/v1/subscription/webhook` |
| 62 | GET | `/v1/user/me` |
| 63 | DELETE | `/v1/user/me` |
| 64 | POST | `/v1/user/ai-consent` |
| 65 | POST | `/v1/user/accept-tos` |
| 66 | PUT | `/v1/user/daily-plan-profile` |
| 67 | GET | `/v1/user/daily-plan-profile` |
| 68 | POST | `/v1/webhooks/whoop` |
