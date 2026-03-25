import Vapor
import JWT
import Redis
import Fluent

// MARK: - JWT Auth Middleware
// Per VAPOR_PROJECT_STRUCTURE.md Section 8 — JWTAuthMiddleware.
// Validates Bearer token, extracts user ID, attaches to request.

struct JWTAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // 1. Extract Bearer token
        guard let bearerToken = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Missing Authorization header.")
        }

        // 2. Verify and decode JWT
        let payload: TempoAccessToken
        do {
            payload = try await request.jwt.verify(bearerToken, as: TempoAccessToken.self)
        } catch {
            throw Abort(.unauthorized, reason: "Invalid or expired access token.")
        }

        // 3. Validate issuer and audience
        guard payload.issuer.value == "tempo-api",
              payload.audience.value.contains("app.tempo.ios") else {
            throw Abort(.unauthorized, reason: "Invalid token claims.")
        }

        // 4. Check if token ID is blocklisted in Redis
        if let jti = payload.jti {
            let blocked = try await request.redis.get(RedisKey("blocklist:jti:\(jti)"), as: String.self).get()
            if blocked != nil {
                throw Abort(.unauthorized, reason: "Token has been revoked.")
            }
        }

        // 5. Attach authenticated user info to request
        let authInfo = AuthenticatedUser(
            userID: payload.subject.value,
            scopes: payload.scopes,
            deviceID: payload.deviceID
        )
        request.storage[AuthenticatedUserKey.self] = authInfo

        // 6. Update last_active_at (fire and forget)
        Task {
            if let user = try? await User.find(payload.subject.value, on: request.db) {
                user.lastActiveAt = Date()
                try? await user.save(on: request.db)
            }
        }

        return try await next.respond(to: request)
    }
}

// MARK: - JWT Payload
// Per VAPOR_PROJECT_STRUCTURE.md Section 8 — ES256, 15-min TTL.

struct TempoAccessToken: JWTPayload {
    var subject: SubjectClaim
    var issuer: IssuerClaim
    var audience: AudienceClaim
    var issuedAt: IssuedAtClaim
    var expiration: ExpirationClaim
    var jti: String?
    var deviceID: String
    var scopes: [String]

    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case issuer = "iss"
        case audience = "aud"
        case issuedAt = "iat"
        case expiration = "exp"
        case jti
        case deviceID = "device_id"
        case scopes
    }

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.expiration.verifyNotExpired()
    }
}

// MARK: - Auth Storage

struct AuthenticatedUserKey: StorageKey {
    typealias Value = AuthenticatedUser
}

struct AuthenticatedUser: Sendable {
    let userID: String
    let scopes: [String]
    let deviceID: String

    var isAdmin: Bool { scopes.contains("admin") }
}
