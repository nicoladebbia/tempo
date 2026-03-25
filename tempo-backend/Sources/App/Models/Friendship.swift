import Fluent
import Vapor

// MARK: - Friendship Model
// Per MODULE_ARENA.md Section 9 — Friend system.
// Per BACKEND_API.md Section 10.6 — Friend endpoints.

final class Friendship: Model, Content, @unchecked Sendable {
    static let schema = "friendships"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_a_id")
    var userAID: String

    @Field(key: "user_b_id")
    var userBID: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(userAID: String, userBID: String) {
        // Enforce user_a < user_b for unique constraint
        if userAID < userBID {
            self.userAID = userAID
            self.userBID = userBID
        } else {
            self.userAID = userBID
            self.userBID = userAID
        }
    }
}

// MARK: - Friend Request Model

final class FriendRequest: Model, Content, @unchecked Sendable {
    static let schema = "friend_requests"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "from_user_id")
    var fromUserID: String

    @Field(key: "to_user_id")
    var toUserID: String

    @Field(key: "status")
    var status: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @OptionalField(key: "responded_at")
    var respondedAt: Date?

    init() {}

    init(fromUserID: String, toUserID: String) {
        self.fromUserID = fromUserID
        self.toUserID = toUserID
        self.status = "pending"
    }
}
