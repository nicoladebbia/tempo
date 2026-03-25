import Fluent
import Vapor

// MARK: - Whoop Sleep Model
// Per BACKEND_API.md — Stores Whoop sleep data (main sleep + naps).

final class WhoopSleep: Model, Content, @unchecked Sendable {
    static let schema = "whoop_sleep"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "whoop_sleep_id")
    var whoopSleepId: Int64

    @Field(key: "date")
    var date: Date

    @Field(key: "start_time")
    var startTime: Date

    @Field(key: "end_time")
    var endTime: Date

    @OptionalField(key: "total_in_bed_milli")
    var totalInBedMilli: Int64?

    @OptionalField(key: "total_awake_milli")
    var totalAwakeMilli: Int64?

    @OptionalField(key: "total_light_sleep_milli")
    var totalLightSleepMilli: Int64?

    @OptionalField(key: "total_slow_wave_sleep_milli")
    var totalSlowWaveSleepMilli: Int64?

    @OptionalField(key: "total_rem_sleep_milli")
    var totalRemSleepMilli: Int64?

    @OptionalField(key: "sleep_cycle_count")
    var sleepCycleCount: Int?

    @OptionalField(key: "disturbance_count")
    var disturbanceCount: Int?

    @OptionalField(key: "baseline_sleep_need_milli")
    var baselineSleepNeedMilli: Int64?

    @OptionalField(key: "need_from_sleep_debt_milli")
    var needFromSleepDebtMilli: Int64?

    @OptionalField(key: "need_from_strain_milli")
    var needFromStrainMilli: Int64?

    @OptionalField(key: "need_from_nap_milli")
    var needFromNapMilli: Int64?

    @OptionalField(key: "respiratory_rate")
    var respiratoryRate: Double?

    @OptionalField(key: "sleep_performance_percentage")
    var sleepPerformancePercentage: Double?

    @OptionalField(key: "sleep_consistency_percentage")
    var sleepConsistencyPercentage: Double?

    @OptionalField(key: "sleep_efficiency_percentage")
    var sleepEfficiencyPercentage: Double?

    @Field(key: "is_nap")
    var isNap: Bool

    @Field(key: "synced_at")
    var syncedAt: Date

    @OptionalField(key: "deleted_at")
    var deletedAt: Date?

    init() {}

    init(
        userID: String,
        whoopSleepId: Int64,
        date: Date,
        startTime: Date,
        endTime: Date,
        isNap: Bool = false
    ) {
        self.id = "slp_" + String.randomHex(length: 8)
        self.$user.id = userID
        self.whoopSleepId = whoopSleepId
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.isNap = isNap
        self.syncedAt = Date()
    }
}
