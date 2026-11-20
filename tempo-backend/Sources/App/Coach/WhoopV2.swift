import Foundation
import Vapor

// MARK: - WHOOP v2 workout DTOs
//
// Shapes read from WHOOP's own documentation (developer.whoop.com, "Workout" and the v1 -> v2 migration guide,
// 2026-11-20): `id` is a UUID string, `v1_id` keeps the old number, `sport_name` replaces `sport_id`, and the zone
// times are `zone_durations`. Decoded with `WhoopJSON` (a plain decoder), so the snake_case CodingKeys below are right.

struct WhoopV2WorkoutResponse: Decodable, Sendable {
    let records: [WhoopV2WorkoutRecord]
    let nextToken: String?

    enum CodingKeys: String, CodingKey {
        case records
        case nextToken = "next_token"
    }
}

struct WhoopV2WorkoutRecord: Decodable, Sendable {
    let id: String
    let v1Id: Int64?
    let userId: Int
    let start: String
    let end: String
    let timezoneOffset: String?
    let sportName: String?
    let scoreState: String
    let score: WhoopV2WorkoutScore?

    enum CodingKeys: String, CodingKey {
        case id
        case v1Id = "v1_id"
        case userId = "user_id"
        case start, end
        case timezoneOffset = "timezone_offset"
        case sportName = "sport_name"
        case scoreState = "score_state"
        case score
    }
}

struct WhoopV2WorkoutScore: Decodable, Sendable {
    let strain: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let kilojoule: Double?
    let percentRecorded: Double?

    enum CodingKeys: String, CodingKey {
        case strain
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case kilojoule
        case percentRecorded = "percent_recorded"
    }
}

extension WhoopAPIService {
    /// GET /developer/v2/activity/workout. Same token refresh behaviour as the v1 calls.
    func fetchWorkoutsV2(for userID: String, start: String, end: String, on req: Request) async throws -> WhoopV2WorkoutResponse {
        let url = "\(Self.baseURLV2)/activity/workout?start=\(start)&end=\(end)&limit=25"
        func get(_ token: String) async throws -> ClientResponse {
            try await req.client.get(URI(string: url)) { $0.headers.bearerAuthorization = BearerAuthorization(token: token) }
        }
        var response = try await get(try await validAccessToken(for: userID, on: req))
        if response.status == .unauthorized {
            response = try await get(try await forceRefreshToken(for: userID, on: req))
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "WHOOP workout fetch failed: \(response.status)")
        }
        return try WhoopJSON.decode(WhoopV2WorkoutResponse.self, from: response)
    }
}
