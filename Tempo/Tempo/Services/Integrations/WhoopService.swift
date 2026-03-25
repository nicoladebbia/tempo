import Foundation
import AuthenticationServices
import os

// MARK: - Whoop Service (Real Implementation)
// Per INTEGRATION_SPECS.md Section 1 — iOS-side Whoop OAuth and data fetching.

@Observable
final class WhoopService: NSObject, WhoopServiceProtocol, @unchecked Sendable {

    private(set) var connectionState: WhoopConnectionState = .disconnected

    private let apiClient: APIClient
    private let logger = Logger(subsystem: "app.tempo", category: "WhoopService")

    // Hold strong reference to auth session to prevent deallocation
    private var authSession: ASWebAuthenticationSession?

    init(apiClient: APIClient) {
        self.apiClient = apiClient
        super.init()
    }

    // MARK: - Connect (OAuth Flow)
    // Per INTEGRATION_SPECS.md Section 1.1 Steps 1-11

    func connect() async throws {
        guard connectionState != .connecting else { return }
        connectionState = .connecting

        do {
            // Step 2: Get authorization URL from backend
            let authResponse = try await apiClient.request(
                APIEndpoint<WhoopAuthorizeResponseDTO>.whoopAuthorize()
            )

            guard let authURL = URL(string: authResponse.authorizationUrl) else {
                throw WhoopError.invalidAuthorizationURL
            }

            // Step 3: Open ASWebAuthenticationSession
            let callbackURL = try await openAuthSession(url: authURL)

            // Step 6: Handle callback (state already validated server-side)
            try handleCallback(callbackURL)

            // Step 11: Update state
            connectionState = .connected
            logger.info("Whoop connected successfully")

        } catch let error as WhoopError where error == .userCancelled {
            // User intentionally cancelled — reset to disconnected, do NOT show error
            connectionState = .disconnected
        } catch {
            connectionState = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Disconnect
    // Per INTEGRATION_SPECS.md Section 1.1

    func disconnect() async throws {
        do {
            _ = try await apiClient.request(
                APIEndpoint<EmptyResponse>.whoopDisconnect()
            )
        } catch {
            logger.warning("Whoop disconnect API call failed: \(error.localizedDescription)")
            // Continue — clear local state regardless
        }

        connectionState = .disconnected
        logger.info("Whoop disconnected")
    }

    // MARK: - Fetch Recovery
    // Per INTEGRATION_SPECS.md Section 1.3.1

    func fetchRecovery(for date: Date) async throws -> WhoopRecoveryData {
        let dateString = Self.dateFormatter.string(from: date)
        let response = try await apiClient.request(
            APIEndpoint<WhoopEnvelope<[WhoopRecoveryItemDTO]>>.whoopRecovery(),
            queryItems: [URLQueryItem(name: "date", value: dateString)]
        )

        guard let record = response.data.first else {
            throw WhoopError.noDataAvailable
        }

        return WhoopRecoveryData(
            score: record.recoveryScore,
            hrvRmssd: record.hrvRmssdMilli,
            restingHeartRate: record.restingHeartRate,
            spo2: record.spo2Percentage,
            skinTemp: record.skinTempCelsius,
            date: date
        )
    }

    // MARK: - Fetch Sleep
    // Per INTEGRATION_SPECS.md Section 1.3.2

    func fetchSleep(for date: Date) async throws -> WhoopSleepData {
        let dateString = Self.dateFormatter.string(from: date)
        let response = try await apiClient.request(
            APIEndpoint<WhoopEnvelope<[WhoopSleepItemDTO]>>.whoopSleep(),
            queryItems: [URLQueryItem(name: "date", value: dateString)]
        )

        // Get main sleep (not nap)
        guard let record = response.data.first(where: { !$0.nap }) else {
            throw WhoopError.noDataAvailable
        }

        let stageSummary = record.score?.stageSummary
        let totalSleepMilli = (stageSummary?.totalLightSleepTimeMilli ?? 0)
            + (stageSummary?.totalSlowWaveSleepTimeMilli ?? 0)
            + (stageSummary?.totalRemSleepTimeMilli ?? 0)

        return WhoopSleepData(
            totalHours: Double(totalSleepMilli) / 3_600_000.0,
            sleepScore: record.score?.sleepPerformancePercentage ?? 0,
            sleepEfficiency: record.score?.sleepEfficiencyPercentage ?? 0,
            sleepConsistency: record.score?.sleepConsistencyPercentage ?? 0,
            deepSleepMinutes: Int((stageSummary?.totalSlowWaveSleepTimeMilli ?? 0) / 60_000),
            remSleepMinutes: Int((stageSummary?.totalRemSleepTimeMilli ?? 0) / 60_000),
            lightSleepMinutes: Int((stageSummary?.totalLightSleepTimeMilli ?? 0) / 60_000),
            awakeMinutes: Int((stageSummary?.totalAwakeTimeMilli ?? 0) / 60_000),
            respiratoryRate: record.score?.respiratoryRate ?? 0,
            date: date
        )
    }

    // MARK: - Fetch Workouts
    // Per INTEGRATION_SPECS.md Section 1.3.3

    func fetchWorkouts(for date: Date) async throws -> [WhoopWorkoutData] {
        let dateString = Self.dateFormatter.string(from: date)
        let response = try await apiClient.request(
            APIEndpoint<WhoopEnvelope<[WhoopWorkoutItemDTO]>>.whoopWorkouts(),
            queryItems: [URLQueryItem(name: "date", value: dateString)]
        )

        return response.data.map { record in
            WhoopWorkoutData(
                strain: record.score?.strain ?? 0,
                averageHeartRate: Double(record.score?.averageHeartRate ?? 0),
                maxHeartRate: Double(record.score?.maxHeartRate ?? 0),
                caloriesBurned: (record.score?.kilojoule ?? 0) / 4.184, // kJ to kcal
                durationMinutes: 0, // Calculated from start/end if needed
                sportID: record.sportId,
                startTime: ISO8601DateFormatter().date(from: record.startTime) ?? date
            )
        }
    }

    // MARK: - Fetch Cycle (Strain)
    // Per INTEGRATION_SPECS.md Section 1.3.4

    func fetchCycle(for date: Date) async throws -> WhoopCycleData {
        let dateString = Self.dateFormatter.string(from: date)
        let response = try await apiClient.request(
            APIEndpoint<WhoopEnvelope<[WhoopCycleItemDTO]>>.whoopCycles(),
            queryItems: [URLQueryItem(name: "date", value: dateString)]
        )

        guard let record = response.data.first else {
            throw WhoopError.noDataAvailable
        }

        return WhoopCycleData(
            strain: record.strain ?? 0,
            averageHeartRate: Double(record.averageHeartRate ?? 0),
            maxHeartRate: Double(record.maxHeartRate ?? 0),
            caloriesBurned: (record.kilojoule ?? 0) / 4.184,
            dayStrain: record.strain ?? 0,
            date: date
        )
    }

    // MARK: - Sync All

    func syncAll() async throws {
        let today = Date()
        _ = try? await fetchRecovery(for: today)
        _ = try? await fetchSleep(for: today)
        _ = try? await fetchWorkouts(for: today)
        _ = try? await fetchCycle(for: today)
        logger.info("Whoop sync all completed")
    }

    // MARK: - Check Status on Launch
    // Per INTEGRATION_SPECS.md Section 1.2

    func checkConnectionOnLaunch() async {
        do {
            let status = try await apiClient.request(
                APIEndpoint<WhoopEnvelope<WhoopStatusDTO>>.whoopStatus()
            )
            if status.data.connected {
                connectionState = .connected
            } else {
                connectionState = .disconnected
            }
        } catch {
            // Network error — keep previous state
            logger.warning("Failed to check Whoop connection status: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Open ASWebAuthenticationSession for Whoop OAuth.
    /// Per INTEGRATION_SPECS.md Section 1.1 Step 3.
    @MainActor
    private func openAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "tempo"
            ) { [weak self] callbackURL, error in
                self?.authSession = nil

                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: WhoopError.userCancelled)
                    } else {
                        continuation.resume(throwing: WhoopError.authSessionFailed(error.localizedDescription))
                    }
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: WhoopError.noCallbackURL)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            // Per INTEGRATION_SPECS.md — ephemeral session, no cookie sharing
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            self.authSession = session
            session.start()
        }
    }

