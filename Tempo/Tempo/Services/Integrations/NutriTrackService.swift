import Foundation
import SwiftData
import os

// MARK: - NutriTrack Service (Real Implementation)
// Per BUILD_PLAN step 11.2.
// Per INTEGRATION_SPECS.md Section 3 — Communicates with Tempo backend proxy.

@Observable
final class NutriTrackService: NutriTrackServiceProtocol, @unchecked Sendable {

    private(set) var connectionState: NutriTrackConnectionState = .disconnected

    private let apiClient: APIClient
    private let logger = Logger.nutritrack

    /// Cached today data for offline fallback.
    private var cachedTodayData: NutriTrackDayData?

    /// Last successful sync timestamp — shown in UI for stale data indicator.
    private(set) var lastSyncDate: Date?

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Connect
    // Per INTEGRATION_SPECS.md Section 3.1 — Send base URL + PIN to backend.
    // Backend validates URL, tests PIN against NutriTrack /api/pin/verify, stores encrypted.

    func connect(baseURL: URL, pin: String) async throws {
        if case .connecting = connectionState { return }
        connectionState = .connecting

        do {
            _ = try await apiClient.request(
                APIEndpoint<NutriTrackEnvelope<NutriTrackConnectResponseDTO>>.nutriTrackConnect(),
                body: NutriTrackConnectRequestDTO(
                    baseURL: baseURL.absoluteString,
                    pin: pin
                )
            )
            connectionState = .connected
            logger.info("NutriTrack connected successfully")
        } catch {
            connectionState = .error(error.localizedDescription)
            logger.error("NutriTrack connect failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Disconnect
    // Per INTEGRATION_SPECS.md Section 3.1 — Delete connection on backend.

    func disconnect() {
        Task { [weak self] in
            _ = try? await self?.apiClient.request(
                APIEndpoint<EmptyResponse>.nutriTrackDisconnect()
            )
        }
        connectionState = .disconnected
        cachedTodayData = nil
        lastSyncDate = nil
        logger.info("NutriTrack disconnected")
    }

    // MARK: - Fetch Today's Meals
    // Per INTEGRATION_SPECS.md Section 3.3 — Proxy to NutriTrack /api/today.

    func fetchTodayMeals() async throws -> NutriTrackDayData {
        do {
            let dto = try await apiClient.request(
                APIEndpoint<NutriTrackTodayDTO>.nutriTrackToday()
            )
            let dayData = dto.toDayData()
            cachedTodayData = dayData
            lastSyncDate = Date()
            return dayData
        } catch {
            // Per ERROR_RECOVERY_FLOWS.md INT-005 — serve cached data when server unreachable
            if let cached = cachedTodayData {
                logger.warning("NutriTrack fetch failed, using cached data: \(error.localizedDescription)")
                return cached
            }
            throw NutriTrackError.fetchFailed(error.localizedDescription)
        }
    }

    // MARK: - Fetch Macro Balance
    // Per INTEGRATION_SPECS.md Section 3.3 — Proxy to NutriTrack /api/today/macro-balance.

    func fetchMacroBalance() async throws -> MacroBalance {
        let dto = try await apiClient.request(
            APIEndpoint<NutriTrackMacroBalanceDTO>.nutriTrackMacroBalance()
        )
        return MacroBalance(
            proteinPercentage: dto.proteinPercentage,
            carbsPercentage: dto.carbsPercentage,
            fatPercentage: dto.fatPercentage
        )
    }

    // MARK: - Fetch Weekly Report
    // Per INTEGRATION_SPECS.md Section 3.3 — Proxy to NutriTrack /api/week/:date.

    func fetchWeeklyReport() async throws -> NutriTrackWeeklyReport {
        let dto = try await apiClient.request(
            APIEndpoint<NutriTrackWeeklyReportDTO>.nutriTrackWeeklyReport()
        )
        return NutriTrackWeeklyReport(
            averageCalories: dto.averageCalories,
            averageProtein: dto.averageProtein,
            adherencePercentage: dto.adherencePercentage,
            daysLogged: dto.daysLogged
        )
    }

    // MARK: - Sync to SwiftData
    // Per BUILD_PLAN step 11.2 — Update DailySnapshot fuel fields from NutriTrack data.

    func syncToSwiftData(dayData: NutriTrackDayData, modelContext: ModelContext) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: dayData.date)

        // Find or create today's snapshot
        let predicate = #Predicate<DailySnapshot> { snapshot in
            snapshot.date == startOfDay
        }
        let descriptor = FetchDescriptor<DailySnapshot>(predicate: predicate)

        guard let snapshot = (try? modelContext.fetch(descriptor))?.first else {
            logger.warning("No DailySnapshot found for NutriTrack sync")
            return
        }

        // Update fuel fields
        snapshot.caloriesConsumed = Int(dayData.totalCalories)
        snapshot.calorieTarget = Int(dayData.calorieTarget)
        snapshot.proteinActual = dayData.proteinGrams
        snapshot.proteinTarget = dayData.proteinTarget
        snapshot.carbsActual = dayData.carbsGrams
        snapshot.carbsTarget = dayData.carbsTarget
        snapshot.fatActual = dayData.fatGrams
        snapshot.fatTarget = dayData.fatTarget
        snapshot.mealsLogged = dayData.mealsLogged
        snapshot.mealsPlanned = dayData.mealsPlanned

        try? modelContext.save()
        logger.info("NutriTrack data synced to DailySnapshot")
    }

    // MARK: - Check Connection on Launch
    // Per INTEGRATION_SPECS.md Section 3.2 — Sync on app launch.

