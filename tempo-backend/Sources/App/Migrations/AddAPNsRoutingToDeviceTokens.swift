import Fluent

// MARK: - AddAPNsRoutingToDeviceTokens

//
// Which app build a token belongs to. Xcode (debug) builds get sandbox tokens
// for `app.tempo.Tempo.dev`; App Store / TestFlight builds get production
// tokens for `app.tempo.Tempo`. A token pushed to the wrong APNs environment
// or topic is rejected (BadDeviceToken / DeviceTokenNotForTopic) — and that
// rejection deletes the token. Both columns are optional: rows from older app
// versions fall back to production + APNS_TOPIC until the app re-registers
// (it does on every launch).

struct AddAPNsRoutingToDeviceTokens: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("device_tokens")
            .field("bundle_id", .string)
            .field("apns_environment", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("device_tokens")
            .deleteField("bundle_id")
            .deleteField("apns_environment")
            .update()
    }
}
