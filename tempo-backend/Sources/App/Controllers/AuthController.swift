import Vapor
import Fluent
import Crypto
import Redis

// MARK: - Auth Controller
// Per BACKEND_API.md Section 2 — Authentication endpoints.
// POST /v1/auth/apple   — Sign in with Apple (register or login)
// POST /v1/auth/refresh — Token refresh (rotation)
// POST /v1/auth/logout  — Revoke tokens

struct AuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // Public routes (no JWT required)
        routes.post("apple", use: signInWithApple)
        routes.post("refresh", use: refreshToken)

        // Protected routes (JWT required)
        let protected = routes.grouped(JWTAuthMiddleware())
        protected.post("logout", use: logout)
    }

    // MARK: - POST /v1/auth/apple
    // Per BACKEND_API.md Section 2.1

    func signInWithApple(_ req: Request) async throws -> AuthTokenResponse {
        try AppleSignInRequest.validate(content: req)
        let body = try req.content.decode(AppleSignInRequest.self)

        // Extract device ID from header
        guard let deviceID = req.headers.first(name: "X-Device-Id") else {
            throw Abort(.badRequest, reason: "Missing X-Device-Id header.")
        }

        // Verify Apple identity token
        let applePayload = try await AppleAuthService.verifyIdentityToken(
            body.identityToken,
            expectedNonce: body.nonce,
            on: req
        )

        let appleUserID = applePayload.subject.value

        // Look up existing user or create new one
        // Per BACKEND_API.md Section 2.1 step 6
        let user: User

        if let existingUser = try await User.query(on: req.db)
            .filter(\.$appleUserID == appleUserID)
            .first() {

            // Check if account is soft-deleted
            if existingUser.isDeleted {
                if existingUser.isRecoverable {
                    throw Abort(.conflict, reason: "Account in recovery window. Use POST /v1/auth/recover.")
                }
                // Past recovery window — create fresh account
                let newUser = User(
                    appleUserID: appleUserID,
                    username: generateUsername(),
                    displayName: buildDisplayName(firstName: body.firstName, lastName: body.lastName)
                )
                try await newUser.save(on: req.db)
                user = newUser
            } else {
                // Update display name if provided and user's is empty
                if existingUser.displayName.isEmpty,
                   let firstName = body.firstName {
                    existingUser.displayName = buildDisplayName(firstName: firstName, lastName: body.lastName)
                    try await existingUser.save(on: req.db)
                }
                user = existingUser
            }
        } else {
            // Create new user
            let newUser = User(
                appleUserID: appleUserID,
                username: generateUsername(),
                displayName: buildDisplayName(firstName: body.firstName, lastName: body.lastName)
            )
            try await newUser.save(on: req.db)
            user = newUser
        }

        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "User ID unavailable.")
        }

        // Issue token pair
        let tokenResponse = try await JWTService.issueTokenPair(
            userID: userID,
            deviceID: deviceID,
            on: req
        )

        return tokenResponse
    }

    // MARK: - POST /v1/auth/refresh
    // Per BACKEND_API.md Section 2.2

    func refreshToken(_ req: Request) async throws -> AuthTokenResponse {
        try RefreshTokenRequest.validate(content: req)
        let body = try req.content.decode(RefreshTokenRequest.self)

        // Extract device ID from header
        guard let deviceID = req.headers.first(name: "X-Device-Id") else {
            throw Abort(.badRequest, reason: "Missing X-Device-Id header.")
        }

        // Verify refresh token
        let token = try await JWTService.verifyRefreshToken(rawToken: body.refreshToken, on: req)

        // Per BACKEND_API.md Section 2.2 step 2 — device_id must match
        guard token.deviceID == deviceID else {
            // Device mismatch — possible token theft, revoke all tokens
            try await JWTService.revokeAllTokens(userID: token.$user.id, on: req.db)
            throw Abort(.unauthorized, reason: "Device ID mismatch. All sessions invalidated.")
        }

        // Check if token was already revoked (replay detection)
        // Per BACKEND_API.md Section 2.2 step 5
        if token.isRevoked {
            try await JWTService.revokeAllTokens(userID: token.$user.id, on: req.db)
            throw Abort(.unauthorized, reason: "Replay detected. All sessions invalidated.")
        }

        // Revoke old token (single-use rotation)
        try await JWTService.revokeRefreshToken(token, on: req.db)

        // Issue new token pair
        let tokenResponse = try await JWTService.issueTokenPair(
            userID: token.$user.id,
            deviceID: deviceID,
            on: req
        )

        return tokenResponse
    }

    // MARK: - POST /v1/auth/logout
    // Per BACKEND_API.md Section 2.4

    func logout(_ req: Request) async throws -> LogoutResponse {
        let userID = try req.auth.requireUserID()
        let body = try? req.content.decode(LogoutRequest.self)

        var revokedCount = 0

        if body?.allDevices == true {
            // Revoke all tokens for user
            let tokens = try await RefreshToken.query(on: req.db)
                .filter(\.$user.$id == userID)
                .filter(\.$revokedAt == nil)
                .all()
            revokedCount = tokens.count
            try await JWTService.revokeAllTokens(userID: userID, on: req.db)
        } else if let refreshTokenRaw = body?.refreshToken {
            // Revoke specific token
            if let token = try? await JWTService.verifyRefreshToken(rawToken: refreshTokenRaw, on: req) {
                try await JWTService.revokeRefreshToken(token, on: req.db)
                revokedCount = 1
            }
        }

        // Blocklist current access token JTI in Redis
        // Per VAPOR_PROJECT_STRUCTURE.md Section 8 — blocklist for immediate revocation
        if let bearerToken = req.headers.bearerAuthorization?.token {
            if let payload = try? await req.jwt.verify(bearerToken, as: TempoAccessToken.self),
               let jti = payload.jti {
                let ttl = max(1, Int(payload.expiration.value.timeIntervalSinceNow))
                _ = try? await req.redis.setex(
                    RedisKey("blocklist:jti:\(jti)"),
                    to: "revoked",
                    expirationInSeconds: ttl
                ).get()
            }
        }

        return LogoutResponse(revokedCount: revokedCount)
    }

    // MARK: - Helpers

    /// Generate default username per BACKEND_API.md: "user_<random8>"
    private func generateUsername() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let random = (0..<8).map { _ in chars.randomElement()! }
        return "user_" + String(random)
    }

    /// Build display name from Apple-provided first/last name.
    private func buildDisplayName(firstName: String?, lastName: String?) -> String {
        [firstName, lastName]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

// MARK: - Logout Response DTO

struct LogoutResponse: Content {
    let revokedCount: Int
}