    func checkConnectionOnLaunch() async {
        do {
            let status = try await apiClient.request(
                APIEndpoint<NutriTrackEnvelope<NutriTrackStatusResponseDTO>>.nutriTrackStatus()
            )
            if status.data.connected {
                connectionState = .connected
            } else {
                connectionState = .disconnected
            }
        } catch {
            logger.warning("Failed to check NutriTrack connection: \(error.localizedDescription)")
        }
    }
}

// MARK: - NutriTrack Errors

enum NutriTrackError: Error {
    case invalidURL
    case invalidPIN
    case serverUnreachable
    case pinChanged
    case fetchFailed(String)
    case timeout
}

// MARK: - API Endpoint Extensions

extension APIEndpoint where Response == NutriTrackEnvelope<NutriTrackConnectResponseDTO> {
    static func nutriTrackConnect() -> Self {
        APIEndpoint(path: "/v1/integrations/nutritrack/connect", method: .post)
    }
}

extension APIEndpoint where Response == EmptyResponse {
    static func nutriTrackDisconnect() -> Self {
        APIEndpoint(path: "/v1/integrations/nutritrack", method: .delete)
    }
}

extension APIEndpoint where Response == NutriTrackEnvelope<NutriTrackStatusResponseDTO> {
    static func nutriTrackStatus() -> Self {
        APIEndpoint(path: "/v1/integrations/nutritrack/status", method: .get)
    }
}

extension APIEndpoint where Response == NutriTrackTodayDTO {
    static func nutriTrackToday() -> Self {
        APIEndpoint(path: "/v1/nutritrack/today", method: .get)
    }
}

extension APIEndpoint where Response == NutriTrackMacroBalanceDTO {
    static func nutriTrackMacroBalance() -> Self {
        APIEndpoint(path: "/v1/nutritrack/macro-balance", method: .get)
    }
}

extension APIEndpoint where Response == NutriTrackWeeklyReportDTO {
    static func nutriTrackWeeklyReport() -> Self {
        APIEndpoint(path: "/v1/nutritrack/weekly-report", method: .get)
    }
}

// MARK: - Envelope DTO (matches backend Envelope<T>)

struct NutriTrackEnvelope<T: Codable & Sendable>: Codable, Sendable {
    let ok: Bool
    let data: T
}

// MARK: - Request/Response DTOs

struct NutriTrackConnectRequestDTO: Codable, Sendable {
    let baseURL: String
    let pin: String

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case pin
    }
}

struct NutriTrackConnectResponseDTO: Codable, Sendable {
    let connected: Bool
    let baseURL: String

    enum CodingKeys: String, CodingKey {
        case connected
        case baseURL = "base_url"
    }
}

struct NutriTrackStatusResponseDTO: Codable, Sendable {
    let connected: Bool
    let baseURL: String?
    let lastSyncAt: String?
    let lastSyncStatus: String?

    enum CodingKeys: String, CodingKey {
        case connected
        case baseURL = "base_url"
        case lastSyncAt = "last_sync_at"
        case lastSyncStatus = "last_sync_status"
    }
}

// MARK: - Data Proxy DTOs (raw Flask JSON format)
// NutriTrack Flask API uses snake_case keys.

struct NutriTrackTodayDTO: Codable, Sendable {
    let caloriesConsumed: Double
    let targetCalories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let proteinTarget: Double?
    let carbsTarget: Double?
    let fatTarget: Double?
    let mealsLogged: Int
    let mealsPlanned: Int
    let meals: [NutriTrackMealDTO]

    enum CodingKeys: String, CodingKey {
        case caloriesConsumed = "calories_consumed"
        case targetCalories = "target_calories"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case proteinTarget = "protein_target"
        case carbsTarget = "carbs_target"
        case fatTarget = "fat_target"
        case mealsLogged = "meals_logged"
        case mealsPlanned = "meals_planned"
        case meals
    }

    /// Convert to protocol data type.
    func toDayData() -> NutriTrackDayData {
        NutriTrackDayData(
            date: Date(),
            totalCalories: caloriesConsumed,
            calorieTarget: targetCalories,
            proteinGrams: proteinG,
            proteinTarget: proteinTarget ?? 0,
            carbsGrams: carbsG,
            carbsTarget: carbsTarget ?? 0,
            fatGrams: fatG,
            fatTarget: fatTarget ?? 0,
            mealsLogged: mealsLogged,
            mealsPlanned: mealsPlanned,
            meals: meals.map { $0.toMeal() }
        )
    }
}

struct NutriTrackMealDTO: Codable, Sendable {
    let name: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let status: String?
    let time: String?

    enum CodingKeys: String, CodingKey {
        case name, calories, status, time
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }

    /// Convert to protocol data type.
    func toMeal() -> NutriTrackMeal {
        let mealTime: Date
        if let time, let parsed = NutriTrackMealDTO.timeFormatter.date(from: time) {
            mealTime = parsed
        } else {
            mealTime = Date()
        }

        return NutriTrackMeal(
            name: name,
            calories: calories,
            proteinGrams: proteinG,
            carbsGrams: carbsG,
            fatGrams: fatG,
            time: mealTime
        )
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

struct NutriTrackMacroBalanceDTO: Codable, Sendable {
    let proteinPercentage: Double
    let carbsPercentage: Double
    let fatPercentage: Double

    enum CodingKeys: String, CodingKey {
        case proteinPercentage = "protein_percentage"
        case carbsPercentage = "carbs_percentage"
        case fatPercentage = "fat_percentage"
    }
}

struct NutriTrackWeeklyReportDTO: Codable, Sendable {
    let averageCalories: Double
    let averageProtein: Double
    let adherencePercentage: Double
    let daysLogged: Int

    enum CodingKeys: String, CodingKey {
        case averageCalories = "average_calories"
        case averageProtein = "average_protein"
        case adherencePercentage = "adherence_percentage"
        case daysLogged = "days_logged"
    }
}
