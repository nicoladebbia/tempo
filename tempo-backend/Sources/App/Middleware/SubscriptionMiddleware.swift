import Fluent
import Redis
import Vapor

// MARK: - SubscriptionMiddleware

//
// Gates Pro-only routes (AI insights, nutrition AI proxy, receipt structuring).
// Must run AFTER JWTAuthMiddleware — relies on the authenticated user being in
// request storage.
//
// Per AI_INTELLIGENCE_ENGINE.md + MONETIZATION_STRATEGY.md §3 + INTELLIGENCE_REMEDIATION_PLAN.md §4:
//   - Free users get 402 with { error: "subscription_required" } on every gated route.
//   - Pro users without AI consent get 402 with { error: "ai_consent_required" }.
//   - Pro users with consent pass through to the route handler.
//
// Subscription status is cached in Redis for 5 minutes (cheap, scales to many
// concurrent requests per user). Cache is invalidated by SubscriptionController
// on verify/webhook events.

struct SubscriptionMiddleware: AsyncMiddleware {
    private static let cacheTTLSeconds = 300

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let userID = try request.auth.requireUserID()

        // 0. Allowlist bypass. Comma-separated Apple user IDs in the
        // PRO_ALLOWLIST env var get full access with no subscription and no
        // AI-consent gate — used to grant the operator(s) their own access
        // without a purchase. Empty/unset env var = allowlist disabled.
        if try await ProEntitlement.isAllowlisted(userID: userID, on: request) {
            return try await next.respond(to: request)
        }

        // 1. Resolve subscription (Redis cache → Postgres fallback).
        let isPro = try await ProEntitlement.isUserPro(userID: userID, on: request)
        guard isPro else {
            throw subscriptionRequired
        }

        // 2. Enforce AI consent (AI_INTELLIGENCE_ENGINE.md §11.3).
        let hasConsent = try await userHasAIConsent(userID: userID, on: request)
        guard hasConsent else {
            throw aiConsentRequired
        }

        return try await next.respond(to: request)
    }

    // MARK: - AI consent lookup

    private func userHasAIConsent(userID: String, on req: Request) async throws -> Bool {
        let cacheKey = RedisKey("ai_consent:\(userID)")
        if let cached = try await req.redis.get(cacheKey, as: String.self).get() {
            return cached == "1"
        }

        guard let user = try await User.find(userID, on: req.db) else {
            return false
        }
        let hasConsent = user.aiConsentAt != nil

        try await req.redis.setex(
            cacheKey,
            to: hasConsent ? "1" : "0",
            expirationInSeconds: Self.cacheTTLSeconds
        ).get()

        return hasConsent
    }

    // MARK: - Structured errors

    private var subscriptionRequired: Abort {
        Abort(
            .paymentRequired,
            headers: [:],
            reason: "Pro subscription required for AI features.",
            identifier: "subscription_required"
        )
    }

    private var aiConsentRequired: Abort {
        Abort(
            .paymentRequired,
            headers: [:],
            reason: "AI consent is required before using AI features.",
            identifier: "ai_consent_required"
        )
    }
}

// MARK: - Cache invalidation helper

//
// Called from SubscriptionController.verify, the webhook handler, and
// UserController.aiConsent so the next AI request sees the change instantly
// instead of waiting up to 5 minutes for the cache to expire.

extension Request {
    func invalidateSubscriptionCache(userID: String) async {
        _ = try? await redis.delete(RedisKey("sub:active:\(userID)")).get()
        _ = try? await redis.delete(RedisKey("ai_consent:\(userID)")).get()
    }
}
