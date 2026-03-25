# Tempo -- Error Recovery Flows

> **Version:** 1.0.0
> **Last updated:** 2026-03-24
> **Author:** Reliability Engineering Review
> **Philosophy:** Failure is the default state. Success is the exception. Every error has a plan.
> **Status:** Production reference

This document defines the complete error recovery flow for every failure mode in the Tempo app. The goal: the user should never see a broken screen. Every failure degrades gracefully, recovers automatically when possible, and communicates honestly when it cannot.

---

## Table of Contents

1. [Network Errors (NET-001 through NET-011)](#1-network-errors)
2. [Integration Errors (INT-001 through INT-012)](#2-integration-errors)
3. [Data Errors (DAT-001 through DAT-010)](#3-data-errors)
4. [User Experience Errors (UXE-001 through UXE-010)](#4-user-experience-errors)
5. [Backend Errors (SRV-001 through SRV-012)](#5-backend-errors)
6. [Authentication Errors (AUTH-001 through AUTH-006)](#6-authentication-errors)
7. [Error Severity Classification](#7-error-severity-classification)
8. [Global Retry Policy](#8-global-retry-policy)
9. [Offline Queue Architecture](#9-offline-queue-architecture)

---

## Global Conventions

**User communication tiers:**

| Tier | Visual | Duration | When to use |
|------|--------|----------|-------------|
| Silent | Nothing visible | N/A | Automatic recovery succeeds within 2 seconds |
| Toast | Bottom slide-up, `tempo.caption1`, card background | 2 seconds auto-dismiss | Single-source failure, cached data available |
| Banner | Top persistent bar, `tempo.offline.bg` | Until resolved | Connectivity loss, multi-source failures |
| Inline | Per-component error state | Until resolved | Source-specific failure (single quadrant) |
| Full-screen | Modal overlay with action button | Until user acts | Unrecoverable state (auth expired, DB corrupt) |

**Logging convention (all errors):**

```json
{
  "error_code": "NET-001",
  "error_name": "internet_loss_dashboard_load",
  "timestamp": "ISO 8601",
  "user_id": "usr_xxx (hashed)",
  "device_id": "UUID",
  "app_version": "1.x.x",
  "os_version": "iOS xx.x",
  "context": { "screen": "dashboard", "connection_type": "none" },
  "recovery_action": "served_cache",
  "trace_id": "trace_xxx"
}
```

---

## 1. Network Errors

### [NET-001] Complete Internet Loss During Dashboard Load

**Trigger:** `NWPathMonitor` reports `path.status == .unsatisfied` while `SyncService.fullSync()` is executing on app launch or foreground resume.

**Detection:** `NWPathMonitor` callback fires. All in-flight URLSession tasks receive `NSURLErrorNotConnectedToInternet` (-1009). Detected within 100ms of network state change.

**User Impact:** Dashboard cannot refresh. If first launch with no cache, user sees empty quadrants. If cache exists, data may be hours old.

**Immediate Response (< 100ms):**
1. Cancel all in-flight network requests to free resources.
2. Set `DashboardState.isOffline = true`.
3. Trigger UI update to show offline banner.

**Recovery Strategy:**
1. Display offline banner: "Offline -- showing cached data" with `wifi.slash` icon, `tempo.offline.bg` background, `tempo.caption1` font.
2. Load all quadrants from SwiftData cache. Apply staleness indicators per source thresholds (Whoop > 30 min, NutriTrack > 20 min, HealthKit > 10 min for HR).
3. Local data (Mind quadrant, non-negotiables) continues to function normally -- these do not require network.
4. Register `NWPathMonitor` callback for connectivity restoration.
5. On reconnect: wait 1 second (debounce flapping connections), then trigger `fullSync()` automatically. Dismiss offline banner on first successful source sync.

**Fallback:** If no cache exists (first launch while offline):
- Body quadrant: Show "Connect to load recovery data" with a retry button.
- Fuel quadrant: Show "Connect to load nutrition data" with a retry button.
- Move quadrant: HealthKit data is local -- steps and active energy still load from on-device HealthKit store. Show normally.
- Mind quadrant: Fully functional (local SwiftData).
- Daily score: Show "--" (insufficient sources for calculation).

**Prevention:** Pre-fetch and cache aggressively. Background app refresh (`BGAppRefreshTask`) runs every 15 minutes for Whoop, every 10 minutes for NutriTrack. HealthKit observer queries deliver data passively.

**Monitoring:**
- Telemetry: Track `offline_dashboard_loads` counter with label `has_cache: true/false`.
- Alert threshold: If > 20% of dashboard loads are offline for any user over 24 hours, flag for review (possible device issue).

**Retry strategy:** No retry while offline. Automatic retry on reconnect.
**User communication:** Banner (persistent until resolved).
**Logging:** Level `info`. Log duration of offline period on reconnect.

---

### [NET-002] Internet Loss During Active Workout Logging

**Trigger:** Network drops while user is in Active Workout View (RepForge module) and has logged one or more sets. Sets are being written to local SwiftData and queued for backend sync.

**Detection:** `NWPathMonitor` status change, or URLSession task failure on background snapshot upload.

**User Impact:** Zero data loss risk. The workout continues entirely locally. The user may not notice at all.

**Immediate Response (< 100ms):**
1. Set offline flag.
2. Suppress any sync-related toasts during active workout (critical UX -- do not interrupt someone mid-set).
3. Continue all workout functionality: set logging, rest timer, PR detection, plate calculator.

**Recovery Strategy:**
1. Every set completion persists full workout state to SwiftData (exercise index, set data, timestamps, rest durations). This is the crash-safe checkpoint.
2. Workout summary screen at the end queues the completed workout for backend upload.
3. On reconnect, `SyncService` drains the offline queue: uploads workout data, triggers XP events, sends daily snapshot.
4. If the user completes the workout and closes the app before reconnection, the queued upload persists in SwiftData and executes on next app launch.

**Fallback:** If upload fails after 3 retries post-reconnect:
- Workout data remains in local SwiftData (never lost).
- A subtle badge appears on the Training tab: "1 workout pending sync."
- The workout is included in local progress charts and PR tracking immediately.
- Backend sync retries on next app launch.

**Prevention:** Workout logging is offline-first by design. Network is never in the critical path of set logging.

**Monitoring:**
- Telemetry: Track `workouts_completed_offline` counter.
- Track `workout_sync_delay_seconds` histogram (time between workout completion and successful backend upload).
- Alert: If any workout remains unsynced for > 48 hours.

**Retry strategy:** Exponential backoff (2s, 4s, 8s) after reconnection. Max 3 retries per sync cycle.
**User communication:** Silent during workout. Toast post-workout if sync fails: "Workout saved locally. Will sync when connected."
**Logging:** Level `info`. Include workout duration and set count.

---

### [NET-003] Internet Loss During Whoop OAuth Flow

**Trigger:** Network drops during the multi-step Whoop OAuth2 flow: (a) fetching authorization URL from backend, (b) during browser-based Whoop login, or (c) during code exchange callback.

**Detection:**
- Step (a): `URLSession` returns `NSURLErrorNotConnectedToInternet`.
- Step (b): `ASWebAuthenticationSession` browser shows a loading error page. No callback fires.
- Step (c): Backend callback fails to reach Whoop token endpoint, returns error redirect to iOS.

**User Impact:** Whoop connection fails. User must restart the flow.

**Immediate Response (< 100ms):**
1. Set `WhoopService.connectionState = .error(.networkUnavailable)`.
2. Dismiss `ASWebAuthenticationSession` if active (step b).
3. Clean up any pending state tokens in Redis (backend-side, with 10-min TTL auto-expiry).

**Recovery Strategy:**
1. Show error on `WhoopConnectView`: "No internet connection. Connect to Wi-Fi or cellular to link Whoop." with a "Try Again" button.
2. Do NOT auto-retry the OAuth flow -- it requires user interaction (browser login).
3. When user taps "Try Again," verify network is available before starting. If still offline, show the same message immediately without launching the browser.
4. If failure occurred at step (c) specifically (code obtained but exchange failed), the authorization code is single-use and expired. The user must re-authorize. Clean explanation: "Connection interrupted. Please authorize again."

**Fallback:** User continues with Whoop disconnected. Body quadrant shows "Connect Whoop" prompt. Dashboard calculates daily score without recovery data (weight redistributed to available sources, or "--" if < 2 sources).

**Prevention:** Pre-check network before starting OAuth flow. Show a blocking message if offline.

**Monitoring:**
- Telemetry: Track `whoop_oauth_failures` counter with label `step: authorize_url|browser|callback`.
- Track `whoop_oauth_completion_rate` (starts vs. successful completions).
- Alert: If completion rate drops below 70% over 24 hours.

**Retry strategy:** Never auto-retry (requires user action).
**User communication:** Inline error on connection screen.
**Logging:** Level `warning`. Include failure step and underlying error.

---

### [NET-004] Backend Server Down (503 Service Unavailable)

**Trigger:** Tempo backend returns HTTP 503, or the load balancer returns 503 when all instances are unhealthy.

**Detection:** `APIClient` receives 503 status code. Health check endpoint `/v1/health/ready` returns 503.

**User Impact:** All backend-dependent features are unavailable: Whoop data sync, NutriTrack proxy, XP/leaderboard, AI insights, push notification registration. Local features (HealthKit, study timer, non-negotiables) continue working.

**Immediate Response (< 100ms):**
1. Mark backend as unreachable in `APIClient` state.
2. Serve all data from cache.
3. Queue all mutating operations (XP events, workout uploads, snapshot uploads) in the offline queue.

**Recovery Strategy:**
1. Show toast: "Server temporarily unavailable. Using cached data."
2. Implement circuit breaker pattern:
   - After 3 consecutive 503 responses within 60 seconds, open the circuit.
   - While circuit is open: skip network requests, serve cache, check health endpoint every 30 seconds.
   - When health endpoint returns 200, close circuit and trigger `fullSync()`.
3. Drain offline queue on recovery.

**Fallback:**
- Dashboard: Cached data with staleness indicators. Daily score uses last calculated value.
- Training: Fully functional (offline-first). Workout uploads queued.
- Accountability: Fully functional (local). Whoop/NutriTrack auto-tracking paused; manual tracking works.
- Arena: XP display frozen at last known value. Leaderboard shows cached state.
- AI insights: Rule-based fallback from local pattern engine with `[offline insight]` badge.

**Prevention:** Backend runs minimum 2 replicas. Rolling deployments ensure zero-downtime. Health checks configured at 30-second intervals.

**Monitoring:**
- Telemetry: Track `backend_503_count` counter.
- Track `circuit_breaker_state` gauge (0 = closed, 1 = open).
- Alert: Error rate > 5% 5xx for 5 minutes = Critical.

**Retry strategy:** Circuit breaker with 30-second health check polling.
**User communication:** Toast on first occurrence. Banner if persists > 2 minutes.
**Logging:** Level `error`. Include request path, response body if available.

---

### [NET-005] Backend Response Timeout

**Trigger:** `URLSession` request exceeds its timeout interval. Default timeouts: 10 seconds for data requests, 15 seconds for auth requests, 60 seconds for sync operations.

**Detection:** `URLSession` fires `NSURLErrorTimedOut` (-1001).

**User Impact:** Specific data fails to load. If timeout occurs during pull-to-refresh, the spinner shows for unusually long before resolving.

**Immediate Response (< 100ms):**
1. Cancel the timed-out request.
2. Serve cached data for the affected source.
3. Apply stale indicator to the affected quadrant.

**Recovery Strategy:**
1. If pull-to-refresh: Show toast "[Source] sync timed out" (auto-dismiss 2 seconds). End refresh animation.
2. If background sync: Log the timeout, add to retry queue with exponential backoff.
3. If the timeout occurs on a critical path (auth refresh): retry immediately once, then escalate.
4. Retry schedule: 1st retry after 5 seconds, 2nd after 15 seconds, 3rd after 45 seconds. Max 3 retries.

**Fallback:** Cached data with stale indicators. If no cache: component shows its disconnected state.

**Prevention:**
- Set appropriate timeout intervals per endpoint category.
- Backend implements request deadlines: if processing exceeds 8 seconds, return partial results with a `X-Partial-Response: true` header.

**Monitoring:**
- Telemetry: Track `request_timeout_count` counter by endpoint.
- Track `request_duration_ms` histogram for p95/p99 monitoring.
- Alert: If p99 latency exceeds 5 seconds for 10 minutes.

**Retry strategy:** Exponential backoff (5s, 15s, 45s). Max 3 retries.
**User communication:** Toast if user-initiated. Silent if background.
**Logging:** Level `warning`. Include endpoint, timeout duration, retry count.

---

### [NET-006] DNS Resolution Failure

**Trigger:** Device cannot resolve `api.tempo.app` to an IP address. Causes: DNS server unreachable, DNS cache expired while offline, corporate/university network DNS filtering.

**Detection:** `URLSession` returns `NSURLErrorCannotFindHost` (-1003) or `NSURLErrorDNSLookupFailed` (-1006).

**User Impact:** Identical to complete backend outage. All backend-dependent features unavailable.

**Immediate Response (< 100ms):**
1. Check `NWPathMonitor` -- if network is actually available, this is a DNS-specific issue.
2. Serve cached data.
3. Set specific error state: "Cannot reach Tempo servers."

**Recovery Strategy:**
1. If `NWPathMonitor` reports connected but DNS fails: retry with a 5-second delay (DNS may be temporarily unreachable).
2. After 3 DNS failures: show banner "Cannot reach Tempo servers. Check your network connection."
3. Continue retrying every 30 seconds in background.
4. On success: dismiss banner, trigger full sync.

**Fallback:** Same as NET-004 (backend down). All local features continue.

**Prevention:** Consider implementing DNS-over-HTTPS as a fallback if system DNS fails consistently for a user.

**Monitoring:**
- Telemetry: Track `dns_failure_count` counter.
- Alert: If > 10% of users experience DNS failures in a 1-hour window (possible DNS infrastructure issue).

**Retry strategy:** Fixed interval (30 seconds) since DNS issues often resolve with network changes.
**User communication:** Banner after 3 consecutive failures.
**Logging:** Level `warning`. Include resolved hostname and network type (WiFi/cellular).

---

### [NET-007] SSL/TLS Certificate Error

**Trigger:** Certificate pinning failure, expired certificate, self-signed certificate, or man-in-the-middle interception. `URLSession` returns `NSURLErrorServerCertificateUntrusted` (-1202) or related SSL errors.

**Detection:** `URLSession` delegate receives `didReceive challenge` for `NSURLAuthenticationMethodServerTrust` and validation fails.

**User Impact:** All backend communication is blocked. This is treated as a security event, not a transient error.

**Immediate Response (< 100ms):**
1. Reject the connection -- never bypass SSL validation.
2. Log a security event with full certificate chain details.
3. Block all backend requests until resolved.

**Recovery Strategy:**
1. Show banner: "Secure connection failed. If you're on a public or corporate network, try switching to cellular data."
2. Do NOT retry automatically on the same network -- the issue is likely environmental.
3. If user switches networks (detected via `NWPathMonitor`), retry once.
4. If the certificate pin itself is outdated (after app hasn't been updated in months): the pin configuration should include backup pins. If all pins fail, fall back to standard system trust evaluation with a logged warning.

**Fallback:** Complete graceful degradation to offline mode. All local features work. No data syncs.

**Prevention:**
- Certificate pins include primary + backup pins.
- Pin rotation aligned with certificate renewal schedule (every 90 days).
- App update pushes new pins before old certificate expires.
- Monitor certificate expiry with 14-day warning alerts.

**Monitoring:**
- Telemetry: Track `ssl_error_count` counter with label `reason: pin_mismatch|expired|untrusted`.
- Alert: Any spike in SSL errors is Critical severity (possible MITM or certificate misconfiguration).

**Retry strategy:** Retry only on network change. Never auto-retry on same network.
**User communication:** Banner (persistent).
**Logging:** Level `critical`. Include certificate subject, issuer, expiry, pin hash.

---

### [NET-008] Response Too Large

**Trigger:** Backend response exceeds the iOS client's configured maximum response size (10 MB for standard responses, 50 MB for data exports).

**Detection:** `URLSession` download progress exceeds threshold, or `NSURLErrorDataLengthExceedsMaximum` error.

**User Impact:** The specific request fails. Most commonly occurs during full historical sync (Whoop 30-day backfill, NutriTrack export).

**Immediate Response (< 100ms):**
1. Cancel the download.
2. Free memory allocated for the response.

**Recovery Strategy:**
1. If this is a paginated endpoint: reduce `limit` parameter and retry with smaller pages.
2. If this is a bulk export: request a smaller date range (e.g., split 90 days into three 30-day chunks).
3. If this is a standard endpoint returning unexpectedly large data: log error, serve cache, report to analytics.

**Fallback:** Cached data for affected source. If no cache: show "Data temporarily unavailable."

**Prevention:** Backend enforces response size limits. Paginated endpoints default to `limit=25`, max `limit=100`. Bulk operations stream data or use pagination.

**Monitoring:**
- Telemetry: Track `response_too_large_count` by endpoint.
- Alert: If any non-export endpoint triggers this, it indicates a backend bug.

**Retry strategy:** Immediate retry with reduced payload (smaller page size or date range).
**User communication:** Silent if retry succeeds. Toast if all retries fail.
**Logging:** Level `warning`. Include endpoint, response size, configured limit.

---

### [NET-009] Malformed JSON Response

**Trigger:** Backend returns a response that cannot be decoded by `JSONDecoder`. Causes: backend bug, proxy/CDN injecting HTML error pages, response truncated mid-stream.

**Detection:** `JSONDecoder.decode()` throws `DecodingError` (`.typeMismatch`, `.keyNotFound`, `.valueNotFound`, `.dataCorrupted`).

**User Impact:** The specific request fails. If critical data (auth token, dashboard snapshot), feature is temporarily broken.

**Immediate Response (< 100ms):**
1. Catch the `DecodingError` without crashing.
2. Log the raw response body (first 1KB) for debugging.
3. Serve cached data for the affected resource.

**Recovery Strategy:**
1. Retry the request once (the malformed response may be a transient proxy issue).
2. If retry also returns malformed JSON: mark source as temporarily unavailable, serve cache.
3. Report to analytics with the raw response snippet (scrubbed of sensitive data).
4. Check `Content-Type` header -- if it's `text/html` instead of `application/json`, a proxy or CDN is likely serving an error page. Log specifically.

**Fallback:** Cached data with stale indicators. If no cache: component shows disconnected state.

**Prevention:** Backend validates all response serialization in tests. CDN configured to not cache error pages. Client validates `Content-Type: application/json` before attempting decode.

**Monitoring:**
- Telemetry: Track `json_decode_error_count` by endpoint and `DecodingError` type.
- Alert: Any spike > 5 decode errors in 5 minutes = Warning (possible backend deployment issue).

**Retry strategy:** Immediate retry once. No further retries (if the response is consistently malformed, retrying is pointless).
**User communication:** Silent if cache serves. Toast if no cache: "[Feature] temporarily unavailable."
**Logging:** Level `error`. Include endpoint, decoding error type, raw response snippet (first 1KB, no tokens).

---

### [NET-010] Rate Limited by Tempo Backend (429)

**Trigger:** Client exceeds per-endpoint rate limit. Backend returns HTTP 429 with `Retry-After` header and error code 5001.

**Detection:** `APIClient` receives 429 status code. Response includes `retry_after_seconds` field.

**User Impact:** The specific request is rejected. If pull-to-refresh: refresh appears to fail. If background sync: sync is delayed.

**Immediate Response (< 100ms):**
1. Parse `retry_after_seconds` from response body.
2. Do NOT retry immediately.
3. Serve cached data.

**Recovery Strategy:**
1. Schedule retry after `retry_after_seconds` (typically 30s).
2. If the user triggers another request to the same endpoint before the retry window: silently serve cache, do not fire network request.
3. Implement client-side rate awareness: track remaining quota from `X-RateLimit-Remaining` header. When remaining < 10%, throttle non-essential requests.
4. If rate-limited on auth endpoint: this may indicate a credential replay attack. Log security event.

**Fallback:** Cached data. Rate limiting should be invisible to the user during normal use.

**Prevention:**
- Client-side request deduplication (do not fire identical requests within cache TTL).
- Debounce pull-to-refresh (minimum 10 seconds between refreshes).
- Coalesce background sync requests (one full sync, not per-source individual calls).

**Monitoring:**
- Telemetry: Track `rate_limit_hit_count` by endpoint.
- Track `rate_limit_remaining` gauge per endpoint category.
- Alert: If any user hits rate limits > 10 times in 1 hour, investigate usage pattern.

**Retry strategy:** Respect `Retry-After` header exactly. Single retry after delay.
**User communication:** Silent. Rate limits should not be user-visible.
**Logging:** Level `warning`. Include endpoint, rate limit tier, remaining count.

---

### [NET-011] CDN Cache Stale / Serving Outdated Content

**Trigger:** CloudFront serves a cached version of a resource (exercise library, achievement definitions, app config) that is outdated due to failed cache invalidation.

**Detection:** Client-side: `ETag` mismatch between cached and served resource, or `X-Cache: Hit` header with a `Date` header significantly older than expected. Also detectable when the client receives data that does not match the server's latest version counter.

**User Impact:** User sees outdated exercise descriptions, old achievement definitions, or stale app configuration. Low severity for most resources.

**Immediate Response (< 100ms):**
1. If `ETag` mismatch detected on `If-None-Match` request: use the newly served version.
2. If data appears structurally outdated (missing expected fields from a schema update): fall back to local defaults.

**Recovery Strategy:**
1. Force-refresh by appending `?cache_bust={timestamp}` query parameter.
2. If force-refresh returns the same stale data: the CDN invalidation is broken. Use the local cached version and log.
3. For critical configuration (feature flags, minimum app version): always bypass CDN by calling `/v1/config` with `Cache-Control: no-cache` header.

**Fallback:** Use locally bundled defaults for exercise library and achievement definitions (shipped with the app binary).

**Prevention:** CDN invalidation on write. Version counter in cache keys (`cache:exercises:v{N}:{params}`). Background job verifies CDN freshness every hour.

**Monitoring:**
- Telemetry: Track `cdn_stale_serve_count` by resource type.
- Alert: If CDN serves stale config for > 1 hour after update.

**Retry strategy:** Immediate force-refresh once. Then accept cached version.
**User communication:** Silent. User should never know about CDN layer.
**Logging:** Level `info`. Include resource URL, cached version, expected version.

---

## 2. Integration Errors

### [INT-001] Whoop API Returns 401 (Token Expired Mid-Sync)

**Trigger:** Backend makes a Whoop API call and receives HTTP 401. The access token has expired (1-hour TTL) or was revoked.

**Detection:** Backend `WhoopTokenManager` detects 401 response from `api.prod.whoop.com`.

**User Impact:** Whoop data sync pauses momentarily during token refresh. If refresh succeeds: zero user impact. If refresh fails: Whoop data becomes stale.

**Immediate Response (< 100ms):**
1. Backend `WhoopTokenManager` (actor) initiates token refresh.
2. All concurrent Whoop API calls for this user await the same refresh `Task` (deduplication via `refreshTasks` dictionary).
3. Original request is queued for retry after refresh.

**Recovery Strategy:**
1. Refresh flow: `POST https://api.prod.whoop.com/oauth/oauth2/token` with `grant_type=refresh_token`.
2. If refresh succeeds (200): store new tokens, retry the original request. Total interruption < 2 seconds.
3. If refresh returns 401/400 (refresh token expired/revoked):
   a. Mark integration as `token_revoked`.
   b. Send push notification to user: "Whoop disconnected. Tap to reconnect."
   c. iOS shows Body quadrant in "Connect Whoop" state.
4. If refresh returns 500/502/503 (Whoop servers down): retry 3 times with exponential backoff (2s, 4s, 8s). If all fail, mark as `degraded`. Serve cached data.
5. If refresh returns 429 (rate limited): respect `Retry-After` header and queue.

**Fallback:** Body quadrant shows last cached Whoop data with stale indicator. Recovery recommendations use yesterday's data with note: "Using yesterday's recovery: XX%."

**Prevention:** Backend refreshes tokens proactively when < 5 minutes remain (buffer). The `WhoopTokenManager` checks expiry before every API call.

**Monitoring:**
- Telemetry: Track `whoop_token_refresh_count` (success/failure/revoked).
- Track `whoop_token_refresh_duration_ms` histogram.
- Alert: If > 3 consecutive refresh failures per user, notify user. If > 10% of active users have revoked tokens, investigate Whoop-side changes.

**Retry strategy:** Automatic. Immediate refresh + original request retry.
**User communication:** Silent if refresh succeeds. Push notification if token revoked.
**Logging:** Level `info` for successful refresh. Level `warning` for failure. Level `error` for revocation.

---

### [INT-002] Whoop API Returns 429 (Rate Limited)

**Trigger:** Too many requests to `api.prod.whoop.com`. Whoop rate limits are per-application, not per-user.

**Detection:** Backend receives HTTP 429 with `Retry-After` header from Whoop API.

**User Impact:** Whoop data sync is delayed by the retry window (typically 30-120 seconds). Cached data served in the meantime.

**Immediate Response (< 100ms):**
1. Parse `Retry-After` header.
2. Queue the failed request.
3. Serve cached data to all affected users.

**Recovery Strategy:**
1. Respect `Retry-After` exactly.
2. Implement request queuing with priority: recovery data > sleep data > workout data > cycle data > body measurements.
3. If rate limiting persists (>5 consecutive 429s): reduce polling frequency to half for all users for 10 minutes.
4. The daily reconciliation cron job (3:00 AM UTC) includes a 1-second delay between users to stay well within rate limits.

**Fallback:** Cached data with stale indicators. No data is lost -- just delayed.

**Prevention:**
- 1-second delay between users in batch operations.
- Webhook-driven sync reduces polling dependency.
- Client-side request coalescing prevents redundant API calls.

**Monitoring:**
- Telemetry: Track `whoop_rate_limit_count` counter.
- Track `whoop_rate_limit_retry_after_seconds` histogram.
- Alert: > 10 rate limits in 5 minutes = Warning (need to adjust polling strategy).

**Retry strategy:** Respect `Retry-After`. Exponential backoff if header absent (30s, 60s, 120s).
**User communication:** Silent. Data appears slightly delayed with stale indicators.
**Logging:** Level `warning`. Include endpoint, retry-after value, queue depth.

---

### [INT-003] Whoop Webhook Delivery Failure

**Trigger:** Whoop fails to deliver a webhook event to `POST /v1/webhooks/whoop`. Causes: Tempo backend temporarily down, network issue between Whoop and Tempo, timeout.

**Detection:** Webhook never arrives -- detected indirectly by the daily reconciliation cron job at 3:00 AM UTC, which finds data gaps between Whoop API and local records.

**User Impact:** Data update is delayed until the next polling cycle or daily reconciliation. For recovery data: up to 30 minutes delay (next poll). For workouts: up to 24 hours (next reconciliation) if no foreground sync occurs.

**Immediate Response:** N/A -- the failure is external to Tempo's control.

**Recovery Strategy:**
1. Whoop retries failed webhooks automatically (Whoop's retry policy: 3 attempts with exponential backoff).
2. Backend idempotency check via `trace_id` in Redis (24-hour TTL) prevents duplicate processing if both Whoop retry and Tempo poll deliver the same event.
3. Regular polling backfills missed webhooks: recovery/sleep polled every 30 minutes, cycles every 15 minutes.
4. Daily reconciliation cron (3:00 AM UTC) fetches last 3 days from all Whoop endpoints, filling any gaps.
5. On app foreground: `fullSync()` fetches today's data regardless of webhook status.

**Fallback:** The triple-layer approach (webhooks + polling + daily reconciliation) ensures data gaps are temporary.

**Prevention:** Backend health checks ensure webhook endpoint is reachable. 200 response returned immediately before async processing (fire-and-forget) to minimize Whoop-perceived latency.

**Monitoring:**
- Telemetry: Track `whoop_webhook_received_count` by event type.
- Track `whoop_reconciliation_gaps_found` counter.
- Alert: If reconciliation finds gaps for > 50% of active users, investigate webhook endpoint health.

**Retry strategy:** Automatic via Whoop retries + Tempo polling + daily reconciliation.
**User communication:** Silent. User never knows webhooks exist.
**Logging:** Level `info` for reconciliation fills. Level `warning` if gaps > 6 hours.

---

### [INT-004] Whoop Returns PENDING Recovery (Not Scored Yet)

**Trigger:** Backend fetches recovery and `score_state == "PENDING"`. This happens 5-15 minutes after sleep ends while Whoop computes the recovery score.

**Detection:** Backend parses `score_state` field. iOS receives null `score` object with `scoreState: .pending`.

**User Impact:** Recovery score unavailable temporarily. Training module cannot make recovery-based adjustments.

**Immediate Response (< 100ms):**
1. Body quadrant shows loading spinner with "Recovery score processing..." text.
2. Training module defers recovery-based workout adjustments.

**Recovery Strategy:**
1. Poll every 2 minutes for up to 30 minutes.
2. On each poll: check if `score_state` has changed to `"SCORED"`.
3. If scored: update dashboard immediately with counter-roll animation on recovery number.
4. If still pending after 30 minutes: show "Recovery score unavailable" and use yesterday's recovery for training recommendations with note: "Using yesterday's recovery: XX%."
5. If a `recovery.updated` webhook arrives during polling: process immediately, cancel further polls.

**Fallback:** Yesterday's recovery score used for all recovery-dependent features. Body quadrant shows "Recovery pending" with yesterday's value dimmed.

**Prevention:** Cannot prevent -- this is Whoop's processing pipeline. The morning notification timing accounts for this: "Your recovery is ready" push only sent after score_state == SCORED.

**Monitoring:**
- Telemetry: Track `recovery_pending_duration_seconds` histogram (time from first PENDING to SCORED).
- Alert: If average pending duration > 30 minutes, Whoop may have processing issues.

**Retry strategy:** Fixed 2-minute polling interval. Max 15 polls (30 minutes).
**User communication:** Inline loading state in Body quadrant.
**Logging:** Level `info`. Include cycle_id and pending duration.

---

### [INT-005] NutriTrack Server Unreachable

**Trigger:** Backend proxy cannot connect to the user's self-hosted NutriTrack Flask server. Causes: server is down, network changed, dynamic IP expired, firewall rules changed.

**Detection:** Backend receives connection refused, timeout, or DNS failure when proxying to the stored NutriTrack base URL. Returns error code 3014 (NutriTrack unreachable) to iOS.

**User Impact:** Fuel quadrant data cannot refresh. Accountability module's meal tracking falls back to manual.

**Immediate Response (< 100ms):**
1. Fuel quadrant shows last cached NutriTrack data with stale indicator.
2. If never connected/no cache: show "NutriTrack unavailable."

**Recovery Strategy:**
1. Retry with exponential backoff: 30s, 60s, 120s. Max 3 retries.
2. After 3 failures: show Fuel quadrant with cached data and stale timestamp pulsing (> 1 hour = critical staleness).
3. Accountability module: Meals card shows "NutriTrack offline" badge. "Log Manually" button appears if not visible already.
4. Push notification after 2 hours of unreachable: "NutriTrack server unreachable. Check that your server is running."
5. Continue retrying on every `fullSync()` call (app foreground, pull-to-refresh).

**Fallback:**
- Fuel quadrant: Cached data or "--" for all macro values.
- Accountability: Manual meal logging via long-press "Mark as Complete."
- Daily score: Nutrition weight redistributes to other available sources.

**Prevention:** NutriTrack health check on every sync. Suggest user sets up a static IP or domain name for their server.

**Monitoring:**
- Telemetry: Track `nutritrack_unreachable_count` counter.
- Track `nutritrack_unreachable_duration_seconds` per user.
- Alert: If NutriTrack is unreachable for > 12 hours, escalate notification to user.

**Retry strategy:** Exponential backoff (30s, 60s, 120s). Then retry on every sync cycle.
**User communication:** Inline stale indicator. Push notification after 2 hours.
**Logging:** Level `warning`. Include NutriTrack base URL (domain only, not full path) and error type.

---

### [INT-006] NutriTrack PIN Expired or Invalid

**Trigger:** Backend proxy call to NutriTrack returns HTTP 401 Unauthorized. The stored PIN is no longer valid (user changed it in NutriTrack settings).

**Detection:** Backend receives 401 from NutriTrack `/api/pin/verify` or any proxied endpoint. Returns error code 3013 to iOS.

**User Impact:** All NutriTrack integration stops. Fuel quadrant and meal accountability revert to disconnected state.

**Immediate Response (< 100ms):**
1. Mark NutriTrack integration as `pin_expired` in backend database.
2. Stop all NutriTrack sync attempts to avoid account lockout on NutriTrack side.

**Recovery Strategy:**
1. Send push notification: "NutriTrack PIN expired. Open Tempo to reconnect."
2. iOS shows Fuel quadrant with "NutriTrack PIN expired. Tap to update." prompt.
3. Tapping navigates to a minimal PIN update form (not full reconnect -- server URL is preserved).
4. On new PIN: backend re-verifies against NutriTrack, encrypts, stores. If valid: trigger immediate sync.
5. If new PIN also fails: show inline error "Invalid PIN. Check NutriTrack settings."

**Fallback:** Same as INT-005. Cached data with stale indicators. Manual meal logging.

**Prevention:** NutriTrack PINs do not expire on their own -- this only happens if the user manually changes the PIN.

**Monitoring:**
- Telemetry: Track `nutritrack_pin_expired_count`.
- Track `nutritrack_reconnect_success_rate`.

**Retry strategy:** No auto-retry (requires user to provide new PIN).
**User communication:** Push notification + inline prompt in Fuel quadrant.
**Logging:** Level `warning`. Do not log the PIN.

---

### [INT-007] NutriTrack Returns Corrupt/Malformed Data

**Trigger:** NutriTrack server returns a 200 response with JSON that does not match the expected schema. Causes: NutriTrack app updated with breaking API changes, database corruption on NutriTrack side.

**Detection:** JSON decoding fails on the backend proxy or returns data that fails validation (e.g., negative calories, null required fields).

**User Impact:** Fuel quadrant cannot display current data. Meal accountability tracking may be inaccurate.

**Immediate Response (< 100ms):**
1. Backend rejects the malformed response.
2. Serve last valid cached data to iOS.
3. Log the full malformed response (scrubbed of sensitive data) for debugging.

**Recovery Strategy:**
1. Retry once (may be a transient issue).
2. If retry also returns corrupt data: serve cache with stale indicator.
3. Do not overwrite valid cached data with corrupt data.
4. Backend applies defensive parsing: extract whatever valid fields are available, mark missing fields as null.
5. If specific fields are corrupt but others are valid: use the valid subset (e.g., calories correct but macros missing).

**Fallback:** Fuel quadrant shows cached data. Individual fields that cannot be parsed show "--".

**Prevention:** Backend validates all NutriTrack response data before caching. Schema validation layer between NutriTrack proxy and iOS response.

**Monitoring:**
- Telemetry: Track `nutritrack_malformed_response_count` with label `field_errors: [list]`.
- Alert: > 3 malformed responses in 1 hour for any user.

**Retry strategy:** Immediate single retry. Then serve cache.
**User communication:** Silent if cache available. Toast if no cache: "NutriTrack data temporarily unavailable."
**Logging:** Level `error`. Include response body snippet and validation errors.

---

### [INT-008] HealthKit Permission Revoked by User

**Trigger:** User goes to Settings > Health > Tempo and disables specific data types or all access. Detected on next HealthKit query attempt.

**Detection:** HealthKit query returns zero results for a previously-working data type, or `HKHealthStore.authorizationStatus(for:)` returns `.sharingDenied` for write types. Note: for read types, Apple returns `.notDetermined` even when denied (privacy design).

**User Impact:** Varies by which types were revoked. Steps/energy revoked: Move quadrant shows "--". Heart rate revoked: no live HR during workouts. Workout write revoked: RepForge workouts not written to Health app.

**Immediate Response (< 100ms):**
1. Update `ConnectionStatus.healthkit` to reflect partial/denied status.
2. Gracefully degrade affected features.

**Recovery Strategy:**
1. If specific read types return no data for 7+ consecutive days (high confidence of revocation):
   a. Show inline banner in affected quadrant: "Steps data unavailable. Tap to enable in Health settings."
   b. Tap opens Health app (`x-apple-health://`).
   c. Banner appears maximum once per day per data type to avoid nagging.
2. If write types are denied:
   a. RepForge workout "Save to Health" toggle shows as disabled with explanation.
   b. NutriTrack nutrition data not written to HealthKit (silent, no user impact).
3. Do NOT re-request authorization programmatically (Apple silently ignores repeated requests).
4. If ALL HealthKit access revoked: Move quadrant shows "Enable Health access for step tracking" with a button to open Health settings.

**Fallback:**
- Steps unavailable: Move quadrant step count shows "--", progress ring based on workout status only.
- Heart rate unavailable: RepForge shows no live HR tile. Whoop HR data (via API) still available for dashboard.
- Sleep unavailable: Whoop sleep data (via API) is primary source -- HealthKit sleep is backup.
- Daily score: Movement component uses workout status only (50 points max instead of 100).

**Prevention:** Clear permission explanation during onboarding. Never request types the app does not actively use.

**Monitoring:**
- Telemetry: Track `healthkit_revocation_detected` counter by data type.
- Track `healthkit_authorization_state` gauge per type.

**Retry strategy:** No retry. Guide user to Settings.
**User communication:** Inline banner (once per day per type). Never a blocking modal.
**Logging:** Level `info`. Include which types appear revoked.

---

### [INT-009] HealthKit Returns No Data (Empty but Authorized)

**Trigger:** HealthKit query returns zero results for a data type where authorization is (presumably) granted. Causes: morning state (no steps yet today), new iPhone with no historical data, Apple Watch not worn.

**Detection:** `HKStatisticsQuery` returns nil `sumQuantity()`, or sample query returns empty array.

**User Impact:** Affected metric shows zero or "--" depending on context.

**Immediate Response (< 100ms):**
1. Distinguish between "no data yet today" (normal) and "never any data" (possible permission issue).
2. Show appropriate zero state.

**Recovery Strategy:**
1. Morning state (before 10 AM, no steps): Show `"0"` for steps and `"0 cal"` for active calories. This is NOT an error. Progress bar empty. Normal operation.
2. All-day zero (after 6 PM, still 0 steps, but user has been active per Whoop): likely permission issue. Show subtle hint: "No step data today. Check Health settings if this seems wrong."
3. No historical data (new device): first-time setup. Show "Step tracking will appear as you move."
4. HealthKit observer queries (`HKObserverQuery`) will automatically deliver new data as it becomes available -- no polling needed.

**Fallback:** Zero values displayed (not error states). Daily score calculation treats zero steps as zero score for steps component (not a weight redistribution -- the user has 0 steps, not missing data).

**Prevention:** HealthKit observer queries ensure real-time data delivery when available.

**Monitoring:**
- Telemetry: Track `healthkit_zero_data_past_6pm_count` (potential permission issue indicator).

**Retry strategy:** No retry needed. Observer queries deliver data automatically.
**User communication:** Zero-state UI (not error UI). Subtle hint after 6 PM if data seems wrong.
**Logging:** Level `debug`. Not an error condition.

---

### [INT-010] Calendar (EventKit) Permission Revoked

**Trigger:** User revokes calendar access in Settings, or `EKEventStore.authorizationStatus(for: .event)` returns `.denied`.

**Detection:** EventKit query fails with authorization error, or `authorizationStatus` check returns `.denied`.

**User Impact:** Mind quadrant cannot show exam dates from calendar. Training module cannot detect football match schedule.

**Immediate Response (< 100ms):**
1. Update calendar authorization state.
2. Remove calendar-derived data from UI (exam countdown, football schedule).

**Recovery Strategy:**
1. Exam dates: Fall back to manually-entered exams in Tempo's local database. Show "Add exams manually" prompt if no local exams exist.
2. Football schedule: Fall back to manually-entered match dates. Training module uses default (non-football-adjusted) workout schedule.
3. If user re-enables calendar access: EventKit's `requestFullAccessToEvents()` detects the change on next app launch.

**Fallback:**
- Mind quadrant: Shows study time and streak only. No exam countdown unless manually entered.
- Training: Default workout schedule without football-awareness.

**Prevention:** Clear explanation during onboarding about why calendar access is needed.

**Monitoring:**
- Telemetry: Track `calendar_permission_revoked_count`.

**Retry strategy:** Check authorization on every app foreground.
**User communication:** Inline prompt in affected features: "Enable calendar access for exam tracking."
**Logging:** Level `info`.

---

### [INT-011] Calendar Returns Overlapping Events

**Trigger:** EventKit returns events with overlapping time ranges (common with recurring events, all-day events, multi-calendar duplicates).

**Detection:** Event processing logic detects `startDate < previousEvent.endDate` when events are sorted chronologically.

**User Impact:** Training schedule may show conflicting time slots. Exam countdown may show duplicate exams.

**Immediate Response (< 100ms):**
1. Apply deduplication logic before displaying or using calendar events.

**Recovery Strategy:**
1. Deduplication rules:
   a. Same title + same start time from different calendars: keep one, prefer primary calendar.
   b. All-day events: do not conflict with timed events.
   c. Recurring events: use the specific occurrence, not the template.
2. For training schedule: if events overlap, choose the event from the calendar marked as "primary" or the most recently modified.
3. For exam detection: match by title keyword (e.g., "exam", "test", "final") and date, dedup by date.

**Fallback:** Show all events and let the user resolve conflicts manually.

**Prevention:** Calendar processing layer applies dedup before any downstream use.

**Monitoring:**
- Telemetry: Track `calendar_overlap_detected_count`.

**Retry strategy:** Not applicable (logic error, not transient).
**User communication:** Silent (dedup is automatic).
**Logging:** Level `debug`. Include overlapping event titles and times.

---

### [INT-012] Apple Sign In Token Validation Fails

**Trigger:** Backend fails to validate the identity token from Sign in with Apple. Causes: Apple's public keys rotated and cached keys are stale, token actually expired, clock skew, nonce mismatch.

**Detection:** Backend JWT verification fails at step 3 (signature) or step 4 (claims validation). Returns error codes 1002-1006.

**User Impact:** User cannot sign in. If this is a new user: blocked from creating account. If returning user: blocked from logging in.

**Immediate Response (< 100ms):**
1. Return specific error code to iOS client.
2. iOS shows appropriate error message on sign-in screen.

**Recovery Strategy:**
1. Error 1005 (signature verification failed):
   a. Invalidate cached Apple JWKS keys in Redis.
   b. Fetch fresh keys from `https://appleid.apple.com/auth/keys`.
   c. Retry verification with fresh keys.
   d. If still fails: "Sign in failed. Please try again." User taps retry, new identity token is generated.
2. Error 1006 (token expired):
   a. Token has >5 minute clock skew or user waited too long.
   b. "Session expired. Please sign in again." iOS generates a new `ASAuthorizationAppleIDRequest`.
3. Error 1003 (nonce mismatch):
   a. Possible replay attack or iOS-side bug.
   b. "Sign in failed. Please try again." Generate new nonce on retry.
4. Error 1004 (authorization code invalid):
   a. Code was already exchanged or expired (5-minute TTL).
   b. "Sign in failed. Please try again."

**Fallback:** User retries sign-in. If persistent failure: "If this continues, make sure your device's date and time are set to Automatic."

**Prevention:**
- Cache Apple JWKS keys for 24 hours but refresh on verification failure.
- NTP-synced server clocks (standard on cloud providers).
- Short time window between token generation and validation (< 5 minutes).

**Monitoring:**
- Telemetry: Track `apple_signin_failure_count` by error code.
- Alert: If sign-in failure rate exceeds 5% over 1 hour.

**Retry strategy:** Automatic JWKS refresh + retry for signature failures. User-initiated retry for all others.
**User communication:** Inline error on sign-in screen with "Try Again" button.
**Logging:** Level `error`. Include error code, token `kid`, token `iss`, `aud`, expiry. Never log the token itself.

---

## 3. Data Errors

### [DAT-001] SwiftData Model Migration Fails

**Trigger:** App update includes a SwiftData schema change. `ModelContainer` initialization throws during migration. Causes: incompatible schema change (renamed property without migration plan), corrupted migration metadata, insufficient disk space.

**Detection:** `ModelContainer(for:)` initializer throws. Caught in the app's initialization sequence.

**User Impact:** Critical -- app cannot display any local data. If unhandled, app crashes on launch.

**Immediate Response (< 100ms):**
1. Catch the migration error in a do/catch around `ModelContainer` initialization.
2. Show a recovery screen (not the main app).

**Recovery Strategy:**
1. Attempt re-migration once by reinitializing `ModelContainer`.
2. If re-migration fails: show recovery screen:
   - Title: "Something went wrong"
   - Body: "Tempo needs to reset local data. Your account and connected services will re-sync automatically."
   - Button 1: "Reset and Continue" (destructive) -- deletes SwiftData store files, recreates fresh `ModelContainer`.
   - Button 2: "Contact Support" -- opens mail composer with diagnostic info pre-filled.
3. After reset: trigger `fullSync()` to repopulate from backend and integrations.
4. Workout data logged locally but not yet synced to backend is lost in this scenario -- this is the worst case.

**Fallback:** Fresh database with re-sync from all sources. Backend has all synced data. Only purely local data (unsynced study sessions, unsynced workout sets) may be lost.

**Prevention:**
- Always use `VersionedSchema` and `SchemaMigrationPlan` for SwiftData changes.
- Test migrations on real production data shapes before shipping.
- Keep one version of migration code that handles N-2 to current (supporting users who skip versions).
- Pre-migration backup: before starting migration, copy the `.store` file to a backup location. On failure, restore the backup.

**Monitoring:**
- Telemetry: Track `swiftdata_migration_failure_count` with schema version labels.
- Alert: Any migration failure is Critical severity.

**Retry strategy:** Single automatic re-attempt. Then user-directed recovery.
**User communication:** Full-screen recovery view.
**Logging:** Level `critical`. Include from-version, to-version, error description, device model, iOS version.

---

### [DAT-002] SwiftData Database Corrupt

**Trigger:** SQLite database backing SwiftData is corrupted. Causes: force-quit during write, disk error, iOS upgrade corruption (rare), low storage during write.

**Detection:** SwiftData query throws with SQLite error codes (SQLITE_CORRUPT, SQLITE_NOTADB, SQLITE_IOERR). Or `ModelContext.fetch()` returns unexpected errors.

**User Impact:** Critical -- some or all local data unreadable.

**Immediate Response (< 100ms):**
1. Catch the SQLite error.
2. Attempt to isolate which table/model is corrupt.

**Recovery Strategy:**
1. Try `PRAGMA integrity_check` on the SQLite database to assess corruption extent.
2. If corruption is limited to a specific table:
   a. Delete that table's data.
   b. Re-sync that data type from backend/integrations.
3. If corruption is widespread:
   a. Show recovery screen (same as DAT-001).
   b. Delete and recreate the database.
   c. Full re-sync.
4. Before deletion, attempt to export any readable data from non-corrupt tables.

**Fallback:** Fresh database with full re-sync. Same data loss risk as DAT-001 for unsynced local data.

**Prevention:**
- SwiftData uses WAL (Write-Ahead Logging) mode by default, which is crash-safe.
- Aggressive SwiftData save points: save after every set completion (workout), every timer session (focus), every non-negotiable toggle.
- Low storage warning (see UXE-006) to prevent writes failing due to disk full.

**Monitoring:**
- Telemetry: Track `swiftdata_corruption_count`.
- Alert: Any corruption event is Critical.

**Retry strategy:** Single integrity check + targeted recovery. Full reset if needed.
**User communication:** Full-screen recovery if severe. Toast if targeted recovery succeeds.
**Logging:** Level `critical`. Include SQLite error code, table name if identifiable, database size.

---

### [DAT-003] SwiftData Concurrent Write Conflict

**Trigger:** Multiple `ModelContext` instances attempt to write to the same record simultaneously. Common scenario: background sync updates a record while the user edits it on the main thread.

**Detection:** SwiftData throws a merge conflict error, or `save()` fails with a conflict exception.

**User Impact:** One of the two writes may be silently dropped if not handled.

**Immediate Response (< 100ms):**
1. Catch the conflict.
2. Apply merge policy based on data type.

**Recovery Strategy:**
1. Merge policy per data type:
   - **User-entered data (workout sets, study sessions, non-negotiable toggles):** User's local change wins. The user actively made a decision.
   - **Integration data (Whoop recovery, NutriTrack meals):** Server/integration data wins. It is the authoritative source.
   - **Metadata (timestamps, sync status):** Most recent timestamp wins.
2. After resolving conflict, save the merged result.
3. If the conflict involves data that the user modified AND the server updated: queue a "last write wins" resolution and log for review.

**Fallback:** If merge resolution fails: keep the existing database state and log the failed write for manual inspection.

**Prevention:**
- Use a single `ModelContext` on `@MainActor` for user-facing writes.
- Background sync writes use a separate `ModelContext` on a background queue.
- SwiftData's built-in merge policies handle most cases when configured correctly.
- For workout logging: the active workout state is owned exclusively by the main thread. Background syncs do not touch in-progress workouts.

**Monitoring:**
- Telemetry: Track `swiftdata_merge_conflict_count` by model type.
- Alert: If conflicts exceed 10 per user per day (indicates architectural issue).

**Retry strategy:** Immediate merge resolution. No retry needed.
**User communication:** Silent. User never sees conflicts.
**Logging:** Level `warning`. Include both conflicting values and resolution outcome.

---

### [DAT-004] Sync Conflict: Server and Local Data Diverge

**Trigger:** Backend has different data than local SwiftData for the same entity. Causes: user used the app on a different device (future), backend processed a webhook while app was offline, manual admin correction.

**Detection:** During `fullSync()`, backend returns data with a different `updated_at` timestamp than local record.

**User Impact:** Data inconsistency -- user may see values "jump" when sync resolves.

**Immediate Response (< 100ms):**
1. Compare `updated_at` timestamps between local and server versions.

**Recovery Strategy:**
1. For each conflicting record, apply the conflict resolution matrix:

   | Data Type | Resolution | Rationale |
   |-----------|------------|-----------|
   | Whoop data | Server wins | Server is source of truth via Whoop API |
   | NutriTrack data | Server wins | Server proxies NutriTrack directly |
   | Workout data (completed) | Most recent `updated_at` wins | User may edit from either device |
   | Study sessions | Local wins if unsynced, server wins if synced | Protect unsynced local work |
   | Non-negotiable status | Most recent `updated_at` wins | User intent matters most |
   | XP / Level | Server wins always | Backend is authoritative for social features |
   | User preferences | Most recent `updated_at` wins | User changed settings intentionally |

2. After resolution: upload the resolved state to the backend.
3. If the resolved value differs from what the user is currently viewing: animate the change (counter-roll for numbers, fade for text) rather than snapping instantly.

**Fallback:** If conflict resolution logic fails: prefer server data (backend is the system of record for synced data).

**Prevention:** Idempotency keys on all mutating requests. `updated_at` timestamps on every record. Conflict-free synced data model design (append-only where possible).

**Monitoring:**
- Telemetry: Track `sync_conflict_count` by data type and resolution outcome.
- Alert: > 50 conflicts per user per sync cycle indicates a systematic issue.

**Retry strategy:** Not applicable (resolution, not retry).
**User communication:** Silent. Data updates animate smoothly.
**Logging:** Level `info`. Include entity type, local value, server value, resolution.

---

### [DAT-005] Offline Queue Grows Too Large (> 1000 Pending Operations)

**Trigger:** User has been offline for an extended period while actively using the app. Queued operations (workout uploads, XP events, snapshot uploads) accumulate.

**Detection:** Offline queue size exceeds 1000 entries. Monitored by `SyncService` after each queue addition.

**User Impact:** App may use excessive memory. On reconnect, sync could take a long time and consume significant bandwidth.

**Immediate Response (< 100ms):**
1. Compact the queue: deduplicate operations (e.g., multiple snapshots for the same day -> keep latest only).
2. Prioritize queue entries.

**Recovery Strategy:**
1. Queue compaction rules:
   a. Daily snapshots: keep only the latest per day.
   b. XP events: coalesce into batch operations.
   c. Workout uploads: keep all (each is unique data).
   d. Configuration updates: keep only the latest.
2. After compaction, if queue still > 500: prioritize by recency (most recent first) and data importance (workouts > study sessions > snapshots > XP events).
3. On reconnect: drain queue in priority order with 100ms delays between operations to avoid overwhelming the backend.
4. If queue > 2000 even after compaction: drop oldest snapshot entries (they can be reconstructed from source data).

**Fallback:** If queue processing takes > 5 minutes: notify user "Syncing X days of data..." with progress indicator. Continue in background.

**Prevention:** Queue compaction runs after every addition. Background sync every 15 minutes reduces accumulation rate.

**Monitoring:**
- Telemetry: Track `offline_queue_size` gauge. Track `offline_queue_drain_duration_seconds` histogram.
- Alert: Queue size > 500 for any user = Info. Queue size > 2000 = Warning.

**Retry strategy:** Process on reconnect with throttled drain.
**User communication:** Silent if < 500. Progress indicator if processing takes > 5 seconds.
**Logging:** Level `warning` at 1000+ entries. Include queue size, oldest entry timestamp, entry type distribution.

---

### [DAT-006] Date/Timezone Calculation Error (DST, Travel)

**Trigger:** User crosses time zones, or DST transition occurs. "Today" changes, causing data to appear on the wrong date. Whoop physiological cycles (which use their own start/end boundaries) may misalign with calendar dates.

**Detection:** `Calendar.current.timeZone` differs from the stored user timezone. Or data is attributed to a date that does not match the expected "today."

**User Impact:** Dashboard may show yesterday's data as today's, or vice versa. Workout scheduled for "today" may shift to "tomorrow" after timezone change.

**Immediate Response (< 100ms):**
1. Detect timezone change by comparing `TimeZone.current` with stored value.
2. Trigger date recalculation for all date-dependent data.

**Recovery Strategy:**
1. Whoop cycle-to-date mapping: Use the cycle `start` time with the 4:00 AM cutoff rule (start before 4 AM = previous day). This is timezone-aware.
2. On timezone change:
   a. Recalculate "today" in the new timezone.
   b. If data was fetched for "old today": re-fetch for "new today."
   c. Update all scheduled timers (focus timer, rest timer) -- they use absolute `Date` objects, so they are immune to timezone changes.
   d. Recalculate non-negotiable deadlines (PS5 time is in local time).
3. DST transition:
   a. Spring forward (lose 1 hour): some data may appear to have been logged in a non-existent hour. Use UTC timestamps internally, display in local time.
   b. Fall back (gain 1 hour): data logged during the repeated hour uses UTC to disambiguate.
4. Store all timestamps as UTC internally. Convert to local time only at the presentation layer.

**Fallback:** If recalculation produces inconsistent results: refresh all data from sources.

**Prevention:** All internal timestamps are UTC. Calendar calculations use `Calendar.current` which respects the device timezone. Whoop API returns UTC timestamps. Backend stores UTC.

**Monitoring:**
- Telemetry: Track `timezone_change_detected_count`.
- Track `dst_transition_data_attribution_error_count`.

**Retry strategy:** Immediate recalculation. No network retry needed.
**User communication:** Silent. User should not notice timezone handling.
**Logging:** Level `info`. Include old timezone, new timezone, affected date range.

---

### [DAT-007] Numeric Overflow (XP, Volume Calculations)

**Trigger:** XP total exceeds `Int64.max` (extremely unlikely but theoretically possible over years of use), or workout volume calculation produces an unexpectedly large number due to a parsing error (e.g., weight entered as 10000 kg).

**Detection:** Swift's integer overflow detection (`&+` vs `+`), or value validation bounds checks.

**User Impact:** Incorrect XP display, or workout volume shows nonsensical numbers.

**Immediate Response (< 100ms):**
1. If overflow detected in arithmetic: clamp to maximum representable value.
2. If input validation detects unreasonable values: reject the input.

**Recovery Strategy:**
1. XP: clamp to `Int64.max` (9.2 quintillion -- effectively unreachable). If displayed XP appears corrupted: re-fetch from backend (source of truth for XP).
2. Workout volume: validate all user inputs. Weight: 0.25 kg to 500 kg. Reps: 1 to 999. Sets: 1 to 99. Reject values outside these ranges with haptic error feedback.
3. If corrupted data is already stored: detect via validation on read. Replace with nil and flag for user correction.

**Fallback:** Replace overflow values with nil and display "--".

**Prevention:**
- Input validation on all numeric fields with documented bounds.
- Use `Double` for volume calculations (safe range far exceeds practical use).
- Backend validates all incoming numeric data against the same bounds.

**Monitoring:**
- Telemetry: Track `numeric_overflow_detected_count` by field.
- Alert: Any overflow event is Warning severity (indicates a bug or abuse).

**Retry strategy:** Not applicable.
**User communication:** Silent clamping or input rejection with haptic error.
**Logging:** Level `error`. Include field name, attempted value, max allowed value.

---

### [DAT-008] Missing Required Field in API Response

**Trigger:** Backend response is valid JSON but missing a field that the iOS client requires for display or computation. Causes: backend schema change not yet reflected in client, field conditionally null in edge cases, partial response from a timeout.

**Detection:** Swift `Codable` decoding with `keyNotFound` error, or optional unwrapping finds nil where non-nil is expected.

**User Impact:** Specific UI element cannot render. If unhandled: crash.

**Immediate Response (< 100ms):**
1. Defensive decoding: all API response fields should be declared as `Optional` in the client model, even those documented as required.
2. If a "required" field is nil: use a sensible default.

**Recovery Strategy:**
1. Defaults per field type:
   - Numeric scores: `nil` (display "--")
   - Strings: `""` (empty)
   - Dates: `nil` (hide date display)
   - Booleans: `false`
   - Arrays: `[]` (empty)
2. Log the missing field for debugging.
3. Serve the response with the default-filled field.
4. On next sync, the field may be populated (backend may have been in a transitional state).

**Fallback:** "--" for any missing display value. Feature degrades but does not crash.

**Prevention:**
- All client-side models use `Optional` for all server-sourced fields.
- `CodingKeys` with `decodeIfPresent` for every field.
- Backend API versioning: breaking changes only in new API versions.
- Client checks `X-Client-Version` against backend minimum supported version.

**Monitoring:**
- Telemetry: Track `api_missing_field_count` by endpoint and field name.
- Alert: If a required field is missing in > 10% of responses for any endpoint.

**Retry strategy:** No retry (the response is valid, just incomplete).
**User communication:** Silent. "--" for missing values.
**Logging:** Level `warning`. Include endpoint, field name, response `meta.request_id`.

---

### [DAT-009] Stale Cache Serves Outdated Data

**Trigger:** Cache TTL has not yet expired, but the underlying data has changed. User sees stale data until cache refreshes.

**Detection:** Staleness thresholds per source: Whoop > 30 min, NutriTrack > 20 min, HealthKit HR > 10 min. Detected by comparing `lastSync` timestamp to current time.

**User Impact:** User sees slightly outdated values. In extreme cases: recovery score is from yesterday, meal count is from hours ago.

**Immediate Response (< 100ms):**
1. Calculate `dataAge` per source.
2. Apply visual staleness indicators.

**Recovery Strategy:**
1. Fresh (< threshold): Normal display, no indicators.
2. Stale (threshold to critical threshold):
   a. Yellow 4pt dot next to quadrant category label.
   b. "Last sync" timestamp turns `tempo.stale` (yellow).
   c. VoiceOver announcement: "Body data is stale. Last synced 45 minutes ago."
3. Critically stale (> critical threshold):
   a. Timestamp pulses (opacity 0.5-1.0, 2s cycle).
   b. Card gets 1pt `tempo.stale` border at 40% opacity.
   c. Per-quadrant footer appears: "Synced {relative_time}" in `tempo.caption2`.
4. User can pull-to-refresh to force immediate sync.

**Fallback:** Stale data is always better than no data. Display it with clear visual indicators.

**Prevention:** Background refresh tasks. Observer queries for HealthKit. Webhook-driven updates for Whoop.

**Monitoring:**
- Telemetry: Track `data_staleness_seconds` histogram by source.
- Track `critical_stale_quadrant_views` counter.
- Alert: If average staleness > 2 hours for any source across users.

**Retry strategy:** Background refresh handles this. Pull-to-refresh for user-initiated.
**User communication:** Visual staleness indicators (yellow dot, yellow timestamp, pulsing).
**Logging:** Level `debug`. Staleness is expected behavior, not an error.

---

### [DAT-010] iCloud Sync Conflict (Future Feature)

**Trigger:** When iCloud sync is implemented: two devices have conflicting versions of the same record. iCloud's automatic conflict resolution may choose the wrong version.

**Detection:** CloudKit notification of record conflict, or `CKError.serverRecordChanged`.

**User Impact:** Data from one device overwrites the other. User may lose recent changes.

**Immediate Response (< 100ms):**
1. Detect the conflict via CloudKit error handling.
2. Preserve both versions temporarily.

**Recovery Strategy:**
1. Custom merge resolution (do not rely on CloudKit's default "last write wins"):
   - Workout data: merge at the set level (keep all sets from both devices).
   - Study sessions: merge at the session level (keep all sessions).
   - Non-negotiable completion: most recent toggle wins (user intent).
   - User preferences: most recent `updated_at` wins.
2. If merge produces inconsistency: flag for user review with a "Sync conflict" prompt showing both versions and asking user to choose.
3. After resolution: push resolved record to CloudKit and all devices.

**Fallback:** Server-side backend data is the ultimate source of truth. If CloudKit conflict is unresolvable: re-sync from backend.

**Prevention:** CRDTs (Conflict-free Replicated Data Types) for append-only data (sets, sessions). Timestamp-based LWW (Last Write Wins) for settings. Merge-friendly data model design.

**Monitoring:**
- Telemetry: Track `icloud_conflict_count` by record type.
- Alert: > 10 conflicts per user per day.

**Retry strategy:** Immediate merge resolution + push.
**User communication:** Silent for automatic merges. Prompt for ambiguous conflicts.
**Logging:** Level `warning`. Include both record versions and resolution outcome.

---

## 4. User Experience Errors

### [UXE-001] App Force-Quit During Active Workout

**Trigger:** User swipes up to kill the app (or iOS terminates it for memory) while in Active Workout View with logged sets.

**Detection:** On next app launch, check for `ActiveWorkoutState` record in SwiftData with `isComplete == false`.

**User Impact:** Risk of losing in-progress workout data if not persisted.

**Immediate Response (next app launch, < 500ms):**
1. `AppDelegate` / `@main App` initialization checks for unfinished workout.
2. If found: present workout recovery prompt before showing the dashboard.

**Recovery Strategy:**
1. Full workout state is persisted to SwiftData after every set completion:
   - Current exercise index
   - All logged sets with weights, reps, timestamps
   - Rest timer state
   - Workout start time
   - Elapsed duration
2. On next launch, present recovery prompt:
   - Title: "Unfinished Workout"
   - Body: "You have an incomplete [Push Day] session with [4 of 6] exercises logged."
   - Button 1: "Resume Workout" (primary) -- opens Active Workout View at the last position.
   - Button 2: "Save as Partial" (secondary) -- saves what was logged as a completed (partial) workout.
   - Button 3: "Discard" (destructive, requires confirmation: "This will delete all logged sets from this session.").
3. If resumed: rest timer resets (the user has been away), but all set data is intact. Show "Workout resumed -- rest timer reset."
4. If saved as partial: workout summary shows with actual exercises completed. XP awarded proportionally.

**Fallback:** If `ActiveWorkoutState` record is corrupt: offer only "Discard" option.

**Prevention:** SwiftData save after every set completion (the checkpoint mechanism). `scenePhase` observer triggers a save when app moves to `.inactive` or `.background`.

**Monitoring:**
- Telemetry: Track `workout_recovery_prompt_shown_count`.
- Track `workout_recovery_outcome` (resume/save_partial/discard).
- Track `workout_data_loss_count` (discard chosen or corrupt state).

**Retry strategy:** Not applicable (recovery on next launch).
**User communication:** Full-screen recovery prompt on launch.
**Logging:** Level `warning`. Include workout type, exercises logged, sets logged, time since last checkpoint.

---

### [UXE-002] App Force-Quit During Focus Timer

**Trigger:** User kills the app or iOS terminates it while the Lockdown module's Focus Timer is running.

**Detection:** On next launch, check for `ActiveTimerState` record in SwiftData with `isRunning == true`.

**User Impact:** Study time accumulated before the quit is at risk. Timer state needs recovery.

**Immediate Response (next app launch, < 500ms):**
1. Check for `ActiveTimerState` record.
2. Calculate elapsed time between last checkpoint and current time.

**Recovery Strategy:**
1. Timer state persisted to SwiftData:
   - Session start time
   - Accumulated seconds before pause
   - Subject name
   - Pomodoro session number
   - Last checkpoint timestamp (updated every 60 seconds)
2. On recovery:
   a. Calculate `elapsedSinceCheckpoint = now - lastCheckpointTime`.
   b. If `elapsedSinceCheckpoint < 30 minutes`: assume the timer was running. Credit the time. Show: "Focus session recovered. [Subject]: [accumulated + elapsed] logged."
   c. If `elapsedSinceCheckpoint >= 30 minutes`: the user likely intended to stop. Credit time up to the checkpoint only. Show: "Timer interrupted. [accumulated] minutes credited for [Subject]."
   d. Do NOT resume the timer automatically (user context has changed).
3. Credited time counts toward the study non-negotiable.

**Fallback:** If timer state is corrupt: credit nothing, show "Timer session could not be recovered. Start a new session."

**Prevention:** Timer checkpoints every 60 seconds to SwiftData. `scenePhase` observer saves on background. Local notification scheduled at session end time as a backup timer signal.

**Monitoring:**
- Telemetry: Track `timer_recovery_count` by outcome (full_credit/partial_credit/no_credit).
- Track `timer_recovery_elapsed_minutes` histogram.

**Retry strategy:** Not applicable (recovery on next launch).
**User communication:** Toast with recovery summary.
**Logging:** Level `info`. Include subject, accumulated time, elapsed since checkpoint.

---

### [UXE-003] App Crash During Onboarding

**Trigger:** App crashes during the multi-step onboarding flow (Sign in with Apple -> HealthKit -> Whoop -> NutriTrack -> preferences).

**Detection:** On next launch, check `UserDefaults` flag `onboarding_step_completed` which tracks the last successfully completed step.

**User Impact:** User may need to re-enter information. Partial onboarding state may leave integrations half-connected.

**Immediate Response (next launch, < 500ms):**
1. Read `onboarding_step_completed` from UserDefaults.
2. Resume onboarding from the failed step.

**Recovery Strategy:**
1. Onboarding steps are checkpoint-idempotent:
   - Step 1 (Sign in with Apple): If auth tokens exist in Keychain, skip. User is signed in.
   - Step 2 (HealthKit): If HealthKit authorization status is `.sharingAuthorized` for any write type, skip. Already authorized.
   - Step 3 (Whoop): If backend reports Whoop connected for this user, skip. If partially connected (OAuth started but not finished): start fresh.
   - Step 4 (NutriTrack): If backend reports NutriTrack connected, skip. Otherwise: show connection form.
   - Step 5 (Preferences): If preferences exist in backend, skip. Otherwise: show preference form.
2. Resume from the first incomplete step.
3. User does NOT need to repeat completed steps.

**Fallback:** If onboarding state is ambiguous: show a "Welcome back! Let's finish setting up." screen that re-checks all integration statuses and skips what is already done.

**Prevention:** Each step writes its completion flag immediately upon success, before advancing to the next step.

**Monitoring:**
- Telemetry: Track `onboarding_crash_recovery_count` by step.
- Track `onboarding_completion_rate` (started vs. fully completed).

**Retry strategy:** Automatic resume from checkpoint.
**User communication:** Seamless resume. Brief "Welcome back!" if resuming from step > 1.
**Logging:** Level `warning`. Include crash step, completed steps, device model.

---

### [UXE-004] Phone Call Interrupts Workout

**Trigger:** User receives a phone call during Active Workout View. iOS interrupts the app (foreground call overlay or full-screen call).

**Detection:** `scenePhase` changes to `.inactive` (call overlay) or `.background` (full-screen call). Audio session interrupted notification. `AVAudioSession.interruptionNotification` fires.

**User Impact:** Rest timer may be running. Workout is paused visually but time continues to elapse.

**Immediate Response (< 100ms on scene phase change):**
1. Persist current workout state to SwiftData (crash-safe checkpoint).
2. Pause rest timer display (but note the pause timestamp).
3. Do NOT dismiss or discard any workout state.

**Recovery Strategy:**
1. When app returns to foreground after call:
   a. Calculate call duration: `callDuration = Date() - pauseTimestamp`.
   b. If rest timer was running and `callDuration < 10 minutes`:
      - Extend rest timer by call duration. Show: "Rest timer extended by [duration] for phone call."
   c. If `callDuration >= 10 minutes`:
      - Reset rest timer. Show: "Long break -- rest timer reset. Ready when you are."
   d. All logged set data remains intact.
2. Workout duration counter either:
   a. Includes call time (for total wall-clock duration) -- default.
   b. Excludes call time (for "active" duration) -- tracked separately in workout summary.

**Fallback:** If app was killed during the call: standard UXE-001 recovery flow.

**Prevention:** `scenePhase` observer triggers checkpoint save. Workout state machine is interrupt-safe.

**Monitoring:**
- Telemetry: Track `workout_call_interruption_count`.
- Track `workout_call_duration_seconds` histogram.

**Retry strategy:** Not applicable (resume, not retry).
**User communication:** Toast showing rest timer adjustment.
**Logging:** Level `info`. Include call duration and timer adjustment.

---

### [UXE-005] Low Battery During Workout

**Trigger:** Device battery drops below 10% during active workout. iOS may throttle CPU and disable background activity.

**Detection:** `UIDevice.current.batteryLevel < 0.10` and `UIDevice.current.batteryState != .charging`. Monitor via `batteryLevelDidChangeNotification`.

**User Impact:** Risk of device shutting down mid-workout. All unsaved data would be lost.

**Immediate Response (< 100ms):**
1. Trigger immediate SwiftData checkpoint save.
2. Show non-intrusive banner: "Low battery. Your workout is being saved automatically."
3. Increase save frequency to after every action (not just every set completion).

**Recovery Strategy:**
1. If battery drops below 5%:
   a. Show more urgent banner: "Battery critical. Workout saved. Consider plugging in."
   b. Disable non-essential features: animations reduced, haptics disabled, plate calculator closed.
   c. Save workout state to UserDefaults as a secondary backup (in addition to SwiftData).
2. If device shuts down: standard UXE-001 recovery flow on next launch with full data from checkpoint.
3. Apple Watch companion (if running): Watch can continue tracking workout independently and sync when phone recovers.

**Fallback:** All workout data saved via aggressive checkpointing. Recovery on next launch.

**Prevention:** Checkpoint after every set (standard behavior). Battery monitoring during workouts.

**Monitoring:**
- Telemetry: Track `low_battery_during_workout_count`.
- Track `workout_battery_shutdown_data_loss_count` (should be zero).

**Retry strategy:** Not applicable.
**User communication:** Banner at 10%. Urgent banner at 5%.
**Logging:** Level `info` at 10%. Level `warning` at 5%.

---

### [UXE-006] Low Storage on Device

**Trigger:** Device has less than 100 MB free storage. SwiftData writes may fail, background sync may fail.

**Detection:** `FileManager.default.attributesOfFileSystem` for device storage. Check on app launch and periodically.

**User Impact:** New data cannot be saved. Workouts may not persist. Cache cannot grow.

**Immediate Response (< 100ms):**
1. Detect low storage.
2. Prioritize what to preserve and what to trim.

**Recovery Strategy:**
1. First tier -- trim (automatic, no user impact):
   a. Clear URLSession cache (`URLCache.shared.removeAllCachedResponses()`).
   b. Clear image cache (exercise demo images, avatar cache).
   c. Delete SwiftData records older than 180 days for non-essential data (workout details, daily snapshots).
   d. Compact SQLite database (`VACUUM`).
2. Second tier -- inform user:
   a. If still < 50 MB after trimming: show banner "Storage is low. Some features may not work properly."
   b. Suggest: "Free up space by deleting unused apps or media."
3. Third tier -- degrade features:
   a. Disable background sync (prevents writes that might fail).
   b. Workout logging continues (critical path) but with minimal metadata.
   c. Exercise demo videos do not download.
4. Essential data preservation order (never delete):
   a. Active workout state
   b. Current day's study sessions
   c. Non-negotiable completion status
   d. User auth tokens

**Fallback:** If SwiftData write fails due to disk full: queue the operation in memory and retry when storage is freed.

**Prevention:** Proactive cache management. Default data retention policy (90 days for NutriTrack, 365 days for workouts). Background cleanup job on app launch.

**Monitoring:**
- Telemetry: Track `low_storage_event_count`.
- Track `storage_freed_mb` by cleanup tier.

**Retry strategy:** Automatic cleanup + retry writes.
**User communication:** Banner if cleanup is insufficient.
**Logging:** Level `warning`. Include available storage, storage consumed by Tempo, cleanup actions taken.

---

### [UXE-007] User Deletes and Reinstalls App

**Trigger:** User deletes Tempo from their device and reinstalls from the App Store.

**Detection:** On first launch post-reinstall: Keychain items may or may not persist (iOS preserves Keychain across reinstall). SwiftData database is deleted. UserDefaults are deleted.

**User Impact:** All local data is lost (SwiftData). Keychain tokens may allow automatic sign-in.

**Immediate Response (first launch):**
1. Check Keychain for existing auth tokens.
2. If tokens exist and are valid: attempt silent sign-in.
3. If no tokens: show full onboarding.

**Recovery Strategy:**
1. If Keychain tokens are valid:
   a. Silent sign-in to backend.
   b. Skip to integration re-check (step 2 of onboarding recovery, like UXE-003).
   c. Trigger `fullSync()` to repopulate local database from backend.
   d. Backend has: all Whoop data, NutriTrack connection, user preferences, XP/level, workout history (that was previously synced).
   e. Local-only data that was never synced (study sessions, non-negotiable completions) is lost.
   f. Show: "Welcome back! Restoring your data..." with progress indicator.
2. If Keychain tokens are expired or absent:
   a. Show Sign in with Apple. Since the same Apple ID generates the same `sub`, the user will be matched to their existing account.
   b. Same recovery as above after sign-in.
3. HealthKit data: still on device (HealthKit data persists across app deletion). Re-request authorization and all historical data is accessible.

**Fallback:** All synced data recoverable from backend. Local-only data (unsynced study sessions) is lost. This is acceptable.

**Prevention:** Sync study sessions and non-negotiable completions to backend (they currently sync via daily snapshots). Ensure no data exists only locally for more than 24 hours.

**Monitoring:**
- Telemetry: Track `app_reinstall_detected_count`.
- Track `reinstall_data_recovery_success_rate`.

**Retry strategy:** Automatic data restoration from backend.
**User communication:** "Welcome back! Restoring your data..." progress screen.
**Logging:** Level `info`. Include data recovered and data lost (by type).

---

### [UXE-008] User Switches iPhones (Device Migration)

**Trigger:** User sets up a new iPhone. Data migration depends on transfer method: iCloud backup, direct transfer, or clean setup.

**Detection:** `X-Device-Id` header changes (new UUID generated on fresh install, or preserved via Keychain transfer).

**User Impact:** App data may or may not transfer depending on method.

**Immediate Response (first launch on new device):**
1. Check if this is a new device (different `X-Device-Id` from last known).
2. Check data state: SwiftData populated (transfer) or empty (clean setup).

**Recovery Strategy:**
1. **iCloud backup restore / Direct transfer**: SwiftData, Keychain, and UserDefaults all transfer. App launches normally. Backend detects new device ID on first authenticated request and registers it.
2. **Clean setup with Sign in with Apple**: Same flow as UXE-007. Full data recovery from backend.
3. Multi-device handling:
   a. Backend allows multiple active devices per user.
   b. Refresh token is device-bound (`device_id` in JWT). New device gets new tokens.
   c. Old device's tokens remain valid until they expire naturally (or user logs out from all devices).
4. Push notification token update: register new APNs token on the new device. Old device token is automatically invalidated by Apple.

**Fallback:** Backend data recovery ensures all synced data is available on the new device.

**Prevention:** All critical data syncs to backend. Device migration is a supported, tested flow.

**Monitoring:**
- Telemetry: Track `device_migration_detected_count`.
- Track `device_migration_method` (transfer/clean).

**Retry strategy:** Automatic.
**User communication:** "Setting up on your new device..." if clean setup detected.
**Logging:** Level `info`. Include old device ID, new device ID, transfer method.

---

### [UXE-009] Notification Permission Denied

**Trigger:** User denies notification permission during onboarding, or revokes it later in Settings.

**Detection:** `UNUserNotificationCenter.current().getNotificationSettings()` returns `.denied`.

**User Impact:** No drill-sergeant notifications. No "Recovery is ready" morning alert. No meal reminders. No overdue nudges. The accountability system loses its teeth.

**Immediate Response (< 100ms):**
1. Update notification state in app.
2. Disable notification-dependent features gracefully.

**Recovery Strategy:**
1. During onboarding: if denied, show a brief explanation of what they will miss: "Without notifications, Tempo can't remind you to eat, train, or study. You can enable them later in Settings." Continue onboarding (do not block).
2. In-app nudge (maximum once per week):
   a. Show a subtle inline card on the dashboard: "Enable notifications for accountability reminders."
   b. Tap opens system Settings.
   c. Dismiss hides for 7 days.
3. Features that degrade:
   - Morning recovery notification: user must open app manually.
   - Meal reminders: not sent. Accountability module still functions but relies on user opening app.
   - Overdue escalation: escalation messages stored in-app (notification center within the app) instead of push.
   - PS5 time countdown: only visible when app is open.
4. In-app notification center: all would-be push notifications are stored locally and displayed as a badge on the dashboard. User can review missed alerts.

**Fallback:** App is fully functional without push notifications. Accountability is self-directed rather than push-directed.

**Prevention:** Clear, compelling notification permission prompt. Request at the right moment (after user has configured non-negotiables, when the value proposition is clear).

**Monitoring:**
- Telemetry: Track `notification_permission_denied_count`.
- Track `notification_permission_denied_at_step` (onboarding vs. later revocation).
- Track `engagement_rate_with_vs_without_notifications` (measure impact).

**Retry strategy:** Weekly in-app nudge. No programmatic re-request (iOS prevents it).
**User communication:** Inline card (once per week). In-app notification center as fallback.
**Logging:** Level `info`. Include when permission was denied (onboarding or post-onboarding).

---

### [UXE-010] HealthKit Permission Partially Denied

**Trigger:** User grants some HealthKit data types but denies others during the authorization sheet. Common: grants steps but denies heart rate.

**Detection:** Read permissions cannot be detected directly (Apple privacy design). Write permissions checked via `authorizationStatus(for:)` returning `.sharingDenied`. Read denials inferred from zero-result queries over extended periods.

**User Impact:** Specific features degrade while others work normally.

**Immediate Response (< 100ms):**
1. Accept whatever permissions were granted.
2. Note which write types are denied.
3. Begin monitoring read types for data availability.

**Recovery Strategy:**
1. Feature degradation map:

   | Denied Type | Affected Feature | Degradation |
   |-------------|-----------------|-------------|
   | Steps (read) | Move quadrant step count | Shows "--". Progress based on workout only. |
   | Active Energy (read) | Move quadrant calories | Shows "--". |
   | Heart Rate (read) | Live HR during workout | HR tile hidden in Active Workout. |
   | Resting HR (read) | Body quadrant (HealthKit fallback) | Whoop RHR used instead. No degradation if Whoop connected. |
   | Sleep (read) | Body quadrant (HealthKit fallback) | Whoop sleep used instead. No degradation if Whoop connected. |
   | Workout (write) | RepForge -> Health sync | Workouts not written to Health. Inline note: "Enable Health access to sync workouts." |
   | Nutrition (write) | NutriTrack -> Health sync | Nutrition not written to Health. Silent (low impact). |

2. For each denied type: check if an alternative source provides the same data (Whoop covers most biometrics).
3. After 7 days of zero data for a read type: show a one-time inline hint (see INT-008).
4. Do NOT repeatedly prompt the user about denied permissions.

**Fallback:** Whoop + NutriTrack cover most data. HealthKit denial primarily affects step counting and workout write-back.

**Prevention:** Clear explanation during onboarding of what each permission enables.

**Monitoring:**
- Telemetry: Track `healthkit_partial_authorization_types_denied` (set of type identifiers).
- Track `healthkit_feature_degradation_active` gauge by feature.

**Retry strategy:** No retry. Guide to Settings if user asks.
**User communication:** Silent initially. Inline hints after 7 days of missing data. Maximum once per day per type.
**Logging:** Level `info`. Include granted and denied type lists.

---

## 5. Backend Errors

### [SRV-001] Database Connection Pool Exhausted

**Trigger:** All 32 database connections (4 per event loop x 8 cores) are in use. New queries wait and then timeout after 10 seconds (`connectionPoolTimeout: .seconds(10)`).

**Detection:** Connection pool metrics show `db_pool_active == db_pool_max`. Queries throw `ConnectionPoolTimeout` error.

**User Impact:** API requests fail with 500 Internal Server Error. All backend-dependent features unavailable.

**Immediate Response (< 100ms):**
1. Return 503 Service Unavailable (not 500) to signal transient failure.
2. Include `Retry-After: 5` header.
3. Log connection pool state.

**Recovery Strategy:**
1. Immediate: identify and kill long-running queries (`pg_stat_activity` WHERE `state = 'active'` AND `duration > '30 seconds'`).
2. Check for connection leaks: queries that acquired a connection but never released it (common bug in async code with early returns).
3. If sustained: increase `maxConnectionsPerEventLoop` temporarily.
4. If caused by traffic spike: the rate limiter should already be throttling. Verify rate limits are properly configured.
5. If caused by a slow query: identify via `pg_stat_statements`, add appropriate indices.

**Fallback:** iOS receives 503 and serves cached data (see NET-004).

**Prevention:**
- Query timeout: 5 seconds per query (PostgreSQL `statement_timeout`).
- Connection pool monitoring with alerting at 80% utilization.
- All database operations use `defer` to ensure connection release.
- Load testing validates pool size is adequate for expected traffic.

**Monitoring:**
- Telemetry: `db_pool_active` gauge, `db_pool_max` gauge.
- `db_query_duration_ms` histogram.
- Alert: Pool utilization > 80% for 5 minutes = Warning.

**Retry strategy:** iOS retries with `Retry-After` header.
**User communication:** iOS serves cached data (silent or toast depending on context).
**Logging:** Level `critical`. Include pool state, longest running query, connection count by state.

---

### [SRV-002] Redis Cache Unavailable

**Trigger:** Redis instance is down, unreachable, or out of memory. Affects: rate limiting, session management, cache, idempotency keys, Whoop OAuth state tokens.

**Detection:** Redis operations throw connection errors. Health check endpoint reports Redis as unhealthy.

**User Impact:** Varies by which Redis function is affected:
- Rate limiting disabled: all requests pass through (acceptable short-term).
- Cache unavailable: requests hit PostgreSQL directly (slower, but functional).
- OAuth state tokens lost: in-progress Whoop connections fail.
- Idempotency keys lost: duplicate webhook processing possible.

**Immediate Response (< 100ms):**
1. Log Redis connection failure.
2. Switch to bypass mode for non-critical Redis operations.

**Recovery Strategy:**
1. Rate limiting: bypass (fail-open). Log that rate limiting is disabled.
2. Cache: fall through to PostgreSQL for all queries. Performance degrades but correctness maintained.
3. OAuth state: any in-progress OAuth flows will fail. Users must restart. No data loss.
4. Idempotency: accept potential duplicate webhook processing. Upsert logic in PostgreSQL prevents duplicate data.
5. Session data: JWTs are self-contained and do not require Redis for validation (blocked token list unavailable, but this is a temporary acceptable risk).
6. Redis reconnection: automatic with exponential backoff (1s, 2s, 4s, 8s, max 30s).
7. On recovery: flush all caches (they may be stale). Rebuild rate limit counters from zero.

**Fallback:** Backend operates without Redis at reduced performance. No data loss.

**Prevention:** Redis persistence enabled (`appendonly yes`). Redis `maxmemory-policy allkeys-lru` evicts stale keys rather than refusing writes. Monitor memory usage.

**Monitoring:**
- Telemetry: `redis_operation_duration_ms` histogram, `redis_memory_bytes` gauge.
- Alert: Redis unreachable for > 30 seconds = Critical.

**Retry strategy:** Automatic reconnection with exponential backoff.
**User communication:** Silent (backend degradation is invisible to user).
**Logging:** Level `critical`. Include Redis connection error, retry count.

---

### [SRV-003] Claude API Timeout or Error

**Trigger:** Claude API call for weekly insights or pattern detection fails. Causes: timeout (> 10 seconds), rate limit, malformed response, API outage.

**Detection:** HTTP response from Anthropic API: timeout, 429, 500, or response that fails parsing.

**User Impact:** AI-generated insights are unavailable. Weekly report may be delayed.

**Immediate Response (< 100ms):**
1. Log the failure with trace ID.
2. Switch to rule-based fallback insights.

**Recovery Strategy:**
1. On timeout: retry once with a shorter `max_tokens` (reduce from 2000 to 1000).
2. On 429 (rate limited): respect `Retry-After`. Queue for later.
3. On 500 (Claude outage): retry once after 30 seconds. If still failing: use fallback.
4. Fallback insight generation:
   a. Local pattern engine identifies trends from the last 7 days of data.
   b. Rule-based templates generate prose insights:
      - "Your recovery averaged X% this week, [up/down] from last week."
      - "You hit your study target X of 7 days."
      - "Protein intake was consistently [above/below] target."
   c. Each fallback insight gets a `[offline insight]` badge (`tempo.caption2`, `tempo.text.tertiary`, italic).
5. When Claude becomes available again: generate the real insight and replace the fallback (if the weekly window has not passed).

**Fallback:** Rule-based insights from local data. Functional but less nuanced.

**Prevention:**
- Budget monitoring: monthly Claude spend capped at `CLAUDE_MONTHLY_BUDGET_CENTS` (default $50).
- Budget alert at 80% and 95%.
- Insight generation is batched (Sunday 7:50 PM UTC) to spread load.
- Response timeout: 30 seconds (Claude can be slow on complex prompts).

**Monitoring:**
- Telemetry: `claude_api_duration_ms` histogram, `claude_api_cost_cents` counter.
- Track `claude_fallback_insight_count`.
- Alert: Claude budget > 80% = Warning. > 95% = Critical.

**Retry strategy:** Single retry with reduced params. Then fallback.
**User communication:** Fallback insights with `[offline insight]` badge. User rarely notices the difference.
**Logging:** Level `warning`. Include error type, prompt length, retry outcome.

---

### [SRV-004] APNs Delivery Failure

**Trigger:** Push notification fails to deliver via Apple Push Notification service. Causes: invalid device token, APNs outage, payload too large, token expired.

**Detection:** APNs returns error response: `BadDeviceToken`, `Unregistered`, `PayloadTooLarge`, `TooManyRequests`, `InternalServerError`.

**User Impact:** User does not receive the intended notification (recovery alert, meal reminder, overdue nudge).

**Immediate Response (< 100ms):**
1. Parse APNs error response.
2. Handle per error type.

**Recovery Strategy:**
1. `BadDeviceToken` / `Unregistered`:
   a. Remove the invalid token from the database.
   b. The device will re-register on next app launch.
   c. Do not retry with the same token.
2. `PayloadTooLarge`:
   a. Truncate the notification body to fit within 4KB limit.
   b. Retry with truncated payload.
3. `TooManyRequests`:
   a. Respect `Retry-After`.
   b. Queue notification for later delivery.
4. `InternalServerError` (APNs outage):
   a. Retry 3 times with exponential backoff (10s, 30s, 90s).
   b. If all retries fail: store notification in the user's in-app notification queue (delivered on next app open).
5. Critical notifications (accountability overdue, streak about to break): retry more aggressively (5 attempts) and also send a silent push (may have different delivery path).

**Fallback:** In-app notification queue. User sees notifications when they next open the app. Badge count on app icon reflects undelivered notifications.

**Prevention:** Re-register device tokens on every app launch. Validate payload size before sending. Monitor APNs delivery success rate.

**Monitoring:**
- Telemetry: `push_notifications_sent` counter by type and status.
- Track `push_delivery_failure_rate`.
- Alert: Delivery failure rate > 10% = Warning.

**Retry strategy:** Varies by error type (see above). Max 3-5 retries.
**User communication:** Silent (user does not know a push failed). In-app fallback.
**Logging:** Level `warning` for transient failures. Level `error` for persistent failures.

---

### [SRV-005] Webhook Processing Fails

**Trigger:** Background job processing a Whoop webhook event fails. Causes: database error, Whoop API error during data fetch, job timeout.

**Detection:** `WhoopWebhookJob.error()` handler fires. Job status marked as `failed` in Redis.

**User Impact:** Data update from webhook is delayed until the job is retried or the polling/reconciliation catches up.

**Immediate Response (< 100ms):**
1. Mark webhook as `failed` in Redis.
2. Queue for automatic retry.

**Recovery Strategy:**
1. Job queue automatically retries failed jobs (3 retries with exponential backoff per the job catalog: default backoff).
2. If all 3 retries fail: job is dead-lettered. The event data is not lost -- it exists in Whoop's API.
3. Reconciliation cron (3:00 AM UTC daily) will fill any data gaps by fetching the last 3 days from Whoop API.
4. Next foreground sync also fetches current data regardless of webhook status.

**Fallback:** Triple-layer redundancy: webhooks + polling + daily reconciliation ensures eventual consistency.

**Prevention:** Job timeouts configured per job type (30s for incremental sync). Dead letter queue monitored.

**Monitoring:**
- Telemetry: `sync_jobs_total` counter by type and status.
- Track `webhook_job_failure_count` by event type.
- Alert: > 10 failed webhook jobs in 1 hour = Warning.

**Retry strategy:** Automatic via job queue (3 retries, exponential backoff).
**User communication:** Silent.
**Logging:** Level `error`. Include trace_id, event type, error description, retry count.

---

### [SRV-006] Materialized View Refresh Fails

**Trigger:** PostgreSQL materialized view refresh (leaderboards) fails. Causes: query timeout, disk space, concurrent refresh, source data inconsistency.

**Detection:** `REFRESH MATERIALIZED VIEW CONCURRENTLY` throws an error. Background job reports failure.

**User Impact:** Leaderboard data is stale (shows last successful refresh).

**Immediate Response (< 100ms):**
1. Log the failure.
2. Serve stale materialized view data (still valid, just not latest).

**Recovery Strategy:**
1. Retry the refresh after 5 minutes.
2. If the failure is due to timeout: extend the query timeout for the refresh operation (allow up to 60 seconds).
3. If the failure is due to disk space: alert operations team.
4. If `CONCURRENTLY` fails (requires unique index): attempt non-concurrent refresh during low-traffic period (3-4 AM UTC).
5. Leaderboard cache TTL (Redis: 300s) means stale data is served for at most 5 minutes after cache expires, then the next request hits the stale MV (which is still better than nothing).

**Fallback:** Stale leaderboard data. Users may see slightly outdated rankings. XP counts are always current (from the `xp_events` table directly).

**Prevention:** Schedule refreshes during off-peak hours. Monitor refresh duration to catch slow queries before they become timeouts.

**Monitoring:**
- Telemetry: Track `materialized_view_refresh_duration_ms` histogram.
- Track `materialized_view_refresh_failure_count`.
- Alert: Refresh failure = Warning. Refresh duration > 30 seconds = Info.

**Retry strategy:** Fixed delay (5 minutes) then retry.
**User communication:** Silent. Stale leaderboard is invisible to users.
**Logging:** Level `error`. Include view name, duration before failure, error description.

---

### [SRV-007] Background Job Fails (Generic)

**Trigger:** Any background job (accountability check, achievement check, stale token cleanup, GDPR export, report generation) fails during execution.

**Detection:** Job error handler fires. Job status tracked in respective database table or log.

**User Impact:** Varies by job type:
- Accountability check: overdue notifications delayed by up to 15 minutes.
- Achievement check: achievement unlock delayed.
- GDPR export: user's export is not generated.
- Report generation: weekly report delayed.

**Immediate Response (< 100ms):**
1. Log the error with job type, payload, and error description.
2. Queue for retry per the job catalog's retry policy.

**Recovery Strategy:**
1. Per-job retry policies (from the job catalog):
   - Accountability check: 0 retries (runs again in 15 minutes anyway).
   - Achievement check: 1 retry.
   - GDPR export: 1 retry. On failure: mark export as `failed`, notify user "Export failed. Please try again."
   - Report generation: 1 retry. On failure: generate rule-based report.
   - Stale token cleanup: 0 retries (runs again tomorrow).
   - Account hard-delete: 0 retries (runs again tomorrow, within the 30-day window).
2. Dead-letter queue for persistent failures: reviewed by operations.

**Fallback:** Each job has a natural retry cycle (cron runs again). Critical jobs (GDPR export, report) have explicit user-facing failure handling.

**Prevention:** Job-level timeouts prevent runaway processes. Circuit breaker on downstream dependencies.

**Monitoring:**
- Telemetry: `background_jobs_queued` gauge by type. `sync_jobs_total` counter by status.
- Alert: Per the job catalog, based on job criticality.

**Retry strategy:** Per job catalog (0-3 retries, varies by job).
**User communication:** Silent for internal jobs. User-facing notification for GDPR export failure.
**Logging:** Level varies: `warning` for retryable, `error` for dead-lettered.

---

### [SRV-008] Disk Space Full on Server

**Trigger:** Server disk reaches capacity. Causes: log accumulation, database WAL growth, uncollected temp files, large GDPR exports.

**Detection:** Health check reports disk usage. Alert threshold: < 20% free = Warning.

**User Impact:** Write operations fail. New data cannot be stored. API may return 500 errors.

**Immediate Response (< 100ms):**
1. Return 503 to new requests with `Retry-After: 60`.
2. Alert operations team immediately.

**Recovery Strategy:**
1. Automated cleanup (run when disk < 15%):
   a. Rotate and compress logs (keep last 7 days).
   b. Delete completed GDPR exports older than 48 hours.
   c. Clean temporary upload files.
   d. Vacuum PostgreSQL to reclaim dead tuple space.
2. Manual intervention (if automated cleanup insufficient):
   a. Increase disk size (AWS EBS resize).
   b. Archive old data to cold storage (S3).
   c. Review and optimize data retention policies.
3. After space freed: server resumes normal operation automatically.

**Fallback:** iOS clients serve cached data during the outage (see NET-004 pattern).

**Prevention:**
- Log rotation policy: 7-day retention, compressed.
- GDPR exports: 48-hour TTL then auto-delete.
- Database partition strategy: partition by month, drop partitions older than retention period.
- Disk space monitoring with proactive alerting at 20%.
- Automated cleanup cron at 85% utilization.

**Monitoring:**
- Telemetry: Disk usage percentage gauge.
- Alert: < 20% free = Warning. < 10% free = Critical.

**Retry strategy:** iOS retries after server recovery. Server auto-recovers after cleanup.
**User communication:** iOS serves cache. Short outage may be invisible.
**Logging:** Level `critical`. Include disk usage, largest directories, available space.

---

### [SRV-009] Memory Leak in Long-Running Process

**Trigger:** Vapor server process memory grows unbounded over time due to a leak in request handling, background jobs, or retained closures.

**Detection:** `process_memory_bytes` gauge shows consistent upward trend. Health check `memory_mb` exceeds threshold.

**User Impact:** Gradual performance degradation, then OOM kill by the OS. Server restarts, causing temporary outage.

**Immediate Response (on OOM kill):**
1. Container orchestrator (Railway/Fly.io) automatically restarts the process.
2. Health check validates the new process is ready.
3. Requests resume.

**Recovery Strategy:**
1. Process restart resolves immediate issue (memory freed).
2. Investigation:
   a. Analyze memory growth pattern: linear (leak) vs. sawtooth (normal with GC).
   b. Enable Swift runtime heap profiling in staging.
   c. Common Swift causes: retained `Task` references, closures capturing `self` strongly, actors with unbounded queues.
3. If identified: deploy fix. If not: implement periodic process restart (every 24 hours during low-traffic period) as a stopgap.

**Fallback:** Multiple replicas (minimum 2) ensure availability during restart. Load balancer routes traffic to healthy instance.

**Prevention:**
- Use `jemalloc` (already configured in Dockerfile) for better memory allocation behavior.
- Memory limit per container: configure in deployment (e.g., 512 MB for Fly.io machine).
- Regular load testing to detect leaks before production.
- Weak references in closures and delegate patterns.

**Monitoring:**
- Telemetry: `process_memory_bytes` gauge.
- Alert: Memory > 80% of container limit = Warning. OOM restart = Critical.

**Retry strategy:** Automatic process restart by orchestrator.
**User communication:** Brief (< 10 second) unavailability during restart. iOS retries transparently.
**Logging:** Level `critical` on OOM kill. Include peak memory, uptime, last restart.

---

### [SRV-010] Deployment Goes Wrong (Rollback Procedure)

**Trigger:** New deployment introduces a bug: crashes, data corruption, performance regression, or breaking API change.

**Detection:**
- Error rate > 5% 5xx for 5 minutes (automated alert).
- Latency p99 > 2000ms for 5 minutes.
- Any migration failure.
- Manual observation of incorrect behavior.

**User Impact:** Varies from degraded performance to complete outage.

**Immediate Response (< 2 minutes):**
1. If automated: monitoring alert fires. On-call engineer notified.
2. Assess: is this a rollback-worthy event? Criteria:
   - Error rate > 10% = always rollback.
   - Data corruption detected = always rollback.
   - Performance regression > 3x p99 = rollback.

**Recovery Strategy:**
1. **Rollback process:**
   a. Revert to previous Docker image tag: `fly deploy --image registry/tempo-api:previous-tag` or Railway rollback to previous deployment.
   b. If database migration was run: execute the down migration. Pre-migration snapshot available for restore if needed.
   c. Verify health check passes on rolled-back version.
   d. Monitor error rate returns to baseline.
2. **If migration cannot be rolled back** (destructive migration):
   a. Restore from pre-migration database snapshot (taken automatically before each migration, 7-day retention).
   b. Re-deploy previous version.
   c. All data written since the bad migration is lost. Acceptable if the bad migration caused corruption.
3. **Post-rollback:**
   a. Root cause analysis within 24 hours.
   b. Fix, test in staging with production-like data.
   c. Re-deploy with monitoring.

**Fallback:** iOS clients have cache. Short backend outages during rollback (< 2 minutes) are absorbed by client-side caching.

**Prevention:**
- Staging environment with production-like data.
- Pre-migration database snapshots.
- Rolling deployments (minimum 2 replicas, one-at-a-time).
- Feature flags for major changes (rollback without redeployment).
- Canary deployments: route 10% of traffic to new version first.

**Monitoring:**
- Telemetry: All standard metrics (error rate, latency, pool utilization).
- Alert: Per Section 27.5 of BACKEND_API.md.

**Retry strategy:** N/A (operational, not automatic).
**User communication:** If outage > 30 seconds: iOS shows "Tempo is being updated. Back shortly." via app config endpoint (if reachable) or local fallback.
**Logging:** Level `critical`. Full incident log with timeline.

---

### [SRV-011] Whoop Membership Expires (403 from Whoop API)

**Trigger:** User's Whoop membership lapses. All Whoop API calls return HTTP 403 Forbidden.

**Detection:** Backend receives 403 from any Whoop API endpoint. Distinct from 401 (token issue) -- 403 indicates account-level restriction.

**User Impact:** No new Whoop data. Historical data remains accessible.

**Immediate Response (< 100ms):**
1. Mark integration as `membership_expired` in database.
2. Stop all polling and webhook processing for this user.
3. Send push notification to user.

**Recovery Strategy:**
1. Push notification: "Your Whoop membership has expired. Tempo will use cached data until it's renewed."
2. Body quadrant: show last known data with stale indicator and note: "Whoop membership inactive."
3. Training module: fall back to "moderate" intensity recommendation (no recovery data).
4. Check membership status daily (single lightweight API call to Whoop profile endpoint) to detect re-activation.
5. When membership is renewed (API returns 200):
   a. Resume normal sync.
   b. Backfill missed data (up to 30 days).
   c. Send push: "Whoop reconnected! Syncing your data."
   d. Update integration status to `active`.

**Fallback:** HealthKit provides fallback biometric data (sleep, heart rate) if Apple Watch is worn. Training module defaults to moderate intensity.

**Prevention:** Cannot prevent -- membership is between the user and Whoop. Inform user when data becomes unavailable.

**Monitoring:**
- Telemetry: Track `whoop_membership_expired_count`.
- Track `whoop_membership_expired_duration_days` histogram.

**Retry strategy:** Daily check for re-activation.
**User communication:** Push notification + inline quadrant message.
**Logging:** Level `info`. Include last sync date and data staleness.

---

### [SRV-012] WebSocket Connection Drops (Real-Time Features)

**Trigger:** WebSocket connection between iOS app and backend (used for real-time leaderboard updates, live challenge tracking) drops. Causes: network change, server restart, idle timeout.

**Detection:** WebSocket `onClose` handler fires. Heartbeat ping/pong fails.

**User Impact:** Real-time updates stop. Leaderboard may not reflect latest XP. Live challenges do not update.

**Immediate Response (< 100ms):**
1. Mark WebSocket as disconnected.
2. Switch to polling fallback for real-time features.

**Recovery Strategy:**
1. Automatic reconnection with exponential backoff: 1s, 2s, 4s, 8s, max 30s.
2. On reconnect: send a "catch-up" request for any events missed during disconnection (server stores event log per user, 1-hour retention).
3. While disconnected: poll leaderboard endpoint every 60 seconds instead of real-time updates. Poll challenge status every 30 seconds during active challenges.
4. After 5 failed reconnection attempts: stop reconnecting. Resume on next app foreground.

**Fallback:** Polling provides identical data, just with higher latency (30-60 seconds vs. real-time). User impact is minimal.

**Prevention:** Server-side heartbeat every 30 seconds. Client ping/pong every 45 seconds. Idle timeout: 5 minutes. Reconnect on app foreground.

**Monitoring:**
- Telemetry: Track `websocket_connections_active` gauge.
- Track `websocket_reconnection_count`.
- Alert: If > 50% of connections drop within 1 minute (server issue).

**Retry strategy:** Exponential backoff (1s to 30s). Max 5 attempts per background cycle.
**User communication:** Silent. Polling fallback is seamless.
**Logging:** Level `info` for drops. Level `warning` for > 3 consecutive reconnection failures.

---

## 6. Authentication Errors

### [AUTH-001] Access Token Expired During App Use

**Trigger:** JWT access token expires (15-minute TTL) while user is actively using the app. Next API call returns 401 with error code 1001.

**Detection:** `APIClient` receives 401 with code 1001. JWT `exp` claim is in the past.

**User Impact:** Momentary pause in data loading (< 2 seconds) while tokens refresh. If refresh succeeds: invisible to user.

**Immediate Response (< 100ms):**
1. Intercept 401 in `APIClient` middleware.
2. Initiate token refresh.
3. Queue the failed request for retry after refresh.

**Recovery Strategy:**
1. Refresh flow:
   a. `POST /v1/auth/refresh` with current refresh token.
   b. Backend validates refresh token (hash lookup, not expired, not revoked, device ID matches).
   c. Old refresh token revoked (single-use rotation).
   d. New access + refresh tokens returned.
   e. Store in Keychain.
   f. Retry the original failed request with new access token.
2. If refresh fails with 1009 (refresh token expired):
   a. Clear all tokens from Keychain.
   b. Present Sign in with Apple screen.
   c. "Session expired. Please sign in again."
3. If refresh fails with 1011 (replay detected):
   a. All sessions invalidated by backend (security event).
   b. Force sign-out on all devices.
   c. "Security alert: your sessions have been reset. Please sign in again."
   d. Log security event.

**Fallback:** If refresh fails and user cannot sign in: app shows cached data in read-only mode with persistent sign-in prompt.

**Prevention:** Proactive refresh: `APIClient` checks token expiry before each request. If < 2 minutes remaining, refresh preemptively.

**Monitoring:**
- Telemetry: Track `token_refresh_count` (success/failure).
- Alert: Replay detection (1011) is always Critical.

**Retry strategy:** Automatic refresh + retry. Single attempt.
**User communication:** Silent if refresh succeeds. Full-screen sign-in if refresh fails.
**Logging:** Level `info` for normal refresh. Level `critical` for replay detection.

---

### [AUTH-002] Refresh Token Expired (30-Day TTL)

**Trigger:** User has not opened the app in 30+ days. Refresh token has expired.

**Detection:** `POST /v1/auth/refresh` returns 401 with error code 1009.

**User Impact:** User must sign in again. All local data remains (SwiftData persists). No data loss.

**Immediate Response (< 100ms):**
1. Clear expired tokens from Keychain.
2. Navigate to sign-in screen.

**Recovery Strategy:**
1. Show Sign in with Apple screen with explanation: "Welcome back! Please sign in to continue."
2. After sign-in: backend matches Apple `sub` to existing account. Full account restored.
3. Trigger `fullSync()` to refresh all data.
4. All local data (study sessions, workouts) that was never synced is still in SwiftData. Queue for upload.

**Fallback:** If Sign in with Apple fails: user can use the app in offline/read-only mode with cached data.

**Prevention:** Encourage regular app use (daily notifications maintain engagement). Consider extending refresh token TTL to 90 days.

**Monitoring:**
- Telemetry: Track `refresh_token_expired_count`.
- Track `days_since_last_use` histogram for expired tokens.

**Retry strategy:** User-initiated (sign in again).
**User communication:** Full-screen sign-in with welcoming tone.
**Logging:** Level `info`. Include last active date.

---

### [AUTH-003] Refresh Token Replay Detected

**Trigger:** A refresh token that was already used (and rotated) is presented again. This indicates either a bug (client cached the old token) or a stolen token being replayed.

**Detection:** Backend detects the token hash matches a revoked token. Returns 401 with error code 1011.

**User Impact:** All sessions for this user are immediately invalidated. User is forced to sign in on all devices.

**Immediate Response (< 100ms):**
1. Backend revokes ALL refresh tokens for this user.
2. Return 1011 to the requesting client.
3. Log security event with full context.

**Recovery Strategy:**
1. iOS receives 1011: clear all tokens from Keychain.
2. Show security-aware sign-in screen: "For your security, all sessions have been signed out. Please sign in again."
3. After sign-in: normal operation resumes with fresh tokens.
4. Backend logs: IP addresses, device IDs, timestamps for both the original use and the replay.
5. If the replay came from a different device/IP: potential compromise. Consider notifying user via email if configured.

**Fallback:** User signs in again. No data loss (backend has all synced data).

**Prevention:** Client stores tokens in Keychain (hardware-backed). Token rotation ensures each token is single-use. Race condition prevention: if two requests simultaneously try to refresh, `APIClient` deduplicates (only one refresh request).

**Monitoring:**
- Telemetry: Track `refresh_token_replay_count`.
- Alert: Any replay event is Critical.

**Retry strategy:** User must sign in again.
**User communication:** Full-screen security message.
**Logging:** Level `critical`. Include both token uses (original and replay), device IDs, IPs, timestamps.

---

### [AUTH-004] Device ID Mismatch on Token Refresh

**Trigger:** Refresh token's bound `device_id` does not match the `X-Device-Id` header. Returns 401 with error code 1012.

**Detection:** Backend compares `device_id` in stored refresh token with request header.

**User Impact:** Token refresh fails. User must sign in again on this device.

**Immediate Response (< 100ms):**
1. Return 1012.
2. Do NOT revoke other sessions (this is likely a legitimate device, not an attack).

**Recovery Strategy:**
1. iOS receives 1012: clear tokens for this device.
2. Show sign-in screen: "Please sign in on this device."
3. After sign-in: new device-bound tokens issued.
4. Common cause: user restored an iCloud backup to a different device. The Keychain tokens transferred but the `device_id` is different because it is newly generated.

**Fallback:** User signs in again. No data loss.

**Prevention:** Generate `device_id` from Keychain on first launch and persist. Keychain items survive app reinstall but `device_id` may not survive device-to-device transfer if stored in UserDefaults.

**Monitoring:**
- Telemetry: Track `device_id_mismatch_count`.

**Retry strategy:** User-initiated (sign in).
**User communication:** Full-screen sign-in prompt.
**Logging:** Level `warning`. Include expected and received device IDs.

---

### [AUTH-005] Account Deleted but User Returns Within Recovery Window

**Trigger:** User deleted their account, then signs in again within the 30-day recovery window. Backend returns 409 with error code 1007.

**Detection:** Sign in with Apple succeeds but backend finds a soft-deleted account matching the Apple `sub`.

**User Impact:** User can recover their account and all data.

**Immediate Response (< 100ms):**
1. Show recovery prompt: "Your account was scheduled for deletion. Would you like to restore it?"

**Recovery Strategy:**
1. Button 1: "Restore Account" -- calls `POST /v1/auth/recover`.
   a. Backend un-deletes the account.
   b. Restores all data (was soft-deleted, not hard-deleted).
   c. Normal sign-in flow continues.
2. Button 2: "No, Delete Permanently" -- calls `POST /v1/auth/confirm-delete` (not yet implemented at this stage).
3. After restoration: `fullSync()` repopulates local data. All integrations (Whoop, NutriTrack) are still configured.

**Fallback:** If recovery fails: user creates a new account. Old data is lost when hard-delete cron runs.

**Prevention:** Clear warning during account deletion about the 30-day window.

**Monitoring:**
- Telemetry: Track `account_recovery_count`.

**Retry strategy:** User-initiated.
**User communication:** Full-screen recovery prompt.
**Logging:** Level `info`. Include deletion date and recovery date.

---

### [AUTH-006] JWT Signing Key Rotation

**Trigger:** Every 90 days, the ES256 signing key rotates. Old key kept for 15 minutes. During the overlap: tokens signed with old key are still valid. After 15 minutes: old key is removed from JWKS.

**Detection:** This is a planned operation, not an error. However, if misconfigured: tokens signed with the old key may fail validation.

**User Impact:** If handled correctly: zero impact. If old key removed too early: users with tokens signed by old key get 401 until they refresh.

**Immediate Response (if tokens fail validation unexpectedly):**
1. iOS `APIClient` treats this as a normal 401 and refreshes.
2. New tokens are signed with the current key.

**Recovery Strategy:**
1. Token refresh resolves the issue (new access token signed with current key).
2. If the JWKS endpoint is stale (CDN caching old keys for 24 hours): force-refresh by clearing CDN cache.
3. If many users are affected simultaneously: extend old key validity by re-adding it to JWKS.

**Fallback:** Token refresh always works because the refresh endpoint does not validate the old access token (only the refresh token, which is not a JWT).

**Prevention:**
- Key rotation script: (1) add new key to JWKS, (2) start signing new tokens with new key, (3) wait 20 minutes (longer than any access token TTL), (4) remove old key from JWKS.
- Test key rotation in staging first.

**Monitoring:**
- Telemetry: Track `jwt_validation_failure_by_key_id`.
- Alert: Spike in validation failures after rotation = Warning (old key removed too early).

**Retry strategy:** Automatic token refresh.
**User communication:** Silent.
**Logging:** Level `info` for normal rotation. Level `warning` for unexpected validation failures.

---

## 7. Error Severity Classification

| Severity | Definition | Response Time | Examples |
|----------|-----------|---------------|---------|
| **P0 - Critical** | App unusable for all users. Data loss risk. Security breach. | < 15 minutes | SRV-001, SRV-008, AUTH-003, DAT-001 |
| **P1 - High** | Major feature broken for many users. No workaround. | < 1 hour | NET-004, SRV-010, INT-012, DAT-002 |
| **P2 - Medium** | Feature degraded. Workaround available. | < 4 hours | INT-001, INT-005, NET-005, UXE-001 |
| **P3 - Low** | Minor issue. Cosmetic or edge case. | < 24 hours | NET-011, INT-011, DAT-007, DAT-009 |
| **P4 - Informational** | Expected behavior. Logging only. | No response needed | INT-009, DAT-006, UXE-009 |

---

## 8. Global Retry Policy

| Category | Strategy | Max Retries | Backoff | Circuit Breaker |
|----------|----------|-------------|---------|-----------------|
| Auth (token refresh) | Immediate | 1 | None | No |
| Sync (Whoop, NutriTrack) | Exponential backoff | 3 | 2s, 4s, 8s | Yes (3 failures in 60s) |
| Webhooks (inbound processing) | Exponential backoff | 3 | Job queue managed | No |
| Push notifications | Exponential backoff | 3 (5 for critical) | 10s, 30s, 90s | No |
| Background jobs | Per-job policy | 0-3 | Varies | No |
| User-initiated (OAuth) | Never auto-retry | 0 | N/A | No |
| Health check polling | Fixed interval | Unlimited | 30s | Yes (circuit breaker pattern) |

**Global rules:**
1. Never retry a request that returned 4xx (client error), except 401 (trigger refresh) and 429 (respect Retry-After).
2. Always retry 5xx (server error) with backoff.
3. Always retry network errors (timeout, connection reset) with backoff.
4. Idempotency keys on all mutating retries to prevent duplicate side effects.
5. Maximum total retry duration: 60 seconds. After that, serve cache and give up until next sync cycle.

---

## 9. Offline Queue Architecture

```
+---------------------------------------------------+
|                 Offline Queue                      |
|                                                    |
|  Priority 1: Auth (token refresh)                  |
|  Priority 2: Workout uploads                       |
|  Priority 3: Study session uploads                 |
|  Priority 4: Non-negotiable status updates         |
|  Priority 5: XP events                             |
|  Priority 6: Daily snapshots                       |
|  Priority 7: Configuration updates                 |
|                                                    |
|  Max size: 2000 entries (after compaction)          |
|  Persistence: SwiftData                            |
|  Drain trigger: Network reconnect + 1s debounce    |
|  Drain rate: 1 request per 100ms                   |
|  Compaction: On every addition                      |
|  TTL: 7 days (entries older than 7 days dropped)   |
+---------------------------------------------------+
```

**Queue entry structure:**
```swift
@Model
class OfflineQueueEntry {
    var id: UUID
    var priority: Int                // 1 (highest) to 7 (lowest)
    var endpoint: String             // e.g., "/v1/workouts"
    var method: String               // "POST", "PATCH", etc.
    var body: Data                   // JSON-encoded request body
    var idempotencyKey: String       // Prevents duplicate processing
    var createdAt: Date
    var retryCount: Int
    var lastAttemptAt: Date?
    var status: QueueEntryStatus     // .pending, .inFlight, .completed, .failed
}
```

**Compaction rules:**
1. Daily snapshots: keep only latest per day.
2. Configuration updates: keep only latest.
3. XP events: batch into single request (up to 50 events).
4. All others: keep all (unique data).

---

## Appendix: Error Code Quick Reference

| Code | Name | Category | Severity | Recovery |
|------|------|----------|----------|----------|
| NET-001 | Internet loss (dashboard) | Network | P2 | Automatic on reconnect |
| NET-002 | Internet loss (workout) | Network | P3 | Automatic on reconnect |
| NET-003 | Internet loss (OAuth) | Network | P2 | User retry |
| NET-004 | Backend 503 | Network | P1 | Circuit breaker + auto |
| NET-005 | Request timeout | Network | P2 | Exponential backoff |
| NET-006 | DNS failure | Network | P2 | Fixed interval retry |
| NET-007 | SSL error | Network | P1 | Network change only |
| NET-008 | Response too large | Network | P3 | Reduce payload + retry |
| NET-009 | Malformed JSON | Network | P2 | Single retry + cache |
| NET-010 | Rate limited (429) | Network | P3 | Respect Retry-After |
| NET-011 | CDN stale | Network | P4 | Force refresh |
| INT-001 | Whoop 401 (token expired) | Integration | P2 | Auto refresh |
| INT-002 | Whoop 429 (rate limited) | Integration | P3 | Respect Retry-After |
| INT-003 | Whoop webhook failure | Integration | P3 | Triple-layer redundancy |
| INT-004 | Whoop recovery pending | Integration | P4 | Poll every 2 min |
| INT-005 | NutriTrack unreachable | Integration | P2 | Exponential backoff |
| INT-006 | NutriTrack PIN expired | Integration | P2 | User re-enters PIN |
| INT-007 | NutriTrack corrupt data | Integration | P2 | Single retry + cache |
| INT-008 | HealthKit permission revoked | Integration | P3 | Guide to Settings |
| INT-009 | HealthKit no data | Integration | P4 | Not an error |
| INT-010 | Calendar permission revoked | Integration | P3 | Guide to Settings |
| INT-011 | Calendar overlapping events | Integration | P4 | Automatic dedup |
| INT-012 | Apple Sign In validation fail | Integration | P1 | JWKS refresh + retry |
| DAT-001 | SwiftData migration fail | Data | P0 | Reset + re-sync |
| DAT-002 | SwiftData corruption | Data | P0 | Integrity check + reset |
| DAT-003 | Concurrent write conflict | Data | P3 | Merge policy |
| DAT-004 | Sync conflict | Data | P3 | Timestamp resolution |
| DAT-005 | Offline queue overflow | Data | P3 | Compaction + priority |
| DAT-006 | Timezone/DST error | Data | P4 | Recalculation |
| DAT-007 | Numeric overflow | Data | P3 | Clamping + validation |
| DAT-008 | Missing API field | Data | P3 | Defaults + degrade |
| DAT-009 | Stale cache | Data | P4 | Visual indicators |
| DAT-010 | iCloud sync conflict | Data | P3 | Custom merge |
| UXE-001 | Force-quit during workout | UX | P2 | Checkpoint recovery |
| UXE-002 | Force-quit during timer | UX | P2 | Checkpoint recovery |
| UXE-003 | Crash during onboarding | UX | P2 | Step resume |
| UXE-004 | Phone call during workout | UX | P4 | Timer adjustment |
| UXE-005 | Low battery during workout | UX | P3 | Aggressive save |
| UXE-006 | Low storage | UX | P2 | Tiered cleanup |
| UXE-007 | Delete + reinstall | UX | P3 | Backend re-sync |
| UXE-008 | Device migration | UX | P3 | Backend re-sync |
| UXE-009 | Notifications denied | UX | P4 | In-app fallback |
| UXE-010 | HealthKit partial deny | UX | P4 | Feature degradation map |
| SRV-001 | DB pool exhausted | Backend | P0 | Kill long queries |
| SRV-002 | Redis unavailable | Backend | P1 | Bypass mode |
| SRV-003 | Claude API failure | Backend | P3 | Rule-based fallback |
| SRV-004 | APNs delivery failure | Backend | P3 | In-app queue fallback |
| SRV-005 | Webhook processing fail | Backend | P3 | Job retry + reconciliation |
| SRV-006 | Materialized view fail | Backend | P3 | Stale view served |
| SRV-007 | Background job fail | Backend | P3 | Per-job retry policy |
| SRV-008 | Disk full | Backend | P0 | Automated cleanup |
| SRV-009 | Memory leak | Backend | P1 | Process restart |
| SRV-010 | Bad deployment | Backend | P1 | Rollback procedure |
| SRV-011 | Whoop membership expired | Backend | P3 | Daily re-check |
| SRV-012 | WebSocket drop | Backend | P4 | Polling fallback |
| AUTH-001 | Access token expired | Auth | P4 | Auto refresh |
| AUTH-002 | Refresh token expired | Auth | P3 | User sign-in |
| AUTH-003 | Refresh token replay | Auth | P0 | Full session revocation |
| AUTH-004 | Device ID mismatch | Auth | P3 | User sign-in |
| AUTH-005 | Deleted account recovery | Auth | P4 | User-initiated |
| AUTH-006 | JWT key rotation | Auth | P4 | Auto refresh |
