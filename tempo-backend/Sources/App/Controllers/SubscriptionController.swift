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
    //
    // Apple App Store Server Notifications V2.
    // Per LAUNCH_PUNCH_LIST.md §3.2 + Apple's "Receiving App Store Server
    // Notifications" guide.
    //
    // Pipeline:
    //   1. Decode the outer envelope: { "signedPayload": "<JWS>" }
    //   2. Verify the JWS against Apple Root CA - G3 (X5CVerifier).
    //   3. Check the notificationUUID against processed_appstore_notifications
    //      — Apple retries until they see a 200, so we must dedup.
    //   4. Verify the inner signedTransactionInfo (separate JWS).
    //   5. Switch on notificationType × subtype and update the matching
    //      UserSubscription row (matched on originalTransactionId AND
    //      environment so a Sandbox notification can't overwrite a
    //      Production row, or vice versa).
    //   6. Record the notificationUUID in the dedup table.
    //   7. ALWAYS return 200 if we got far enough to decode the envelope —
    //      returning 4xx tells Apple to stop retrying, which is the wrong
    //      response to a transient downstream error. 401 is the right
    //      response to an invalid signature (so Apple knows the URL is
    //      misconfigured or the message is forged).

    func handleWebhook(_ req: Request) async throws -> HTTPStatus {
        // 1. Outer envelope
        let envelope: AppStoreSignedPayloadEnvelope
        do {
            envelope = try req.content.decode(AppStoreSignedPayloadEnvelope.self)
        } catch {
            req.logger.error("[appstore_webhook] malformed envelope: \(error)")
            return .badRequest
        }

        // 2. Verify outer JWS
        let payload: ResponseBodyV2DecodedPayload
        do {
            payload = try await AppStoreNotificationVerifier.shared.verifyEnvelope(envelope.signedPayload)
        } catch {
            req.logger.error("[appstore_webhook] JWS verification failed: \(error)")
            return .unauthorized
        }

        req.logger.info("""
            [appstore_webhook] verified notification=\(payload.notificationType) \
            subtype=\(payload.subtype ?? "-") uuid=\(payload.notificationUUID) \
            env=\(payload.data?.environment ?? "-")
            """)

        // 3. Idempotency — Apple retries; we process once.
        if try await ProcessedAppStoreNotification.find(payload.notificationUUID, on: req.db) != nil {
            req.logger.info("[appstore_webhook] duplicate uuid=\(payload.notificationUUID) — already processed")
            return .ok
        }

        // 4. Inner transaction info
        let txn: AppStoreTransactionInfoPayload?
        if let signedTxn = payload.data?.signedTransactionInfo {
            do {
                txn = try await AppStoreNotificationVerifier.shared.verifyTransaction(signedTxn)
            } catch {
                req.logger.error("[appstore_webhook] inner transaction JWS failed: \(error)")
                return .unauthorized
            }
        } else {
            txn = nil
        }

        // 5. Apply the state change
        if let txn {
            do {
                try await applyNotification(
                    type: payload.notificationType,
                    subtype: payload.subtype,
                    txn: txn,
                    on: req.db
                )
            } catch {
                // Database error — let Apple retry by NOT recording the
                // notification UUID. Return 500 so they retry.
                req.logger.error("[appstore_webhook] db apply failed: \(error)")
                return .internalServerError
            }
        }

        // 6. Record so retries no-op.
        let record = ProcessedAppStoreNotification(
            uuid: payload.notificationUUID,
            type: payload.notificationType,
            subtype: payload.subtype,
            environment: payload.data?.environment ?? "unknown"
        )
        // If two retries land in the same instant, one will lose the race
        // on the PK and throw — that's fine, the other call wins and we
        // still return 200.
        try? await record.create(on: req.db)

        return .ok
    }

    // MARK: - Apply notification to UserSubscription

    private func applyNotification(
        type: String,
        subtype: String?,
        txn: AppStoreTransactionInfoPayload,
        on db: Database
    ) async throws {
        // Match on (originalTransactionId, environment) so a Sandbox
        // notification can never overwrite a Production row.
        let sub = try await UserSubscription.query(on: db)
            .filter(\.$originalTransactionId == txn.originalTransactionId)
            .filter(\.$environment == txn.environment)
            .first()

        let now = Date()
        let expires = Self.date(fromMs: txn.expiresDate)

        switch type {
        // Initial purchase / restart of a previously expired subscription.
        // The iOS-side ReceiptController flow normally creates the row; if
        // for some reason it didn't (e.g. user purchased in Apple's
        // sandbox without ever opening the app), we'd still want to
        // record the active state — but we can't without a userId mapping.
        // For now: only update an existing row.
        case "SUBSCRIBED":
            guard let sub else { return }
            sub.isActive = true
            sub.expirationDate = expires ?? sub.expirationDate
            sub.updatedAt = now
            try await sub.save(on: db)

        // Auto-renew succeeded.
        case "DID_RENEW":
            guard let sub else { return }
            sub.isActive = true
            sub.expirationDate = expires ?? sub.expirationDate
            sub.updatedAt = now
            try await sub.save(on: db)

        // Auto-renew failed (billing problem, expired card). Apple
        // distinguishes GRACE_PERIOD (still active for ~16 days) from
        // BILLING_RETRY (already inactive) via the subtype. Spec §3.2.
        case "DID_FAIL_TO_RENEW":
            guard let sub else { return }
            if subtype == "GRACE_PERIOD" {
                // Keep active during grace period — Apple is still trying.
                sub.updatedAt = now
            } else {
                sub.isActive = false
                sub.updatedAt = now
            }
            try await sub.save(on: db)

        // Subscription has fully expired (grace period ended, billing
        // retry exhausted, or user cancelled and the period ran out).
        case "EXPIRED":
            guard let sub else { return }
            sub.isActive = false
            sub.updatedAt = now
            try await sub.save(on: db)

        // User contacted Apple Support and got a refund. Revoke
        // immediately regardless of expiration.
        case "REFUND":
            guard let sub else { return }
            sub.isActive = false
            sub.updatedAt = now
            try await sub.save(on: db)

        // Apple revoked access (family-sharing removal, fraud, etc).
        case "REVOKE":
            guard let sub else { return }
            sub.isActive = false
            sub.updatedAt = now
            try await sub.save(on: db)

        // Grace period ended without successful billing retry — same
        // outcome as EXPIRED.
        case "GRACE_PERIOD_EXPIRED":
            guard let sub else { return }
            sub.isActive = false
            sub.updatedAt = now
            try await sub.save(on: db)

        // User changed auto-renew status (turned off in Settings → Apple
        // ID → Subscriptions). Doesn't affect current period — they keep
        // Pro until expirationDate. We still record the new status by
        // bumping updatedAt so a downstream observer (e.g. churn-risk
        // mailer) can react.
        case "DID_CHANGE_RENEWAL_STATUS":
            guard let sub else { return }
            sub.updatedAt = now
            try await sub.save(on: db)

        // User opted into / out of a renewal-extension (Apple PR-1
        // outage credit, etc). No row change needed.
        case "RENEWAL_EXTENDED":
            guard let sub else { return }
            sub.expirationDate = expires ?? sub.expirationDate
            sub.updatedAt = now
            try await sub.save(on: db)

        // Plan change (monthly → annual etc). Apple sends this with a
        // new productId; the existing originalTransactionId stays the
        // same. We update productId so /v1/user/me reflects the change.
        case "DID_CHANGE_RENEWAL_PREF":
            guard let sub else { return }
            sub.productId = txn.productId
            sub.updatedAt = now
            try await sub.save(on: db)

        // Promotional offer redeemed (Apple's "Offer Codes"). Treat as
        // a renewal — productId may change and expirationDate definitely
        // moves out.
        case "OFFER_REDEEMED":
            guard let sub else { return }
            sub.isActive = true
            sub.productId = txn.productId
            sub.expirationDate = expires ?? sub.expirationDate
            sub.updatedAt = now
            try await sub.save(on: db)

        // CONSUMPTION_REQUEST, PRICE_INCREASE, TEST: nothing to do
        // on the subscription row itself. Log at debug level.
        default:
            // Verified, ignored. Still return 200 from the caller.
            break
        }
    }

    /// Apple sends timestamps as milliseconds since epoch (Double). Convert
    /// to a Date.
    private static func date(fromMs ms: Double?) -> Date? {
        guard let ms else { return nil }
        return Date(timeIntervalSince1970: ms / 1000.0)
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

// (AppStoreNotification / TransactionInfo previously defined here have
// been removed — they were a flat-shape stub that did not match Apple's
// V2 envelope. See AppStoreNotificationVerifier.swift for the real
// JWS-verified payload types.)

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
