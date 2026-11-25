//
// APIEndpoints+Coach.swift
// Tempo
//
// Wire contract for the Recovery Coach (backend `Coach/*`, `Nutrition/Recovery/*`):
//
//   GET  /v1/coach/sessions/recent → Envelope<[CoachSession]>
//        Finished WHOOP workouts of the last 48 h that are big enough
//        (>= 20 min and >= 150 kcal).
//   POST /v1/coach/recovery        → Envelope<CoachRecoveryResponse>
//        Weigh-ins + fluids in, sweat range and recovery plan out. All the math
//        is server-side; the app only shows it.
//
// The app's decoder/encoder have no key strategy, so every snake_case key is
// spelled in CodingKeys. Pinned by contracts/golden/coach-*.json and
// push-post_workout_weighin.json (APIContractTests).
//

import Foundation

// MARK: - Session

struct CoachSession: Codable, Sendable, Equatable, Identifiable {
    /// WHOOP v2 workout id (UUID text).
    let id: String
    let start: Date
    let end: Date
    /// e.g. "soccer"; shown as the session label when present.
    let sportName: String?
    let strain: Double?
    let kilojoules: Double?
    let averageHeartRate: Int?
    let percentRecorded: Double?

    enum CodingKeys: String, CodingKey {
        case id, start, end, strain, kilojoules
        case sportName = "sport_name"
        case averageHeartRate = "average_heart_rate"
        case percentRecorded = "percent_recorded"
    }

    var label: String { sportName.map(\.capitalized) ?? String(localized: "Workout") }

    var durationMinutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

// MARK: - Request

/// `source` is `withings` (a reading Health got from the Withings scale) or `manual`.
struct CoachWeighIn: Codable, Sendable, Equatable {
    let time: Date
    let kg: Double
    let source: String

    static let sourceWithings = "withings"
    static let sourceManual = "manual"
}

struct CoachRecoveryRequest: Encodable, Sendable, Equatable {
    let sessionId: String
    let sessionStart: Date
    let weighIns: [CoachWeighIn]
    /// nil = unknown: the server then says "at least".
    let drankLiters: Double?
    let urineLiters: Double?
    let hoursUntilNextHardSession: Double?
    /// Coarse (0.1 degree) and only when location is already authorized.
    let latitude: Double?
    let longitude: Double?
    let bodyMassKg: Double?
    let scaleRepeatabilitySdKg: Double?

