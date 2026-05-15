import Fluent

// MARK: - Create processed_appstore_notifications
//
// Per LAUNCH_PUNCH_LIST.md §3.2 — Apple App Store Server Notifications V2.
// Apple retries notifications until they receive a 200. Without dedup we'd
// process the same renewal twice and overwrite expirationDate with stale
// data, or process a refund twice and double-revoke.
//
// `notification_uuid` is the unique identifier Apple stamps on every
// notification. Storing it as the primary key lets us race-safely INSERT
// and let the unique violation tell us "already handled."

struct CreateProcessedAppStoreNotifications: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("processed_appstore_notifications")
            .field("notification_uuid", .string, .identifier(auto: false))
            .field("notification_type", .string, .required)
            .field("subtype", .string)
            .field("environment", .string, .required)
            .field("received_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("processed_appstore_notifications").delete()
    }
}
