@testable import App
import Fluent
import Foundation
import Redis
import Testing
import Vapor
import XCTVapor

// MARK: - App Store webhook → Pro cache

//
// `ProEntitlement.isUserPro` caches the answer in Redis for 300 s. The webhook
// used to change UserSubscription without clearing it, so a refund or expiry
// kept granting Pro for up to five minutes.

@Suite("Subscription webhook cache", .serialized)
struct SubscriptionWebhookCacheTests {
    private func withApp(_ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await app.asyncBoot()
            try await body(app)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func txn(_ original: String, expires: Date) -> AppStoreTransactionInfoPayload {
        AppStoreTransactionInfoPayload(
            originalTransactionId: original,
            transactionId: original,
            productId: "tempo.pro.monthly",
            purchaseDate: nil,
            originalPurchaseDate: nil,
            expiresDate: expires.timeIntervalSince1970 * 1000,
            type: "Auto-Renewable Subscription",
            inAppOwnershipType: "PURCHASED",
            environment: "Sandbox",
            revocationDate: nil,
            revocationReason: nil
        )
    }

    @Test(arguments: ["REFUND", "EXPIRED", "REVOKE"])
    func terminalNotificationEndsProImmediately(type: String) async throws {
        try await withApp { app in
            let suffix = UUID().uuidString.prefix(12)
            let user = User(appleUserID: "apple_\(suffix)", username: "user_\(suffix)", displayName: "T")
            try await user.save(on: app.db)
            let uid = try user.requireID()
            let original = "orig_\(suffix)"
            let future = Date().addingTimeInterval(86400 * 30)
            try await UserSubscription(
                userID: uid, productId: "tempo.pro.monthly", originalTransactionId: original,
                purchaseDate: Date(), expirationDate: future, environment: "Sandbox"
            ).save(on: app.db)

            let req = Request(application: app, on: app.eventLoopGroup.next())
            #expect(try await ProEntitlement.isUserPro(userID: uid, on: req) == true) // primes the cache

            try await SubscriptionController().applyNotification(
                type: type, subtype: nil, txn: txn(original, expires: future), on: req
            )
            #expect(try await ProEntitlement.isUserPro(userID: uid, on: req) == false, "\(type) left a stale Pro cache")
        }
    }

    @Test func renewalGrantsProImmediately() async throws {
        try await withApp { app in
            let suffix = UUID().uuidString.prefix(12)
            let user = User(appleUserID: "apple_\(suffix)", username: "user_\(suffix)", displayName: "T")
            try await user.save(on: app.db)
            let uid = try user.requireID()
            let original = "orig_\(suffix)"
            let past = Date().addingTimeInterval(-86400)
            try await UserSubscription(
                userID: uid, productId: "tempo.pro.monthly", originalTransactionId: original,
                purchaseDate: past, expirationDate: past, environment: "Sandbox"
            ).save(on: app.db)

            let req = Request(application: app, on: app.eventLoopGroup.next())
            #expect(try await ProEntitlement.isUserPro(userID: uid, on: req) == false) // caches "0"

            try await SubscriptionController().applyNotification(
                type: "DID_RENEW", subtype: nil,
                txn: txn(original, expires: Date().addingTimeInterval(86400 * 30)), on: req
            )
            #expect(try await ProEntitlement.isUserPro(userID: uid, on: req) == true)
        }
    }
}
