//
// APIEndpoints.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - HTTPMethod

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - APIEndpoint

struct APIEndpoint<Response: Decodable & Sendable> {
    let path: String
    let method: HTTPMethod
    let requiresAuth: Bool
    /// True when the backend wraps the response in `Envelope<T>` (the default for
    /// most routes per VAPOR_PROJECT_STRUCTURE.md). False for the small set of
    /// auth routes that return their payload directly. Per
    /// INTELLIGENCE_REMEDIATION_PLAN.md §3 (envelope unwrap fix).
    let expectsEnvelope: Bool

    init(path: String, method: HTTPMethod = .get, requiresAuth: Bool = true, expectsEnvelope: Bool = true) {
        self.path = path
        self.method = method
        self.requiresAuth = requiresAuth
        self.expectsEnvelope = expectsEnvelope
    }
}

// MARK: - APIEnvelope

/// Mirrors backend `Envelope<T>` ({ ok, data, meta, pagination? }). The iOS
/// APIClient unwraps this automatically when `APIEndpoint.expectsEnvelope` is
/// true and hands the caller the inner `T`. Per
/// INTELLIGENCE_REMEDIATION_PLAN.md §3.
struct APIEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    let ok: Bool
    let data: T
}

// MARK: - Auth Endpoints

extension APIEndpoint where Response == AuthTokenResponse {
    static func signInWithApple() -> Self {
        // Auth controller returns AuthTokenResponse directly (no Envelope wrap).
        APIEndpoint(path: "/v1/auth/apple", method: .post, requiresAuth: false, expectsEnvelope: false)
    }

    static func refreshToken() -> Self {
        APIEndpoint(path: "/v1/auth/refresh", method: .post, requiresAuth: false, expectsEnvelope: false)
    }
}

extension APIEndpoint where Response == EmptyResponse {
    static func logout() -> Self {
        // Auth controller returns LogoutResponse directly; iOS decodes as Empty.
        APIEndpoint(path: "/v1/auth/logout", method: .post, requiresAuth: true, expectsEnvelope: false)
    }
}

// MARK: - Sync Endpoints

extension APIEndpoint where Response == SyncStatusResponse {
    static func syncStatus() -> Self {
        APIEndpoint(path: "/v1/sync/status", method: .get)
    }
}

extension APIEndpoint where Response == SyncBatchResponse {
    static func syncBatch() -> Self {
        APIEndpoint(path: "/v1/sync/batch", method: .post)
    }
}

// MARK: - AuthTokenResponse

struct AuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int

    // The backend serializes all JSON with
    // `keyEncodingStrategy = .convertToSnakeCase`, so these arrive as
    // access_token / refresh_token / etc. The app's decoder uses no global
    // key strategy (other DTOs already spell their keys snake_case), so
    // map them explicitly here — matching codebase convention.
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

// MARK: - SyncStatusResponse

struct SyncStatusResponse: Codable {
    let last_synced: [String: String]
}

// MARK: - SyncBatchResponse

struct SyncBatchResponse: Codable {
    let succeeded: Int
    let failed: Int
}

// MARK: - EmptyResponse

struct EmptyResponse: Codable {}

// MARK: - User endpoints

/// Mirrors backend AIConsentRequest. Per AI_INTELLIGENCE_ENGINE.md §11.3.
struct AIConsentRequestDTO: Codable, Sendable {
    let consented: Bool
}

/// Mirrors backend AIConsentResponse.
struct AIConsentResponseDTO: Codable, Sendable {
    let aiConsentAt: Date?

    enum CodingKeys: String, CodingKey {
        case aiConsentAt = "ai_consent_at"
    }
}

extension APIEndpoint where Response == AIConsentResponseDTO {
    static func setAIConsent() -> Self {
        APIEndpoint(path: "/v1/user/ai-consent", method: .post)
    }
}

// MARK: - ToS Acceptance (LAUNCH_PUNCH_LIST.md §3.5)

struct AcceptToSRequestDTO: Codable, Sendable {
    let documentVersion: String?

