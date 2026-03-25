import Vapor
import Fluent
@preconcurrency import Redis

// MARK: - Whoop API Service
// Per INTEGRATION_SPECS.md Section 1.2/1.3 — Actor-based Whoop API v2 client
// with automatic token refresh and per-user deduplication.

actor WhoopAPIService {

    // Singleton for app-wide use
    static let shared = WhoopAPIService()

    // In-flight refresh tasks keyed by user ID to prevent concurrent refreshes
    private var refreshTasks: [String: Task<String, Error>] = [:]

    // MARK: - Whoop API v2 Endpoints

    private static let baseURL = "https://api.prod.whoop.com/developer/v1"

    // MARK: - Public API

    /// Fetch recovery data for a date range.
    /// Per INTEGRATION_SPECS.md Section 1.3.1
    func fetchRecovery(
        for userID: String,
        startDate: String,
        endDate: String,
        on req: Request
    ) async throws -> WhoopAPIRecoveryResponse {
        let token = try await validAccessToken(for: userID, on: req)
        let url = "\(Self.baseURL)/recovery?start=\(startDate)&end=\(endDate)"

        let response = try await req.client.get(URI(string: url)) { clientReq in
            clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
        }

        guard response.status == .ok else {
            if response.status == .unauthorized {
                // Token may have been revoked — try refresh once
                let freshToken = try await forceRefreshToken(for: userID, on: req)
                let retryResponse = try await req.client.get(URI(string: url)) { clientReq in
                    clientReq.headers.bearerAuthorization = BearerAuthorization(token: freshToken)
                }
                guard retryResponse.status == .ok else {
                    throw Abort(.badGateway, reason: "Whoop recovery fetch failed: \(retryResponse.status)")
                }
                return try retryResponse.content.decode(WhoopAPIRecoveryResponse.self)
            }
            throw Abort(.badGateway, reason: "Whoop recovery fetch failed: \(response.status)")
        }

        req.logger.info("Whoop API: fetched recovery for user \(userID)")
        return try response.content.decode(WhoopAPIRecoveryResponse.self)
    }

    /// Fetch sleep data for a date range.
    /// Per INTEGRATION_SPECS.md Section 1.3.2
    func fetchSleep(
        for userID: String,
        startDate: String,
        endDate: String,
        on req: Request
    ) async throws -> WhoopAPISleepResponse {
        let token = try await validAccessToken(for: userID, on: req)
        let url = "\(Self.baseURL)/activity/sleep?start=\(startDate)&end=\(endDate)"

        let response = try await req.client.get(URI(string: url)) { clientReq in
            clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
        }

        guard response.status == .ok else {
            if response.status == .unauthorized {
                let freshToken = try await forceRefreshToken(for: userID, on: req)
                let retryResponse = try await req.client.get(URI(string: url)) { clientReq in
                    clientReq.headers.bearerAuthorization = BearerAuthorization(token: freshToken)
                }
                guard retryResponse.status == .ok else {
                    throw Abort(.badGateway, reason: "Whoop sleep fetch failed: \(retryResponse.status)")
                }
                return try retryResponse.content.decode(WhoopAPISleepResponse.self)
            }
            throw Abort(.badGateway, reason: "Whoop sleep fetch failed: \(response.status)")
        }

        req.logger.info("Whoop API: fetched sleep for user \(userID)")
        return try response.content.decode(WhoopAPISleepResponse.self)
    }

    /// Fetch workouts for a date range.
    /// Per INTEGRATION_SPECS.md Section 1.3.3
    func fetchWorkouts(
        for userID: String,
        startDate: String,
        endDate: String,
        on req: Request
    ) async throws -> WhoopAPIWorkoutResponse {
        let token = try await validAccessToken(for: userID, on: req)
        let url = "\(Self.baseURL)/activity/workout?start=\(startDate)&end=\(endDate)"

        let response = try await req.client.get(URI(string: url)) { clientReq in
            clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
        }

        guard response.status == .ok else {
            if response.status == .unauthorized {
                let freshToken = try await forceRefreshToken(for: userID, on: req)
                let retryResponse = try await req.client.get(URI(string: url)) { clientReq in
                    clientReq.headers.bearerAuthorization = BearerAuthorization(token: freshToken)
                }
                guard retryResponse.status == .ok else {
                    throw Abort(.badGateway, reason: "Whoop workout fetch failed: \(retryResponse.status)")
                }
                return try retryResponse.content.decode(WhoopAPIWorkoutResponse.self)
            }
            throw Abort(.badGateway, reason: "Whoop workout fetch failed: \(response.status)")
        }

        req.logger.info("Whoop API: fetched workouts for user \(userID)")
        return try response.content.decode(WhoopAPIWorkoutResponse.self)
    }

    /// Fetch cycle/strain data for a date range.
    /// Per INTEGRATION_SPECS.md Section 1.3.4
    func fetchCycles(
        for userID: String,
        startDate: String,
        endDate: String,
        on req: Request
    ) async throws -> WhoopAPICycleResponse {
        let token = try await validAccessToken(for: userID, on: req)
        let url = "\(Self.baseURL)/cycle?start=\(startDate)&end=\(endDate)"

        let response = try await req.client.get(URI(string: url)) { clientReq in
            clientReq.headers.bearerAuthorization = BearerAuthorization(token: token)
        }

        guard response.status == .ok else {
            if response.status == .unauthorized {
                let freshToken = try await forceRefreshToken(for: userID, on: req)
                let retryResponse = try await req.client.get(URI(string: url)) { clientReq in
                    clientReq.headers.bearerAuthorization = BearerAuthorization(token: freshToken)
                }
                guard retryResponse.status == .ok else {
                    throw Abort(.badGateway, reason: "Whoop cycle fetch failed: \(retryResponse.status)")
                }
                return try retryResponse.content.decode(WhoopAPICycleResponse.self)
            }
            throw Abort(.badGateway, reason: "Whoop cycle fetch failed: \(response.status)")
        }

        req.logger.info("Whoop API: fetched cycles for user \(userID)")
        return try response.content.decode(WhoopAPICycleResponse.self)
    }

    // MARK: - Token Management
    // Per INTEGRATION_SPECS.md Section 1.2 — Actor-based deduplication.

    /// Returns a valid access token, refreshing if needed.
    /// If a refresh is already in-flight for this user, awaits that task.
    private func validAccessToken(for userID: String, on req: Request) async throws -> String {
        // If a refresh is already in-flight, await it
        if let existingTask = refreshTasks[userID] {
            return try await existingTask.value
        }

        guard let integration = try await WhoopIntegration.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first() else {
            throw Abort(.notFound, reason: "Whoop not connected.")
        }

        let accessToken = try integration.accessToken()

        // If token expires in more than 5 minutes, it's still valid
        if !integration.needsRefresh {
            return accessToken
        }

        // Token is expiring soon or already expired — refresh
        let task = Task<String, Error> {
            defer { refreshTasks[userID] = nil }
            return try await performRefresh(for: integration, on: req)
        }
        refreshTasks[userID] = task
        return try await task.value
    }

    /// Force a token refresh (used when API returns 401).
    private func forceRefreshToken(for userID: String, on req: Request) async throws -> String {
        if let existingTask = refreshTasks[userID] {
            return try await existingTask.value
        }

        guard let integration = try await WhoopIntegration.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first() else {
            throw Abort(.notFound, reason: "Whoop not connected.")
        }

        let task = Task<String, Error> {
            defer { refreshTasks[userID] = nil }
            return try await performRefresh(for: integration, on: req)
        }
        refreshTasks[userID] = task
        return try await task.value
    }

    /// Perform the actual token refresh against Whoop's token endpoint.
    private func performRefresh(
        for integration: WhoopIntegration,
        on req: Request
    ) async throws -> String {
        let refreshToken = try integration.refreshToken()

        let tokenResponse: WhoopOAuthService.TokenResponse
        do {
            tokenResponse = try await WhoopOAuthService.refreshAccessToken(
                refreshToken: refreshToken,
                on: req
            )
        } catch {
            // Refresh failed — mark as token_revoked
            integration.lastSyncStatus = "token_revoked"
            try await integration.save(on: req.db)
            throw error
        }

        // Update tokens in database
        try integration.updateTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresIn: tokenResponse.expiresIn
        )
        try await integration.save(on: req.db)

        return tokenResponse.accessToken
    }
}

