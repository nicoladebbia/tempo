import Fluent
import SQLKit

// MARK: - Create User Subscriptions Migration
//
// Per BUILD_PLAN Step 20.1 + INTELLIGENCE_REMEDIATION_PLAN.md §4.
// Backs the `UserSubscription` model declared in SubscriptionController.swift.
// Used by SubscriptionMiddleware to determine Pro tier on every AI route.
//
// FK note: `users.id` is a String (custom-keyed via @ID(custom:generatedBy:.user)
// in User.swift), so user_id here is also .string.

struct CreateUserSubscriptions: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("user_subscriptions")
            .field("id", .uuid, .identifier(auto: false))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("product_id", .string, .required)
            .field("original_transaction_id", .string, .required)
            .field("purchase_date", .datetime, .required)
            .field("expiration_date", .datetime, .required)
            .field("is_trial", .bool, .required, .sql(.default(false)))
            .field("is_active", .bool, .required, .sql(.default(false)))
            .field("environment", .string, .required, .sql(.default("production")))
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            // A single Apple transaction must not be recorded twice for the
            // same user. Apple's `originalTransactionId` is globally stable
            // for a subscription's lifetime — including renewals.
            .unique(on: "user_id", "original_transaction_id")
            .create()

        guard let sql = database as? SQLDatabase else { return }

        // SubscriptionMiddleware hot path:
        //   WHERE user_id = $1 AND is_active = true AND expiration_date > now()
        // Covered by this partial index.
        try await sql.raw("""
            CREATE INDEX idx_user_subscriptions_active
            ON user_subscriptions(user_id, expiration_date)
            WHERE is_active = TRUE
            """).run()

        // Webhook handlers look up by original_transaction_id (no user_id
        // available in the Apple notification payload).
        try await sql.raw("""
            CREATE INDEX idx_user_subscriptions_original_txn
            ON user_subscriptions(original_transaction_id)
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("user_subscriptions").delete()
    }
}
