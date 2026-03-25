import Fluent
import Vapor

// MARK: - Refresh Token Model
// Per BACKEND_API.md Section 21 — refresh_tokens table schema.
// Token value is hashed (SHA-256), never stored in plaintext.

final class RefreshToken: Model, Content, @unchecked Sendable {
    static let schema = "refresh_tokens"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "device_id")
    var deviceID: String

    @Field(key: "token_hash")
    var tokenHash: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "revoked_at")
    var revokedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    // ── Initializers ───────────────────────────
    init() {}

    init(
        userID: String,
        deviceID: String,
        tokenHash: String,
        expiresAt: Date
    ) {
        self.id = "rt_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24).description
        self.$user.id = userID
        self.deviceID = deviceID
        self.tokenHash = tokenHash
        self.expiresAt = expiresAt
    }

    // ── Computed ───────────────────────────────

    var isRevoked: Bool { revokedAt != nil }

    var isExpired: Bool { expiresAt < Date() }

    var isValid: Bool { !isRevoked && !isExpired }
}
