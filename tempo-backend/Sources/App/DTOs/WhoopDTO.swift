import Vapor

// MARK: - Whoop Response DTOs
// Per BACKEND_API.md Sections 5.6-5.9 — Tempo's response format for Whoop data.

// MARK: - Recovery DTO

struct WhoopRecoveryDTO: Content {
    let id: String
    let whoopCycleId: Int64
    let date: String
    let recoveryScore: Double
    let restingHeartRate: Double
    let hrvRmssdMilli: Double
    let spo2Percentage: Double?
    let skinTempCelsius: Double?
    let userCalibrating: Bool
    let scoreState: String
    let syncedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case whoopCycleId = "whoop_cycle_id"
        case date
        case recoveryScore = "recovery_score"
        case restingHeartRate = "resting_heart_rate"
        case hrvRmssdMilli = "hrv_rmssd_milli"
        case spo2Percentage = "spo2_percentage"
        case skinTempCelsius = "skin_temp_celsius"
        case userCalibrating = "user_calibrating"
        case scoreState = "score_state"
        case syncedAt = "synced_at"
    }

    /// Map from Whoop API record to Tempo DTO.
    init(from record: WhoopAPIRecoveryRecord) {
        self.id = "rec_" + String.randomHex(length: 8)
        self.whoopCycleId = record.cycleId
        self.date = record.createdAt.prefix(10).description // YYYY-MM-DD
        self.recoveryScore = record.score?.recoveryScore ?? 0
        self.restingHeartRate = record.score?.restingHeartRate ?? 0
        self.hrvRmssdMilli = record.score?.hrvRmssdMilli ?? 0
        self.spo2Percentage = record.score?.spo2Percentage
        self.skinTempCelsius = record.score?.skinTempCelsius
        self.userCalibrating = record.score?.userCalibrating ?? false
        self.scoreState = record.scoreState
        self.syncedAt = Date()
    }
}

// MARK: - Sleep DTO

struct WhoopSleepDTO: Content {
    let id: String
    let whoopSleepId: Int64
    let date: String
    let startTime: String
    let endTime: String
    let score: WhoopSleepScoreDTO?
    let nap: Bool
    let scoreState: String
    let syncedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case whoopSleepId = "whoop_sleep_id"
        case date
        case startTime = "start_time"
        case endTime = "end_time"
        case score
        case nap
        case scoreState = "score_state"
        case syncedAt = "synced_at"
    }

    init(from record: WhoopAPISleepRecord) {
        self.id = "slp_" + String.randomHex(length: 8)
        self.whoopSleepId = record.id
        // Date based on end time (wake-up time)
        self.date = record.end.prefix(10).description
        self.startTime = record.start
        self.endTime = record.end
        self.score = record.score.map { WhoopSleepScoreDTO(from: $0) }
        self.nap = record.nap
        self.scoreState = record.scoreState
        self.syncedAt = Date()
    }
}

struct WhoopSleepScoreDTO: Content {
    let stageSummary: WhoopStageSummaryDTO?
    let sleepNeeded: WhoopSleepNeededDTO?
    let respiratoryRate: Double?
    let sleepPerformancePercentage: Double?
    let sleepConsistencyPercentage: Double?
    let sleepEfficiencyPercentage: Double?

    enum CodingKeys: String, CodingKey {
        case stageSummary = "stage_summary"
        case sleepNeeded = "sleep_needed"
        case respiratoryRate = "respiratory_rate"
        case sleepPerformancePercentage = "sleep_performance_percentage"
        case sleepConsistencyPercentage = "sleep_consistency_percentage"
        case sleepEfficiencyPercentage = "sleep_efficiency_percentage"
    }

