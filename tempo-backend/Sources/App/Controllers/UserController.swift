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
        routes.delete("me", use: deleteMe)
        routes.post("ai-consent", use: setAIConsent)
        // Per LAUNCH_PUNCH_LIST.md §3.5 — ToS acceptance.
        routes.post("accept-tos", use: acceptToS)
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
            aiConsentAt: user.aiConsentAt,
            tosAcceptedAt: user.tosAcceptedAt
        )
        return Envelope(data: response, requestID: req.requestID)
    }

    // MARK: - DELETE /v1/user/me
    //
    // Apple-required since 2022 (App Store Review Guideline 5.1.1(v)): users
    // must be able to initiate account deletion in-app. Also satisfies GDPR
    // Article 17 (right to erasure).
    //
    // Behavior:
    //   1. Mark active subscription rows inactive (Apple-side cancellation
    //      happens via the user's Apple ID settings; we just stop honoring
    //      Pro locally and unsubscribe from future renewals via the receipt
    //      webhook).
    //   2. Hard-delete all owned per-user data so the user disappears from
    //      friends' leaderboards, friend requests, etc. immediately. All FKs
    //      have ON DELETE CASCADE — but we wipe explicitly because the User
    //      row itself is soft-deleted (30-day recovery window per
    //      User.isRecoverable), and we don't want stale recovery/XP data
    //      hanging on the cascade fence.
    //   3. Wipe AI cache rows whose key embeds this user ID.
    //   4. Revoke every refresh token (cuts all device sessions).
    //   5. Soft-delete the User row: zero PII, set deleted_at.
    //
    // Idempotent: calling twice on the same user is a no-op the second time.

    @Sendable
    func deleteMe(_ req: Request) async throws -> Envelope<AccountDeletionResponse> {
        let userID = try req.auth.requireUserID()

        guard let user = try await User.find(userID, on: req.db) else {
            // Already gone — treat as success for idempotency.
            return Envelope(
                data: AccountDeletionResponse(deletedAt: Date()),
                requestID: req.requestID
            )
        }

        if user.deletedAt != nil {
            // Already soft-deleted; return the original timestamp.
            return Envelope(
                data: AccountDeletionResponse(deletedAt: user.deletedAt!),
                requestID: req.requestID
            )
        }

        let now = Date()

        try await req.db.transaction { db in
            // 1. Subscriptions — mark inactive (don't delete; receipts are
            //    immutable for audit). Apple-side cancel is user-initiated
            //    via their Apple ID; we just stop granting Pro here.
            try await UserSubscription.query(on: db)
                .filter(\.$user.$id == userID)
                .set(\.$isActive, to: false)
                .update()

            // 2. Owned per-user data. Cascades would handle these if we
            //    hard-deleted the User row, but soft delete preserves the
            //    User row for the recovery window, so we wipe explicitly.
            try await RefreshToken.query(on: db).filter(\.$user.$id == userID).delete()
            try await DeviceToken.query(on: db).filter(\.$userID == userID).delete()
            try await Friendship.query(on: db)
                .group(.or) { or in
                    or.filter(\.$userAID == userID)
                    or.filter(\.$userBID == userID)
                }
                .delete()
            try await FriendRequest.query(on: db)
                .group(.or) { or in
                    or.filter(\.$fromUserID == userID)
                    or.filter(\.$toUserID == userID)
                }
                .delete()
            try await WhoopIntegration.query(on: db).filter(\.$user.$id == userID).delete()
            try await WhoopRecovery.query(on: db).filter(\.$user.$id == userID).delete()
            try await WhoopSleep.query(on: db).filter(\.$user.$id == userID).delete()
            try await WhoopCycle.query(on: db).filter(\.$user.$id == userID).delete()
            try await WhoopWorkout.query(on: db).filter(\.$user.$id == userID).delete()
            try await XPEvent.query(on: db).filter(\.$user.$id == userID).delete()
            try await UserAchievement.query(on: db).filter(\.$userID == userID).delete()
            try await ChallengeMember.query(on: db).filter(\.$userID == userID).delete()
            try await Challenge.query(on: db).filter(\.$creatorID == userID).delete()
            try await UserDailyPlanProfile.query(on: db).filter(\.$user.$id == userID).delete()

            // 3. AI cache rows. Postgres-backed entries embed the user ID
            //    inside cache_key (see AICacheKey.* in AICache.swift). Redis
            //    entries fall off their natural TTLs (max 30d for study
            //    schedules), so we don't fan out a SCAN here.
            try await CachedAIResponse.query(on: db)
                .filter(\.$cacheKey ~~ ":\(userID):")
                .delete()

            // 4. Soft-delete the User row. Keep the row for the 30-day
            //    recovery window (User.isRecoverable) but null out anything
            //    that identifies the user. apple_user_id stays so a re-sign-
            //    in within 30 days can restore; after 30d a maintenance job
            //    should hard-delete (out of scope for this commit).
            user.deletedAt = now
            user.displayName = ""
            user.username = "deleted_\(userID.suffix(8))"
            user.bio = nil
            user.avatarURL = nil
            user.aiConsentAt = nil
            user.tosAcceptedAt = nil
            user.lastActiveAt = nil
            try await user.save(on: db)
        }

        // 5. Bust the SubscriptionMiddleware cache so any in-flight requests
        //    don't see Pro for the next 5 minutes.
        await req.invalidateSubscriptionCache(userID: userID)

        return Envelope(
            data: AccountDeletionResponse(deletedAt: now),
            requestID: req.requestID
        )
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

    // MARK: - POST /v1/user/accept-tos
    //
    // Records that the authenticated user accepted the Terms of Service +
    // Privacy Policy. Idempotent — re-accepting does not overwrite the
    // existing timestamp (audit trail). Per LAUNCH_PUNCH_LIST.md §3.5.

    @Sendable
    func acceptToS(_ req: Request) async throws -> Envelope<AcceptToSResponse> {
        let userID = try req.auth.requireUserID()
        _ = try? req.content.decode(AcceptToSRequest.self) // optional; not yet persisted

        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.notFound, reason: "User not found.")
        }

        if user.tosAcceptedAt == nil {
            user.tosAcceptedAt = Date()
            try await user.save(on: req.db)
        }

        return Envelope(
            data: AcceptToSResponse(tosAcceptedAt: user.tosAcceptedAt ?? Date()),
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
    let tosAcceptedAt: Date?
}

struct AcceptToSRequest: Content {
    /// SHA-256 (or any stable hash) of the ToS+PrivacyPolicy text the user
    /// accepted. Optional in v1 — preserved for future audit when we want
    /// to know which version of the docs was signed off. Per
    /// LAUNCH_PUNCH_LIST.md §3.5.
    let documentVersion: String?
}

struct AcceptToSResponse: Content {
    let tosAcceptedAt: Date
}

struct AIConsentRequest: Content {
    let consented: Bool
}

struct AIConsentResponse: Content {
    let aiConsentAt: Date?
}

struct AccountDeletionResponse: Content {
    let deletedAt: Date
}
