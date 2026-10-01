import Fluent
import Vapor

// MARK: - Subscription states

//
// POST /v1/test/subscription {name, state, days?} → {state, pro, expires_at}
//
// Puts a test user's server-side subscription into one of the states the App
// Store webhook can leave it in, so every Pro gate (402s, Pro-only jobs) can
// be checked without a sandbox purchase. Dates follow the test clock, so
// `cancelled --days 2` + `time +3d` is "the subscription ran out".
// The app itself decides Pro from StoreKit on the device — this is the
// server's view only.

extension TestModeController {
    func bootSubscription(routes: RoutesBuilder) {
        routes.post("subscription", use: setSubscription)
    }

    enum SubscriptionState: String, Codable, CaseIterable {
        /// No subscription at all.
        case free
        /// Free trial (7 days unless `days`).
        case trial
        /// Paid, renewing (30 days unless `days`).
        case active
        /// Auto-renew turned off: still Pro until it runs out (3 days unless `days`).
        case cancelled
        /// Renewal failed, Apple's grace period: still Pro (6 days unless `days`).
        case grace
        /// Grace period over, Apple still retrying billing: not Pro.
        case billingRetry = "billing-retry"
        /// Ran out.
        case expired
        /// Refunded or revoked: not Pro, effective now.
        case refunded
    }

    struct SubscriptionRequest: Content {
        let name: String
        let state: String
        var days: Double?
    }

    struct SubscriptionResponse: Content {
        let name: String
        let state: String
        let pro: Bool
        let expiresAt: Date?
    }

    func setSubscription(_ req: Request) async throws -> SubscriptionResponse {
        _ = try Self.state(req)
        let body = try req.content.decode(SubscriptionRequest.self)
        guard let state = SubscriptionState(rawValue: body.state) else {
            let names = SubscriptionState.allCases.map(\.rawValue).joined(separator: ", ")
            throw Abort(.badRequest, reason: "Unknown state '\(body.state)'. States: \(names).")
        }
        guard let user = try await User.query(on: req.db)
            .filter(\.$appleUserID == Self.appleUserID(for: body.name)).first()
        else {
            throw Abort(.notFound, reason: "No test user '\(body.name)'.")
        }
        let userID = try user.requireID()
        let now = req.now
        let day: TimeInterval = 86400

        try await UserSubscription.query(on: req.db).filter(\.$user.$id == userID).delete()

        let row: (expires: Date, active: Bool, trial: Bool, product: String)?
        switch state {
        case .free:
            row = nil
        case .trial:
            row = (now + (body.days ?? 7) * day, true, true, "app.tempo.Tempo.pro.monthly")
        case .active:
            row = (now + (body.days ?? 30) * day, true, false, "app.tempo.Tempo.pro.monthly")
        case .cancelled:
            row = (now + (body.days ?? 3) * day, true, false, "app.tempo.Tempo.pro.monthly")
        case .grace:
            row = (now + (body.days ?? 6) * day, true, false, "app.tempo.Tempo.pro.monthly")
        case .billingRetry:
            row = (now - day, false, false, "app.tempo.Tempo.pro.monthly")
        case .expired:
            row = (now - (body.days ?? 1) * day, false, false, "app.tempo.Tempo.pro.monthly")
        case .refunded:
            row = (now, false, false, "app.tempo.Tempo.pro.monthly")
        }

        if let row {
            let sub = UserSubscription(
                userID: userID,
                productId: row.product,
                originalTransactionId: "test_\(UUID().uuidString.prefix(12))",
                purchaseDate: now - 30 * day,
                expirationDate: row.expires,
                isTrial: row.trial,
                environment: "sandbox"
            )
            // The init derives isActive from the real clock; the test clock decides here.
            sub.isActive = row.active
            try await sub.save(on: req.db)
        }
        await req.invalidateSubscriptionCache(userID: userID)

        let pro = try await ProEntitlement.isUserPro(userID: userID, on: req)
        return SubscriptionResponse(name: body.name, state: state.rawValue, pro: pro, expiresAt: row?.expires)
    }
}