// MARK: - Whoop API v2 Raw Response DTOs
// These map directly to Whoop's API v2 JSON shapes.

struct WhoopAPIRecoveryResponse: Content {
    let records: [WhoopAPIRecoveryRecord]
    let nextToken: String?

    enum CodingKeys: String, CodingKey {
        case records
        case nextToken = "next_token"
    }
}

struct WhoopAPIRecoveryRecord: Content {
    let cycleId: Int64
    let sleepId: Int64?
    let userId: Int
    let createdAt: String
    let updatedAt: String
    let scoreState: String
    let score: WhoopAPIRecoveryScore?

    enum CodingKeys: String, CodingKey {
        case cycleId = "cycle_id"
        case sleepId = "sleep_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case scoreState = "score_state"
        case score
    }
}

struct WhoopAPIRecoveryScore: Content {
    let userCalibrating: Bool
    let recoveryScore: Double
    let restingHeartRate: Double
    let hrvRmssdMilli: Double
    let spo2Percentage: Double?
    let skinTempCelsius: Double?

    enum CodingKeys: String, CodingKey {
        case userCalibrating = "user_calibrating"
        case recoveryScore = "recovery_score"
        case restingHeartRate = "resting_heart_rate"
        case hrvRmssdMilli = "hrv_rmssd_milli"
        case spo2Percentage = "spo2_percentage"
        case skinTempCelsius = "skin_temp_celsius"
    }
}