    init(from score: WhoopAPISleepScore) {
        self.stageSummary = score.stageSummary.map { WhoopStageSummaryDTO(from: $0) }
        self.sleepNeeded = score.sleepNeeded.map { WhoopSleepNeededDTO(from: $0) }
        self.respiratoryRate = score.respiratoryRate
        self.sleepPerformancePercentage = score.sleepPerformancePercentage
        self.sleepConsistencyPercentage = score.sleepConsistencyPercentage
        self.sleepEfficiencyPercentage = score.sleepEfficiencyPercentage
    }
}

struct WhoopStageSummaryDTO: Content {
    let totalInBedTimeMilli: Int64
    let totalAwakeTimeMilli: Int64
    let totalLightSleepTimeMilli: Int64
    let totalSlowWaveSleepTimeMilli: Int64
    let totalRemSleepTimeMilli: Int64
    let sleepCycleCount: Int
    let disturbanceCount: Int

    enum CodingKeys: String, CodingKey {
        case totalInBedTimeMilli = "total_in_bed_time_milli"
        case totalAwakeTimeMilli = "total_awake_time_milli"
        case totalLightSleepTimeMilli = "total_light_sleep_time_milli"
        case totalSlowWaveSleepTimeMilli = "total_slow_wave_sleep_time_milli"
        case totalRemSleepTimeMilli = "total_rem_sleep_time_milli"
        case sleepCycleCount = "sleep_cycle_count"
        case disturbanceCount = "disturbance_count"
    }

    init(from summary: WhoopAPIStageSummary) {
        self.totalInBedTimeMilli = summary.totalInBedTimeMilli
        self.totalAwakeTimeMilli = summary.totalAwakeTimeMilli
        self.totalLightSleepTimeMilli = summary.totalLightSleepTimeMilli
        self.totalSlowWaveSleepTimeMilli = summary.totalSlowWaveSleepTimeMilli
        self.totalRemSleepTimeMilli = summary.totalRemSleepTimeMilli
        self.sleepCycleCount = summary.sleepCycleCount
        self.disturbanceCount = summary.disturbanceCount
    }
}

struct WhoopSleepNeededDTO: Content {
    let baselineMilli: Int64
    let needFromSleepDebtMilli: Int64
    let needFromRecentStrainMilli: Int64
    let needFromRecentNapMilli: Int64

    enum CodingKeys: String, CodingKey {
        case baselineMilli = "baseline_milli"
        case needFromSleepDebtMilli = "need_from_sleep_debt_milli"
        case needFromRecentStrainMilli = "need_from_recent_strain_milli"
        case needFromRecentNapMilli = "need_from_recent_nap_milli"
    }

    init(from needed: WhoopAPISleepNeeded) {
        self.baselineMilli = needed.baselineMilli
        self.needFromSleepDebtMilli = needed.needFromSleepDebtMilli
        self.needFromRecentStrainMilli = needed.needFromRecentStrainMilli
        self.needFromRecentNapMilli = needed.needFromRecentNapMilli
    }
}

// MARK: - Workout DTO

struct WhoopWorkoutDTO: Content {
    let id: String
    let whoopWorkoutId: Int64
    let date: String
    let sportId: Int
    let sportName: String
    let startTime: String
    let endTime: String
    let score: WhoopWorkoutScoreDTO?
    let source: String?
    let syncedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case whoopWorkoutId = "whoop_workout_id"
        case date
        case sportId = "sport_id"
        case sportName = "sport_name"
        case startTime = "start_time"
        case endTime = "end_time"
        case score
        case source
        case syncedAt = "synced_at"
    }

    init(from record: WhoopAPIWorkoutRecord) {
        self.id = "wkt_" + String.randomHex(length: 8)
        self.whoopWorkoutId = record.id
        self.date = record.start.prefix(10).description
        self.sportId = record.sportId
        self.sportName = Self.sportName(for: record.sportId)
        self.startTime = record.start
        self.endTime = record.end
        self.score = record.score.map { WhoopWorkoutScoreDTO(from: $0) }
        self.source = record.source
        self.syncedAt = Date()
    }

    /// Per INTEGRATION_SPECS.md Section 1.3.3 — Sport ID mapping.
    static func sportName(for sportId: Int) -> String {
        switch sportId {
        case 0: return "Running"
        case 1: return "Cycling"
        case 33: return "Weightlifting"
        case 44: return "Functional Fitness"
        case 48: return "Football (Soccer)"
        case 52: return "Walking"
        case 55: return "HIIT"
        case 56: return "Yoga"
        case 63: return "Stretching"
        case 71: return "Swimming"
        case 82: return "Lacrosse"
        default: return "Other"
        }
    }
}

