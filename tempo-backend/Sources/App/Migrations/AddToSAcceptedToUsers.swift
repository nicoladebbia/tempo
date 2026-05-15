import Fluent

// MARK: - Add tos_accepted_at to users
// Per LAUNCH_PUNCH_LIST.md §3.5 — GDPR + Apple compliance: every active
// user must have a recorded ToS acceptance timestamp. The ToSGate
// middleware refuses any non-auth, non-tos route with 451 (Unavailable
// for Legal Reasons) when this column is null.
//
// Nullable so existing prod users (created before this migration) aren't
// locked out — they will hit the ToS gate on their next request and
// accept in-app.

struct AddToSAcceptedToUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("tos_accepted_at", .datetime)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .deleteField("tos_accepted_at")
            .update()
    }
}