    /// Handle the tempo:// callback URL.
    /// Per INTEGRATION_SPECS.md Section 1.1 Step 6.
    private func handleCallback(_ callbackURL: URL) throws {
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)

        // Check for error response
        if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
            switch error {
            case "access_denied":
                throw WhoopError.userDeniedAccess
            default:
                throw WhoopError.oauthError(error)
            }
        }

        // Check for error path (tempo://integrations/whoop/error)
        if callbackURL.absoluteString.contains("/error") {
            let code = components?.queryItems?.first(where: { $0.name == "code" })?.value ?? "unknown"
            let message = components?.queryItems?.first(where: { $0.name == "message" })?.value ?? "Unknown error"
            throw WhoopError.backendError(code: code, message: message)
        }

        // Success — backend already exchanged code and stored tokens
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension WhoopService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

// MARK: - Whoop Errors

enum WhoopError: Error, Equatable {
    case userCancelled
    case userDeniedAccess
    case invalidAuthorizationURL
    case noCallbackURL
    case authSessionFailed(String)
    case oauthError(String)
    case backendError(code: String, message: String)
    case noDataAvailable
    case notConnected
}

// MARK: - API Endpoint Extensions for Whoop

extension APIEndpoint where Response == WhoopAuthorizeResponseDTO {
    static func whoopAuthorize() -> Self {
        APIEndpoint(path: "/v1/integrations/whoop/authorize", method: .get)
    }
}