    enum CodingKeys: String, CodingKey {
        case documentVersion = "document_version"
    }
}

struct AcceptToSResponseDTO: Codable, Sendable {
    let tosAcceptedAt: Date

    enum CodingKeys: String, CodingKey {
        case tosAcceptedAt = "tos_accepted_at"
    }
}

extension APIEndpoint where Response == AcceptToSResponseDTO {
    static func acceptToS() -> Self {
        APIEndpoint(path: "/v1/user/accept-tos", method: .post)
    }
}

/// Mirrors backend UserMeResponse. Used to hydrate Pro tier + AI consent state
/// after sign-in. Per INTELLIGENCE_REMEDIATION_PLAN.md §4.
struct UserMeResponseDTO: Codable, Sendable {
    let id: String
    let displayName: String
    let username: String
    let timezone: String
    let xpTotal: Int
    let level: Int
    let streakDays: Int
    let isPro: Bool
    let productId: String?
    let subscriptionExpiresAt: Date?
    let aiConsentAt: Date?
    let tosAcceptedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case username
        case timezone
        case xpTotal = "xp_total"
        case level
        case streakDays = "streak_days"
        case isPro = "is_pro"
        case productId = "product_id"
        case subscriptionExpiresAt = "subscription_expires_at"
        case aiConsentAt = "ai_consent_at"
        case tosAcceptedAt = "tos_accepted_at"
    }
}

extension APIEndpoint where Response == UserMeResponseDTO {
    static func currentUser() -> Self {
        APIEndpoint(path: "/v1/user/me", method: .get)
    }
}

// MARK: - Account deletion (Apple-required per App Store Guideline 5.1.1(v))

struct AccountDeletionResponseDTO: Decodable, Sendable {
    let deletedAt: Date

    enum CodingKeys: String, CodingKey {
        case deletedAt = "deleted_at"
    }
}

extension APIEndpoint where Response == AccountDeletionResponseDTO {
    static func deleteAccount() -> Self {
        APIEndpoint(path: "/v1/user/me", method: .delete)
    }
}

// MARK: - Daily plan profile

/// Mirrors backend SetDailyPlanProfileRequest. Per INTELLIGENCE_REMEDIATION_PLAN.md §8.
///
/// Property names are camelCase to match the rest of the iOS DTO surface;
/// CodingKeys map them to snake_case on the wire. The backend's
/// `convertFromSnakeCase` strategy then maps the wire keys back to its own
/// camelCase struct fields.
struct OnboardingDailyPlanProfileDTO: Codable, Sendable {
    let wakeTimeMinutes: Int
    let sleepTargetHours: Double
    let chronotype: String
    let trainingTimePreference: String
    let eatingWindowPreset: String
    let eatingWindowStartMinutes: Int
    let eatingWindowEndMinutes: Int
    let breakfastSkipped: Bool
    let postWorkoutMandatory: Bool
    let studySessionLengthMinutes: Int
    let weekendDifferential: String
    let termStartDate: Date?
    let termEndDate: Date?
    let classBlocks: [ClassBlock]
    let workBlocks: [WorkBlock]

    enum CodingKeys: String, CodingKey {
        case wakeTimeMinutes = "wake_time_minutes"
        case sleepTargetHours = "sleep_target_hours"
        case chronotype
        case trainingTimePreference = "training_time_preference"
        case eatingWindowPreset = "eating_window_preset"
        case eatingWindowStartMinutes = "eating_window_start_minutes"
        case eatingWindowEndMinutes = "eating_window_end_minutes"
        case breakfastSkipped = "breakfast_skipped"
        case postWorkoutMandatory = "post_workout_mandatory"
        case studySessionLengthMinutes = "study_session_length_minutes"
        case weekendDifferential = "weekend_differential"
        case termStartDate = "term_start_date"
        case termEndDate = "term_end_date"
        case classBlocks = "class_blocks"
        case workBlocks = "work_blocks"
    }

    struct ClassBlock: Codable, Sendable {
        let weekday: Int
        let startMinuteOfDay: Int
        let endMinuteOfDay: Int
        let courseCode: String
        let courseName: String?
        let location: String?

