import Vapor
import Fluent

// MARK: - Subscription Controller
// Per BUILD_PLAN Step 20.1 — Server-side receipt validation + App Store Server Notifications v2.
// Per APP_STORE_COMPLIANCE.md Section 5.1 — Use App Store Server API v2 (not deprecated /verifyReceipt).

struct SubscriptionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // Protected routes (JWT required)
        let protected = routes.grouped(JWTAuthMiddleware())
        protected.post("verify", use: verifyReceipt)
        protected.get("status", use: subscriptionStatus)

        // Apple webhook (no JWT — Apple calls this directly)
        routes.post("webhook", use: handleWebhook)
    }

    // MARK: - POST /v1/subscription/verify
    // Verifies a StoreKit 2 transaction and records it server-side.

    func verifyReceipt(_ req: Request) async throws -> SubscriptionStatusResponse {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(VerifyReceiptRequest.self)

        // In production: verify JWS signed transaction with Apple's public key
        // For now, trust the client-provided transaction data and record it

        // Upsert subscription record
        if let existing = try await UserSubscription.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$originalTransactionId == body.originalTransactionId)
            .first() {
            existing.expirationDate = body.expirationDate
            existing.isActive = body.expirationDate > Date()
            existing.isTrial = body.isTrial
            existing.updatedAt = Date()
            try await existing.save(on: req.db)
        } else {
            let subscription = UserSubscription(
                userID: userID,
                productId: body.productId,
                originalTransactionId: body.originalTransactionId,
                purchaseDate: body.purchaseDate,
                expirationDate: body.expirationDate,
                isTrial: body.isTrial,
                environment: body.environment
            )
            try await subscription.save(on: req.db)
        }

        // Invalidate the SubscriptionMiddleware cache so the next AI request
        // sees the new state immediately. Per INTELLIGENCE_REMEDIATION_PLAN.md §4.
        await req.invalidateSubscriptionCache(userID: userID)

        return SubscriptionStatusResponse(
            isActive: body.expirationDate > Date(),
            productId: body.productId,
            expirationDate: body.expirationDate,
            isTrial: body.isTrial
        )
    }

    // MARK: - GET /v1/subscription/status

    func subscriptionStatus(_ req: Request) async throws -> SubscriptionStatusResponse {
        let userID = try req.auth.requireUserID()

        guard let subscription = try await UserSubscription.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$isActive == true)
            .sort(\.$expirationDate, .descending)
            .first() else {
            return SubscriptionStatusResponse(
                isActive: false,
                productId: nil,
                expirationDate: nil,
                isTrial: false
            )
        }

        let isActive = subscription.expirationDate > Date()
        if !isActive {
            subscription.isActive = false
            try await subscription.save(on: req.db)
        }

        return SubscriptionStatusResponse(
            isActive: isActive,
            productId: subscription.productId,
            expirationDate: subscription.expirationDate,
            isTrial: subscription.isTrial
        )
    }

    // MARK: - POST /v1/subscription/webhook
    // Per APP_STORE_COMPLIANCE.md — App Store Server Notifications v2.

    func handleWebhook(_ req: Request) async throws -> HTTPStatus {
        // In production: verify the JWS signature of the notification payload
        // using Apple's root certificate chain
        let notification = try req.content.decode(AppStoreNotification.self)

        req.logger.info("App Store notification: \(notification.notificationType)")

        switch notification.notificationType {
        case "DID_RENEW":
            if let txn = notification.transactionInfo {
                try await activateSubscription(txn, on: req.db)
            }

        case "DID_FAIL_TO_RENEW":
            if let txn = notification.transactionInfo {
                try await markGracePeriod(txn, on: req.db)
            }

        case "EXPIRED":
            if let txn = notification.transactionInfo {
                try await expireSubscription(txn, on: req.db)
            }

        case "REFUND":
            if let txn = notification.transactionInfo {
                try await revokeSubscription(txn, on: req.db)
            }

        default:
            req.logger.info("Unhandled notification type: \(notification.notificationType)")
        }

        return .ok
    }

    // MARK: - Helpers

    private func activateSubscription(_ txn: TransactionInfo, on db: Database) async throws {
        guard let sub = try await UserSubscription.query(on: db)
            .filter(\.$originalTransactionId == txn.originalTransactionId)
            .first() else { return }

        sub.isActive = true
        sub.expirationDate = txn.expiresDate ?? sub.expirationDate
        sub.updatedAt = Date()
        try await sub.save(on: db)
    }

    private func markGracePeriod(_ txn: TransactionInfo, on db: Database) async throws {
        guard let sub = try await UserSubscription.query(on: db)
            .filter(\.$originalTransactionId == txn.originalTransactionId)
            .first() else { return }

        // Keep active during grace period
        sub.updatedAt = Date()
        try await sub.save(on: db)
    }

    private func expireSubscription(_ txn: TransactionInfo, on db: Database) async throws {
        guard let sub = try await UserSubscription.query(on: db)
            .filter(\.$originalTransactionId == txn.originalTransactionId)
            .first() else { return }

        sub.isActive = false
        sub.updatedAt = Date()
        try await sub.save(on: db)
    }

    private func revokeSubscription(_ txn: TransactionInfo, on db: Database) async throws {
        guard let sub = try await UserSubscription.query(on: db)
            .filter(\.$originalTransactionId == txn.originalTransactionId)
            .first() else { return }

        sub.isActive = false
        sub.updatedAt = Date()
        try await sub.save(on: db)
    }
}

// MARK: - Request / Response Models

struct VerifyReceiptRequest: Content {
    let productId: String
    let originalTransactionId: String
    let purchaseDate: Date
    let expirationDate: Date
    let isTrial: Bool
    let environment: String
}

struct SubscriptionStatusResponse: Content {
    let isActive: Bool
    let productId: String?
    let expirationDate: Date?
    let isTrial: Bool
}

struct AppStoreNotification: Content {
    let notificationType: String
    let subtype: String?
    let transactionInfo: TransactionInfo?
}

struct TransactionInfo: Content {
    let originalTransactionId: String
    let expiresDate: Date?
}

// MARK: - UserSubscription Model (Fluent)
// Per STATE_MACHINES.md Section 15 — Backend persistence.

import struct Foundation.UUID
import struct Foundation.Date

final class UserSubscription: Model, Content, @unchecked Sendable {

    static let schema = "user_subscriptions"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "product_id")
    var productId: String

    @Field(key: "original_transaction_id")
    var originalTransactionId: String

    @Field(key: "purchase_date")
    var purchaseDate: Date

    @Field(key: "expiration_date")
    var expirationDate: Date

    @Field(key: "is_trial")
    var isTrial: Bool

    @Field(key: "is_active")
    var isActive: Bool

    @Field(key: "environment")
    var environment: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: String,
        productId: String,
        originalTransactionId: String,
        purchaseDate: Date,
        expirationDate: Date,
        isTrial: Bool = false,
        environment: String = "production"
    ) {
        self.id = id
        self.$user.id = userID
        self.productId = productId
        self.originalTransactionId = originalTransactionId
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.isTrial = isTrial
        self.isActive = expirationDate > Date()
        self.environment = environment
    }
}
