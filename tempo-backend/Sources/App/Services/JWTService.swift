import Vapor
import JWT
import Fluent
import Crypto

// MARK: - JWT Service
// Per VAPOR_PROJECT_STRUCTURE.md Section 8 — ES256 JWT issuing and verification.
// Access tokens: 15 min TTL. Refresh tokens: 30 day TTL.

struct JWTService {

    // MARK: - Token TTLs

    static let accessTokenTTL: TimeInterval = 900  // 15 minutes
    static let refreshTokenTTL: TimeInterval = 30 * 24 * 3600  // 30 days

    /// The real TTL, unless local test mode shortened it (`testenv.sh auth ttl`).
    static func accessTTL(_ req: Request) -> TimeInterval {
        req.application.testMode?.accessTokenTTL ?? accessTokenTTL
    }

    // MARK: - Issue Access Token

    static func issueAccessToken(
        userID: String,
        deviceID: String,
        scopes: [String] = ["user"],
        on req: Request
    ) async throws -> String {
        let now = Date()
        let payload = TempoAccessToken(
            subject: .init(value: userID),
            issuer: .init(value: "tempo-api"),
            audience: .init(value: ["app.tempo.ios"]),
            issuedAt: .init(value: now),
            expiration: .init(value: now.addingTimeInterval(accessTTL(req))),
            jti: UUID().uuidString,
            deviceID: deviceID,
            scopes: scopes
        )
        return try await req.jwt.sign(payload)
    }

    // MARK: - Issue Refresh Token

    static func issueRefreshToken(
        userID: String,
        deviceID: String,
        on req: Request
    ) async throws -> (rawToken: String, model: RefreshToken) {
        let rawToken = "rt_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let hash = SHA256.hash(data: Data(rawToken.utf8))
        let tokenHash = hash.compactMap { String(format: "%02x", $0) }.joined()

        let refreshToken = RefreshToken(
            userID: userID,
            deviceID: deviceID,
            tokenHash: tokenHash,
            expiresAt: Date().addingTimeInterval(refreshTokenTTL)
        )

        try await refreshToken.save(on: req.db)
        return (rawToken, refreshToken)
    }

    // MARK: - Issue Token Pair

    static func issueTokenPair(
        userID: String,
        deviceID: String,
        scopes: [String] = ["user"],
        on req: Request
    ) async throws -> AuthTokenResponse {
        let accessToken = try await issueAccessToken(
            userID: userID,
            deviceID: deviceID,
            scopes: scopes,
            on: req
        )

        let (rawRefresh, _) = try await issueRefreshToken(
            userID: userID,
            deviceID: deviceID,
            on: req
        )

        return AuthTokenResponse(
            accessToken: accessToken,
            refreshToken: rawRefresh,
            expiresIn: Int(accessTTL(req))
        )
    }

    // MARK: - Verify Refresh Token

    static func verifyRefreshToken(
        rawToken: String,
        includeRevoked: Bool = false,
        on req: Request
    ) async throws -> RefreshToken {
        let hash = SHA256.hash(data: Data(rawToken.utf8))
        let tokenHash = hash.compactMap { String(format: "%02x", $0) }.joined()

        // `includeRevoked` lets the refresh endpoint SEE an already-rotated
        // token so it can run replay detection (revoke every session). Other
        // callers (logout) keep treating a revoked token as unknown.
        let query = RefreshToken.query(on: req.db).filter(\.$tokenHash == tokenHash)
        if !includeRevoked {
            query.filter(\.$revokedAt == nil)
        }
        guard let token = try await query.first() else {
            throw Abort(.unauthorized, reason: "Invalid refresh token.")
        }

        guard !token.isExpired else {
            throw Abort(.unauthorized, reason: "Refresh token expired.")
        }

        return token
    }

    // MARK: - Revoke Refresh Token

    static func revokeRefreshToken(_ token: RefreshToken, on db: Database) async throws {
        token.revokedAt = Date()
        try await token.save(on: db)
    }

    // MARK: - Revoke All Tokens for User

    static func revokeAllTokens(userID: String, on db: Database) async throws {
        try await RefreshToken.query(on: db)
            .filter(\.$user.$id == userID)
            .filter(\.$revokedAt == nil)
            .set(\.$revokedAt, to: Date())
            .update()
    }
}
