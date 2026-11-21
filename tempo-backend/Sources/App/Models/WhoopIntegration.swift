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

    /// The phone owns this link: it shared only its WHOOP access token (no refresh token), keeps refreshing it
    /// itself and re-shares every new one. The server must NEVER refresh it: WHOOP refresh tokens are single-use,
    /// so a server refresh would break the phone's own WHOOP login.
    var isPhoneManaged: Bool {
        // Only a refresh token that decrypts to "" counts: an unreadable one is a broken server link, not a phone one.
        (try? refreshToken()) == ""
    }

    /// How long before its expiry a phone-shared token stops being used (it must not run out mid-request).
    static let phoneTokenMargin: TimeInterval = 30

    /// A phone-managed access token that has (nearly) run out: nothing the server can do until the phone shares a new one.
    var isExpiredPhoneLink: Bool {
        isPhoneManaged && tokenExpiresAt <= Date().addingTimeInterval(Self.phoneTokenMargin)
    }

    /// A server-owned link that can no longer work (revoked, or its refresh token can't be read).
    var isDeadServerLink: Bool {
        !isPhoneManaged && (lastSyncStatus == "token_revoked" || (try? refreshToken()) == nil)
    }

    /// Store an access token the phone shared (no refresh token on the server).
    func adoptPhoneToken(accessToken: String, expiresAt: Date) throws {
        self.encryptedAccessToken = try EncryptionService.encrypt(accessToken)
        self.encryptedRefreshToken = try EncryptionService.encrypt("")
        self.tokenExpiresAt = expiresAt
        if lastSyncStatus == "token_revoked" { lastSyncStatus = nil }
    }

    /// Update tokens with new encrypted values.
    func updateTokens(accessToken: String, refreshToken: String, expiresIn: Int) throws {
        self.encryptedAccessToken = try EncryptionService.encrypt(accessToken)
        self.encryptedRefreshToken = try EncryptionService.encrypt(refreshToken)
        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}
