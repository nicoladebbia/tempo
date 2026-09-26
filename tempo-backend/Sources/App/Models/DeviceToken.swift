import Fluent
import Vapor

// MARK: - Device Token Model
// Per BUILD_PLAN step 12.1 — Stores APNs device tokens for push notifications.
// Per ADR-019 — Direct APNs, no third-party push service.

final class DeviceToken: Model, Content, @unchecked Sendable {
    static let schema = "device_tokens"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "user_id")
    var userID: String

    @Field(key: "token")
    var token: String

    @Field(key: "device_id")
    var deviceID: String

    @OptionalField(key: "device_name")
    var deviceName: String?

    @Field(key: "platform")
    var platform: String

    @OptionalField(key: "app_version")
    var appVersion: String?

    /// The app build's bundle ID — the APNs topic for this token.
    @OptionalField(key: "bundle_id")
    var bundleID: String?

    /// "sandbox" (Xcode builds) or "production" (TestFlight / App Store).
    @OptionalField(key: "apns_environment")
    var apnsEnvironment: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    // ── Initializers ───────────────────────────

    init() {}

    init(
        userID: String,
        token: String,
        deviceID: String,
        deviceName: String? = nil,
        platform: String = "ios",
        appVersion: String? = nil,
        bundleID: String? = nil,
        apnsEnvironment: String? = nil
    ) {
        self.id = "dt_" + UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(20)
            .description
        self.userID = userID
        self.token = token
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platform = platform
        self.appVersion = appVersion
        self.bundleID = bundleID
        self.apnsEnvironment = apnsEnvironment
    }
}
