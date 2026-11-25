import Fluent
import Vapor

// MARK: - Friend Invite
// One shareable link per user. Anyone who opens it while signed in becomes the
// owner's friend. Revoking it (or rotating) kills the old link.

final class FriendInvite: Model, @unchecked Sendable {
    static let schema = "friend_invites"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userID: String

    @Field(key: "token")
    var token: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @OptionalField(key: "revoked_at")
    var revokedAt: Date?

    init() {}

    init(userID: String, token: String) {
        self.userID = userID
        self.token = token
    }

    var isLive: Bool { revokedAt == nil }

    /// 16 chars from a 36-letter alphabet: ~82 bits, short enough to text.
    static func makeToken() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var rng = SystemRandomNumberGenerator()
        return String((0 ..< 16).map { _ in alphabet.randomElement(using: &rng)! })
    }
}
