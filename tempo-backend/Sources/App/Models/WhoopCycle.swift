import Fluent
import Vapor

// MARK: - Whoop Cycle Model
// Per BACKEND_API.md — Stores Whoop cycle/strain data.

final class WhoopCycle: Model, Content, @unchecked Sendable {
    static let schema = "whoop_cycles"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "whoop_cycle_id")
    var whoopCycleId: Int64

    @Field(key: "date")
    var date: Date

    @Field(key: "start_time")
    var startTime: Date

    @OptionalField(key: "end_time")
    var endTime: Date?

    @OptionalField(key: "strain")
    var strain: Double?

    @OptionalField(key: "kilojoule")
    var kilojoule: Double?

    @OptionalField(key: "average_heart_rate")
    var averageHeartRate: Int?

    @OptionalField(key: "max_heart_rate")
    var maxHeartRate: Int?

    @Field(key: "synced_at")
    var syncedAt: Date

    @OptionalField(key: "deleted_at")
    var deletedAt: Date?

    init() {}

    init(
        userID: String,
        whoopCycleId: Int64,
        date: Date,
        startTime: Date,
        endTime: Date? = nil
    ) {
        self.id = "cyc_" + String.randomHex(length: 8)
        self.$user.id = userID
        self.whoopCycleId = whoopCycleId
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.syncedAt = Date()
    }
}
