import Fluent
import Vapor

// MARK: - UserController
//
// Per INTELLIGENCE_REMEDIATION_PLAN.md §4 + AI_INTELLIGENCE_ENGINE.md §11.3.
//
// Routes:
//   GET  /v1/user/me         — current user (id, displayName, tier, consent, streak)
//   POST /v1/user/ai-consent — record/revoke AI consent (idempotent)
//
// Both routes are JWT-protected via the parent group.

struct UserController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("me", use: me)
        routes.post("ai-consent", use: setAIConsent)
        // Per INTELLIGENCE_REMEDIATION_PLAN.md §8.
        routes.put("daily-plan-profile", use: setDailyPlanProfile)
        routes.get("daily-plan-profile", use: getDailyPlanProfile)
    }

    // MARK: - GET /v1/user/me

    @Sendable
    func me(_ req: Request) async throws -> Envelope<UserMeResponse> {
        let userID = try req.auth.requireUserID()

        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.notFound, reason: "User not found.")
        }

        // Resolve active subscription (cheap, single index hit on (user_id, is_active, expiration_date)).
        let activeSub = try await UserSubscription.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$isActive == true)
            .filter(\.$expirationDate > Date())
            .sort(\.$expirationDate, .descending)
            .first()

        let response = UserMeResponse(
            id: user.id ?? userID,
            displayName: user.displayName,
            username: user.username,
            timezone: user.timezone,
            xpTotal: user.xpTotal,
            level: user.level,
            streakDays: user.streakDays,
            isPro: activeSub != nil,
            productId: activeSub?.productId,
            subscriptionExpiresAt: activeSub?.expirationDate,
            aiConsentAt: user.aiConsentAt
        )
        return Envelope(data: response, requestID: req.requestID)
    }

    // MARK: - POST /v1/user/ai-consent

    @Sendable
    func setAIConsent(_ req: Request) async throws -> Envelope<AIConsentResponse> {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(AIConsentRequest.self)

        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.notFound, reason: "User not found.")
        }

        // Idempotent: setting consent twice is fine; revoke is also idempotent.
        if body.consented {
            // Don't overwrite an existing timestamp on re-confirm — preserves
            // the audit trail for "consent given at X" required by GDPR §7.
            if user.aiConsentAt == nil {
                user.aiConsentAt = Date()
            }
        } else {
            user.aiConsentAt = nil
        }
        try await user.save(on: req.db)

        // Bust the SubscriptionMiddleware cache so the very next AI request
        // sees the new consent state without waiting up to 5 minutes.
        await req.invalidateSubscriptionCache(userID: userID)

        return Envelope(
            data: AIConsentResponse(aiConsentAt: user.aiConsentAt),
            requestID: req.requestID
        )
    }

    // MARK: - PUT /v1/user/daily-plan-profile
    //
    // Idempotent upsert. iOS sends the entire profile on every change; we
    // overwrite. This matches the SwiftData side-effect of editing the local
    // copy — there's no patch surface that wouldn't introduce drift.

    @Sendable
    func setDailyPlanProfile(_ req: Request) async throws -> Envelope<DailyPlanProfileResponse> {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(DailyPlanProfileRequest.self)

        let classJSON = try Self.encode(body.classBlocks)
        let workJSON = try Self.encode(body.workBlocks)

        if let existing = try await UserDailyPlanProfile.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first()
        {
            existing.wakeTimeMinutes = body.wakeTimeMinutes
            existing.sleepTargetHours = body.sleepTargetHours
            existing.chronotype = body.chronotype
            existing.trainingTimePreference = body.trainingTimePreference
            existing.eatingWindowPreset = body.eatingWindowPreset
            existing.eatingWindowStartMinutes = body.eatingWindowStartMinutes
            existing.eatingWindowEndMinutes = body.eatingWindowEndMinutes
            existing.breakfastSkipped = body.breakfastSkipped
            existing.postWorkoutMandatory = body.postWorkoutMandatory
            existing.studySessionLengthMinutes = body.studySessionLengthMinutes
            existing.weekendDifferential = body.weekendDifferential
            existing.termStartDate = body.termStartDate
            existing.termEndDate = body.termEndDate
            existing.classBlocksJSON = classJSON
            existing.workBlocksJSON = workJSON
            try await existing.save(on: req.db)
        } else {
            let row = UserDailyPlanProfile(
                userID: userID,
                wakeTimeMinutes: body.wakeTimeMinutes,
                sleepTargetHours: body.sleepTargetHours,
                chronotype: body.chronotype,
                trainingTimePreference: body.trainingTimePreference,
                eatingWindowPreset: body.eatingWindowPreset,
                eatingWindowStartMinutes: body.eatingWindowStartMinutes,
                eatingWindowEndMinutes: body.eatingWindowEndMinutes,
                breakfastSkipped: body.breakfastSkipped,
                postWorkoutMandatory: body.postWorkoutMandatory,
                studySessionLengthMinutes: body.studySessionLengthMinutes,
                weekendDifferential: body.weekendDifferential,
                termStartDate: body.termStartDate,
                termEndDate: body.termEndDate,
                classBlocksJSON: classJSON,
                workBlocksJSON: workJSON
            )
            try await row.create(on: req.db)
        }

        return Envelope(
            data: DailyPlanProfileResponse(updated: true),
            requestID: req.requestID
        )
    }

    // MARK: - GET /v1/user/daily-plan-profile

    @Sendable
    func getDailyPlanProfile(_ req: Request) async throws -> Envelope<DailyPlanProfileRequest> {
        let userID = try req.auth.requireUserID()
        guard
            let row = try await UserDailyPlanProfile.query(on: req.db)
                .filter(\.$user.$id == userID)
                .first()
        else {
            throw Abort(.notFound, reason: "No daily plan profile yet.")
        }
        let classBlocks = (try? JSONDecoder().decode([StoredClassBlock].self, from: Data(row.classBlocksJSON.utf8))) ?? []
        let workBlocks = (try? JSONDecoder().decode([StoredWorkBlock].self, from: Data(row.workBlocksJSON.utf8))) ?? []

        let response = DailyPlanProfileRequest(
            wakeTimeMinutes: row.wakeTimeMinutes,
            sleepTargetHours: row.sleepTargetHours,
            chronotype: row.chronotype,
            trainingTimePreference: row.trainingTimePreference,
            eatingWindowPreset: row.eatingWindowPreset,
            eatingWindowStartMinutes: row.eatingWindowStartMinutes,
            eatingWindowEndMinutes: row.eatingWindowEndMinutes,
            breakfastSkipped: row.breakfastSkipped,
            postWorkoutMandatory: row.postWorkoutMandatory,
            studySessionLengthMinutes: row.studySessionLengthMinutes,
            weekendDifferential: row.weekendDifferential,
            termStartDate: row.termStartDate,
            termEndDate: row.termEndDate,
            classBlocks: classBlocks,
            workBlocks: workBlocks
        )
        return Envelope(data: response, requestID: req.requestID)
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

// MARK: - DTOs

struct DailyPlanProfileRequest: Content {
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
    let classBlocks: [StoredClassBlock]
    let workBlocks: [StoredWorkBlock]
}

struct DailyPlanProfileResponse: Content {
    let updated: Bool
}

struct UserMeResponse: Content {
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
}

struct AIConsentRequest: Content {
    let consented: Bool
}

struct AIConsentResponse: Content {
    let aiConsentAt: Date?
}
