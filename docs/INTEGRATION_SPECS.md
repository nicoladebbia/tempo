# Tempo — Integration Specifications

> **Version:** 1.0.0
> **Last updated:** 2026-03-24
> **Author:** Nicola Debbia
> **Status:** Definitive Reference

This document specifies every detail of how data flows between Tempo and its four external integrations: Whoop API (v2), Apple HealthKit, NutriTrack (Flask API), and Apple Calendar (EventKit). It is the single source of truth for all integration behavior, edge cases, error handling, and Swift implementation.

---

## Table of Contents

1. [Whoop API Integration](#1-whoop-api-integration)
2. [Apple HealthKit Integration](#2-apple-healthkit-integration)
3. [NutriTrack Integration](#3-nutritrack-integration)
4. [Apple Calendar (EventKit) Integration](#4-apple-calendar-eventkit-integration)
5. [Sync Architecture](#5-sync-architecture)
6. [Error Recovery & Resilience](#6-error-recovery--resilience)

---

## 1. Whoop API Integration

> **CRITICAL: Whoop Developer Mode 10-User Limit (Technical Feasibility Audit Section 2.1)**
>
> Whoop's developer API has a **10-user hard limit** in development mode. To go beyond 10 users, you must apply for production access approval from Whoop. Key facts:
>
> - **Approval timeline:** 2 weeks to 3+ months. Some apps never receive a response.
> - **Requirements for application:** Working demo, privacy policy, terms of service.
> - **Whoop can revoke access at any time** if the integration competes with their product.
>
> **Action items:**
> 1. **Apply for Whoop production access NOW** -- do not wait until launch.
> 2. **Ship beta with HealthKit-only fallback.** All beta testing (TestFlight) must work without Whoop.
> 3. **Gate Whoop features behind a connection toggle.** If Whoop approval is delayed, the app ships with Apple Watch + HealthKit recovery estimation instead.
> 4. **Design Tempo so Whoop is a premium add-on, not a core dependency.** Apple Watch + HealthKit can provide recovery estimation (HRV, RHR, sleep stages) without Whoop, and the addressable market is 100x larger (Apple Watch ~100M users vs Whoop ~1M).

### 1.1 Authentication Flow — Step by Step

The Whoop OAuth2 flow is a three-legged process split between the iOS app and the Tempo backend. The backend holds the client_secret and manages token storage. The iOS app never touches raw Whoop tokens.

#### Step 1: User Taps "Connect Whoop"

**UI:** `WhoopConnectView` displays a branded "Connect Whoop" button (Whoop's brand guidelines require their logo mark, black/green color scheme).

**Pre-check before opening OAuth:**
```swift
// WhoopService.swift — iOS side
@Observable
final class WhoopService {
    private let apiClient: APIClient
    private(set) var connectionState: WhoopConnectionState = .disconnected

    enum WhoopConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(lastSync: Date?)
        case error(WhoopError)
    }

    /// Initiates the Whoop OAuth flow.
    /// 1. Requests the authorization URL from the backend.
    /// 2. Opens ASWebAuthenticationSession.
    /// 3. Sends the callback code to the backend.
    func connect() async throws {
        guard connectionState != .connecting else { return }
        connectionState = .connecting

        do {
            // Step 2: Get authorization URL from backend
            let authResponse = try await apiClient.get(
                "/v1/integrations/whoop/authorize",
                response: WhoopAuthURLResponse.self
            )

            // Step 3-6: Open browser and handle callback
            let callbackURL = try await openAuthSession(
                url: authResponse.authorizationURL,
                expectedState: authResponse.state
            )

            // Step 7: Send code to backend
            try await exchangeCode(from: callbackURL)

            // Step 11: Update UI and trigger initial sync
            connectionState = .connected(lastSync: nil)
            try await triggerInitialSync()
        } catch let error as WhoopError where error == .userCancelled {
            // User intentionally cancelled — reset to disconnected, do NOT show error
            connectionState = .disconnected
            // Do not rethrow — cancellation is not an error
        } catch {
            connectionState = .error(WhoopError(from: error))
            throw error
        }
    }
}
```

**Error cases:**
- Network unreachable before starting: show "No internet connection. Connect to Wi-Fi or cellular to link Whoop." with retry button.
- Backend returns 409 (already connected): show "Whoop is already connected. Disconnect first to re-link."
- Timeout (15 seconds): cancel the request, show "Connection timed out. Try again."

#### Step 2: Construct Authorization URL

The iOS app requests the URL from the Tempo backend, which constructs it server-side to keep the `client_id` and scopes centralized.

**Backend endpoint:** `GET /v1/integrations/whoop/authorize`

**Backend constructs:**
```
https://api.prod.whoop.com/oauth/oauth2/auth
  ?client_id=<WHOOP_CLIENT_ID>
  &redirect_uri=https://api.tempo.app/v1/integrations/whoop/callback
  &scope=read:recovery read:cycles read:workout read:sleep read:profile read:body_measurement offline
  &state=<CSRF_TOKEN>
  &response_type=code
```

**Parameter details:**

| Parameter | Value | Notes |
|-----------|-------|-------|
| `client_id` | From env `WHOOP_CLIENT_ID` | Registered at developer.whoop.com |
| `redirect_uri` | `https://api.tempo.app/v1/integrations/whoop/callback` | Must exactly match the registered redirect URI in Whoop dashboard |
| `scope` | `read:recovery read:cycles read:workout read:sleep read:profile read:body_measurement offline` | `offline` scope is required for refresh tokens |
| `state` | Cryptographically random 32-byte hex string (64 hex characters) | Stored server-side in Redis with 10-minute TTL, keyed to user_id. **Whoop requires the state parameter to be at least 8 characters.** Our 64-char hex string exceeds this. Never generate a state shorter than 8 chars. |
| `response_type` | `code` | Authorization code grant |

**Response from backend:**
```json
{
  "ok": true,
  "data": {
    "authorization_url": "https://api.prod.whoop.com/oauth/oauth2/auth?client_id=...&state=...",
    "state": "a1b2c3d4e5f6..."
  }
}
```

**Error cases:**
- Backend returns 409 error code 3001: Whoop already connected.
- Backend unreachable: show offline error, retry with exponential backoff.

#### Step 3: Open ASWebAuthenticationSession

```swift
// WhoopService.swift — iOS side
private func openAuthSession(url: URL, expectedState: String) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "tempo"  // matches tempo://
        ) { callbackURL, error in
            if let error = error {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: WhoopError.userCancelled)
                } else {
                    continuation.resume(throwing: WhoopError.authSessionFailed(error))
                }
                return
            }

            guard let callbackURL = callbackURL else {
                continuation.resume(throwing: WhoopError.noCallbackURL)
                return
            }

            continuation.resume(returning: callbackURL)
        }

        // Must set presentationContextProvider on @MainActor
        session.presentationContextProviding = self
        session.prefersEphemeralWebBrowserSession = true   // Do NOT share cookies with Safari — each auth is a clean session. This prevents stale Whoop sessions from auto-logging in the wrong account and avoids cookie leakage. The tradeoff is the user must enter Whoop credentials every time, but this is acceptable because connecting Whoop is a one-time action.
        session.start()
    }
}
```

**Why `prefersEphemeralWebBrowserSession = true`:**
- Setting `true` means ASWebAuthenticationSession uses a private, isolated cookie jar — no cookies from Safari or other apps bleed in, and no cookies persist after the session ends.
- Setting `false` would allow SSO cookies from Safari, meaning if the user is already logged into Whoop in Safari, the OAuth flow auto-completes. This sounds convenient but is dangerous: if a family member is logged into Whoop in Safari, Tempo would silently connect the wrong account.
- Since Whoop connection is a one-time setup event (not a frequent login), the UX cost of entering credentials once is negligible.
- This also satisfies App Store review requirements for OAuth flows that handle health data.

**Why ASWebAuthenticationSession, not SFSafariViewController:**
- ASWebAuthenticationSession is the Apple-recommended approach for OAuth on iOS 13+ and is the ONLY correct choice for iOS 17.4+.
- It handles the custom URL scheme callback automatically via `callbackURLScheme`.
- It shows the "app wants to sign in using..." system prompt, which builds user trust.
- SFSafariViewController requires manual URL interception via delegate methods and is deprecated for OAuth flows as of iOS 12.
- ASWebAuthenticationSession supports `prefersEphemeralWebBrowserSession` for privacy.
- On iOS 17.4+, SFSafariViewController does NOT reliably intercept custom URL scheme redirects — ASWebAuthenticationSession is the only supported mechanism.

**Custom URL scheme `tempo://` — no Associated Domains required:**
- The `callbackURLScheme: "tempo"` parameter tells ASWebAuthenticationSession to intercept any redirect to `tempo://...`.
- This uses iOS custom URL schemes, NOT Universal Links. Custom URL schemes are registered in `Info.plist` under `CFBundleURLTypes` and work without any Associated Domains entitlement or `apple-app-site-association` file.
- Associated Domains (and the `.applinks:` prefix) are only required for Universal Links (`https://` scheme). Our flow uses Universal Links for the backend callback (`https://api.tempo.app/...`) which then redirects to `tempo://...`, but the iOS app only needs to handle the custom scheme part.
- Ensure `Info.plist` contains:
  ```xml
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>tempo</string>
      </array>
    </dict>
  </array>
  ```

**Error cases:**
- User taps "Cancel" on the system prompt: `ASWebAuthenticationSessionError.canceledLogin`. Catch this and set state back to `.disconnected`. Do NOT show an error alert — the user intentionally cancelled. Do NOT log this as an error in analytics — it is expected user behavior.
- User closes the browser tab: same cancel error.
- Whoop login page fails to load (Whoop servers down): the user sees a blank/error page in the browser. No callback fires. After 60 seconds, show "Connection timed out" and dismiss the session programmatically by cancelling the `ASWebAuthenticationSession`.
- iOS kills the session (backgrounded for too long): cancel error.
- User switches to another app mid-OAuth and returns: ASWebAuthenticationSession may have been deallocated. The `withCheckedThrowingContinuation` will never resume. Guard against this by holding a strong reference to the session as an instance property and implementing a timeout.

#### Step 4: User Authorizes on Whoop's Page

This step is entirely within Whoop's web UI. The user logs in (if not already), reviews the requested scopes, and taps "Authorize."

**What the user sees:**
1. Whoop login page (email + password, or SSO).
2. Consent screen listing: Recovery, Sleep, Workouts, Cycles, Profile, Body Measurements.
3. "Authorize" or "Deny" button.

**If user denies:** Whoop redirects with `?error=access_denied&state=YYY`. The backend callback handler detects this and redirects to `tempo://integrations/whoop/error?code=3004&message=access_denied`.

#### Step 5: Whoop Redirects to Callback

Whoop redirects to:
```
https://api.tempo.app/v1/integrations/whoop/callback?code=XXX&state=YYY
```

This hits the **backend** callback endpoint (not the iOS app directly). The backend then redirects to the iOS app via custom URL scheme.

**Backend callback flow:**
1. Validate the `state` parameter against Redis.
2. Exchange the `code` for tokens (Step 8).
3. On success: redirect to `tempo://integrations/whoop/success`
4. On failure: redirect to `tempo://integrations/whoop/error?code=XXXX&message=...`

The iOS app's `ASWebAuthenticationSession` catches the `tempo://` redirect.

#### Step 6: iOS Validates State Parameter

```swift
private func exchangeCode(from callbackURL: URL) async throws {
    guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
        throw WhoopError.invalidCallbackURL
    }

    // Check for error response from Whoop
    if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
        switch error {
        case "access_denied":
            throw WhoopError.userDeniedAccess
        default:
            throw WhoopError.oauthError(error)
        }
    }

    // The state was already validated server-side in the callback handler.
    // The iOS app receives tempo://integrations/whoop/success or tempo://integrations/whoop/error.
    // Check which one we got.

    guard callbackURL.host == "integrations",
          callbackURL.pathComponents.contains("whoop") else {
        throw WhoopError.invalidCallbackURL
    }

    if callbackURL.pathComponents.contains("error") {
        let code = components.queryItems?.first(where: { $0.name == "code" })?.value ?? "unknown"
        let message = components.queryItems?.first(where: { $0.name == "message" })?.value ?? "Unknown error"
        throw WhoopError.backendError(code: code, message: message)
    }

    // Success — the backend already exchanged the code and stored tokens.
    // No further action needed from the iOS app.
}
```

**Error cases:**
- State mismatch (possible CSRF attack): backend returns error, iOS shows "Authentication failed. Please try again."
- State expired (user took >10 minutes): backend returns error code 3002, iOS shows "Session expired. Please try again."

#### Step 7: Backend Receives Authorization Code (Already handled in Step 5)

The backend callback endpoint handles this. The iOS app does not send the code separately — the backend intercepts it at the `redirect_uri`.

#### Step 8: Backend Exchanges Code for Tokens

```
POST https://api.prod.whoop.com/oauth/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code=<AUTHORIZATION_CODE>
&client_id=<WHOOP_CLIENT_ID>
&client_secret=<WHOOP_CLIENT_SECRET>
&redirect_uri=https://api.tempo.app/v1/integrations/whoop/callback
```

**Whoop token response:**
```json
{
  "access_token": "eyJ...",
  "refresh_token": "abc123...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "scope": "read:recovery read:cycles read:workout read:sleep read:profile read:body_measurement offline"
}
```

**Error cases:**
- Invalid code (expired or already used): Whoop returns 400. Backend logs the error, redirects iOS to error URL. Show "Authorization failed. Please try again."
- Whoop servers unreachable: backend returns 502, error code 3007. Retry up to 3 times with 2-second delays before failing.
- Rate limited by Whoop: HTTP 429. Respect `Retry-After` header.
- Missing `offline` scope in response (Whoop changed scope grants): log warning, proceed but mark that refresh may not work.

#### Step 9: Backend Encrypts and Stores Tokens

```swift
// Vapor backend — WhoopService.swift
func storeTokens(
    userId: UUID,
    accessToken: String,
    refreshToken: String,
    expiresIn: Int,
    on db: Database
) async throws {
    let encryptedAccess = try CryptoService.encrypt(
        plaintext: accessToken,
        using: .whoopTokenKey  // Derived from WHOOP_TOKEN_ENCRYPTION_KEY env var
    )
    let encryptedRefresh = try CryptoService.encrypt(
        plaintext: refreshToken,
        using: .whoopTokenKey
    )

    let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))

    // Upsert — replace existing tokens for this user
    if let existing = try await WhoopIntegration.query(on: db)
        .filter(\.$user.$id == userId)
        .first()
    {
        existing.encryptedAccessToken = encryptedAccess
        existing.encryptedRefreshToken = encryptedRefresh
        existing.tokenExpiresAt = expiresAt
        existing.lastSyncAt = nil
        existing.lastSyncStatus = nil
        try await existing.save(on: db)
    } else {
        let integration = WhoopIntegration(
            userId: userId,
            encryptedAccessToken: encryptedAccess,
            encryptedRefreshToken: encryptedRefresh,
            tokenExpiresAt: expiresAt
        )
        try await integration.save(on: db)
    }
}
```

**Encryption details:**
- Algorithm: AES-256-GCM
- Key derivation: HKDF-SHA256 from the `WHOOP_TOKEN_ENCRYPTION_KEY` environment variable, with salt `"whoop-token-v1"` and info `"tempo-whoop-encryption"`
- Each encryption generates a random 12-byte nonce
- Storage format: `base64(nonce || ciphertext || tag)` as a single TEXT column
- Key rotation: when rotating the encryption key, decrypt with old key, re-encrypt with new key in a migration

#### Step 10: Backend Returns Success to iOS

The backend redirects the browser to `tempo://integrations/whoop/success`, which `ASWebAuthenticationSession` intercepts and delivers to the app.

**UI update:** The `WhoopConnectView` transitions from the "Connect Whoop" button to a success state showing "Whoop Connected" with a green checkmark animation.

#### Step 11: iOS Updates UI, Triggers Initial Sync

```swift
private func triggerInitialSync() async throws {
    // Request full 30-day history sync from backend
    let response = try await apiClient.post(
        "/v1/integrations/whoop/sync",
        body: WhoopSyncRequest(daysBack: 30),
        response: WhoopSyncResponse.self
    )

    // The sync happens asynchronously on the backend.
    // The backend sends a push notification when complete.
    // Meanwhile, start polling for today's data immediately.
    try await fetchTodayData()
}
```

**Error cases:**
- Backend returns 409 (sync already in progress): ignore silently, the sync is happening.
- Network error during sync trigger: queue the sync trigger for retry. Show "Connected! Syncing your data..." with a spinner.
- Push notification not delivered (user denied notifications): fall back to polling every 30 seconds for 5 minutes, then every 5 minutes.

---

### 1.2 Token Management

#### Refresh Flow

Access tokens expire after 1 hour (3600 seconds). The backend refreshes proactively.

```swift
// Vapor backend — WhoopTokenManager.swift (actor for thread safety)
actor WhoopTokenManager {
    private var refreshTasks: [UUID: Task<String, Error>] = [:]

    /// Returns a valid access token, refreshing if needed.
    /// Uses a per-user lock to prevent concurrent refresh races.
    func validAccessToken(for userId: UUID, on db: Database) async throws -> String {
        // If a refresh is already in flight for this user, await it
        if let existingTask = refreshTasks[userId] {
            return try await existingTask.value
        }

        guard let integration = try await WhoopIntegration.query(on: db)
            .filter(\.$user.$id == userId)
            .first()
        else {
            throw WhoopError.notConnected
        }

        let accessToken = try CryptoService.decrypt(
            ciphertext: integration.encryptedAccessToken,
            using: .whoopTokenKey
        )

        // If token expires in more than 5 minutes, it's still valid
        let fiveMinutesFromNow = Date().addingTimeInterval(300)
        if integration.tokenExpiresAt > fiveMinutesFromNow {
            return accessToken
        }

        // Token is expiring soon or already expired — refresh
        let task = Task<String, Error> {
            defer { refreshTasks[userId] = nil }
            return try await performRefresh(for: integration, on: db)
        }
        refreshTasks[userId] = task
        return try await task.value
    }

    private func performRefresh(
        for integration: WhoopIntegration,
        on db: Database
    ) async throws -> String {
        let refreshToken = try CryptoService.decrypt(
            ciphertext: integration.encryptedRefreshToken,
            using: .whoopTokenKey
        )

        // POST to Whoop token endpoint
        let response = try await httpClient.post(
            "https://api.prod.whoop.com/oauth/oauth2/token",
            body: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": Environment.get("WHOOP_CLIENT_ID")!,
                "client_secret": Environment.get("WHOOP_CLIENT_SECRET")!,
            ]
        )

        guard response.status == .ok else {
            if response.status == .unauthorized || response.status == .badRequest {
                // Refresh token is invalid/revoked — mark as disconnected
                integration.lastSyncStatus = "token_revoked"
                try await integration.save(on: db)
                throw WhoopError.refreshTokenRevoked
            }
            throw WhoopError.refreshFailed(status: response.status)
        }

        let tokenResponse = try response.decode(WhoopTokenResponse.self)

        // Store new tokens
        try await storeTokens(
            userId: integration.$user.id,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresIn: tokenResponse.expiresIn,
            on: db
        )

        return tokenResponse.accessToken
    }
}
```

#### Refresh Failure Scenarios

| Scenario | HTTP Status | Action |
|----------|-------------|--------|
| Refresh token valid | 200 | Store new tokens, continue |
| Refresh token expired | 401 | Mark integration as `token_revoked`, send push to user: "Whoop disconnected. Tap to reconnect.", trigger re-auth flow (see below) |
| Refresh token revoked (user revoked from Whoop app) | 400 | Same as expired |
| Whoop servers down | 500/502/503 | Retry 3 times with exponential backoff (2s, 4s, 8s). If all fail, mark as `degraded`. Retry again on next API call. |
| Rate limited | 429 | Respect `Retry-After` header. Queue the refresh. |
| Network timeout | N/A | Retry up to 3 times with 2s backoff. Do NOT mark as revoked — the token may still be valid. |

#### Re-Authentication Flow (Expired Refresh Token)

When the refresh token is expired or revoked, the user must re-authorize through the full OAuth flow. This cannot be done silently.

```swift
// Vapor backend — WhoopTokenManager.swift
private func handleRefreshTokenExpired(
    for integration: WhoopIntegration,
    on db: Database,
    app: Application
) async throws {
    // 1. Mark integration as requiring re-auth
    integration.lastSyncStatus = "token_revoked"
    integration.encryptedAccessToken = ""  // Clear invalid tokens
    integration.encryptedRefreshToken = ""
    try await integration.save(on: db)

    // 2. Send visible push notification to user
    try await pushService.sendVisiblePush(
        to: integration.$user.id,
        title: "Whoop Disconnected",
        body: "Your Whoop session has expired. Open Tempo to reconnect.",
        category: "WHOOP_REAUTH",
        app: app
    )

    // 3. When user opens the app, WhoopService detects token_revoked status
    //    and shows the reconnect UI automatically (same as initial connect flow).
    //    The old integration record is reused — storeTokens() does an upsert.
}
```

**iOS side — detecting re-auth requirement:**
```swift
// WhoopService.swift
func checkConnectionOnLaunch() async {
    do {
        let status = try await apiClient.get(
            "/v1/integrations/whoop/status",
            response: WhoopStatusResponse.self
        )

        switch status.data.state {
        case "connected":
            connectionState = .connected(lastSync: status.data.lastSyncAt)
        case "token_revoked":
            connectionState = .error(.refreshTokenRevoked)
            // Show reconnect banner — NOT a blocking modal
        case "degraded":
            connectionState = .connected(lastSync: status.data.lastSyncAt)
            // Show warning but continue with cached data
        default:
            connectionState = .disconnected
        }
    } catch {
        // Network error — keep previous state, use cached data
    }
}
```

#### Race Condition Prevention

The `WhoopTokenManager` is an `actor`, which serializes all access. The `refreshTasks` dictionary ensures that if 5 API calls all discover the token is expired simultaneously, only ONE refresh request is sent to Whoop. All 5 callers await the same `Task`.

**How concurrent requests are handled step-by-step:**
1. Request A calls `validAccessToken()`, finds token expired, creates a `Task` and stores it in `refreshTasks[userId]`.
2. Request B calls `validAccessToken()` while A's refresh is in-flight. It finds the existing task in `refreshTasks[userId]` and calls `try await existingTask.value` — it does NOT create a second refresh request.
3. Request A's refresh completes. The `defer { refreshTasks[userId] = nil }` clears the task.
4. Both Request A and Request B receive the new access token from the same `Task.value`.
5. Request C arrives after the refresh completed. `refreshTasks[userId]` is nil, so it checks the token expiry normally and finds a fresh token.

**Swift 6 strict concurrency compliance:** The `WhoopTokenManager` is declared as an `actor`, which is inherently `Sendable`. The `refreshTasks` dictionary and `performRefresh` method are actor-isolated. The `Task<String, Error>` stored in `refreshTasks` is `Sendable` because both `String` and `Error` are `Sendable`. No `@unchecked Sendable` annotations are needed. The `Database` parameter is passed through Vapor's concurrency-safe database layer.

---

### 1.3 Data Sync Pipeline

#### 1.3.1 Recovery

**Whoop endpoint:** `GET https://api.prod.whoop.com/developer/v1/recovery?start=YYYY-MM-DD&end=YYYY-MM-DD`

**Whoop response shape:**
```json
{
  "records": [
    {
      "cycle_id": 123456789,
      "sleep_id": 987654321,
      "user_id": 12345,
      "created_at": "2026-03-24T08:00:00.000Z",
      "updated_at": "2026-03-24T08:05:00.000Z",
      "score_state": "SCORED",
      "score": {
        "user_calibrating": false,
        "recovery_score": 78.0,
        "resting_heart_rate": 52.0,
        "hrv_rmssd_milli": 65.4,
        "spo2_percentage": 97.2,
        "skin_temp_celsius": 36.8
      }
    }
  ],
  "next_token": null
}
```

**Polling frequency:**
- 6:00 AM - 10:00 PM local time: every 30 minutes
- 10:00 PM - 6:00 AM local time: every 60 minutes
- Rationale: recovery scores are calculated after sleep ends (usually 6-9 AM). Higher frequency during the day catches score updates and recalculations.

**Webhook trigger:** `recovery.updated` event fires when a new recovery score is calculated or an existing one is recalculated. On receiving this webhook, immediately fetch the recovery for that cycle_id.

**Data mapping — Whoop fields to Tempo `DailyRecovery` model:**

| Whoop Field | Tempo Field | Type | Transform |
|-------------|------------|------|-----------|
| `score.recovery_score` | `recoveryScore` | Double | Direct (0-100) |
| `score.resting_heart_rate` | `restingHR` | Double | Direct (bpm) |
| `score.hrv_rmssd_milli` | `hrvRmssd` | Double | Direct (ms) |
| `score.spo2_percentage` | `spo2` | Double? | Direct (%), nil if not available |
| `score.skin_temp_celsius` | `skinTemp` | Double? | Direct (C), nil if not available |
| `score_state` | `scoreState` | RecoveryScoreState | Map: "SCORED" -> .scored, "PENDING" -> .pending, "UNSCORABLE" -> .unscorable |
| `cycle_id` | `whoopCycleId` | Int64 | Direct |
| `created_at` | `createdAt` | Date | ISO 8601 parse |
| `updated_at` | `updatedAt` | Date | ISO 8601 parse |
| Derived | `recoveryZone` | RecoveryZone | .green if >= 67, .yellow if >= 34, .red if < 34 |

**Conflict resolution:** If both webhook-triggered fetch and scheduled poll return data for the same `cycle_id`, compare `updated_at` timestamps. Keep the record with the most recent `updated_at`.

**Backend storage and iOS delivery:**
```swift
// Vapor backend — WhoopSyncService.swift
func syncRecovery(for userId: UUID, on db: Database) async throws {
    let token = try await tokenManager.validAccessToken(for: userId, on: db)
    let today = Date()
    let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: today)!

    let response = try await whoopClient.getRecovery(
        token: token,
        startDate: threeDaysAgo,
        endDate: today
    )

    for record in response.records {
        // Upsert by whoop_cycle_id
        if let existing = try await WhoopRecovery.query(on: db)
            .filter(\.$whoopCycleId == record.cycleId)
            .first()
        {
            // Only update if Whoop's data is newer
            guard record.updatedAt > existing.updatedAt else { continue }
            existing.update(from: record)
            try await existing.save(on: db)
        } else {
            let recovery = WhoopRecovery(from: record, userId: userId)
            try await recovery.save(on: db)
        }
    }

    // Send silent push to iOS to trigger UI refresh
    try await pushService.sendSilentPush(
        to: userId,
        payload: ["type": "whoop_recovery_updated"]
    )
}
```

#### 1.3.2 Sleep

**Whoop endpoint:** `GET https://api.prod.whoop.com/developer/v1/activity/sleep?start=YYYY-MM-DD&end=YYYY-MM-DD`

**Whoop response shape:**
```json
{
  "records": [
    {
      "id": 987654321,
      "user_id": 12345,
      "created_at": "2026-03-24T07:30:00.000Z",
      "updated_at": "2026-03-24T07:35:00.000Z",
      "start": "2026-03-23T23:15:00.000Z",
      "end": "2026-03-24T07:00:00.000Z",
      "timezone_offset": "+01:00",
      "nap": false,
      "score_state": "SCORED",
      "score": {
        "stage_summary": {
          "total_in_bed_time_milli": 27900000,
          "total_awake_time_milli": 900000,
          "total_no_data_time_milli": 0,
          "total_light_sleep_time_milli": 10800000,
          "total_slow_wave_sleep_time_milli": 7200000,
          "total_rem_sleep_time_milli": 5400000,
          "sleep_cycle_count": 4,
          "disturbance_count": 3
        },
        "sleep_needed": {
          "baseline_milli": 28800000,
          "need_from_sleep_debt_milli": 3600000,
          "need_from_recent_strain_milli": 1800000,
          "need_from_recent_nap_milli": -1800000
        },
        "respiratory_rate": 14.5,
        "sleep_performance_percentage": 88.0,
        "sleep_consistency_percentage": 85.0,
        "sleep_efficiency_percentage": 90.0
      }
    }
  ],
  "next_token": null
}
```

**Polling frequency:** Same as recovery (they typically update together).

**Webhook trigger:** `sleep.updated`

**Special handling — Naps vs. Main Sleep:**
```swift
// Vapor backend — WhoopSleepProcessor.swift
func processSleepRecords(_ records: [WhoopSleepRecord], userId: UUID, on db: Database) async throws {
    for record in records {
        if record.nap {
            // Nap: store separately, do NOT overwrite main sleep
            try await upsertNap(record, userId: userId, on: db)
        } else {
            // Main sleep: this is the primary sleep record for the day
            // The "day" is determined by the END time (when user woke up)
            let sleepDate = Calendar.current.startOfDay(for: record.end)
            try await upsertMainSleep(record, date: sleepDate, userId: userId, on: db)
        }
    }
}
```

**Nap handling rules:**
- A user can have 0 or 1 main sleep and 0+ naps per day.
- Main sleep: `nap == false`. Determines the recovery score.
- Naps: `nap == true`. Tracked separately but contribute to total sleep and reduce sleep need.
- Dashboard shows main sleep duration. Naps shown as a separate line item: "Nap: 45 min".
- If multiple main sleep records exist for the same day (rare edge case: Whoop recalculates), keep the one with the latest `updated_at`.

**Data mapping — Sleep stages:**

| Whoop Stage Field | Tempo Field | Unit |
|-------------------|------------|------|
| `total_in_bed_time_milli` | `totalInBedDuration` | TimeInterval (seconds, divide by 1000) |
| `total_awake_time_milli` | `totalAwakeDuration` | TimeInterval |
| `total_light_sleep_time_milli` | `lightSleepDuration` | TimeInterval |
| `total_slow_wave_sleep_time_milli` | `deepSleepDuration` | TimeInterval |
| `total_rem_sleep_time_milli` | `remSleepDuration` | TimeInterval |
| `sleep_cycle_count` | `sleepCycles` | Int |
| `disturbance_count` | `disturbances` | Int |
| `respiratory_rate` | `respiratoryRate` | Double (breaths/min) |
| `sleep_performance_percentage` | `sleepPerformance` | Double (0-100) |
| `sleep_consistency_percentage` | `sleepConsistency` | Double (0-100) |
| `sleep_efficiency_percentage` | `sleepEfficiency` | Double (0-100) |
| `sleep_needed.baseline_milli` | `sleepNeededBaseline` | TimeInterval |
| `sleep_needed.need_from_sleep_debt_milli` | `sleepDebt` | TimeInterval |

**Multiple sleep entries per day — iOS model:**
```swift
@Model
class DailySleep {
    var date: Date                          // Calendar date (based on wake-up time)
    var mainSleep: SleepRecord?             // The primary overnight sleep
    var naps: [SleepRecord]                 // 0 or more naps

    var totalSleepDuration: TimeInterval {  // Main + all naps
        let mainDuration = mainSleep?.totalSleepDuration ?? 0
        let napDuration = naps.reduce(0) { $0 + $1.totalSleepDuration }
        return mainDuration + napDuration
    }

    var totalSleepHours: Double {
        totalSleepDuration / 3600.0
    }
}

@Model
class SleepRecord {
    var whoopSleepId: Int64
    var startTime: Date
    var endTime: Date
    var isNap: Bool
    var scoreState: String                  // "SCORED", "PENDING", "UNSCORABLE"

    // Stage durations (seconds)
    var totalInBedDuration: TimeInterval
    var totalAwakeDuration: TimeInterval
    var lightSleepDuration: TimeInterval
    var deepSleepDuration: TimeInterval
    var remSleepDuration: TimeInterval

    var totalSleepDuration: TimeInterval {
        lightSleepDuration + deepSleepDuration + remSleepDuration
    }

    // Scores
    var sleepPerformance: Double?
    var sleepConsistency: Double?
    var sleepEfficiency: Double?
    var respiratoryRate: Double?
    var sleepCycles: Int
    var disturbances: Int

    // Sleep need
    var sleepNeededBaseline: TimeInterval?
    var sleepDebt: TimeInterval?

    var updatedAt: Date
}
```

#### 1.3.3 Workouts

**Whoop endpoint:** `GET https://api.prod.whoop.com/developer/v1/activity/workout?start=YYYY-MM-DD&end=YYYY-MM-DD`

**Whoop response shape:**
```json
{
  "records": [
    {
      "id": 111222333,
      "user_id": 12345,
      "created_at": "2026-03-24T08:00:00.000Z",
      "updated_at": "2026-03-24T08:05:00.000Z",
      "start": "2026-03-24T06:30:00.000Z",
      "end": "2026-03-24T07:45:00.000Z",
      "timezone_offset": "+01:00",
      "sport_id": 1,
      "score_state": "SCORED",
      "score": {
        "strain": 12.5,
        "average_heart_rate": 142,
        "max_heart_rate": 178,
        "kilojoule": 2500.0,
        "percent_recorded": 100.0,
        "distance_meter": null,
        "altitude_gain_meter": null,
        "altitude_change_meter": null,
        "zone_duration": {
          "zone_zero_milli": 60000,
          "zone_one_milli": 300000,
          "zone_two_milli": 900000,
          "zone_three_milli": 1200000,
          "zone_four_milli": 900000,
          "zone_five_milli": 300000
        }
      },
      "source": "auto"
    }
  ],
  "next_token": null
}
```

**Webhook trigger:** `workout.updated`

**Polling frequency:** Not relied upon for workouts (webhooks are primary). Polling only as part of full sync: on app launch and daily reconciliation.

**Sport ID to Tempo workout type mapping:**

| Whoop sport_id | Whoop sport_name | Tempo WorkoutType | Notes |
|----------------|-----------------|-------------------|-------|
| 0 | Running | `.run` | |
| 1 | Cycling | `.cardio` | |
| 33 | Weightlifting | `.strength` | |
| 44 | Functional Fitness | `.strength` | CrossFit-style |
| 48 | Football (Soccer) | `.football` | Critical for Tempo's football scheduling |
| 52 | Walking | `.walk` | |
| 55 | HIIT | `.hiit` | |
| 56 | Yoga | `.mobility` | |
| 63 | Stretching | `.mobility` | |
| 71 | Swimming | `.cardio` | |
| 82 | Lacrosse | `.sport` | |
| Other | (Various) | `.other` | Log the sport_id for future mapping |

**Note:** Whoop has 80+ sport IDs. The mapping above covers the most common ones. Unknown sport_ids default to `.other` and the original `sport_id` is stored for later classification.

**Zone duration mapping:**
```swift
struct HeartRateZones: Codable {
    var zone0Duration: TimeInterval  // Below 50% max HR (rest)
    var zone1Duration: TimeInterval  // 50-60% (warm-up)
    var zone2Duration: TimeInterval  // 60-70% (fat burn)
    var zone3Duration: TimeInterval  // 70-80% (cardio)
    var zone4Duration: TimeInterval  // 80-90% (hard)
    var zone5Duration: TimeInterval  // 90-100% (max)

    init(from whoopZones: WhoopZoneDuration) {
        self.zone0Duration = TimeInterval(whoopZones.zoneZeroMilli) / 1000.0
        self.zone1Duration = TimeInterval(whoopZones.zoneOneMilli) / 1000.0
        self.zone2Duration = TimeInterval(whoopZones.zoneTwoMilli) / 1000.0
        self.zone3Duration = TimeInterval(whoopZones.zoneThreeMilli) / 1000.0
        self.zone4Duration = TimeInterval(whoopZones.zoneFourMilli) / 1000.0
        self.zone5Duration = TimeInterval(whoopZones.zoneFiveMilli) / 1000.0
    }
}
```

**Manually-added vs. auto-detected workouts:**
- `source: "auto"` — Whoop auto-detected the workout from heart rate data. These may be inaccurate (e.g., detecting a stressful meeting as a workout).
- `source: "user"` — User manually started/stopped the workout in the Whoop app. These are reliable.
- Tempo treats both equally but shows an "auto-detected" badge on auto-detected workouts.
- If a user logs the same workout in both Whoop and Tempo's RepForge module, deduplication matches by time overlap (>50% overlap = same workout).

#### 1.3.4 Cycles (Strain)

**Whoop endpoint:** `GET https://api.prod.whoop.com/developer/v1/cycle?start=YYYY-MM-DD&end=YYYY-MM-DD`

**Whoop response shape:**
```json
{
  "records": [
    {
      "id": 444555666,
      "user_id": 12345,
      "created_at": "2026-03-24T06:45:00.000Z",
      "updated_at": "2026-03-24T14:30:00.000Z",
      "start": "2026-03-24T06:45:00.000Z",
      "end": null,
      "timezone_offset": "+01:00",
      "score_state": "SCORED",
      "score": {
        "strain": 8.2,
        "kilojoule": 7500.0,
        "average_heart_rate": 72,
        "max_heart_rate": 182
      }
    }
  ],
  "next_token": null
}
```

**No webhook available for cycles.** Must poll.

**Polling frequency:**
- 6:00 AM - 10:00 PM: every 15 minutes (strain changes throughout the day as user is active)
- 10:00 PM - 6:00 AM: every 60 minutes (strain rarely changes overnight)

**Day boundary handling:**
Whoop "physiological cycles" do NOT align with calendar days. A Whoop cycle starts when the user wakes up and ends when they wake up the next day. For example:
- Cycle starts: March 24 at 7:00 AM (wake-up)
- Cycle ends: March 25 at 6:30 AM (next wake-up)

This means a Whoop cycle may span two calendar dates. Tempo maps cycles to calendar dates as follows:
- Use the cycle's `start` date as the Tempo calendar date.
- If a cycle has `end: null`, it is the current active cycle.
- The Dashboard always shows the current active cycle's strain, regardless of whether it technically started yesterday.

```swift
// Vapor backend — map Whoop cycle to Tempo date
func tempoDateForCycle(_ cycle: WhoopCycle) -> Date {
    // Use start time to determine the "Tempo day"
    // But if start is before 4 AM, it belongs to the previous day
    // (user woke up very early, cycle started at e.g., 4:30 AM previous night)
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: cycle.start)
    if hour < 4 {
        return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: cycle.start))!
    }
    return calendar.startOfDay(for: cycle.start)
}
```

---

### 1.4 Webhook Processing

#### Receiving and Verifying Webhooks

**Endpoint:** `POST /v1/webhooks/whoop`

```swift
// Vapor backend — WebhookController.swift
func handleWhoopWebhook(req: Request) async throws -> HTTPStatus {
    // 1. Read raw body for signature verification
    guard let rawBody = req.body.data else {
        throw Abort(.badRequest, reason: "Empty body")
    }
    let bodyString = String(buffer: rawBody)

    // 2. Extract headers
    guard let signature = req.headers.first(name: "X-Whoop-Signature") else {
        throw Abort(.badRequest, reason: "Missing X-Whoop-Signature header")
    }
    guard let timestampString = req.headers.first(name: "X-Whoop-Timestamp"),
          let timestamp = Double(timestampString) else {
        throw Abort(.badRequest, reason: "Missing or invalid X-Whoop-Timestamp header")
    }

    // 3. Replay attack prevention: reject if timestamp is >5 minutes old
    let webhookTime = Date(timeIntervalSince1970: timestamp)
    let fiveMinutesAgo = Date().addingTimeInterval(-300)
    guard webhookTime > fiveMinutesAgo else {
        req.logger.warning("Whoop webhook replay attempt: timestamp \(timestampString)")
        throw Abort(.unauthorized, reason: "Timestamp too old")
    }

    // 4. HMAC-SHA256 verification with timing-safe comparison
    let webhookSecret = Environment.get("WHOOP_WEBHOOK_SECRET")!
    let signatureInput = "\(timestampString).\(bodyString)"
    let expectedSignature = HMAC<SHA256>.authenticationCode(
        for: Data(signatureInput.utf8),
        using: SymmetricKey(data: Data(webhookSecret.utf8))
    )
    let expectedHex = expectedSignature.map { String(format: "%02x", $0) }.joined()

    // Timing-safe comparison
    guard timingSafeEqual(signature, expectedHex) else {
        req.logger.warning("Whoop webhook signature mismatch")
        throw Abort(.unauthorized, reason: "Invalid signature")
    }

    // 5. Parse the event
    let event = try req.content.decode(WhoopWebhookEvent.self)

    // 6. Idempotency check using trace_id
    let cacheKey = "whoop_webhook:\(event.traceId)"
    if let _ = try await req.redis.get(RedisKey(cacheKey), as: String.self).get() {
        // Already processed this webhook — return 200 to prevent retries
        req.logger.info("Duplicate webhook \(event.traceId), skipping")
        return .ok
    }
    // Mark as processing (TTL: 24 hours)
    try await req.redis.setex(RedisKey(cacheKey), to: "processing", expirationInSeconds: 86400).get()

    // 7. Look up Tempo user by Whoop user ID
    guard let integration = try await WhoopIntegration.query(on: req.db)
        .filter(\.$whoopUserId == event.userId)
        .first()
    else {
        req.logger.warning("Unknown Whoop user ID: \(event.userId)")
        throw Abort(.notFound, reason: "Unknown Whoop user ID")
    }

    // 8. Enqueue background processing job
    try await req.queue.dispatch(WhoopWebhookJob.self, .init(
        userId: integration.$user.id,
        eventType: event.type,
        resourceId: event.id,
        traceId: event.traceId
    ))

    // 9. Return 200 immediately (processing is async)
    return .ok
}

/// Timing-safe string comparison to prevent timing attacks on HMAC verification
private func timingSafeEqual(_ a: String, _ b: String) -> Bool {
    let aBytes = Array(a.utf8)
    let bBytes = Array(b.utf8)
    guard aBytes.count == bBytes.count else { return false }
    var result: UInt8 = 0
    for i in 0..<aBytes.count {
        result |= aBytes[i] ^ bBytes[i]
    }
    return result == 0
}
```

#### Background Webhook Processing Job

```swift
// Vapor backend — WhoopWebhookJob.swift
struct WhoopWebhookJob: AsyncJob {
    struct Payload: Codable {
        let userId: UUID
        let eventType: String
        let resourceId: Int64
        let traceId: String
    }

    func dequeue(_ context: QueueContext, _ payload: Payload) async throws {
        let db = context.application.db

        switch payload.eventType {
        case "recovery.updated":
            try await syncRecovery(userId: payload.userId, on: db)
            // Send morning recovery push notification
            try await sendRecoveryPush(userId: payload.userId, on: db, app: context.application)

        case "sleep.updated":
            try await syncSleep(userId: payload.userId, on: db)
            try await sendSilentPush(userId: payload.userId, type: "sleep_updated", app: context.application)

        case "workout.updated":
            try await syncWorkout(userId: payload.userId, workoutId: payload.resourceId, on: db)
            try await awardWorkoutXP(userId: payload.userId, workoutId: payload.resourceId, on: db)
            try await sendSilentPush(userId: payload.userId, type: "workout_updated", app: context.application)

        case "cycle.updated":
            try await syncCycle(userId: payload.userId, on: db)
            try await sendSilentPush(userId: payload.userId, type: "cycle_updated", app: context.application)

        case "body_measurement.updated":
            try await syncBodyMeasurement(userId: payload.userId, on: db)

        case let type where type.hasSuffix(".deleted"):
            let resourceType = type.replacingOccurrences(of: ".deleted", with: "")
            try await softDeleteResource(
                type: resourceType,
                resourceId: payload.resourceId,
                userId: payload.userId,
                on: db
            )

        default:
            context.logger.warning("Unhandled Whoop webhook type: \(payload.eventType)")
        }

        // Mark webhook as fully processed in Redis
        let cacheKey = "whoop_webhook:\(payload.traceId)"
        try await context.application.redis.setex(
            RedisKey(cacheKey), to: "completed", expirationInSeconds: 86400
        ).get()
    }

    func error(_ context: QueueContext, _ error: Error, _ payload: Payload) async throws {
        context.logger.error("Whoop webhook processing failed: \(error) for trace_id: \(payload.traceId)")
        // The job will be automatically retried by the queue system.
        // Mark as failed in Redis for observability.
        let cacheKey = "whoop_webhook:\(payload.traceId)"
        try await context.application.redis.setex(
            RedisKey(cacheKey), to: "failed", expirationInSeconds: 86400
        ).get()
    }
}
```

#### Reconciliation Cron Job

Webhooks can be lost (network issues, server downtime, Whoop outage). A daily cron job reconciles data.

```swift
// Vapor backend — WhoopReconciliationJob.swift
struct WhoopReconciliationJob: AsyncScheduledJob {
    // Runs daily at 3:00 AM UTC
    func run(context: QueueContext) async throws {
        let db = context.application.db

        // Get all active Whoop integrations
        let integrations = try await WhoopIntegration.query(on: db)
            .filter(\.$lastSyncStatus != "token_revoked")
            .all()

        for integration in integrations {
            do {
                let userId = integration.$user.id

                // Fetch last 3 days from Whoop API
                let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!

                try await syncRecovery(userId: userId, startDate: threeDaysAgo, on: db)
                try await syncSleep(userId: userId, startDate: threeDaysAgo, on: db)
                try await syncWorkouts(userId: userId, startDate: threeDaysAgo, on: db)
                try await syncCycles(userId: userId, startDate: threeDaysAgo, on: db)

                // Update last sync timestamp
                integration.lastSyncAt = Date()
                integration.lastSyncStatus = "success"
                try await integration.save(on: db)

                // Rate limit: wait 1 second between users to avoid hitting Whoop's rate limit
                try await Task.sleep(for: .seconds(1))
            } catch {
                context.logger.error("Reconciliation failed for user \(integration.$user.id): \(error)")
                integration.lastSyncStatus = "reconciliation_failed"
                try await integration.save(on: db)
            }
        }
    }
}
```

---

### 1.5 Whoop Data Edge Cases

#### User Removes Whoop During Sleep (Partial Sleep Data)

When the Whoop strap is removed during sleep, Whoop records the data up to the removal point. The sleep record will have:
- `score_state: "SCORED"` (or `"UNSCORABLE"` if too little data)
- Reduced `total_in_bed_time_milli`
- Missing or zero values for some sleep stages

**Tempo handling:**
- If `score_state == "UNSCORABLE"`: show "Incomplete sleep data — Whoop removed during the night." in the Sleep Detail view. Do NOT include this in recovery trend calculations.
- If `score_state == "SCORED"` but total sleep < 3 hours and no nap flag: flag as potentially partial. Show the data but with a warning badge.

#### Whoop Battery Dies (Gap in Data)

Whoop battery lasts ~5 days. When it dies:
- No new data is recorded until recharged.
- The cycle's `end` time is set to when the battery died.
- A new cycle starts when the device is back on.

**Tempo handling:**
- Detect gaps: if the latest cycle's `end` is non-null and older than 6 hours, and no new cycle has started, Whoop is likely dead/off.
- Dashboard shows: "Whoop data unavailable — last synced X hours ago."
- Recovery module shows last known recovery with a "stale" indicator.
- Training module falls back to "moderate" intensity recommendation when recovery data is stale (>12 hours old).

#### Recovery Score "PENDING"

After sleep ends, the recovery score takes 5-15 minutes to compute. During this window:
- `score_state: "PENDING"`
- `score` object is null

**Tempo handling:**
- Show a loading spinner in the recovery card with "Recovery score processing..."
- Poll every 2 minutes for up to 30 minutes.
- If still pending after 30 minutes, show "Recovery score unavailable" and use yesterday's recovery for training recommendations (with a note: "Using yesterday's recovery: XX%").

#### Day Cycle Doesn't Match Calendar Day

Covered in Section 1.3.4. Key rule: use the cycle's start time to determine the Tempo date, with the 4:00 AM cutoff.

#### Whoop Membership Expires (API Returns 403)

When a user's Whoop membership expires, API calls return HTTP 403 Forbidden.

**Tempo handling:**
1. Backend detects 403 from Whoop API.
2. Mark the integration as `membership_expired`.
3. Send push notification: "Your Whoop membership has expired. Tempo will use cached data until it's renewed."
4. Stop polling/webhook processing for this user.
5. Keep existing historical data accessible.
6. Check membership status daily (one lightweight API call) to detect re-activation.
7. When membership is renewed (API returns 200 again), resume normal sync and backfill missed data.

#### Multiple Whoop Devices

Extremely rare. Whoop's API is per-user, not per-device. If a user has multiple Whoop straps (e.g., upgraded from 4.0 to 5.0), only one is active at a time. The API returns data from whichever device is currently active.

**Tempo handling:** No special handling needed. The data is always attributed to the same Whoop user ID.

#### Whoop App Not Synced

Data flows: Whoop strap -> Whoop app (Bluetooth) -> Whoop API. If the user hasn't opened the Whoop app recently, strap data may not have synced to Whoop's servers.

**Tempo handling:**
- If data is unexpectedly stale (e.g., no recovery by 10 AM), show a notification: "Open your Whoop app to sync today's data."
- Detect staleness: if `last_recovery.created_at` is more than 4 hours before current time and it's after 9 AM, data is likely unsynced.

---

## 2. Apple HealthKit Integration

### 2.1 Authorization

#### Exact HKObjectType Sets

```swift
// HealthKitService.swift — iOS
import HealthKit

final class HealthKitService {
    private let healthStore = HKHealthStore()

    // Types we READ from HealthKit
    static let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = [
            // Activity
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.appleExerciseTime),

            // Heart
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),

            // Sleep
            HKCategoryType(.sleepAnalysis),

            // Nutrition (to read what Whoop/other apps write)
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),

            // Body
            HKQuantityType(.bodyMass),
            HKQuantityType(.height),

            // Workouts
            HKWorkoutType.workoutType(),
        ]

        // iOS 17+: workout route for GPS data
        if #available(iOS 17.0, *) {
            types.insert(HKSeriesType.workoutRoute())
        }

        return types
    }()

    // Types we WRITE to HealthKit
    static let writeTypes: Set<HKSampleType> = [
        // Workouts logged in RepForge
        HKWorkoutType.workoutType(),

        // Nutrition from NutriTrack
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.dietaryFiber),
        HKQuantityType(.dietarySugar),
        HKQuantityType(.dietarySodium),
    ]
}
```

#### Authorization Request Timing

Request HealthKit authorization during **onboarding Step 3** (after Sign in with Apple and before Whoop connection). This maximizes the chance of approval because the user is in a "setting up" mindset.

**CRITICAL: iPad and device compatibility.**
`HKHealthStore.isHealthDataAvailable()` returns `false` on iPad (all models, including iPad Pro). It also returns `false` on iPod touch and Apple TV. This check MUST be performed before any HealthKit call, including authorization requests. If HealthKit is unavailable, Tempo degrades gracefully: the Body quadrant shows "Health data unavailable on this device" and all HealthKit-dependent features (steps, heart rate, sleep from Apple Watch) are hidden. Whoop API data and NutriTrack data still work.

```swift
// HealthKitService.swift
func requestAuthorization() async throws -> HealthKitAuthResult {
    guard HKHealthStore.isHealthDataAvailable() else {
        return .unavailable  // iPad, iPod touch, etc.
    }

    do {
        try await healthStore.requestAuthorization(
            toShare: Self.writeTypes,
            read: Self.readTypes
        )

        // Check what was actually granted
        return await checkAuthorizationStatus()
    } catch {
        return .error(error)
    }
}

enum HealthKitAuthResult {
    case fullAccess                           // All types granted
    case partialAccess(denied: [String])      // Some types denied
    case denied                               // All types denied
    case unavailable                          // HealthKit not available on device (iPad, etc.)
    case error(Error)                         // System error
}
```

#### Checking Permissions on Every App Launch

**Critical edge case:** A user can revoke HealthKit permissions for Tempo at any time via Settings > Privacy & Security > Health > Tempo. When they do, the app receives NO notification or callback. Queries simply return empty results.

**Mitigation:** On every app launch (`scenePhase == .active`), re-check write authorization status and attempt a lightweight read query to detect if read permissions were revoked.

```swift
// HealthKitService.swift

/// Must be called on every app launch and every return to foreground.
/// Detects if the user revoked HealthKit permissions in Settings.
func verifyPermissionsOnLaunch() async {
    guard HKHealthStore.isHealthDataAvailable() else {
        authResult = .unavailable
        return
    }

    // Check write permissions (these ARE queryable)
    let workoutStatus = healthStore.authorizationStatus(for: HKWorkoutType.workoutType())
    if workoutStatus == .sharingDenied && previousWriteStatus == .sharingAuthorized {
        // User revoked write permission since last check
        Logger.healthKit.warning("HealthKit write permission revoked by user")
        authResult = .denied
    }
    previousWriteStatus = workoutStatus

    // Check read permissions by attempting a lightweight query
    // (read permission revocation is not directly queryable — Apple privacy design)
    do {
        let stepType = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: Date()),
            end: Date(),
            options: .strictStartDate
        )
        let _ = try await fetchSamples(type: stepType, predicate: predicate, limit: 1, sortDescriptors: [])
        // If we get here, read permission is likely still granted
        // (though zero results could also mean no data today)
    } catch {
        Logger.healthKit.warning("HealthKit read query failed on launch: \(error)")
    }
}
```

#### Handling Partial Authorization

HealthKit allows users to grant/deny each type individually. The user might grant steps but deny heart rate.

```swift
func checkAuthorizationStatus() async -> HealthKitAuthResult {
    var deniedTypes: [String] = []

    for type in Self.readTypes {
        let status = healthStore.authorizationStatus(for: type)
        // NOTE: HealthKit returns .notDetermined for read types even when denied,
        // because Apple doesn't want apps to know what the user denied.
        // For read types, we can only check .sharingAuthorized for write types.
        // For read types, we must ATTEMPT a query and check if data comes back.
    }

    // For write types, we CAN check authorization status
    for type in Self.writeTypes {
        let status = healthStore.authorizationStatus(for: type)
        if status == .sharingDenied {
            deniedTypes.append(type.identifier)
        }
    }

    if deniedTypes.isEmpty {
        return .fullAccess  // Note: read permissions are unknowable
    } else {
        return .partialAccess(denied: deniedTypes)
    }
}
```

**Critical HealthKit quirk:** You CANNOT programmatically determine if a READ type was denied. `authorizationStatus(for:)` returns `.notDetermined` for read types even after the user denied them. This is an Apple privacy design decision. The only way to detect denial is to perform a query and observe that zero results come back.

#### Re-requesting Denied Permissions

HealthKit does not allow programmatic re-requests. Once the user has responded to the authorization sheet, calling `requestAuthorization` again does nothing.

```swift
// Guide the user to Settings
func openHealthSettings() {
    if let url = URL(string: "x-apple-health://") {
        UIApplication.shared.open(url)
    }
}
```

**UI flow when data is missing due to denied permissions:**
1. If a specific data type returns no data for 7+ days, show an inline banner: "Steps data unavailable. Tap to enable in Health settings."
2. Tapping the banner opens the Health app where the user can toggle permissions.
3. Never nag more than once per day per data type.

---

### 2.2 Read Operations — Complete Implementation

#### 2.2.1 Steps

```swift
// HealthKitService.swift
func fetchTodaySteps() async throws -> Int {
    let stepType = HKQuantityType(.stepCount)
    let startOfDay = Calendar.current.startOfDay(for: Date())
    let predicate = HKQuery.predicateForSamples(
        withStart: startOfDay,
        end: Date(),
        options: .strictStartDate
    )

    let statistics = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKStatistics, Error>) in
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
            if let error = error {
                continuation.resume(throwing: error)
            } else if let statistics = statistics {
                continuation.resume(returning: statistics)
            } else {
                continuation.resume(throwing: HealthKitError.noData)
            }
        }
        healthStore.execute(query)
    }

    // HKStatisticsQuery automatically deduplicates across sources.
    // If both iPhone and Apple Watch report steps, it merges them
    // without double-counting (uses the highest priority source per time interval).
    let steps = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
    return Int(steps)
}
```

**Update frequency:** Every 15 minutes via background delivery (see Section 2.4).

**Data source handling:** `HKStatisticsQuery` with `.cumulativeSum` automatically handles multiple sources (iPhone pedometer + Apple Watch accelerometer). It applies Apple's source prioritization algorithm to avoid double-counting. No manual deduplication needed.

#### 2.2.2 Heart Rate

> **FEASIBILITY NOTE (Technical Feasibility Audit Section 1.5):** Live heart rate during workouts is ONLY available with Apple Watch paired. iPhones have no wrist HR sensor. Whoop writes HR to HealthKit only after workout processing (not real-time). For Whoop-only users, show "HR will appear after Whoop syncs" during workout, then populate retroactively from Whoop API data post-workout.

```swift
// HealthKitService.swift

/// Observe heart rate samples from HealthKit.
/// IMPORTANT: Live HR during workouts requires Apple Watch.
/// For Whoop-only users, HR data arrives post-workout via Whoop API sync.
/// UI must handle the "no live data" case gracefully.
func observeHeartRate(
    handler: @escaping (Double, Date) -> Void
) -> HKObserverQuery {
    let hrType = HKQuantityType(.heartRate)

    let query = HKAnchoredObjectQuery(
        type: hrType,
        predicate: nil,
        anchor: nil,
        limit: HKObjectQueryNoLimit
    ) { _, samples, _, _, error in
        guard let samples = samples as? [HKQuantitySample] else { return }
        for sample in samples {
            let bpm = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            handler(bpm, sample.startDate)
        }
    }

    query.updateHandler = { _, samples, _, _, error in
        guard let samples = samples as? [HKQuantitySample] else { return }
        for sample in samples {
            let bpm = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            handler(bpm, sample.startDate)
        }
    }

    healthStore.execute(query)
    return query
}

/// Fetch today's resting heart rate.
func fetchRestingHeartRate() async throws -> Double? {
    let rhrType = HKQuantityType(.restingHeartRate)
    let startOfDay = Calendar.current.startOfDay(for: Date())
    let predicate = HKQuery.predicateForSamples(
        withStart: startOfDay,
        end: Date(),
        options: .strictStartDate
    )

    let samples = try await fetchSamples(
        type: rhrType,
        predicate: predicate,
        limit: 1,
        sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
    )

    return samples.first.map {
        ($0 as! HKQuantitySample).quantity.doubleValue(for: .count().unitDivided(by: .minute()))
    }
}

/// Fetch daily average heart rate.
func fetchAverageHeartRate(for date: Date) async throws -> Double? {
    let hrType = HKQuantityType(.heartRate)
    let startOfDay = Calendar.current.startOfDay(for: date)
    let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
    let predicate = HKQuery.predicateForSamples(
        withStart: startOfDay,
        end: endOfDay,
        options: .strictStartDate
    )

    return try await withCheckedThrowingContinuation { continuation in
        let query = HKStatisticsQuery(
            quantityType: hrType,
            quantitySamplePredicate: predicate,
            options: .discreteAverage
        ) { _, statistics, error in
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                let avg = statistics?.averageQuantity()?.doubleValue(
                    for: .count().unitDivided(by: .minute())
                )
                continuation.resume(returning: avg)
            }
        }
        healthStore.execute(query)
    }
}
```

**Heart rate source priority:**

| Scenario | Preferred Source | Rationale |
|----------|----------------|-----------|
| Resting HR | Whoop API | Whoop measures RHR during sleep with a more accurate algorithm than Apple Watch |
| Workout HR | Apple Watch (if worn) or Whoop | Real-time during workout; Apple Watch's optical HR sensor on wrist is better positioned during exercise |
| Daily average | Merge all sources | Composite view is most accurate |
| HRV | Whoop API | Whoop's HRV measurement during sleep is more controlled and consistent |

**Implementation of source priority:**
```swift
/// Returns resting HR, preferring Whoop data over HealthKit.
func getRestingHeartRate() async -> Double? {
    // First check if we have Whoop recovery data for today
    if let whoopRecovery = await whoopService.todayRecovery,
       let rhr = whoopRecovery.restingHR {
        return rhr
    }
    // Fall back to HealthKit
    return try? await fetchRestingHeartRate()
}
```

#### 2.2.3 Sleep

```swift
// HealthKitService.swift

/// Fetch sleep analysis for a given date.
/// Returns categorized sleep stages (iOS 16+ required for stage detail).
func fetchSleep(for date: Date) async throws -> HealthKitSleepData? {
    let sleepType = HKCategoryType(.sleepAnalysis)

    // Sleep typically starts the evening before and ends on the target date.
    // Search from 6 PM yesterday to 12 PM today.
    let calendar = Calendar.current
    let sixPMYesterday = calendar.date(
        bySettingHour: 18, minute: 0, second: 0,
        of: calendar.date(byAdding: .day, value: -1, to: date)!
    )!
    let noonToday = calendar.date(
        bySettingHour: 12, minute: 0, second: 0,
        of: date
    )!

    let predicate = HKQuery.predicateForSamples(
        withStart: sixPMYesterday,
        end: noonToday,
        options: .strictStartDate
    )

    let samples = try await fetchSamples(
        type: sleepType,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
    ) as! [HKCategorySample]

    guard !samples.isEmpty else { return nil }

    // Group by source to handle overlapping samples from multiple apps
    let groupedBySource = Dictionary(grouping: samples) { $0.sourceRevision.source.bundleIdentifier }

    // Determine which source to use (priority: Whoop > Apple Watch > iPhone)
    let preferredSamples = selectPreferredSleepSource(groupedBySource)

    // Parse sleep stages (iOS 16+)
    var totalInBed: TimeInterval = 0
    var totalAsleep: TimeInterval = 0
    var coreSleep: TimeInterval = 0
    var deepSleep: TimeInterval = 0
    var remSleep: TimeInterval = 0
    var awake: TimeInterval = 0

    for sample in preferredSamples {
        let duration = sample.endDate.timeIntervalSince(sample.startDate)

        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .inBed:
            totalInBed += duration
        case .asleepUnspecified:
            totalAsleep += duration
        case .asleepCore:
            coreSleep += duration
            totalAsleep += duration
        case .asleepDeep:
            deepSleep += duration
            totalAsleep += duration
        case .asleepREM:
            remSleep += duration
            totalAsleep += duration
        case .awake:
            awake += duration
        default:
            break
        }
    }

    return HealthKitSleepData(
        totalInBed: totalInBed,
        totalAsleep: totalAsleep,
        coreSleep: coreSleep,
        deepSleep: deepSleep,
        remSleep: remSleep,
        awake: awake,
        bedTime: preferredSamples.first?.startDate,
        wakeTime: preferredSamples.last?.endDate,
        source: preferredSamples.first?.sourceRevision.source.name ?? "Unknown"
    )
}

/// Select sleep samples from the best available source.
/// Priority: Whoop > Apple Watch > iPhone > Other
private func selectPreferredSleepSource(
    _ grouped: [String?: [HKCategorySample]]
) -> [HKCategorySample] {
    let priorityOrder = [
        "com.whoop.Diamond",        // Whoop app bundle ID
        "com.apple.health.watch",   // Apple Watch
        "com.apple.health",         // iPhone
    ]

    for bundleId in priorityOrder {
        if let samples = grouped[bundleId], !samples.isEmpty {
            return samples
        }
    }

    // Fall back to whichever source has the most data
    return grouped.values.max(by: { $0.count < $1.count }) ?? []
}
```

**Sleep data deduplication — overlapping samples from multiple sources:**

When both Whoop and Apple Watch report sleep, HealthKit contains overlapping samples from both sources for the same time period. Without deduplication, summing all samples would double-count sleep duration.

**Deduplication strategy:**
1. Group all sleep samples by `sourceRevision.source.bundleIdentifier`.
2. Select ONE source using the priority order: Whoop > Apple Watch > iPhone > Other (implemented in `selectPreferredSleepSource()`).
3. Use ONLY samples from the selected source. Never merge samples across sources for the same night.
4. If the preferred source has incomplete data (e.g., Whoop removed at 3 AM), do NOT fall back to a secondary source for the remaining hours — that creates inconsistent stage data. Instead, report the partial data with a warning.

**Why not merge across sources:** Whoop and Apple Watch categorize sleep stages differently. Whoop uses its own ML model for light/deep/REM classification. Apple Watch uses a different model. Merging them would create contradictory stage data (e.g., Whoop says REM while Apple Watch says deep for the same time window). Pick one source and be consistent.

**Whoop sleep via HealthKit vs. Whoop API — Reconciliation Strategy:**

Whoop writes basic sleep data to HealthKit (in bed, asleep, awake stages). However, the Whoop API provides much richer data (sleep performance %, efficiency %, respiratory rate, disturbance count, sleep need calculations).

**Rule:** Use Whoop API for all sleep metrics when available. Only fall back to HealthKit sleep data when:
1. Whoop is not connected.
2. Whoop data is stale (>12 hours old) but HealthKit has fresh data.
3. The user only wears Apple Watch for sleep (no Whoop).

Never combine Whoop API sleep data with HealthKit sleep data for the same night — pick one source.

#### 2.2.4 Workouts

```swift
// HealthKitService.swift

/// Fetch workouts for a date range.
func fetchWorkouts(
    startDate: Date,
    endDate: Date
) async throws -> [HealthKitWorkout] {
    let workoutType = HKWorkoutType.workoutType()
    let predicate = HKQuery.predicateForSamples(
        withStart: startDate,
        end: endDate,
        options: .strictStartDate
    )

    let samples = try await fetchSamples(
        type: workoutType,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
    ) as! [HKWorkout]

    return samples.map { workout in
        HealthKitWorkout(
            id: workout.uuid,
            activityType: workout.workoutActivityType,
            tempoType: mapActivityType(workout.workoutActivityType),
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            totalEnergyBurned: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
            totalDistance: workout.totalDistance?.doubleValue(for: .meter()),
            source: workout.sourceRevision.source.name,
            sourceBundle: workout.sourceRevision.source.bundleIdentifier,
            isWhoopSource: workout.sourceRevision.source.bundleIdentifier == "com.whoop.Diamond"
        )
    }
}

/// Map HKWorkoutActivityType to Tempo's WorkoutType.
func mapActivityType(_ activityType: HKWorkoutActivityType) -> WorkoutType {
    switch activityType {
    // Strength
    case .traditionalStrengthTraining, .functionalStrengthTraining:
        return .strength

    // Running
    case .running:
        return .run

    // Football (Soccer)
    case .soccer:
        return .football

    // Cardio
    case .cycling, .swimming, .rowing, .elliptical, .stairClimbing:
        return .cardio

    // HIIT
    case .highIntensityIntervalTraining, .crossTraining:
        return .hiit

    // Mobility
    case .yoga, .flexibility, .pilates, .mindAndBody:
        return .mobility

    // Walking
    case .walking, .hiking:
        return .walk

    // Other sports
    case .basketball, .tennis, .tableTennis, .badminton, .rugby,
         .volleyball, .handball, .martialArts, .boxing:
        return .sport

    default:
        return .other
    }
}
```

**Reading heart rate during a specific workout:**
```swift
/// Fetch heart rate samples recorded during a specific workout.
func fetchHeartRateDuringWorkout(_ workout: HKWorkout) async throws -> [HeartRateSample] {
    let hrType = HKQuantityType(.heartRate)
    let predicate = HKQuery.predicateForSamples(
        withStart: workout.startDate,
        end: workout.endDate,
        options: .strictStartDate
    )

    let samples = try await fetchSamples(
        type: hrType,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
    ) as! [HKQuantitySample]

    return samples.map { sample in
        HeartRateSample(
            bpm: sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())),
            timestamp: sample.startDate
        )
    }
}
```

**Reading workout route (GPS):**
```swift
/// Fetch GPS route for a workout (available for outdoor runs, cycles, etc.).
@available(iOS 17.0, *)
func fetchWorkoutRoute(_ workout: HKWorkout) async throws -> [CLLocation]? {
    let routeType = HKSeriesType.workoutRoute()
    let predicate = HKQuery.predicateForObjects(from: workout)

    let routes = try await fetchSamples(
        type: routeType,
        predicate: predicate,
        limit: 1,
        sortDescriptors: []
    ) as? [HKWorkoutRoute]

    guard let route = routes?.first else { return nil }

    return try await withCheckedThrowingContinuation { continuation in
        var allLocations: [CLLocation] = []

        let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }
            if let locations = locations {
                allLocations.append(contentsOf: locations)
            }
            if done {
                continuation.resume(returning: allLocations)
            }
        }
        healthStore.execute(query)
    }
}
```

#### 2.2.5 Active Energy

```swift
// HealthKitService.swift

/// Fetch today's total active energy burned.
func fetchTodayActiveEnergy() async throws -> Double {
    let energyType = HKQuantityType(.activeEnergyBurned)
    let startOfDay = Calendar.current.startOfDay(for: Date())
    let predicate = HKQuery.predicateForSamples(
        withStart: startOfDay,
        end: Date(),
        options: .strictStartDate
    )

    return try await withCheckedThrowingContinuation { continuation in
        let query = HKStatisticsQuery(
            quantityType: energyType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                let kcal = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: kcal)
            }
        }
        healthStore.execute(query)
    }
}
```

---

### 2.3 Write Operations

#### 2.3.1 Saving RepForge Workouts to HealthKit

```swift
// HealthKitService.swift

/// Save a completed RepForge workout to HealthKit.
func saveWorkout(
    type: WorkoutType,
    startDate: Date,
    endDate: Date,
    totalEnergyBurned: Double?,  // kcal, from HR-based estimation
    heartRateSamples: [HeartRateSample]?
) async throws {
    guard healthStore.authorizationStatus(for: HKWorkoutType.workoutType()) == .sharingAuthorized else {
        throw HealthKitError.writeNotAuthorized
    }

    let configuration = HKWorkoutConfiguration()
    configuration.activityType = mapToHKActivityType(type)
    configuration.locationType = .indoor  // RepForge workouts are typically indoor

    let builder = HKWorkoutBuilder(
        healthStore: healthStore,
        configuration: configuration,
        device: .local()
    )

    try await builder.beginCollection(at: startDate)

    // Add energy burned if available
    if let energy = totalEnergyBurned {
        let energySample = HKQuantitySample(
            type: HKQuantityType(.activeEnergyBurned),
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy),
            start: startDate,
            end: endDate
        )
        try await builder.addSamples([energySample])
    }

    // Add heart rate samples if captured
    if let hrSamples = heartRateSamples {
        let hkSamples = hrSamples.map { sample in
            HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(
                    unit: .count().unitDivided(by: .minute()),
                    doubleValue: sample.bpm
                ),
                start: sample.timestamp,
                end: sample.timestamp
            )
        }
        try await builder.addSamples(hkSamples)
    }

    try await builder.endCollection(at: endDate)
    try await builder.finishWorkout()
}

private func mapToHKActivityType(_ type: WorkoutType) -> HKWorkoutActivityType {
    switch type {
    case .push, .pull, .legs, .upper, .lower, .fullBody, .strength:
        return .traditionalStrengthTraining
    case .run:
        return .running
    case .football:
        return .soccer
    case .hiit, .conditioning:
        return .highIntensityIntervalTraining
    case .mobility:
        return .flexibility
    case .cardio:
        return .cycling  // default; could be more specific
    case .sprint:
        return .running
    case .walk:
        return .walking
    case .sport:
        return .other
    case .rest, .other:
        return .other
    }
}
```

#### 2.3.2 Writing NutriTrack Nutrition to HealthKit

```swift
// HealthKitService.swift

/// Write a meal's nutrition data to HealthKit as an HKCorrelation.
func saveMealNutrition(
    mealName: String,      // "Breakfast", "Lunch", "Dinner", "Snack"
    calories: Double,       // kcal
    proteinG: Double,
    carbsG: Double,
    fatG: Double,
    fiberG: Double?,
    sugarG: Double?,
    mealTime: Date
) async throws {
    guard healthStore.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed)) == .sharingAuthorized else {
        return  // Silently skip if not authorized — nutrition write is optional
    }

    var samples: [HKQuantitySample] = []

    // Calories
    samples.append(HKQuantitySample(
        type: HKQuantityType(.dietaryEnergyConsumed),
        quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
        start: mealTime,
        end: mealTime,
        metadata: [HKMetadataKeyFoodType: mealName]
    ))

    // Protein
    samples.append(HKQuantitySample(
        type: HKQuantityType(.dietaryProtein),
        quantity: HKQuantity(unit: .gram(), doubleValue: proteinG),
        start: mealTime,
        end: mealTime
    ))

    // Carbs
    samples.append(HKQuantitySample(
        type: HKQuantityType(.dietaryCarbohydrates),
        quantity: HKQuantity(unit: .gram(), doubleValue: carbsG),
        start: mealTime,
        end: mealTime
    ))

    // Fat
    samples.append(HKQuantitySample(
        type: HKQuantityType(.dietaryFatTotal),
        quantity: HKQuantity(unit: .gram(), doubleValue: fatG),
        start: mealTime,
        end: mealTime
    ))

    // Optional: Fiber
    if let fiber = fiberG {
        samples.append(HKQuantitySample(
            type: HKQuantityType(.dietaryFiber),
            quantity: HKQuantity(unit: .gram(), doubleValue: fiber),
            start: mealTime,
            end: mealTime
        ))
    }

    // Optional: Sugar
    if let sugar = sugarG {
        samples.append(HKQuantitySample(
            type: HKQuantityType(.dietarySugar),
            quantity: HKQuantity(unit: .gram(), doubleValue: sugar),
            start: mealTime,
            end: mealTime
        ))
    }

    // Create a correlation grouping all nutrients for this meal
    let correlationType = HKCorrelationType(.food)
    let correlation = HKCorrelation(
        type: correlationType,
        start: mealTime,
        end: mealTime,
        objects: Set(samples),
        metadata: [
            HKMetadataKeyFoodType: mealName,
            "TempoSource": "NutriTrack"  // Custom metadata to identify our writes
        ]
    )

    try await healthStore.save(correlation)
}
```

**Deduplication:** Before writing meal nutrition, check if we already wrote data for this meal (by querying for our custom metadata key `"TempoSource": "NutriTrack"` at the same timestamp). If found, delete the old correlation and write the new one (handles meal edits in NutriTrack).

---

### 2.4 Background Delivery

```swift
// HealthKitService.swift

/// Enable background delivery for key health data types.
/// Must be called once during app initialization.
func enableBackgroundDelivery() {
    let typesAndFrequencies: [(HKObjectType, HKUpdateFrequency)] = [
        (HKQuantityType(.stepCount), .hourly),
        (HKWorkoutType.workoutType(), .immediate),
        (HKCategoryType(.sleepAnalysis), .immediate),
        (HKQuantityType(.activeEnergyBurned), .hourly),
    ]

    for (type, frequency) in typesAndFrequencies {
        healthStore.enableBackgroundDelivery(for: type, frequency: frequency) { success, error in
            if let error = error {
                Logger.healthKit.error("Failed to enable background delivery for \(type.identifier): \(error)")
            } else if success {
                Logger.healthKit.info("Background delivery enabled for \(type.identifier)")
            }
        }
    }
}

/// Set up observer queries that trigger when HealthKit data changes.
/// These persist across app launches when background delivery is enabled.
///
/// CRITICAL: Every HKObserverQuery callback MUST call the `completionHandler`
/// parameter. If the completionHandler is never called, HealthKit will stop
/// delivering background updates for that data type permanently (until the app
/// is reinstalled). This is the #1 cause of "background delivery stopped working"
/// bugs. The completionHandler MUST be called even if an error occurs, even if
/// the fetch fails, even if the task is cancelled. Use `defer` to guarantee it.
func setupObserverQueries() {
    // Steps observer
    let stepsQuery = HKObserverQuery(
        sampleType: HKQuantityType(.stepCount),
        predicate: nil
    ) { [weak self] _, completionHandler, error in
        guard error == nil else {
            completionHandler()
            return
        }

        Task {
            do {
                let steps = try await self?.fetchTodaySteps() ?? 0
                await self?.updateSnapshot(steps: steps)
            } catch {
                Logger.healthKit.error("Background step fetch failed: \(error)")
            }
            completionHandler()  // MUST call to allow next delivery
        }
    }
    healthStore.execute(stepsQuery)

    // Workout observer (immediate delivery)
    let workoutQuery = HKObserverQuery(
        sampleType: HKWorkoutType.workoutType(),
        predicate: nil
    ) { [weak self] _, completionHandler, error in
        guard error == nil else {
            completionHandler()
            return
        }

        Task {
            do {
                let today = Calendar.current.startOfDay(for: Date())
                let workouts = try await self?.fetchWorkouts(startDate: today, endDate: Date()) ?? []
                await self?.processNewWorkouts(workouts)
            } catch {
                Logger.healthKit.error("Background workout fetch failed: \(error)")
            }
            completionHandler()
        }
    }
    healthStore.execute(workoutQuery)

    // Sleep observer (immediate delivery)
    let sleepQuery = HKObserverQuery(
        sampleType: HKCategoryType(.sleepAnalysis),
        predicate: nil
    ) { [weak self] _, completionHandler, error in
        guard error == nil else {
            completionHandler()
            return
        }

        Task {
            do {
                let sleep = try await self?.fetchSleep(for: Date())
                await self?.updateSnapshot(sleep: sleep)
            } catch {
                Logger.healthKit.error("Background sleep fetch failed: \(error)")
            }
            completionHandler()
        }
    }
    healthStore.execute(sleepQuery)
}
```

**Background processing with BGAppRefreshTask:**
```swift
// TempoApp.swift
import BackgroundTasks

@main
struct TempoApp: App {
    init() {
        registerBackgroundTasks()
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.tempo.healthkit-sync",
            using: nil
        ) { task in
            handleHealthKitSync(task: task as! BGAppRefreshTask)
        }
    }

    private func scheduleHealthKitSync() {
        let request = BGAppRefreshTaskRequest(identifier: "com.tempo.healthkit-sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger.background.error("Failed to schedule HealthKit sync: \(error)")
        }
    }
}

func handleHealthKitSync(task: BGAppRefreshTask) {
    // Create a task to batch-process all HealthKit updates
    let syncTask = Task {
        let healthKitService = HealthKitService.shared

        do {
            // Batch multiple queries in one background session
            async let steps = healthKitService.fetchTodaySteps()
            async let energy = healthKitService.fetchTodayActiveEnergy()
            async let sleep = healthKitService.fetchSleep(for: Date())

            let (stepsResult, energyResult, sleepResult) = try await (steps, energy, sleep)

            // Update local SwiftData snapshot
            await healthKitService.updateDailySnapshot(
                steps: stepsResult,
                activeEnergy: energyResult,
                sleep: sleepResult
            )
        } catch {
            Logger.background.error("HealthKit background sync failed: \(error)")
        }
    }

    task.expirationHandler = {
        syncTask.cancel()
    }

    Task {
        _ = await syncTask.result
        task.setTaskCompleted(success: true)
        // Schedule next sync
        scheduleHealthKitSync()
    }
}
```

**Battery optimization:** All HealthKit background queries are batched into a single background session. The observer query completion handler is called as quickly as possible to minimize background runtime. Heavy processing (trend calculations, AI insights) is deferred to the next foreground session.

---

### 2.5 HealthKit + Whoop Data Reconciliation

#### Core Principle

Whoop writes some data to HealthKit (heart rate, HRV, sleep, workouts). Tempo also reads directly from the Whoop API. To avoid confusion and double-counting:

**Use Whoop API for Whoop-specific data:**
- Recovery score (only available via API)
- Strain score (only available via API)
- Sleep performance/efficiency/consistency (richer via API)
- HRV RMSSD (Whoop's sleep-measured HRV is more reliable)
- Resting heart rate (Whoop's sleep-measured RHR is more accurate)

**Use HealthKit for Apple-specific data:**
- Steps (Apple Watch/iPhone pedometer)
- Active energy burned (Apple Watch calorie estimation)
- Apple Exercise Time (Apple's exercise ring metric)
- Distance walked/run

**Use preferred source for overlapping data:**
- Sleep: Whoop API preferred, HealthKit fallback
- Workouts: Whoop API for Whoop-tracked workouts, HealthKit for Apple Watch workouts, Local for RepForge workouts
- Heart rate: Whoop API for resting, HealthKit for real-time during exercise

#### Identifying Whoop as a HealthKit Source

```swift
/// Check if a HealthKit sample came from the Whoop app.
func isWhoopSource(_ sample: HKSample) -> Bool {
    return sample.sourceRevision.source.bundleIdentifier == "com.whoop.Diamond"
}

/// When reading workouts from HealthKit, filter OUT Whoop-sourced workouts
/// (since we already have those via the Whoop API with richer data).
func fetchNonWhoopWorkouts(startDate: Date, endDate: Date) async throws -> [HealthKitWorkout] {
    let allWorkouts = try await fetchWorkouts(startDate: startDate, endDate: endDate)
    return allWorkouts.filter { !$0.isWhoopSource }
}
```

---

## 3. NutriTrack Integration

### 3.1 Connection Flow

NutriTrack is Nicola's self-hosted Flask app. It uses a simple PIN-based authentication. The Tempo backend proxies all requests to keep the NutriTrack server URL and PIN out of the iOS app's traffic.

#### Step-by-Step Connection

**Step 1: User enters NutriTrack server URL**

The onboarding UI (`NutriTrackConnectView`) presents a text field for the NutriTrack server URL. Pre-populated with a hint: `https://nutritrack.example.com`.

```swift
// NutriTrackConnectView.swift
struct NutriTrackConnectView: View {
    @State private var serverURL = ""
    @State private var pin = ""
    @State private var isConnecting = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("Connect NutriTrack")
                .font(.title2.bold())

            Text("Enter your NutriTrack server address and PIN.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("https://nutritrack.example.com", text: $serverURL)
                .keyboardType(.URL)
                .textContentType(.URL)
                .autocapitalization(.none)
                .textFieldStyle(.roundedBorder)

            SecureField("6-digit PIN", text: $pin)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: connect) {
                if isConnecting {
                    ProgressView()
                } else {
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(serverURL.isEmpty || pin.count < 4 || isConnecting)
        }
        .padding()
    }

    private func connect() {
        isConnecting = true
        error = nil

        Task {
            do {
                try await nutriTrackService.connect(
                    serverURL: serverURL,
                    pin: pin
                )
                // Success — navigate to next onboarding step
            } catch NutriTrackError.invalidPIN {
                error = "Invalid PIN. Check your NutriTrack settings."
            } catch NutriTrackError.serverUnreachable {
                error = "Cannot reach NutriTrack server. Check the URL and ensure the server is running."
            } catch NutriTrackError.timeout {
                error = "Connection timed out. Check your network and server."
            } catch {
                error = "Connection failed: \(error.localizedDescription)"
            }
            isConnecting = false
        }
    }
}
```

**Step 2: User enters PIN**

The PIN is entered in the same form (see above). PINs are 4-8 digits.

**Step 3: Tempo backend verifies**

```swift
// NutriTrackService.swift — iOS side
@Observable
final class NutriTrackService {
    private let apiClient: APIClient
    private(set) var isConnected = false
    private(set) var lastSyncDate: Date?

    /// Connect to NutriTrack via the Tempo backend.
    func connect(serverURL: String, pin: String) async throws {
        // Validate URL format
        guard let url = URL(string: serverURL),
              url.scheme == "https" || url.scheme == "http" else {
            throw NutriTrackError.invalidURL
        }

        // Send to backend for verification
        let response = try await apiClient.post(
            "/v1/integrations/nutritrack/connect",
            body: NutriTrackConnectRequest(
                baseURL: serverURL,
                pin: pin
            ),
            response: NutriTrackConnectResponse.self
        )

        isConnected = true
    }
}
```

**Backend flow:**
1. Receives `base_url` and `pin` from iOS.
2. Validates URL format (must be HTTPS in production, HTTP allowed in development).
3. Tests connectivity: `POST {base_url}/api/pin/verify` with `{"pin": "<pin>"}`.
4. NutriTrack responds with `200 OK` if valid, `401 Unauthorized` if invalid.
5. On success: encrypt and store `base_url` and `pin` in the `nutritrack_integrations` table.
6. On failure: return appropriate error to iOS.

**Step 3b: Backend validates URL before storing**

Before storing the NutriTrack URL, the backend performs validation:
```swift
// Vapor backend — NutriTrackService.swift
func validateNutriTrackURL(_ urlString: String) throws -> URL {
    guard let url = URL(string: urlString) else {
        throw NutriTrackError.invalidURL
    }

    // Scheme validation
    guard url.scheme == "https" || (Environment.get("ENVIRONMENT") == "development" && url.scheme == "http") else {
        throw NutriTrackError.httpsRequired
    }

    // Reject localhost/loopback in production
    let host = url.host?.lowercased() ?? ""
    let localhostPatterns = ["localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"]
    if Environment.get("ENVIRONMENT") != "development" && localhostPatterns.contains(where: { host == $0 }) {
        throw NutriTrackError.localhostNotAllowed
    }

    // Reject private IP ranges in production (10.x.x.x, 192.168.x.x, 172.16-31.x.x)
    // These are unreachable from the Tempo backend server
    if Environment.get("ENVIRONMENT") != "development" {
        if host.hasPrefix("10.") || host.hasPrefix("192.168.") ||
           (host.hasPrefix("172.") && isPrivate172(host)) {
            throw NutriTrackError.privateIPNotAllowed
        }
    }

    return url
}

/// Health check: verify NutriTrack server is reachable and responding correctly.
func healthCheck(url: URL) async throws {
    let response = try await httpClient.get("\(url)/api/health", timeout: .seconds(10))
    guard response.status == .ok else {
        throw NutriTrackError.healthCheckFailed(status: response.status)
    }
}
```

**Localhost / local development note:**
- The iOS app communicates with the Tempo backend, NOT directly with NutriTrack. So even if NutriTrack runs on `localhost:5000` on Nicola's laptop, the iOS app does not need to reach localhost.
- However, the Tempo BACKEND must be able to reach the NutriTrack server. If both the backend and NutriTrack run on the same machine (development), `localhost` works. In production, NutriTrack must be on a publicly accessible URL or VPN-accessible address.
- For local development with the iOS Simulator: the simulator can reach the Mac's localhost. But a physical iPhone cannot reach the Mac's localhost without extra configuration (use the Mac's LAN IP instead, e.g., `http://192.168.1.100:5000`).

**Step 4: Backend stores URL + credentials securely**

The backend encrypts the NutriTrack PIN using AES-256-GCM (same key management as Whoop tokens, different key derivation info: `"tempo-nutritrack-encryption"`). The base URL is stored in plaintext (not sensitive).

**Step 5: Backend proxies all subsequent requests**

All NutriTrack data flows through the backend proxy:
```
iOS → Tempo Backend (/v1/nutritrack/*) → NutriTrack Flask Server (/api/*)
```

The backend adds a session cookie (obtained during PIN verification) to each proxied request.

---

### 3.2 Data Sync Strategy

#### Sync on App Launch

When the app enters foreground, fetch current day data:
```swift
// NutriTrackService.swift
func syncOnLaunch() async {
    do {
        let today = try await fetchToday()
        await updateLocalCache(today)
        lastSyncDate = Date()
    } catch {
        Logger.nutriTrack.error("Launch sync failed: \(error)")
        // Show stale data from local cache
    }
}
```

#### Periodic Sync (Every 15 Minutes)

```swift
// SyncService.swift
func startPeriodicNutriTrackSync() {
    nutriTrackSyncTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
        Task {
            await self?.nutriTrackService.syncOnLaunch()
        }
    }
}
```

#### Background Sync — Detecting NutriTrack Events

NutriTrack does NOT have webhooks. Tempo must poll.

**Detection strategy for meal logging:**
1. Every 15 minutes, compare the `meals_logged` count from `/api/today` with the cached value.
2. If the count increased, a new meal was logged. Trigger downstream updates (HealthKit write, XP event, Dashboard refresh).
3. If a meal's status changed (planned -> eaten, planned -> skipped), update the Accountability module.

#### Full Historical Sync

On first connection and on-demand:
```swift
// NutriTrackService.swift
func fullSync() async throws {
    // NutriTrack's /api/export returns all data
    let exportData = try await apiClient.get(
        "/v1/nutritrack/export",
        response: NutriTrackExportResponse.self
    )

    // Process and cache locally
    // Limited to last 90 days to avoid overwhelming the device
    let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
    let recentData = exportData.days.filter { $0.date >= ninetyDaysAgo }

    for day in recentData {
        await cacheDay(day)
    }
}
```

---

### 3.3 Endpoint Mapping

Every NutriTrack endpoint used by Tempo, mapped to its Tempo use case.

#### Dashboard — Fuel Quadrant

**Tempo endpoint:** `GET /v1/nutritrack/today`
**NutriTrack endpoint:** `GET /api/today`
**Cache:** 2 minutes TTL (Redis)

**Data extracted for Dashboard:**

| NutriTrack Field | Tempo Use | Dashboard Display |
|-----------------|-----------|-------------------|
| `calories_consumed` | FuelQuadrant calories ring | "1850 / 2400 kcal" |
| `target_calories` | FuelQuadrant target | Ring fill percentage |
| `protein_g` | Macro breakdown | "145g protein" |
| `carbs_g` | Macro breakdown | "220g carbs" |
| `fat_g` | Macro breakdown | "62g fat" |
| `meals` array | Meal timeline | Meal cards with status |
| `meals[].status` | Accountability meal tracking | "Eaten", "Planned", "Skipped" |

#### Recovery Module — Nutrition for Recovery

**Tempo endpoint:** `GET /v1/nutritrack/macros`
**NutriTrack endpoint:** `GET /api/today/macro-balance`
**Cache:** 2 minutes TTL

**Data extracted:**
- Current protein intake vs. target (recovery requires adequate protein)
- Calorie balance (surplus/deficit affects recovery)
- Meal timing relative to training

#### Accountability Module — Meal Compliance

**Tempo endpoint:** `GET /v1/nutritrack/today`
**NutriTrack endpoint:** `GET /api/today`

**Data extracted:**
- Number of meals eaten vs. planned
- Specific meal statuses: which meals are "eaten", "planned", "skipped", "delayed"
- Used to auto-complete the "Eat 3 meals" non-negotiable

**Auto-tracking logic:**
```swift
// AccountabilityService.swift
func checkMealNonNegotiable() async {
    guard let nutriData = await nutriTrackService.cachedToday else { return }

    let mealsEaten = nutriData.meals.filter { $0.status == "eaten" }.count
    let mealTarget = 3  // configurable

    if let mealNN = todayAccountability.nonNegotiables.first(where: { $0.type == .meals }) {
        mealNN.currentValue = Double(mealsEaten)
        mealNN.isCompleted = mealsEaten >= mealTarget
        if mealNN.isCompleted && mealNN.completedAt == nil {
            mealNN.completedAt = Date()
        }
    }
}
```

#### Training Module — Training Readiness

**Tempo endpoint:** `GET /v1/nutritrack/training-readiness`
**NutriTrack endpoint:** `GET /api/intelligence/training/readiness`
**Cache:** 5 minutes TTL

**Data extracted:**
- Training readiness recommendation from NutriTrack's intelligence engine
- Pre-workout nutrition advice
- Post-workout nutrition window

#### Weekly Report

**Tempo endpoint:** `GET /v1/nutritrack/week/:date`
**NutriTrack endpoint:** `GET /api/week/:date`
**Cache:** 10 minutes TTL

**Data extracted:**
- Weekly calorie adherence percentage
- Average macro breakdown
- Meal compliance rate (eaten/total)
- Best/worst days

#### Arena — Streaks

**Tempo endpoint:** `GET /v1/nutritrack/streaks`
**NutriTrack endpoint:** `GET /api/progress/streaks`
**Cache:** 10 minutes TTL

**Data extracted:**
- Current meal logging streak
- Longest streak
- Used for XP calculation (streak milestones)

---

### 3.4 Error Handling

#### NutriTrack Server Down

```swift
// NutriTrackService.swift

/// Fetch today's NutriTrack data with graceful degradation.
func fetchToday() async throws -> NutriTrackToday {
    do {
        let response = try await apiClient.get(
            "/v1/nutritrack/today",
            response: TempoAPIResponse<NutriTrackToday>.self,
            timeout: 10
        )

        // Cache the successful response
        await cacheToday(response.data)
        lastSyncDate = Date()
        syncError = nil

        return response.data
    } catch let error as APIError where error.isServerUnreachable {
        // NutriTrack server is down — use cached data
        syncError = .serverDown(since: lastSyncDate)

        if let cached = await getCachedToday() {
            return cached  // Return stale data
        } else {
            throw NutriTrackError.serverUnreachable
        }
    }
}
```

**UI for stale data:**
When showing cached NutriTrack data, the Fuel quadrant displays a subtle indicator:
```swift
// FuelQuadrantView.swift
if let lastSync = nutriTrackService.lastSyncDate {
    let minutesAgo = Int(Date().timeIntervalSince(lastSync) / 60)
    if minutesAgo > 15 {
        Label("Last synced \(minutesAgo) min ago", systemImage: "clock.arrow.circlepath")
            .font(.caption2)
            .foregroundStyle(.orange)
    }
}
```

#### PIN / Session Expired — Automatic Re-Authentication

NutriTrack session cookies have a configurable TTL (default: 72 hours, but this is set on the NutriTrack server side via `SESSION_LIFETIME_HOURS` and can be changed by the user). The Tempo backend must NOT assume any fixed expiry duration. Instead, it detects session expiry reactively via HTTP 401 responses and re-authenticates automatically.

**Auto-re-auth flow (transparent to the iOS app):**
```swift
// Vapor backend — NutriTrackProxy.swift

/// Proxy a request to NutriTrack with automatic re-authentication on 401.
func proxyWithReauth(
    method: HTTPMethod,
    path: String,
    body: ByteBuffer?,
    for userId: UUID,
    on db: Database
) async throws -> ClientResponse {
    // Attempt the request with current session cookie
    var response = try await proxyRequest(method: method, path: path, body: body, for: userId, on: db)

    if response.status == .unauthorized {
        // Session expired — attempt transparent re-auth
        Logger.nutriTrack.info("NutriTrack session expired for user \(userId), re-authenticating...")

        guard let integration = try await NutriTrackIntegration.query(on: db)
            .filter(\.$user.$id == userId)
            .first()
        else {
            throw NutriTrackError.notConnected
        }

        let pin = try CryptoService.decrypt(
            ciphertext: integration.encryptedPin,
            using: .nutriTrackKey
        )

        // Re-authenticate
        let authResponse = try await httpClient.post(
            "\(integration.baseURL)/api/pin/verify",
            body: ["pin": pin]
        )

        if authResponse.status == .ok {
            // Extract new session cookie and store it
            if let setCookie = authResponse.headers.first(name: "Set-Cookie") {
                integration.sessionCookie = setCookie
                try await integration.save(on: db)
            }

            // Retry the original request with the new session
            response = try await proxyRequest(method: method, path: path, body: body, for: userId, on: db)
        } else if authResponse.status == .unauthorized {
            // PIN itself is invalid (user changed it on NutriTrack side)
            integration.lastSyncStatus = "auth_failed"
            try await integration.save(on: db)

            // Notify user
            try await pushService.sendVisiblePush(
                to: userId,
                title: "NutriTrack PIN Changed",
                body: "Your NutriTrack PIN has changed. Open Tempo to update it.",
                category: "NUTRITRACK_REAUTH",
                app: app
            )

            throw NutriTrackError.pinChanged
        } else {
            // NutriTrack server error during re-auth
            throw NutriTrackError.serverError(status: authResponse.status)
        }
    }

    return response
}
```

**Key behaviors:**
1. The iOS app NEVER sees the 401 — re-auth is handled transparently by the backend proxy.
2. If the PIN itself changed (NutriTrack returns 401 on `/api/pin/verify`), THEN the user is notified and must update their PIN in Tempo's settings.
3. The backend does NOT retry re-auth more than once per request to avoid infinite loops.
4. All re-auth attempts are logged for debugging.
5. A URL health check (`GET /api/health`) is performed before re-auth to distinguish "server down" from "session expired".

#### Network Timeout

Retry with exponential backoff:
```swift
// APIClient.swift — shared retry logic

func requestWithRetry<T: Decodable>(
    _ method: HTTPMethod,
    path: String,
    body: (any Encodable)? = nil,
    response: T.Type,
    maxRetries: Int = 3,
    baseDelay: TimeInterval = 1.0,
    maxDelay: TimeInterval = 30.0
) async throws -> T {
    var lastError: Error?

    for attempt in 0..<maxRetries {
        do {
            return try await request(method, path: path, body: body, response: response)
        } catch let error as APIError where error.isRetryable {
            lastError = error
            let delay = min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
            // Add jitter: +/- 25%
            let jitter = delay * Double.random(in: 0.75...1.25)
            try await Task.sleep(for: .seconds(jitter))
        } catch {
            throw error  // Non-retryable error, fail immediately
        }
    }

    throw lastError!
}
```

#### Invalid Response from NutriTrack

If NutriTrack returns valid HTTP but invalid JSON or unexpected structure:
1. Log the raw response body for debugging.
2. Return cached data if available.
3. Show fallback UI with "Nutrition data temporarily unavailable."
4. Do NOT crash the app — NutriTrack is a non-critical integration.

---

## 4. Apple Calendar (EventKit) Integration

### 4.1 Authorization

```swift
// CalendarService.swift
import EventKit

/// CalendarService manages all EventKit interactions.
///
/// CRITICAL: EKEventStore MUST be a singleton. Creating multiple EKEventStore instances
/// causes issues: duplicate notifications, memory leaks, and inconsistent state.
/// Apple's documentation explicitly recommends using a single instance throughout the app.
@Observable
final class CalendarService {
    static let shared = CalendarService()

    /// Single EKEventStore instance for the entire app lifecycle.
    /// Never create additional instances elsewhere.
    private let eventStore = EKEventStore()
    private(set) var isAuthorized = false

    private init() {
        // Start observing calendar changes immediately
        observeCalendarChanges()
    }

    /// Request calendar access.
    /// Called during onboarding Step 4 (after HealthKit, before notifications).
    ///
    /// iOS 17+ changed the calendar authorization API:
    /// - `requestFullAccessToEvents()` is the NEW API (iOS 17+). Grants full read/write.
    /// - `requestAccess(to: .event)` is DEPRECATED in iOS 17 and triggers a compiler warning.
    /// - On iOS 17+, calling the deprecated API may return `.writeOnly` instead of `.fullAccess`,
    ///   which would break our event reading. Always use `requestFullAccessToEvents()`.
    /// - Since Tempo targets iOS 17.4+, we can use the new API unconditionally (no #available check needed).
    func requestAccess() async -> Bool {
        do {
            // iOS 17.4+ — use the non-deprecated API directly
            let granted = try await eventStore.requestFullAccessToEvents()
            isAuthorized = granted
            return granted
        } catch {
            Logger.calendar.error("Calendar access request failed: \(error)")
            isAuthorized = false
            return false
        }
    }

    /// Check current authorization status.
    /// On iOS 17+, possible values include .fullAccess, .writeOnly, .denied, .notDetermined.
    /// Tempo requires .fullAccess (we need to READ events for scheduling).
    func checkAuthorizationStatus() -> EKAuthorizationStatus {
        let status = EKEventStore.authorizationStatus(for: .event)
        // Update our cached flag
        if #available(iOS 17.0, *) {
            isAuthorized = (status == .fullAccess)
        } else {
            isAuthorized = (status == .authorized)
        }
        return status
    }

    /// Must be called on every app launch to detect if user revoked calendar access.
    func verifyPermissionsOnLaunch() {
        let status = checkAuthorizationStatus()
        if #available(iOS 17.0, *) {
            if status == .writeOnly {
                // User granted write-only in iOS 17 — we need full access
                // Show a banner explaining why we need to read events
                Logger.calendar.warning("Calendar access is write-only — event reading disabled")
                isAuthorized = false
            }
        }
    }
}
```

**Handling denied permission:**
```swift
// CalendarPermissionBanner.swift
struct CalendarPermissionBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(.orange)

            VStack(alignment: .leading) {
                Text("Calendar Access Needed")
                    .font(.caption.bold())
                Text("Tempo uses your calendar to avoid scheduling conflicts with classes and football.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.bold())
        }
        .padding()
        .background(.orange.opacity(0.1))
        .cornerRadius(12)
    }
}
```

---

### 4.2 Reading Calendar Data

```swift
// CalendarService.swift

/// Fetch and categorize calendar events for the next 3 weeks.
func fetchUpcomingEvents() async -> [CategorizedEvent] {
    guard isAuthorized else { return [] }

    let startDate = Calendar.current.startOfDay(for: Date())
    let endDate = Calendar.current.date(byAdding: .weekOfYear, value: 3, to: startDate)!

    let predicate = eventStore.predicateForEvents(
        withStart: startDate,
        end: endDate,
        calendars: nil  // All calendars
    )

    let events = eventStore.events(matching: predicate)

    return events.compactMap { event -> CategorizedEvent? in
        let category = categorize(event)

        return CategorizedEvent(
            id: event.eventIdentifier,
            title: event.title ?? "Untitled",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            calendarName: event.calendar.title,
            calendarColor: event.calendar.cgColor.map { UIColor(cgColor: $0) },
            category: category,
            isRecurring: event.hasRecurrenceRules,
            location: event.location
        )
    }
}

/// Categorize a calendar event based on its title and other metadata.
func categorize(_ event: EKEvent) -> EventCategory {
    let title = (event.title ?? "").lowercased()
    let location = (event.location ?? "").lowercased()
    let notes = (event.notes ?? "").lowercased()
    let combined = "\(title) \(location) \(notes)"

    // Academic exams (highest priority — affects everything)
    let examKeywords = ["exam", "esame", "test", "final", "midterm", "partial", "parziale", "appello", "prova"]
    if examKeywords.contains(where: { combined.contains($0) }) {
        return .exam
    }

    // Football / Soccer
    let footballKeywords = ["football", "soccer", "calcio", "calcetto", "partita", "match", "game",
                           "practice", "allenamento", "training calcio"]
    if footballKeywords.contains(where: { combined.contains($0) }) {
        return .football
    }

    // University classes / lectures
    let classKeywords = ["class", "lecture", "lezione", "lab", "laboratorio", "seminar", "seminario",
                        "tutorial", "lesson", "corso"]
    if classKeywords.contains(where: { combined.contains($0) }) {
        return .universityClass
    }

    // Study blocks
    let studyKeywords = ["study", "studio", "library", "biblioteca", "revision", "ripasso", "homework"]
    if studyKeywords.contains(where: { combined.contains($0) }) {
        return .studyBlock
    }

    // Gym / Training (may be redundant with Whoop but useful for scheduling)
    let gymKeywords = ["gym", "palestra", "workout", "training", "weights", "pesi", "run", "corsa"]
    if gymKeywords.contains(where: { combined.contains($0) }) {
        return .training
    }

    // Social / Personal
    let socialKeywords = ["dinner", "cena", "lunch", "pranzo", "party", "festa", "birthday", "compleanno",
                         "aperitivo", "drinks"]
    if socialKeywords.contains(where: { combined.contains($0) }) {
        return .social
    }

    return .other
}

enum EventCategory: String, Codable {
    case exam              // Academic exam
    case football          // Football match or practice
    case universityClass   // University class/lecture
    case studyBlock        // Planned study time
    case training          // Gym/workout (non-football)
    case social            // Social events
    case other             // Uncategorized
}

struct CategorizedEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String
    let calendarColor: UIColor?
    let category: EventCategory
    let isRecurring: Bool
    let location: String?

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
}
```

---

### 4.3 Data Flow

#### Calendar -> Training Module

```swift
// TrainingEngine.swift

/// Determine available training windows for a given day,
/// accounting for calendar events.
func availableTrainingWindows(for date: Date) async -> [TimeWindow] {
    let events = await calendarService.fetchEvents(for: date)

    // Define potential training window: 6 AM to 9 PM
    let calendar = Calendar.current
    let dayStart = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: date)!
    let dayEnd = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date)!

    // Build list of blocked time ranges
    var blockedRanges: [DateInterval] = []

    for event in events {
        // Add buffer time around events
        let buffer: TimeInterval
        switch event.category {
        case .universityClass:
            buffer = 15 * 60  // 15 min travel buffer
        case .exam:
            buffer = 60 * 60  // 1 hour before exam for prep
        case .football:
            buffer = 30 * 60  // 30 min warmup before football
        default:
            buffer = 0
        }

        let blockedStart = event.startDate.addingTimeInterval(-buffer)
        let blockedEnd = event.endDate
        blockedRanges.append(DateInterval(start: blockedStart, end: blockedEnd))
    }

    // Calculate free windows (minimum 45 minutes for a workout)
    return calculateFreeWindows(
        dayRange: DateInterval(start: dayStart, end: dayEnd),
        blocked: blockedRanges,
        minimumDuration: 45 * 60
    )
}

/// Check if tomorrow has football — affects today's training.
func hasFootballTomorrow() async -> Bool {
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    let events = await calendarService.fetchEvents(for: tomorrow)
    return events.contains(where: { $0.category == .football })
}

/// Training constraints from calendar:
/// - Never schedule heavy legs before a football match
/// - No training during class time
/// - If exam within 3 days, reduce training volume
func calendarConstraints(for date: Date) async -> TrainingConstraints {
    let upcomingEvents = await calendarService.fetchUpcomingEvents()
    let daysToNextExam = upcomingEvents
        .filter { $0.category == .exam && $0.startDate > date }
        .map { Calendar.current.dateComponents([.day], from: date, to: $0.startDate).day ?? 999 }
        .min()

    let footballTomorrow = await hasFootballTomorrow()
    let footballToday = upcomingEvents.contains {
        $0.category == .football && Calendar.current.isDate($0.startDate, inSameDayAs: date)
    }

    return TrainingConstraints(
        footballToday: footballToday,
        footballTomorrow: footballTomorrow,
        daysToNextExam: daysToNextExam,
        availableWindows: await availableTrainingWindows(for: date),
        noHeavyLegs: footballTomorrow || footballToday,
        reduceVolume: (daysToNextExam ?? 999) <= 3,
        suggestedFocus: footballToday ? .rest : (footballTomorrow ? .upper : nil)
    )
}
```

#### Calendar -> Accountability Module

```swift
// AccountabilityService.swift

/// Determine available study blocks based on calendar.
func availableStudyWindows(for date: Date) async -> [TimeWindow] {
    let events = await calendarService.fetchEvents(for: date)

    // Study windows: prefer gaps between classes, evening hours
    let freeWindows = await calendarService.freeWindows(
        for: date,
        minimumDuration: 25 * 60  // Minimum one Pomodoro (25 min)
    )

    return freeWindows
}

/// Check if a study reminder should be suppressed.
func shouldSuppressStudyReminder() async -> Bool {
    let now = Date()
    let currentEvents = await calendarService.currentEvents(at: now)

    // Don't send study reminders during class, football, or exams
    return currentEvents.contains { event in
        [.universityClass, .football, .exam].contains(event.category)
    }
}
```

#### Calendar -> Dashboard (Mind Quadrant)

```swift
// MindQuadrantView.swift

/// Shows exam countdown if an exam is upcoming.
var examCountdown: some View {
    Group {
        if let nextExam = calendarEvents.first(where: { $0.category == .exam && $0.startDate > Date() }) {
            let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: nextExam.startDate).day ?? 0

            VStack {
                Text("\(daysUntil)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(daysUntil <= 3 ? .red : (daysUntil <= 7 ? .orange : .primary))

                Text("days to \(nextExam.title)")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }
}
```

#### Calendar -> Notification Scheduling

```swift
// NotificationService.swift

/// Schedule accountability notifications, respecting calendar events.
func scheduleNotifications(for date: Date) async {
    let events = await calendarService.fetchEvents(for: date)

    // Build quiet periods (don't notify during these)
    let quietPeriods: [DateInterval] = events
        .filter { [.universityClass, .exam, .football].contains($0.category) }
        .map { DateInterval(start: $0.startDate, end: $0.endDate) }

    // Schedule escalating notifications, skipping quiet periods
    let notificationTimes = [
        (hour: 14, minute: 0, tier: NotificationTier.gentle),
        (hour: 17, minute: 0, tier: NotificationTier.firm),
        (hour: 18, minute: 30, tier: NotificationTier.urgent),
        (hour: 19, minute: 0, tier: NotificationTier.aggressive),
        (hour: 20, minute: 0, tier: NotificationTier.final),
    ]

    for notification in notificationTimes {
        let notifTime = Calendar.current.date(
            bySettingHour: notification.hour,
            minute: notification.minute,
            second: 0,
            of: date
        )!

        // Skip if during a quiet period
        let isDuringQuietPeriod = quietPeriods.contains { $0.contains(notifTime) }
        if isDuringQuietPeriod {
            // Delay to after the quiet period ends
            if let quietPeriod = quietPeriods.first(where: { $0.contains(notifTime) }) {
                let delayed = quietPeriod.end.addingTimeInterval(5 * 60) // 5 min after event ends
                await scheduleNotification(tier: notification.tier, at: delayed)
            }
        } else {
            await scheduleNotification(tier: notification.tier, at: notifTime)
        }
    }
}
```

---

### 4.4 Edge Cases

#### Multiple Calendars

Users may have personal, university, and shared calendars. Tempo reads all calendars by default.

```swift
/// Let users select which calendars to include.
/// Default: all calendars. Users can exclude personal calendars in Settings.
func fetchEnabledCalendars() -> [EKCalendar] {
    let allCalendars = eventStore.calendars(for: .event)
    let excludedIds = UserDefaults.standard.stringArray(forKey: "excludedCalendarIds") ?? []
    return allCalendars.filter { !excludedIds.contains($0.calendarIdentifier) }
}
```

#### All-Day Events vs. Timed Events

All-day events (e.g., "Exam Week") are handled differently:
- All-day events do NOT block training windows.
- They are used for informational purposes only (exam countdown).
- The categorization still applies — an all-day "Exam" event triggers the exam countdown.

```swift
// Skip all-day events when calculating blocked time ranges
let timedEvents = events.filter { !$0.isAllDay }
```

#### Recurring Events

EventKit automatically expands recurring events when using `predicateForEvents(withStart:end:calendars:)`. A weekly "Football Practice" that repeats every Tuesday shows up as individual event instances in each week's results within the queried date range. No special handling needed for reading — EventKit handles the expansion.

**Key behaviors for recurring events:**
- Each occurrence is a separate `EKEvent` instance with its own `startDate` and `endDate`.
- All occurrences share the same `eventIdentifier` (the master event's ID). To uniquely identify an occurrence, use `calendarItemExternalIdentifier` combined with `startDate`.
- The `hasRecurrenceRules` property is `true` for all occurrences of a recurring event.
- If the user deletes a single occurrence (e.g., "Football Practice" cancelled this Tuesday), that specific occurrence disappears from query results while future occurrences remain.
- If the user modifies a single occurrence (e.g., moved this week's practice to Wednesday), EventKit creates a "detached" event for that occurrence. The original recurrence rule is preserved for other weeks.
- The categorization function `categorize(_:)` runs on EACH occurrence independently. This means a weekly "Football Practice" is correctly categorized as `.football` every week, not just the first occurrence.

**Detecting event changes (including recurring event modifications):**

The app MUST observe `EKEventStoreChanged` to react when the user adds, modifies, or deletes events (including individual occurrences of recurring events). Without this observer, Tempo would show stale calendar data until the next scheduled sync.

Tempo re-reads the calendar:
- Every time the app enters foreground (`scenePhase == .active`).
- Every 4 hours via background refresh.
- Immediately when `EKEventStoreChanged` notification fires.

```swift
// CalendarService.swift
/// Observe changes to the system calendar.
/// This fires when ANY calendar event is added, modified, or deleted — by any app,
/// including the system Calendar app, Google Calendar, etc.
/// MUST use the singleton eventStore as the `object` parameter to receive notifications.
private func observeCalendarChanges() {
    NotificationCenter.default.addObserver(
        forName: .EKEventStoreChanged,
        object: eventStore,  // MUST match our singleton EKEventStore instance
        queue: .main
    ) { [weak self] _ in
        Task {
            await self?.refreshEvents()
            // Also check if any changes conflict with the current training plan
            await self?.checkForScheduleConflicts()
        }
    }
}
```

#### Calendar Changes After Plan Generation

If Tempo has already generated a training plan for the week and the user adds a new class to their calendar:
1. `EKEventStoreChanged` fires.
2. Tempo re-reads events.
3. Tempo compares the new event schedule with the current training plan.
4. If a conflict exists (workout scheduled during a new class), Tempo sends a notification: "New calendar event conflicts with your planned workout. Tap to reschedule."
5. The user can tap to see the conflict and accept a rescheduled workout.

#### Timezone Handling

```swift
// Always use the event's own timezone for comparison
func fetchEvents(for date: Date) -> [CategorizedEvent] {
    // EventKit stores events with their timezone.
    // When comparing with "today," use the device's current timezone.
    let calendar = Calendar.current  // Uses device timezone
    let startOfDay = calendar.startOfDay(for: date)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

    let predicate = eventStore.predicateForEvents(
        withStart: startOfDay,
        end: endOfDay,
        calendars: fetchEnabledCalendars()
    )

    return eventStore.events(matching: predicate).map { /* ... */ }
}
```

If the user travels across timezones (e.g., university in Rome, family visit in London), EventKit handles timezone conversion automatically. The events appear at their correct local times.

---

## 5. Sync Architecture

### 5.1 Sync Coordinator

The `SyncService` is the central orchestrator for all data integrations. It manages sync priority, parallelism, state tracking, and retry logic.

```swift
// SyncService.swift
@Observable
final class SyncService {
    private let whoopService: WhoopService
    private let healthKitService: HealthKitService
    private let nutriTrackService: NutriTrackService
    private let calendarService: CalendarService
    private let apiClient: APIClient

    // Sync state per integration
    private(set) var syncStates: [Integration: SyncState] = [
        .whoop: .idle,
        .healthKit: .idle,
        .nutriTrack: .idle,
        .calendar: .idle,
    ]

    enum Integration: String, CaseIterable {
        case whoop, healthKit, nutriTrack, calendar
    }

    enum SyncState: Equatable {
        case idle
        case syncing(startedAt: Date)
        case completed(at: Date)
        case failed(error: String, at: Date)
    }

    // Retry queue for failed syncs
    private var retryQueue: [(Integration, Int)] = []  // (integration, retryCount)
    private let maxRetries = 3

    /// Full sync — called on app launch and pull-to-refresh.
    ///
    /// ALL FOUR integrations run in parallel with independent timeouts.
    /// No integration blocks another. If Whoop is slow (e.g., token refresh),
    /// HealthKit/NutriTrack/Calendar data still arrives immediately.
    ///
    /// Previous design ran Whoop+HealthKit first, then NutriTrack+Calendar.
    /// This was suboptimal because a slow Whoop token refresh (up to 8 seconds
    /// with retries) would delay NutriTrack and Calendar data unnecessarily.
    /// Since all four sources are completely independent, there is no reason
    /// to sequence them.
    func fullSync() async {
        // All 4 syncs run in parallel with individual timeouts
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.syncWithTimeout(.whoop, timeout: 15) }
            group.addTask { await self.syncWithTimeout(.healthKit, timeout: 10) }
            group.addTask { await self.syncWithTimeout(.nutriTrack, timeout: 10) }
            group.addTask { await self.syncWithTimeout(.calendar, timeout: 5) }

            // Wait for all to complete (or timeout individually)
            await group.waitForAll()
        }

        // Process retry queue for any that failed
        await processRetryQueue()

        // Upload daily snapshot to backend
        await uploadDailySnapshot()
    }

    /// Run a single integration sync with a timeout.
    /// If the sync exceeds the timeout, it is cancelled and marked as failed.
    private func syncWithTimeout(_ integration: Integration, timeout: TimeInterval) async {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    switch integration {
                    case .whoop: await self.syncWhoop()
                    case .healthKit: await self.syncHealthKit()
                    case .nutriTrack: await self.syncNutriTrack()
                    case .calendar: await self.syncCalendar()
                    }
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw SyncError.timeout(integration)
                }

                // First task to complete wins; cancel the other
                try await group.next()
                group.cancelAll()
            }
        } catch is SyncError {
            syncStates[integration] = .failed(error: "Sync timed out after \(Int(timeout))s", at: Date())
            Logger.sync.warning("\(integration.rawValue) sync timed out after \(timeout)s")
        } catch {
            // Task cancellation or other error — already handled in individual sync methods
        }
    }

    private func syncWhoop() async {
        guard whoopService.connectionState != .disconnected else { return }
        syncStates[.whoop] = .syncing(startedAt: Date())

        do {
            try await whoopService.fetchTodayData()
            syncStates[.whoop] = .completed(at: Date())
        } catch {
            syncStates[.whoop] = .failed(error: error.localizedDescription, at: Date())
            retryQueue.append((.whoop, 0))
        }
    }

    private func syncHealthKit() async {
        syncStates[.healthKit] = .syncing(startedAt: Date())

        do {
            async let steps = healthKitService.fetchTodaySteps()
            async let energy = healthKitService.fetchTodayActiveEnergy()
            async let sleep = healthKitService.fetchSleep(for: Date())
            async let rhr = healthKitService.getRestingHeartRate()

            let (stepsResult, energyResult, sleepResult, rhrResult) = try await (steps, energy, sleep, rhr)

            await healthKitService.updateDailySnapshot(
                steps: stepsResult,
                activeEnergy: energyResult,
                sleep: sleepResult,
                restingHR: rhrResult
            )

            syncStates[.healthKit] = .completed(at: Date())
        } catch {
            syncStates[.healthKit] = .failed(error: error.localizedDescription, at: Date())
            retryQueue.append((.healthKit, 0))
        }
    }

    private func syncNutriTrack() async {
        guard nutriTrackService.isConnected else { return }
        syncStates[.nutriTrack] = .syncing(startedAt: Date())

        do {
            try await nutriTrackService.syncOnLaunch()
            syncStates[.nutriTrack] = .completed(at: Date())
        } catch {
            syncStates[.nutriTrack] = .failed(error: error.localizedDescription, at: Date())
            retryQueue.append((.nutriTrack, 0))
        }
    }

    private func syncCalendar() async {
        guard calendarService.isAuthorized else { return }
        syncStates[.calendar] = .syncing(startedAt: Date())

        do {
            _ = await calendarService.fetchUpcomingEvents()
            syncStates[.calendar] = .completed(at: Date())
        } catch {
            syncStates[.calendar] = .failed(error: error.localizedDescription, at: Date())
            // Calendar doesn't retry — it's local and either works or permissions are denied
        }
    }

    private func processRetryQueue() async {
        let currentQueue = retryQueue
        retryQueue = []

        for (integration, retryCount) in currentQueue {
            guard retryCount < maxRetries else {
                Logger.sync.error("Max retries exceeded for \(integration.rawValue)")
                continue
            }

            // Exponential backoff delay
            let delay = pow(2.0, Double(retryCount))
            try? await Task.sleep(for: .seconds(delay))

            switch integration {
            case .whoop: await syncWhoop()
            case .healthKit: await syncHealthKit()
            case .nutriTrack: await syncNutriTrack()
            case .calendar: await syncCalendar()
            }
        }
    }

    /// Upload the consolidated daily snapshot to the backend.
    private func uploadDailySnapshot() async {
        let snapshot = await buildDailySnapshot()

        do {
            try await apiClient.post(
                "/v1/sync/snapshot",
                body: snapshot,
                response: SnapshotResponse.self
            )
        } catch {
            Logger.sync.error("Failed to upload daily snapshot: \(error)")
            // Queue for retry on next sync
        }
    }
}
```

---

### 5.2 Conflict Resolution Matrix

When the same data type is available from multiple sources, Tempo applies a deterministic priority system.

| Data Type | Whoop API | HealthKit | NutriTrack | Local (SwiftData) | Winner | Rationale |
|-----------|-----------|-----------|------------|-------------------|--------|-----------|
| Recovery score | Y | | | | **Whoop API** | Only source |
| Recovery zone | Y | | | | **Whoop API** | Derived from recovery score |
| HRV (RMSSD) | Y | Y (from Whoop) | | | **Whoop API** | Same data, API has richer context |
| Resting HR | Y | Y | | | **Whoop API** | Whoop measures during sleep, more accurate |
| Sleep duration | Y | Y | | | **Whoop API** | Richer data (stages, efficiency, performance) |
| Sleep stages | Y | Y | | | **Whoop API** | More granular (light/deep/REM/awake + percentages) |
| Strain | Y | | | | **Whoop API** | Only source |
| Steps | | Y | | | **HealthKit** | Apple Watch/iPhone are the only step counters |
| Active energy | | Y | | | **HealthKit** | Apple's calorie estimation is device-specific |
| Exercise minutes | | Y | | | **HealthKit** | Apple's exercise ring metric |
| Workout (logged in RepForge) | | | | Y | **Local** | User-entered data is authoritative |
| Workout (Whoop auto-detected) | Y | Y (from Whoop) | | | **Whoop API** | Richer data (strain, HR zones) |
| Workout (Apple Watch only) | | Y | | | **HealthKit** | Only source for non-Whoop workouts |
| Calories consumed | | | Y | | **NutriTrack** | Only source |
| Macros (protein/carbs/fat) | | | Y | | **NutriTrack** | Only source |
| Meal status | | | Y | | **NutriTrack** | Only source |
| Meal plan | | | Y | | **NutriTrack** | Only source |
| Study minutes | | | | Y | **Local** | Tracked by focus timer |
| Non-negotiable completion | | | | Y | **Local** | Tracked locally, some auto-verified |
| Calendar events | | | | | **EventKit** | Only source |
| XP / Level | | | | | **Backend** | Backend is source of truth for social features |

**Implementation of conflict resolution:**
```swift
// DailySnapshotBuilder.swift

/// Builds the day's snapshot by merging data from all sources with priority resolution.
func buildDailySnapshot() async -> DailySnapshot {
    let snapshot = DailySnapshot(date: Date())

    // Recovery: Whoop only
    if let whoopRecovery = await whoopService.todayRecovery {
        snapshot.recoveryScore = whoopRecovery.recoveryScore
        snapshot.hrvRmssd = whoopRecovery.hrvRmssd
        snapshot.restingHR = whoopRecovery.restingHR
        snapshot.strain = await whoopService.todayCycle?.strain
    }

    // Sleep: Whoop preferred, HealthKit fallback
    if let whoopSleep = await whoopService.todaySleep {
        snapshot.sleepHours = whoopSleep.totalSleepDuration / 3600.0
        snapshot.sleepScore = whoopSleep.sleepPerformance
    } else if let hkSleep = await healthKitService.cachedSleep {
        snapshot.sleepHours = hkSleep.totalAsleep / 3600.0
        snapshot.sleepScore = nil  // HealthKit doesn't provide a sleep "score"
    }

    // Steps: HealthKit only
    snapshot.steps = await healthKitService.cachedSteps

    // Active energy: HealthKit only
    snapshot.activeCalories = await healthKitService.cachedActiveEnergy

    // Nutrition: NutriTrack only
    if let nutriData = await nutriTrackService.cachedToday {
        snapshot.caloriesConsumed = nutriData.calories
        snapshot.calorieTarget = nutriData.targetCalories
        snapshot.proteinG = nutriData.proteinG
        snapshot.carbsG = nutriData.carbsG
        snapshot.fatG = nutriData.fatG
        snapshot.mealsLogged = nutriData.mealsEaten
        snapshot.mealsPlanned = nutriData.mealsTotal
    }

    // Study: Local only
    snapshot.studyMinutes = await studyService.todayMinutes
    snapshot.studyTarget = await studyService.dailyTarget

    // Workout: merge local + Whoop + HealthKit (deduplicated)
    snapshot.workoutCompleted = await determineWorkoutCompleted()

    return snapshot
}

/// Determine if the user completed a workout today, considering all sources.
private func determineWorkoutCompleted() async -> Bool {
    // 1. Check local RepForge workouts
    let localWorkouts = await workoutService.todayWorkouts
    if !localWorkouts.isEmpty { return true }

    // 2. Check Whoop workouts
    let whoopWorkouts = await whoopService.todayWorkouts
    if !whoopWorkouts.isEmpty { return true }

    // 3. Check HealthKit workouts (non-Whoop sources only)
    let hkWorkouts = try? await healthKitService.fetchNonWhoopWorkouts(
        startDate: Calendar.current.startOfDay(for: Date()),
        endDate: Date()
    )
    if let hkWorkouts, !hkWorkouts.isEmpty { return true }

    return false
}
```

---

### 5.3 Data Freshness Indicators

```swift
// DataFreshnessMonitor.swift

@Observable
final class DataFreshnessMonitor {

    /// Staleness thresholds per data source.
    static let staleThresholds: [SyncService.Integration: TimeInterval] = [
        .whoop: 30 * 60,      // 30 minutes
        .nutriTrack: 15 * 60, // 15 minutes
        .healthKit: 0,        // Immediate (local data, always fresh)
        .calendar: 24 * 60 * 60, // 1 day
    ]

    /// Check if a data source is stale.
    func isStale(_ integration: SyncService.Integration, lastSync: Date?) -> Bool {
        guard let lastSync else { return true }
        let threshold = Self.staleThresholds[integration] ?? 0
        return Date().timeIntervalSince(lastSync) > threshold
    }

    /// Human-readable freshness string.
    func freshnessLabel(for integration: SyncService.Integration, lastSync: Date?) -> String? {
        guard let lastSync else { return "Never synced" }

        let elapsed = Date().timeIntervalSince(lastSync)

        guard isStale(integration, lastSync: lastSync) else { return nil }

        if elapsed < 60 {
            return "Synced just now"
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return "Synced \(minutes) min ago"
        } else if elapsed < 86400 {
            let hours = Int(elapsed / 3600)
            return "Synced \(hours)h ago"
        } else {
            let days = Int(elapsed / 86400)
            return "Synced \(days)d ago"
        }
    }

    /// Visual treatment for stale data.
    func staleOpacity(for integration: SyncService.Integration, lastSync: Date?) -> Double {
        guard isStale(integration, lastSync: lastSync) else { return 1.0 }

        let elapsed = Date().timeIntervalSince(lastSync ?? .distantPast)
        let threshold = Self.staleThresholds[integration] ?? 0

        // Gradually dim: 100% at threshold, 60% at 2x threshold, 40% at 4x+
        let ratio = elapsed / max(threshold, 1)
        return max(0.4, 1.0 - (ratio - 1.0) * 0.2)
    }
}
```

**Auto-refresh trigger:**
```swift
// SyncService.swift

/// Called periodically (every minute) to check if any source needs refreshing.
func checkAndRefreshStaleData() async {
    let monitor = DataFreshnessMonitor()

    for integration in SyncService.Integration.allCases {
        let lastSync: Date?
        switch integration {
        case .whoop: lastSync = whoopService.lastSyncDate
        case .healthKit: lastSync = healthKitService.lastSyncDate
        case .nutriTrack: lastSync = nutriTrackService.lastSyncDate
        case .calendar: lastSync = calendarService.lastSyncDate
        }

        if monitor.isStale(integration, lastSync: lastSync) {
            await syncIntegration(integration)
        }
    }
}
```

---

### 5.4 Offline Behavior

#### Local Cache Architecture

All integration data is cached in SwiftData. The app provides a full read experience even with zero connectivity.

```swift
// SwiftData models for cached integration data

@Model
class CachedWhoopData {
    var date: Date
    var recoveryJSON: Data?       // Serialized WhoopRecovery
    var sleepJSON: Data?          // Serialized WhoopSleep
    var cycleJSON: Data?          // Serialized WhoopCycle
    var workoutsJSON: Data?       // Serialized [WhoopWorkout]
    var fetchedAt: Date
}

@Model
class CachedNutriTrackData {
    var date: Date
    var todayJSON: Data?          // Serialized NutriTrackToday
    var macrosJSON: Data?         // Serialized NutriTrackMacros
    var fetchedAt: Date
}

@Model
class CachedCalendarData {
    var weekStartDate: Date
    var eventsJSON: Data?         // Serialized [CategorizedEvent]
    var fetchedAt: Date
}
```

#### Write Queue for Offline Operations

When the device is offline, write operations (workout logs, study sessions, non-negotiable check-offs) are queued and replayed when connectivity returns.

```swift
// OfflineQueue.swift

@Observable
final class OfflineQueue {
    @Model
    class QueuedOperation {
        var id: UUID
        var type: String              // "workout_log", "study_session", "nn_checkoff", "xp_event", "snapshot"
        var payload: Data             // JSON-encoded request body
        var createdAt: Date
        var retryCount: Int = 0
        var lastError: String?
    }

    private var modelContext: ModelContext
    private var isProcessing = false

    /// Maximum number of queued operations. Prevents unbounded storage growth
    /// if the device is offline for an extended period.
    private static let maxQueueSize = 500

    /// Queue a write operation for later.
    /// If the queue exceeds maxQueueSize, the oldest LOW-PRIORITY operations
    /// are dropped first. High-priority operations (workout_log, study_session)
    /// are never dropped — they represent user-entered data that cannot be recreated.
    func enqueue(type: String, payload: any Encodable) {
        let data = try! JSONEncoder().encode(payload)
        let operation = QueuedOperation(
            id: UUID(),
            type: type,
            payload: data,
            createdAt: Date()
        )
        modelContext.insert(operation)
        try? modelContext.save()

        // Enforce max queue size
        evictIfOverCapacity()
    }

    /// Drop oldest low-priority operations if queue exceeds capacity.
    /// Priority tiers:
    ///   HIGH (never drop): workout_log, study_session, nn_checkoff
    ///   LOW (drop oldest first): xp_event, snapshot
    private func evictIfOverCapacity() {
        let descriptor = FetchDescriptor<QueuedOperation>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let allOps = try? modelContext.fetch(descriptor),
              allOps.count > Self.maxQueueSize else { return }

        let highPriorityTypes: Set<String> = ["workout_log", "study_session", "nn_checkoff"]
        let lowPriorityOps = allOps.filter { !highPriorityTypes.contains($0.type) }

        // Drop oldest low-priority ops until under capacity
        let excess = allOps.count - Self.maxQueueSize
        for op in lowPriorityOps.prefix(excess) {
            Logger.offline.info("Evicting queued operation \(op.id) (type: \(op.type)) — queue over capacity")
            modelContext.delete(op)
        }
        try? modelContext.save()
    }

    /// Process all queued operations (called when connectivity returns).
    func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let descriptor = FetchDescriptor<QueuedOperation>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        guard let operations = try? modelContext.fetch(descriptor) else { return }

        for operation in operations {
            do {
                try await processOperation(operation)
                modelContext.delete(operation)
                try? modelContext.save()
            } catch {
                operation.retryCount += 1
                operation.lastError = error.localizedDescription

                if operation.retryCount >= 5 {
                    Logger.offline.error("Permanently failed operation \(operation.id): \(error)")
                    modelContext.delete(operation)
                }

                try? modelContext.save()
            }
        }
    }

    private func processOperation(_ operation: QueuedOperation) async throws {
        switch operation.type {
        case "workout_log":
            let workout = try JSONDecoder().decode(WorkoutLogRequest.self, from: operation.payload)
            try await apiClient.post("/v1/sync/workouts", body: workout)

        case "study_session":
            let session = try JSONDecoder().decode(StudySessionRequest.self, from: operation.payload)
            try await apiClient.post("/v1/sync/study-sessions", body: session)

        case "xp_event":
            let event = try JSONDecoder().decode(XPEventRequest.self, from: operation.payload)
            try await apiClient.post("/v1/xp/events", body: event)

        case "snapshot":
            let snapshot = try JSONDecoder().decode(DailySnapshotRequest.self, from: operation.payload)
            try await apiClient.post("/v1/sync/snapshot", body: snapshot)

        default:
            Logger.offline.warning("Unknown queued operation type: \(operation.type)")
        }
    }
}
```

#### Conflict Detection for Queued Writes

When the queue is replayed, some data may have changed on the server (e.g., a workout was also logged via Whoop webhook while the app was offline).

```swift
// Conflict detection during queue replay
private func processWorkoutLog(_ workout: WorkoutLogRequest) async throws {
    // Check if this workout's time range overlaps with a workout
    // that was already synced via Whoop webhook
    let existingWorkouts = try await apiClient.get(
        "/v1/whoop/workouts",
        query: [
            "start_date": ISO8601DateFormatter().string(from: workout.startedAt),
            "end_date": ISO8601DateFormatter().string(from: workout.endedAt),
        ],
        response: WhoopWorkoutsResponse.self
    )

    // If >50% time overlap with an existing Whoop workout, skip the upload
    // (the Whoop workout is more authoritative for the same activity)
    for existing in existingWorkouts.data {
        let overlap = calculateOverlap(
            a: (workout.startedAt, workout.endedAt),
            b: (existing.start, existing.end)
        )
        if overlap > 0.5 {
            Logger.offline.info("Skipping queued workout — overlaps with Whoop workout \(existing.id)")
            return  // Don't upload, but don't error either
        }
    }

    // No conflict — upload normally
    try await apiClient.post("/v1/sync/workouts", body: workout)
}
```

#### Network Monitoring

```swift
// NetworkMonitor.swift
import Network

@Observable
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private(set) var isConnected = true
    private(set) var connectionType: ConnectionType = .unknown

    enum ConnectionType {
        case wifi, cellular, unknown
    }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else {
                    self?.connectionType = .unknown
                }

                // When connectivity returns, process the offline queue
                if path.status == .satisfied {
                    await OfflineQueue.shared.processQueue()
                    await SyncService.shared.fullSync()
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }
}
```

---

### 5.5 Complete Data Flow Diagram

```
                         TEMPO DATA FLOW
                         ===============

EXTERNAL SOURCES                  TEMPO BACKEND                    TEMPO iOS APP
================                  =============                    =============

Whoop API v2 ----[webhooks]----> POST /v1/webhooks/whoop
             <---[poll/fetch]--> WhoopSyncService
                                    |
                                    v
                                 PostgreSQL ----[GET /v1/whoop/*]---> WhoopService
                                 (whoop_recovery,                       |
                                  whoop_sleep,                          v
                                  whoop_workouts,                  SwiftData Cache
                                  whoop_cycles)                    (CachedWhoopData)
                                                                        |
                                                                        v
Apple HealthKit                                                    HealthKitService
(on-device) -----[HKObserverQuery]------------------------------->     |
             <---[HKStatisticsQuery]-------------------------------     |
             <---[HKWorkoutBuilder]--------------------------------     |
                                                                        v
                                                                   DailySnapshot
                                                                   (SwiftData)
NutriTrack   <---------[proxy]-------> NutriTrackProxy                  ^
Flask Server        GET /v1/nutritrack/*    |                           |
                                           v                     NutriTrackService
                                        Redis Cache                     |
                                        (2-10 min TTL)                  v
                                                               CachedNutriTrackData
                                                                        |
Apple Calendar                                                          v
(EventKit,   ----[EKEventStore.events(matching:)]---------------> CalendarService
 on-device)                                                             |
                                                                        v
                                                               CachedCalendarData
                                                                        |
                                                                        v
                                                                  ┌─────────────┐
                                                                  │ SyncService  │
                                                                  │ (orchestrator│
                                                                  │  + conflict  │
                                                                  │  resolution) │
                                                                  └──────┬──────┘
                                                                         |
                                                                         v
                                                                  DailySnapshot
                                                                  (merged, final)
                                                                         |
                                                          ┌──────────────┼──────────────┐
                                                          v              v              v
                                                     Dashboard    Training Engine  Accountability
                                                     (LifeOS)    (RepForge)       (Lockdown)
                                                          |              |              |
                                                          v              v              v
                                                     POST /v1/sync/snapshot ---------> Backend
                                                     POST /v1/xp/events ------------> Backend
                                                     POST /v1/sync/workouts --------> Backend
                                                     POST /v1/sync/study-sessions --> Backend
```

---

### 5.6 Integration Health Dashboard

The Settings screen includes an integration health view showing the status of all connections.

```swift
// IntegrationHealthView.swift
struct IntegrationHealthView: View {
    @Environment(SyncService.self) var syncService
    @Environment(WhoopService.self) var whoopService
    @Environment(NutriTrackService.self) var nutriTrackService
    @Environment(HealthKitService.self) var healthKitService
    @Environment(CalendarService.self) var calendarService

    var body: some View {
        List {
            integrationRow(
                name: "Whoop",
                icon: "heart.circle.fill",
                color: .green,
                state: syncService.syncStates[.whoop] ?? .idle,
                connected: whoopService.connectionState != .disconnected,
                lastSync: whoopService.lastSyncDate
            )

            integrationRow(
                name: "Apple Health",
                icon: "heart.text.square.fill",
                color: .red,
                state: syncService.syncStates[.healthKit] ?? .idle,
                connected: true,  // Always "connected" if device supports HealthKit
                lastSync: healthKitService.lastSyncDate
            )

            integrationRow(
                name: "NutriTrack",
                icon: "fork.knife.circle.fill",
                color: .orange,
                state: syncService.syncStates[.nutriTrack] ?? .idle,
                connected: nutriTrackService.isConnected,
                lastSync: nutriTrackService.lastSyncDate
            )

            integrationRow(
                name: "Calendar",
                icon: "calendar.circle.fill",
                color: .blue,
                state: syncService.syncStates[.calendar] ?? .idle,
                connected: calendarService.isAuthorized,
                lastSync: calendarService.lastSyncDate
            )
        }
        .navigationTitle("Integrations")
    }

    private func integrationRow(
        name: String,
        icon: String,
        color: Color,
        state: SyncService.SyncState,
        connected: Bool,
        lastSync: Date?
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title2)

            VStack(alignment: .leading) {
                Text(name)
                    .font(.headline)

                Group {
                    if !connected {
                        Text("Not connected")
                            .foregroundStyle(.secondary)
                    } else {
                        switch state {
                        case .idle:
                            Text("Connected")
                                .foregroundStyle(.green)
                        case .syncing:
                            Text("Syncing...")
                                .foregroundStyle(.blue)
                        case .completed(let date):
                            Text("Synced \(date.formatted(.relative(presentation: .named)))")
                                .foregroundStyle(.secondary)
                        case .failed(let error, _):
                            Text("Error: \(error)")
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                }
                .font(.caption)
            }

            Spacer()

            // Status indicator
            Circle()
                .fill(statusColor(connected: connected, state: state))
                .frame(width: 10, height: 10)
        }
    }

    private func statusColor(connected: Bool, state: SyncService.SyncState) -> Color {
        guard connected else { return .gray }
        switch state {
        case .idle, .completed: return .green
        case .syncing: return .blue
        case .failed: return .red
        }
    }
}
```

---

---

## 6. Error Recovery & Resilience

Integration failures are the #1 source of user complaints. This section specifies retry strategies, circuit breakers, user notifications, and graceful degradation for EVERY integration.

### 6.1 Retry Strategies

| Integration | Error Type | Strategy | Details |
|-------------|-----------|----------|---------|
| **Whoop** | Network timeout | Exponential backoff | 3 retries: 2s, 4s, 8s. Jitter +/- 25%. |
| **Whoop** | 429 Rate Limited | Respect Retry-After | Use the `Retry-After` header value. If absent, wait 60s. |
| **Whoop** | 500/502/503 Server Error | Exponential backoff | 3 retries: 2s, 4s, 8s. If all fail, mark as `degraded`. |
| **Whoop** | 401 Token Expired | Immediate refresh | Refresh token once. If refresh fails with 401, trigger re-auth flow. No retry. |
| **Whoop** | 403 Membership Expired | No retry | Mark as `membership_expired`. Check daily. |
| **HealthKit** | Query returns no data | No retry | Data may legitimately be empty. Show "No data available." |
| **HealthKit** | Query throws error | Immediate retry once | HealthKit queries rarely fail; a single retry usually succeeds. |
| **HealthKit** | Background delivery stops | N/A | Re-register observer queries on app launch (already happens in `setupObserverQueries()`). |
| **NutriTrack** | Network timeout | Exponential backoff | 3 retries: 1s, 2s, 4s. Max delay 30s. |
| **NutriTrack** | 401 Session Expired | Immediate re-auth | Transparent re-auth via backend proxy (Section 3.4). If PIN changed, notify user. |
| **NutriTrack** | Server unreachable | Exponential backoff | 3 retries. After failure, serve cached data. Retry on next periodic sync (15 min). |
| **NutriTrack** | Invalid JSON response | No retry | Log the response body. Serve cached data. Flag for investigation. |
| **Calendar** | Permission denied | No retry | Show permission banner. User must fix in Settings. |
| **Calendar** | EKEventStore error | No retry | Calendar is local; errors are rare and usually indicate a corrupted calendar database. Restart eventStore. |
| **Backend** | Network timeout | Exponential backoff | 3 retries: 1s, 2s, 4s. Queue for offline replay if all fail. |
| **Backend** | 401 JWT Expired | Immediate refresh | Refresh JWT once. If refresh fails, force re-login. |
| **Backend** | 500 Server Error | Exponential backoff | 3 retries. Queue for offline replay if all fail. |

### 6.2 Circuit Breaker Pattern

When an integration fails repeatedly, stop trying for a cooldown period to avoid wasting battery and bandwidth on a known-down service.

```swift
// CircuitBreaker.swift

actor CircuitBreaker {
    enum State {
        case closed       // Normal operation — requests pass through
        case open         // Failing — requests are blocked for cooldownDuration
        case halfOpen     // Testing — one request allowed through to check recovery
    }

    private var state: State = .closed
    private var failureCount: Int = 0
    private var lastFailureAt: Date?
    private var lastSuccessAt: Date?

    /// Number of consecutive failures before opening the circuit.
    let failureThreshold: Int

    /// How long to wait before allowing a test request.
    let cooldownDuration: TimeInterval

    init(failureThreshold: Int = 5, cooldownDuration: TimeInterval = 300) { // 5 failures, 5 min cooldown
        self.failureThreshold = failureThreshold
        self.cooldownDuration = cooldownDuration
    }

    /// Check if a request should be allowed through.
    func shouldAllow() -> Bool {
        switch state {
        case .closed:
            return true
        case .open:
            // Check if cooldown has elapsed
            if let lastFailure = lastFailureAt,
               Date().timeIntervalSince(lastFailure) >= cooldownDuration {
                state = .halfOpen
                return true  // Allow one test request
            }
            return false
        case .halfOpen:
            return false  // Only one request at a time in half-open
        }
    }

    /// Record a successful request.
    func recordSuccess() {
        failureCount = 0
        lastSuccessAt = Date()
        state = .closed
    }

    /// Record a failed request.
    func recordFailure() {
        failureCount += 1
        lastFailureAt = Date()

        if failureCount >= failureThreshold {
            state = .open
        }
    }
}
```

**Circuit breaker configuration per integration:**

| Integration | Failure Threshold | Cooldown Duration | Rationale |
|-------------|------------------|-------------------|-----------|
| Whoop API | 5 failures | 5 minutes | Whoop outages are typically short. Don't give up too fast. |
| NutriTrack | 3 failures | 10 minutes | Self-hosted server — if it's down, it's likely down for a while. |
| Backend | 5 failures | 2 minutes | Backend should recover quickly. Short cooldown for fast recovery. |
| HealthKit | No circuit breaker | N/A | Local-only — failures are instantaneous and not rate-related. |
| Calendar | No circuit breaker | N/A | Local-only — same as HealthKit. |

### 6.3 User Notification Strategy

Users should be informed about integration issues at the right level of urgency — not too noisy, not too silent.

| Scenario | When to Notify | Notification Type | Copy |
|----------|---------------|-------------------|------|
| Whoop token revoked | Immediately | Visible push + in-app banner | "Whoop disconnected. Tap to reconnect." |
| Whoop membership expired | Immediately | Visible push + in-app banner | "Your Whoop membership expired. Tempo will use cached data." |
| Whoop data stale (>2 hours) | After 2 hours | In-app banner only (no push) | "Whoop data last updated 2h ago. Open Whoop app to sync." |
| Whoop servers down | After 3 failed retries | In-app banner only | "Whoop is temporarily unavailable. Using last known data." |
| NutriTrack PIN changed | Immediately | Visible push + in-app banner | "NutriTrack PIN changed. Tap to update." |
| NutriTrack server down | After 30 minutes | In-app banner only | "NutriTrack server unreachable. Nutrition data may be stale." |
| HealthKit permissions revoked | On next app launch | In-app banner | "Health data access disabled. Tap to enable in Settings." |
| Calendar permissions revoked | On next app launch | In-app banner | "Calendar access disabled. Tap to enable in Settings." |
| Backend unreachable | After 5 minutes | In-app banner | "Tempo is offline. Your data is saved locally." |
| Offline queue growing | Queue > 50 items | In-app subtle indicator | Sync icon with badge count |

**Notification rate limiting:**
- Never send more than 1 push notification per integration per hour.
- Never show more than 2 in-app banners simultaneously.
- If multiple integrations are failing, show a single summary banner: "Some integrations are having issues. Tap for details."

### 6.4 Graceful Degradation Matrix

When an integration is down, Tempo must still provide value. This matrix specifies exactly which features work and which degrade for each integration failure.

#### Without Whoop

| Feature | Behavior | Degraded UI |
|---------|----------|-------------|
| Dashboard — Body quadrant | Recovery score hidden. Show "Connect Whoop for recovery data." | Gray placeholder |
| Dashboard — Move quadrant | Strain hidden. Steps and active energy still shown from HealthKit. | Partial data |
| Training — Recovery-adjusted workouts | Fall back to "moderate" intensity. Show note: "Recovery data unavailable — defaulting to moderate intensity." | Warning badge |
| Training — HR zones during workout | Use HealthKit heart rate (Apple Watch) instead of Whoop. | Seamless if Apple Watch available |
| Recovery module | Entirely disabled. Show "Connect Whoop to access recovery insights." | Module locked |
| Sleep analysis | Fall back to HealthKit sleep data (Apple Watch). Reduced detail (no sleep performance/efficiency). | Partial data |
| Arena — XP from recovery | Recovery-based XP events not generated. Other XP sources still work. | Reduced XP |

#### Without HealthKit

| Feature | Behavior | Degraded UI |
|---------|----------|-------------|
| Dashboard — Body quadrant | Steps and active energy hidden. Recovery still shown from Whoop. | Partial data |
| Dashboard — Move quadrant | Show Whoop strain only. No step count. | Partial data |
| Training — Workout logging | Workouts logged locally in RepForge but NOT written to HealthKit. | No cross-app sync |
| Nutrition — HealthKit write | NutriTrack data not written to HealthKit. | No cross-app sync |
| Sleep (no Apple Watch) | Whoop sleep data still available. Only impacts users without Whoop. | Seamless if Whoop connected |

#### Without NutriTrack

| Feature | Behavior | Degraded UI |
|---------|----------|-------------|
| Dashboard — Fuel quadrant | Show "Connect NutriTrack for nutrition data." No calorie/macro info. | Gray placeholder |
| Accountability — Meal tracking | "Eat 3 meals" non-negotiable cannot be auto-verified. User must manually check it off. | Manual fallback |
| Training — Nutrition timing | No pre/post workout nutrition advice. Training plan generated without nutrition context. | Reduced intelligence |
| Recovery — Nutrition for recovery | No protein intake data for recovery recommendations. | Reduced intelligence |
| Arena — Meal streak XP | Meal-based XP events not generated. | Reduced XP |
| HealthKit — Nutrition write | No nutrition data written to HealthKit. | No cross-app sync |

#### Without Calendar

| Feature | Behavior | Degraded UI |
|---------|----------|-------------|
| Dashboard — Mind quadrant | No exam countdown. Show "Connect Calendar for exam tracking." | Gray placeholder |
| Training — Schedule conflicts | No conflict detection. Workout scheduling ignores classes/events. | Reduced intelligence |
| Training — Football awareness | Cannot detect football matches. User must manually indicate match days. | Manual fallback |
| Accountability — Study windows | No suggested study windows. User picks their own times. | Manual fallback |
| Notifications — Quiet periods | No quiet period detection. Notifications fire regardless of events. | Potentially annoying |

#### Completely Offline (No Network)

| Feature | Behavior |
|---------|----------|
| Dashboard | Shows all cached data with staleness indicators. All four quadrants work with last known data. |
| Training — Workout logging | Fully functional. Workouts saved to SwiftData. Queued for backend sync. |
| Accountability — Focus timer | Fully functional. Study sessions saved locally. Queued for sync. |
| Accountability — Non-negotiables | Fully functional. Check-offs saved locally. |
| Arena — XP | XP events queued locally. Leaderboard shows stale data with "Last updated X ago." |
| HealthKit reads | Fully functional (local). |
| Calendar reads | Fully functional (local). |
| Whoop data | Stale. Shows last known data. |
| NutriTrack data | Stale. Shows last cached day. |

### 6.5 Conflict Resolution — Backend vs. Local

When the backend and the local device disagree on a value (e.g., after queue replay or race conditions), these rules determine the winner:

| Data Type | Winner | Rationale |
|-----------|--------|-----------|
| Daily recovery score | **Backend** | Backend receives authoritative data from Whoop API. |
| Daily strain | **Backend** | Same as recovery. |
| Sleep data | **Backend** | Backend has the latest Whoop API data. |
| Steps | **Local (HealthKit)** | HealthKit is the ground truth for step counts. Backend stores a snapshot but never overrides HealthKit. |
| Active energy | **Local (HealthKit)** | Same as steps. |
| Workout (logged in RepForge) | **Last-write-wins with timestamp** | If the user edited the workout on another device (future feature), the most recent edit wins. Conflict detected by comparing `updatedAt` timestamps. |
| NutriTrack nutrition | **Backend** (proxied from NutriTrack) | NutriTrack server is the source of truth for nutrition data. |
| Non-negotiable completion | **Local** | User's device is authoritative for self-reported completions. Backend never un-completes a non-negotiable. |
| XP / Level | **Backend** | Backend is the global source of truth for XP to prevent client-side manipulation. If local XP > backend XP, the backend value wins. Queued XP events are replayed and the backend recalculates. |
| Study minutes | **Last-write-wins with timestamp** | Same logic as workouts. |
| Calendar events | **Local (EventKit)** | EventKit is the source of truth. Backend does not store calendar events. |

---

*End of Integration Specifications. This document is the authoritative reference for all data flow in Tempo. Update it when adding new integrations or changing sync behavior.*
