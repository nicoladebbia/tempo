import Fluent
import Vapor

// MARK: - Challenge Model
// Per MODULE_ARENA.md Section 9 — Challenge system.
// Per BACKEND_API.md Section 10.7 — Challenge endpoints.

final class Challenge: Model, Content, @unchecked Sendable {
    static let schema = "challenges"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "creator_id")
    var creatorID: String

    @Field(key: "title")
    var title: String

    @Field(key: "description")
    var description: String

    @Field(key: "type")
    var type: String // head_to_head, group, daily

    @Field(key: "metric")
    var metric: String // steps, study_hours, xp_total, workout_count, etc.

    @Field(key: "start_date")
    var startDate: Date

    @Field(key: "end_date")
    var endDate: Date

    @Field(key: "max_participants")
    var maxParticipants: Int

    @Field(key: "visibility")
    var visibility: String // friends_only, public

    @Field(key: "status")
    var status: String // upcoming, active, completed

    @Children(for: \.$challenge)
    var members: [ChallengeMember]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        creatorID: String,
        title: String,
        description: String = "",
        type: String = "group",
        metric: String,
        startDate: Date,
        endDate: Date,
        maxParticipants: Int = 10,
        visibility: String = "friends_only"
    ) {
        self.creatorID = creatorID
        self.title = title
        self.description = description
        self.type = type
        self.metric = metric
        self.startDate = startDate
        self.endDate = endDate
        self.maxParticipants = maxParticipants
        self.visibility = visibility
        self.status = "upcoming"
    }
}

// MARK: - Challenge Member Model

final class ChallengeMember: Model, Content, @unchecked Sendable {
    static let schema = "challenge_members"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "challenge_id")
    var challenge: Challenge

    @Field(key: "user_id")
    var userID: String

    @Field(key: "status")
    var status: String // invited, joined, completed, left

    @OptionalField(key: "final_score")
    var finalScore: Double?

    @OptionalField(key: "rank")
    var rank: Int?

    @Timestamp(key: "joined_at", on: .create)
    var joinedAt: Date?

    @OptionalField(key: "completed_at")
    var completedAt: Date?

    init() {}

    init(challengeID: UUID, userID: String, status: String = "joined") {
        self.$challenge.id = challengeID
        self.userID = userID
        self.status = status
    }
}
