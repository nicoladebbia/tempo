import Fluent
import Vapor

// MARK: - Whoop Integration Model
// Per INTEGRATION_SPECS.md Section 1 — Stores encrypted Whoop OAuth tokens.

final class WhoopIntegration: Model, Content, @unchecked Sendable {
    static let schema = "whoop_integrations"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "encrypted_access_token")
    var encryptedAccessToken: String

    @Field(key: "encrypted_refresh_token")
    var encryptedRefreshToken: String

    @Field(key: "token_expires_at")
    var tokenExpiresAt: Date

    @OptionalField(key: "whoop_user_id")
    var whoopUserID: String?

    @OptionalField(key: "scopes")
    var scopes: String?

    @Field(key: "connected_at")
    var connectedAt: Date

    @OptionalField(key: "last_sync_at")
    var lastSyncAt: Date?

    @OptionalField(key: "last_sync_status")
    var lastSyncStatus: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    // ── Initializers ───────────────────────────
    init() {}

    init(
        userID: String,
        encryptedAccessToken: String,
        encryptedRefreshToken: String,
        tokenExpiresAt: Date,
        whoopUserID: String? = nil,
        scopes: String? = nil
    ) {
        self.id = "whoop_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(20).description
        self.$user.id = userID
        self.encryptedAccessToken = encryptedAccessToken
        self.encryptedRefreshToken = encryptedRefreshToken
        self.tokenExpiresAt = tokenExpiresAt
        self.whoopUserID = whoopUserID
        self.scopes = scopes
        self.connectedAt = Date()
    }

    // ── Computed ───────────────────────────────

    /// Access token is about to expire (within 5 minutes).
    var needsRefresh: Bool {
        tokenExpiresAt.timeIntervalSinceNow < 300
    }

    /// Decrypt and return the access token.
    func accessToken() throws -> String {
        try EncryptionService.decrypt(encryptedAccessToken)
    }

    /// Decrypt and return the refresh token.
    func refreshToken() throws -> String {
        try EncryptionService.decrypt(encryptedRefreshToken)
    }

    /// Update tokens with new encrypted values.
    func updateTokens(accessToken: String, refreshToken: String, expiresIn: Int) throws {
        self.encryptedAccessToken = try EncryptionService.encrypt(accessToken)
        self.encryptedRefreshToken = try EncryptionService.encrypt(refreshToken)
        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}