struct WhoopWorkoutScoreDTO: Content {
    let strain: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let kilojoule: Double?
    let distanceMeter: Double?
    let zoneDuration: WhoopZoneDurationDTO?

    enum CodingKeys: String, CodingKey {
        case strain
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case kilojoule
        case distanceMeter = "distance_meter"
        case zoneDuration = "zone_duration"
    }

    init(from score: WhoopAPIWorkoutScore) {
        self.strain = score.strain
        self.averageHeartRate = score.averageHeartRate
        self.maxHeartRate = score.maxHeartRate
        self.kilojoule = score.kilojoule
        self.distanceMeter = score.distanceMeter
        self.zoneDuration = score.zoneDuration.map { WhoopZoneDurationDTO(from: $0) }
    }
}

struct WhoopZoneDurationDTO: Content {
    let zoneZeroMilli: Int64
    let zoneOneMilli: Int64
    let zoneTwoMilli: Int64
    let zoneThreeMilli: Int64
    let zoneFourMilli: Int64
    let zoneFiveMilli: Int64

    enum CodingKeys: String, CodingKey {
        case zoneZeroMilli = "zone_zero_milli"
        case zoneOneMilli = "zone_one_milli"
        case zoneTwoMilli = "zone_two_milli"
        case zoneThreeMilli = "zone_three_milli"
        case zoneFourMilli = "zone_four_milli"
        case zoneFiveMilli = "zone_five_milli"
    }

    init(from zone: WhoopAPIZoneDuration) {
        self.zoneZeroMilli = zone.zoneZeroMilli
        self.zoneOneMilli = zone.zoneOneMilli
        self.zoneTwoMilli = zone.zoneTwoMilli
        self.zoneThreeMilli = zone.zoneThreeMilli
        self.zoneFourMilli = zone.zoneFourMilli
        self.zoneFiveMilli = zone.zoneFiveMilli
    }
}

// MARK: - Cycle DTO

struct WhoopCycleDTO: Content {
    let id: String
    let whoopCycleId: Int64
    let date: String
    let startTime: String
    let endTime: String?
    let strain: Double?
    let kilojoule: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let scoreState: String
    let syncedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case whoopCycleId = "whoop_cycle_id"
        case date
        case startTime = "start_time"
        case endTime = "end_time"
        case strain
        case kilojoule
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case scoreState = "score_state"
        case syncedAt = "synced_at"
    }

    init(from record: WhoopAPICycleRecord) {
        self.id = "cyc_" + String.randomHex(length: 8)
        self.whoopCycleId = record.id
        // Per INTEGRATION_SPECS.md — use start date, but if before 4 AM assign to previous day
        self.date = record.start.prefix(10).description
        self.startTime = record.start
        self.endTime = record.end
        self.strain = record.score?.strain
        self.kilojoule = record.score?.kilojoule
        self.averageHeartRate = record.score?.averageHeartRate
        self.maxHeartRate = record.score?.maxHeartRate
        self.scoreState = record.scoreState
        self.syncedAt = Date()
    }
}

// MARK: - Date Query DTO

struct WhoopDateQuery: Content {
    var date: String?
    var startDate: String?
    var endDate: String?

    enum CodingKeys: String, CodingKey {
        case date
        case startDate = "start_date"
        case endDate = "end_date"
    }
}