extension APIEndpoint where Response == EmptyResponse {
    static func whoopDisconnect() -> Self {
        APIEndpoint(path: "/v1/integrations/whoop", method: .delete)
    }
}

extension APIEndpoint where Response == WhoopEnvelope<WhoopStatusDTO> {
    static func whoopStatus() -> Self {
        APIEndpoint(path: "/v1/integrations/whoop/status", method: .get)
    }
}

extension APIEndpoint where Response == WhoopEnvelope<[WhoopRecoveryItemDTO]> {
    static func whoopRecovery() -> Self {
        APIEndpoint(path: "/v1/whoop/recovery", method: .get)
    }
}

extension APIEndpoint where Response == WhoopEnvelope<[WhoopSleepItemDTO]> {
    static func whoopSleep() -> Self {
        APIEndpoint(path: "/v1/whoop/sleep", method: .get)
    }
}

extension APIEndpoint where Response == WhoopEnvelope<[WhoopWorkoutItemDTO]> {
    static func whoopWorkouts() -> Self {
        APIEndpoint(path: "/v1/whoop/workouts", method: .get)
    }
}

extension APIEndpoint where Response == WhoopEnvelope<[WhoopCycleItemDTO]> {
    static func whoopCycles() -> Self {
        APIEndpoint(path: "/v1/whoop/cycles", method: .get)
    }
}

// MARK: - iOS-side Response DTOs

struct WhoopEnvelope<T: Codable & Sendable>: Codable, Sendable {
    let ok: Bool
    let data: T
}

struct WhoopAuthorizeResponseDTO: Codable, Sendable {
    let authorizationUrl: String
    let state: String
}

struct WhoopStatusDTO: Codable, Sendable {
    let connected: Bool
    let lastSync: String?
    let connectedSince: String?
}

struct WhoopRecoveryItemDTO: Codable, Sendable {
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
    let syncedAt: String
}

struct WhoopSleepItemDTO: Codable, Sendable {
    let id: String
    let whoopSleepId: Int64
    let date: String
    let startTime: String
    let endTime: String
    let score: WhoopSleepScoreItemDTO?
    let nap: Bool
    let scoreState: String
    let syncedAt: String
}

struct WhoopSleepScoreItemDTO: Codable, Sendable {
    let stageSummary: WhoopStageSummaryItemDTO?
    let respiratoryRate: Double?
    let sleepPerformancePercentage: Double?
    let sleepConsistencyPercentage: Double?
    let sleepEfficiencyPercentage: Double?
}

struct WhoopStageSummaryItemDTO: Codable, Sendable {
    let totalInBedTimeMilli: Int64
    let totalAwakeTimeMilli: Int64
    let totalLightSleepTimeMilli: Int64
    let totalSlowWaveSleepTimeMilli: Int64
    let totalRemSleepTimeMilli: Int64
    let sleepCycleCount: Int
    let disturbanceCount: Int
}

struct WhoopWorkoutItemDTO: Codable, Sendable {
    let id: String
    let whoopWorkoutId: Int64
    let date: String
    let sportId: Int
    let sportName: String
    let startTime: String
    let endTime: String
    let score: WhoopWorkoutScoreItemDTO?
    let source: String?
    let syncedAt: String
}

struct WhoopWorkoutScoreItemDTO: Codable, Sendable {
    let strain: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let kilojoule: Double?
    let distanceMeter: Double?
}

struct WhoopCycleItemDTO: Codable, Sendable {
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
    let syncedAt: String
}
