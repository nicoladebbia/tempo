import Fluent
import Vapor

// MARK: - XP Event Model
// Per MODULE_ARENA.md Section 2.1 — XP event tracking.
// Per BACKEND_API.md Section 10.1 — Record XP events.

final class XPEvent: Model, Content, @unchecked Sendable {
    static let schema = "xp_events"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "source")
    var source: String

    @Field(key: "base_xp")
    var baseXP: Int

    @Field(key: "multiplied_xp")
    var multipliedXP: Int

    @Field(key: "streak_multiplier")
    var streakMultiplier: Double

    @OptionalField(key: "metadata")
    var metadata: [String: String]?

    @Field(key: "flagged")
    var flagged: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        userID: String,
        source: String,
        baseXP: Int,
        streakMultiplier: Double = 1.0,
        metadata: [String: String]? = nil
    ) {
        self.$user.id = userID
        self.source = source
        self.baseXP = baseXP
        self.multipliedXP = Int(Double(baseXP) * streakMultiplier)
        self.streakMultiplier = streakMultiplier
        self.metadata = metadata
        self.flagged = false
    }
}