struct WhoopAPISleepResponse: Content {
    let records: [WhoopAPISleepRecord]
    let nextToken: String?

    enum CodingKeys: String, CodingKey {
        case records
        case nextToken = "next_token"
    }
}

struct WhoopAPISleepRecord: Content {
    let id: Int64
    let userId: Int
    let createdAt: String
    let updatedAt: String
    let start: String
    let end: String
    let timezoneOffset: String?
    let nap: Bool
    let scoreState: String
    let score: WhoopAPISleepScore?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start, end
        case timezoneOffset = "timezone_offset"
        case nap
        case scoreState = "score_state"
        case score
    }
}

struct WhoopAPISleepScore: Content {
    let stageSummary: WhoopAPIStageSummary?
    let sleepNeeded: WhoopAPISleepNeeded?
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
}

struct WhoopAPIStageSummary: Content {
    let totalInBedTimeMilli: Int64
    let totalAwakeTimeMilli: Int64
    let totalNoDataTimeMilli: Int64?
    let totalLightSleepTimeMilli: Int64
    let totalSlowWaveSleepTimeMilli: Int64
    let totalRemSleepTimeMilli: Int64
    let sleepCycleCount: Int
    let disturbanceCount: Int

    enum CodingKeys: String, CodingKey {
        case totalInBedTimeMilli = "total_in_bed_time_milli"
        case totalAwakeTimeMilli = "total_awake_time_milli"
        case totalNoDataTimeMilli = "total_no_data_time_milli"
        case totalLightSleepTimeMilli = "total_light_sleep_time_milli"
        case totalSlowWaveSleepTimeMilli = "total_slow_wave_sleep_time_milli"
        case totalRemSleepTimeMilli = "total_rem_sleep_time_milli"
        case sleepCycleCount = "sleep_cycle_count"
        case disturbanceCount = "disturbance_count"
    }
}

struct WhoopAPISleepNeeded: Content {
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
}

struct WhoopAPIWorkoutResponse: Content {
    let records: [WhoopAPIWorkoutRecord]
    let nextToken: String?

    enum CodingKeys: String, CodingKey {
        case records
        case nextToken = "next_token"
    }
}

struct WhoopAPIWorkoutRecord: Content {
    let id: Int64
    let userId: Int
    let createdAt: String
    let updatedAt: String
    let start: String
    let end: String
    let timezoneOffset: String?
    let sportId: Int
    let scoreState: String
    let score: WhoopAPIWorkoutScore?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start, end
        case timezoneOffset = "timezone_offset"
        case sportId = "sport_id"
        case scoreState = "score_state"
        case score
        case source
    }
}

struct WhoopAPIWorkoutScore: Content {
    let strain: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let kilojoule: Double?
    let percentRecorded: Double?
    let distanceMeter: Double?
    let altitudeGainMeter: Double?
    let altitudeChangeMeter: Double?
    let zoneDuration: WhoopAPIZoneDuration?

    enum CodingKeys: String, CodingKey {
        case strain
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case kilojoule
        case percentRecorded = "percent_recorded"
        case distanceMeter = "distance_meter"
        case altitudeGainMeter = "altitude_gain_meter"
        case altitudeChangeMeter = "altitude_change_meter"
        case zoneDuration = "zone_duration"
    }
}

struct WhoopAPIZoneDuration: Content {
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
}

struct WhoopAPICycleResponse: Content {
    let records: [WhoopAPICycleRecord]
    let nextToken: String?

    enum CodingKeys: String, CodingKey {
        case records
        case nextToken = "next_token"
    }
}

struct WhoopAPICycleRecord: Content {
    let id: Int64
    let userId: Int
    let createdAt: String
    let updatedAt: String
    let start: String
    let end: String?
    let timezoneOffset: String?
    let scoreState: String
    let score: WhoopAPICycleScore?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start, end
        case timezoneOffset = "timezone_offset"
        case scoreState = "score_state"
        case score
    }
}

struct WhoopAPICycleScore: Content {
    let strain: Double?
    let kilojoule: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?

    enum CodingKeys: String, CodingKey {
        case strain
        case kilojoule
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
    }
}