        enum CodingKeys: String, CodingKey {
            case weekday
            case startMinuteOfDay = "start_minute_of_day"
            case endMinuteOfDay = "end_minute_of_day"
            case courseCode = "course_code"
            case courseName = "course_name"
            case location
        }
    }

    struct WorkBlock: Codable, Sendable {
        let weekday: Int
        let startMinuteOfDay: Int
        let endMinuteOfDay: Int
        let label: String

        enum CodingKeys: String, CodingKey {
            case weekday
            case startMinuteOfDay = "start_minute_of_day"
            case endMinuteOfDay = "end_minute_of_day"
            case label
        }
    }
}

extension APIEndpoint where Response == EmptyResponse {
    static func setDailyPlanProfile() -> Self {
        APIEndpoint(path: "/v1/user/daily-plan-profile", method: .put)
    }
}

// MARK: - §7 AI route DTOs (hydration only)
//
// Only the fields the DayPlannerAIHydrator actually consumes. The
// backend's input structs have many more fields — anything we don't
// pass falls through to fallback values on the server, which is fine
// for v1 hydration since AI failure is non-fatal.

struct DayPlanTrainingProgramRequest: Codable, Sendable {
    let weekStart: String
    let footballDays: [String]
    let recentRecovery7Day: [Int]
    let recentSessions: [String]
    let goal: String

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case footballDays = "football_days"
        case recentRecovery7Day = "recent_recovery_7day"
        case recentSessions = "recent_sessions"
        case goal
    }
}

struct DayPlanTrainingProgramResponse: Codable, Sendable {
    let rationale: String
    /// Per-day entries from the backend. We only consume `rationale` for
    /// v1 hydration — the per-day breakdown is the source for the
    /// weekly planner, not the daily-plan view.
}

extension APIEndpoint where Response == DayPlanTrainingProgramResponse {
    static func dayPlanTrainingProgram() -> Self {
        APIEndpoint(path: "/v1/insights/training-program", method: .post)
    }
}

struct DayPlanMealTimingRequest: Codable, Sendable {
    let date: String
    let mealIndex: Int
    let mealName: String
    let plannedCalories: Int
    let plannedProteinGrams: Int
    let trainingTimeToday: String?
    let lastMealTime: String?
    let recoveryZone: String

    enum CodingKeys: String, CodingKey {
        case date
        case mealIndex = "meal_index"
        case mealName = "meal_name"
        case plannedCalories = "planned_calories"
        case plannedProteinGrams = "planned_protein_grams"
        case trainingTimeToday = "training_time_today"
        case lastMealTime = "last_meal_time"
        case recoveryZone = "recovery_zone"
    }
}

struct DayPlanMealTimingResponse: Codable, Sendable {
    let suggestedTime: String
    let note: String

    enum CodingKeys: String, CodingKey {
        case suggestedTime = "suggested_time"
        case note
    }
}

extension APIEndpoint where Response == DayPlanMealTimingResponse {
    static func dayPlanMealTiming() -> Self {
        APIEndpoint(path: "/v1/nutrition/ai/meal-timing", method: .post)
    }
}

struct DayPlanStudyScheduleRequest: Codable, Sendable {
    let examId: String
    let examName: String
    let daysUntilExam: Int
    let topics: [String]
    let topicProgress: [String: Int]
    let dailyAvailabilityMinutes: Int

    enum CodingKeys: String, CodingKey {
        case examId = "exam_id"
        case examName = "exam_name"
        case daysUntilExam = "days_until_exam"
        case topics
        case topicProgress = "topic_progress"
        case dailyAvailabilityMinutes = "daily_availability_minutes"
    }
}

struct DayPlanStudyScheduleResponse: Codable, Sendable {
    let rationale: String
}

extension APIEndpoint where Response == DayPlanStudyScheduleResponse {
    static func dayPlanStudySchedule() -> Self {
        APIEndpoint(path: "/v1/insights/study-schedule", method: .post)
    }
}
