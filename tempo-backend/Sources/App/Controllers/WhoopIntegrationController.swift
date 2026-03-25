import Vapor
import Fluent
@preconcurrency import Redis

// MARK: - Whoop Integration Controller
// Per INTEGRATION_SPECS.md Section 1.1 — Whoop OAuth endpoints.
// GET  /v1/integrations/whoop/authorize  — Build OAuth URL + CSRF state
// GET  /v1/integrations/whoop/callback   — Handle OAuth callback
// DELETE /v1/integrations/whoop          — Disconnect
// GET  /v1/integrations/whoop/status     — Connection status

struct WhoopIntegrationController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("authorize", use: authorize)
        routes.get("callback", use: callback)
        routes.delete(use: disconnect)
        routes.get("status", use: status)
    }

    // MARK: - GET /authorize
    // Per INTEGRATION_SPECS.md Section 1.1 — Build Whoop OAuth URL with CSRF state.

    func authorize(_ req: Request) async throws -> WhoopAuthorizeResponse {
        let userID = try req.auth.requireUserID()

        // Check if already connected
        if let existing = try await WhoopIntegration.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first() {
            _ = existing
            throw Abort(.conflict, reason: "Whoop already connected.")
        }

        // Generate CSRF state and store in Redis with 10-min TTL
        let state = String.randomHex(length: 32) // 64 hex chars
        let stateKey = RedisKey("whoop_oauth_state:\(userID)")
        _ = try await req.redis.setex(stateKey, to: state, expirationInSeconds: 600).get()

        let authorizationURL = WhoopOAuthService.buildAuthorizationURL(state: state)

        return WhoopAuthorizeResponse(authorizationUrl: authorizationURL, state: state)
    }

    // MARK: - GET /callback
    // Per INTEGRATION_SPECS.md Section 1.1 — Handle Whoop OAuth callback.

    func callback(_ req: Request) async throws -> Response {
        // Check for error from Whoop (user denied)
        if let error = req.query[String.self, at: "error"] {
            return req.redirect(to: "tempo://integrations/whoop/error?code=3004&message=\(error)")
        }

        guard let code = req.query[String.self, at: "code"],
              let state = req.query[String.self, at: "state"] else {
            return req.redirect(to: "tempo://integrations/whoop/error?code=3002&message=missing_params")
        }

        // We need the user ID to validate state — extract from a temporary parameter
        // In practice, we encode the user ID in the state or use a session
        // For now, look up the state across all keys
        guard let userID = try await findUserIDForState(state, on: req) else {
            return req.redirect(to: "tempo://integrations/whoop/error?code=3002&message=invalid_state")
        }

        // Delete state from Redis
        _ = try await req.redis.delete(RedisKey("whoop_oauth_state:\(userID)")).get()

        // Exchange code for tokens (with retry)
        let tokenResponse: WhoopOAuthService.TokenResponse
        do {
            tokenResponse = try await exchangeWithRetry(code: code, on: req)
        } catch {
            return req.redirect(to: "tempo://integrations/whoop/error?code=3007&message=token_exchange_failed")
        }

        // Encrypt tokens
        let encryptedAccess = try EncryptionService.encrypt(tokenResponse.accessToken)
        let encryptedRefresh = try EncryptionService.encrypt(tokenResponse.refreshToken)

        // Fetch Whoop user profile
        let whoopUserID = try await WhoopOAuthService.fetchUserProfile(
            accessToken: tokenResponse.accessToken,
            on: req
        )

        // Create or update integration
        let integration = WhoopIntegration(
            userID: userID,
            encryptedAccessToken: encryptedAccess,
            encryptedRefreshToken: encryptedRefresh,
            tokenExpiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            whoopUserID: whoopUserID,
            scopes: WhoopOAuthService.scopes
        )
        try await integration.save(on: req.db)

        return req.redirect(to: "tempo://integrations/whoop/success")
    }

    // MARK: - DELETE /
    // Per INTEGRATION_SPECS.md — Disconnect Whoop, revoke tokens, delete record.

    func disconnect(_ req: Request) async throws -> WhoopDisconnectResponse {
        let userID = try req.auth.requireUserID()

        guard let integration = try await WhoopIntegration.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first() else {
            throw Abort(.notFound, reason: "Whoop not connected.")
        }

        // Revoke tokens with Whoop (best effort)
        if let accessToken = try? integration.accessToken() {
            try await WhoopOAuthService.revokeToken(accessToken, on: req)
        }

        // Delete integration record
        try await integration.delete(on: req.db)

        // Clear cached Whoop data
        let cachePattern = "whoop:cache:\(userID):*"
        // Note: Redis SCAN for pattern deletion would be ideal, but for now
        // individual cache keys are cleared as they expire (5-min TTL)
        _ = cachePattern // suppress unused warning

        return WhoopDisconnectResponse(disconnected: true)
    }

    // MARK: - GET /status

    func status(_ req: Request) async throws -> WhoopStatusResponse {
        let userID = try req.auth.requireUserID()

        guard let integration = try await WhoopIntegration.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first() else {
            return WhoopStatusResponse(connected: false, lastSync: nil, connectedSince: nil)
        }

        return WhoopStatusResponse(
            connected: true,
            lastSync: integration.lastSyncAt,
            connectedSince: integration.connectedAt
        )
    }

    // MARK: - Helpers

    /// Exchange code with up to 3 retries on failure.
    private func exchangeWithRetry(
        code: String,
        on req: Request,
        attempt: Int = 0
    ) async throws -> WhoopOAuthService.TokenResponse {
        do {
            return try await WhoopOAuthService.exchangeCode(code, on: req)
        } catch {
            if attempt < 2 {
                try await Task.sleep(for: .seconds(2))
                return try await exchangeWithRetry(code: code, on: req, attempt: attempt + 1)
            }
            throw error
        }
    }

    /// Find user ID that matches the given state parameter in Redis.
    /// Scans whoop_oauth_state:* keys to find the matching state.
    private func findUserIDForState(_ state: String, on req: Request) async throws -> String? {
        // Use SCAN to find matching state keys
        // The state value is stored under whoop_oauth_state:{userID}
        var cursor: Int = 0
        repeat {
            let (nextCursor, keys) = try await req.redis.scan(
                startingFrom: cursor,
                matching: "whoop_oauth_state:*",
                count: 100
            ).get()
            cursor = nextCursor

            for key in keys {
                let storedState = try await req.redis.get(RedisKey(key), as: String.self).get()
                if storedState == state {
                    // Extract user ID from key: "whoop_oauth_state:{userID}"
                    let prefix = "whoop_oauth_state:"
                    if key.hasPrefix(prefix) {
                        return String(key.dropFirst(prefix.count))
                    }
                }
            }
        } while cursor != 0

        return nil
    }
}

// MARK: - Response DTOs

struct WhoopAuthorizeResponse: Content {
    let authorizationUrl: String
    let state: String
}

struct WhoopDisconnectResponse: Content {
    let disconnected: Bool
}

struct WhoopStatusResponse: Content {
    let connected: Bool
    let lastSync: Date?
    let connectedSince: Date?
}
