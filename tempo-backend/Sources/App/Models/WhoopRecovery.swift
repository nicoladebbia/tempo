import Fluent
import Vapor

// MARK: - Whoop Recovery Model
// Per BACKEND_API.md — Stores Whoop recovery data (synced from API/webhooks).

final class WhoopRecovery: Model, Content, @unchecked Sendable {
    static let schema = "whoop_recovery"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "whoop_cycle_id")
    var whoopCycleId: Int64

    @Field(key: "date")
    var date: Date

    @OptionalField(key: "recovery_score")
    var recoveryScore: Int?

    @OptionalField(key: "resting_heart_rate")
    var restingHeartRate: Int?

    @OptionalField(key: "hrv_rmssd_milli")
    var hrvRmssdMilli: Double?

    @OptionalField(key: "spo2_percentage")
    var spo2Percentage: Double?

    @OptionalField(key: "skin_temp_celsius")
    var skinTempCelsius: Double?

    @Field(key: "user_calibrating")
    var userCalibrating: Bool

    @Field(key: "synced_at")
    var syncedAt: Date

    @OptionalField(key: "deleted_at")
    var deletedAt: Date?

    init() {}

    init(
        userID: String,
        whoopCycleId: Int64,
        date: Date,
        recoveryScore: Int? = nil,
        restingHeartRate: Int? = nil,
        hrvRmssdMilli: Double? = nil,
        spo2Percentage: Double? = nil,
        skinTempCelsius: Double? = nil,
        userCalibrating: Bool = false
    ) {
        self.id = "rec_" + String.randomHex(length: 8)
        self.$user.id = userID
        self.whoopCycleId = whoopCycleId
        self.date = date
        self.recoveryScore = recoveryScore
        self.restingHeartRate = restingHeartRate
        self.hrvRmssdMilli = hrvRmssdMilli
        self.spo2Percentage = spo2Percentage
        self.skinTempCelsius = skinTempCelsius
        self.userCalibrating = userCalibrating
        self.syncedAt = Date()
    }
}
