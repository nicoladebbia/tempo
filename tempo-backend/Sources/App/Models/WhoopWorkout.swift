import Fluent
import Vapor

// MARK: - Whoop Workout Model
// Per BACKEND_API.md — Stores Whoop workout data.

final class WhoopWorkout: Model, Content, @unchecked Sendable {
    static let schema = "whoop_workouts"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "whoop_workout_id")
    var whoopWorkoutId: Int64

    @Field(key: "date")
    var date: Date

    @Field(key: "sport_id")
    var sportId: Int

    @Field(key: "sport_name")
    var sportName: String

    @Field(key: "start_time")
    var startTime: Date

    @Field(key: "end_time")
    var endTime: Date

    @OptionalField(key: "strain")
    var strain: Double?

    @OptionalField(key: "average_heart_rate")
    var averageHeartRate: Int?

    @OptionalField(key: "max_heart_rate")
    var maxHeartRate: Int?

    @OptionalField(key: "kilojoule")
    var kilojoule: Double?

    @OptionalField(key: "percent_recorded")
    var percentRecorded: Double?

    @OptionalField(key: "distance_meter")
    var distanceMeter: Double?

    @OptionalField(key: "altitude_gain_meter")
    var altitudeGainMeter: Double?

    @OptionalField(key: "altitude_change_meter")
    var altitudeChangeMeter: Double?

    @OptionalField(key: "zone_zero_milli")
    var zoneZeroMilli: Int64?

    @OptionalField(key: "zone_one_milli")
    var zoneOneMilli: Int64?

    @OptionalField(key: "zone_two_milli")
    var zoneTwoMilli: Int64?

    @OptionalField(key: "zone_three_milli")
    var zoneThreeMilli: Int64?

    @OptionalField(key: "zone_four_milli")
    var zoneFourMilli: Int64?

    @OptionalField(key: "zone_five_milli")
    var zoneFiveMilli: Int64?

    @Field(key: "synced_at")
    var syncedAt: Date

    @OptionalField(key: "deleted_at")
    var deletedAt: Date?

    init() {}

    init(
        userID: String,
        whoopWorkoutId: Int64,
        date: Date,
        sportId: Int,
        sportName: String,
        startTime: Date,
        endTime: Date
    ) {
        self.id = "wkt_" + String.randomHex(length: 8)
        self.$user.id = userID
        self.whoopWorkoutId = whoopWorkoutId
        self.date = date
        self.sportId = sportId
        self.sportName = sportName
        self.startTime = startTime
        self.endTime = endTime
        self.syncedAt = Date()
    }
}
