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
}

// MARK: - DTOs

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
