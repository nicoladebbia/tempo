import Fluent
import Vapor

// MARK: - ProcessedAppStoreNotification
//
// Idempotency record for App Store Server Notifications V2. Existence of a
// row means "we already processed this notification — drop the retry."
//
// Per LAUNCH_PUNCH_LIST.md §3.2.

final class ProcessedAppStoreNotification: Model, @unchecked Sendable {
    static let schema = "processed_appstore_notifications"

    @ID(custom: "notification_uuid", generatedBy: .user)
    var id: String?

    @Field(key: "notification_type")
    var notificationType: String

    @OptionalField(key: "subtype")
    var subtype: String?

    @Field(key: "environment")
    var environment: String

    @Field(key: "received_at")
    var receivedAt: Date

    init() {}

    init(uuid: String, type: String, subtype: String?, environment: String) {
        self.id = uuid
        self.notificationType = type
        self.subtype = subtype
        self.environment = environment
        self.receivedAt = Date()
    }
}