    init(
        sessionId: String, sessionStart: Date, weighIns: [CoachWeighIn], drankLiters: Double? = nil,
        urineLiters: Double? = nil, hoursUntilNextHardSession: Double? = nil,
        latitude: Double? = nil, longitude: Double? = nil, bodyMassKg: Double? = nil,
        scaleRepeatabilitySdKg: Double? = nil
    ) {
        self.sessionId = sessionId
        self.sessionStart = sessionStart
        self.weighIns = weighIns
        self.drankLiters = drankLiters
        self.urineLiters = urineLiters
        self.hoursUntilNextHardSession = hoursUntilNextHardSession
        self.latitude = latitude
        self.longitude = longitude
        self.bodyMassKg = bodyMassKg
        self.scaleRepeatabilitySdKg = scaleRepeatabilitySdKg
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case sessionStart = "session_start"
        case weighIns = "weigh_ins"
        case drankLiters = "drank_liters"
        case urineLiters = "urine_liters"
        case hoursUntilNextHardSession = "hours_until_next_hard_session"
        case latitude, longitude
        case bodyMassKg = "body_mass_kg"
        case scaleRepeatabilitySdKg = "scale_repeatability_sd_kg"
    }
}

// MARK: - Response

struct CoachRecoveryResponse: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case ready
        case needsWeighIn = "needs_weigh_in"
        case implausible
    }

    let status: Status
    /// `pre_weigh_in` / `post_weigh_in` when status is needs_weigh_in.
    let missing: [String]?
    let preWeighIn: CoachWeighIn?
    let postWeighIn: CoachWeighIn?
    let sweat: Sweat?
    let plan: Plan?
    let notes: [String]
    let session: CoachSession?

    struct Sweat: Codable, Sendable, Equatable {
        let massLostKg: Double
        let percentBodyMassLost: Double
        let sweatLitersRaw: Double?
        let sweatLitersLow: Double?
        let sweatLitersMid: Double?
        let sweatLitersHigh: Double?
        /// True when fluid intake was unknown: the real sweat is "at least" this.
        let isLowerBound: Bool
        /// `tight` or `loose`.
        let protocolQuality: String?
        let marginOfErrorPercent: Double?
        let meetsFivePercentTarget: Bool
        let assumptions: [String]

        enum CodingKeys: String, CodingKey {
            case massLostKg = "mass_lost_kg"
            case percentBodyMassLost = "percent_body_mass_lost"
            case sweatLitersRaw = "sweat_liters_raw"
            case sweatLitersLow = "sweat_liters_low"
            case sweatLitersMid = "sweat_liters_mid"
            case sweatLitersHigh = "sweat_liters_high"
            case isLowerBound = "is_lower_bound"
            case protocolQuality = "protocol_quality"
            case marginOfErrorPercent = "margin_of_error_percent"
            case meetsFivePercentTarget = "meets_five_percent_target"
            case assumptions
        }
    }

    struct Plan: Codable, Sendable, Equatable {
        /// nil when there is no measured sweat.
        let drinkLiters: Double?
        let sodiumMgLow: Double?
        let sodiumMgHigh: Double?
        let sodiumMgPlan: Double?
        let carbsGrams: Double
        let carbWindowHours: Double
        let proteinGrams: Double
        let leucineMgLow: Double?
        let leucineMgHigh: Double?
        let reasons: [String]
        let evidence: [String]

        enum CodingKeys: String, CodingKey {
            case drinkLiters = "drink_liters"
            case sodiumMgLow = "sodium_mg_low"
            case sodiumMgHigh = "sodium_mg_high"
            case sodiumMgPlan = "sodium_mg_plan"
            case carbsGrams = "carbs_grams"
            case carbWindowHours = "carb_window_hours"
            case proteinGrams = "protein_grams"
            case leucineMgLow = "leucine_mg_low"
            case leucineMgHigh = "leucine_mg_high"
            case reasons, evidence
        }
    }

    enum CodingKeys: String, CodingKey {
        case status, missing, sweat, plan, notes, session
        case preWeighIn = "pre_weigh_in"
        case postWeighIn = "post_weigh_in"
    }

    var missingPre: Bool { missing?.contains("pre_weigh_in") ?? false }
    var missingPost: Bool { missing?.contains("post_weigh_in") ?? false }
}

// MARK: - Endpoints

extension APIEndpoint where Response == [CoachSession] {
    static func coachRecentSessions() -> Self {
        APIEndpoint(path: "/v1/coach/sessions/recent", method: .get)
    }
}

extension APIEndpoint where Response == CoachRecoveryResponse {
    /// Body: `CoachRecoveryRequest`. Idempotent math, safe to retry.
    static func coachRecovery() -> Self {
        APIEndpoint(path: "/v1/coach/recovery", method: .post)
    }
}

// MARK: - Push payload

/// `data` keys of the `post_workout_weighin` push (contracts/golden/push-post_workout_weighin.json).
/// Match a push to a session by `sessionId` ONLY: push dates carry milliseconds, API dates do not.
struct CoachPushPayload: Equatable, Sendable {
    let sessionId: String
    let sessionStart: Date?
    let sessionEnd: Date?

    /// ISO8601 with milliseconds, with a plain-seconds fallback.
    private static func parseDate(_ raw: Any?) -> Date? {
        guard let s = raw as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }

    /// Accepts the full APNs userInfo (custom keys nested under `data`) or the flat dictionary.
    init?(userInfo: [AnyHashable: Any]) {
        let info = (userInfo["data"] as? [String: Any]) ?? userInfo.reduce(into: [String: Any]()) { acc, pair in
            if let key = pair.key as? String { acc[key] = pair.value }
        }
        guard (info["type"] as? String) == "post_workout_weighin" else { return nil }
        guard let id = info["session_id"] as? String, !id.isEmpty else { return nil }
        sessionId = id
        sessionStart = Self.parseDate(info["session_start"])
        sessionEnd = Self.parseDate(info["session_end"])
    }
}
