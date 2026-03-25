import Fluent
import Vapor

// MARK: - NutriTrack Integration Model
// Per INTEGRATION_SPECS.md Section 3.1 — Stores encrypted NutriTrack PIN + base URL.
// PIN-based auth (4-8 digits), AES-256-GCM encrypted via EncryptionService.

final class NutriTrackIntegration: Model, Content, @unchecked Sendable {
    static let schema = "nutritrack_integrations"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "base_url")
    var baseURL: String

    @Field(key: "encrypted_pin")
    var encryptedPin: String

    @OptionalField(key: "session_cookie")
    var sessionCookie: String?

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
        baseURL: String,
        encryptedPin: String
    ) {
        self.id = "nt_" + UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(20)
            .description
        self.$user.id = userID
        self.baseURL = baseURL
        self.encryptedPin = encryptedPin
        self.connectedAt = Date()
    }

    // ── Computed ───────────────────────────────

    /// Decrypt and return the NutriTrack PIN.
    func pin() throws -> String {
        try EncryptionService.decryptNutriTrack(encryptedPin)
    }

    /// Update the stored PIN with a new encrypted value.
    func updatePin(_ newPin: String) throws {
        self.encryptedPin = try EncryptionService.encryptNutriTrack(newPin)
    }
}
